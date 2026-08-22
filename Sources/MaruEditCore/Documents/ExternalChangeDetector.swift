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
    /// A file exists but there is no baseline to compare it against, so
    /// whether it changed is unknowable.
    ///
    /// Distinct from `.unchanged` on purpose. Reporting "unchanged" for a
    /// file nobody ever read is an unearned claim, and a caller that acts on
    /// it overwrites content it has never seen. Callers that ask a question
    /// ("should I warn the human?") may treat this as "nothing to say";
    /// callers about to destroy data must treat it as a refusal.
    case unknownBaseline
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

        // No baseline is not the same as no change. A document with no
        // captured metadata cannot be compared, and reporting `.unchanged`
        // means a save will happily overwrite a file it never read. Callers
        // that genuinely have no baseline — a brand-new document being saved
        // for the first time — do not reach here, because they have no URL to
        // compare either.
        guard let knownModificationDate else { return .unknownBaseline }

        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        let currentModificationDate = attributes?[.modificationDate] as? Date
        let currentIdentity = FileIdentity.of(url)

        if currentModificationDate == knownModificationDate, currentIdentity == knownIdentity {
            return .unchanged
        }
        return .modified
    }
}
