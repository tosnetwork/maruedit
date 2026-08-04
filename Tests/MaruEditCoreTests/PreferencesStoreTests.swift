import XCTest
@testable import MaruEditCore

final class PreferencesStoreTests: XCTestCase {

    /// A throwaway UserDefaults suite per test, so tests never touch the
    /// real user's preferences and never leak state between runs.
    private func makeStore() -> (PreferencesStore, UserDefaults, String) {
        let suiteName = "PreferencesStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        return (PreferencesStore(defaults: defaults), defaults, suiteName)
    }

    func testLoadWithNothingStoredReturnsDefaults() {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }

        XCTAssertEqual(store.load(), .defaults)
    }

    func testSaveThenLoadRoundTrips() {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }

        var prefs = Preferences.defaults
        prefs.fontSize = 16
        prefs.tabWidth = 2
        prefs.wrapLines = true
        prefs.theme = .monokai
        store.save(prefs)

        XCTAssertEqual(store.load(), prefs)
    }

    func testCorruptDataFallsBackToDefaultsWithoutCrashing() {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }

        defaults.set(Data("not valid json".utf8), forKey: "MaruEditPreferences")

        XCTAssertEqual(store.load(), .defaults, "corrupt preferences must fall back to deterministic defaults, not crash")
    }

    func testResetToDefaultsRemovesStoredPreferences() {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }

        var prefs = Preferences.defaults
        prefs.fontSize = 20
        store.save(prefs)
        XCTAssertEqual(store.load().fontSize, 20)

        store.resetToDefaults()
        XCTAssertEqual(store.load(), .defaults)
    }

    func testUnknownFutureFieldsDoNotCrashDecoding() {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }

        // Simulates a newer app version having added a field this
        // version of Preferences doesn't know about yet.
        let json = """
        {
          "schemaVersion": 1,
          "fontName": "SF Mono",
          "fontSize": 13,
          "theme": "monokai",
          "showLineNumbers": true,
          "wrapLines": false,
          "tabWidth": 4,
          "aFieldFromTheFuture": "ignored"
        }
        """
        defaults.set(Data(json.utf8), forKey: "MaruEditPreferences")

        XCTAssertEqual(store.load(), .defaults)
    }

    func testMigrateStampsCurrentSchemaVersion() {
        var older = Preferences.defaults
        older.schemaVersion = 0
        let migrated = PreferencesStore.migrate(older)
        XCTAssertEqual(migrated.schemaVersion, Preferences.currentSchemaVersion)
    }
}
