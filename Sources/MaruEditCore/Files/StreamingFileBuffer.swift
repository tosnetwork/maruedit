import Foundation

public struct StreamingEdit: Equatable, Sendable {
    public let range: Range<UInt64>
    public let replacement: Data

    public init(range: Range<UInt64>, replacement: Data) {
        self.range = range
        self.replacement = replacement
    }
}

/// A bounded-memory editing layer for files that should not be materialized as
/// a String. Edits use original-file byte offsets and must not overlap.
public final class StreamingFileBuffer: @unchecked Sendable {
    public let sourceURL: URL
    public let byteCount: UInt64
    private let lock = NSLock()
    private var edits: [StreamingEdit] = []

    public init(url: URL) throws {
        sourceURL = url
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        byteCount = UInt64(values.fileSize ?? 0)
    }

    public func read(offset: UInt64, length: Int) throws -> Data {
        guard offset <= byteCount, length >= 0 else { throw StreamingFileError.invalidRange }
        let handle = try FileHandle(forReadingFrom: sourceURL)
        defer { try? handle.close() }
        try handle.seek(toOffset: offset)
        return try handle.read(upToCount: min(length, 1_048_576)) ?? Data()
    }

    public func stage(_ edit: StreamingEdit) throws {
        guard edit.range.lowerBound <= edit.range.upperBound,
              edit.range.upperBound <= byteCount else { throw StreamingFileError.invalidRange }
        lock.lock()
        defer { lock.unlock() }
        guard !edits.contains(where: { $0.range.overlaps(edit.range) }) else {
            throw StreamingFileError.overlappingEdit
        }
        edits.append(edit)
        edits.sort { $0.range.lowerBound < $1.range.lowerBound }
    }

    public var stagedEdits: [StreamingEdit] {
        lock.withLock { edits }
    }

    /// Streams unchanged spans and replacements to a new file in bounded chunks.
    public func write(to destination: URL, chunkSize: Int = 1_048_576) throws {
        let chunkSize = min(1_048_576, max(4_096, chunkSize))
        let input = try FileHandle(forReadingFrom: sourceURL)
        FileManager.default.createFile(atPath: destination.path, contents: nil)
        let output = try FileHandle(forWritingTo: destination)
        defer { try? input.close(); try? output.close() }
        var cursor: UInt64 = 0
        for edit in stagedEdits {
            try copy(input: input, output: output, from: cursor,
                     count: edit.range.lowerBound - cursor, chunkSize: chunkSize)
            try output.write(contentsOf: edit.replacement)
            cursor = edit.range.upperBound
        }
        try copy(input: input, output: output, from: cursor,
                 count: byteCount - cursor, chunkSize: chunkSize)
    }

    private func copy(input: FileHandle, output: FileHandle, from offset: UInt64,
                      count: UInt64, chunkSize: Int) throws {
        try input.seek(toOffset: offset)
        var remaining = count
        while remaining > 0 {
            let amount = min(chunkSize, Int(remaining))
            guard let data = try input.read(upToCount: amount), !data.isEmpty else {
                throw StreamingFileError.unexpectedEndOfFile
            }
            try output.write(contentsOf: data)
            remaining -= UInt64(data.count)
        }
    }
}

public enum StreamingFileError: Error, Equatable { case invalidRange, overlappingEdit, unexpectedEndOfFile }

public struct BinaryRow: Equatable, Sendable {
    public let offset: UInt64
    public let bytes: [UInt8]
    public var hexadecimal: String { bytes.map { String(format: "%02X", $0) }.joined(separator: " ") }
    public var ascii: String { String(bytes.map { (32...126).contains($0) ? Character(UnicodeScalar($0)) : "." }) }
}

public enum BinaryViewModel {
    public static func rows(data: Data, startingAt offset: UInt64 = 0,
                            bytesPerRow: Int = 16) -> [BinaryRow] {
        let width = min(256, max(1, bytesPerRow))
        let bytes = Array(data)
        return stride(from: 0, to: bytes.count, by: width).map { index in
            BinaryRow(offset: offset + UInt64(index),
                      bytes: Array(bytes[index..<min(index + width, bytes.count)]))
        }
    }
}
