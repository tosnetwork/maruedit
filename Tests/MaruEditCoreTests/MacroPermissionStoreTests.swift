import XCTest
@testable import MaruEditCore

final class MacroPermissionStoreTests: XCTestCase {
    func testStoresAllowedDeniedAndDirectoryBookmarkByMacro() {
        let store = makeStore()
        let one: CommandID = "macro.user.one"
        let two: CommandID = "macro.user.two"
        store.save(.init(macroID: one, permission: .otherFiles, decision: .allowed,
                         directoryBookmark: Data([1, 2]), directoryDisplayPath: "/tmp/Allowed"))
        store.save(.init(macroID: two, permission: .externalCommands, decision: .denied))
        XCTAssertEqual(store.decision(for: one, permission: .otherFiles)?.directoryBookmark, Data([1, 2]))
        XCTAssertEqual(store.decision(for: two, permission: .externalCommands)?.decision, .denied)
        store.revoke(macroID: one, permission: .otherFiles)
        XCTAssertNil(store.decision(for: one, permission: .otherFiles))
        XCTAssertNotNil(store.decision(for: two, permission: .externalCommands))
        store.revokeAll()
        XCTAssertEqual(store.load(), MacroPermissionState())
    }

    func testDuplicateGrantReplacesAndFutureOrCorruptSchemaFailsClosed() throws {
        let defaults = isolatedDefaults()
        let store = MacroPermissionStore(defaults: defaults)
        let id: CommandID = "macro.user.one"
        store.save(.init(macroID: id, permission: .externalCommands, decision: .allowed))
        store.save(.init(macroID: id, permission: .externalCommands, decision: .denied))
        XCTAssertEqual(store.load().grants.count, 1)
        XCTAssertEqual(store.load().grants[0].decision, .denied)
        defaults.set(Data("bad".utf8), forKey: "MacroPermissionState")
        XCTAssertEqual(store.load(), MacroPermissionState())
        let future = MacroPermissionState(schemaVersion: 99, grants: [])
        defaults.set(try JSONEncoder().encode(future), forKey: "MacroPermissionState")
        XCTAssertEqual(store.load(), MacroPermissionState())
    }

    private func makeStore() -> MacroPermissionStore {
        MacroPermissionStore(defaults: isolatedDefaults())
    }
    private func isolatedDefaults() -> UserDefaults {
        UserDefaults(suiteName: "MacroPermissionStoreTests.\(UUID().uuidString)")!
    }
}
