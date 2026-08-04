import XCTest
@testable import MaruEditCore

final class GrepServiceTests: XCTestCase {

    private var root: URL!

    override func setUpWithError() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("maruedit-grep-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    // MARK: - Helpers

    @discardableResult
    private func write(_ contents: String, to relativePath: String, encoding: TextEncoding = .utf8) throws -> URL {
        let url = root.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let foundation = try XCTUnwrap(encoding.foundationEncoding)
        let data = try XCTUnwrap(contents.data(using: foundation), "\(contents) is not representable in \(encoding.rawValue)")
        try data.write(to: url)
        return url
    }

    private struct Result {
        var matches: [GrepMatch] = []
        var skips: [(URL, SkipReason)] = []
        var summary = GrepSummary()
        var progressReports = 0
        var startedCount = 0
    }

    private func run(
        pattern: String,
        mode: SearchMode = .literal,
        isCaseSensitive: Bool = false,
        wholeWord: Bool = false,
        includeGlobs: [String] = [],
        isCancelled: () -> Bool = { false }
    ) -> Result {
        var result = Result()
        let request = GrepRequest(
            query: SearchQuery(
                pattern: pattern, mode: mode,
                isCaseSensitive: isCaseSensitive, wholeWord: wholeWord),
            roots: [root],
            includeGlobs: includeGlobs
        )
        GrepService.run(request, isCancelled: isCancelled) { event in
            switch event {
            case .started: result.startedCount += 1
            case .match(let match): result.matches.append(match)
            case .skippedFile(let url, let reason): result.skips.append((url, reason))
            case .progress: result.progressReports += 1
            case .finished(let summary): result.summary = summary
            }
        }
        return result
    }

    // MARK: - Results

    func testReportsPathLineColumnAndPreview() throws {
        try write("first line\nsecond needle here\nthird\n", to: "notes.txt")

        let result = run(pattern: "needle")
        XCTAssertEqual(result.matches.count, 1)
        let match = try XCTUnwrap(result.matches.first)
        XCTAssertEqual(match.relativePath, "notes.txt")
        XCTAssertEqual(match.line, 2)
        XCTAssertEqual(match.column, 8)
        XCTAssertEqual(match.preview, "second needle here")
        XCTAssertEqual((match.preview as NSString).substring(with: match.previewRange), "needle")
    }

    func testLineNumbersAreCorrectForManyMatchesInOneFile() throws {
        let lines = (1...20).map { "line \($0) target" }.joined(separator: "\n")
        try write(lines, to: "many.txt")

        let result = run(pattern: "target")
        XCTAssertEqual(result.matches.map { $0.line }, Array(1...20))
    }

    func testCRLFFileOffsetsMatchTheNormalizedTextTheEditorWouldShow() throws {
        try write("alpha\r\nbeta needle\r\n", to: "crlf.txt")

        let match = try XCTUnwrap(run(pattern: "needle").matches.first)
        XCTAssertEqual(match.line, 2)
        XCTAssertEqual(match.preview, "beta needle", "the preview must not carry a stray carriage return")
        // "alpha\nbeta " is 11 UTF-16 units once normalized.
        XCTAssertEqual(match.range.location, 11)
    }

    func testSearchesRecursivelyAndReportsRelativePaths() throws {
        try write("hit", to: "a.txt")
        try write("hit", to: "sub/b.txt")

        let paths = run(pattern: "hit").matches.map { $0.relativePath }.sorted()
        XCTAssertEqual(paths, ["a.txt", "sub/b.txt"])
    }

    // MARK: - Options

    func testSharedSearchOptionsApply() throws {
        try write("Cat cat category\n", to: "cats.txt")

        XCTAssertEqual(run(pattern: "cat").matches.count, 3)
        XCTAssertEqual(run(pattern: "cat", isCaseSensitive: true).matches.count, 2)
        XCTAssertEqual(run(pattern: "cat", wholeWord: true).matches.count, 2)
        XCTAssertEqual(run(pattern: "c.t", mode: .regularExpression).matches.count, 3)
    }

    func testInvalidRegexFailsBeforeReadingAnyFile() throws {
        try write("anything", to: "a.txt")

        let result = run(pattern: "a(", mode: .regularExpression)
        XCTAssertNotNil(result.summary.errorMessage)
        XCTAssertEqual(result.summary.scannedFiles, 0)
        XCTAssertTrue(result.matches.isEmpty)
    }

    func testEmptyPatternFindsNothing() throws {
        try write("anything", to: "a.txt")
        let result = run(pattern: "")
        XCTAssertTrue(result.matches.isEmpty)
        XCTAssertNil(result.summary.errorMessage)
    }

    // MARK: - Japanese encodings (M3-05 acceptance)

    func testFindsMatchesAcrossUTF8Windows31JAndEUCJPFixtures() throws {
        let japanese = "一行目\n検索する語\n三行目\n"
        try write(japanese, to: "utf8.txt", encoding: .utf8)
        try write(japanese, to: "cp932.txt", encoding: .windows31J)
        try write(japanese, to: "eucjp.txt", encoding: .eucJP)

        let result = run(pattern: "検索する語")
        XCTAssertEqual(result.matches.count, 3)
        XCTAssertEqual(Set(result.matches.map { $0.relativePath }),
                       ["utf8.txt", "cp932.txt", "eucjp.txt"])
        for match in result.matches {
            XCTAssertEqual(match.line, 2, "\(match.relativePath) reported the wrong line")
            XCTAssertEqual(match.column, 1)
            XCTAssertEqual(match.preview, "検索する語")
        }
        // Each file's detected encoding is reported, so the UI can show it
        // and a later Grep Replace can write back in the same one.
        let encodings = Set(result.matches.map { $0.encoding })
        XCTAssertTrue(encodings.contains(.utf8))
        XCTAssertEqual(encodings.count, 3, "expected three distinct encodings, got \(encodings)")
    }

    // MARK: - Streaming, counts, cancellation

    func testStreamsMatchesBeforeFinishing() throws {
        try write("hit", to: "a.txt")
        try write("hit", to: "b.txt")

        var order: [String] = []
        let request = GrepRequest(query: SearchQuery(pattern: "hit"), roots: [root])
        GrepService.run(request) { event in
            switch event {
            case .started: order.append("started")
            case .match: order.append("match")
            case .finished: order.append("finished")
            default: break
            }
        }
        XCTAssertEqual(order, ["started", "match", "match", "finished"],
                       "matches must arrive as they are found, not in one batch at the end")
    }

    func testSummaryCountsScannedMatchedAndSkipped() throws {
        try write("hit hit", to: "a.txt")
        try write("nothing", to: "b.txt")
        try write("hidden hit", to: ".secret.txt")

        let result = run(pattern: "hit")
        XCTAssertEqual(result.summary.scannedFiles, 2)
        XCTAssertEqual(result.summary.matchedFiles, 1)
        XCTAssertEqual(result.summary.matchCount, 2)
        XCTAssertEqual(result.summary.skippedFiles, 1, "the hidden file counts as skipped")
        XCTAssertFalse(result.summary.wasCancelled)
    }

    func testCancellationStopsPromptlyAndIsReported() throws {
        for index in 0..<40 { try write("hit", to: "file\(index).txt") }

        let token = CancellationToken()
        var seen = 0
        let request = GrepRequest(query: SearchQuery(pattern: "hit"), roots: [root])
        var summary = GrepSummary()
        GrepService.run(request, isCancelled: { token.isCancelled }) { event in
            switch event {
            case .match:
                seen += 1
                if seen == 2 { token.cancel() }
            case .finished(let final): summary = final
            default: break
            }
        }
        XCTAssertEqual(seen, 2)
        XCTAssertTrue(summary.wasCancelled)
        XCTAssertLessThan(summary.scannedFiles, 40)
    }

    func testIncludeGlobsNarrowTheScan() throws {
        try write("hit", to: "a.swift")
        try write("hit", to: "b.txt")

        let result = run(pattern: "hit", includeGlobs: ["*.swift"])
        XCTAssertEqual(result.matches.map { $0.relativePath }, ["a.swift"])
        XCTAssertEqual(result.summary.skippedFiles, 1)
    }
}
