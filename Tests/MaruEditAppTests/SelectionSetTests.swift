import XCTest
@testable import MaruEditApp

final class SelectionSetTests: XCTestCase {
    func testNormalizesSortsDeduplicatesAndMergesOverlaps() {
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

    func testAdjacentSelectionsRemainDistinct() {
        let set = SelectionSet(ranges: [
            NSRange(location: 0, length: 2),
            NSRange(location: 2, length: 2),
        ])
        XCTAssertEqual(set.ranges.count, 2)
    }

    func testPrimarySelectionSurvivesSorting() {
        let primary = NSRange(location: 20, length: 2)
        let set = SelectionSet(ranges: [primary, NSRange(location: 2, length: 1)], primaryIndex: 0)
        set.update(ranges: [primary, NSRange(location: 2, length: 1)], primaryRange: primary)
        XCTAssertEqual(set.primaryRange, primary)
        XCTAssertEqual(set.primaryIndex, 1)
    }

    func testEmptyInputFallsBackToOneInsertionPoint() {
        let set = SelectionSet(ranges: [])
        XCTAssertEqual(set.ranges, [NSRange(location: 0, length: 0)])
        XCTAssertEqual(set.primaryIndex, 0)
    }

    func testEditorAndTextViewSynchronizeInBothDirections() {
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

    func testTwoEditorsOwnIndependentSelectionSets() {
        let first = EditorViewController()
        let second = EditorViewController()
        first.setSelections([NSRange(location: 5, length: 0)])
        XCTAssertEqual(first.selectionSet.primaryRange.location, 5)
        XCTAssertEqual(second.selectionSet.primaryRange.location, 0)
    }

    func testSwitchingDocumentsResetsMultiSelectionToDocumentsCursor() {
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
}
