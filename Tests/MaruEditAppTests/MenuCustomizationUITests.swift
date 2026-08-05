import AppKit
import MaruEditCore
import XCTest
@preconcurrency @testable import MaruEditApp


@preconcurrency @MainActor
final class MenuCustomizationUITests: XCTestCase {
    private let settings = CommandDefinition(id: .appSettings, title: "Settings") { _ in }
    private let find = CommandDefinition(id: .searchFind, title: "Find") { _ in }

    func testWindowHidesOptionalCommandsButProtectsRequiredCommandsAndRestores() async throws {
        var changes: [MenuCustomization] = []
        let controller = MenuCustomizationWindowController(
            definitions: [settings, find], protectedCommandIDs: [.appSettings],
            customization: .defaults, onChange: { changes.append($0) })

        controller.setVisibleForTesting(false, command: .appSettings)
        XCTAssertEqual(controller.checkboxForTesting(.appSettings)?.state, .on)
        XCTAssertEqual(controller.currentCustomization, .defaults)

        controller.setVisibleForTesting(false, command: .searchFind)
        XCTAssertEqual(controller.currentCustomization.hiddenCommandIDs, [.searchFind])
        XCTAssertEqual(changes.last?.hiddenCommandIDs, [.searchFind])

        controller.restoreForTesting()
        XCTAssertEqual(controller.currentCustomization, .defaults)
        XCTAssertEqual(controller.checkboxForTesting(.searchFind)?.state, .on)
    }

    func testApplyingCustomizationUsesIDsAndNeverHidesSystemOrProtectedItems() async {
        let root = NSMenu()
        let menu = NSMenu(title: "Test")
        let top = NSMenuItem(); top.submenu = menu; root.addItem(top)
        menu.addItem(NSMenuItem(title: "About Localized However", action: nil, keyEquivalent: ""))
        menu.addItem(.separator())
        let protected = NSMenuItem(title: "Localized Settings", action: nil, keyEquivalent: "")
        protected.representedObject = CommandID.appSettings
        menu.addItem(protected)
        let group = NSMenuItem(title: "Localized Group", action: nil, keyEquivalent: "")
        group.identifier = NSUserInterfaceItemIdentifier("menu.group.test")
        let submenu = NSMenu()
        let optional = NSMenuItem(title: "Localized Find", action: nil, keyEquivalent: "")
        optional.representedObject = CommandID.searchFind
        submenu.addItem(optional)
        group.submenu = submenu
        menu.addItem(group)

        AppDelegate.applyMenuCustomization(
            MenuCustomization(hiddenCommandIDs: [.appSettings, .searchFind]),
            protectedCommandIDs: [.appSettings], to: root)

        XCTAssertFalse(menu.items[0].isHidden, "system item has no Command ID and is protected by construction")
        XCTAssertFalse(protected.isHidden)
        XCTAssertTrue(optional.isHidden)
        XCTAssertTrue(group.isHidden, "an empty optional command group should collapse")
    }

    func testBuiltApplicationMenuContainsRequiredMacOSItems() async {
        _ = NSApplication.shared
        let delegate = AppDelegate()
        delegate.buildMenu()
        let menus = NSApp.mainMenu?.items.compactMap(\.submenu) ?? []
        let allTitles = Set(menus.flatMap { $0.items.map(\.title) })
        for required in ["About MaruEdit", "Services", "Hide MaruEdit", "Hide Others",
                         "Show All", "Quit MaruEdit", "Undo", "Redo", "Minimize", "Zoom"] {
            XCTAssertTrue(allTitles.contains(required), "missing required menu item \(required)")
        }
    }

    func testBusinessMenuOrderMatchesHidemaru() async {
        _ = NSApplication.shared
        let delegate = AppDelegate(); delegate.buildMenu()
        let titles = NSApp.mainMenu?.items.compactMap { $0.submenu?.title } ?? []
        XCTAssertEqual(Array(titles.dropFirst()), [
            "File", "Edit", "Convert", "View", "Insert", "Search", "Highlight",
            "Bookmark", "Tools", "Window", "Macro", "Other", "Help",
        ])
    }

    func testToolsMenuGroupsCompareTagsExternalCommandsAndCommandList() async {
        let app = AppDelegate()
        app.buildMenu()
        let tools = NSApp.mainMenu?.item(withTitle: "Tools")?.submenu
        let titles = tools?.items.map(\.title) ?? []
        XCTAssertTrue(titles.contains("Compare with Next Document"))
        XCTAssertTrue(titles.contains("Generate Tags File…"))
        XCTAssertTrue(titles.contains("Jump to Tag…"))
        XCTAssertTrue(titles.contains("External Commands"))
        XCTAssertTrue(titles.contains("Command List…"))
        XCTAssertNotNil(tools?.item(withTitle: "External Commands")?.submenu)
    }

    func testHelpMenuContainsSixConfigurableExternalHelpSlots() async {
        let app = AppDelegate(); app.buildMenu()
        let helpMenu = NSApp.mainMenu?.items.compactMap(\.submenu).first { $0.title == "Help" }
        let titles = helpMenu?.items.map(\.title) ?? []
        for slot in 1...6 { XCTAssertTrue(titles.contains("External Help \(slot)")) }
        XCTAssertTrue(titles.contains("Configure External Help…"))
    }

    func testOtherMenuProvidesCategorizedHistoryClearing() async {
        let app = AppDelegate(); app.buildMenu()
        let other = NSApp.mainMenu?.items.compactMap(\.submenu).first { $0.title == "Other" }
        let clear = other?.item(withTitle: "Clear History")?.submenu
        XCTAssertEqual(clear?.items.filter { !$0.isSeparatorItem }.map(\.title), [
            "Clear Find History", "Clear Replace History", "Clear Grep History",
            "Clear Clipboard History", "Clear Recent Files", "Clear Recent Project Folders",
            "Clear Recent Workspaces", "Clear Recent Encodings", "Clear All Histories",
        ])
    }
}
