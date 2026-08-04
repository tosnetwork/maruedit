import Foundation

public enum TextFileLoaderError: Error, Sendable, Equatable {
    case fileNotReadable(path: String)
    case couldNotDecode(path: String, diagnostics: [String])
    case couldNotDecodeWithEncoding(path: String, encoding: TextEncoding)
}

extension TextFileLoaderError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .fileNotReadable(let path):
            return "Could not read the file at \(path)."
        case .couldNotDecode(let path, let diagnostics):
            let detail = diagnostics.first ?? "No candidate encoding matched."
            return "Could not determine the text encoding of \(path). \(detail)"
        case .couldNotDecodeWithEncoding(let path, let encoding):
            return "Could not decode \(path) as \(encoding.displayName)."
        }
    }
}

public struct LoadedText: Sendable, Equatable {
    public let content: String
    public let encoding: TextEncoding
    public let hasByteOrderMark: Bool
    public let confidence: DetectionConfidence
    public let fileSize: Int64
    public let modificationDate: Date?
    public let posixPermissions: Int
    public let fileIdentity: FileIdentity?
    public let diagnostics: [EncodingDiagnostic]
}

/// Reads a file's bytes and decodes them via `EncodingDetector`, also
/// capturing the file metadata (size, permissions, modification date,
/// identity) that later safe-save and external-modification-detection
/// work (M2-05/M2-06) will need.
///
/// This is a plain, side-effect-free function safe to call from any
/// thread or queue. It performs synchronous, potentially-blocking disk
/// I/O — callers must dispatch it off the main thread/actor themselves
/// (ROADMAP.md M2-01: "perform file reads away from the main actor"). It
/// is deliberately not `async` itself: nothing in this codebase uses
/// Swift concurrency yet (see M1-03's `CommandDefinition` for the same
/// tradeoff, recorded there).
public enum TextFileLoader {
    /// Loads `url`, auto-detecting its encoding.
    public static func load(contentsOf url: URL) throws -> LoadedText {
        let (path, data) = try readData(at: url)

        let result = EncodingDetector.detect(data)
        guard result.confidence != .failed else {
            throw TextFileLoaderError.couldNotDecode(
                path: path,
                diagnostics: result.diagnostics.map { $0.message }
            )
        }

        return loadedText(
            content: result.content,
            encoding: result.encoding,
            hasByteOrderMark: result.hasByteOrderMark,
            confidence: result.confidence,
            diagnostics: result.diagnostics,
            data: data,
            url: url
        )
    }

    /// Loads `url` using a specific, user-chosen encoding, bypassing
    /// auto-detection entirely (ROADMAP.md M2-02, "Reopen with
    /// Encoding…"). Still verifies the bytes actually decode — refuses to
    /// return garbled content even when the user's choice was wrong —
    /// but does not require a round-trip match: an explicit user choice
    /// is trusted more than an automatic guess, so a lossy-but-decodable
    /// result is returned with `.low` confidence rather than rejected.
    public static func load(contentsOf url: URL, forcing encoding: TextEncoding) throws -> LoadedText {
        let (path, data) = try readData(at: url)

        guard let foundationEncoding = encoding.foundationEncoding,
              let content = String(data: data, encoding: foundationEncoding)
        else {
            throw TextFileLoaderError.couldNotDecodeWithEncoding(path: path, encoding: encoding)
        }

        let roundTrips = content.data(using: foundationEncoding) == data
        return loadedText(
            content: content,
            encoding: encoding,
            hasByteOrderMark: false,
            confidence: roundTrips ? .high : .low,
            diagnostics: roundTrips ? [] : [EncodingDiagnostic("Decoded as \(encoding.displayName), but re-encoding does not reproduce the original bytes exactly.")],
            data: data,
            url: url
        )
    }

    private static func readData(at url: URL) throws -> (path: String, data: Data) {
        let path = url.path
        guard let data = FileManager.default.contents(atPath: path) else {
            throw TextFileLoaderError.fileNotReadable(path: path)
        }
        return (path, data)
    }

    private static func loadedText(
        content: String,
        encoding: TextEncoding,
        hasByteOrderMark: Bool,
        confidence: DetectionConfidence,
        diagnostics: [EncodingDiagnostic],
        data: Data,
        url: URL
    ) -> LoadedText {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        let modificationDate = attributes?[.modificationDate] as? Date
        let permissions = (attributes?[.posixPermissions] as? NSNumber)?.intValue ?? 0

        return LoadedText(
            content: content,
            encoding: encoding,
            hasByteOrderMark: hasByteOrderMark,
            confidence: confidence,
            fileSize: Int64(data.count),
            modificationDate: modificationDate,
            posixPermissions: permissions,
            fileIdentity: FileIdentity.of(url),
            diagnostics: diagnostics
        )
    }
}
