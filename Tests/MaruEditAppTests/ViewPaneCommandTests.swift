import XCTest
@testable import MaruEditApp

@MainActor
final class ViewPaneCommandTests: XCTestCase {
    func testStatusAndOutputPanesToggleAndFocus() {
        let controller = MainWindowController()
        XCTAssertTrue(controller.isStatusBarVisibleForTesting)
        XCTAssertFalse(controller.isOutputPaneVisibleForTesting)

        controller.toggleStatusBar()
        controller.toggleOutputPane()
        XCTAssertFalse(controller.isStatusBarVisibleForTesting)
        XCTAssertTrue(controller.isOutputPaneVisibleForTesting)

        controller.focusOutputPane()
        controller.toggleOutputPane()
        XCTAssertFalse(controller.isOutputPaneVisibleForTesting)
    }
}
