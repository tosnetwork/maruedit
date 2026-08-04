import Foundation

/// Loads, saves, and migrates the single `Preferences` blob under one
/// `UserDefaults` key, instead of scattering individual string keys
/// through the codebase (ROADMAP.md M1-04).
///
/// Not a singleton: callers own an instance and inject it where needed,
/// per the "avoid new singletons" principle from M1-02. `AppCoordinator`
/// is expected to own the app's one instance once something consumes it.
public final class PreferencesStore {
    private let defaults: UserDefaults
    private let key: String

    public init(defaults: UserDefaults = .standard, key: String = "MaruEditPreferences") {
        self.defaults = defaults
        self.key = key
    }

    /// Loads stored preferences, migrating older schema versions and
    /// falling back to `Preferences.defaults` if nothing is stored or the
    /// stored data can't be decoded. Never throws: corrupt or missing
    /// preferences must never prevent the app from starting.
    public func load() -> Preferences {
        guard let data = defaults.data(forKey: key) else {
            return .defaults
        }
        guard let decoded = try? JSONDecoder().decode(Preferences.self, from: data) else {
            return .defaults
        }
        return Self.migrate(decoded)
    }

    public func save(_ preferences: Preferences) {
        guard let data = try? JSONEncoder().encode(preferences) else { return }
        defaults.set(data, forKey: key)
    }

    /// Removes the stored blob entirely, so the next `load()` returns
    /// `Preferences.defaults`.
    public func resetToDefaults() {
        defaults.removeObject(forKey: key)
    }

    /// Migration entry point: brings a decoded, possibly-older schema up
    /// to `Preferences.currentSchemaVersion`. There is only one version
    /// so far, so this currently just re-stamps the version number — this
    /// is where a future version bump adds real field migrations.
    static func migrate(_ preferences: Preferences) -> Preferences {
        var migrated = preferences
        migrated.schemaVersion = Preferences.currentSchemaVersion
        return migrated
    }
}
