import Foundation

public struct KeyBinding: Codable, Hashable, Sendable {
    public var keys: [KeyGesture]
    public var command: CommandID

    public init(keys: [KeyGesture], command: CommandID) {
        self.keys = keys
        self.command = command
    }

    private enum CodingKeys: String, CodingKey { case keys, command }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        keys = try container.decode([KeyGesture].self, forKey: .keys)
        command = CommandID(try container.decode(String.self, forKey: .command))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(keys, forKey: .keys)
        try container.encode(command.rawValue, forKey: .command)
    }
}

public struct KeyBindingProfile: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1
    public var schemaVersion: Int
    public var name: String
    public var bindings: [KeyBinding]

    public init(name: String, bindings: [KeyBinding], schemaVersion: Int = currentSchemaVersion) {
        self.schemaVersion = schemaVersion
        self.name = name
        self.bindings = bindings
    }
}

public struct KeyBindingConflict: Equatable, Sendable {
    public let keys: [KeyGesture]
    public let commands: [CommandID]
}

public enum KeyBindingError: LocalizedError, Equatable {
    case unsupportedSchema(Int)
    case emptySequence(CommandID)

    public var errorDescription: String? {
        switch self {
        case .unsupportedSchema(let version): return "Unsupported key-binding schema version \(version)."
        case .emptySequence(let command): return "Command \(command.rawValue) has an empty key sequence."
        }
    }
}

public final class KeyBindingManager {
    public private(set) var activeProfile: KeyBindingProfile
    public private(set) var dynamicBindings: [KeyBinding] = []

    public init(profile: KeyBindingProfile = .macOSStandard) {
        self.activeProfile = profile
    }

    public func activate(_ profile: KeyBindingProfile) throws {
        guard profile.schemaVersion == KeyBindingProfile.currentSchemaVersion else {
            throw KeyBindingError.unsupportedSchema(profile.schemaVersion)
        }
        if let binding = profile.bindings.first(where: { $0.keys.isEmpty }) {
            throw KeyBindingError.emptySequence(binding.command)
        }
        activeProfile = profile
    }

    public func command(for keys: [KeyGesture]) -> CommandID? {
        bindings.first { $0.keys == keys }?.command
    }

    public func keys(for command: CommandID) -> [KeyGesture]? {
        bindings.first { $0.command == command }?.keys
    }

    public var bindings: [KeyBinding] { dynamicBindings + activeProfile.bindings }

    public func setDynamicBindings(_ bindings: [KeyBinding]) {
        dynamicBindings = bindings.filter { !$0.keys.isEmpty }
    }

    public var conflicts: [KeyBindingConflict] {
        Dictionary(grouping: bindings, by: \.keys)
            .compactMap { keys, bindings in
                let commands = Array(Set(bindings.map(\.command))).sorted { $0.rawValue < $1.rawValue }
                return commands.count > 1 ? KeyBindingConflict(keys: keys, commands: commands) : nil
            }
            .sorted { $0.keys.map(\.description).joined() < $1.keys.map(\.description).joined() }
    }

    /// A one-step command cannot also be the prefix of a chord: dispatch
    /// would otherwise have to guess whether to run now or wait.
    public var prefixConflicts: [KeyBindingConflict] {
        let singles = bindings.filter { $0.keys.count == 1 }
        return bindings.compactMap { binding in
            guard binding.keys.count == 2,
                  let single = singles.first(where: { $0.keys[0] == binding.keys[0] }) else { return nil }
            return KeyBindingConflict(keys: [binding.keys[0]], commands: [single.command, binding.command])
        }
    }

    public func exportJSON() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(activeProfile)
    }

    @discardableResult
    public func importJSON(_ data: Data) throws -> KeyBindingProfile {
        let profile = try JSONDecoder().decode(KeyBindingProfile.self, from: data)
        try activate(profile)
        return profile
    }

    public func export(to url: URL) throws { try exportJSON().write(to: url, options: .atomic) }

    @discardableResult
    public func `import`(from url: URL) throws -> KeyBindingProfile {
        try importJSON(Data(contentsOf: url))
    }

    public func restoreDefaults(_ profile: BuiltInKeyBindingProfile) {
        activeProfile = profile.profile
    }
}

public enum BuiltInKeyBindingProfile: String, CaseIterable, Sendable {
    case macOSStandard
    case maruClassic

    public var profile: KeyBindingProfile {
        switch self { case .macOSStandard: .macOSStandard; case .maruClassic: .maruClassic }
    }
}
