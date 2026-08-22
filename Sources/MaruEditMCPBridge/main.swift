import Foundation
import MaruEditCore

/// `maruedit-mcp` — the process an agent launches.
///
/// An MCP stdio server is spawned by its client, and an already-running GUI
/// application cannot be anyone's child process, so the bridge exists to be
/// that child. It holds connection state and no business state: documents,
/// revisions, anchors, and proposals all live in MaruEdit, and every handle it
/// relays is opaque to it.
///
/// It also starts and answers `tools/list` when MaruEdit is not running, so an
/// agent's tool list does not blink in and out of existence depending on
/// whether the editor happens to be open.

// MARK: - Arguments

struct Options {
    var pair = false
    var instanceID: String?
    var credentialPath: String?
    var clientName: String?

    static func parse(_ arguments: [String]) -> Options {
        var options = Options()
        var index = 0
        while index < arguments.count {
            switch arguments[index] {
            case "--pair":
                options.pair = true
            case "--instance":
                index += 1
                options.instanceID = index < arguments.count ? arguments[index] : nil
            case "--credential":
                index += 1
                options.credentialPath = index < arguments.count ? arguments[index] : nil
            case "--client-name":
                index += 1
                options.clientName = index < arguments.count ? arguments[index] : nil
            default:
                break
            }
            index += 1
        }
        return options
    }
}

let options = Options.parse(Array(CommandLine.arguments.dropFirst()))
let home = URL(fileURLWithPath: NSHomeDirectory())

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

// MARK: - Instance discovery

func liveInstances() -> [AgentEndpoint.Instance] {
    AgentEndpoint.readRegistry(home: home).filter {
        AgentEndpoint.isAlive($0, now: AgentEndpoint.processStartTime(pid:))
    }
}

func describeDiscoveryFailure(_ error: AgentEndpoint.DiscoveryError) -> String {
    switch error {
    case .notRunning:
        return "MaruEdit is not running, or its agent interface is switched off in Settings."
    case .ambiguous(let ids):
        return """
            More than one MaruEdit is running and choosing for you could expose \
            the wrong documents. Pass --instance with one of: \(ids.joined(separator: ", "))
            """
    case .unknownInstance(let id):
        return "No running MaruEdit has instance id \(id)."
    case .unreadableRegistry:
        return "MaruEdit's instance registry could not be read."
    }
}

// MARK: - Connection

/// One live connection to the app, with framing on top.
final class AppConnection {
    private let descriptor: Int32
    private var inbound = Data()
    private var nextCallID = 1

    init(socketPath: String) throws {
        descriptor = try UnixSocket.connect(to: socketPath)
    }

    deinit { close(descriptor) }

    func send(_ value: JSONValue) throws {
        try UnixSocket.writeAll(descriptor, try AgentFraming.encode(try value.encoded()))
    }

    /// Blocks until one frame arrives, or the peer closes.
    func receive() throws -> JSONValue? {
        while true {
            if let frame = try AgentFraming.decode(from: &inbound) {
                return try JSONValue.decode(frame)
            }
            let chunk = try UnixSocket.read(descriptor)
            if chunk.isEmpty { return nil }
            inbound.append(chunk)
        }
    }

    /// Invoked for a change event the app pushed while we were reading.
    var onEvent: ((AgentEnvelope.Event) -> Void)?

    /// Latest authorization state the app pushed. Informational only.
    private(set) var authorization: AgentEnvelope.AuthorizationState.Status = .pending

    func call(tool: String, arguments: JSONValue) throws -> AgentToolOutcome {
        let id = nextCallID
        nextCallID += 1
        try send(AgentEnvelope.Call(id: id, tool: tool, arguments: arguments).json)
        while let frame = try receive() {
            if let event = AgentEnvelope.Event.parse(frame) {
                // Events arrive interleaved with replies; forwarding them here
                // keeps the bridge single-threaded and still delivers them
                // promptly, since an idle agent is not waiting on anything.
                onEvent?(event)
                continue
            }
            if let state = AgentEnvelope.AuthorizationState.parse(frame) {
                // Authorization frames are *state*, never the answer to a call.
                // Treating one as an answer meant the frame the app sends right
                // after hello was consumed as the result of the first call — so
                // an approved call reported "pending" while the app went ahead
                // and ran it, and pairing could never complete. The app answers
                // every call with a reply, including a refusal, so waiting for
                // that reply is both correct and simpler.
                authorization = state.status
                continue
            }
            if let reply = AgentEnvelope.Reply.parse(frame), reply.id == id {
                return reply.outcome
            }
        }
        return .failure(code: "transport.closed", message: "MaruEdit closed the connection.", details: nil)
    }
}

func readTrimmed(_ url: URL) -> String? {
    guard let data = try? Data(contentsOf: url) else { return nil }
    let text = String(decoding: data, as: UTF8.self)
        .trimmingCharacters(in: .whitespacesAndNewlines)
    return text.isEmpty ? nil : text
}

struct BridgeFailure: Error { let message: String }

func openConnection() -> Result<AppConnection, BridgeFailure> {
    let instances = liveInstances()
    switch AgentEndpoint.resolve(instances: instances, requestedID: options.instanceID) {
    case .failure(let error):
        return .failure(BridgeFailure(message: describeDiscoveryFailure(error)))
    case .success(let instance):
        guard let token = readTrimmed(
            AgentEndpoint.tokenURL(home: home, serverInstanceID: instance.serverInstanceID))
        else { return .failure(BridgeFailure(message: "MaruEdit's session token could not be read.")) }
        let credential = options.credentialPath.flatMap { readTrimmed(URL(fileURLWithPath: $0)) }
        do {
            let connection = try AppConnection(socketPath: instance.socketPath)
            try connection.send(AgentEnvelope.Hello(
                token: token,
                credential: credential,
                clientName: options.clientName ?? ProcessInfo.processInfo.environment["MARUEDIT_CLIENT_NAME"],
                bridgePID: getpid()).json)
            return .success(connection)
        } catch {
            return .failure(BridgeFailure(message: "Could not connect to MaruEdit: \(error)"))
        }
    }
}

// MARK: - Pairing

if options.pair {
    switch openConnection() {
    case .failure(let failure):
        fail(failure.message)
    case .success(let connection):
        do {
            let outcome = try connection.call(tool: "control.pair", arguments: JSONValue.object([:]))
            switch outcome {
            case .success(let payload):
                let code = payload["verificationCode"]?.stringValue ?? "?"
                let path = payload["credentialPath"]?.stringValue ?? "?"
                print("""
                    MaruEdit is showing this verification code:

                        \(code)

                    Confirm it in MaruEdit's agent indicator. Once you do, point your \
                    agent's MCP server config at:

                        --credential \(path)
                    """)
            case .failure(let code, let message, _):
                fail("\(code): \(message)")
            }
        } catch {
            fail("Pairing failed: \(error)")
        }
        exit(0)
    }
}

// MARK: - MCP stdio loop

/// Connection to the app, opened lazily and reopened if MaruEdit restarts, so
/// the bridge outlives an editor relaunch the way an agent expects.
final class LazyConnection: @unchecked Sendable {
    private var connection: AppConnection?
    private let lock = NSLock()

    /// Forwards a document-change event to the MCP client.
    var onEvent: ((AgentEnvelope.Event) -> Void)?

    func call(tool: String, arguments: JSONValue) -> AgentToolOutcome {
        lock.lock()
        defer { lock.unlock() }
        if connection == nil {
            switch openConnection() {
            case .success(let opened):
                opened.onEvent = { [weak self] event in self?.onEvent?(event) }
                connection = opened
            case .failure(let failure):
                return .failure(code: "editor.unavailable", message: failure.message, details: nil)
            }
        }
        guard let connection else {
            return .failure(code: "editor.unavailable", message: "No connection.", details: nil)
        }
        do {
            return try connection.call(tool: tool, arguments: arguments)
        } catch {
            self.connection = nil
            return .failure(
                code: "transport.closed",
                message: "The connection to MaruEdit dropped. Try again.",
                details: nil)
        }
    }
}

let connection = LazyConnection()

// Only what is actually wired up is advertised.
let advertisedPhase = 3

let server = MCPServer(
    info: MCPServer.ServerInfo(name: "maruedit", version: AgentBridgeVersion.current),
    tools: AgentToolCatalog.tools(throughPhase: advertisedPhase),
    // Resources stay unadvertised until the bridge reads the app continuously
    // rather than only while a call is outstanding: an idle subscriber would
    // otherwise be promised notifications it can never receive.
    servesResources: false,
    invoke: { tool, arguments in connection.call(tool: tool, arguments: arguments) })

func emit(_ message: JSONRPCMessage) {
    guard let data = try? message.json.encoded(sortedKeys: false) else { return }
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data("\n".utf8))
}

connection.onEvent = { event in
    // The notification carries only the URI: a pushed revision could be stale
    // by the time it lands, and re-reading returns text and revision together.
    emit(MCPServer.resourceUpdatedNotification(documentID: event.documentID))
}

// stdio MCP is line-delimited JSON. Logging goes to stderr, never stdout,
// which carries protocol traffic only.
while let line = readLine(strippingNewline: true) {
    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { continue }
    guard let value = try? JSONValue.decode(Data(trimmed.utf8)) else {
        FileHandle.standardError.write(Data("maruedit-mcp: unparsable frame\n".utf8))
        continue
    }
    let request = JSONRPCMessage.parse(value)
    let reply = await server.handle(request)
    if let reply { emit(reply) }
}
