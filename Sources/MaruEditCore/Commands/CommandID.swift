import Foundation

/// A stable identifier for a user-facing editor command (e.g. "file.save").
/// Menus, key bindings, macros, and the command palette all refer to
/// commands only by `CommandID` — never by selector or closure — so those
/// surfaces can be reconfigured independently of how a command is
/// implemented. Per ROADMAP.md ADR-006, published IDs must remain stable.
public struct CommandID: RawRepresentable, Hashable, Codable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }
}

extension CommandID: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) {
        self.rawValue = value
    }
}

extension CommandID: CustomStringConvertible {
    public var description: String { rawValue }
}
