import XCTest
@testable import MaruEditCore

final class SearchHistoryStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var store: SearchHistoryStore!

    override func setUp() {
        super.setUp()
        let name = "SearchHistoryStoreTests-\(UUID())"
        defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        store = SearchHistoryStore(defaults: defaults, limit: 3)
    }

    func testHistoriesAreSeparateDeduplicatedAndLimited() {
        var state = SearchHistoryState()
        for value in ["one", "two", "three", "four", "two"] {
            store.record(value, in: .find, state: &state)
        }
        store.record("replacement", in: .replace, state: &state)
        store.record("folder query", in: .grep, state: &state)

        XCTAssertEqual(state.find, ["two", "four", "three"])
        XCTAssertEqual(state.replace, ["replacement"])
        XCTAssertEqual(state.grep, ["folder query"])
        XCTAssertEqual(store.load(), state)
    }

    func testDisablingPersistenceClearsMemoryAndStoredData() {
        var state = SearchHistoryState(find: ["secret"], replace: ["private"], grep: ["query"])
        store.save(state)
        store.setPersistenceEnabled(false, state: &state)

        XCTAssertFalse(state.isPersistenceEnabled)
        XCTAssertTrue(state.find.isEmpty)
        XCTAssertTrue(state.replace.isEmpty)
        XCTAssertTrue(state.grep.isEmpty)
        XCTAssertEqual(store.load(), state)
    }

    func testClearRemovesAllThreeHistories() {
        var state = SearchHistoryState(find: ["a"], replace: ["b"], grep: ["c"])
        store.clear(&state)
        XCTAssertEqual(state.find, [])
        XCTAssertEqual(state.replace, [])
        XCTAssertEqual(state.grep, [])
    }

    func testCategorizedClearPreservesOtherHistoriesAndPersists() {
        var state = SearchHistoryState(find: ["a"], replace: ["b"], grep: ["c"])
        store.clear(.replace, state: &state)
        XCTAssertEqual(state.find, ["a"])
        XCTAssertEqual(state.replace, [])
        XCTAssertEqual(state.grep, ["c"])
        XCTAssertEqual(store.load(), state)
    }

    func testCorruptDataFallsBackWithoutCrashing() {
        defaults.set(Data("not-json".utf8), forKey: "MaruEditSearchHistory")
        XCTAssertEqual(store.load(), SearchHistoryState())
    }

    func testMigrationStampsSchemaAndNormalizesOldData() throws {
        let old = SearchHistoryState(schemaVersion: 0, find: ["a", "a", "b", "c", "d"])
        defaults.set(try JSONEncoder().encode(old), forKey: "MaruEditSearchHistory")
        let loaded = store.load()
        XCTAssertEqual(loaded.schemaVersion, SearchHistoryState.currentSchemaVersion)
        XCTAssertEqual(loaded.find, ["a", "b", "c"])
    }

    func testEncodedStateContainsQueriesButNoMatchedContentField() throws {
        let state = SearchHistoryState(find: ["needle"])
        let text = String(decoding: try JSONEncoder().encode(state), as: UTF8.self)
        XCTAssertTrue(text.contains("needle"))
        XCTAssertFalse(text.contains("preview"))
        XCTAssertFalse(text.contains("content"))
        XCTAssertFalse(text.contains("result"))
    }
}
