import AppKit
import XCTest
@testable import MaruEditApp

final class CJKIMETests: XCTestCase {
    private var windows: [NSWindow] = []

    override func tearDown() {
        windows.removeAll()
        super.tearDown()
    }

    private func editor() -> EditorViewController {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled], backing: .buffered, defer: true)
        let editor = EditorViewController()
        window.contentView = editor.view
        windows.append(window)
        editor.textView.string = "aa aa"
        editor.textView.undoManager?.removeAllActions()
        editor.setSelections([
            NSRange(location: 0, length: 2), NSRange(location: 3, length: 2),
        ], primaryRange: NSRange(location: 0, length: 2))
        editor.isMultiEditActive = true
        return editor
    }

    func testMarkedTextStaysAtPrimaryThenCommitReplicatesFinalText() {
        let editor = editor()
        editor.textView.setMarkedText(
            "に", selectedRange: NSRange(location: 1, length: 0),
            replacementRange: NSRange(location: 0, length: 2))

        XCTAssertEqual(editor.textView.string, "に aa")
        XCTAssertEqual(editor.selectionSet.ranges, [
            NSRange(location: 0, length: 2), NSRange(location: 3, length: 2),
        ], "marked-text updates must not rewrite logical secondary selections")

        editor.textView.insertText("日本", replacementRange: editor.textView.markedRange())
        XCTAssertEqual(editor.textView.string, "日本 日本")
        XCTAssertEqual(editor.selectionSet.ranges.count, 2)

        editor.textView.undoManager?.undo()
        XCTAssertEqual(editor.textView.string, "aa aa", "one Undo reverses one committed composition")
    }

    func testCancellingCompositionRestoresTextAndSecondarySelections() {
        let editor = editor()
        let original = editor.selectionSet.ranges
        editor.textView.setMarkedText(
            "中", selectedRange: NSRange(location: 1, length: 0),
            replacementRange: NSRange(location: 0, length: 2))
        editor.cancelMarkedTextComposition()

        XCTAssertEqual(editor.textView.string, "aa aa")
        XCTAssertEqual(editor.selectionSet.ranges, original)
        XCTAssertTrue(editor.isMultiEditActive)
    }

    func testOrdinaryCommittedTextUsesTheSameCommitBoundary() {
        let editor = editor()
        editor.textView.insertText("語", replacementRange: NSRange(location: 0, length: 2))
        XCTAssertEqual(editor.textView.string, "語 語")
    }
}
