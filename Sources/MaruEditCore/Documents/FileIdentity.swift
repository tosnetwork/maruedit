import Foundation

/// A POSIX device+inode pair identifying a specific file on disk,
/// independent of its current path. Two `URL`s pointing at the same
/// inode (e.g. after a rename) have the same `FileIdentity`; a
/// replacement file at the same path does not. Used by later milestones
/// (external-modification detection, M2-06) to distinguish "this file was
/// edited" from "this file was replaced."
public struct FileIdentity: Sendable, Equatable, Hashable {
    public let deviceID: Int32
    public let inodeNumber: UInt64

    public init(deviceID: Int32, inodeNumber: UInt64) {
        self.deviceID = deviceID
        self.inodeNumber = inodeNumber
    }

    /// Reads the identity of the file currently at `url`, or `nil` if it
    /// can't be stat'd (e.g. the file doesn't exist).
    public static func of(_ url: URL) -> FileIdentity? {
        var statInfo = stat()
        guard stat(url.path, &statInfo) == 0 else { return nil }
        return FileIdentity(deviceID: Int32(statInfo.st_dev), inodeNumber: UInt64(statInfo.st_ino))
    }
}
