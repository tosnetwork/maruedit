import AppKit
import XCTest
@testable import MaruEditApp

final class BookmarkTests: XCTestCase {
    private var windows: [NSWindow] = []

    override func tearDown() {
        windows.removeAll()
        super.tearDown()
    }

    private func editor(_ text: String) -> EditorViewController {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled], backing: .buffered, defer: true)
        let editor = EditorViewController()
        window.contentView = editor.view
        windows.append(window)
        editor.document = Document(content: text)
        editor.textView.undoManager?.removeAllActions()
        return editor
    }

    func testToggleNavigationWrappingAndClear() {
        let subject = editor("a\nb\nc\n")
        subject.setSelections([NSRange(location: 0, length: 0)])
        subject.toggleBookmark()
        subject.setSelections([NSRange(location: 4, length: 0)])
        subject.toggleBookmark()
        XCTAssertEqual(subject.document?.bookmarks.offsets, Set([0, 4]))

        subject.nextBookmark()
        XCTAssertEqual(subject.selectionSet.primaryRange.location, 0)
        subject.previousBookmark()
        XCTAssertEqual(subject.selectionSet.primaryRange.location, 4)

        subject.clearBookmarks()
        XCTAssertTrue(subject.document?.bookmarks.offsets.isEmpty == true)
    }

    func testBookmarksAreOwnedByTheirDocument() {
        let first = editor("a\nb\n")
        let second = Document(content: "x\ny\n")
        first.toggleBookmark()
        first.document = second
        XCTAssertTrue(second.bookmarks.offsets.isEmpty)
        first.toggleBookmark()
        XCTAssertEqual(second.bookmarks.offsets, Set([0]))
    }

    func testBookmarkAnchorsMoveWithLineEditsAndUndo() {
        let subject = editor("a\nb\nc\n")
        subject.setSelections([NSRange(location: 4, length: 0)])
        subject.toggleBookmark()
        subject.setSelections([NSRange(location: 0, length: 0)])
        subject.performLineCommand(.delete)
        XCTAssertEqual(subject.document?.bookmarks.offsets, Set([2]))

        subject.textView.undoManager?.undo()
        XCTAssertEqual(subject.textView.string, "a\nb\nc\n")
        XCTAssertEqual(subject.document?.bookmarks.offsets, Set([4]))
    }

    func testTypingAtBookmarkedLineStartKeepsMarkerOnThatLine() {
        let subject = editor("a\nb\n")
        subject.setSelections([NSRange(location: 2, length: 0)])
        subject.toggleBookmark()
        subject.textView.insertText("prefix", replacementRange: NSRange(location: 2, length: 0))
        XCTAssertEqual(subject.document?.bookmarks.offsets, Set([2]))
    }
}
