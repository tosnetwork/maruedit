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
        prefs.invisibleCharacters = InvisibleCharacterOptions(
            spaces: true, tabs: false, lineEndings: true, fullWidthSpaces: true)
        prefs.theme = .monokai
        prefs.workspaceStyle = .modern
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

        let loaded = store.load()
        XCTAssertEqual(loaded.fontName, "SF Mono")
        XCTAssertEqual(loaded.theme, .monokai)
        XCTAssertEqual(loaded.workspaceStyle, .modern)
    }

    func testMigrateStampsCurrentSchemaVersion() {
        var older = Preferences.defaults
        older.schemaVersion = 0
        let migrated = PreferencesStore.migrate(older)
        XCTAssertEqual(migrated.schemaVersion, Preferences.currentSchemaVersion)
    }

    func testVersionOnePreferencesMigrateWithInvisibleMarkersOff() throws {
        let json = """
        {"schemaVersion":1,"fontName":"SF Mono","fontSize":13,"theme":"monokai",
         "showLineNumbers":true,"wrapLines":false,"tabWidth":4}
        """
        let decoded = try JSONDecoder().decode(Preferences.self, from: Data(json.utf8))
        let migrated = PreferencesStore.migrate(decoded)
        XCTAssertEqual(migrated.schemaVersion, 4)
        XCTAssertEqual(migrated.invisibleCharacters, .none)
        XCTAssertEqual(migrated.workspaceStyle, .modern)
        XCTAssertEqual(migrated.classicChrome, .allVisible)
    }

    func testExportImportRestoreAndRejectFutureSchema() throws {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("MaruEditSettings-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        var preferences = Preferences.defaults
        preferences.fontSize = 17
        preferences.invisibleCharacters.tabs = true
        try store.export(preferences, to: url)
        XCTAssertEqual(try store.importSettings(from: url), preferences)

        store.save(preferences)
        store.resetToDefaults()
        XCTAssertEqual(store.load(), .defaults)

        preferences.schemaVersion = Preferences.currentSchemaVersion + 1
        try JSONEncoder().encode(preferences).write(to: url)
        XCTAssertThrowsError(try store.importSettings(from: url))
    }
}
