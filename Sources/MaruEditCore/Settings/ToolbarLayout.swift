import Foundation

public enum ToolbarDisplayMode: String, Codable, CaseIterable, Sendable {
    case iconOnly
    case iconAndText
    case textOnly
}

public enum ToolbarIconSize: String, Codable, CaseIterable, Sendable {
    case small, medium, large

    public var pointSize: Double {
        switch self { case .small: 13; case .medium: 17; case .large: 21 }
    }
}

/// Persistent ordered toolbar contents. Command/responder keys and separators
/// share one sequence so customization round-trips without losing grouping.
public struct ToolbarLayout: Codable, Equatable, Sendable {
    public static let separator = "-"
    public var entries: [String]

    public init(entries: [String]) {
        self.entries = entries
    }

    public func normalized(availableKeys: Set<String>) -> ToolbarLayout {
        var seen = Set<String>()
        var result: [String] = []
        for entry in entries {
            if entry == Self.separator {
                guard result.last != Self.separator, !result.isEmpty else { continue }
                result.append(entry)
            } else if availableKeys.contains(entry), seen.insert(entry).inserted {
                result.append(entry)
            }
        }
        while result.last == Self.separator { result.removeLast() }
        return ToolbarLayout(entries: result)
    }

    public mutating func remove(_ key: String) {
        entries.removeAll { $0 == key }
        self = normalized(availableKeys: Set(entries.filter { $0 != Self.separator }))
    }

    public mutating func append(_ key: String, availableKeys: Set<String>) {
        guard availableKeys.contains(key), !entries.contains(key) else { return }
        entries.append(key)
        self = normalized(availableKeys: availableKeys)
    }

    public mutating func move(_ key: String, offset: Int, availableKeys: Set<String>) {
        guard let source = entries.firstIndex(of: key) else { return }
        let destination = max(0, min(entries.count - 1, source + offset))
        guard source != destination else { return }
        entries.remove(at: source)
        entries.insert(key, at: destination)
        self = normalized(availableKeys: availableKeys)
    }

    public mutating func insertSeparator(after key: String) {
        guard let index = entries.firstIndex(of: key), index + 1 < entries.count,
              entries[index + 1] != Self.separator else { return }
        entries.insert(Self.separator, at: index + 1)
    }
}
