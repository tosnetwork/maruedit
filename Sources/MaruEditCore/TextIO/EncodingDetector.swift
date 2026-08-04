import Foundation

/// How sure `EncodingDetector` is about a result. `.failed` means it
/// deliberately did not guess — see `EncodingDetector.detect`.
public enum DetectionConfidence: Sendable, Equatable {
    case certain // a byte-order mark was present
    case high    // no BOM, but strict UTF-8 validation passed
    case low     // matched a legacy candidate only via round-trip validation
    case failed  // nothing decoded cleanly; content is empty, never a lossy guess
}

public struct EncodingDiagnostic: Sendable, Equatable {
    public let message: String
    public init(_ message: String) {
        self.message = message
    }
}

public struct EncodingDetectionResult: Sendable, Equatable {
    public let encoding: TextEncoding
    public let confidence: DetectionConfidence
    public let hasByteOrderMark: Bool
    public let content: String
    public let diagnostics: [EncodingDiagnostic]
}

/// Detects a text encoding and decodes bytes into a `String`, following
/// the pipeline in ROADMAP.md section 10.1: byte-order mark first, then
/// strict UTF-8, then legacy Japanese candidates — each accepted only if
/// it round-trips byte-for-byte (decode, then re-encode, then compare to
/// the original bytes). Never silently returns lossy content.
public enum EncodingDetector {
    private static let utf32LE: [UInt8] = [0xFF, 0xFE, 0x00, 0x00]
    private static let utf32BE: [UInt8] = [0x00, 0x00, 0xFE, 0xFF]
    private static let utf8BOM: [UInt8] = [0xEF, 0xBB, 0xBF]
    private static let utf16LEBOM: [UInt8] = [0xFF, 0xFE]
    private static let utf16BEBOM: [UInt8] = [0xFE, 0xFF]

    public static func detect(_ data: Data) -> EncodingDetectionResult {
        if data.isEmpty {
            return EncodingDetectionResult(
                encoding: .utf8, confidence: .certain, hasByteOrderMark: false, content: "", diagnostics: []
            )
        }

        if let bomResult = detectByBOM(data) {
            return bomResult
        }

        // ISO-2022-JP is checked before plain UTF-8: it's a 7-bit-safe
        // encoding built entirely from ASCII-range bytes plus ESC-based
        // mode-switch sequences, so it is *always* also technically valid
        // UTF-8 (every byte is in the ASCII range) — a plain UTF-8 check
        // would "successfully" decode it as garbled literal escape-code
        // text and never reach the legacy-candidate fallback below, which
        // only runs when UTF-8 decoding fails outright. The `ESC $`
        // sequence that opens every ISO-2022-JP double-byte mode is a
        // strong, specific signal (0x1B essentially never appears in
        // ordinary text) that this isn't actually plain UTF-8.
        if data.range(of: Data([0x1B, 0x24])) != nil,
           let decoded = String(data: data, encoding: .iso2022JP),
           let reencoded = decoded.data(using: .iso2022JP),
           reencoded == data {
            return EncodingDetectionResult(
                encoding: .iso2022JP,
                confidence: .high,
                hasByteOrderMark: false,
                content: decoded,
                diagnostics: [EncodingDiagnostic("Detected via ISO-2022-JP escape sequence, confirmed by round-trip.")]
            )
        }

        if let content = String(data: data, encoding: .utf8) {
            return EncodingDetectionResult(
                encoding: .utf8, confidence: .high, hasByteOrderMark: false, content: content, diagnostics: []
            )
        }

        for candidate in TextEncoding.initialCandidates where candidate != .iso2022JP {
            guard let foundationEncoding = candidate.foundationEncoding,
                  let decoded = String(data: data, encoding: foundationEncoding),
                  let reencoded = decoded.data(using: foundationEncoding),
                  reencoded == data
            else { continue }

            return EncodingDetectionResult(
                encoding: candidate,
                confidence: .low,
                hasByteOrderMark: false,
                content: decoded,
                diagnostics: [EncodingDiagnostic("Matched \(candidate.displayName) via round-trip validation; UTF-8 was not valid.")]
            )
        }

        return EncodingDetectionResult(
            encoding: .utf8,
            confidence: .failed,
            hasByteOrderMark: false,
            content: "",
            diagnostics: [EncodingDiagnostic("Could not decode with UTF-8 or any known legacy candidate.")]
        )
    }

    private static func detectByBOM(_ data: Data) -> EncodingDetectionResult? {
        let prefix = [UInt8](data.prefix(4))

        // Checked before the 2-byte UTF-16LE pattern, since UTF-32LE's
        // BOM (FF FE 00 00) starts with the same two bytes.
        if prefix.starts(with: utf32LE) || prefix.starts(with: utf32BE) {
            return EncodingDetectionResult(
                encoding: .utf8, confidence: .failed, hasByteOrderMark: true, content: "",
                diagnostics: [EncodingDiagnostic("UTF-32 byte-order mark detected; UTF-32 decoding is not supported yet.")]
            )
        }
        if prefix.starts(with: utf8BOM) {
            let body = data.dropFirst(3)
            guard let content = String(data: body, encoding: .utf8) else {
                return failedBOMResult(.utf8, "UTF-8 byte-order mark present but the body is not valid UTF-8.")
            }
            return EncodingDetectionResult(encoding: .utf8, confidence: .certain, hasByteOrderMark: true, content: content, diagnostics: [])
        }
        if prefix.starts(with: utf16LEBOM) {
            let body = data.dropFirst(2)
            guard let content = String(data: body, encoding: .utf16LittleEndian) else {
                return failedBOMResult(.utf16LittleEndian, "UTF-16LE byte-order mark present but the body did not decode.")
            }
            return EncodingDetectionResult(encoding: .utf16LittleEndian, confidence: .certain, hasByteOrderMark: true, content: content, diagnostics: [])
        }
        if prefix.starts(with: utf16BEBOM) {
            let body = data.dropFirst(2)
            guard let content = String(data: body, encoding: .utf16BigEndian) else {
                return failedBOMResult(.utf16BigEndian, "UTF-16BE byte-order mark present but the body did not decode.")
            }
            return EncodingDetectionResult(encoding: .utf16BigEndian, confidence: .certain, hasByteOrderMark: true, content: content, diagnostics: [])
        }
        return nil
    }

    private static func failedBOMResult(_ encoding: TextEncoding, _ message: String) -> EncodingDetectionResult {
        EncodingDetectionResult(
            encoding: encoding, confidence: .failed, hasByteOrderMark: true, content: "",
            diagnostics: [EncodingDiagnostic(message)]
        )
    }
}
