import Foundation

/// Decides whether a file looks like something a text search should skip.
///
/// The rule is the classic one: a NUL byte in the first few kilobytes.
/// It is cheap, has no false positives on UTF-8/Shift-JIS/EUC-JP text, and
/// deliberately does not try to be clever — UTF-16 text, which legitimately
/// contains NUL bytes, is recognized by its BOM first.
public enum BinaryContentDetector {
    public static let inspectedByteCount = 8 * 1024

    public static func isProbablyBinary(_ data: Data) -> Bool {
        if hasTextByteOrderMark(data) { return false }
        return data.prefix(inspectedByteCount).contains(0)
    }

    /// Reads only the header, so deciding "binary" never costs a full read
    /// of a large file. Returns `false` when the file can't be read — the
    /// caller reports unreadable files separately and shouldn't have that
    /// turn into a "binary" label.
    public static func isProbablyBinaryFile(at url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        let header = (try? handle.read(upToCount: inspectedByteCount)) ?? Data()
        return isProbablyBinary(header)
    }

    private static func hasTextByteOrderMark(_ data: Data) -> Bool {
        let marks: [[UInt8]] = [
            [0xEF, 0xBB, 0xBF],       // UTF-8
            [0xFF, 0xFE],             // UTF-16 LE (and UTF-32 LE, which starts the same)
            [0xFE, 0xFF],             // UTF-16 BE
            [0x00, 0x00, 0xFE, 0xFF], // UTF-32 BE
        ]
        let prefix = Array(data.prefix(4))
        return marks.contains { mark in
            prefix.count >= mark.count && Array(prefix.prefix(mark.count)) == mark
        }
    }
}
