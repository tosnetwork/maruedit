import AppKit
import XCTest
@testable import MaruEditApp

@MainActor
final class DeletionHistoryTests: XCTestCase {
    func testNativeDeletionIsRememberedAndCanBeRestored() {
        let editor = EditorViewController()
        _ = editor.view
        editor.textView.string = "alpha beta"
        editor.textView.setSelectedRange(NSRange(location: 6, length: 4))
        editor.textView.delete(nil)

        XCTAssertEqual(editor.textView.string, "alpha ")
        XCTAssertEqual(editor.deletedTextHistory.first, "beta")
        XCTAssertTrue(editor.restoreLastDeletedText())
        XCTAssertEqual(editor.textView.string, "alpha beta")
    }

    func testBatchDeletionCombinesSelectionsAndBoundsHistory() {
        let editor = EditorViewController()
        _ = editor.view
        editor.textView.string = "one two three"
        editor.batchReplace([
            NSRange(location: 0, length: 3),
            NSRange(location: 8, length: 5),
        ], with: "")
        XCTAssertEqual(editor.deletedTextHistory.first, "onethree")

        for index in 0..<35 { editor.rememberDeletedText("deleted-\(index)") }
        XCTAssertEqual(editor.deletedTextHistory.count, 30)
        XCTAssertEqual(editor.deletedTextHistory.first, "deleted-34")
    }
}
