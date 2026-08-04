import AppKit
import XCTest
import MaruEditCore
@testable import MaruEditApp

final class SharedOutputPaneTests: XCTestCase {
    func testMacroOutputHasTimestampChannelSeverityAndCanClear() {
        let pane = OutputPaneView()
        pane.appendMacroError(
            name: "Broken", message: "failure", timestamp: Date(timeIntervalSince1970: 0))
        XCTAssertTrue(pane.resultsText.contains("[macro] [error] Broken: failure"))
        XCTAssertTrue(pane.resultsText.contains(":"))
        pane.clearForTesting()
        XCTAssertEqual(pane.resultsText, "")
    }

    func testCompilerStyleLocationNavigatesToLineAndColumn() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("SharedOutputPaneTests-\(UUID().uuidString).txt")
        try "first\nsecond line\nthird".write(to: url, atomically: true, encoding: .utf8)
        let coordinator = AppCoordinator(preferencesStore: PreferencesStore(defaults: UserDefaults(
            suiteName: "SharedOutputPaneTests.\(UUID().uuidString)")!))
        let window = coordinator.ensureWindowControllerReady(restoreSession: false)
        window.outputPane(OutputPaneView(), didActivate: OutputLocation(url: url, line: 2, column: 3))
        XCTAssertEqual(window.macroEditor.selectionSet.primaryRange, NSRange(location: 8, length: 0))
    }
}
