import Foundation

/// The private bridge↔app protocol.
///
/// ADR-011's method catalog is superseded here: it had no representation for
/// ranged reads, transactions, revisions, or proposals. Rather than invent a
/// second public protocol, everything travels in one versioned envelope
/// wrapping a typed request and outcome, so the internal operation set tracks
/// the tool catalog without a separate negotiation.
public enum AgentEnvelope {
    /// Bumped when the envelope's own shape changes, independently of the tool
    /// catalog's version, because they age differently.
    public static let version = 1

    /// First frame on every connection, as ADR-011 §11 requires.
    public struct Hello: Equatable, Sendable {
        public let envelopeVersion: Int
        public let catalogVersion: Int
        public let token: String
        public let credential: String?
        public let clientName: String?
        public let bridgePID: Int32

        public init(
            envelopeVersion: Int = AgentEnvelope.version,
            catalogVersion: Int = AgentToolCatalog.version,
            token: String,
            credential: String?,
            clientName: String?,
            bridgePID: Int32
        ) {
            self.envelopeVersion = envelopeVersion
            self.catalogVersion = catalogVersion
            self.token = token
            self.credential = credential
            self.clientName = clientName
            self.bridgePID = bridgePID
        }

        public var json: JSONValue {
            .object([
                "kind": .string("control.hello"),
                "envelopeVersion": .int(envelopeVersion),
                "catalogVersion": .int(catalogVersion),
                "token": .string(token),
                "credential": credential.map(JSONValue.string) ?? .null,
                "clientName": clientName.map(JSONValue.string) ?? .null,
                "bridgePid": .int(Int(bridgePID)),
            ])
        }

        public static func parse(_ value: JSONValue) -> Hello? {
            guard value["kind"]?.stringValue == "control.hello",
                  let envelopeVersion = value["envelopeVersion"]?.intValue,
                  let catalogVersion = value["catalogVersion"]?.intValue,
                  let token = value["token"]?.stringValue,
                  let pid = value["bridgePid"]?.intValue
            else { return nil }
            return Hello(
                envelopeVersion: envelopeVersion,
                catalogVersion: catalogVersion,
                token: token,
                credential: value["credential"]?.stringValue,
                clientName: value["clientName"]?.stringValue,
                bridgePID: Int32(pid))
        }
    }

    /// A tool invocation on its way to the app.
    public struct Call: Equatable, Sendable {
        public let id: Int
        public let tool: String
        public let arguments: JSONValue

        public init(id: Int, tool: String, arguments: JSONValue) {
            self.id = id
            self.tool = tool
            self.arguments = arguments
        }

        public var json: JSONValue {
            .object([
                "kind": .string("agent.call"),
                "id": .int(id),
                "tool": .string(tool),
                "arguments": arguments,
            ])
        }

        public static func parse(_ value: JSONValue) -> Call? {
            guard value["kind"]?.stringValue == "agent.call",
                  let id = value["id"]?.intValue,
                  let tool = value["tool"]?.stringValue
            else { return nil }
            return Call(id: id, tool: tool, arguments: value["arguments"] ?? .object([:]))
        }
    }

    /// Cancellation for an in-flight call. Whether it can still take effect is
    /// ADR-011 §8.5's problem, not the envelope's: a mutation already committed
    /// is not undone by a cancel arriving afterwards.
    public struct Cancel: Equatable, Sendable {
        public let id: Int
        public init(id: Int) { self.id = id }
        public var json: JSONValue { .object(["kind": .string("agent.cancel"), "id": .int(id)]) }
        public static func parse(_ value: JSONValue) -> Cancel? {
            guard value["kind"]?.stringValue == "agent.cancel",
                  let id = value["id"]?.intValue else { return nil }
            return Cancel(id: id)
        }
    }

    /// The app's answer to one call.
    public struct Reply: Equatable, Sendable {
        public let id: Int
        public let outcome: AgentToolOutcome

        public init(id: Int, outcome: AgentToolOutcome) {
            self.id = id
            self.outcome = outcome
        }

        public var json: JSONValue {
            switch outcome {
            case .success(let payload):
                return .object([
                    "kind": .string("agent.reply"),
                    "id": .int(id),
                    "ok": .bool(true),
                    "result": payload,
                ])
            case .failure(let code, let message, let details):
                return .object([
                    "kind": .string("agent.reply"),
                    "id": .int(id),
                    "ok": .bool(false),
                    "error": .string(code),
                    "message": .string(message),
                    "details": details ?? .null,
                ])
            }
        }

        public static func parse(_ value: JSONValue) -> Reply? {
            guard value["kind"]?.stringValue == "agent.reply",
                  let id = value["id"]?.intValue,
                  let ok = value["ok"]?.boolValue
            else { return nil }
            if ok {
                return Reply(id: id, outcome: .success(value["result"] ?? .object([:])))
            }
            let details = value["details"]
            return Reply(id: id, outcome: .failure(
                code: value["error"]?.stringValue ?? "internal",
                message: value["message"]?.stringValue ?? "",
                details: details == .null ? nil : details))
        }
    }

    /// A document changed. Carries only the identifier, deliberately.
    ///
    /// Pushing the new revision would invite a client to trust a number that
    /// could already be stale by the time it lands; re-reading returns text and
    /// revision together, which is the only way those two are guaranteed to
    /// agree.
    public struct Event: Equatable, Sendable {
        public let documentID: String

        public init(documentID: String) { self.documentID = documentID }

        public var json: JSONValue {
            .object([
                "kind": .string("agent.event"),
                "event": .string("document.changed"),
                "documentId": .string(documentID),
            ])
        }

        public static func parse(_ value: JSONValue) -> Event? {
            guard value["kind"]?.stringValue == "agent.event",
                  let id = value["documentId"]?.stringValue
            else { return nil }
            return Event(documentID: id)
        }
    }

    /// Authorization state pushed by the app without being asked, so the bridge
    /// can turn a pending approval into a retryable tool error instead of
    /// holding a request open while a human decides (R17).
    public struct AuthorizationState: Equatable, Sendable {
        public enum Status: String, Sendable {
            case pending, approved, denied, disconnected, expired
        }
        public let status: Status
        public let message: String

        public init(status: Status, message: String) {
            self.status = status
            self.message = message
        }

        public var json: JSONValue {
            .object([
                "kind": .string("control.authorization"),
                "status": .string(status.rawValue),
                "message": .string(message),
            ])
        }

        public static func parse(_ value: JSONValue) -> AuthorizationState? {
            guard value["kind"]?.stringValue == "control.authorization",
                  let raw = value["status"]?.stringValue,
                  let status = Status(rawValue: raw)
            else { return nil }
            return AuthorizationState(status: status, message: value["message"]?.stringValue ?? "")
        }
    }
}
