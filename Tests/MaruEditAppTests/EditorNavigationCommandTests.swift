import AppKit
import XCTest
@preconcurrency @testable import MaruEditApp

@preconcurrency @MainActor
final class EditorNavigationCommandTests: XCTestCase {
    private var windows: [NSWindow] = []

    override func tearDown() {
        windows.removeAll()
        super.tearDown()
    }

    private func editor(_ text: String, cursor: Int = 0) -> EditorViewController {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled], backing: .buffered, defer: true)
        let editor = EditorViewController()
        window.contentView = editor.view
        windows.append(window)
        editor.document = Document(content: text)
        editor.setSelections([NSRange(location: cursor, length: 0)])
        editor.cursorHistory.removeAll()
        return editor
    }

    func testDocumentLogicalLineAndWordNavigation() {
        let subject = editor("alpha beta\n  gamma\n", cursor: 8)
        subject.moveToDocumentStart()
        XCTAssertEqual(subject.selectionSet.primaryRange.location, 0)
        subject.moveToDocumentEnd()
        XCTAssertEqual(subject.selectionSet.primaryRange.location, 19)

        subject.setSelections([NSRange(location: 14, length: 0)])
        subject.moveToLogicalLineStart()
        XCTAssertEqual(subject.selectionSet.primaryRange.location, 11)
        subject.moveToLogicalLineEnd()
        XCTAssertEqual(subject.selectionSet.primaryRange.location, 18)
        subject.moveToWordStart()
        XCTAssertEqual(subject.selectionSet.primaryRange.location, 13)
        subject.moveWordRightSalnen()
        XCTAssertEqual(subject.selectionSet.primaryRange.location, 18)
    }

    func testConfiguredTabStopsAreUnicodeSafe() {
        let subject = editor("😀abcdef", cursor: 2)
        subject.moveToAdjacentTab(forward: true)
        XCTAssertEqual(subject.selectionSet.primaryRange.location, 4)
        subject.moveToAdjacentTab(forward: false)
        XCTAssertEqual(subject.selectionSet.primaryRange.location, 0)
    }

    func testNestedBracketBraceAndTagNavigation() {
        let brackets = editor("(a[b]c)")
        brackets.moveToMatchingBracket()
        XCTAssertEqual(brackets.selectionSet.primaryRange.location, 6)
        brackets.setSelections([NSRange(location: 2, length: 0)])
        brackets.moveToMatchingBracket()
        XCTAssertEqual(brackets.selectionSet.primaryRange.location, 4)

        let braces = editor("before { inner } after", cursor: 12)
        braces.moveToBrace(opening: true)
        XCTAssertEqual(braces.selectionSet.primaryRange.location, 7)
        braces.moveToBrace(opening: false)
        XCTAssertEqual(braces.selectionSet.primaryRange.location, 15)

        let tags = editor("<div><span>x</span><br/></div>", cursor: 5)
        tags.moveToMatchingTag()
        XCTAssertEqual(tags.selectionSet.primaryRange.location, 12)
        tags.setSelections([NSRange(location: 21, length: 0)])
        tags.moveToMatchingTag()
        XCTAssertEqual(tags.selectionSet.primaryRange.location, 21)
    }

    func testPreviousCursorAndLastEditAreDocumentLocal() {
        let subject = editor("one\ntwo\nthree")
        subject.setSelections([NSRange(location: 1, length: 0)])
        subject.setSelections([NSRange(location: 6, length: 0)])
        subject.moveToPreviousCursorPosition()
        XCTAssertEqual(subject.selectionSet.primaryRange.location, 1)

        subject.document?.editMarks.recordEdit(
            range: NSRange(location: 4, length: 0), replacement: "x",
            in: subject.textView.string as NSString)
        subject.moveToLastEditMark()
        XCTAssertEqual(subject.selectionSet.primaryRange.location, 4)

        subject.document = Document(content: "replacement")
        XCTAssertTrue(subject.cursorHistory.isEmpty)
    }

    func testVisualLineEndVariantsUseCharacterBoundary() {
        let subject = editor("abc\n", cursor: 0)
        subject.moveToLineEnd()
        XCTAssertEqual(subject.selectionSet.primaryRange.location, 2)
        subject.moveToLineEndAfterCharacter()
        XCTAssertEqual(subject.selectionSet.primaryRange.location, 3)
    }
}
