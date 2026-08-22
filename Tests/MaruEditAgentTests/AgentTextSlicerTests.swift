import XCTest
@testable import MaruEditCore

/// The ranged-read and search semantics ADR-012 §5.0 makes normative, because
/// leaving them unstated is an off-by-one in every client.
final class AgentTextSlicerTests: XCTestCase {

    private let sample = "alpha\nbeta\ngamma\ndelta\n"

    func testLineRangesAreOneBasedAndHalfOpen() {
        let slice = AgentTextSlicer.slice(text: sample, startLine: 2, endLine: 4, maxBytes: 1_000)
        // Lines 2 and 3, not 2 through 4: the end is exclusive.
        XCTAssertEqual(slice.text, "beta\ngamma\n")
        XCTAssertEqual(slice.startLine, 2)
        XCTAssertEqual(slice.endLine, 4)
        // "…delta\n" opens an empty fifth line, exactly as the gutter shows.
        XCTAssertEqual(slice.totalLines, 5)
        XCTAssertFalse(slice.truncated)
    }

    func testWholeDocumentReadWhenNoRangeIsGiven() {
        let slice = AgentTextSlicer.slice(text: sample, startLine: nil, endLine: nil, maxBytes: 1_000)
        XCTAssertEqual(slice.text, sample)
        XCTAssertEqual(slice.startLine, 1)
        XCTAssertFalse(slice.truncated)
    }

    func testEndLinePastTheEndIsClampedAndReported() {
        let slice = AgentTextSlicer.slice(text: sample, startLine: 3, endLine: 9_999, maxBytes: 1_000)
        XCTAssertEqual(slice.text, "gamma\ndelta\n")
        XCTAssertLessThanOrEqual(slice.endLine, slice.totalLines + 1)
    }

    func testStartPastTheEndReturnsNothingRatherThanFailing() {
        let slice = AgentTextSlicer.slice(text: sample, startLine: 99, endLine: nil, maxBytes: 1_000)
        XCTAssertEqual(slice.text, "")
        XCTAssertFalse(slice.truncated)
    }

    func testTruncationNeverSplitsAMultiByteCharacter() {
        let japanese = String(repeating: "日本語テキスト\n", count: 40)
        let slice = AgentTextSlicer.slice(text: japanese, startLine: nil, endLine: nil, maxBytes: 50)
        XCTAssertTrue(slice.truncated)
        XCTAssertLessThanOrEqual(slice.text.utf8.count, 50)
        // The proof that no scalar was cut in half: it still round-trips.
        XCTAssertEqual(String(decoding: Array(slice.text.utf8), as: UTF8.self), slice.text)
        XCTAssertTrue(japanese.hasPrefix(slice.text))
    }

    func testTruncationReportsWhatItActuallyReturned() {
        let slice = AgentTextSlicer.slice(text: sample, startLine: 1, endLine: nil, maxBytes: 7)
        XCTAssertTrue(slice.truncated)
        // Not the range that was asked for — the range that came back.
        XCTAssertEqual(slice.endOffset - slice.startOffset, (slice.text as NSString).length)
    }

    func testPositionsAreOneBasedInBothAxes() {
        let text = sample as NSString
        XCTAssertEqual(AgentTextSlicer.position(ofOffset: 0, in: text), .init(line: 1, column: 1))
        XCTAssertEqual(AgentTextSlicer.position(ofOffset: 6, in: text), .init(line: 2, column: 1))
        XCTAssertEqual(AgentTextSlicer.position(ofOffset: 8, in: text), .init(line: 2, column: 3))
    }

    // MARK: - Search

    private func documents(_ text: String)
        -> [(id: String, revision: UInt64, metadataRevision: UInt64, text: String)] {
        [(id: "doc_1", revision: 7, metadataRevision: 2, text: text)]
    }

    func testSearchReportsPositionsContextAndTheSnapshotItRanAgainst() throws {
        let results = AgentTextSlicer.searchLiteral(
            in: documents(sample), query: "gamma", ignoreCase: false, limit: 10)
        XCTAssertEqual(results.matches.count, 1)
        let match = try XCTUnwrap(results.matches.first)
        XCTAssertEqual(match["line"], .int(3))
        XCTAssertEqual(match["column"], .int(1))
        XCTAssertEqual(match["offset"], .int(11))
        XCTAssertEqual(match["lineText"], .string("gamma"))
        // An offset is meaningless without the revision it indexes.
        XCTAssertEqual(match["revision"], .int(7))
        XCTAssertEqual(match["metadataRevision"], .int(2))
    }

    func testSearchFindsEveryOccurrenceAndHonoursCaseFolding() {
        let text = "Foo foo FOO"
        XCTAssertEqual(
            AgentTextSlicer.searchLiteral(
                in: documents(text), query: "foo", ignoreCase: false, limit: 10).matches.count, 1)
        XCTAssertEqual(
            AgentTextSlicer.searchLiteral(
                in: documents(text), query: "foo", ignoreCase: true, limit: 10).matches.count, 3)
    }

    func testSearchStopsAtItsLimitAndSaysSo() {
        let text = String(repeating: "needle\n", count: 50)
        let results = AgentTextSlicer.searchLiteral(
            in: documents(text), query: "needle", ignoreCase: false, limit: 5)
        XCTAssertEqual(results.matches.count, 5)
        // A truncated answer that does not say so is a wrong answer.
        XCTAssertTrue(results.truncated)
    }

    func testSearchOnEmptyDocumentsIsEmptyNotAnError() {
        let results = AgentTextSlicer.searchLiteral(
            in: documents(""), query: "x", ignoreCase: false, limit: 5)
        XCTAssertTrue(results.matches.isEmpty)
        XCTAssertFalse(results.truncated)
    }

    func testSearchOverlappingCandidatesAdvancesAndTerminates() {
        // "aaa" searched for "aa" must not loop forever on the same offset.
        let results = AgentTextSlicer.searchLiteral(
            in: documents("aaaa"), query: "aa", ignoreCase: false, limit: 10)
        XCTAssertEqual(results.matches.count, 2)
    }

    func testLargeDocumentSearchStaysWithinABudget() {
        let large = String(repeating: "lorem ipsum dolor sit amet\n", count: 100_000)
        let started = Date()
        let results = AgentTextSlicer.searchLiteral(
            in: documents(large), query: "dolor", ignoreCase: false, limit: 100)
        XCTAssertEqual(results.matches.count, 100)
        XCTAssertTrue(results.truncated)
        // Not a benchmark — a guard that the limit is applied while scanning
        // rather than after collecting every match in a 2.6 MB document.
        XCTAssertLessThan(Date().timeIntervalSince(started), 5.0)
    }
}
