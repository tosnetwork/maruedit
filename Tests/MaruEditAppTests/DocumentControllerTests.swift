import XCTest
@preconcurrency @testable import MaruEditApp


@preconcurrency @MainActor
final class DocumentControllerTests: XCTestCase {

    private func tempFile(named name: String, content: String = "") throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("DocumentControllerTests-\(UUID().uuidString)-\(name)")
        try content.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func testNewDocumentBecomesCurrent() async {
        let c = DocumentController()
        let doc = c.newDocument()
        XCTAssertEqual(c.documents.count, 1)
        XCTAssertEqual(c.currentIndex, 0)
        XCTAssertTrue(c.currentDocument === doc)
    }

    func testOpenAppendsNewTabForUnseenFile() async throws {
        let c = DocumentController()
        _ = c.newDocument()
        let url = try tempFile(named: "a.txt", content: "hello")

        let result = try c.open(url: url)
        XCTAssertFalse(result.wasAlreadyOpen)
        XCTAssertEqual(c.documents.count, 2)
        XCTAssertEqual(c.currentIndex, 1)
        XCTAssertEqual(result.document.content, "hello")
    }

    func testOpenActivatesExistingTabInsteadOfDuplicating() async throws {
        let c = DocumentController()
        let url = try tempFile(named: "a.txt", content: "hello")
        _ = try c.open(url: url)
        _ = c.newDocument() // move away from it

        let result = try c.open(url: url)
        XCTAssertTrue(result.wasAlreadyOpen)
        XCTAssertEqual(c.documents.count, 2, "must not duplicate an already-open file")
        XCTAssertEqual(c.currentIndex, 0)
    }

    func testOpenInCurrentTabReplacesUnmodifiedBlankTab() async throws {
        let c = DocumentController()
        _ = c.newDocument() // blank, unmodified
        let url = try tempFile(named: "a.txt", content: "hello")

        let result = try c.openInCurrentTab(url: url)
        XCTAssertFalse(result.wasAlreadyOpen)
        XCTAssertEqual(c.documents.count, 1, "should replace the blank tab in place, not append")
        XCTAssertEqual(c.currentDocument?.fileURL, url)
    }

    func testOpenInCurrentTabAppendsWhenCurrentTabIsModified() async throws {
        let c = DocumentController()
        let blank = c.newDocument()
        blank.content = "unsaved work"
        blank.markModified()
        let url = try tempFile(named: "a.txt", content: "hello")

        _ = try c.openInCurrentTab(url: url)
        XCTAssertEqual(c.documents.count, 2, "must not discard modified content")
    }

    func testCloseDocumentRecreatesBlankWhenListEmptied() async {
        let c = DocumentController()
        _ = c.newDocument()
        let emptiedAndReplaced = c.closeDocument(at: 0)
        XCTAssertTrue(emptiedAndReplaced)
        XCTAssertEqual(c.documents.count, 1, "must never leave zero tabs open")
        XCTAssertNil(c.currentDocument?.fileURL)
    }

    func testCloseDocumentSelectsNeighborWhenNotEmptied() async {
        let c = DocumentController()
        _ = c.newDocument()
        _ = c.newDocument()
        _ = c.newDocument()
        c.selectDocument(at: 2)

        let emptiedAndReplaced = c.closeDocument(at: 2)
        XCTAssertFalse(emptiedAndReplaced)
        XCTAssertEqual(c.documents.count, 2)
        XCTAssertEqual(c.currentIndex, 1)
    }

    func testSelectDocumentIgnoresOutOfRangeIndex() async {
        let c = DocumentController()
        _ = c.newDocument()
        c.selectDocument(at: 99)
        XCTAssertEqual(c.currentIndex, 0, "out-of-range selection must be a no-op, not corrupt state")
    }

    func testSelectDocumentClampedHandlesOutOfRangeSavedIndex() async {
        let c = DocumentController()
        _ = c.newDocument()
        _ = c.newDocument()
        c.selectDocumentClamped(to: 99)
        XCTAssertEqual(c.currentIndex, 1)
        c.selectDocumentClamped(to: -5)
        XCTAssertEqual(c.currentIndex, 0)
    }

    func testPruneLeftoverBlankDocumentKeepsSoleDocument() async {
        let c = DocumentController()
        _ = c.newDocument() // the leftover blank from window init; nothing else was restored
        c.pruneLeftoverBlankDocument()
        XCTAssertEqual(c.documents.count, 1, "must not prune the last remaining document")
    }

    func testPruneLeftoverBlankDocumentRemovesBlankWhenRealDocumentExists() async {
        let c = DocumentController()
        _ = c.newDocument() // leftover blank from window init
        let real = c.newDocument()
        real.content = "not blank"
        real.markModified()

        c.pruneLeftoverBlankDocument()
        XCTAssertEqual(c.documents.count, 1)
        XCTAssertTrue(c.documents[0] === real)
    }

    func testIndependentWindowControllersCanCloseInEitherOrder() async {
        let firstWindow = DocumentController()
        let secondWindow = DocumentController()
        let first = firstWindow.newDocument()
        let second = secondWindow.newDocument()
        first.content = "first unsaved window"
        second.content = "second unsaved window"

        XCTAssertTrue(secondWindow.closeDocument(at: 0))
        XCTAssertEqual(firstWindow.currentDocument?.content, "first unsaved window")
        XCTAssertTrue(firstWindow.closeDocument(at: 0))
        XCTAssertEqual(firstWindow.documents.count, 1)
        XCTAssertEqual(secondWindow.documents.count, 1)
    }
}
