import AppKit
import MaruEditCore

/// The one place text is replaced in bulk.
///
/// The multi-cursor engine that preceded it silently dropped out-of-bounds
/// ranges, merged overlaps by picking the earliest replacement, returned
/// nothing, and hard-coded its Undo action name. That is fine for a human
/// dragging cursors and useless as the floor under automation, which needs a
/// batch to apply completely or not at all, and needs to know which it was.
///
/// So the primitive is strict and the lenient behavior lives in an adapter
/// above it (`batchReplace`), rather than the primitive being weakened to suit
/// its most forgiving caller.
extension EditorViewController {

    /// Applies every edit as one transaction, or none of them.
    ///
    /// Validation happens before any mutation, so a rejected transaction leaves
    /// the document byte-identical — text, selections, bookmarks, color
    /// markers, temporary markers, and line index alike.
    @discardableResult
    func applyTransaction(
        _ edits: [AutomationEdit],
        actionName: String
    ) -> Result<AutomationTransactionOutcome, AutomationTransactionError> {
        guard let storage = textView.textStorage else { return .failure(.notEditable) }
        if let document, document.isEditingDisabled { return .failure(.notEditable) }
        guard !edits.isEmpty else { return .failure(.empty) }

        let documentLength = storage.length
        for edit in edits {
            let range = edit.range
            guard range.location != NSNotFound,
                  range.location >= 0,
                  range.length >= 0,
                  NSMaxRange(range) <= documentLength
            else { return .failure(.rangeOutOfBounds(range)) }
        }

        let ordered = edits.sorted {
            $0.range.location == $1.range.location
                ? $0.range.length < $1.range.length
                : $0.range.location < $1.range.location
        }
        for (previous, next) in zip(ordered, ordered.dropFirst()) {
            let overlaps = next.range.location < NSMaxRange(previous.range)
                || (next.range.length == 0 && NSLocationInRange(next.range.location, previous.range))
            if overlaps { return .failure(.overlappingEdits(previous.range, next.range)) }
        }

        return .success(commitValidatedTransaction(ordered, actionName: actionName))
    }

    /// Applies edits already known to be in bounds, ordered, and disjoint.
    ///
    /// Every offset-addressed set a document carries has a stated policy here,
    /// because an edit that moves text without moving them corrupts them
    /// silently and no text comparison notices:
    ///
    /// | Set | Policy |
    /// |---|---|
    /// | Bookmarks | transformed with the edit, then normalized |
    /// | Color markers | transformed with the edit |
    /// | Temporary color markers | transformed with the edit |
    /// | Line index | transformed with the edit |
    /// | Selections | recomputed from the applied edits |
    /// | Edit marks | transformed *and* extended — the gutter's job is to show
    ///   which lines changed, and an agent's edit is a change |
    /// | Search color layers | **invalidated** — they are results of a query
    ///   against text that no longer exists |
    /// | Folds | **invalidated** — ranges are rebuilt from the new outline |
    /// | Syntax highlighting | rebuilt asynchronously |
    ///
    /// Invalidation is a real choice, not an omission: a stale search highlight
    /// pointing into moved text is worse than none. So is transformation where
    /// it is meaningful — an edit mark that did not follow its line would send
    /// the human to the wrong place.
    func commitValidatedTransaction(
        _ ordered: [AutomationEdit],
        actionName: String
    ) -> AutomationTransactionOutcome {
        guard let storage = textView.textStorage else {
            return AutomationTransactionOutcome(
                appliedEdits: [], resultingCursors: [], revisions: document?.revisions ?? DocumentRevisions())
        }
        beginInputLatencySignpost()
        defer { endInputLatencySignpost() }
        if lineIndex.utf16Length != storage.length {
            lineIndex = LineIndex(textView.string)
        }

        let deleted = ordered.compactMap { edit -> String? in
            guard edit.replacement.isEmpty, edit.range.length > 0 else { return nil }
            return (textView.string as NSString).substring(with: edit.range)
        }.joined()
        rememberDeletedText(deleted)

        var positions: [Int] = []
        var offset = 0
        for edit in ordered {
            let insertLength = (edit.replacement as NSString).length
            positions.append(edit.range.location + offset + insertLength)
            offset += insertLength - edit.range.length
        }

        let snapshot = transactionSnapshot()

        let textBeforeEdit = textView.string as NSString
        storage.beginEditing()
        for edit in ordered.reversed() {
            document?.bookmarks.applyEdit(range: edit.range, replacement: edit.replacement)
            document?.editMarks.recordEdit(
                range: edit.range, replacement: edit.replacement, in: textBeforeEdit)
            document?.colorMarkers.applyEdit(range: edit.range, replacement: edit.replacement)
            applyTemporaryColorMarkerEdit(range: edit.range, replacement: edit.replacement)
            lineIndex.applyEdit(range: edit.range, replacement: edit.replacement)
            storage.replaceCharacters(in: edit.range, with: edit.replacement)
        }
        storage.endEditing()

        // Search highlights are results of a query against text that no longer
        // exists, so they go rather than being dragged along.
        document?.searchColorLayers.removeAll()
        refreshColorOverlays()

        let newContent = textView.string
        document?.bookmarks.normalize(in: newContent as NSString)
        // Edit marks are line anchors; after a multi-line deletion one can end
        // up mid-line unless it is snapped back, exactly as the ordinary edit
        // path does.
        document?.editMarks.normalize(in: newContent as NSString)
        document?.content = newContent
        document?.markModified()
        delegate?.editorTextDidChange(self)

        let maxLength = (newContent as NSString).length
        let unique = Array(Set(positions.map { max(0, min($0, maxLength)) })).sorted()
        let cursors = unique.map { NSRange(location: $0, length: 0) }
        let primary = cursors.first ?? NSRange(location: 0, length: 0)

        setSelections(cursors, primaryRange: primary)
        isMultiEditActive = cursors.count > 1
        refreshBookmarkGutter()
        rehighlightEntireDocument()
        // Attribute-only highlighting must not change logical selections. This
        // second call is deliberately a no-op for the selection revision.
        setSelections(cursors, primaryRange: primary)

        registerTransactionUndo(snapshot, actionName: actionName)

        return AutomationTransactionOutcome(
            appliedEdits: ordered,
            resultingCursors: cursors,
            revisions: document?.revisions ?? DocumentRevisions())
    }

    // MARK: - Undo

    /// Everything a transaction changes and Undo must put back. Text alone is
    /// not enough: restoring text while leaving bookmarks where the new text
    /// put them is a silent corruption that no text comparison catches.
    struct TransactionSnapshot {
        let text: String
        let selections: [NSRange]
        let primary: NSRange
        let bookmarks: Set<Int>
        let markers: [Int: MarkerColor]
        /// Restored because the transaction moves and adds to them; without
        /// this, undo gives back the text and leaves the gutter describing
        /// changes that no longer exist.
        let editMarks: Set<Int>
        let lastRecordedEditMark: Int?
        let searchLayers: [SearchColorLayer]
        /// Transformed by the transaction, so undo has to put them back too.
        let temporaryMarkers: [TemporaryColorMarker]
    }

    func transactionSnapshot() -> TransactionSnapshot {
        TransactionSnapshot(
            text: textView.string,
            selections: selectionSet.ranges,
            primary: selectionSet.primaryRange,
            bookmarks: document?.bookmarks.offsets ?? [],
            markers: document?.colorMarkers.markers ?? [:],
            editMarks: document?.editMarks.offsets ?? [],
            lastRecordedEditMark: document?.editMarks.lastRecordedOffset,
            searchLayers: document?.searchColorLayers ?? [],
            temporaryMarkers: temporaryColorMarkers
        )
    }

    func registerTransactionUndo(_ snapshot: TransactionSnapshot, actionName: String) {
        guard let undoManager = textView.undoManager else { return }
        undoManager.beginUndoGrouping()
        undoManager.registerUndo(withTarget: self) { target in
            target.restoreTransactionSnapshot(snapshot, actionName: actionName)
        }
        undoManager.setActionName(actionName)
        undoManager.endUndoGrouping()
    }

    func restoreTransactionSnapshot(_ snapshot: TransactionSnapshot, actionName: String) {
        let inverse = transactionSnapshot()
        guard let storage = textView.textStorage else { return }
        storage.beginEditing()
        storage.replaceCharacters(
            in: NSRange(location: 0, length: storage.length), with: snapshot.text)
        storage.endEditing()
        document?.content = snapshot.text
        document?.bookmarks.restore(snapshot.bookmarks)
        document?.colorMarkers.restore(snapshot.markers)
        document?.editMarks.restore(
            snapshot.editMarks, lastRecorded: snapshot.lastRecordedEditMark)
        temporaryColorMarkers = snapshot.temporaryMarkers
        document?.searchColorLayers = snapshot.searchLayers
        document?.markModified()
        delegate?.editorTextDidChange(self)
        lineIndex = LineIndex(snapshot.text)
        setSelections(snapshot.selections, primaryRange: snapshot.primary)
        isMultiEditActive = snapshot.selections.count > 1
        refreshBookmarkGutter()
        rehighlightEntireDocument()
        setSelections(snapshot.selections, primaryRange: snapshot.primary)
        textView.undoManager?.registerUndo(withTarget: self) { target in
            target.restoreTransactionSnapshot(inverse, actionName: actionName)
        }
        textView.undoManager?.setActionName(actionName)
    }
}
