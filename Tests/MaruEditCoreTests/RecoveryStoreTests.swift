import XCTest
@testable import MaruEditCore

final class RecoveryStoreTests: XCTestCase {

    private func makeStore() -> (RecoveryStore, URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("RecoveryStoreTests-\(UUID().uuidString)", isDirectory: true)
        return (RecoveryStore(directory: dir), dir)
    }

    private func record(content: String = "unsaved text") -> RecoveryRecord {
        RecoveryRecord(
            recoveryID: RecoveryID(),
            content: content,
            encoding: .utf8,
            selectionLocation: 3,
            selectionLength: 0
        )
    }

    func testLoadMissingRecordReturnsNil() {
        let (store, dir) = makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        XCTAssertNil(store.load(RecoveryID()))
    }

    func testSaveThenLoadRoundTrips() {
        let (store, dir) = makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        let r = record()
        store.save(r)

        XCTAssertEqual(store.load(r.recoveryID), r)
    }

    func testDeleteRemovesTheRecord() {
        let (store, dir) = makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        let r = record()
        store.save(r)
        XCTAssertNotNil(store.load(r.recoveryID))

        store.delete(r.recoveryID)
        XCTAssertNil(store.load(r.recoveryID))
    }

    func testLoadAllReturnsEveryRecordIndependently() {
        let (store, dir) = makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        let r1 = record(content: "first")
        let r2 = record(content: "second")
        let r3 = record(content: "third")
        store.save(r1)
        store.save(r2)
        store.save(r3)

        let all = store.loadAll()
        XCTAssertEqual(Set(all.map { $0.recoveryID }), Set([r1, r2, r3].map { $0.recoveryID }))
    }

    func testLoadAllSkipsCorruptFilesRatherThanFailing() throws {
        let (store, dir) = makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        let good = record(content: "good")
        store.save(good)

        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("not valid json".utf8).write(to: dir.appendingPathComponent("garbage.json"))

        let all = store.loadAll()
        XCTAssertEqual(all.map { $0.recoveryID }, [good.recoveryID], "a corrupt record must be skipped, not crash loadAll()")
    }

    func testClearAllRemovesEveryRecord() {
        let (store, dir) = makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        store.save(record())
        store.save(record())
        XCTAssertEqual(store.loadAll().count, 2)

        store.clearAll()
        XCTAssertTrue(store.loadAll().isEmpty)
    }

    func testMigrateStampsCurrentSchemaVersion() {
        var older = record()
        older.schemaVersion = 0
        let migrated = RecoveryStore.migrate(older)
        XCTAssertEqual(migrated.schemaVersion, RecoveryRecord.currentSchemaVersion)
    }

    func testEachDocumentGetsAUniqueStableID() {
        let a = RecoveryID()
        let b = RecoveryID()
        XCTAssertNotEqual(a, b)
    }

    func testInterruptedWriteArtifactCannotReplaceLastCompleteRecovery() throws {
        let (store, dir) = makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let complete = record(content: "last complete snapshot")
        store.save(complete)

        // Models termination after a same-directory temporary file was
        // created but before AtomicFileWriter's rename commit. RecoveryStore
        // considers only complete, decodable .json records.
        try Data(#"{"schemaVersion":1,"content":"partial""#.utf8)
            .write(to: dir.appendingPathComponent(".interrupted-write.tmp"))

        XCTAssertEqual(store.load(complete.recoveryID), complete)
        XCTAssertEqual(store.loadAll(), [complete])
    }

    func testRecoverySnapshotNeverWritesThroughToSourceFile() throws {
        let (store, dir) = makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = dir.deletingLastPathComponent()
            .appendingPathComponent("RecoverySource-\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: source) }
        try Data("source on disk".utf8).write(to: source)

        store.save(record(content: "newer unsaved text"))

        XCTAssertEqual(try String(contentsOf: source, encoding: .utf8), "source on disk")
        XCTAssertEqual(store.loadAll().map(\.content), ["newer unsaved text"])
    }
}
