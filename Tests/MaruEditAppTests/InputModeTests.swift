import XCTest
@preconcurrency @testable import MaruEditApp

@preconcurrency @MainActor
final class InputModeTests: XCTestCase {
    private var windows: [NSWindow] = []

    private func editor(_ text: String) -> EditorViewController {
        let editor = EditorViewController()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled], backing: .buffered, defer: true)
        window.contentView = editor.view
        windows.append(window)
        editor.document = Document(content: text)
        editor.textView.undoManager?.removeAllActions()
        editor.toggleInputMode()
        return editor
    }

    func testOverwriteReplacesGraphemesWithoutCrossingLineEnd() {
        let editor = editor("A😀C\nnext")
        editor.textView.setSelectedRange(NSRange(location: 1, length: 0))
        editor.textView.insertText("字", replacementRange: editor.textView.selectedRange())
        XCTAssertEqual(editor.textView.string, "A字C\nnext")

        editor.textView.setSelectedRange(NSRange(location: 3, length: 0))
        editor.textView.insertText("Z", replacementRange: editor.textView.selectedRange())
        XCTAssertEqual(editor.textView.string, "A字CZ\nnext")
    }

    func testSelectionAndNewlineKeepNormalReplacementSemantics() {
        let editor = editor("abcd")
        editor.textView.setSelectedRange(NSRange(location: 1, length: 2))
        editor.textView.insertText("X", replacementRange: editor.textView.selectedRange())
        XCTAssertEqual(editor.textView.string, "aXd")
        editor.textView.setSelectedRange(NSRange(location: 1, length: 0))
        editor.textView.insertText("\n", replacementRange: editor.textView.selectedRange())
        XCTAssertEqual(editor.textView.string, "a\nXd")
    }

    func testOverwriteIMECommitUsesSameGraphemeRuleAndSingleUndo() {
        let editor = editor("abc")
        editor.setSelections([NSRange(location: 1, length: 0)], primaryRange: NSRange(location: 1, length: 0))
        editor.beginMarkedTextComposition()
        editor.commitMarkedText("漢")
        XCTAssertEqual(editor.textView.string, "a漢c")
        editor.textView.undoManager?.undo()
        XCTAssertEqual(editor.textView.string, "abc")
    }

    func testModeIsOwnedPerDocument() {
        let first = Document(content: "a")
        let second = Document(content: "b")
        let editor = EditorViewController()
        _ = editor.view
        editor.document = first
        editor.toggleInputMode()
        editor.document = second
        XCTAssertEqual(second.inputMode, .insert)
        editor.document = first
        XCTAssertEqual(first.inputMode, .overwrite)
    }

    func testMultiCursorOverwriteIsOneUndoTransaction() {
        let editor = editor("abcde")
        editor.setSelections([
            NSRange(location: 0, length: 0), NSRange(location: 2, length: 0),
        ], primaryRange: NSRange(location: 0, length: 0))
        editor.isMultiEditActive = true
        editor.multiEditInsert("X")
        XCTAssertEqual(editor.textView.string, "XbXde")
        editor.textView.undoManager?.undo()
        XCTAssertEqual(editor.textView.string, "abcde")
    }
}
