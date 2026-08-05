import XCTest
import MaruEditCore
@preconcurrency @testable import MaruEditApp

@preconcurrency @MainActor
final class ClassicWorkspaceTests: XCTestCase {
    func testClassicIsDefaultAndCanSwitchToModernWithoutChangingDocument() async {
        let controller = MainWindowController()
        controller.macroEditor.textView.string = "classic content"

        controller.applyPreferences(.defaults)
        XCTAssertTrue(controller.isClassicWorkspace)
        XCTAssertTrue(controller.isClassicChromeVisibleForTesting)
        XCTAssertEqual(controller.classicHeadingForTesting, "Untitled")

        var modern = Preferences.defaults
        modern.workspaceStyle = .modern
        controller.applyPreferences(modern)
        XCTAssertFalse(controller.isClassicWorkspace)
        XCTAssertFalse(controller.isClassicChromeVisibleForTesting)
        XCTAssertEqual(controller.macroEditor.textView.string, "classic content")
    }

    func testClassicChromeAndStatusExposeAccessibilityInformation() async {
        let controller = MainWindowController()
        controller.applyPreferences(.defaults)
        let root = try! XCTUnwrap(controller.window?.contentView)
        let labels = descendants(of: root).compactMap { $0.accessibilityLabel() }
        XCTAssertTrue(labels.contains("Current document heading"))
        XCTAssertTrue(labels.contains("Character column ruler"))
        XCTAssertTrue(labels.contains("Favorite command strip"))
    }

    private func descendants(of view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + descendants(of: $0) }
    }
}
