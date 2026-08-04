import Foundation

/// A stable identifier for one document's crash-recovery record,
/// independent of any file path (unnamed documents have none). Generated
/// once per document and kept for its lifetime.
public struct RecoveryID: RawRepresentable, Hashable, Codable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    /// Generates a fresh, unique ID for a new document.
    public init() {
        self.rawValue = UUID().uuidString
    }
}

/// A recoverable snapshot of one unnamed document's unsaved content
/// (ROADMAP.md M2-07). Deliberately does not carry a file path — by
/// definition, an unnamed document has none; recovery restores it as a
/// new unsaved tab, not by writing back to a specific location.
public struct RecoveryRecord: Codable, Sendable, Equatable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var recoveryID: RecoveryID
    public var content: String
    public var encoding: TextEncoding
    public var selectionLocation: Int
    public var selectionLength: Int
    public var savedAt: Date

    public init(
        schemaVersion: Int = RecoveryRecord.currentSchemaVersion,
        recoveryID: RecoveryID,
        content: String,
        encoding: TextEncoding,
        selectionLocation: Int,
        selectionLength: Int,
        savedAt: Date = Date()
    ) {
        self.schemaVersion = schemaVersion
        self.recoveryID = recoveryID
        self.content = content
        self.encoding = encoding
        self.selectionLocation = selectionLocation
        self.selectionLength = selectionLength
        self.savedAt = savedAt
    }
}
