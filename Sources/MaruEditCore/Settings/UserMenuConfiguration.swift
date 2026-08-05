import Foundation

public struct UserMenuConfiguration: Codable, Equatable, Sendable {
    public static let menuCount = 8
    public static let separator = "-"
    public var menus: [[String]]

    public init(menus: [[String]] = Array(repeating: [], count: menuCount)) {
        let normalized = menus.prefix(Self.menuCount).map(Self.normalize)
        self.menus = normalized + Array(
            repeating: [], count: max(0, Self.menuCount - normalized.count))
    }

    public subscript(index: Int) -> [String] {
        get { menus.indices.contains(index) ? menus[index] : [] }
        set {
            guard menus.indices.contains(index) else { return }
            menus[index] = Self.normalize(newValue)
        }
    }

    private static func normalize(_ entries: [String]) -> [String] {
        var result: [String] = []
        for raw in entries.prefix(200) {
            let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { continue }
            if value == separator {
                if !result.isEmpty, result.last != separator { result.append(value) }
            } else if !result.contains(value) {
                result.append(value)
            }
        }
        if result.last == separator { result.removeLast() }
        return result
    }
}

public final class UserMenuConfigurationStore {
    private let defaults: UserDefaults
    private let key: String

    public init(defaults: UserDefaults = .standard, key: String = "MaruEditUserMenus") {
        self.defaults = defaults
        self.key = key
    }

    public func load() -> UserMenuConfiguration {
        guard let data = defaults.data(forKey: key),
              let value = try? JSONDecoder().decode(UserMenuConfiguration.self, from: data) else {
            return UserMenuConfiguration()
        }
        return UserMenuConfiguration(menus: value.menus)
    }

    public func save(_ value: UserMenuConfiguration) {
        if let data = try? JSONEncoder().encode(value) { defaults.set(data, forKey: key) }
    }

    public func restoreDefaults() { defaults.removeObject(forKey: key) }
}
