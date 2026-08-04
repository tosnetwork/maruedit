import Foundation

/// Stores one JSON file per unnamed document's `RecoveryRecord` under
/// `~/Library/Application Support/MaruEdit/Recovery/<id>.json` — local
/// only, never uploaded anywhere (ROADMAP.md M2-07: "Store content
/// locally under Application Support only").
///
/// One file per record, not a single combined blob like `SessionStore`:
/// several unnamed documents can be open and autosaving independently at
/// once, and per-record files avoid one document's debounced write
/// racing another's.
///
/// Not a singleton: callers own an instance, per the "avoid new
/// singletons" principle from M1-02.
public final class RecoveryStore {
    private let directory: URL

    public init(directory: URL = RecoveryStore.defaultDirectory()) {
        self.directory = directory
    }

    public static func defaultDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return base
            .appendingPathComponent("MaruEdit", isDirectory: true)
            .appendingPathComponent("Recovery", isDirectory: true)
    }

    private func fileURL(for id: RecoveryID) -> URL {
        directory.appendingPathComponent("\(id.rawValue).json")
    }

    public func save(_ record: RecoveryRecord) {
        guard let data = try? JSONEncoder().encode(record) else { return }
        try? AtomicFileWriter.write(data, to: fileURL(for: record.recoveryID))
    }

    public func load(_ id: RecoveryID) -> RecoveryRecord? {
        guard let data = try? Data(contentsOf: fileURL(for: id)) else { return nil }
        guard let decoded = try? JSONDecoder().decode(RecoveryRecord.self, from: data) else { return nil }
        return Self.migrate(decoded)
    }

    /// Removes one document's recovery record — called when it's no
    /// longer needed: the user explicitly discarded the document (closed
    /// without saving), or it gained a real file (Save As), which is its
    /// own recovery mechanism from then on.
    public func delete(_ id: RecoveryID) {
        try? FileManager.default.removeItem(at: fileURL(for: id))
    }

    /// Every recovery record currently on disk, for offering recovery of
    /// unnamed documents at launch. Corrupt individual files are skipped,
    /// not surfaced as an error — losing the recovery of one unsaved
    /// scratch buffer is not the kind of failure that should block
    /// launch or need a quarantine dance the way `SessionStore` needs one
    /// for its single higher-stakes file.
    public func loadAll() -> [RecoveryRecord] {
        guard let filenames = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else {
            return []
        }
        return filenames.compactMap { name -> RecoveryRecord? in
            guard name.hasSuffix(".json") else { return nil }
            guard let data = try? Data(contentsOf: directory.appendingPathComponent(name)) else { return nil }
            guard let decoded = try? JSONDecoder().decode(RecoveryRecord.self, from: data) else { return nil }
            return Self.migrate(decoded)
        }
    }

    /// Deletes every recovery record (ROADMAP.md M2-07, "Add a command
    /// to clear recovery data").
    public func clearAll() {
        for record in loadAll() {
            delete(record.recoveryID)
        }
    }

    static func migrate(_ record: RecoveryRecord) -> RecoveryRecord {
        var migrated = record
        migrated.schemaVersion = RecoveryRecord.currentSchemaVersion
        return migrated
    }
}
