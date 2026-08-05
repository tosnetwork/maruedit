import XCTest
@preconcurrency @testable import MaruEditApp


@preconcurrency @MainActor
final class SelectionSetTests: XCTestCase {
    func testClassicWordLineParagraphSelectionsAndQuotedClipboard() async {
        let editor = EditorViewController(); _ = editor.view
        editor.document = Document(content: "alpha beta\nsecond line\n\nthird")
        editor.setSelections([NSRange(location: 2, length: 0)], primaryRange: NSRange(location: 2, length: 0))
        editor.selectCurrentWord()
        XCTAssertEqual(editor.selectionSet.primaryRange, NSRange(location: 0, length: 5))
        editor.selectCurrentLine()
        XCTAssertEqual(editor.selectionSet.primaryRange, NSRange(location: 0, length: 11))
        editor.setSelections([NSRange(location: 12, length: 0)], primaryRange: NSRange(location: 12, length: 0))
        editor.selectCurrentParagraph()
        XCTAssertEqual((editor.textView.string as NSString).substring(with: editor.selectionSet.primaryRange), "second line\n")

        let pasteboard = NSPasteboard(name: .init("SelectionSetTests.quoted"))
        editor.setSelections([NSRange(location: 0, length: 10)], primaryRange: NSRange(location: 0, length: 10))
        XCTAssertTrue(editor.copyWithQuotePrefix(to: pasteboard))
        XCTAssertEqual(pasteboard.string(forType: .string), "> alpha beta")
        pasteboard.clearContents(); pasteboard.setString("> one\n> two\nplain", forType: .string)
        editor.setSelections([NSRange(location: 0, length: 5)], primaryRange: NSRange(location: 0, length: 5))
        XCTAssertTrue(editor.pasteRemovingQuotePrefix(from: pasteboard))
        XCTAssertTrue(editor.textView.string.hasPrefix("one\ntwo\nplain"))
    }
    func testNormalizesSortsDeduplicatesAndMergesOverlaps() async {
        let set = SelectionSet(ranges: [
            NSRange(location: 10, length: 3),
            NSRange(location: 2, length: 4),
            NSRange(location: 4, length: 4),
            NSRange(location: 10, length: 3),
        ])
        XCTAssertEqual(set.ranges, [
            NSRange(location: 2, length: 6),
            NSRange(location: 10, length: 3),
        ])
    }

    func testAdjacentSelectionsRemainDistinct() async {
        let set = SelectionSet(ranges: [
            NSRange(location: 0, length: 2),
            NSRange(location: 2, length: 2),
        ])
        XCTAssertEqual(set.ranges.count, 2)
    }

    func testPrimarySelectionSurvivesSorting() async {
        let primary = NSRange(location: 20, length: 2)
        let set = SelectionSet(ranges: [primary, NSRange(location: 2, length: 1)], primaryIndex: 0)
        set.update(ranges: [primary, NSRange(location: 2, length: 1)], primaryRange: primary)
        XCTAssertEqual(set.primaryRange, primary)
        XCTAssertEqual(set.primaryIndex, 1)
    }

    func testEmptyInputFallsBackToOneInsertionPoint() async {
        let set = SelectionSet(ranges: [])
        XCTAssertEqual(set.ranges, [NSRange(location: 0, length: 0)])
        XCTAssertEqual(set.primaryIndex, 0)
    }

    func testEditorAndTextViewSynchronizeInBothDirections() async {
        let editor = EditorViewController()
        editor.loadView()
        let programmatic = [NSRange(location: 0, length: 1), NSRange(location: 2, length: 1)]
        editor.textView.string = "abcd"
        editor.setSelections(programmatic, primaryRange: programmatic[1])
        XCTAssertEqual(editor.textView.selectedRanges.map(\.rangeValue), programmatic)
        XCTAssertEqual(editor.selectionSet.primaryRange, programmatic[1])

        let fromTextView = [NSValue(range: NSRange(location: 1, length: 1))]
        editor.textView.setSelectedRanges(fromTextView, affinity: .downstream, stillSelecting: false)
        editor.textViewDidChangeSelection(Notification(name: NSTextView.didChangeSelectionNotification))
        XCTAssertEqual(editor.selectionSet.ranges, [NSRange(location: 1, length: 1)])
    }

    func testTwoEditorsOwnIndependentSelectionSets() async {
        let first = EditorViewController()
        let second = EditorViewController()
        first.setSelections([NSRange(location: 5, length: 0)])
        XCTAssertEqual(first.selectionSet.primaryRange.location, 5)
        XCTAssertEqual(second.selectionSet.primaryRange.location, 0)
    }

    func testSwitchingDocumentsResetsMultiSelectionToDocumentsCursor() async {
        let editor = EditorViewController()
        editor.loadView()
        let first = Document(content: "first document")
        let second = Document(content: "second document")
        second.cursorPosition = 6

        editor.document = first
        editor.isMultiEditActive = true
        editor.setSelections([NSRange(location: 0, length: 2), NSRange(location: 6, length: 2)])
        editor.document = second

        XCTAssertFalse(editor.isMultiEditActive)
        XCTAssertEqual(editor.selectionSet.ranges, [NSRange(location: 6, length: 0)])
        XCTAssertEqual(editor.textView.selectedRange(), NSRange(location: 6, length: 0))
    }

    func testCursorBelowPreservesColumnAndClampsToShortLine() async {
        let editor = EditorViewController()
        editor.loadView()
        editor.textView.string = "abc\nx\nabcdef"
        editor.setSelections([NSRange(location: 2, length: 0)])
        editor.addCursorBelow()
        XCTAssertEqual(editor.selectionSet.ranges, [
            NSRange(location: 2, length: 0), NSRange(location: 5, length: 0),
        ])
        XCTAssertEqual(editor.selectionSet.primaryRange, NSRange(location: 2, length: 0))
    }

    func testSelectNextOccurrenceAndUndoLastAddedCursor() async {
        let editor = EditorViewController()
        editor.loadView()
        editor.textView.string = "foo foo foo"
        editor.setSelections([NSRange(location: 0, length: 3)])
        editor.selectNextOccurrence()
        XCTAssertEqual(editor.selectionSet.ranges, [
            NSRange(location: 0, length: 3), NSRange(location: 4, length: 3),
        ])
        editor.undoLastAddedCursor()
        XCTAssertEqual(editor.selectionSet.ranges, [NSRange(location: 0, length: 3)])
    }

    func testSelectAllOccurrencesAndEscapeCollapseToPrimary() async {
        let editor = EditorViewController()
        editor.loadView()
        editor.textView.string = "foo foo foo"
        editor.setSelections([NSRange(location: 4, length: 3)], primaryRange: NSRange(location: 4, length: 3))
        editor.selectAllOccurrences()
        XCTAssertEqual(editor.selectionSet.ranges.count, 3)
        XCTAssertEqual(editor.selectionSet.primaryRange, NSRange(location: 4, length: 3))
        editor.exitMultiEdit()
        XCTAssertEqual(editor.selectionSet.ranges, [NSRange(location: 4, length: 3)])
    }

    func testAppendCopyAndCutPreserveExistingClipboard() {
        let editor = EditorViewController(); _ = editor.view
        editor.textView.string = "one two"
        editor.setSelections([NSRange(location: 4, length: 3)])
        let pasteboard = NSPasteboard(name: .init("SelectionSetTests.append"))
        pasteboard.clearContents(); pasteboard.setString("prefix:", forType: .string)
        XCTAssertTrue(editor.appendSelectionToClipboard(cut: false, pasteboard: pasteboard))
        XCTAssertEqual(pasteboard.string(forType: .string), "prefix:two")
        XCTAssertEqual(editor.textView.string, "one two")
        XCTAssertTrue(editor.appendSelectionToClipboard(cut: true, pasteboard: pasteboard))
        XCTAssertEqual(pasteboard.string(forType: .string), "prefix:twotwo")
        XCTAssertEqual(editor.textView.string, "one ")
    }

    func testDeleteToLineBoundariesAcrossMultipleCursors() {
        let editor = EditorViewController(); _ = editor.view
        editor.textView.string = "abcde\n12345"
        editor.setSelections([NSRange(location: 2, length: 0), NSRange(location: 9, length: 0)])
        editor.deleteToLineStart()
        XCTAssertEqual(editor.textView.string, "cde\n45")

        editor.textView.string = "abcde\n12345"
        editor.setSelections([NSRange(location: 2, length: 0), NSRange(location: 9, length: 0)])
        editor.deleteToLineEnd()
        XCTAssertEqual(editor.textView.string, "ab\n123")
    }

    func testInvertReserveAndRestoreSelections() {
        let editor = EditorViewController(); _ = editor.view
        editor.textView.string = "0123456789"
        editor.setSelections([NSRange(location: 2, length: 2), NSRange(location: 6, length: 2)])
        editor.invertSelections()
        XCTAssertEqual(editor.selectionSet.ranges, [
            NSRange(location: 0, length: 2), NSRange(location: 4, length: 2),
            NSRange(location: 8, length: 2),
        ])
        editor.reserveSelections()
        XCTAssertEqual(editor.reservedSelections.count, 3)
        editor.setSelections([NSRange(location: 3, length: 1)])
        editor.restoreReservedSelections()
        XCTAssertTrue(editor.reservedSelections.isEmpty)
        XCTAssertEqual(editor.selectionSet.ranges.count, 4)
        XCTAssertEqual(editor.selectionSet.primaryRange, NSRange(location: 3, length: 1))
    }
}
