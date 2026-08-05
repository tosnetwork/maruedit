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
    public init(name: String, description: String, shortcut: String?,
                requiredPermissions: Set<MacroPermission>) {
        self.name = name; self.description = description; self.shortcut = shortcut
        self.requiredPermissions = requiredPermissions
    }
}

public struct UserMacro: Equatable, Sendable {
    public let id: CommandID
    public let url: URL
    public let source: String
    public let metadata: MacroMetadata
    public var isEnabled: Bool
    public init(id: CommandID, url: URL, source: String, metadata: MacroMetadata, isEnabled: Bool) {
        self.id = id; self.url = url; self.source = source; self.metadata = metadata
        self.isEnabled = isEnabled
    }
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
    public static func load(from directory: URL, disabledIDs: Set<CommandID> = [],
                            enableMaruCompatibility: Bool = false) -> MacroCatalog {
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
        for case let url as URL in enumerator {
            let extensionName = url.pathExtension.lowercased()
            guard extensionName == "js" || (enableMaruCompatibility && extensionName == "mac") else { continue }
            do {
                let originalSource = try String(contentsOf: url, encoding: .utf8)
                let source = extensionName == "mac"
                    ? try MaruCompatibility.translate(originalSource) : originalSource
                let components = url.resolvingSymlinksInPath().standardizedFileURL.pathComponents
                let relative = components.dropFirst(baseComponents.count).joined(separator: "/")
                let prefix = extensionName == "mac" ? "macro.compat." : "macro.user."
                let id = CommandID(prefix + stableComponent(relative))
                var metadata = parseMetadata(originalSource, fallbackName: url.deletingPathExtension().lastPathComponent)
                if extensionName == "mac" {
                    metadata.name += " (Experimental)"
                    metadata.description = "Experimental Maru-compatible subset. " + metadata.description
                    metadata.requiredPermissions = [.currentDocument]
                }
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
