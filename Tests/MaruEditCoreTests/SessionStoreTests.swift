import XCTest
@testable import MaruEditCore

final class SessionStoreTests: XCTestCase {

    private func makeStore() -> (SessionStore, URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SessionStoreTests-\(UUID().uuidString)", isDirectory: true)
        let fileURL = dir.appendingPathComponent("session.json")
        return (SessionStore(fileURL: fileURL), dir)
    }

    func testLoadWithNothingStoredReturnsEmpty() {
        let (store, dir) = makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        XCTAssertEqual(store.load(), .empty)
    }

    func testSaveThenLoadRoundTrips() {
        let (store, dir) = makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        let state = SessionState(
            rootFolderPath: "/Users/tester/project",
            openFiles: [
                OpenFileState(path: "/Users/tester/project/a.swift", cursorPosition: 42, scrollOffsetX: 0, scrollOffsetY: 120.5, collapsedFoldIDs: ["type:Editor:0"]),
                OpenFileState(path: "/Users/tester/project/b.swift", cursorPosition: 0, scrollOffsetX: 0, scrollOffsetY: 0)
            ],
            activeIndex: 1,
            windowZoomed: true,
            sidebarCollapsed: false
        )
        store.save(state)

        XCTAssertEqual(store.load(), state)
    }

    func testCorruptFileIsQuarantinedNotLost() throws {
        let (store, dir) = makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("not valid json".utf8).write(to: store.fileURL)

        let loaded = store.load()
        XCTAssertEqual(loaded, .empty, "corrupt session data must fall back to a clean session, not crash")

        XCTAssertFalse(FileManager.default.fileExists(atPath: store.fileURL.path), "the corrupt file should have been moved aside, not left in place")
        let quarantinedFiles = try FileManager.default.contentsOfDirectory(atPath: dir.path)
            .filter { $0.hasPrefix("session.json.corrupt-") }
        XCTAssertEqual(quarantinedFiles.count, 1, "the corrupt file should be preserved under a quarantine name, not deleted")
    }

    func testMigrateStampsCurrentSchemaVersion() {
        var older = SessionState.empty
        older.schemaVersion = 0
        let migrated = SessionStore.migrate(older)
        XCTAssertEqual(migrated.schemaVersion, SessionState.currentSchemaVersion)
    }

    func testDefaultFileURLLivesUnderApplicationSupportMaruEdit() {
        let url = SessionStore.defaultFileURL()
        XCTAssertEqual(url.lastPathComponent, "session.json")
        XCTAssertEqual(url.deletingLastPathComponent().lastPathComponent, "MaruEdit")
    }
}
