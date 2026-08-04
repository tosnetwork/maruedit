import XCTest
@testable import MaruEditCore

final class GrepResultFormatterTests: XCTestCase {
    private let match = GrepMatch(
        url: URL(fileURLWithPath: "/tmp/root/Sources/App.swift"),
        relativePath: "Sources/App.swift",
        line: 7,
        column: 12,
        range: NSRange(location: 50, length: 6),
        preview: "let answer = 42",
        previewRange: NSRange(location: 4, length: 6),
        encoding: .utf8
    )

    func testLineUsesNavigablePathLineColumnFormat() {
        XCTAssertEqual(
            GrepResultFormatter.line(for: match),
            "Sources/App.swift:7:12: let answer = 42"
        )
    }

    func testPlainTextContainsQueryMatchesAndSummary() {
        let summary = GrepSummary(scannedFiles: 3, matchedFiles: 1, matchCount: 1, skippedFiles: 2)
        let text = GrepResultFormatter.plainText(matches: [match], summary: summary, pattern: "answer")

        XCTAssertTrue(text.hasPrefix("Search for: answer\n"))
        XCTAssertTrue(text.contains("Sources/App.swift:7:12: let answer = 42"))
        XCTAssertTrue(text.hasSuffix("1 match in 1 of 3 files, 2 skipped\n"))
    }

    func testSummaryMakesCancellationAndErrorsExplicit() {
        XCTAssertEqual(
            GrepResultFormatter.describe(GrepSummary(wasCancelled: true)),
            "0 matches in 0 of 0 files (cancelled)"
        )
        XCTAssertEqual(
            GrepResultFormatter.describe(GrepSummary(errorMessage: "Invalid pattern")),
            "Invalid pattern"
        )
    }
}
