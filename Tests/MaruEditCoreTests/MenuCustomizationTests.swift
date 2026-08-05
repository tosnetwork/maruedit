import XCTest
@testable import MaruEditCore

final class MenuCustomizationTests: XCTestCase {
    func testSchemaStoresOnlySortedUniqueCommandIDs() throws {
        var value = MenuCustomization(hiddenCommandIDs: [
            CommandID("search.find"), CommandID("file.save"), CommandID("search.find"),
        ])
        value.setVisible(true, command: CommandID("file.save"))
        value.setVisible(false, command: CommandID("view.toggleWrap"))
        XCTAssertEqual(value.hiddenCommandIDs.map(\.rawValue), ["search.find", "view.toggleWrap"])

        let json = String(data: try JSONEncoder().encode(value), encoding: .utf8)!
        XCTAssertTrue(json.contains("hiddenCommandIDs"))
        XCTAssertTrue(json.contains("hiddenTopLevelMenus"))
        XCTAssertFalse(json.contains("Find"), "localized titles must never enter the schema")
    }

    func testOldMaruDefaultMenusAndExtendedMenuVisibility() {
        var value = MenuCustomization.defaults
        XCTAssertEqual(value.hiddenTopLevelMenus, [
            "Bookmark", "Convert", "Help", "Highlight", "Insert", "Tools",
        ])
        value.setMenuVisible(true, menu: "Convert")
        XCTAssertFalse(value.hiddenMenus.contains("Convert"))
        value.setMenuVisible(false, menu: "Convert")
        XCTAssertTrue(value.hiddenMenus.contains("Convert"))
        value.setMenuVisible(false, menu: "File")
        XCTAssertFalse(value.hiddenMenus.contains("File"), "the seven default menus cannot be hidden")
    }

    func testStoreRoundTripRestoreMigrationAndFutureFallback() throws {
        let suite = "MenuCustomizationTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = MenuCustomizationStore(defaults: defaults)
        store.save(MenuCustomization(
            schemaVersion: 0, hiddenCommandIDs: [CommandID("search.grep")]))
        XCTAssertEqual(store.load(), MenuCustomization(
            hiddenCommandIDs: [CommandID("search.grep")]))
        store.restoreDefaults()
        XCTAssertEqual(store.load(), .defaults)

        let future = MenuCustomization(
            schemaVersion: MenuCustomization.currentSchemaVersion + 1,
            hiddenCommandIDs: [CommandID("file.save")])
        defaults.set(try JSONEncoder().encode(future), forKey: "MaruEditMenuCustomization")
        XCTAssertEqual(store.load(), .defaults)
    }
}
