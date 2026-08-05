import Foundation

public enum ProfileFilePolicyError: LocalizedError {
    case templateTooLarge
    case templateNotUTF8
    case invalidBackupDirectory

    public var errorDescription: String? {
        switch self {
        case .templateTooLarge: "The template exceeds the 1 MiB safety limit."
        case .templateNotUTF8: "The template is not valid UTF-8."
        case .invalidBackupDirectory: "The configured backup directory is missing or invalid."
        }
    }
}

public enum ProfileFilePolicy {
    public static func loadTemplate(path: String) throws -> String {
        let data = try Data(contentsOf: URL(fileURLWithPath: path), options: .mappedIfSafe)
        guard data.count <= 1_024 * 1_024 else { throw ProfileFilePolicyError.templateTooLarge }
        guard let text = String(data: data, encoding: .utf8) else {
            throw ProfileFilePolicyError.templateNotUTF8
        }
        return text
    }

    public static func transformedForSave(_ text: String, policy: ProfileSavePolicy?) -> String {
        guard let policy else { return text }
        var value = text
        if policy.trimsTrailingWhitespace {
            value = value.split(separator: "\n", omittingEmptySubsequences: false)
                .map { $0.replacingOccurrences(of: #"[\t ]+$"#, with: "", options: .regularExpression) }
                .joined(separator: "\n")
        }
        if policy.ensuresFinalNewline, !value.isEmpty, !value.hasSuffix("\n") { value += "\n" }
        return value
    }

    @discardableResult
    public static func createBackup(of source: URL, settings: BackupSettings) throws -> URL? {
        guard settings.enabled, FileManager.default.fileExists(atPath: source.path) else { return nil }
        let directory: URL
        switch settings.destination {
        case .sibling: directory = source.deletingLastPathComponent()
        case .directory:
            guard let path = settings.directoryPath, !path.isEmpty else {
                throw ProfileFilePolicyError.invalidBackupDirectory
            }
            directory = URL(fileURLWithPath: path, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        let stamp = String(Int(Date().timeIntervalSince1970 * 1_000))
        let name = source.lastPathComponent + "." + stamp + settings.suffix
        let destination = directory.appendingPathComponent(name)
        try FileManager.default.copyItem(at: source, to: destination)

        let prefix = source.lastPathComponent + "."
        let backups = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil))?.filter {
                $0.lastPathComponent.hasPrefix(prefix) && $0.lastPathComponent.hasSuffix(settings.suffix)
            }.sorted { $0.lastPathComponent > $1.lastPathComponent } ?? []
        for stale in backups.dropFirst(max(1, settings.maximumCopies)) {
            try? FileManager.default.removeItem(at: stale)
        }
        return destination
    }
}
