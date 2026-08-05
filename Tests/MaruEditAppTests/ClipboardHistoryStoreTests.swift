import AppKit
import XCTest
@preconcurrency @testable import MaruEditApp

@preconcurrency @MainActor
final class ClipboardHistoryStoreTests: XCTestCase {
    func testPollingTracksExternalChangesDeduplicatesAndBoundsHistory() async {
        let pasteboard = NSPasteboard(name: .init("ClipboardHistoryStoreTests"))
        let history = ClipboardHistoryStore(limit: 2)
        for value in ["one", "two", "one", "three"] {
            pasteboard.clearContents(); pasteboard.setString(value, forType: .string)
            history.poll(pasteboard)
        }
        XCTAssertEqual(history.entries, ["three", "one"])
        history.poll(pasteboard)
        XCTAssertEqual(history.entries, ["three", "one"], "unchanged pasteboard must not duplicate")
        history.clear(); XCTAssertTrue(history.entries.isEmpty)
    }
}
