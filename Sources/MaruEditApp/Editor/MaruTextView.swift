import AppKit
import MaruEditCore

/// Text view boundary for committed text versus IME marked text.
/// Marked text is left entirely to AppKit at the primary selection;
/// only `insertText` (the committed result) is replicated.
final class MaruTextView: NSTextView {
    static let invisibleMarkerLargeFileThreshold = 100_000
    weak var selectionOwner: EditorViewController?
    var invisibleCharacters: InvisibleCharacterOptions = .none {
        didSet { needsDisplay = true }
    }
    var usesHighContrastMarkers = false {
        didSet { needsDisplay = true }
    }
    var isInvisibleRenderingSuppressedForLargeFile: Bool {
        (textStorage?.length ?? 0) > Self.invisibleMarkerLargeFileThreshold
    }
    private var isDraggingColumn = false
    private var isCancellingComposition = false
    private var isFinalizingThroughInsertText = false

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        drawInvisibleMarkers(in: dirtyRect)
    }

    private func drawInvisibleMarkers(in dirtyRect: NSRect) {
        guard invisibleCharacters != .none,
              !isInvisibleRenderingSuppressedForLargeFile,
              let storage = textStorage, storage.length > 0,
              let layoutManager, let textContainer else { return }
        let containerRect = dirtyRect.offsetBy(
            dx: -textContainerOrigin.x, dy: -textContainerOrigin.y)
        let glyphs = layoutManager.glyphRange(forBoundingRect: containerRect, in: textContainer)
        let characters = layoutManager.characterRange(
            forGlyphRange: glyphs, actualGlyphRange: nil)
        let string = storage.string as NSString
        let color = usesHighContrastMarkers
            ? NSColor.white.withAlphaComponent(0.9) : Theme.gutterText
        let markerFont = font ?? Theme.editorFont
        let attributes: [NSAttributedString.Key: Any] = [
            .font: markerFont,
            .foregroundColor: color,
        ]
        let end = min(string.length, NSMaxRange(characters))
        guard characters.location < end else { return }
        for index in characters.location..<end {
            guard let marker = Self.marker(
                forUTF16CodeUnit: string.character(at: index), options: invisibleCharacters)
            else { continue }
            let glyph = layoutManager.glyphIndexForCharacter(at: index)
            guard glyph < layoutManager.numberOfGlyphs else { continue }
            let fragment = layoutManager.lineFragmentRect(
                forGlyphAt: glyph, effectiveRange: nil, withoutAdditionalLayout: true)
            let location = layoutManager.location(forGlyphAt: glyph)
            let point = NSPoint(
                x: textContainerOrigin.x + fragment.minX + location.x,
                y: textContainerOrigin.y + fragment.minY
                    + max(0, (fragment.height - markerFont.pointSize) / 2))
            marker.draw(at: point, withAttributes: attributes)
        }
    }

    static func marker(
        forUTF16CodeUnit codeUnit: unichar, options: InvisibleCharacterOptions
    ) -> String? {
        switch codeUnit {
        case 0x20 where options.spaces: "·"
        case 0x09 where options.tabs: "→"
        case 0x0A where options.lineEndings: "¶"
        case 0x3000 where options.fullWidthSpaces: "□"
        default: nil
        }
    }

    override func changeFont(_ sender: Any?) {
        guard let manager = sender as? NSFontManager else {
            super.changeFont(sender)
            return
        }
        selectionOwner?.changeEditorFont(using: manager)
    }

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
