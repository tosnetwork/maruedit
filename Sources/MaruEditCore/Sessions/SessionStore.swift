import Foundation

/// Loads and saves `SessionState` to a JSON file (not `UserDefaults` — see
/// ROADMAP.md M1-05 and section 7's `Sessions/SessionStore.swift`), so a
/// corrupt session can be quarantined as a file rather than needing
/// special-cased `UserDefaults` cleanup.
///
/// Not a singleton: callers own an instance, per the "avoid new
/// singletons" principle from M1-02.
public final class SessionStore {
    public let fileURL: URL

    public init(fileURL: URL = SessionStore.defaultFileURL()) {
        self.fileURL = fileURL
    }

    public static func defaultFileURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return base
            .appendingPathComponent("MaruEdit", isDirectory: true)
            .appendingPathComponent("session.json")
    }

    /// Loads the stored session, migrating older schema versions.
    /// Returns `.empty` if nothing is stored yet. If a file exists but
    /// can't be decoded, it is quarantined — renamed aside with a
    /// `.corrupt-<timestamp>` suffix, never deleted or overwritten — and
    /// `.empty` is returned. Corrupt session data must never prevent the
    /// app from starting; it always gets a clean session instead.
    public func load() -> SessionState {
        guard let data = try? Data(contentsOf: fileURL) else {
            return .empty
        }
        guard let decoded = try? JSONDecoder().decode(SessionState.self, from: data) else {
            quarantineCorruptFile()
            return .empty
        }
        return Self.migrate(decoded)
    }

    public func save(_ state: SessionState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? AtomicFileWriter.write(data, to: fileURL)
    }

    private func quarantineCorruptFile() {
        let quarantined = fileURL.deletingLastPathComponent()
            .appendingPathComponent("session.json.corrupt-\(Int(Date().timeIntervalSince1970))")
        try? FileManager.default.moveItem(at: fileURL, to: quarantined)
    }

    /// Migration entry point: brings a decoded, possibly-older schema up
    /// to `SessionState.currentSchemaVersion`. Currently the identity
    /// function beyond re-stamping the version, since there is only one
    /// version so far — this is where a future bump adds real steps.
    static func migrate(_ state: SessionState) -> SessionState {
        var migrated = state
        migrated.schemaVersion = SessionState.currentSchemaVersion
        return migrated
    }
}
