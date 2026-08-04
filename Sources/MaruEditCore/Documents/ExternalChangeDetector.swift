import Foundation

/// Whether a file on disk has changed since a document last knew about
/// it, per ROADMAP.md M2-06.
public enum ExternalChangeStatus: Sendable, Equatable {
    /// Nothing detectable has changed since the known baseline.
    case unchanged
    /// The file still exists but its modification date (and/or identity)
    /// no longer matches the known baseline — something wrote to it.
    case modified
    /// No file exists at the given path anymore (deleted, or moved/
    /// renamed away — this checker has no way to distinguish the two
    /// without a live filesystem watcher, which is out of scope; both are
    /// reported the same way so callers can react without crashing or
    /// silently pretending nothing happened).
    case deletedOrMoved
}

/// Compares a file's current on-disk state against a previously-known
/// baseline (typically `Document.fileIdentity`/`lastKnownModificationDate`,
/// captured by `TextFileLoader` on open and refreshed by `TextFileSaver`
/// after every save — so a document's *own* save always updates its own
/// baseline and never flags itself as an external change).
///
/// This is revalidation, not live monitoring: it answers "has this
/// changed since I last checked," called at specific points (window
/// activation, before a save) rather than watching the filesystem
/// continuously via FSEvents. ROADMAP.md M2-06 explicitly allows either
/// approach ("Monitor **or** revalidate").
public enum ExternalChangeDetector {
    public static func check(url: URL, knownIdentity: FileIdentity?, knownModificationDate: Date?) -> ExternalChangeStatus {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return .deletedOrMoved
        }

        // No baseline to compare against (e.g. a document that was never
        // actually loaded from this exact path with metadata captured) —
        // nothing to call "changed" relative to.
        guard let knownModificationDate else { return .unchanged }

        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        let currentModificationDate = attributes?[.modificationDate] as? Date
        let currentIdentity = FileIdentity.of(url)

        if currentModificationDate == knownModificationDate, currentIdentity == knownIdentity {
            return .unchanged
        }
        return .modified
    }
}
