import AppKit
import XCTest
import MaruEditCore
@testable import MaruEditApp

final class GrepUITests: XCTestCase {
    func testPanelBuildsRequestFromPrefilledQueryAndFolder() {
        let panel = GrepPanel()
        panel.folderURL = URL(fileURLWithPath: "/tmp/project")
        panel.prefill(with: SearchQuery(
            pattern: "needle",
            mode: .regularExpression,
            isCaseSensitive: true,
            wholeWord: true
        ))

        let request = panel.currentRequest
        XCTAssertEqual(request?.roots, [URL(fileURLWithPath: "/tmp/project")])
        XCTAssertEqual(request?.query.pattern, "needle")
        XCTAssertEqual(request?.query.mode, .regularExpression)
        XCTAssertEqual(request?.query.isCaseSensitive, true)
        XCTAssertEqual(request?.query.wholeWord, true)
    }

    func testPanelRequiresPatternAndFolder() {
        let panel = GrepPanel()
        XCTAssertNil(panel.currentRequest)

        panel.prefill(with: SearchQuery(pattern: "needle"))
        XCTAssertNil(panel.currentRequest)
    }

    func testResultRowCarriesReadableAccessibilityDescription() {
        let match = GrepMatch(
            url: URL(fileURLWithPath: "/tmp/a.txt"),
            relativePath: "a.txt",
            line: 2,
            column: 4,
            range: NSRange(location: 2, length: 6),
            preview: "a needle here",
            previewRange: NSRange(location: 2, length: 6),
            encoding: .utf8
        )

        XCTAssertEqual(
            OutputPaneView.accessibilityDescription(for: match),
            "a.txt, line 2, column 4: a needle here"
        )
        XCTAssertEqual(OutputPaneView.attributedRow(for: match).string, "a.txt:2: a needle here")
    }
}
