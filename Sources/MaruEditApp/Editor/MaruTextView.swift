import AppKit

/// Text view boundary for committed text versus IME marked text.
/// Marked text is left entirely to AppKit at the primary selection;
/// only `insertText` (the committed result) is replicated.
final class MaruTextView: NSTextView {
    weak var selectionOwner: EditorViewController?
    private var isDraggingColumn = false
    private var isCancellingComposition = false
    private var isFinalizingThroughInsertText = false

    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.option) {
            isDraggingColumn = true
            selectionOwner?.beginColumnSelection(atUTF16Offset: characterIndexForInsertion(at: convert(event.locationInWindow, from: nil)))
            return
        }
        selectionOwner?.cancelColumnSelection()
        super.mouseDown(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        guard isDraggingColumn else { super.mouseDragged(with: event); return }
        selectionOwner?.updateColumnSelection(toUTF16Offset: characterIndexForInsertion(at: convert(event.locationInWindow, from: nil)))
    }

    override func mouseUp(with event: NSEvent) {
        if isDraggingColumn {
            isDraggingColumn = false
            selectionOwner?.endColumnSelection()
            return
        }
        super.mouseUp(with: event)
    }

    override func setMarkedText(
        _ string: Any,
        selectedRange: NSRange,
        replacementRange: NSRange
    ) {
        selectionOwner?.beginMarkedTextComposition()
        super.setMarkedText(string, selectedRange: selectedRange, replacementRange: replacementRange)
        // Kotoeri can end marking internally after its final setMarkedText
        // call without dispatching insertText/unmarkText to this subclass.
        // Check once the input-method callback stack has unwound.
        DispatchQueue.main.async { [weak selectionOwner] in
            selectionOwner?.finalizeCompositionIfUnmarked()
        }
    }

    /// Some system input methods (including current Japanese Kotoeri) commit
    /// through the legacy one-argument NSTextInput entry point. Keep it in
    /// lockstep with the replacement-range variant below.
    override func insertText(_ insertString: Any) {
        let replacementRange = hasMarkedText() ? markedRange() : selectedRange()
        guard selectionOwner?.hasMarkedTextComposition == true else {
            insertText(insertString, replacementRange: replacementRange)
            return
        }

        let text = committedString(from: insertString)
        undoManager?.disableUndoRegistration()
        isFinalizingThroughInsertText = true
        super.insertText(insertString, replacementRange: replacementRange)
        isFinalizingThroughInsertText = false
        undoManager?.enableUndoRegistration()

        // The legacy NSTextInput entry point is invoked inside an AppKit-owned
        // Undo grouping. Defer our logical multi-selection transaction until
        // that outer group closes, or its transient primary edit can become
        // interleaved with the single composition Undo step.
        DispatchQueue.main.async { [weak selectionOwner] in
            selectionOwner?.commitMarkedText(text)
        }
    }

    override func insertText(_ insertString: Any, replacementRange: NSRange) {
        let text = committedString(from: insertString)

        if selectionOwner?.hasMarkedTextComposition == true {
            // Let AppKit close its marked-text session, but keep that
            // transient primary-only mutation out of Undo. The owner then
            // restores the pre-composition snapshot and commits once to all
            // selections as one transaction.
            undoManager?.disableUndoRegistration()
            isFinalizingThroughInsertText = true
            super.insertText(insertString, replacementRange: replacementRange)
            isFinalizingThroughInsertText = false
            undoManager?.enableUndoRegistration()
            selectionOwner?.commitMarkedText(text)
        } else if selectionOwner?.isMultiEditActive == true {
            selectionOwner?.multiEditInsert(text)
        } else {
            super.insertText(insertString, replacementRange: replacementRange)
        }
    }

    private func committedString(from value: Any) -> String {
        if let attributed = value as? NSAttributedString { return attributed.string }
        if let plain = value as? String { return plain }
        return String(describing: value)
    }

    override func unmarkText() {
        guard !isCancellingComposition,
              !isFinalizingThroughInsertText,
              selectionOwner?.hasMarkedTextComposition == true,
              let storage = textStorage else {
            super.unmarkText()
            return
        }
        let range = markedRange()
        guard range.location != NSNotFound, NSMaxRange(range) <= storage.length else {
            super.unmarkText()
            return
        }
        let committed = storage.attributedSubstring(from: range).string
        super.unmarkText()
        DispatchQueue.main.async { [weak selectionOwner] in
            selectionOwner?.commitMarkedText(committed)
        }
    }

    /// Deterministic coverage for IMEs that ask TextKit to end marking
    /// without dispatching through this subclass's public callback.
    func systemUnmarkForTesting() { super.unmarkText() }

    override func cancelOperation(_ sender: Any?) {
        let wasComposing = hasMarkedText() || selectionOwner?.hasMarkedTextComposition == true
        guard wasComposing else {
            selectionOwner?.exitMultiEdit()
            return
        }
        isCancellingComposition = true
        isCancellingComposition = false
        DispatchQueue.main.async { [weak selectionOwner] in
            selectionOwner?.cancelMarkedTextComposition()
        }
    }
}
