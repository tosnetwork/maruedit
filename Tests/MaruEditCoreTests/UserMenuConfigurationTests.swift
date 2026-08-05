import MaruEditCore
import XCTest

final class UserMenuConfigurationTests: XCTestCase {
    func testEightMenusNormalizeOrderDuplicatesAndSeparators() {
        var subject = UserMenuConfiguration(menus: [[
            " file.open ", "-", "-", "file.save", "file.open", "-",
        ]])
        XCTAssertEqual(subject.menus.count, 8)
        XCTAssertEqual(subject[0], ["file.open", "-", "file.save"])
        subject[7] = ["search.find", "search.replace"]
        XCTAssertEqual(subject[7], ["search.find", "search.replace"])
    }

    func testStoreRoundTripsAndRestoresDefaults() throws {
        let suite = "UserMenuConfigurationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = UserMenuConfigurationStore(defaults: defaults)
        let value = UserMenuConfiguration(menus: [["file.open", "-", "search.find"]])
        store.save(value)
        XCTAssertEqual(store.load(), value)
        store.restoreDefaults()
        XCTAssertEqual(store.load(), UserMenuConfiguration())
    }
}
