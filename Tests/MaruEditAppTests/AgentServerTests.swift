import AppKit
import XCTest
@preconcurrency @testable import MaruEditApp
@testable import MaruEditCore

/// Phase 1 end to end: a real Unix socket, real framing, real authorization,
/// and the real tool executor against a real editor.
///
/// The protocol tests cover the value logic exhaustively; this covers the part
/// they cannot — that the pieces are actually wired to each other.
@MainActor
final class AgentServerTests: XCTestCase {

    private var home: URL!
    private var coordinator: AppCoordinator!
    private var server: AgentServer!

    override func setUp() async throws {
        try await super.setUp()
        _ = NSApplication.shared
        // Deliberately short: the per-user temp directory is already ~85
        // characters, and `sockaddr_un.sun_path` allows 104 in total, so a
        // test rooted there could not bind a socket no matter how the layout
        // is arranged.
        home = URL(fileURLWithPath: "/tmp/mt-\(UUID().uuidString.prefix(8))")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        coordinator = AppCoordinator()
        _ = coordinator.ensureWindowControllerReady(restoreSession: false)
        server = AgentServer(coordinator: coordinator, home: home)
    }

    override func tearDown() async throws {
        server?.stop()
        NSApp.windows.filter { $0.windowController is MainWindowController }.forEach { $0.close() }
        try? FileManager.default.removeItem(at: home)
        try await super.tearDown()
    }

    // MARK: - Client

    /// Minimal bridge stand-in, so the test exercises the same framing and
    /// envelope a real bridge uses rather than a shortcut past them.
    private final class Client {
        let descriptor: Int32
        var buffer = Data()

        init(socketPath: String) throws {
            descriptor = try UnixSocket.connect(to: socketPath)
        }

        deinit { close(descriptor) }

        func send(_ value: JSONValue) throws {
            try UnixSocket.writeAll(descriptor, try AgentFraming.encode(try value.encoded()))
        }

        func receive(timeout: TimeInterval = 3) throws -> JSONValue? {
            let deadline = Date().addingTimeInterval(timeout)
            while Date() < deadline {
                if let frame = try AgentFraming.decode(from: &buffer) {
                    return try JSONValue.decode(frame)
                }
                var readable = pollfd(fd: descriptor, events: Int16(POLLIN), revents: 0)
                if poll(&readable, 1, 50) > 0 {
                    let chunk = try UnixSocket.read(descriptor)
                    if chunk.isEmpty { return nil }
                    buffer.append(chunk)
                } else {
                    RunLoop.current.run(until: Date().addingTimeInterval(0.02))
                }
            }
            return nil
        }
    }

    private func startServerAndConnect(credential: String? = nil) throws -> Client {
        server.start()
        XCTAssertTrue(server.isRunning)
        let socketPath = AgentEndpoint.socketURL(
            home: home, serverInstanceID: server.control.serverInstanceID).path
        let client = try Client(socketPath: socketPath)
        try client.send(AgentEnvelope.Hello(
            token: server.control.sessionToken,
            credential: credential,
            clientName: "test-agent",
            bridgePID: getpid()).json)
        return client
    }

    private func pump(_ seconds: TimeInterval = 0.15) {
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
    }

    // MARK: - Endpoint lifecycle

    func testTheProductionSocketPathFitsInSunPath() {
        // This is a regression guard for a real bug: the obvious layout,
        // `…/ExternalControl/instance-<16 hex>/control.sock`, is 108 characters
        // under a 16-character home directory and so could never bind. Sockets
        // therefore live in a short directory of their own.
        let realHome = URL(fileURLWithPath: "/Users/some-longer-username")
        let path = AgentEndpoint.socketURL(
            home: realHome, serverInstanceID: "0123456789abcdef").path
        XCTAssertLessThanOrEqual(
            path.utf8.count, UnixSocket.maximumPathLength,
            "socket path would fail to bind: \(path)")
    }

    func testStartPublishesAnEndpointWithoutTheTokenAndStopRemovesIt() throws {
        server.start()
        let id = server.control.serverInstanceID

        let endpoint = AgentEndpoint.endpointURL(home: home, serverInstanceID: id)
        let published = try String(contentsOf: endpoint, encoding: .utf8)
        // ADR-011 §3.1: discovery data is not a credential store.
        XCTAssertFalse(published.contains(server.control.sessionToken))
        XCTAssertFalse(published.lowercased().contains("token"))

        let tokenURL = AgentEndpoint.tokenURL(home: home, serverInstanceID: id)
        let attributes = try FileManager.default.attributesOfItem(atPath: tokenURL.path)
        XCTAssertEqual(attributes[.posixPermissions] as? Int, 0o600)

        let socketPath = AgentEndpoint.socketURL(home: home, serverInstanceID: id).path
        let socketMode = try FileManager.default.attributesOfItem(atPath: socketPath)[.posixPermissions] as? Int
        XCTAssertEqual(socketMode, 0o600)

        XCTAssertEqual(AgentEndpoint.readRegistry(home: home).map(\.serverInstanceID), [id])

        server.stop()
        // Off must mean no endpoint at all, not merely a server that ignores
        // you: a stale socket invites the next launch to reclaim it.
        XCTAssertFalse(FileManager.default.fileExists(atPath: socketPath))
        XCTAssertTrue(AgentEndpoint.readRegistry(home: home).isEmpty)
    }

    // MARK: - Authorization

    func testAConnectionStartsPendingAndIsToldSoRatherThanBeingLeftWaiting() throws {
        let client = try startServerAndConnect()
        pump()

        let state = try XCTUnwrap(AgentEnvelope.AuthorizationState.parse(
            try XCTUnwrap(client.receive())))
        XCTAssertEqual(state.status, .pending)

        try client.send(AgentEnvelope.Call(id: 1, tool: "list_documents", arguments: .object([:])).json)
        pump()
        let reply = try XCTUnwrap(AgentEnvelope.Reply.parse(try XCTUnwrap(client.receive())))
        guard case .failure(let code, _, _) = reply.outcome else {
            return XCTFail("an unapproved client must not read anything")
        }
        // R17: the call returns promptly instead of blocking on a human.
        XCTAssertEqual(code, "authorization.pending")
    }

    func testAWrongTokenIsRefused() throws {
        server.start()
        let socketPath = AgentEndpoint.socketURL(
            home: home, serverInstanceID: server.control.serverInstanceID).path
        let client = try Client(socketPath: socketPath)
        try client.send(AgentEnvelope.Hello(
            token: "not-the-token", credential: nil, clientName: "impostor", bridgePID: getpid()).json)
        pump()
        let reply = try XCTUnwrap(AgentEnvelope.Reply.parse(try XCTUnwrap(client.receive())))
        guard case .failure(let code, _, _) = reply.outcome else { return XCTFail("expected refusal") }
        XCTAssertEqual(code, "authorization.denied")
    }

    func testApprovalGrantsExactlyWhatWasOpenAtTheTime() throws {
        let controller = try XCTUnwrap(coordinator.agentWindowControllers().first)
        controller.prepareUITestDocument(content: "first document", selections: [])
        // Type into it, so the reported buffer state is a real unsaved change
        // rather than a fixture's initial value — the divergence between buffer
        // and disk is the whole reason this interface exists.
        controller.macroEditor.textView.insertText(
            "!", replacementRange: NSRange(location: 0, length: 0))
        let client = try startServerAndConnect()
        pump()
        _ = try client.receive()

        let connection = try XCTUnwrap(server.control.connections.first)
        let openNow = coordinator.agentVisibleTargets().map(\.document.automationID)
        server.control.approve(connection, documents: openNow)
        server.notifyAuthorization(connection)
        pump()

        try client.send(AgentEnvelope.Call(id: 2, tool: "list_documents", arguments: .object([:])).json)
        pump()
        var payload: JSONValue?
        while let frame = try client.receive(timeout: 1) {
            if let reply = AgentEnvelope.Reply.parse(frame), reply.id == 2 {
                if case .success(let value) = reply.outcome { payload = value }
                break
            }
        }
        let documents = try XCTUnwrap(payload?["documents"]?.arrayValue)
        XCTAssertEqual(documents.count, openNow.count)
        XCTAssertEqual(documents.first?["bufferState"]?.stringValue, "dirty")
        XCTAssertNotNil(documents.first?["revision"]?.intValue)

        // A document opened afterwards stays invisible: the grant froze.
        controller.newDocument()
        try client.send(AgentEnvelope.Call(id: 3, tool: "list_documents", arguments: .object([:])).json)
        pump()
        var second: JSONValue?
        while let frame = try client.receive(timeout: 1) {
            if let reply = AgentEnvelope.Reply.parse(frame), reply.id == 3 {
                if case .success(let value) = reply.outcome { second = value }
                break
            }
        }
        XCTAssertEqual(second?["documents"]?.arrayValue?.count, openNow.count)
    }

    func testRevokedGrantStopsFurtherReads() throws {
        let client = try startServerAndConnect()
        pump()
        _ = try client.receive()
        let connection = try XCTUnwrap(server.control.connections.first)
        server.control.approve(
            connection, documents: coordinator.agentVisibleTargets().map(\.document.automationID))
        server.control.revoke(connection)

        try client.send(AgentEnvelope.Call(id: 4, tool: "list_documents", arguments: .object([:])).json)
        pump()
        while let frame = try client.receive(timeout: 1) {
            if let reply = AgentEnvelope.Reply.parse(frame), reply.id == 4 {
                guard case .failure(let code, _, _) = reply.outcome else {
                    return XCTFail("a revoked client must not read")
                }
                XCTAssertEqual(code, "authorization.denied")
                return
            }
        }
        XCTFail("no reply")
    }

    // MARK: - Reads

    func testReadingAndSearchingGrantedDocuments() throws {
        let controller = try XCTUnwrap(coordinator.agentWindowControllers().first)
        controller.prepareUITestDocument(
            content: "alpha\nbeta needle\ngamma\n", selections: [NSRange(location: 0, length: 5)])
        let client = try startServerAndConnect()
        pump()
        _ = try client.receive()
        let connection = try XCTUnwrap(server.control.connections.first)
        server.control.approve(
            connection, documents: coordinator.agentVisibleTargets().map(\.document.automationID))

        func call(_ id: Int, _ tool: String, _ arguments: JSONValue) throws -> JSONValue? {
            try client.send(AgentEnvelope.Call(id: id, tool: tool, arguments: arguments).json)
            pump(0.25)
            while let frame = try client.receive(timeout: 2) {
                if let reply = AgentEnvelope.Reply.parse(frame), reply.id == id {
                    if case .success(let value) = reply.outcome { return value }
                    if case .failure(let code, let message, _) = reply.outcome {
                        XCTFail("\(tool) failed: \(code) \(message)")
                    }
                    return nil
                }
            }
            return nil
        }

        let documents = try XCTUnwrap(try call(10, "list_documents", .object([:]))?["documents"]?.arrayValue)
        let documentID = try XCTUnwrap(documents.first?["documentId"]?.stringValue)

        let read = try XCTUnwrap(try call(11, "read_document", .object([
            "documentId": .string(documentID), "startLine": .int(2), "endLine": .int(3),
        ])))
        XCTAssertEqual(read["text"]?.stringValue, "beta needle\n")
        XCTAssertEqual(read["truncated"], .bool(false))
        XCTAssertNotNil(read["revision"]?.intValue)
        XCTAssertNotNil(read["metadataRevision"]?.intValue)

        let search = try XCTUnwrap(try call(12, "search_documents", .object([
            "query": .string("needle"),
        ])))
        let matches = try XCTUnwrap(search["matches"]?.arrayValue)
        XCTAssertEqual(matches.count, 1)
        XCTAssertEqual(matches.first?["line"], .int(2))

        let editors = try XCTUnwrap(try call(13, "list_editors", .object([:]))?["editors"]?.arrayValue)
        let editorID = try XCTUnwrap(editors.first?["editorId"]?.stringValue)
        let selection = try XCTUnwrap(try call(14, "get_selection", .object([
            "editorId": .string(editorID),
        ])))
        XCTAssertNotNil(selection["selectionRevision"]?.intValue)

        let outline = try call(15, "get_outline", .object(["documentId": .string(documentID)]))
        XCTAssertNotNil(outline?["symbols"]?.arrayValue)
    }

    func testAnUngrantedDocumentIsReportedAsUnknownRatherThanForbidden() throws {
        let client = try startServerAndConnect()
        pump()
        _ = try client.receive()
        let connection = try XCTUnwrap(server.control.connections.first)
        server.control.approve(connection, documents: [])

        try client.send(AgentEnvelope.Call(
            id: 20, tool: "read_document",
            arguments: .object(["documentId": .string("doc_does_not_exist")])).json)
        pump()
        while let frame = try client.receive(timeout: 1) {
            if let reply = AgentEnvelope.Reply.parse(frame), reply.id == 20 {
                guard case .failure(let code, _, _) = reply.outcome else { return XCTFail("expected refusal") }
                // "Forbidden" would confirm the document exists.
                XCTAssertEqual(code, "document.unknown")
                return
            }
        }
        XCTFail("no reply")
    }

    // MARK: - Audit

    func testEveryCallIsAudited() throws {
        let client = try startServerAndConnect()
        pump()
        _ = try client.receive()
        let connection = try XCTUnwrap(server.control.connections.first)
        server.control.approve(
            connection, documents: coordinator.agentVisibleTargets().map(\.document.automationID))
        try client.send(AgentEnvelope.Call(id: 30, tool: "list_documents", arguments: .object([:])).json)
        pump(0.25)
        _ = try client.receive(timeout: 1)

        let tools = server.control.audit.map(\.tool)
        XCTAssertTrue(tools.contains("control.hello"))
        XCTAssertTrue(tools.contains("control.approve"))
        XCTAssertTrue(tools.contains("list_documents"))
    }
}
