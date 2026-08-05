import AppKit
import MaruEditCore
import XCTest
@preconcurrency @testable import MaruEditApp

@MainActor
final class SearchParityCommandTests: XCTestCase {
    func testHighlightSelectColorAndClearUseTheActiveQuery() {
        let controller = MainWindowController()
        controller.prepareUITestDocument(content: "foo x foo y foo", selections: [])
        controller.setSearchQueryForTesting(SearchQuery(pattern: "foo"))

        controller.toggleSearchHighlight()
        XCTAssertEqual(controller.macroEditor.searchHighlightRangesForTesting.count, 3)
        controller.toggleSearchHighlight()
        XCTAssertTrue(controller.macroEditor.searchHighlightRangesForTesting.isEmpty)

        controller.colorAllSearchMatches()
        XCTAssertEqual(controller.macroEditor.searchHighlightRangesForTesting.count, 3)
        controller.clearSearchColors()
        XCTAssertTrue(controller.macroEditor.searchHighlightRangesForTesting.isEmpty)

        controller.selectAllSearchMatches()
        XCTAssertEqual(controller.macroEditor.textView.selectedRanges.map(\.rangeValue), [
            NSRange(location: 0, length: 3), NSRange(location: 6, length: 3),
            NSRange(location: 12, length: 3),
        ])
    }

    func testExplicitSearchRangeConstrainsCommandsAndCanBeReselectedAndCleared() {
        let controller = MainWindowController()
        controller.prepareUITestDocument(
            content: "foo x foo y foo", selections: [NSRange(location: 5, length: 5)])
        controller.setSearchRangeFromSelection()
        controller.setSearchQueryForTesting(SearchQuery(pattern: "foo"))
        controller.toggleSearchHighlight()
        XCTAssertEqual(controller.macroEditor.searchHighlightRangesForTesting,
                       [NSRange(location: 6, length: 3)])

        controller.macroEditor.setSelections([NSRange(location: 0, length: 0)])
        controller.selectSearchRange()
        XCTAssertEqual(controller.macroEditor.selectionSet.primaryRange,
                       NSRange(location: 5, length: 5))
        controller.clearSearchRange()
        controller.clearSearchColors()
        controller.toggleSearchHighlight()
        XCTAssertEqual(controller.macroEditor.searchHighlightRangesForTesting.count, 3)
    }

    func testReturnToSearchStartRestoresOpeningCaret() {
        let controller = MainWindowController()
        controller.prepareUITestDocument(
            content: "zero one two", selections: [NSRange(location: 5, length: 0)])
        controller.showFind()
        controller.macroEditor.setSelections([NSRange(location: 9, length: 0)])
        controller.returnToSearchStart()
        XCTAssertEqual(controller.macroEditor.selectionSet.primaryRange.location, 5)
    }

    func testFindWordAndCaptureSearchStringUseNativeCursorWord() {
        let controller = MainWindowController()
        controller.prepareUITestDocument(
            content: "cat scatter cat", selections: [NSRange(location: 1, length: 0)])
        controller.findWordAtCursor()
        XCTAssertEqual(controller.currentSearchQueryForTesting?.pattern, "cat")
        XCTAssertTrue(controller.currentSearchQueryForTesting?.wholeWord == true)
        XCTAssertEqual(controller.macroEditor.selectionSet.primaryRange, NSRange(location: 12, length: 3))

        controller.macroEditor.setSelections(
            [NSRange(location: 4, length: 7)], primaryRange: NSRange(location: 4, length: 7))
        controller.captureSearchStringAtCursor()
        XCTAssertEqual(controller.currentSearchQueryForTesting?.pattern, "scatter")
        XCTAssertFalse(controller.currentSearchQueryForTesting?.wholeWord == true)
        XCTAssertEqual(controller.macroEditor.selectionSet.primaryRange, NSRange(location: 4, length: 7),
                       "capturing must not execute a search or move the selection")
    }
}
