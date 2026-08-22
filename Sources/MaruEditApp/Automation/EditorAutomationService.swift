import AppKit
import MaruEditCore

/// The one place editor semantics live for every automation surface.
///
/// The macro engine used to reach into `EditorViewController` and
/// `NSTextView` directly through `MacroCommandBridge`. Anything else wanting
/// the same operations — an agent over MCP, a future ACP adapter, a test —
/// would have had to reimplement them, and two implementations of "replace
/// every selection" is one too many.
///
/// So the semantics move here, expressed in values, and the bridges become
/// adapters. This type is `@MainActor` because it touches the editor; nothing
/// it returns is, so results can cross to a worker later without dragging
/// `Document` or AppKit along.
@MainActor
final class EditorAutomationService {
    private unowned let editor: EditorViewController

    init(editor: EditorViewController) {
        self.editor = editor
    }

    // MARK: - Identity

    var editorID: AutomationID { editor.automationID }
    var documentID: AutomationID? { editor.document?.automationID }

    // MARK: - Reading

    var revisions: DocumentRevisions { editor.document?.revisions ?? DocumentRevisions() }
    var selectionRevision: UInt64 { editor.selectionRevision }

    func documentText() -> String { editor.textView.string }

    func documentSnapshot() -> DocumentSnapshot? {
        guard let document = editor.document else { return nil }
        return DocumentSnapshot(
            documentID: document.automationID,
            displayName: document.localizedDisplayName,
            path: document.fileURL?.path,
            text: editor.textView.string,
            revisions: document.revisions,
            isDirty: document.isModified,
            isEditable: !document.isEditingDisabled,
            isSavableInPlace: !document.isEditingDisabled && !document.isOverwriteProhibited,
            contentKind: document.isBinaryMode ? .hex : .text,
            encodingName: document.encoding.displayName,
            lineEndingName: document.lineEnding.displayName,
            hasByteOrderMark: document.hasByteOrderMark)
    }

    func editorSnapshot() -> EditorSnapshot {
        EditorSnapshot(
            editorID: editor.automationID,
            documentID: editor.document?.automationID,
            selections: editor.selectionSet.ranges,
            primarySelection: editor.selectionSet.primaryRange,
            selectionRevision: editor.selectionRevision,
            isPrimaryPane: editor.reusesDocumentTextStorage)
    }

    func selections() -> [NSRange] { editor.selectionSet.ranges }

    // MARK: - Writing

    /// Replaces the whole document in one transaction.
    @discardableResult
    func setDocumentText(_ text: String, actionName: String)
        -> Result<AutomationTransactionOutcome, AutomationTransactionError> {
        let length = (editor.textView.string as NSString).length
        return editor.applyTransaction(
            [AutomationEdit(range: NSRange(location: 0, length: length), replacement: text)],
            actionName: actionName)
    }

    /// Validates and applies a selection set. Returns `false` when the ranges
    /// are empty or any of them falls outside the document, matching the
    /// contract `maru.editor.setSelections` has always had.
    @discardableResult
    func setSelections(_ ranges: [NSRange]) -> Bool {
        let length = (editor.textView.string as NSString).length
        guard !ranges.isEmpty else { return false }
        for range in ranges {
            guard range.location >= 0, range.length >= 0,
                  NSMaxRange(range) <= length else { return false }
        }
        editor.setSelections(ranges, primaryRange: ranges.first)
        return true
    }

    /// Applies the same replacement to every current selection.
    @discardableResult
    func replaceSelections(with text: String, actionName: String)
        -> Result<AutomationTransactionOutcome, AutomationTransactionError> {
        let ranges = editor.selectionSet.ranges
        guard !ranges.isEmpty else { return .failure(.empty) }
        return applyEdits(ranges.map { AutomationEdit(range: $0, replacement: text) },
                          actionName: actionName,
                          lenient: true)
    }

    /// Applies a batch.
    ///
    /// `lenient` selects the multi-cursor contract — drop ranges that no longer
    /// exist, merge overlapping ones — which macros and human multi-cursor
    /// editing have always had. Automation calls it strictly, so a batch it
    /// cannot apply exactly is refused rather than partially honoured.
    @discardableResult
    func applyEdits(
        _ edits: [AutomationEdit],
        actionName: String,
        lenient: Bool
    ) -> Result<AutomationTransactionOutcome, AutomationTransactionError> {
        guard !edits.isEmpty else { return .failure(.empty) }
        if lenient {
            editor.batchReplace(
                edits.map(\.range),
                with: edits.map(\.replacement),
                actionName: actionName)
            return .success(AutomationTransactionOutcome(
                appliedEdits: edits,
                resultingCursors: editor.selectionSet.ranges,
                revisions: revisions))
        }
        return editor.applyTransaction(edits, actionName: actionName)
    }

    // MARK: - Undo grouping

    func beginUndoGroup() {
        editor.textView.undoManager?.beginUndoGrouping()
    }

    func endUndoGroup(actionName: String) {
        editor.textView.undoManager?.endUndoGrouping()
        editor.textView.undoManager?.setActionName(actionName)
    }
}
