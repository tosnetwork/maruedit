import Foundation

public enum MacroPermission: String, Codable, CaseIterable, Sendable {
    case currentDocument
    case clipboard
    case otherFiles
    case externalCommands
    case network
}

public struct MacroMetadata: Equatable, Sendable {
    public var name: String
    public var description: String
    public var shortcut: String?
    public var requiredPermissions: Set<MacroPermission>
}

public struct UserMacro: Equatable, Sendable {
    public let id: CommandID
    public let url: URL
    public let source: String
    public let metadata: MacroMetadata
    public var isEnabled: Bool
}

public struct MacroCatalogIssue: Equatable, Sendable {
    public let url: URL
    public let message: String
}

public struct MacroCatalog: Equatable, Sendable {
    public var macros: [UserMacro]
    public var issues: [MacroCatalogIssue]
    public init(macros: [UserMacro], issues: [MacroCatalogIssue]) {
        self.macros = macros
        self.issues = issues
    }
}

public enum MacroCatalogLoader {
    public static func load(from directory: URL, disabledIDs: Set<CommandID> = []) -> MacroCatalog {
        let manager = FileManager.default
        do { try manager.createDirectory(at: directory, withIntermediateDirectories: true) }
        catch { return MacroCatalog(macros: [], issues: [.init(url: directory, message: error.localizedDescription)]) }
        guard let enumerator = manager.enumerator(
            at: directory, includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]) else {
            return MacroCatalog(macros: [], issues: [])
        }
        var macros: [UserMacro] = []
        var issues: [MacroCatalogIssue] = []
        let baseComponents = directory.resolvingSymlinksInPath().standardizedFileURL.pathComponents
        for case let url as URL in enumerator where url.pathExtension.lowercased() == "js" {
            do {
                let source = try String(contentsOf: url, encoding: .utf8)
                let components = url.resolvingSymlinksInPath().standardizedFileURL.pathComponents
                let relative = components.dropFirst(baseComponents.count).joined(separator: "/")
                let id = CommandID("macro.user." + stableComponent(relative))
                let metadata = parseMetadata(source, fallbackName: url.deletingPathExtension().lastPathComponent)
                macros.append(.init(id: id, url: url, source: source, metadata: metadata,
                                    isEnabled: !disabledIDs.contains(id)))
            } catch {
                issues.append(.init(url: url, message: error.localizedDescription))
            }
        }
        macros.sort { $0.metadata.name.localizedStandardCompare($1.metadata.name) == .orderedAscending }
        issues.sort { $0.url.path < $1.url.path }
        return MacroCatalog(macros: macros, issues: issues)
    }

    public static func parseMetadata(_ source: String, fallbackName: String) -> MacroMetadata {
        var fields: [String: String] = [:]
        for line in source.split(separator: "\n", omittingEmptySubsequences: false).prefix(40) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("// @maru-") else { continue }
            let body = trimmed.dropFirst("// @maru-".count)
            guard let separator = body.firstIndex(of: ":") else { continue }
            fields[String(body[..<separator]).lowercased()] =
                body[body.index(after: separator)...].trimmingCharacters(in: .whitespaces)
        }
        let permissions = Set((fields["permissions"] ?? "currentDocument")
            .split(separator: ",").compactMap { MacroPermission(rawValue: $0.trimmingCharacters(in: .whitespaces)) })
        return MacroMetadata(
            name: fields["name"].flatMap { $0.isEmpty ? nil : $0 } ?? fallbackName,
            description: fields["description"] ?? "",
            shortcut: fields["shortcut"].flatMap { $0.isEmpty ? nil : $0 },
            requiredPermissions: permissions.isEmpty ? [.currentDocument] : permissions)
    }

    private static func stableComponent(_ path: String) -> String {
        path.lowercased().unicodeScalars.map { scalar in
            CharacterSet.alphanumerics.contains(scalar) ? String(scalar) : "_"
        }.joined()
    }
}

public final class MacroEnablementStore {
    private let defaults: UserDefaults
    private let key: String
    public init(defaults: UserDefaults = .standard, key: String = "MacroDisabledCommandIDs") {
        self.defaults = defaults
        self.key = key
    }
    public func disabledIDs() -> Set<CommandID> {
        Set((defaults.stringArray(forKey: key) ?? []).map { CommandID($0) })
    }
    public func setEnabled(_ enabled: Bool, id: CommandID) {
        var values = disabledIDs()
        if enabled { values.remove(id) } else { values.insert(id) }
        defaults.set(values.map(\.rawValue).sorted(), forKey: key)
    }
}
