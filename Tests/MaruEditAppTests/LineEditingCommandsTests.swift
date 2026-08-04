import AppKit
import MaruEditCore
import XCTest
@testable import MaruEditApp

final class LineEditingCommandsTests: XCTestCase {
    private var windows: [NSWindow] = []

    override func tearDown() {
        windows.removeAll()
        super.tearDown()
    }

    private func editor(
        _ text: String,
        ranges: [NSRange] = [NSRange(location: 0, length: 0)],
        language: Language = .plainText
    ) -> EditorViewController {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled], backing: .buffered, defer: true)
        let editor = EditorViewController()
        window.contentView = editor.view
        windows.append(window)
        editor.document = Document(content: text, language: language)
        editor.textView.undoManager?.removeAllActions()
        editor.setSelections(ranges, primaryRange: ranges.first)
        return editor
    }

    func testDeleteLineSupportsCaretAndMultipleSelectionsWithOneUndo() {
        let editor = editor("a\nb\nc\n", ranges: [
            NSRange(location: 0, length: 0), NSRange(location: 4, length: 0),
        ])
        editor.performLineCommand(.delete)
        XCTAssertEqual(editor.textView.string, "b\n")
        editor.textView.undoManager?.undo()
        XCTAssertEqual(editor.textView.string, "a\nb\nc\n")
    }

    func testDuplicateAndMoveLineCommands() {
        let duplicate = editor("a\nb\n", ranges: [NSRange(location: 2, length: 0)])
        duplicate.performLineCommand(.duplicate)
        XCTAssertEqual(duplicate.textView.string, "a\nb\nb\n")

        let up = editor("a\nb\nc\n", ranges: [NSRange(location: 2, length: 0)])
        up.performLineCommand(.moveUp)
        XCTAssertEqual(up.textView.string, "b\na\nc\n")

        let down = editor("a\nb\nc\n", ranges: [NSRange(location: 2, length: 0)])
        down.performLineCommand(.moveDown)
        XCTAssertEqual(down.textView.string, "a\nc\nb\n")
    }

    func testJoinAndTrimTrailingWhitespace() {
        let join = editor("alpha  \n  beta\ngamma\n")
        join.performLineCommand(.join)
        XCTAssertEqual(join.textView.string, "alpha beta\ngamma\n")

        let trim = editor("a  \n b\t\n")
        trim.performLineCommand(.trimTrailingWhitespace)
        XCTAssertEqual(trim.textView.string, "a\n b\n")
    }

    func testCaseConversionHonorsMultipleExactSelections() {
        let upper = editor("aa bb", ranges: [
            NSRange(location: 0, length: 2), NSRange(location: 3, length: 2),
        ])
        upper.performLineCommand(.uppercase)
        XCTAssertEqual(upper.textView.string, "AA BB")
        upper.performLineCommand(.lowercase)
        XCTAssertEqual(upper.textView.string, "aa bb")
    }

    func testSortAndReverseLines() {
        let sort = editor("c\na\nb\n")
        sort.performLineCommand(.sort)
        XCTAssertEqual(sort.textView.string, "a\nb\nc\n")

        let reverse = editor("a\nb\nc\n")
        reverse.performLineCommand(.reverse)
        XCTAssertEqual(reverse.textView.string, "c\nb\na\n")
    }

    func testIndentOutdentAndToggleComment() {
        let indent = editor("a\n  b\n", ranges: [NSRange(location: 0, length: 5)])
        indent.performLineCommand(.indent)
        XCTAssertEqual(indent.textView.string, "\ta\n\t  b\n")
        indent.performLineCommand(.outdent)
        XCTAssertEqual(indent.textView.string, "a\n  b\n")

        let comment = editor(
            "  let a = 1\nlet b = 2\n",
            ranges: [NSRange(location: 0, length: 22)], language: .swift)
        comment.performLineCommand(.toggleComment)
        XCTAssertEqual(comment.textView.string, "  // let a = 1\n// let b = 2\n")
        comment.performLineCommand(.toggleComment)
        XCTAssertEqual(comment.textView.string, "  let a = 1\nlet b = 2\n")
    }

    func testGoToLineAndColumnClampsToLineEnd() {
        let editor = editor("abc\nx\nlast")
        editor.goTo(line: 2, column: 9)
        XCTAssertEqual(editor.selectionSet.primaryRange, NSRange(location: 5, length: 0))
        editor.goTo(line: 3, column: 3)
        XCTAssertEqual(editor.selectionSet.primaryRange, NSRange(location: 8, length: 0))
    }

    func testEveryMutatingLineCommandPreservesValidSelectionsAndUsesOneUndoStep() {
        let cases: [(LineEditCommand, String, NSRange, Language)] = [
            (.delete, "c\nb\na\n", NSRange(location: 2, length: 0), .plainText),
            (.duplicate, "c\nb\na\n", NSRange(location: 2, length: 0), .plainText),
            (.moveUp, "c\nb\na\n", NSRange(location: 2, length: 0), .plainText),
            (.moveDown, "c\nb\na\n", NSRange(location: 2, length: 0), .plainText),
            (.join, "c\nb\na\n", NSRange(location: 0, length: 0), .plainText),
            (.trimTrailingWhitespace, "c  \nb\ta\n", NSRange(location: 0, length: 0), .plainText),
            (.uppercase, "c\nb\na\n", NSRange(location: 0, length: 1), .plainText),
            (.lowercase, "C\nb\na\n", NSRange(location: 0, length: 1), .plainText),
            (.sort, "c\nb\na\n", NSRange(location: 0, length: 6), .plainText),
            (.reverse, "c\nb\na\n", NSRange(location: 0, length: 6), .plainText),
            (.indent, "c\nb\na\n", NSRange(location: 0, length: 4), .plainText),
            (.outdent, "\tc\n\tb\n", NSRange(location: 0, length: 5), .plainText),
            (.toggleComment, "c\nb\na\n", NSRange(location: 0, length: 4), .swift),
        ]

        for (command, original, range, language) in cases {
            let subject = editor(original, ranges: [range], language: language)
            subject.performLineCommand(command)
            XCTAssertNotEqual(subject.textView.string, original, "\(command) should edit text")
            let editedLength = (subject.textView.string as NSString).length
            XCTAssertTrue(subject.selectionSet.ranges.allSatisfy { NSMaxRange($0) <= editedLength })
            subject.textView.undoManager?.undo()
            XCTAssertEqual(subject.textView.string, original, "\(command) should undo in one step")
        }
    }
}
