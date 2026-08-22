import AppKit
import MaruEditCore

/// The only thing that writes a document to disk.
///
/// Saving used to be a synchronous method every entry point called for itself,
/// which was fine while nothing could change underneath it. Two things broke
/// that. The expensive part — policy transformation and encoding a large
/// buffer — ran on the main actor and stalled typing. And `markSaved()`
/// recorded whatever `content` held when the write returned, so the moment any
/// of it moved off the main actor a document could be reported clean in a state
/// it was never saved in.
///
/// So there is one machine now, every entry point goes through it, and each
/// path out of it is named. A fence only one participant respects is not a
/// fence.
@MainActor
final class SaveCoordinator {

    // MARK: - Types

    /// Everything a save needs, captured before anything can move.
    ///
    /// Three values are named separately because conflating them is exactly how
    /// the old code arrived at its bug: what the buffer held, what reached
    /// disk, and what the file looked like beforehand are three different
    /// things.
    struct SavePlan {
        /// The buffer text as captured, in LF form.
        let sourceSnapshot: String
        let textRevision: UInt64
        let metadataRevision: UInt64
        let url: URL
        let encoding: TextEncoding
        let hasByteOrderMark: Bool
        let lineEnding: LineEndingState
        let savePolicy: ProfileSavePolicy?
        let permissions: Int?
        let isBinary: Bool
        /// File identity and modification date as observed at plan time.
        let diskIdentity: FileIdentity?
        let diskModificationDate: Date?
        /// Save As writes somewhere the baseline does not describe, so the
        /// external-change check does not apply to it.
        let checksExternalChange: Bool
        /// Revisions the *caller* requires to still hold at commit time.
        ///
        /// These belong to the requester, not to the machine. An agent's save
        /// acts on a read that may have expired, so it declares what it saw and
        /// is refused if that moved. A human pressing ⌘S has no such concept:
        /// typing a character while a large file encodes must still save — what
        /// was there when they pressed it — and leave the newer character
        /// unsaved. Refusing there would turn "I saved" into a silent no-op,
        /// which is the failure the human-first rule exists to prevent.
        let requiredTextRevision: UInt64?
        let requiredMetadataRevision: UInt64?
    }

    /// Where a save ended. Every one of these releases the fence exactly once
    /// and settles any pending human intent.
    enum Outcome: Equatable {
        case succeeded
        /// Nothing was written and the file on disk is untouched.
        case failedBeforeIrreversible(String)
        /// The commit had begun. The file is either the old bytes or the new
        /// ones — never a mixture — but which one is not knowable from here.
        case failedAfterIrreversible(String)
        /// A human save won while an agent's was still preparing.
        case superseded
        /// A precondition moved between planning and committing.
        case conflicted(String)
        /// Another *agent* save of this document is mid-flight.
        case inProgress
        /// A human save arrived mid-flight and will run as soon as the current
        /// one unwinds. It is queued, not refused.
        case queuedBehindAnotherSave
    }

    enum Requester: Equatable {
        case human
        case agent
    }

    // MARK: - State

    static let shared = SaveCoordinator()

    private var inFlight: Set<AutomationID> = []
    /// A human save that arrived too late to supersede and runs as soon as the
    /// current one finishes. Never dropped: a person who pressed ⌘S and got
    /// nothing would be exactly the failure the human-first rule exists to
    /// prevent.
    private var pendingHumanSaves: [AutomationID: () -> Void] = [:]
    private var supersededDocuments: Set<AutomationID> = []

    // MARK: - Planning

    /// Non-interactive preflight. Returns why a save would not work, or `nil`.
    func preflightFailure(for document: Document, savingAs url: URL? = nil) -> String? {
        if document.isEditingDisabled { return "read_only" }
        if document.isOverwriteProhibited && url == nil { return "overwrite_prohibited" }
        if url == nil && document.fileURL == nil { return "save_as_required" }
        if !document.isBinaryMode {
            if case .mixed = document.lineEnding { return "mixed_line_endings" }
            if !document.preflightSave().isRepresentable { return "unrepresentable" }
        }
        return nil
    }

    func plan(
        for document: Document,
        savingAs url: URL? = nil,
        requiredTextRevision: UInt64? = nil,
        requiredMetadataRevision: UInt64? = nil
    ) -> SavePlan? {
        guard let target = url ?? document.fileURL else { return nil }
        return SavePlan(
            sourceSnapshot: document.content,
            textRevision: document.textRevision,
            metadataRevision: document.metadataRevision,
            url: target,
            encoding: document.encoding,
            hasByteOrderMark: document.hasByteOrderMark,
            lineEnding: document.lineEnding,
            savePolicy: document.fileTypeProfile?.settings.savePolicy,
            permissions: document.posixPermissions,
            isBinary: document.isBinaryMode,
            diskIdentity: document.fileIdentity,
            diskModificationDate: document.lastKnownModificationDate,
            checksExternalChange: url == nil,
            requiredTextRevision: requiredTextRevision,
            requiredMetadataRevision: requiredMetadataRevision)
    }

    // MARK: - Saving

    /// Runs one save from end to end.
    ///
    /// `completion` is called on the main actor with the outcome. The caller
    /// decides what to show; the coordinator never puts UI on screen, because
    /// an agent-initiated save must not be able to open a dialog (R17).
    func save(
        document: Document,
        as url: URL? = nil,
        requester: Requester,
        requiredTextRevision: UInt64? = nil,
        requiredMetadataRevision: UInt64? = nil,
        completion: @escaping (Outcome) -> Void
    ) {
        let id = document.automationID

        if inFlight.contains(id) {
            switch requester {
            case .agent:
                // A queue here would hide the ordering question rather than
                // answer it.
                completion(.inProgress)
            case .human:
                // The human always wins. Too late to supersede the write, so
                // it runs the moment the current one finishes.
                pendingHumanSaves[id] = { [weak self] in
                    self?.save(
                        document: document, as: url, requester: .human,
                        completion: completion)
                }
            }
            return
        }

        if let failure = preflightFailure(for: document, savingAs: url) {
            completion(.failedBeforeIrreversible(failure))
            return
        }
        guard let plan = plan(
            for: document, savingAs: url,
            requiredTextRevision: requiredTextRevision,
            requiredMetadataRevision: requiredMetadataRevision)
        else {
            completion(.failedBeforeIrreversible("save_as_required"))
            return
        }

        inFlight.insert(id)
        supersededDocuments.remove(id)

        // Prepare off the main actor: policy transformation and encoding are
        // the expensive part of saving a large buffer, and they touch only the
        // plan, never the live document.
        Task.detached(priority: .userInitiated) {
            let prepared = Self.prepare(plan)
            await MainActor.run {
                self.commit(
                    document: document, plan: plan, prepared: prepared,
                    requester: requester, completion: completion)
            }
        }
    }

    /// Saves without yielding, for the callers whose next step depends on the
    /// write having happened.
    ///
    /// Save-and-close, Save All, and app termination all sequence something
    /// after the save — closing a tab, moving to the next document, quitting —
    /// and an asynchronous write there would let the tab close before the bytes
    /// land. They pay a stalled main thread for that ordering, which is the
    /// right trade when the alternative is losing the file.
    ///
    /// It is the same machine: same plan, same fence, same commit, same
    /// finalize. Only the hop is missing.
    @discardableResult
    func saveSynchronously(
        document: Document,
        as url: URL? = nil,
        requester: Requester = .human
    ) -> Outcome {
        let id = document.automationID
        if inFlight.contains(id) {
            switch requester {
            case .agent:
                return .inProgress
            case .human:
                // Never dropped. The agent save in flight has already been told
                // to stand down by `supersede`; this one runs the moment it
                // unwinds. Returning `.inProgress` here — which is what the
                // first version did — silently threw away a ⌘S, which is
                // precisely the failure the human-first rule exists to prevent.
                pendingHumanSaves[id] = { [weak self] in
                    _ = self?.saveSynchronously(document: document, as: url, requester: .human)
                }
                return .queuedBehindAnotherSave
            }
        }
        if let failure = preflightFailure(for: document, savingAs: url) {
            return .failedBeforeIrreversible(failure)
        }
        guard let plan = plan(for: document, savingAs: url) else {
            return .failedBeforeIrreversible("save_as_required")
        }
        inFlight.insert(id)
        supersededDocuments.remove(id)
        let prepared = Self.prepare(plan)
        var outcome: Outcome = .failedBeforeIrreversible("unknown")
        commit(document: document, plan: plan, prepared: prepared, requester: requester) {
            outcome = $0
        }
        return outcome
    }

    /// A human save arriving while an agent's is still preparing supersedes it.
    func supersede(_ document: Document) {
        guard inFlight.contains(document.automationID) else { return }
        supersededDocuments.insert(document.automationID)
    }

    // MARK: - Prepare (off the main actor)

    private enum Prepared {
        case bytes(Data)
        case failure(String)
    }

    private nonisolated static func prepare(_ plan: SavePlan) -> Prepared {
        if plan.isBinary {
            // A binary document's buffer is a hex rendering; it is parsed back
            // rather than encoded, and none of the text pipeline applies.
            do { return .bytes(try BinaryDocumentCodec.parse(plan.sourceSnapshot)) }
            catch { return .failure("invalid_binary") }
        }
        guard let foundationEncoding = plan.encoding.foundationEncoding else {
            return .failure("unrepresentable")
        }
        let transformed = ProfileFilePolicy.transformedForSave(
            plan.sourceSnapshot, policy: plan.savePolicy)
        let preflight = SavePreflight.check(transformed, encoding: plan.encoding)
        guard preflight.isRepresentable else { return .failure("unrepresentable") }

        let kind: LineEndingKind
        switch plan.lineEnding {
        case .lf: kind = .lf
        case .crlf: kind = .crlf
        case .cr: kind = .cr
        case .mixed, .none: kind = .lf
        }
        let output = LineEndingDetector.applying(kind, to: transformed)
        guard let encoded = output.data(using: foundationEncoding) else {
            return .failure("unrepresentable")
        }
        let bom = plan.hasByteOrderMark ? (plan.encoding.byteOrderMark ?? Data()) : Data()
        return .bytes(bom + encoded)
    }

    // MARK: - Commit and finalize (on the main actor)

    private func commit(
        document: Document,
        plan: SavePlan,
        prepared: Prepared,
        requester: Requester,
        completion: @escaping (Outcome) -> Void
    ) {
        let id = document.automationID

        func finish(_ outcome: Outcome) {
            inFlight.remove(id)
            supersededDocuments.remove(id)
            let pending = pendingHumanSaves.removeValue(forKey: id)
            completion(outcome)
            // Pending human intent runs after *every* terminal state, against
            // fresh state, never silently dropped.
            pending?()
        }

        if supersededDocuments.contains(id) && requester == .agent {
            return finish(.superseded)
        }
        guard case .bytes(let data) = prepared else {
            if case .failure(let reason) = prepared { return finish(.failedBeforeIrreversible(reason)) }
            return finish(.failedBeforeIrreversible("unknown"))
        }

        // Revalidate. This is the last point at which nothing has happened.
        //
        // Only the caller's own preconditions are enforced here. Text moving
        // during prepare is normal — the human kept typing — and the planned
        // snapshot is still exactly what they asked to save; finalize leaves
        // the newer text dirty.
        if let required = plan.requiredTextRevision, document.textRevision != required {
            return finish(.conflicted("text_revision"))
        }
        if let required = plan.requiredMetadataRevision, document.metadataRevision != required {
            return finish(.conflicted("metadata_revision"))
        }
        if plan.checksExternalChange {
            let status = ExternalChangeDetector.check(
                url: plan.url,
                knownIdentity: plan.diskIdentity,
                knownModificationDate: plan.diskModificationDate)
            // Anything but `.unchanged`: a file that was deleted or moved after
            // it was opened must not be silently recreated by a save the human
            // did not ask for.
            switch status {
            case .unchanged: break
            case .modified: return finish(.conflicted("external_change"))
            default: return finish(.conflicted("external_missing"))
            }
        }

        // Irreversible from here. Backup creation counts: it copies the old
        // file and may delete an older backup before the destination is
        // touched at all.
        do {
            if let backup = plan.savePolicy?.backup, plan.checksExternalChange {
                _ = try ProfileFilePolicy.createBackup(of: plan.url, settings: backup)
            }
            let info = try TextFileSaver.save(
                data, to: plan.url, preservingPermissionsFrom: plan.permissions)
            finalize(document: document, plan: plan, info: info)
            finish(.succeeded)
        } catch {
            finish(.failedAfterIrreversible(error.localizedDescription))
        }
    }

    private func finalize(document: Document, plan: SavePlan, info: SavedFileInfo) {
        // Read this *before* touching the document: assigning the new URL,
        // identity, and permissions bumps the metadata revision itself, so
        // comparing afterwards would report every save as having raced.
        let metadataMoved = document.metadataRevision != plan.metadataRevision

        document.fileURL = plan.url
        document.fileIdentity = info.fileIdentity
        document.lastKnownModificationDate = info.modificationDate
        document.posixPermissions = info.posixPermissions
        // What was written is the plan's snapshot, not whatever the buffer
        // holds now, and metadata that moved after planning leaves the document
        // format-dirty rather than clean — it was never saved in that form.
        document.markSaved(
            snapshot: plan.sourceSnapshot,
            metadataChangedSincePlan: metadataMoved)
    }
}
