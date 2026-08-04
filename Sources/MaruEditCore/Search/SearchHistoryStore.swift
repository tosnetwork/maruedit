import Foundation

/// Versioned, privacy-limited history for user-entered search strings.
/// Matched document text and result previews are never part of this model.
public struct SearchHistoryState: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var isPersistenceEnabled: Bool
    public var find: [String]
    public var replace: [String]
    public var grep: [String]

    public init(
        schemaVersion: Int = Self.currentSchemaVersion,
        isPersistenceEnabled: Bool = true,
        find: [String] = [],
        replace: [String] = [],
        grep: [String] = []
    ) {
        self.schemaVersion = schemaVersion
        self.isPersistenceEnabled = isPersistenceEnabled
        self.find = find
        self.replace = replace
        self.grep = grep
    }
}

public final class SearchHistoryStore {
    public static let defaultLimit = 20

    private let defaults: UserDefaults
    private let key: String
    private let limit: Int

    public init(
        defaults: UserDefaults = .standard,
        key: String = "MaruEditSearchHistory",
        limit: Int = SearchHistoryStore.defaultLimit
    ) {
        self.defaults = defaults
        self.key = key
        self.limit = max(0, limit)
    }

    public func load() -> SearchHistoryState {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode(SearchHistoryState.self, from: data)
        else { return SearchHistoryState() }
        return normalized(decoded)
    }

    public func save(_ state: SearchHistoryState) {
        let state = normalized(state)
        guard let data = try? JSONEncoder().encode(state) else { return }
        defaults.set(data, forKey: key)
    }

    public func record(_ value: String, in kind: Kind, state: inout SearchHistoryState) {
        guard !value.isEmpty else { return }
        switch kind {
        case .find: Self.insert(value, into: &state.find, limit: limit)
        case .replace: Self.insert(value, into: &state.replace, limit: limit)
        case .grep: Self.insert(value, into: &state.grep, limit: limit)
        }
        save(state)
    }

    public func clear(_ state: inout SearchHistoryState) {
        state.find.removeAll()
        state.replace.removeAll()
        state.grep.removeAll()
        save(state)
    }

    public func setPersistenceEnabled(_ enabled: Bool, state: inout SearchHistoryState) {
        state.isPersistenceEnabled = enabled
        if !enabled {
            state.find.removeAll()
            state.replace.removeAll()
            state.grep.removeAll()
        }
        save(state)
    }

    public enum Kind: Sendable { case find, replace, grep }

    private func normalized(_ state: SearchHistoryState) -> SearchHistoryState {
        var result = state
        result.schemaVersion = SearchHistoryState.currentSchemaVersion
        result.find = Self.normalized(result.find, limit: limit)
        result.replace = Self.normalized(result.replace, limit: limit)
        result.grep = Self.normalized(result.grep, limit: limit)
        return result
    }

    private static func insert(_ value: String, into values: inout [String], limit: Int) {
        values.removeAll { $0 == value }
        values.insert(value, at: 0)
        if values.count > limit { values.removeLast(values.count - limit) }
    }

    private static func normalized(_ values: [String], limit: Int) -> [String] {
        var result: [String] = []
        for value in values where !value.isEmpty && !result.contains(value) {
            result.append(value)
            if result.count == limit { break }
        }
        return result
    }
}
