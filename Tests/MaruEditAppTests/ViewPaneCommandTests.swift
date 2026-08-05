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

    func testAutomaticSpellingToggleIsDocumentLocal() {
        let controller = MainWindowController()
        controller.prepareUITestDocument(content: "mispeling", selections: [])
        let initial = controller.macroEditor.textView.isContinuousSpellCheckingEnabled
        controller.toggleSpellChecking()
        XCTAssertEqual(controller.macroEditor.textView.isContinuousSpellCheckingEnabled, !initial)
        XCTAssertEqual(controller.macroEditor.document?.spellCheckingOverride, !initial)

        controller.macroEditor.document = Document(content: "other")
        XCTAssertNil(controller.macroEditor.document?.spellCheckingOverride)
    }
}
