import Foundation

public enum MacroPermissionDecision: String, Codable, Sendable {
    case allowed
    case denied
}

public struct MacroPermissionGrant: Codable, Equatable, Sendable {
    public var macroID: CommandID
    public var permission: MacroPermission
    public var decision: MacroPermissionDecision
    public var directoryBookmark: Data?
    public var directoryDisplayPath: String?

    public init(macroID: CommandID, permission: MacroPermission,
                decision: MacroPermissionDecision, directoryBookmark: Data? = nil,
                directoryDisplayPath: String? = nil) {
        self.macroID = macroID
        self.permission = permission
        self.decision = decision
        self.directoryBookmark = directoryBookmark
        self.directoryDisplayPath = directoryDisplayPath
    }
}

public struct MacroPermissionState: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1
    public var schemaVersion: Int
    public var grants: [MacroPermissionGrant]
    public init(schemaVersion: Int = currentSchemaVersion, grants: [MacroPermissionGrant] = []) {
        self.schemaVersion = schemaVersion
        self.grants = grants
    }
}

public final class MacroPermissionStore {
    private let defaults: UserDefaults
    private let key: String
    public init(defaults: UserDefaults = .standard, key: String = "MacroPermissionState") {
        self.defaults = defaults
        self.key = key
    }

    public func load() -> MacroPermissionState {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode(MacroPermissionState.self, from: data),
              decoded.schemaVersion <= MacroPermissionState.currentSchemaVersion else {
            return MacroPermissionState()
        }
        var state = decoded
        state.schemaVersion = MacroPermissionState.currentSchemaVersion
        state.grants = normalized(state.grants)
        return state
    }

    public func decision(for macroID: CommandID, permission: MacroPermission) -> MacroPermissionGrant? {
        load().grants.first { $0.macroID == macroID && $0.permission == permission }
    }

    public func save(_ grant: MacroPermissionGrant) {
        var state = load()
        state.grants.removeAll { $0.macroID == grant.macroID && $0.permission == grant.permission }
        state.grants.append(grant)
        state.grants = normalized(state.grants)
        if let data = try? JSONEncoder().encode(state) { defaults.set(data, forKey: key) }
    }

    public func revoke(macroID: CommandID, permission: MacroPermission? = nil) {
        var state = load()
        state.grants.removeAll {
            $0.macroID == macroID && (permission == nil || $0.permission == permission)
        }
        if let data = try? JSONEncoder().encode(state) { defaults.set(data, forKey: key) }
    }

    public func revokeAll() { defaults.removeObject(forKey: key) }

    private func normalized(_ grants: [MacroPermissionGrant]) -> [MacroPermissionGrant] {
        var result: [String: MacroPermissionGrant] = [:]
        for grant in grants { result[grant.macroID.rawValue + "\u{0}" + grant.permission.rawValue] = grant }
        return result.values.sorted {
            ($0.macroID.rawValue, $0.permission.rawValue) < ($1.macroID.rawValue, $1.permission.rawValue)
        }
    }
}

public struct MacroAuthorizationError: LocalizedError, Equatable, Sendable {
    public let macroID: CommandID
    public let permission: MacroPermission
    public let reason: String
    public init(macroID: CommandID, permission: MacroPermission, reason: String) {
        self.macroID = macroID; self.permission = permission; self.reason = reason
    }
    public var errorDescription: String? {
        "Macro \(macroID.rawValue) is not authorized for \(permission.rawValue): \(reason)"
    }
}
