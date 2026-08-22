import Foundation

public enum TextFileLoaderError: Error, Sendable, Equatable {
    case fileNotReadable(path: String)
    case couldNotDecode(path: String, diagnostics: [String])
    case couldNotDecodeWithEncoding(path: String, encoding: TextEncoding)
    case invalidByteRange(path: String, offset: Int64, length: Int)
    case partialRangeSplitsCharacter(path: String, encoding: TextEncoding)
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
        case let .invalidByteRange(path, offset, length):
            return "The byte range \(offset)..<\(offset + Int64(length)) is outside \(path)."
        case .partialRangeSplitsCharacter(let path, let encoding):
            return "The selected byte range in \(path) splits a \(encoding.displayName) character. Adjust the start or length."
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
    /// Reads only the requested bytes. When encoding is omitted a bounded
    /// prefix is inspected; the full file is never materialized.
    public static func loadPartial(
        contentsOf url: URL, offset: Int64, length: Int,
        forcing requestedEncoding: TextEncoding? = nil
    ) throws -> (content: String, encoding: TextEncoding) {
        let path = url.path
        let fileSize = try LargeFilePolicy.fileSize(at: url)
        guard offset >= 0, length > 0, offset < fileSize,
              offset + Int64(length) <= fileSize else {
            throw TextFileLoaderError.invalidByteRange(path: path, offset: offset, length: length)
        }
        let handle: FileHandle
        do { handle = try FileHandle(forReadingFrom: url) }
        catch { throw TextFileLoaderError.fileNotReadable(path: path) }
        defer { try? handle.close() }

        let encoding: TextEncoding
        if let requestedEncoding {
            encoding = requestedEncoding
        } else {
            do {
                try handle.seek(toOffset: 0)
                let probe = try handle.read(upToCount: min(65_536, Int(fileSize))) ?? Data()
                let result = EncodingDetector.detect(probe)
                guard result.confidence != .failed else {
                    throw TextFileLoaderError.couldNotDecode(
                        path: path, diagnostics: result.diagnostics.map(\.message))
                }
                encoding = result.encoding
            } catch let error as TextFileLoaderError { throw error }
            catch { throw TextFileLoaderError.fileNotReadable(path: path) }
        }
        guard let foundationEncoding = encoding.foundationEncoding else {
            throw TextFileLoaderError.couldNotDecodeWithEncoding(path: path, encoding: encoding)
        }
        do {
            try handle.seek(toOffset: UInt64(offset))
            let data = try handle.read(upToCount: length) ?? Data()
            guard data.count == length, let content = String(data: data, encoding: foundationEncoding) else {
                throw TextFileLoaderError.partialRangeSplitsCharacter(path: path, encoding: encoding)
            }
            return (content, encoding)
        } catch let error as TextFileLoaderError { throw error }
        catch { throw TextFileLoaderError.fileNotReadable(path: path) }
    }

    /// Loads bytes that were already read, from a descriptor the caller
    /// verified.
    ///
    /// The agent interface opens files by walking down from an authorized root
    /// with `O_NOFOLLOW` at every component; reopening the path afterwards to
    /// hand it to the ordinary loader would give back the symlink race that
    /// walk just closed. So the bytes come in, and the URL is used only for
    /// naming and file-type resolution.
    public static func load(data: Data, representing url: URL) throws -> LoadedText {
        let result = EncodingDetector.detect(data)
        guard result.confidence != .failed else {
            throw TextFileLoaderError.couldNotDecode(
                path: url.path,
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
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else {
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
