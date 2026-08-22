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

/// Phase 5: what persists across restarts, and what deliberately does not.
@MainActor
final class AgentPersistenceTests: XCTestCase {

    private var home: URL!
    private var coordinator: AppCoordinator!

    override func setUp() async throws {
        try await super.setUp()
        _ = NSApplication.shared
        home = URL(fileURLWithPath: "/tmp/mp-\(UUID().uuidString.prefix(8))")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        coordinator = AppCoordinator()
        _ = coordinator.ensureWindowControllerReady(restoreSession: false)
    }

    override func tearDown() async throws {
        NSApp.windows.filter { $0.windowController is MainWindowController }.forEach { $0.close() }
        try? FileManager.default.removeItem(at: home)
        try await super.tearDown()
    }

    func testPairingWritesACredentialFileOnlyTheUserCanRead() throws {
        let control = AgentControlService(home: home)
        guard case .success(let request) = control.beginPairing() else {
            return XCTFail("pairing should start")
        }
        XCTAssertEqual(request.verificationCode.count, 6)
        XCTAssertTrue(control.confirmPairing(label: "Claude Code"))

        let attributes = try FileManager.default.attributesOfItem(atPath: request.credentialPath)
        XCTAssertEqual(attributes[.posixPermissions] as? Int, 0o600)
        XCTAssertTrue(control.pairedCredentials.values.contains("Claude Code"))
    }

    func testAPairingSurvivesARestartButItsGrantDoesNot() throws {
        let first = AgentControlService(home: home)
        guard case .success = first.beginPairing() else { return XCTFail("pairing") }
        XCTAssertTrue(first.confirmPairing(label: "Codex"))
        let credential = try XCTUnwrap(first.pairedCredentials.keys.first)
        first.setRemembered(credential, true)

        // A fresh service, as if the app relaunched.
        let second = AgentControlService(home: home)
        XCTAssertEqual(second.pairedCredentials[credential], "Codex")
        XCTAssertTrue(second.rememberedCredentials.contains(credential))

        // The session token is new, so a bridge holding the old one is refused:
        // remembering a pairing is not remembering a session.
        XCTAssertNotEqual(first.sessionToken, second.sessionToken)
        let stale = second.register(hello: AgentEnvelope.Hello(
            token: first.sessionToken, credential: credential,
            clientName: "codex", bridgePID: getpid()))
        guard case .failure(let failure) = stale else { return XCTFail("expected refusal") }
        XCTAssertEqual(failure.code, "authorization.denied")
    }

    func testRevokingACredentialCutsOffItsConnectionsAndForgetsIt() throws {
        let control = AgentControlService(home: home)
        guard case .success = control.beginPairing() else { return XCTFail("pairing") }
        XCTAssertTrue(control.confirmPairing(label: "Agent"))
        let credential = try XCTUnwrap(control.pairedCredentials.keys.first)
        control.setRemembered(credential, true)

        guard case .success(let connection) = control.register(hello: AgentEnvelope.Hello(
            token: control.sessionToken, credential: credential,
            clientName: "agent", bridgePID: getpid()))
        else { return XCTFail("registration") }
        control.approve(connection, documents: [AutomationID.next(prefix: "doc")])
        XCTAssertFalse(connection.grantedDocuments.isEmpty)

        control.revokeCredential(credential)

        XCTAssertTrue(connection.grantedDocuments.isEmpty)
        XCTAssertEqual(connection.status, .denied)
        XCTAssertNil(control.pairedCredentials[credential])
        XCTAssertFalse(control.rememberedCredentials.contains(credential))
        XCTAssertNotNil(control.authorize(connection, tool: "list_documents"))
    }

    func testAnUnrememberedPairingStillWaitsForApproval() throws {
        let control = AgentControlService(home: home)
        guard case .success = control.beginPairing() else { return XCTFail("pairing") }
        XCTAssertTrue(control.confirmPairing(label: "Agent"))
        let credential = try XCTUnwrap(control.pairedCredentials.keys.first)

        guard case .success(let connection) = control.register(hello: AgentEnvelope.Hello(
            token: control.sessionToken, credential: credential,
            clientName: "agent", bridgePID: getpid()))
        else { return XCTFail("registration") }
        // Pairing establishes provenance; it is not a standing permission.
        XCTAssertEqual(connection.status, .pending)
    }

    func testAStaleRegistryEntryIsNotTreatedAsLive() throws {
        let dead = AgentEndpoint.Instance(
            serverInstanceID: "gone", pid: 999_999, startTime: 1,
            socketPath: home.appendingPathComponent("missing.sock").path)
        try AgentEndpoint.updateRegistry(home: home) { _ in [dead] }
        // The socket does not exist and the pid is not ours, so nothing about
        // this entry may be reclaimed on the strength of ownership alone.
        XCTAssertFalse(
            AgentEndpoint.isAlive(dead, now: AgentEndpoint.processStartTime(pid:)))
    }
}

/// Authorization behaviour from the implementation review: capabilities are
/// separate, the write mode is the human's choice, and a revoked grant stops
/// work that is already in flight.
@MainActor
final class AgentAuthorizationTests: XCTestCase {

    private var home: URL!
    private var coordinator: AppCoordinator!
    private var server: AgentServer!
    private var connection: AgentControlService.Connection!
    private var executor: AgentToolExecutor!
    private var controller: MainWindowController!

    override func setUp() async throws {
        try await super.setUp()
        _ = NSApplication.shared
        home = URL(fileURLWithPath: "/tmp/maz-\(UUID().uuidString.prefix(8))")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        coordinator = AppCoordinator()
        controller = coordinator.ensureWindowControllerReady(restoreSession: false)
        controller.prepareUITestDocument(content: "hello world", selections: [])
        server = AgentServer(coordinator: coordinator, home: home)
        connection = AgentControlService.Connection(
            id: AutomationID.next(prefix: "conn"),
            credentialID: nil, claimedName: "test-agent", bridgePID: getpid())
        executor = AgentToolExecutor(coordinator: coordinator, control: server.control)
    }

    override func tearDown() async throws {
        server?.stop()
        NSApp.windows.filter { $0.windowController is MainWindowController }.forEach { $0.close() }
        try? FileManager.default.removeItem(at: home)
        try await super.tearDown()
    }

    private func run(_ tool: String, _ arguments: [String: JSONValue] = [:]) async -> AgentToolOutcome {
        await executor.run(tool: tool, arguments: .object(arguments), connection: connection)
    }

    private func failureCode(_ outcome: AgentToolOutcome) -> String? {
        if case .failure(let code, _, _) = outcome { return code }
        return nil
    }

    private var document: Document { controller.macroEditor.document! }

    private func editArguments() -> [String: JSONValue] {
        [
            "documentId": .string(document.automationID.rawValue),
            "baseRevision": .int(Int(document.textRevision)),
            "baseMetadataRevision": .int(Int(document.metadataRevision)),
            "edits": .array([.object([
                "start": .int(0), "end": .int(5), "text": .string("HELLO"),
            ])]),
        ]
    }

    func testApproveGrantsReadingAndNothingElse() async {
        server.control.approveForTesting(connection, coordinator: coordinator)

        // One button used to hand over reading, editing, saving, opening files
        // and running commands together.
        guard case .success = await run("list_documents") else {
            return XCTFail("reading is what Approve grants")
        }
        let denied1 = await run("apply_edits", editArguments())
        XCTAssertEqual(failureCode(denied1), "authorization.capability")
        let denied2 = await run("open_document", ["path": .string("/tmp/x")])
        XCTAssertEqual(failureCode(denied2), "authorization.capability")
        let denied3 = await run("run_command", ["commandId": .string("file.new")])
        XCTAssertEqual(failureCode(denied3), "authorization.capability")
        XCTAssertEqual(document.content, "hello world")
    }

    func testEditingWithoutTheAutoModeQueuesForReviewEvenWhenTheAgentAsksToApply() async throws {
        server.control.approveForTesting(
            connection, coordinator: coordinator,
            capabilities: [.readOnly, .writeDocuments], writeMode: .review)

        var arguments = editArguments()
        arguments["mode"] = .string("apply")
        let outcome = await run("apply_edits", arguments)

        guard case .success(let payload) = outcome else { return XCTFail("expected a proposal") }
        // The grant decides, not the caller.
        XCTAssertEqual(payload["status"], .string("pending"))
        XCTAssertEqual(document.content, "hello world")
    }

    func testAnUnknownWriteModeIsRefusedRatherThanTreatedAsApply() async {
        server.control.approveForTesting(
            connection, coordinator: coordinator,
            capabilities: [.readOnly, .writeDocuments], writeMode: .auto)

        var arguments = editArguments()
        arguments["mode"] = .string("reveiw")
        // A typo used to mean "apply immediately".
        let denied4 = await run("apply_edits", arguments)
        XCTAssertEqual(failureCode(denied4), "argument.invalid")
        XCTAssertEqual(document.content, "hello world")
    }

    func testRevokingStopsFurtherWorkAndClearsAnchors() async {
        server.control.approveForTesting(
            connection, coordinator: coordinator,
            capabilities: [.readOnly, .writeDocuments], writeMode: .auto)
        _ = connection.anchors.mint(revision: 1, start: 0, end: 1, text: "h")
        XCTAssertEqual(connection.anchors.count, 1)

        server.control.revoke(connection)

        XCTAssertEqual(connection.anchors.count, 0)
        let denied5 = await run("list_documents")
        XCTAssertEqual(failureCode(denied5), "authorization.denied")
        let denied6 = await run("apply_edits", editArguments())
        XCTAssertEqual(failureCode(denied6), "authorization.denied")
        XCTAssertEqual(document.content, "hello world")
    }

    func testGrantStampsNoticeARevocationThatHappensMidCall() {
        server.control.approveForTesting(connection, coordinator: coordinator)
        let stamp = server.control.stamp(connection)
        XCTAssertTrue(server.control.isStillValid(stamp))

        // The counter existed from the start; nothing read it, so a revoked
        // in-flight read still returned document contents.
        server.control.revoke(connection)
        XCTAssertFalse(server.control.isStillValid(stamp))
    }

    func testFoldersAreGrantedPerConnectionRatherThanProcessWide() {
        let other = AgentControlService.Connection(
            id: AutomationID.next(prefix: "conn"),
            credentialID: nil, claimedName: "other", bridgePID: getpid())
        server.control.approveForTesting(connection, coordinator: coordinator)
        server.control.approveForTesting(other, coordinator: coordinator)
        server.control.addAuthorizedRoot("/tmp")

        server.control.grantRoots(connection, ["/tmp"])

        XCTAssertEqual(connection.authorizedRoots, ["/tmp"])
        // A folder authorized for one configuration must not silently authorize
        // every other connection.
        XCTAssertTrue(other.authorizedRoots.isEmpty)
    }

    func testAnIdempotencyKeyReturnsTheFirstOutcomeRatherThanEditingTwice() async throws {
        server.control.approveForTesting(
            connection, coordinator: coordinator,
            capabilities: [.readOnly, .writeDocuments], writeMode: .auto)

        var arguments = editArguments()
        arguments["idempotencyKey"] = .string("k1")
        guard case .success = await run("apply_edits", arguments) else {
            return XCTFail("first call should apply")
        }
        XCTAssertEqual(document.content, "HELLO world")

        // A client that lost the reply and retried used to get a second edit.
        guard case .success(let repeated) = await run("apply_edits", arguments) else {
            return XCTFail("a repeat returns the first outcome")
        }
        XCTAssertEqual(repeated["status"], .string("applied"))
        XCTAssertEqual(document.content, "HELLO world")
    }

    func testReusingAKeyWithDifferentArgumentsIsRefused() async {
        server.control.approveForTesting(
            connection, coordinator: coordinator,
            capabilities: [.readOnly, .writeDocuments], writeMode: .auto)

        var first = editArguments()
        first["idempotencyKey"] = .string("k2")
        _ = await run("apply_edits", first)

        var second = editArguments()
        second["idempotencyKey"] = .string("k2")
        second["label"] = .string("something else")
        // Answering with someone else's result would be worse than refusing.
        let denied7 = await run("apply_edits", second)
        XCTAssertEqual(failureCode(denied7), "idempotency.mismatch")
    }
}
