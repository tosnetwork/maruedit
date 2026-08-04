import Foundation

public struct MenuCustomization: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1
    public var schemaVersion: Int
    public var hiddenCommandIDs: [CommandID]

    public init(
        schemaVersion: Int = currentSchemaVersion,
        hiddenCommandIDs: [CommandID] = []
    ) {
        self.schemaVersion = schemaVersion
        self.hiddenCommandIDs = Self.normalized(hiddenCommandIDs)
    }

    public static let defaults = MenuCustomization()
    public var hiddenCommands: Set<CommandID> { Set(hiddenCommandIDs) }

    public mutating func setVisible(_ visible: Bool, command: CommandID) {
        var hidden = hiddenCommands
        if visible { hidden.remove(command) } else { hidden.insert(command) }
        hiddenCommandIDs = Self.normalized(Array(hidden))
    }

    static func normalized(_ commands: [CommandID]) -> [CommandID] {
        Set(commands.filter { !$0.rawValue.isEmpty }).sorted { $0.rawValue < $1.rawValue }
    }
}

public final class MenuCustomizationStore {
    private let defaults: UserDefaults
    private let key: String

    public init(defaults: UserDefaults = .standard, key: String = "MaruEditMenuCustomization") {
        self.defaults = defaults
        self.key = key
    }

    public func load() -> MenuCustomization {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode(MenuCustomization.self, from: data),
              decoded.schemaVersion <= MenuCustomization.currentSchemaVersion else {
            return .defaults
        }
        return Self.migrate(decoded)
    }

    public func save(_ customization: MenuCustomization) {
        let migrated = Self.migrate(customization)
        guard let data = try? JSONEncoder().encode(migrated) else { return }
        defaults.set(data, forKey: key)
    }

    public func restoreDefaults() {
        defaults.removeObject(forKey: key)
    }

    public static func migrate(_ customization: MenuCustomization) -> MenuCustomization {
        MenuCustomization(
            schemaVersion: MenuCustomization.currentSchemaVersion,
            hiddenCommandIDs: customization.hiddenCommandIDs)
    }
}
