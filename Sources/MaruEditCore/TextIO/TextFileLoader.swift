import Foundation

public enum TextFileLoaderError: Error, Sendable, Equatable {
    case fileNotReadable(path: String)
    case couldNotDecode(path: String, diagnostics: [String])
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
/// tradeoff, recorded there), and there is no caller yet to design the
/// async boundary around — `Document.open(url:)` still reads files with
/// a hardcoded `String(contentsOf:encoding:.utf8)` and is **not** wired
/// to this loader yet. That's intentional: wiring the read side alone,
/// without the corresponding write-side encoding preservation (M2-04's
/// Save Preflight, M2-05's TextFileSaver), would let MaruEdit silently
/// re-encode a Shift-JIS/EUC-JP file to UTF-8 the next time it's saved —
/// exactly the silent corruption ROADMAP.md section 1.2 commits against.
public enum TextFileLoader {
    public static func load(contentsOf url: URL) throws -> LoadedText {
        let path = url.path
        guard let data = FileManager.default.contents(atPath: path) else {
            throw TextFileLoaderError.fileNotReadable(path: path)
        }

        let result = EncodingDetector.detect(data)
        guard result.confidence != .failed else {
            throw TextFileLoaderError.couldNotDecode(
                path: path,
                diagnostics: result.diagnostics.map { $0.message }
            )
        }

        let attributes = try? FileManager.default.attributesOfItem(atPath: path)
        let modificationDate = attributes?[.modificationDate] as? Date
        let permissions = (attributes?[.posixPermissions] as? NSNumber)?.intValue ?? 0

        return LoadedText(
            content: result.content,
            encoding: result.encoding,
            hasByteOrderMark: result.hasByteOrderMark,
            confidence: result.confidence,
            fileSize: Int64(data.count),
            modificationDate: modificationDate,
            posixPermissions: permissions,
            fileIdentity: FileIdentity.of(url),
            diagnostics: result.diagnostics
        )
    }
}
