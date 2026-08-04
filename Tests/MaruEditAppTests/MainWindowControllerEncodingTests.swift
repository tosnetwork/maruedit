import XCTest
import MaruEditCore
@preconcurrency @testable import MaruEditApp

/// Exercises M2-02's "Reopen with Encoding" through the real
/// `MainWindowController`, not just `Document` in isolation — this is
/// the actual code path the status bar click and File menu item drive.

@preconcurrency @MainActor
final class MainWindowControllerEncodingTests: XCTestCase {

    private let japaneseSample = "日本語のテキストファイルです。漢字とひらがなとカタカナ。"

    private func tempFile(contents: Data) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("MainWindowControllerEncodingTests-\(UUID().uuidString).txt")
        try contents.write(to: url)
        return url
    }

    func testBuildEncodingMenuListsAllUserSelectableEncodingsAndChecksCurrent() async throws {
        guard let data = japaneseSample.data(using: .japaneseEUC) else { return XCTFail("setup") }
        let url = try tempFile(contents: data)
        defer { try? FileManager.default.removeItem(at: url) }

        let wc = MainWindowController()
        wc.openFile(url)

        let menu = wc.buildEncodingMenu()
        let titles = menu.items.compactMap { $0.representedObject as? TextEncoding }
        for encoding in TextEncoding.userSelectable {
            XCTAssertTrue(titles.contains(encoding), "\(encoding.rawValue) missing from the menu")
        }

        let checkedItem = menu.items.first { ($0.representedObject as? TextEncoding) == .eucJP }
        XCTAssertEqual(checkedItem?.state, .on, "the currently-active encoding should be checked")
    }

    func testReopenCurrentDocumentWithEncodingUpdatesDocumentAndStatusBar() async throws {
        guard let data = japaneseSample.data(using: .japaneseEUC) else { return XCTFail("setup") }
        let url = try tempFile(contents: data)
        defer { try? FileManager.default.removeItem(at: url) }

        let wc = MainWindowController()
        wc.openFile(url)
        // Re-open forcing the same (correct) encoding — proves the full
        // path (Document.reopen -> EditorViewController.reloadCurrentDocument
        // -> tab/status refresh) runs without crashing and lands on the
        // right encoding.
        wc.reopenCurrentDocument(with: .eucJP)

        let menu = wc.buildEncodingMenu()
        let checkedItem = menu.items.first { $0.state == .on }
        XCTAssertEqual(checkedItem?.representedObject as? TextEncoding, .eucJP)
    }

    func testReopenTracksRecentEncodings() async throws {
        // Deliberately reopens with the *correct* encoding for these
        // bytes: forcing a wrong one that fails to decode would hit
        // reopenCurrentDocument's error path, which shows a real
        // NSAlert(...).runModal() — that blocks forever in a headless
        // test process with nothing to click it.
        RecentEncodings.clearAll()
        guard let data = japaneseSample.data(using: .japaneseEUC) else { return XCTFail("setup") }
        let url = try tempFile(contents: data)
        defer { try? FileManager.default.removeItem(at: url) }
        defer { RecentEncodings.clearAll() }

        let wc = MainWindowController()
        wc.openFile(url)
        wc.reopenCurrentDocument(with: .eucJP)

        XCTAssertTrue(RecentEncodings.encodings.contains(.eucJP))
    }
}
