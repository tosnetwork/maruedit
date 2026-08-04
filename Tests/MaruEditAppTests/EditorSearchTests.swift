import XCTest
import AppKit
import MaruEditCore
@preconcurrency @testable import MaruEditApp

/// Covers the editor-side glue between `SearchEngine` and the text view
/// (ROADMAP.md M3-02). Uses a real, window-less `EditorViewController`;
/// nothing here opens a panel or an alert.

@preconcurrency @MainActor
final class EditorSearchTests: XCTestCase {

    /// Windows created here are never ordered front and never run modal;
    /// one is needed only because `NSTextView` resolves its undo manager
    /// through the responder chain, so a window-less text view records no
    /// Undo at all.
    private var windows: [NSWindow] = []

    override func tearDown() {
        windows.removeAll()
        super.tearDown()
    }

    private func makeEditor(_ text: String) -> EditorViewController {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled], backing: .buffered, defer: true
        )
        let vc = EditorViewController()
        window.contentView = vc.view // forces loadView, and gives the text view an undo manager
        windows.append(window)
        vc.textView.string = text
        return vc
    }

    func testFindNextSelectsTheFollowingMatch() async {
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

    func testFindNextWrapsAroundTheDocument() async {
        let editor = makeEditor("cat dog cat")
        editor.textView.setSelectedRange(NSRange(location: 8, length: 3))
        let outcome = editor.find(SearchQuery(pattern: "cat"), direction: .next)
        XCTAssertEqual(editor.textView.selectedRange(), NSRange(location: 0, length: 3))
        XCTAssertEqual(outcome.currentIndex, 1)
    }

    func testFindPreviousMovesBackwards() async {
        let editor = makeEditor("cat dog cat")
        editor.textView.setSelectedRange(NSRange(location: 8, length: 3))
        _ = editor.find(SearchQuery(pattern: "cat"), direction: .previous)
        XCTAssertEqual(editor.textView.selectedRange(), NSRange(location: 0, length: 3))
    }

    /// The point of incremental search: refining the pattern must keep
    /// matching at the place the user started from, not step forward once
    /// per keystroke.
    func testIncrementalSearchStaysAnchoredWhileTyping() async {
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

    func testMatchStatusReportsCountsWithoutMovingTheSelection() async {
        let editor = makeEditor("cat cat cat")
        editor.textView.setSelectedRange(NSRange(location: 4, length: 3))

        let status = editor.matchStatus(for: SearchQuery(pattern: "cat"))
        XCTAssertEqual(status.totalMatches, 3)
        XCTAssertEqual(status.currentIndex, 2, "the selection is the second match")
        XCTAssertEqual(editor.textView.selectedRange(), NSRange(location: 4, length: 3))
    }

    func testNoMatchesLeavesSelectionAloneAndReportsZero() async {
        let editor = makeEditor("cat")
        editor.textView.setSelectedRange(NSRange(location: 1, length: 0))
        let outcome = editor.find(SearchQuery(pattern: "zebra"), direction: .next)
        XCTAssertEqual(outcome.totalMatches, 0)
        XCTAssertNil(outcome.currentIndex)
        XCTAssertEqual(editor.textView.selectedRange(), NSRange(location: 1, length: 0))
    }

    func testInvalidRegexIsReportedAsAMessageNotACrash() async {
        let editor = makeEditor("abc")
        let outcome = editor.find(
            SearchQuery(pattern: "a(", mode: .regularExpression), direction: .next)
        XCTAssertNotNil(outcome.errorMessage)
        XCTAssertEqual(outcome.totalMatches, 0)
    }

    func testSelectAllMatchesSelectsEveryOccurrence() async {
        let editor = makeEditor("cat dog cat cat")
        let outcome = editor.selectAllMatches(for: SearchQuery(pattern: "cat"))
        XCTAssertEqual(outcome.totalMatches, 3)
        XCTAssertEqual(editor.textView.selectedRanges.map { $0.rangeValue }, [
            NSRange(location: 0, length: 3),
            NSRange(location: 8, length: 3),
            NSRange(location: 12, length: 3),
        ])
    }

    // MARK: - Replace (M3-03)

    func testReplaceCurrentReplacesTheSelectedMatchAndAdvances() async {
        let editor = makeEditor("cat dog cat")
        editor.textView.setSelectedRange(NSRange(location: 0, length: 3))

        let outcome = editor.replaceCurrent(SearchQuery(pattern: "cat", replacement: "fox"))
        XCTAssertEqual(editor.textView.string, "fox dog cat")
        XCTAssertEqual(outcome.replacementCount, 1)
        XCTAssertEqual(editor.textView.selectedRange(), NSRange(location: 8, length: 3),
                       "after replacing, the next match is selected")
    }

    func testReplaceOnANonMatchingSelectionOnlyFinds() async {
        let editor = makeEditor("cat dog cat")
        editor.textView.setSelectedRange(NSRange(location: 4, length: 3)) // "dog"

        let outcome = editor.replaceCurrent(SearchQuery(pattern: "cat", replacement: "fox"))
        XCTAssertEqual(editor.textView.string, "cat dog cat", "nothing may be edited before a match is selected")
        XCTAssertEqual(outcome.replacementCount, 0)
        XCTAssertEqual(editor.textView.selectedRange(), NSRange(location: 8, length: 3))
    }

    func testReplaceAllReportsItsCount() async {
        let editor = makeEditor("cat cat cat")
        let outcome = editor.replaceAll(SearchQuery(pattern: "cat", replacement: "dog"))
        XCTAssertEqual(editor.textView.string, "dog dog dog")
        XCTAssertEqual(outcome.replacementCount, 3)
    }

    /// M3-03's acceptance criterion.
    func testOneUndoRestoresTheDocumentAfterReplaceAll() async {
        let editor = makeEditor("cat cat cat cat")
        let original = editor.textView.string

        _ = editor.replaceAll(SearchQuery(pattern: "cat", replacement: "elephant"))
        XCTAssertEqual(editor.textView.string, "elephant elephant elephant elephant")

        editor.textView.undoManager?.undo()
        XCTAssertEqual(editor.textView.string, original, "a single Undo must restore the whole Replace All")
    }

    func testReplaceAllExpandsCaptureGroups() async {
        let editor = makeEditor("width=100\nheight=250")
        let query = SearchQuery(
            pattern: "(\\w+)=(\\d+)", replacement: "$2 is the $1", mode: .regularExpression)
        _ = editor.replaceAll(query)
        XCTAssertEqual(editor.textView.string, "100 is the width\n250 is the height")
    }

    func testReplacementEscapesAreHonored() async {
        let editor = makeEditor("price")
        let query = SearchQuery(
            pattern: "(price)", replacement: "\\$100 for $1", mode: .regularExpression)
        _ = editor.replaceAll(query)
        XCTAssertEqual(editor.textView.string, "$100 for price",
                       "a backslash-escaped dollar sign is literal, an unescaped one is a group reference")
    }

    func testLiteralModeInsertsTheReplacementVerbatim() async {
        let editor = makeEditor("a a")
        _ = editor.replaceAll(SearchQuery(pattern: "a", replacement: "$1"))
        XCTAssertEqual(editor.textView.string, "$1 $1",
                       "in literal mode '$1' is two characters, not a group reference")
    }

    func testReplaceAllWithinTheSelectionScopeLeavesTheRestAlone() async {
        let editor = makeEditor("cat cat cat cat")
        editor.searchScopeSelection = NSRange(location: 0, length: 7) // first two "cat"s

        let outcome = editor.replaceAll(SearchQuery(pattern: "cat", replacement: "dog"))
        XCTAssertEqual(editor.textView.string, "dog dog cat cat")
        XCTAssertEqual(outcome.replacementCount, 2)
    }

    func testReplaceAllWithAZeroLengthPatternTerminates() async {
        let editor = makeEditor("a\nb\nc")
        let outcome = editor.replaceAll(
            SearchQuery(pattern: "^", replacement: "> ", mode: .regularExpression))
        XCTAssertEqual(editor.textView.string, "> a\n> b\n> c")
        XCTAssertEqual(outcome.replacementCount, 3)
    }

    func testReplaceAllWithNoMatchesChangesNothing() async {
        let editor = makeEditor("cat")
        let outcome = editor.replaceAll(SearchQuery(pattern: "zebra", replacement: "x"))
        XCTAssertEqual(editor.textView.string, "cat")
        XCTAssertEqual(outcome.replacementCount, 0)
    }

    func testReplaceAllWithAnInvalidRegexReportsAnError() async {
        let editor = makeEditor("cat")
        let outcome = editor.replaceAll(
            SearchQuery(pattern: "(", replacement: "x", mode: .regularExpression))
        XCTAssertNotNil(outcome.errorMessage)
        XCTAssertEqual(editor.textView.string, "cat")
    }

    func testReplaceAllOnlyRewritesTheSpanBetweenTheFirstAndLastMatch() async {
        let editor = makeEditor("keep cat keep cat keep")
        _ = editor.replaceAll(SearchQuery(pattern: "cat", replacement: "dog"))
        XCTAssertEqual(editor.textView.string, "keep dog keep dog keep")
    }

    func testSearchOptionsReachTheEngine() async {
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
