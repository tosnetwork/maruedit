import XCTest
import MaruEditCore
@preconcurrency @testable import MaruEditApp

@preconcurrency @MainActor
final class SearchMarkerAndMultilineTests: XCTestCase {
    func testFindFieldsSupportNewlinesAndExplicitResizing() {
        let bar = FindBarView()
        bar.searchField.stringValue = "first\nsecond"
        bar.replaceField.stringValue = "one\ntwo"
        bar.setInputsExpanded(true)
        XCTAssertEqual(bar.currentQuery.pattern, "first\nsecond")
        XCTAssertEqual(bar.currentQuery.replacement, "one\ntwo")
        XCTAssertTrue(bar.areInputsExpandedForTesting)
        XCTAssertGreaterThan(bar.searchField.intrinsicContentSize.height, 40)
    }

    func testGrepFieldsAreMultilineAndWindowResizable() {
        let panel = GrepPanel()
        panel.patternField.stringValue = "a\nb"
        panel.replacementField.stringValue = "x\ny"
        XCTAssertTrue(panel.window.styleMask.contains(.resizable))
        XCTAssertGreaterThan(panel.patternField.intrinsicContentSize.height, 40)
    }

    func testSearchMarkersUseUniqueLinesAndResultsAreBounded() {
        let editor = EditorViewController()
        _ = editor.view
        editor.document = Document(content: "one one\ntwo\n")
        editor.showSearchMarkers([
            NSRange(location: 0, length: 3), NSRange(location: 4, length: 3),
            NSRange(location: 8, length: 3),
        ])
        XCTAssertEqual(editor.searchMarkerOffsetsForTesting, [0, 8])

        let sidebar = SidebarViewController()
        _ = sidebar.view
        sidebar.updateSearchResults([NSRange(location: 0, length: 3)], text: "one\ntwo")
        XCTAssertTrue(sidebar.searchResultTextForTesting.contains("Search · Ln 1: one"))
    }
}
