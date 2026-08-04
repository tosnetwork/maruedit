import XCTest
import MaruEditCore
@preconcurrency @testable import MaruEditApp

/// Only tests the *no-conflict* path through `MainWindowController`'s
/// save flow. Deliberately does not exercise the "file changed
/// externally" branch here: that calls `NSAlert(...).runModal()`, which
/// blocks indefinitely in a headless test process with nothing to click
/// it — the same constraint already documented for M2-03's mixed-line-
/// ending alert and M2-04's unrepresentable-character alert. The
/// underlying detection logic itself is fully covered by
/// `ExternalChangeDetectorTests` at the Core level.

@preconcurrency @MainActor
final class MainWindowControllerExternalChangeTests: XCTestCase {

    func testSavingAnUnchangedFileProceedsWithoutFalsePositive() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("MainWindowControllerExternalChangeTests-\(UUID().uuidString).txt")
        try Data("original".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let wc = MainWindowController()
        wc.openFile(url)
        wc.saveDocument() // no external change occurred — must not hang or block

        // If the false-positive path were taken, this would never be
        // reached because saveDocument() would be blocked on a modal
        // alert instead of returning.
        XCTAssertEqual(try Data(contentsOf: url), Data("original".utf8))
    }
}
