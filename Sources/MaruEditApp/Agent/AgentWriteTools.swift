import AppKit
import MaruEditCore

/// The write half of the tool catalog.
///
/// Every rule here exists because of a specific way agent editing goes wrong in
/// practice: a stale snapshot silently overwriting newer work, a batch that
/// half-applies, an edit aimed at coordinates that moved, an undo entry nobody
/// can find, text the document's encoding cannot represent.
extension AgentToolExecutor {

    // MARK: - apply_edits

    func applyEdits(
        _ arguments: JSONValue, _ connection: AgentControlService.Connection
    ) -> AgentToolOutcome {
        // A client that lost a reply and retried used to get a second edit or a
        // duplicate proposal; the key was advertised and never read.
        if let key = arguments["idempotencyKey"]?.stringValue {
            if let remembered = control.rememberedOutcome(
                connection, tool: "apply_edits", key: key, arguments: arguments) {
                return remembered
            }
            let outcome = applyEditsUnchecked(arguments, connection)
            control.remember(
                connection, tool: "apply_edits", key: key,
                arguments: arguments, outcome: outcome)
            return outcome
        }
        return applyEditsUnchecked(arguments, connection)
    }

    private func applyEditsUnchecked(
        _ arguments: JSONValue, _ connection: AgentControlService.Connection
    ) -> AgentToolOutcome {
        let resolved = resolveForWrite(arguments, connection)
        guard case .success(let target) = resolved else {
            if case .failure(let failure) = resolved { return failure.outcome }
            return .failure(code: "internal", message: "unreachable", details: nil)
        }
        guard let baseRevision = arguments["baseRevision"]?.unsignedValue,
              let baseMetadataRevision = arguments["baseMetadataRevision"]?.unsignedValue
        else {
            return .failure(
                code: "argument.missing",
                message: "baseRevision and baseMetadataRevision are required; take them from read_document.",
                details: nil)
        }

        let document = target.document
        let label = arguments["label"]?.stringValue ?? "edit"

        // Preconditions are checked in precedence order, and the reports differ
        // because what is knowable differs.
        if document.textRevision != baseRevision {
            return .failure(
                code: "state.text_revision_conflict",
                message: """
                    The document changed since you read it. Anchors are snapshot \
                    handles, so MaruEdit cannot tell you where your regions moved \
                    — re-read or search before retrying.
                    """,
                details: .object([
                    "revision": .int(Int(document.textRevision)),
                    "metadataRevision": .int(Int(document.metadataRevision)),
                    "totalLines": .int(AgentToolExecutor.lineCount(document.content)),
                    "utf16Length": .int((document.content as NSString).length),
                ]))
        }
        if document.metadataRevision != baseMetadataRevision {
            // Offsets are still valid here; only the assumptions under them
            // moved, so forcing a full re-read would be a lie in the other
            // direction.
            return .failure(
                code: "state.metadata_conflict",
                message: """
                    The document's encoding, line ending, or profile changed. Your \
                    offsets are still valid; re-check anything that depended on \
                    the old metadata and resubmit with the new revision.
                    """,
                details: .object([
                    "revision": .int(Int(document.textRevision)),
                    "metadataRevision": .int(Int(document.metadataRevision)),
                    "encoding": .string(document.encoding.displayName),
                    "lineEnding": .string(document.lineEnding.displayName),
                ]))
        }

        guard let rawEdits = arguments["edits"]?.arrayValue, !rawEdits.isEmpty else {
            return .failure(code: "argument.missing", message: "edits must be a non-empty array.", details: nil)
        }

        let text = document.content as NSString
        var edits: [AutomationEdit] = []
        var digests: [String?] = []
        for raw in rawEdits {
            let hasAnchor = raw["anchorId"] != nil
            let hasRange = raw["start"] != nil || raw["end"] != nil
            guard !(hasAnchor && hasRange) else {
                return .failure(
                    code: "edit.ambiguous_address",
                    message: "An edit carries both anchorId and start/end. Use one.",
                    details: nil)
            }
            guard let replacement = raw["text"]?.stringValue else {
                return .failure(code: "argument.missing", message: "Each edit needs text.", details: nil)
            }
            guard TextCanonicalization.isCanonical(replacement) else {
                // Rejected rather than normalized: the agent is told its
                // payload was wrong instead of having it silently rewritten.
                return .failure(
                    code: "text.carriage_return",
                    message: "Replacement text must use LF only; MaruEdit buffers never hold CR.",
                    details: nil)
            }

            var range: NSRange
            if hasAnchor {
                guard let anchorID = raw["anchorId"]?.stringValue,
                      let anchor = connection.anchors.anchor(anchorID)
                else {
                    return .failure(
                        code: "anchor.unknown",
                        message: "That anchor is not known to this connection. Re-read to mint fresh ones.",
                        details: nil)
                }
                guard anchor.revision == document.textRevision else {
                    return .failure(
                        code: "anchor.stale",
                        message: "That anchor was minted against an older revision.",
                        details: nil)
                }
                range = NSRange(location: anchor.start, length: anchor.end - anchor.start)
            } else {
                guard let start = raw["start"]?.offsetValue, let end = raw["end"]?.offsetValue,
                      end >= start, end <= text.length
                else {
                    return .failure(
                        code: "edit.range_invalid",
                        message: "start and end must be zero-based UTF-16 offsets inside the document.",
                        details: .object(["utf16Length": .int(text.length)]))
                }
                range = NSRange(location: start, length: end - start)
            }

            if let expected = raw["expectDigest"]?.stringValue {
                let actual = AgentDigest.of(text.substring(with: range))
                guard actual == expected else {
                    // Both revisions matched, so the offsets are exactly
                    // meaningful and the agent can retry immediately.
                    return .failure(
                        code: "state.digest_mismatch",
                        message: "The text at that range is not what you read.",
                        details: .object([
                            "start": .int(range.location),
                            "end": .int(NSMaxRange(range)),
                            "actualDigest": .string(actual),
                            "currentText": .string(AgentTextSlicer.bounded(text.substring(with: range))),
                        ]))
                }
                digests.append(expected)
            } else {
                digests.append(nil)
            }
            edits.append(AutomationEdit(range: range, replacement: replacement))
        }

        // Representability is checked before anything is applied, so an edit
        // cannot leave a document that can no longer be saved without a human
        // conversion decision.
        if let offending = Self.unrepresentable(edits, in: document) {
            return .failure(
                code: "encoding.unrepresentable",
                message: "\(document.encoding.displayName) cannot represent characters in this edit.",
                details: .object(["characters": .string(offending)]))
        }

        // "anything except review means apply" made a typo destructive:
        // `"reveiw"` would have written straight to the document.
        let requested = arguments["mode"]?.stringValue ?? "apply"
        guard requested == "apply" || requested == "review" else {
            return .failure(
                code: "argument.invalid",
                message: "mode must be \"apply\" or \"review\"; got \"\(requested)\".",
                details: nil)
        }
        // The grant decides, not the caller: an agent asking to apply directly
        // gets review anyway unless the human granted that mode. Asking for
        // review when the grant allows applying is honoured, since a client may
        // want a human to look at something.
        let mode = (connection.writeMode == .auto && requested == "apply") ? "apply" : "review"

        if mode == "review" {
            let created = control.proposals.create(
                connectionID: connection.id,
                documentID: document.automationID,
                baseRevision: baseRevision,
                baseMetadataRevision: baseMetadataRevision,
                edits: edits,
                expectedDigests: digests,
                label: label)
            switch created {
            case .success(let proposal):
                return .success(.object([
                    "status": .string("pending"),
                    "proposalId": .string(proposal.id),
                ]))
            case .failure(let failure):
                return failure.outcome
            }
        }

        // Re-check the grant immediately before mutating: it may have been
        // revoked while the edits were being validated.
        guard control.isStillValid(control.stamp(connection)) else {
            return .failure(
                code: "authorization.denied",
                message: "This client's access was revoked before the edit was applied.",
                details: nil)
        }
        return Self.commit(
            edits: edits,
            label: "\(connection.claimedName ?? "agent"): \(label)",
            target: target)
    }

    /// Applies a validated batch and reports the resulting revision.
    static func commit(
        edits: [AutomationEdit],
        label: String,
        target: AgentToolExecutor.Target
    ) -> AgentToolOutcome {
        switch target.editor.applyTransaction(edits, actionName: label) {
        case .success(let outcome):
            return .success(.object([
                "status": .string("applied"),
                "revision": .int(Int(outcome.revisions.text)),
                "metadataRevision": .int(Int(outcome.revisions.metadata)),
                "editsApplied": .int(outcome.appliedEdits.count),
            ]))
        case .failure(let error):
            return .failure(
                code: error.identifier,
                message: String(describing: error),
                details: nil)
        }
    }

    static func unrepresentable(_ edits: [AutomationEdit], in document: Document) -> String? {
        guard let encoding = document.encoding.foundationEncoding, encoding != .utf8 else { return nil }
        var offending: Set<Character> = []
        for edit in edits {
            for character in edit.replacement where String(character).data(using: encoding) == nil {
                offending.insert(character)
            }
        }
        guard !offending.isEmpty else { return nil }
        return String(offending.sorted().prefix(20))
    }

    /// Applies a proposal the human accepted.
    ///
    /// The same atomic check that guards a direct write runs again, because the
    /// grant may have been revoked and the document may have moved while the
    /// proposal sat in the queue. A proposal is never relocated to fit.
    static func applyProposal(
        _ proposal: AgentProposalStore.Proposal,
        target: AgentToolExecutor.Target,
        store: AgentProposalStore
    ) -> Bool {
        let document = target.document
        guard document.textRevision == proposal.baseRevision,
              document.metadataRevision == proposal.baseMetadataRevision
        else {
            store.mark(proposal.id, .conflicted)
            return false
        }
        let text = document.content as NSString
        for (index, edit) in proposal.edits.enumerated() {
            guard let expected = proposal.expectedDigests[index] else { continue }
            guard NSMaxRange(edit.range) <= text.length,
                  AgentDigest.of(text.substring(with: edit.range)) == expected
            else {
                store.mark(proposal.id, .conflicted)
                return false
            }
        }
        switch target.editor.applyTransaction(proposal.edits, actionName: proposal.label) {
        case .success(let outcome):
            store.mark(proposal.id, .applied, resultingRevision: outcome.revisions.text)
            return true
        case .failure:
            store.mark(proposal.id, .conflicted)
            return false
        }
    }

    // MARK: - review_status

    func reviewStatus(_ arguments: JSONValue) -> AgentToolOutcome {
        guard let id = arguments["proposalId"]?.stringValue else {
            return .failure(code: "argument.missing", message: "proposalId is required.", details: nil)
        }
        guard let proposal = control.proposals.proposal(id) else {
            return .failure(
                code: "proposal.unknown",
                message: "No such proposal. They expire after \(Int(AgentProposalStore.lifetime / 60)) minutes.",
                details: nil)
        }
        var payload: [String: JSONValue] = ["status": .string(proposal.status.rawValue)]
        if let revision = proposal.resultingRevision { payload["revision"] = .int(Int(revision)) }
        return .success(.object(payload))
    }

    // MARK: - Selection

    func setSelection(
        _ arguments: JSONValue, _ connection: AgentControlService.Connection
    ) -> AgentToolOutcome {
        guard let raw = arguments["editorId"]?.stringValue,
              let baseRevision = arguments["baseRevision"]?.unsignedValue,
              let baseSelectionRevision = arguments["baseSelectionRevision"]?.unsignedValue
        else {
            return .failure(
                code: "argument.missing",
                message: "editorId, baseRevision, and baseSelectionRevision are required.",
                details: nil)
        }
        guard let target = editorTarget(raw, connection) else {
            return .failure(
                code: "editor.unknown",
                message: "No editor pane with id \(raw) is available to this client.",
                details: nil)
        }
        // Both preconditions: a human editing *elsewhere* moves the coordinates
        // without moving the selection, so the selection revision alone would
        // let a stale target through.
        guard target.document.textRevision == baseRevision else {
            return .failure(
                code: "state.text_revision_conflict",
                message: "The document changed; the coordinates you computed no longer mean the same thing.",
                details: .object(["revision": .int(Int(target.document.textRevision))]))
        }
        guard target.editor.selectionRevision == baseSelectionRevision else {
            return .failure(
                code: "state.selection_conflict",
                message: "The human moved the cursor since you read it.",
                details: .object(["selectionRevision": .int(Int(target.editor.selectionRevision))]))
        }
        guard let rawSelections = arguments["selections"]?.arrayValue, !rawSelections.isEmpty else {
            return .failure(code: "argument.missing", message: "selections must be a non-empty array.", details: nil)
        }
        let length = (target.document.content as NSString).length
        var ranges: [NSRange] = []
        for raw in rawSelections {
            guard let start = raw["start"]?.offsetValue, let end = raw["end"]?.offsetValue,
                  end >= start, end <= length
            else {
                return .failure(
                    code: "edit.range_invalid",
                    message: "Selection offsets must lie inside the document.",
                    details: .object(["utf16Length": .int(length)]))
            }
            ranges.append(NSRange(location: start, length: end - start))
        }
        let service = EditorAutomationService(editor: target.editor)
        guard service.setSelections(ranges) else {
            return .failure(code: "edit.range_invalid", message: "Selection was rejected.", details: nil)
        }
        return .success(.object([
            "selectionRevision": .int(Int(target.editor.selectionRevision)),
        ]))
    }

    func reveal(
        _ arguments: JSONValue, _ connection: AgentControlService.Connection
    ) -> AgentToolOutcome {
        guard let raw = arguments["editorId"]?.stringValue,
              let baseRevision = arguments["baseRevision"]?.unsignedValue,
              let line = arguments["line"]?.offsetValue
        else {
            return .failure(
                code: "argument.missing",
                message: "editorId, baseRevision, and line are required.",
                details: nil)
        }
        guard let target = editorTarget(raw, connection) else {
            return .failure(code: "editor.unknown", message: "No such editor pane.", details: nil)
        }
        guard target.document.textRevision == baseRevision else {
            return .failure(
                code: "state.text_revision_conflict",
                message: "The document changed; that line number may no longer be the line you meant.",
                details: .object(["revision": .int(Int(target.document.textRevision))]))
        }
        let text = target.document.content as NSString
        let starts = AgentTextSlicer.lineStartsForTesting(text)
        let index = max(0, min(starts.count - 1, line - 1))
        // Scrolls without moving the cursor: revealing is not selecting.
        target.editor.textView.scrollRangeToVisible(NSRange(location: starts[index], length: 0))
        return .success(.object(["revealedLine": .int(index + 1)]))
    }

    // MARK: - save_document

    /// Saves, through the same coordinator every other save path uses.
    ///
    /// This only became safe once human Save, Save As, and save-on-close moved
    /// onto that coordinator: a fence only one participant respects is not a
    /// fence. The human still wins every race — a ⌘S supersedes an agent save
    /// that is still preparing, and one that arrives too late runs immediately
    /// afterwards — and nothing here can put a dialog on screen (R17).
    func saveDocument(
        _ arguments: JSONValue, _ connection: AgentControlService.Connection
    ) async -> AgentToolOutcome {
        let resolved = resolveForWrite(arguments, connection)
        guard case .success(let target) = resolved else {
            if case .failure(let failure) = resolved { return failure.outcome }
            return .failure(code: "internal", message: "unreachable", details: nil)
        }
        let document = target.document

        // The preconditions are handed to the coordinator rather than checked
        // here, so they are revalidated atomically immediately before the
        // commit rather than a few statements earlier.
        let grant = control.stamp(connection)
        let outcome = await withCheckedContinuation { continuation in
            SaveCoordinator.shared.save(
                document: document,
                requester: .agent,
                requiredTextRevision: arguments["expectRevision"]?.unsignedValue,
                requiredMetadataRevision: arguments["expectMetadataRevision"]?.unsignedValue
            ) { result in
                continuation.resume(returning: result)
            }
        }

        // A revocation that landed while the save was preparing arrives too
        // late to stop the write, so it is reported rather than hidden.
        if !control.isStillValid(grant), case .succeeded = outcome {
            return .failure(
                code: "authorization.revoked_after_write",
                message: "Access was revoked while the save was in flight; the file was already written.",
                details: nil)
        }

        switch outcome {
        case .succeeded:
            return .success(.object([
                "status": .string("saved"),
                "revision": .int(Int(document.textRevision)),
                "metadataRevision": .int(Int(document.metadataRevision)),
                "stillDirty": .bool(document.isModified),
            ]))
        case .queuedBehindAnotherSave:
            // Only a human save is ever queued, so an agent cannot reach this.
            return .failure(
                code: "save.in_progress",
                message: "A save of this document is already running.",
                details: nil)
        case .inProgress:
            return .failure(
                code: "save.in_progress",
                message: "Another save of this document is running. Try again shortly.",
                details: nil)
        case .superseded:
            return .failure(
                code: "state.superseded",
                message: "The person at the keyboard saved instead; nothing was written on your behalf.",
                details: nil)
        case .conflicted("text_revision"):
            return .failure(
                code: "state.text_revision_conflict",
                message: "The document changed since you read it; nothing was written.",
                details: .object(["revision": .int(Int(document.textRevision))]))
        case .conflicted("metadata_revision"):
            return .failure(
                code: "state.metadata_conflict",
                message: "The encoding or line ending changed since you read it; nothing was written.",
                details: .object(["metadataRevision": .int(Int(document.metadataRevision))]))
        case .conflicted(let reason):
            return .failure(
                code: "state.conflict",
                message: "The save was refused: \(reason). Nothing was written.",
                details: .object(["reason": .string(reason)]))
        case .failedBeforeIrreversible(let reason):
            return .failure(
                code: "save.\(reason)",
                message: "The document cannot be saved as it stands (\(reason)). Nothing was written.",
                details: nil)
        case .failedAfterIrreversible(let reason):
            // The file is either the old bytes or the new ones, never a
            // mixture, but which one is not knowable from here.
            return .failure(
                code: "save.failed_after_write_began",
                message: "The write had already begun when it failed (\(reason)). Check the file.",
                details: nil)
        }
    }
}
