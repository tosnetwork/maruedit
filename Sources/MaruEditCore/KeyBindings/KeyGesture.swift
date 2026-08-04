import Foundation

public enum KeyModifier: String, Codable, CaseIterable, Hashable, Sendable {
    case control = "ctrl"
    case option = "opt"
    case shift
    case command = "cmd"

    fileprivate var order: Int {
        switch self { case .command: 0; case .control: 1; case .option: 2; case .shift: 3 }
    }
}

/// Portable, layout-aware key representation used in JSON profiles.
public struct KeyGesture: Hashable, Sendable, CustomStringConvertible {
    public let key: String
    public let modifiers: Set<KeyModifier>

    public init(key: String, modifiers: Set<KeyModifier> = []) {
        self.key = key.lowercased()
        self.modifiers = modifiers
    }

    public init?(_ notation: String) {
        let parts = notation.lowercased().split(separator: "+").map(String.init)
        guard let key = parts.last, !key.isEmpty else { return nil }
        var modifiers = Set<KeyModifier>()
        for token in parts.dropLast() {
            guard let modifier = KeyModifier(rawValue: token), modifiers.insert(modifier).inserted else { return nil }
        }
        self.init(key: key, modifiers: modifiers)
    }

    public var description: String {
        (modifiers.sorted { $0.order < $1.order }.map(\.rawValue) + [key]).joined(separator: "+")
    }
}

extension KeyGesture: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let notation = try container.decode(String.self)
        guard let value = KeyGesture(notation) else {
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "Invalid key gesture: \(notation)")
        }
        self = value
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }
}
