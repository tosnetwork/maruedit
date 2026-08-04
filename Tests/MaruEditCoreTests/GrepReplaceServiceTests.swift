import XCTest
@testable import MaruEditCore

final class GrepReplaceServiceTests: XCTestCase {
    func testScanGroupsPreviewsSelectionAndWritesMultipleEncodingsWithRecovery() throws {
        let root = try directory()
        let utf8 = root.appendingPathComponent("a.txt")
        let sjis = root.appendingPathComponent("b.txt")
        try Data("foo\r\nfoo\r\n".utf8).write(to: utf8)
        let japanese = "日本 foo\n"
        try XCTUnwrap(japanese.data(using: TextEncoding.windows31J.foundationEncoding!)).write(to: sjis)
        var set = try GrepReplaceService.scan(
            request: request(root: root, pattern: "foo"), replacement: "bar")
        XCTAssertEqual(set.files.count, 2)
        XCTAssertEqual(set.selectedMatchCount, 3)
        XCTAssertEqual(set.files.first { $0.url.lastPathComponent == "a.txt" }?.previewText, "bar\nbar\n")

        let utfIndex = try XCTUnwrap(set.files.firstIndex { $0.url.lastPathComponent == "a.txt" })
        set.files[utfIndex].matches[1].isSelected = false
        XCTAssertEqual(set.files[utfIndex].previewText, "bar\nfoo\n")
        let transactions = root.appendingPathComponent("transactions")
        let summary = GrepReplaceService.apply(set, transactionDirectory: transactions)
        XCTAssertEqual(summary.writtenFiles, 2)
        XCTAssertEqual(try String(contentsOf: utf8, encoding: .utf8), "bar\r\nfoo\r\n")
        let loaded = try TextFileLoader.load(contentsOf: sjis)
        XCTAssertEqual(loaded.encoding, .windows31J)
        XCTAssertEqual(loaded.content, "日本 bar\n")
        XCTAssertTrue(FileManager.default.fileExists(atPath: transactions.appendingPathComponent("transaction.json").path))
        for result in summary.results.values {
            guard case .written(_, let backup) = result else { return XCTFail("Expected write") }
            XCTAssertTrue(FileManager.default.fileExists(atPath: backup.path))
        }
    }

    func testApplyDetectsExternalModificationAndReportsCancellationAndEncodingFailure() throws {
        let root = try directory(), file = root.appendingPathComponent("a.txt")
        try Data("foo".utf8).write(to: file)
        var set = try GrepReplaceService.scan(request: request(root: root, pattern: "foo"), replacement: "bar")
        let scannedURL = try XCTUnwrap(set.files.first?.url)
        try Data("external".utf8).write(to: file)
        let conflict = GrepReplaceService.apply(set, transactionDirectory: root.appendingPathComponent("t1"))
        XCTAssertEqual(conflict.results[scannedURL], .conflict)
        XCTAssertEqual(try String(contentsOf: file), "external")

        try Data("foo".utf8).write(to: file)
        set = try GrepReplaceService.scan(request: request(root: root, pattern: "foo"), replacement: "bar")
        let rescannedURL = try XCTUnwrap(set.files.first?.url)
        let cancelled = GrepReplaceService.apply(
            set, transactionDirectory: root.appendingPathComponent("t2"), isCancelled: { true })
        XCTAssertEqual(cancelled.results[rescannedURL], .cancelled)
        XCTAssertTrue(cancelled.wasCancelled)

        let sjis = root.appendingPathComponent("sjis.txt")
        try XCTUnwrap("日本 foo".data(using: TextEncoding.windows31J.foundationEncoding!)).write(to: sjis)
        let unrepresentable = try GrepReplaceService.scan(
            request: request(root: sjis, pattern: "foo"), replacement: "😀")
        let sjisURL = try XCTUnwrap(unrepresentable.files.first?.url)
        let encodingFailure = GrepReplaceService.apply(
            unrepresentable, transactionDirectory: root.appendingPathComponent("t3"))
        XCTAssertEqual(encodingFailure.results[sjisURL], .encodingFailure)
        XCTAssertEqual(try TextFileLoader.load(contentsOf: sjis).content, "日本 foo")
    }

    private func request(root: URL, pattern: String) -> GrepRequest {
        GrepRequest(query: SearchQuery(pattern: pattern, isCaseSensitive: true), roots: [root])
    }
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
