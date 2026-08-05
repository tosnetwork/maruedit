import Foundation

public struct MenuCustomization: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 2
    public static let optionalTopLevelMenus = [
        "Convert", "Insert", "Highlight", "Bookmark", "Tools", "Help",
    ]
    public var schemaVersion: Int
    public var hiddenCommandIDs: [CommandID]
    public var hiddenTopLevelMenus: [String]

    public init(
        schemaVersion: Int = currentSchemaVersion,
        hiddenCommandIDs: [CommandID] = [],
        hiddenTopLevelMenus: [String] = optionalTopLevelMenus
    ) {
        self.schemaVersion = schemaVersion
        self.hiddenCommandIDs = Self.normalized(hiddenCommandIDs)
        self.hiddenTopLevelMenus = Self.normalizedMenus(hiddenTopLevelMenus)
    }

    public static let defaults = MenuCustomization()
    public var hiddenCommands: Set<CommandID> { Set(hiddenCommandIDs) }
    public var hiddenMenus: Set<String> { Set(hiddenTopLevelMenus) }

    public mutating func setVisible(_ visible: Bool, command: CommandID) {
        var hidden = hiddenCommands
        if visible { hidden.remove(command) } else { hidden.insert(command) }
        hiddenCommandIDs = Self.normalized(Array(hidden))
    }

    public mutating func setMenuVisible(_ visible: Bool, menu: String) {
        guard Self.optionalTopLevelMenus.contains(menu) else { return }
        var hidden = hiddenMenus
        if visible { hidden.remove(menu) } else { hidden.insert(menu) }
        hiddenTopLevelMenus = Self.normalizedMenus(Array(hidden))
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, hiddenCommandIDs, hiddenTopLevelMenus
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            schemaVersion: try values.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 0,
            hiddenCommandIDs: try values.decodeIfPresent([CommandID].self, forKey: .hiddenCommandIDs) ?? [],
            hiddenTopLevelMenus: try values.decodeIfPresent([String].self, forKey: .hiddenTopLevelMenus)
                ?? Self.optionalTopLevelMenus)
    }

    static func normalized(_ commands: [CommandID]) -> [CommandID] {
        Set(commands.filter { !$0.rawValue.isEmpty }).sorted { $0.rawValue < $1.rawValue }
    }

    static func normalizedMenus(_ menus: [String]) -> [String] {
        Set(menus.filter(optionalTopLevelMenus.contains)).sorted()
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
            hiddenCommandIDs: customization.hiddenCommandIDs,
            hiddenTopLevelMenus: customization.hiddenTopLevelMenus)
    }
}
