import XCTest
import AppKit
import MaruEditCore
@preconcurrency @testable import MaruEditApp

/// The Find Bar's contract after M3-02: it builds queries, routes keyboard
/// input to actions, and displays whatever outcome it is handed — and does
/// no matching of its own.

@preconcurrency @MainActor
final class FindBarViewTests: XCTestCase {
    func testMenuFacingOptionAPIUsesTheSameQueryState() async {
        let bar = FindBarView()
        XCTAssertFalse(bar.isOptionEnabled(.caseSensitive))
        bar.toggleOption(.caseSensitive)
        bar.toggleOption(.wholeWord)
        bar.toggleOption(.regularExpression)
        XCTAssertTrue(bar.currentQuery.isCaseSensitive)
        XCTAssertTrue(bar.currentQuery.wholeWord)
        XCTAssertEqual(bar.currentQuery.mode, .regularExpression)
    }

    private final class StubDelegate: FindBarDelegate {
        var actions: [FindBarAction] = []
        var queries: [SearchQuery] = []
        var dismissCount = 0
        var outcome = FindOutcome.empty

        func findBar(_ bar: FindBarView, perform action: FindBarAction, query: SearchQuery) -> FindOutcome {
            actions.append(action)
            queries.append(query)
            return outcome
        }

        func findBarDidDismiss(_ bar: FindBarView) { dismissCount += 1 }
    }

    private func makeBar() -> (FindBarView, StubDelegate) {
        let bar = FindBarView(frame: NSRect(x: 0, y: 0, width: 600, height: 34))
        let delegate = StubDelegate()
        bar.delegate = delegate
        return (bar, delegate)
    }

    /// Stand-in for the field editor AppKit passes to `control(_:textView:doCommandBy:)`.
    private let fieldEditor = NSTextView()

    // MARK: - Query construction

    func testQueryReflectsFieldsAndToggles() async {
        let (bar, _) = makeBar()
        bar.searchField.stringValue = "needle"
        bar.replaceField.stringValue = "pin"

        XCTAssertEqual(bar.currentQuery.pattern, "needle")
        XCTAssertEqual(bar.currentQuery.replacement, "pin")
        XCTAssertEqual(bar.currentQuery.mode, .literal)
        XCTAssertFalse(bar.currentQuery.isCaseSensitive)
        XCTAssertFalse(bar.currentQuery.wholeWord)

        bar.toggleCase()
        bar.toggleWholeWord()
        bar.toggleRegex()

        XCTAssertTrue(bar.currentQuery.isCaseSensitive)
        XCTAssertTrue(bar.currentQuery.wholeWord)
        XCTAssertEqual(bar.currentQuery.mode, .regularExpression)
    }

    func testTogglingAnOptionReRunsTheSearchImmediately() async {
        let (bar, delegate) = makeBar()
        bar.searchField.stringValue = "a"
        bar.toggleCase()
        XCTAssertEqual(delegate.actions, [.incremental],
                       "an option change must re-run the search, not wait for Return")
    }

    // MARK: - Keyboard

    func testReturnRunsFindNextAndEscapeDismisses() async {
        let (bar, delegate) = makeBar()
        bar.searchField.stringValue = "a"

        _ = bar.control(bar.searchField, textView: fieldEditor,
                        doCommandBy: #selector(NSResponder.insertNewline(_:)))
        XCTAssertEqual(delegate.actions, [.findNext])

        _ = bar.control(bar.searchField, textView: fieldEditor,
                        doCommandBy: #selector(NSResponder.cancelOperation(_:)))
        XCTAssertEqual(delegate.dismissCount, 1)
        XCTAssertTrue(bar.isHidden)
    }

    func testReturnInTheReplaceFieldReplaces() async {
        let (bar, delegate) = makeBar()
        _ = bar.control(bar.replaceField, textView: fieldEditor,
                        doCommandBy: #selector(NSResponder.insertNewline(_:)))
        XCTAssertEqual(delegate.actions, [.replace])
    }

    func testUpAndDownRecallSearchHistory() async {
        let (bar, _) = makeBar()
        bar.searchHistory = ["newest", "older", "oldest"]

        XCTAssertTrue(bar.control(bar.searchField, textView: fieldEditor,
                                  doCommandBy: #selector(NSResponder.moveUp(_:))))
        XCTAssertEqual(bar.searchField.stringValue, "newest")

        _ = bar.control(bar.searchField, textView: fieldEditor,
                        doCommandBy: #selector(NSResponder.moveUp(_:)))
        XCTAssertEqual(bar.searchField.stringValue, "older")

        _ = bar.control(bar.searchField, textView: fieldEditor,
                        doCommandBy: #selector(NSResponder.moveDown(_:)))
        XCTAssertEqual(bar.searchField.stringValue, "newest")

        _ = bar.control(bar.searchField, textView: fieldEditor,
                        doCommandBy: #selector(NSResponder.moveDown(_:)))
        XCTAssertEqual(bar.searchField.stringValue, "", "stepping past the newest entry clears the field")
    }

    func testHistoryRecallIsIgnoredWhenThereIsNoHistory() async {
        let (bar, _) = makeBar()
        XCTAssertFalse(bar.control(bar.searchField, textView: fieldEditor,
                                   doCommandBy: #selector(NSResponder.moveUp(_:))),
                       "with no history the field editor must keep its normal Up behavior")
    }

    func testSearchAndReplaceHistoriesAreSeparate() async {
        let (bar, _) = makeBar()
        bar.searchHistory = ["find-me"]
        bar.replacementHistory = ["replace-me"]

        _ = bar.control(bar.searchField, textView: fieldEditor,
                        doCommandBy: #selector(NSResponder.moveUp(_:)))
        _ = bar.control(bar.replaceField, textView: fieldEditor,
                        doCommandBy: #selector(NSResponder.moveUp(_:)))

        XCTAssertEqual(bar.searchField.stringValue, "find-me")
        XCTAssertEqual(bar.replaceField.stringValue, "replace-me")
    }

    func testOptionShortcutsToggleSearchOptions() async throws {
        let (bar, delegate) = makeBar()

        func send(_ character: String) throws {
            let event = try XCTUnwrap(NSEvent.keyEvent(
                with: .keyDown, location: .zero,
                modifierFlags: [.command, .option], timestamp: 0, windowNumber: 0,
                context: nil, characters: character, charactersIgnoringModifiers: character,
                isARepeat: false, keyCode: 0
            ))
            XCTAssertTrue(bar.performKeyEquivalent(with: event), "⌥⌘\(character.uppercased()) should be handled")
        }

        try send("c")
        XCTAssertTrue(bar.currentQuery.isCaseSensitive)
        try send("w")
        XCTAssertTrue(bar.currentQuery.wholeWord)
        try send("r")
        XCTAssertEqual(bar.currentQuery.mode, .regularExpression)
        try send("c")
        XCTAssertFalse(bar.currentQuery.isCaseSensitive, "the same shortcut turns the option back off")

        XCTAssertEqual(delegate.actions, Array(repeating: FindBarAction.incremental, count: 4),
                       "each option change re-runs the search")
    }

    func testHiddenFindBarIgnoresOptionShortcuts() async throws {
        let (bar, _) = makeBar()
        bar.isHidden = true
        let event = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown, location: .zero,
            modifierFlags: [.command, .option], timestamp: 0, windowNumber: 0,
            context: nil, characters: "c", charactersIgnoringModifiers: "c",
            isARepeat: false, keyCode: 0
        ))
        XCTAssertFalse(bar.performKeyEquivalent(with: event))
        XCTAssertFalse(bar.currentQuery.isCaseSensitive)
    }

    // MARK: - Presentation

    func testStatusShowsCurrentAndTotalCounts() async {
        let (bar, delegate) = makeBar()
        bar.searchField.stringValue = "a"
        delegate.outcome = FindOutcome(totalMatches: 12, currentIndex: 3)
        _ = bar.control(bar.searchField, textView: fieldEditor,
                        doCommandBy: #selector(NSResponder.insertNewline(_:)))
        XCTAssertEqual(bar.statusText, "3 of 12")
    }

    func testStatusShowsNoResults() async {
        let (bar, delegate) = makeBar()
        bar.searchField.stringValue = "zzz"
        delegate.outcome = FindOutcome(totalMatches: 0)
        _ = bar.control(bar.searchField, textView: fieldEditor,
                        doCommandBy: #selector(NSResponder.insertNewline(_:)))
        XCTAssertEqual(bar.statusText, "No results")
    }

    func testInvalidPatternMessageReplacesTheCountAndKeepsInput() async {
        let (bar, delegate) = makeBar()
        bar.searchField.stringValue = "a("
        delegate.outcome = .failure("The pattern is invalid.")
        _ = bar.control(bar.searchField, textView: fieldEditor,
                        doCommandBy: #selector(NSResponder.insertNewline(_:)))
        XCTAssertEqual(bar.statusText, "The pattern is invalid.")
        XCTAssertEqual(bar.searchField.stringValue, "a(", "an invalid pattern must not clear what was typed")
    }

    // MARK: - Accessibility

    func testControlsCarryVoiceOverLabels() async {
        let (bar, _) = makeBar()
        XCTAssertEqual(bar.searchField.accessibilityLabel(), "Find")
        XCTAssertEqual(bar.replaceField.accessibilityLabel(), "Replace with")
        XCTAssertNotNil(bar.searchField.accessibilityHelp())
        XCTAssertEqual(bar.accessibilityLabel(), "Find bar")

        // Every button in the bar, not just the fields, must be labeled.
        var buttons: [NSButton] = []
        func collect(_ view: NSView) {
            if let button = view as? NSButton { buttons.append(button) }
            view.subviews.forEach(collect)
        }
        collect(bar)
        XCTAssertEqual(buttons.count, 10)
        for button in buttons {
            XCTAssertFalse(button.accessibilityLabel()?.isEmpty ?? true,
                           "button '\(button.title)' has no VoiceOver label")
        }
    }
}
