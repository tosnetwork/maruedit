import XCTest
@testable import MaruEditCore

final class InMemoryGrepServiceTests: XCTestCase {
    func testSearchesUnsavedUnicodeBuffersWithNavigableRanges() throws {
        let doc = InMemorySearchDocument(
            url: URL(string: "maruedit-memory://0")!, displayName: "Untitled 1",
            text: "😀 alpha\nbeta alpha")
        let matches = try InMemoryGrepService.search(
            [doc], query: SearchQuery(pattern: "alpha", wraps: false))
        XCTAssertEqual(matches.map(\.line), [1, 2])
        XCTAssertEqual(matches.map(\.column), [4, 6])
        XCTAssertEqual(matches.map(\.range.location), [3, 14])
    }

    func testAllOpenDocumentsAndRefinement() throws {
        let docs = [
            InMemorySearchDocument(url: URL(fileURLWithPath: "/a"), displayName: "a", text: "TODO parser"),
            InMemorySearchDocument(url: URL(fileURLWithPath: "/b"), displayName: "b", text: "TODO layout"),
        ]
        let matches = try InMemoryGrepService.search(docs, query: SearchQuery(pattern: "TODO"))
        XCTAssertEqual(matches.count, 2)
        XCTAssertEqual(try InMemoryGrepService.refine(
            matches, query: SearchQuery(pattern: "parser")).map(\.relativePath), ["a"])
    }
}
