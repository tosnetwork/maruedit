import Foundation

/// One JSON-RPC message on the public MCP channel.
public struct JSONRPCMessage: Equatable, Sendable {
    public var id: JSONValue?
    public var method: String?
    public var params: JSONValue?
    public var result: JSONValue?
    public var error: JSONValue?

    public init(
        id: JSONValue? = nil, method: String? = nil, params: JSONValue? = nil,
        result: JSONValue? = nil, error: JSONValue? = nil
    ) {
        self.id = id
        self.method = method
        self.params = params
        self.result = result
        self.error = error
    }

    public static func parse(_ value: JSONValue) -> JSONRPCMessage {
        JSONRPCMessage(
            id: value["id"],
            method: value["method"]?.stringValue,
            params: value["params"],
            result: value["result"],
            error: value["error"])
    }

    public var json: JSONValue {
        var members: [String: JSONValue] = ["jsonrpc": .string("2.0")]
        if let id { members["id"] = id }
        if let method { members["method"] = .string(method) }
        if let params { members["params"] = params }
        if let result { members["result"] = result }
        if let error { members["error"] = error }
        return .object(members)
    }
}

/// Era-neutral outcome of one tool call, mapped to the wire by the adapter.
///
/// Keeping this separate from the JSON is what lets a second protocol era be
/// added later as a mapping table rather than a second implementation of every
/// tool.
public enum AgentToolOutcome: Equatable, Sendable {
    /// Structured payload, plus the text mirror older clients read.
    case success(JSONValue)
    /// Something the model can fix by trying differently. It travels as a tool
    /// result with `isError`, not a JSON-RPC error, because the spec is
    /// explicit that models recover from the former and rarely from the latter.
    case failure(code: String, message: String, details: JSONValue?)

    public var isFailure: Bool { if case .failure = self { true } else { false } }
}

/// A refusal on its way out, in a form `Result` accepts.
///
/// `AgentToolOutcome` covers both halves of a call and so cannot itself be an
/// `Error` without the success case becoming one too.
public struct AgentToolFailure: Error, Equatable, Sendable {
    public let code: String
    public let message: String
    public let details: JSONValue?

    public init(code: String, message: String, details: JSONValue? = nil) {
        self.code = code
        self.message = message
        self.details = details
    }

    public var outcome: AgentToolOutcome {
        .failure(code: code, message: message, details: details)
    }
}

/// The public MCP surface, in its handshake era.
///
/// Measured 2026-08-22: Codex CLI asks for `2025-06-18` and Claude Code for
/// `2025-11-25`, both through `initialize`. Neither speaks the 2026-07-28
/// stateless revision, so that adapter is specified (ADR-012 §5) and not built.
/// This one negotiates whichever handshake revision the client requests.
public struct MCPServer: Sendable {
    public static let supportedProtocolVersions = ["2025-11-25", "2025-06-18", "2025-03-26"]
    public static let preferredProtocolVersion = "2025-11-25"

    public struct ServerInfo: Sendable {
        public let name: String
        public let version: String
        public init(name: String, version: String) {
            self.name = name
            self.version = version
        }
    }

    public let info: ServerInfo
    /// Tools advertised to clients. The bridge passes the catalog filtered to
    /// the phases that are actually wired up.
    public let tools: [AgentToolCatalog.Tool]
    /// Invoked for `tools/call`. Returns an era-neutral outcome.
    public let invoke: @Sendable (String, JSONValue) async -> AgentToolOutcome
    /// Whether the resource surface is advertised. Phases 1-3 expose no
    /// resources: the tools are self-sufficient, and a second way to read the
    /// same text is a second thing to keep consistent.
    public let servesResources: Bool

    public init(
        info: ServerInfo,
        tools: [AgentToolCatalog.Tool],
        servesResources: Bool = false,
        invoke: @escaping @Sendable (String, JSONValue) async -> AgentToolOutcome
    ) {
        self.info = info
        self.tools = tools
        self.servesResources = servesResources
        self.invoke = invoke
    }

    /// Documents are addressed by an opaque URI so a client never has to build
    /// one, and so nothing about the file's location leaks into the handle.
    public static func documentURI(_ documentID: String) -> String {
        "maruedit://document/\(documentID)"
    }

    public static func documentID(fromURI uri: String) -> String? {
        let prefix = "maruedit://document/"
        guard uri.hasPrefix(prefix) else { return nil }
        return String(uri.dropFirst(prefix.count))
    }

    // MARK: - Dispatch

    /// Handles one incoming message. Returns the reply, or `nil` for a
    /// notification, which by definition gets none.
    public func handle(_ message: JSONRPCMessage) async -> JSONRPCMessage? {
        guard let method = message.method else { return nil }
        switch method {
        case "initialize":
            return reply(to: message, result: initializeResult(for: message.params))
        case "notifications/initialized", "notifications/cancelled":
            return nil
        case "ping":
            return reply(to: message, result: .object([:]))
        case "tools/list":
            return reply(to: message, result: .object(["tools": .array(tools.map(descriptor(for:)))]))
        case "tools/call":
            return await callTool(message)
        case "resources/list":
            guard servesResources else {
                return reply(to: message, result: .object(["resources": .array([])]))
            }
            return await listResources(message)
        case "resources/read":
            guard servesResources else {
                return reply(to: message, error: .object([
                    "code": .int(-32602), "message": .string("This server exposes no resources."),
                ]))
            }
            return await readResource(message)
        case "resources/subscribe", "resources/unsubscribe":
            // Subscription is accepted so a client can express interest; the
            // notification it will receive carries only the URI, because a
            // pushed revision could already be stale by the time it lands.
            return reply(to: message, result: .object([:]))
        case "prompts/list":
            return reply(to: message, result: .object(["prompts": .array([])]))
        default:
            guard message.id != nil else { return nil }
            return reply(to: message, error: .object([
                "code": .int(-32601),
                "message": .string("Unknown method: \(method)"),
            ]))
        }
    }

    private func initializeResult(for params: JSONValue?) -> JSONValue {
        let requested = params?["protocolVersion"]?.stringValue
        // Echo the client's revision when we speak it, so a client that pins
        // one is not forced to downgrade; otherwise offer ours and let it
        // decide.
        let negotiated = requested.flatMap { Self.supportedProtocolVersions.contains($0) ? $0 : nil }
            ?? Self.preferredProtocolVersion
        return .object([
            "protocolVersion": .string(negotiated),
            "capabilities": servesResources
                ? .object([
                    "tools": .object(["listChanged": .bool(true)]),
                    "resources": .object(["subscribe": .bool(true), "listChanged": .bool(true)]),
                ])
                : .object(["tools": .object(["listChanged": .bool(true)])]),
            "serverInfo": .object([
                "name": .string(info.name),
                "version": .string(info.version),
            ]),
        ])
    }

    private func descriptor(for tool: AgentToolCatalog.Tool) -> JSONValue {
        .object([
            "name": .string(tool.name),
            "title": .string(tool.title),
            "description": .string(tool.summary),
            "inputSchema": tool.inputSchema,
            "outputSchema": tool.outputSchema,
            "annotations": .object([
                "title": .string(tool.title),
                "readOnlyHint": .bool(tool.isReadOnly),
                "destructiveHint": .bool(tool.isDestructive),
                "idempotentHint": .bool(tool.isReadOnly),
                "openWorldHint": .bool(false),
            ]),
        ])
    }

    private func callTool(_ message: JSONRPCMessage) async -> JSONRPCMessage? {
        guard let name = message.params?["name"]?.stringValue else {
            return reply(to: message, error: .object([
                "code": .int(-32602), "message": .string("tools/call requires a name"),
            ]))
        }
        guard tools.contains(where: { $0.name == name }) else {
            return reply(to: message, error: .object([
                "code": .int(-32602), "message": .string("Unknown tool: \(name)"),
            ]))
        }
        let arguments = message.params?["arguments"] ?? .object([:])
        let outcome = await invoke(name, arguments)
        return reply(to: message, result: Self.toolResult(outcome))
    }

    /// Maps an outcome onto the handshake era's result shape.
    ///
    /// The structured payload is mirrored into a text block because a client
    /// that ignores `outputSchema` sees nothing otherwise — and both measured
    /// clients predate structured content being widely honoured.
    public static func toolResult(_ outcome: AgentToolOutcome) -> JSONValue {
        switch outcome {
        case .success(let payload):
            let mirror = (try? payload.encodedString()) ?? "{}"
            return .object([
                "content": .array([.object(["type": .string("text"), "text": .string(mirror)])]),
                "structuredContent": payload,
                "isError": .bool(false),
            ])
        case .failure(let code, let message, let details):
            var text = "\(code): \(message)"
            if let details, let rendered = try? details.encodedString() {
                text += "\n\(rendered)"
            }
            return .object([
                "content": .array([.object(["type": .string("text"), "text": .string(text)])]),
                "structuredContent": .object([
                    "error": .string(code),
                    "message": .string(message),
                    "details": details ?? .null,
                ]),
                "isError": .bool(true),
            ])
        }
    }

    private func listResources(_ message: JSONRPCMessage) async -> JSONRPCMessage? {
        let outcome = await invoke("list_documents", .object([:]))
        guard case .success(let payload) = outcome,
              let documents = payload["documents"]?.arrayValue
        else { return reply(to: message, result: .object(["resources": .array([])])) }
        let resources = documents.compactMap { document -> JSONValue? in
            guard let id = document["documentId"]?.stringValue else { return nil }
            return .object([
                "uri": .string(Self.documentURI(id)),
                "name": document["displayName"] ?? .string(id),
                "mimeType": .string("text/plain"),
            ])
        }
        return reply(to: message, result: .object(["resources": .array(resources)]))
    }

    private func readResource(_ message: JSONRPCMessage) async -> JSONRPCMessage? {
        guard let uri = message.params?["uri"]?.stringValue,
              let documentID = Self.documentID(fromURI: uri)
        else {
            return reply(to: message, error: .object([
                "code": .int(-32602), "message": .string("Unknown resource URI."),
            ]))
        }
        let outcome = await invoke("read_document", .object(["documentId": .string(documentID)]))
        switch outcome {
        case .success(let payload):
            return reply(to: message, result: .object([
                "contents": .array([.object([
                    "uri": .string(uri),
                    "mimeType": .string("text/plain"),
                    "text": payload["text"] ?? .string(""),
                    // The revisions travel with the text, so a client never
                    // holds one without the other.
                    "_meta": .object([
                        "revision": payload["revision"] ?? .null,
                        "metadataRevision": payload["metadataRevision"] ?? .null,
                    ]),
                ])]),
            ]))
        case .failure(let code, let message2, _):
            return reply(to: message, error: .object([
                "code": .int(-32602), "message": .string("\(code): \(message2)"),
            ]))
        }
    }

    /// A content-change notification, which carries only the URI.
    ///
    /// It is an invalidation hint, not a payload: the client re-reads to get
    /// text and revision together, which is the only way it can be sure the two
    /// agree.
    public static func resourceUpdatedNotification(documentID: String) -> JSONRPCMessage {
        JSONRPCMessage(
            method: "notifications/resources/updated",
            params: .object(["uri": .string(documentURI(documentID))]))
    }

    private func reply(to message: JSONRPCMessage, result: JSONValue) -> JSONRPCMessage? {
        guard let id = message.id else { return nil }
        return JSONRPCMessage(id: id, result: result)
    }

    private func reply(to message: JSONRPCMessage, error: JSONValue) -> JSONRPCMessage? {
        guard let id = message.id else { return nil }
        return JSONRPCMessage(id: id, error: error)
    }
}
