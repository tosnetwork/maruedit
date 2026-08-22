import Foundation

/// Version reported by the bridge in `serverInfo`, and used to spot a bridge
/// and an app from different builds talking to each other.
public enum AgentBridgeVersion {
    public static let current = "0.1.6"
}
