import Foundation

public enum FileTypeProfileError: LocalizedError {
    case unsupportedSchema(Int)
    public var errorDescription: String? {
        switch self { case .unsupportedSchema(let version): "Unsupported file-type profile schema \(version)." }
    }
}

public final class FileTypeProfileStore {
    public let directory: URL
    public init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MaruEdit/FileTypeProfiles", isDirectory: true)
    }

    public func loadUserProfiles() -> [FileTypeProfile] {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil)
            .filter({ $0.pathExtension.lowercased() == "json" }) else { return [] }
        return urls.sorted { $0.lastPathComponent < $1.lastPathComponent }.compactMap {
            guard let data = try? Data(contentsOf: $0),
                  let profile = try? JSONDecoder().decode(FileTypeProfile.self, from: data),
                  let migrated = try? migrate(profile) else { return nil }
            return migrated
        }
    }

    public func saveUserProfile(_ profile: FileTypeProfile) throws {
        guard profile.schemaVersion == FileTypeProfile.currentSchemaVersion else {
            throw FileTypeProfileError.unsupportedSchema(profile.schemaVersion)
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try export(profile, to: directory.appendingPathComponent(safeFilename(profile.id) + ".json"))
    }

    public func importProfile(from url: URL) throws -> FileTypeProfile {
        let decoded = try JSONDecoder().decode(FileTypeProfile.self, from: Data(contentsOf: url))
        let profile = try migrate(decoded)
        try saveUserProfile(profile)
        return profile
    }

    public func export(_ profile: FileTypeProfile, to url: URL) throws {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(profile).write(to: url, options: .atomic)
    }

    public func resolver() -> FileTypeProfileResolver {
        FileTypeProfileResolver(profiles:
            BuiltInFileTypeProfiles.all.map { SourcedFileTypeProfile($0, source: .builtIn) }
            + loadUserProfiles().map { SourcedFileTypeProfile($0, source: .user) })
    }

    private func safeFilename(_ id: String) -> String {
        id.map { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" ? $0 : "_" }.reduce("", { $0 + String($1) })
    }

    private func migrate(_ profile: FileTypeProfile) throws -> FileTypeProfile {
        guard profile.schemaVersion <= FileTypeProfile.currentSchemaVersion else {
            throw FileTypeProfileError.unsupportedSchema(profile.schemaVersion)
        }
        var migrated = profile
        migrated.schemaVersion = FileTypeProfile.currentSchemaVersion
        return migrated
    }
}
