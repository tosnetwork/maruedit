import Foundation

/// Fresh file metadata to record after a successful save, so in-memory
/// state (`Document`) stays accurate for later work like external-
/// modification detection (M2-06) without re-`stat`ing separately.
public struct SavedFileInfo: Sendable, Equatable {
    public let fileIdentity: FileIdentity?
    public let modificationDate: Date?
    public let posixPermissions: Int?
}

public enum TextFileSaverError: Error, Sendable {
    case writeFailed(underlying: NSError)
}

extension TextFileSaverError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .writeFailed(let underlying):
            return "Could not save the file: \(underlying.localizedDescription)"
        }
    }
}

/// Writes document bytes to disk safely, per ROADMAP.md M2-05:
/// - atomic (temporary file on the same filesystem, replaced by rename —
///   a failure partway through never leaves a corrupt or truncated file
///   at the destination, and the original is untouched until the rename
///   succeeds);
/// - preserves the existing file's POSIX permissions instead of letting
///   the new file fall back to default (umask-derived) permissions.
public enum TextFileSaver {
    /// - Parameters:
    ///   - data: the exact bytes to write.
    ///   - url: the destination.
    ///   - existingPermissions: the POSIX permissions to restore after
    ///     writing (typically the value captured when the file was
    ///     loaded). `nil` for a document that has never been saved
    ///     before, in which case the new file keeps its default
    ///     (umask-derived) permissions — there is nothing to preserve.
    @discardableResult
    public static func save(_ data: Data, to url: URL, preservingPermissionsFrom existingPermissions: Int?) throws -> SavedFileInfo {
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            throw TextFileSaverError.writeFailed(underlying: error as NSError)
        }

        if let existingPermissions {
            // Best-effort: a failure here (e.g. unusual filesystem) must
            // not undo an otherwise-successful save.
            try? FileManager.default.setAttributes(
                [.posixPermissions: existingPermissions],
                ofItemAtPath: url.path
            )
        }

        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return SavedFileInfo(
            fileIdentity: FileIdentity.of(url),
            modificationDate: attributes?[.modificationDate] as? Date,
            posixPermissions: (attributes?[.posixPermissions] as? NSNumber)?.intValue
        )
    }
}
