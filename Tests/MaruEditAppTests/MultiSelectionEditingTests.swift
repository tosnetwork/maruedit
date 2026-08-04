import XCTest
@preconcurrency @testable import MaruEditApp


@preconcurrency @MainActor
final class MultiSelectionEditingTests: XCTestCase {
    private var windows: [NSWindow] = []

    override func tearDown() {
        windows.removeAll()
        super.tearDown()
    }

    private func editor(_ text: String, ranges: [NSRange]) -> EditorViewController {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled], backing: .buffered, defer: true
        )
        let editor = EditorViewController()
        window.contentView = editor.view
        windows.append(window)
        editor.textView.string = text
        editor.textView.undoManager?.removeAllActions()
        editor.setSelections(ranges, primaryRange: ranges.first)
        editor.isMultiEditActive = ranges.count > 1
        return editor
    }

    func testInsertAppliesFromEndAndLeavesOneCursorPerEdit() async {
        let editor = editor("ab cd", ranges: [
            NSRange(location: 0, length: 0), NSRange(location: 3, length: 0),
        ])
        editor.multiEditInsert("X")
        XCTAssertEqual(editor.textView.string, "Xab Xcd")
        XCTAssertEqual(editor.selectionSet.ranges, [
            NSRange(location: 1, length: 0), NSRange(location: 5, length: 0),
        ])
    }

    func testDeleteSelectionsAndBackspaceCursors() async {
        let selected = editor("ab cd", ranges: [
            NSRange(location: 0, length: 2), NSRange(location: 3, length: 2),
        ])
        selected.multiEditForwardDelete()
        XCTAssertEqual(selected.textView.string, " ")

        let cursors = editor("ab cd", ranges: [
            NSRange(location: 2, length: 0), NSRange(location: 5, length: 0),
        ])
        cursors.multiEditBackspace()
        XCTAssertEqual(cursors.textView.string, "a c")
        XCTAssertEqual(cursors.selectionSet.ranges, [
            NSRange(location: 1, length: 0), NSRange(location: 3, length: 0),
        ])
    }

    func testPasteMapsEqualFragmentCountOrRepeatsWholeClipboard() async {
        let mapped = editor("ab cd", ranges: [
            NSRange(location: 0, length: 2), NSRange(location: 3, length: 2),
        ])
        mapped.multiEditPaste("ONE\nTWO")
        XCTAssertEqual(mapped.textView.string, "ONE TWO")

        let repeated = editor("ab cd", ranges: [
            NSRange(location: 0, length: 2), NSRange(location: 3, length: 2),
        ])
        repeated.multiEditPaste("Z")
        XCTAssertEqual(repeated.textView.string, "Z Z")
    }

    func testOneUndoAndRedoRestoreTextAndSelections() async {
        let original = [NSRange(location: 0, length: 2), NSRange(location: 3, length: 2)]
        let editor = editor("ab cd", ranges: original)
        editor.multiEditInsert("word")
        let editedSelections = editor.selectionSet.ranges
        XCTAssertEqual(editor.textView.string, "word word")

        editor.textView.undoManager?.undo()
        XCTAssertEqual(editor.textView.string, "ab cd")
        XCTAssertEqual(editor.selectionSet.ranges, original)

        editor.textView.undoManager?.redo()
        XCTAssertEqual(editor.textView.string, "word word")
        XCTAssertEqual(editor.selectionSet.ranges, editedSelections)
    }

    func testOverlapsMergeAndEarliestReplacementWins() async {
        let editor = editor("abcdef", ranges: [NSRange(location: 0, length: 1)])
        editor.batchReplace(
            [NSRange(location: 0, length: 3), NSRange(location: 2, length: 3)],
            with: ["X", "Y"]
        )
        XCTAssertEqual(editor.textView.string, "Xf")
        XCTAssertEqual(editor.selectionSet.ranges, [NSRange(location: 1, length: 0)])
    }

    func testHighlightingDoesNotClearLogicalCursors() async {
        let editor = editor("let a = 1\nlet b = 2", ranges: [
            NSRange(location: 4, length: 1), NSRange(location: 14, length: 1),
        ])
        editor.multiEditInsert("name")
        XCTAssertEqual(editor.selectionSet.ranges.count, 2)
        XCTAssertTrue(editor.isMultiEditActive)
    }
}
