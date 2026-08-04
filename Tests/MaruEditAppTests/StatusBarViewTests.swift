import XCTest
@testable import MaruEditApp

final class StatusBarViewTests: XCTestCase {
    func testTransientMessageRestoresCursorText() {
        let status = StatusBarView(frame: NSRect(x: 0, y: 0, width: 600, height: 24))
        status.updateCursor(line: 4, col: 9)
        status.showTransientMessage("Chord: ctrl+k …", duration: 0.01)
        XCTAssertEqual(status.displayedLeadingText, "Chord: ctrl+k …")

        let restored = expectation(description: "cursor text restored")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) {
            XCTAssertEqual(status.displayedLeadingText, "Ln 4, Col 9")
            restored.fulfill()
        }
        wait(for: [restored], timeout: 1)
    }
}
