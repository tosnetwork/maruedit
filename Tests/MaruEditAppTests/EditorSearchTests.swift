import XCTest
import AppKit
import MaruEditCore
@testable import MaruEditApp

/// Covers the editor-side glue between `SearchEngine` and the text view
/// (ROADMAP.md M3-02). Uses a real, window-less `EditorViewController`;
/// nothing here opens a panel or an alert.
final class EditorSearchTests: XCTestCase {

    private func makeEditor(_ text: String) -> EditorViewController {
        let vc = EditorViewController()
        _ = vc.view // force loadView so textView exists
        vc.textView.string = text
        return vc
    }

    func testFindNextSelectsTheFollowingMatch() {
        let editor = makeEditor("cat dog cat")
        editor.textView.setSelectedRange(NSRange(location: 0, length: 0))

        let first = editor.find(SearchQuery(pattern: "cat"), direction: .next)
        XCTAssertEqual(editor.textView.selectedRange(), NSRange(location: 0, length: 3))
        XCTAssertEqual(first.totalMatches, 2)
        XCTAssertEqual(first.currentIndex, 1)

        let second = editor.find(SearchQuery(pattern: "cat"), direction: .next)
        XCTAssertEqual(editor.textView.selectedRange(), NSRange(location: 8, length: 3))
        XCTAssertEqual(second.currentIndex, 2)
    }

    func testFindNextWrapsAroundTheDocument() {
        let editor = makeEditor("cat dog cat")
        editor.textView.setSelectedRange(NSRange(location: 8, length: 3))
        let outcome = editor.find(SearchQuery(pattern: "cat"), direction: .next)
        XCTAssertEqual(editor.textView.selectedRange(), NSRange(location: 0, length: 3))
        XCTAssertEqual(outcome.currentIndex, 1)
    }

    func testFindPreviousMovesBackwards() {
        let editor = makeEditor("cat dog cat")
        editor.textView.setSelectedRange(NSRange(location: 8, length: 3))
        _ = editor.find(SearchQuery(pattern: "cat"), direction: .previous)
        XCTAssertEqual(editor.textView.selectedRange(), NSRange(location: 0, length: 3))
    }

    /// The point of incremental search: refining the pattern must keep
    /// matching at the place the user started from, not step forward once
    /// per keystroke.
    func testIncrementalSearchStaysAnchoredWhileTyping() {
        let editor = makeEditor("alpha alpine alps")
        editor.textView.setSelectedRange(NSRange(location: 0, length: 0))
        editor.incrementalSearchAnchor = 0

        _ = editor.find(SearchQuery(pattern: "al"), direction: .incremental)
        XCTAssertEqual(editor.textView.selectedRange(), NSRange(location: 0, length: 2))
        _ = editor.find(SearchQuery(pattern: "alp"), direction: .incremental)
        XCTAssertEqual(editor.textView.selectedRange(), NSRange(location: 0, length: 3))
        _ = editor.find(SearchQuery(pattern: "alpi"), direction: .incremental)
        XCTAssertEqual(editor.textView.selectedRange(), NSRange(location: 6, length: 4),
                       "the first match at or after the anchor, not after the previous match")
    }

    func testMatchStatusReportsCountsWithoutMovingTheSelection() {
        let editor = makeEditor("cat cat cat")
        editor.textView.setSelectedRange(NSRange(location: 4, length: 3))

        let status = editor.matchStatus(for: SearchQuery(pattern: "cat"))
        XCTAssertEqual(status.totalMatches, 3)
        XCTAssertEqual(status.currentIndex, 2, "the selection is the second match")
        XCTAssertEqual(editor.textView.selectedRange(), NSRange(location: 4, length: 3))
    }

    func testNoMatchesLeavesSelectionAloneAndReportsZero() {
        let editor = makeEditor("cat")
        editor.textView.setSelectedRange(NSRange(location: 1, length: 0))
        let outcome = editor.find(SearchQuery(pattern: "zebra"), direction: .next)
        XCTAssertEqual(outcome.totalMatches, 0)
        XCTAssertNil(outcome.currentIndex)
        XCTAssertEqual(editor.textView.selectedRange(), NSRange(location: 1, length: 0))
    }

    func testInvalidRegexIsReportedAsAMessageNotACrash() {
        let editor = makeEditor("abc")
        let outcome = editor.find(
            SearchQuery(pattern: "a(", mode: .regularExpression), direction: .next)
        XCTAssertNotNil(outcome.errorMessage)
        XCTAssertEqual(outcome.totalMatches, 0)
    }

    func testSelectAllMatchesSelectsEveryOccurrence() {
        let editor = makeEditor("cat dog cat cat")
        let outcome = editor.selectAllMatches(for: SearchQuery(pattern: "cat"))
        XCTAssertEqual(outcome.totalMatches, 3)
        XCTAssertEqual(editor.textView.selectedRanges.map { $0.rangeValue }, [
            NSRange(location: 0, length: 3),
            NSRange(location: 8, length: 3),
            NSRange(location: 12, length: 3),
        ])
    }

    func testSearchOptionsReachTheEngine() {
        let editor = makeEditor("Cat cat category")
        XCTAssertEqual(editor.matchStatus(for: SearchQuery(pattern: "cat")).totalMatches, 3)
        XCTAssertEqual(
            editor.matchStatus(for: SearchQuery(pattern: "cat", isCaseSensitive: true)).totalMatches, 2)
        XCTAssertEqual(
            editor.matchStatus(for: SearchQuery(pattern: "cat", wholeWord: true)).totalMatches, 2)
        XCTAssertEqual(
            editor.matchStatus(for: SearchQuery(pattern: "c.t", mode: .regularExpression)).totalMatches, 3)
    }
}
