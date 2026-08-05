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

    func testClassicToolbarUsesStableCommandIdentifiers() async {
        let controller = MainWindowController()
        controller.applyPreferences(.defaults)
        XCTAssertEqual(controller.classicToolbarIdentifiersForTesting, [
            "file.new", "file.open", "file.save", "search.find",
            "search.findNext", "search.grep", "navigate.toggleBookmark",
        ])

        var received: CommandID?
        controller.onClassicToolbarCommand = { received = $0 }
        controller.activateClassicToolbarCommandForTesting(.searchGrep)
        XCTAssertEqual(received, .searchGrep)
    }

    func testClassicLightAndModernThemesSwitchWithoutChangingDocument() async {
        let controller = MainWindowController()
        controller.macroEditor.textView.string = "theme-safe content"
        controller.applyPreferences(.defaults)
        let classicBackground = Theme.background

        var modern = Preferences.defaults
        modern.workspaceStyle = .modern
        modern.theme = .monokai
        controller.applyPreferences(modern)

        XCTAssertNotEqual(Theme.background, classicBackground)
        XCTAssertEqual(controller.macroEditor.textView.string, "theme-safe content")
    }

    func testUtilityPaneSwitchesBetweenFilesOutlineAndResults() async {
        let sidebar = SidebarViewController()
        _ = sidebar.view
        XCTAssertEqual(sidebar.utilityPaneLabelsForTesting, ["Files", "Outline", "Results"])
        sidebar.showUtilityPane(.outline)
        XCTAssertEqual(sidebar.selectedUtilityPane, .outline)
        sidebar.showUtilityPane(.results)
        XCTAssertEqual(sidebar.selectedUtilityPane, .results)
    }

    func testClassicChromeComponentsCanBeHiddenIndependently() async {
        let controller = MainWindowController()
        var preferences = Preferences.defaults
        preferences.classicChrome = ClassicChromeOptions(
            showHeading: false, showRuler: true, showCommandStrip: false)
        controller.applyPreferences(preferences)
        XCTAssertEqual(controller.classicChromeVisibilityForTesting, preferences.classicChrome)
    }

    private func descendants(of view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + descendants(of: $0) }
    }
}
