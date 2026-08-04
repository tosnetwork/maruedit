import Foundation

/// Writes `Data` to disk atomically: either the write fully succeeds and
/// replaces the destination, or the destination is left untouched. Used
/// for MaruEdit's own state files (session, preferences-on-disk variants,
/// etc.) — not the full user-document Safe-Save Protocol from
/// ROADMAP.md section 10.5, which has additional requirements (permission
/// preservation, external-conflict detection) that don't apply here.
public enum AtomicFileWriter {
    public enum WriteError: Error {
        case failedToCreateDirectory(URL, underlying: Error)
    }

    /// Writes `data` to `url`, creating the containing directory if
    /// needed. Uses `Data.write(options: .atomic)`, which writes to a
    /// temporary file in the same directory and renames it into place —
    /// a partial write or crash mid-write never corrupts the destination.
    public static func write(_ data: Data, to url: URL) throws {
        let directory = url.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: directory.path) {
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            } catch {
                throw WriteError.failedToCreateDirectory(directory, underlying: error)
            }
        }
        try data.write(to: url, options: .atomic)
    }
}
