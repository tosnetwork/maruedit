import AppKit

/// Text view boundary for committed text versus IME marked text.
/// Marked text is left entirely to AppKit at the primary selection;
/// only `insertText` (the committed result) is replicated.
final class MaruTextView: NSTextView {
    weak var selectionOwner: EditorViewController?

    override func setMarkedText(
        _ string: Any,
        selectedRange: NSRange,
        replacementRange: NSRange
    ) {
        selectionOwner?.beginMarkedTextComposition()
        super.setMarkedText(string, selectedRange: selectedRange, replacementRange: replacementRange)
    }

    override func insertText(_ insertString: Any, replacementRange: NSRange) {
        let text: String
        if let attributed = insertString as? NSAttributedString { text = attributed.string }
        else if let plain = insertString as? String { text = plain }
        else { text = String(describing: insertString) }

        if selectionOwner?.hasMarkedTextComposition == true {
            // Let AppKit close its marked-text session, but keep that
            // transient primary-only mutation out of Undo. The owner then
            // restores the pre-composition snapshot and commits once to all
            // selections as one transaction.
            undoManager?.disableUndoRegistration()
            super.insertText(insertString, replacementRange: replacementRange)
            undoManager?.enableUndoRegistration()
            selectionOwner?.commitMarkedText(text)
        } else if selectionOwner?.isMultiEditActive == true {
            selectionOwner?.multiEditInsert(text)
        } else {
            super.insertText(insertString, replacementRange: replacementRange)
        }
    }

    override func cancelOperation(_ sender: Any?) {
        let wasComposing = hasMarkedText() || selectionOwner?.hasMarkedTextComposition == true
        super.cancelOperation(sender)
        if wasComposing { selectionOwner?.cancelMarkedTextComposition() }
    }
}
