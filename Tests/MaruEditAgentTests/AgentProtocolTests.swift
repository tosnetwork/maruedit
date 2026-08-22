import XCTest
@testable import MaruEditCore

/// Phase 1's protocol layer. All of it is pure value logic, which is why it can
/// be tested exhaustively without a socket or a window in sight.
final class AgentProtocolTests: XCTestCase {

    // MARK: - Framing

    func testFramingRoundTripsAndWaitsForCompleteFrames() throws {
        let payload = Data(#"{"kind":"agent.call"}"#.utf8)
        var buffer = try AgentFraming.encode(payload)

        // A stream socket splits messages wherever it likes; a reader that
        // assumes one read is one message works in tests and fails in
        // production, so decoding must ask for more instead of guessing.
        var partial = buffer.prefix(3) as Data
        XCTAssertNil(try AgentFraming.decode(from: &partial))

        let decoded = try AgentFraming.decode(from: &buffer)
        XCTAssertEqual(decoded, payload)
        XCTAssertTrue(buffer.isEmpty)
    }

    func testFramingRefusesAnOversizedLengthBeforeAllocating() {
        var header = UInt32(AgentFraming.maximumFrameBytes + 1).bigEndian
        var buffer = Data(bytes: &header, count: 4)
        buffer.append(Data(repeating: 0, count: 8))
        XCTAssertThrowsError(try AgentFraming.decode(from: &buffer)) { error in
            XCTAssertEqual(
                error as? AgentFraming.FramingError,
                .frameTooLarge(AgentFraming.maximumFrameBytes + 1))
        }
    }

    func testFramingConcatenatedFramesDecodeInOrder() throws {
        var buffer = Data()
        buffer.append(try AgentFraming.encode(Data("one".utf8)))
        buffer.append(try AgentFraming.encode(Data("two".utf8)))
        XCTAssertEqual(try AgentFraming.decode(from: &buffer), Data("one".utf8))
        XCTAssertEqual(try AgentFraming.decode(from: &buffer), Data("two".utf8))
        XCTAssertNil(try AgentFraming.decode(from: &buffer))
    }

    func testFramingSurvivesFuzzedInput() throws {
        // Not looking for a specific outcome — only that no input crashes or
        // hangs the decoder, since it is the first thing an untrusted peer
        // reaches.
        var generator = SystemRandomNumberGenerator()
        for _ in 0..<500 {
            var buffer = Data((0..<Int.random(in: 0...64, using: &generator)).map { _ in
                UInt8.random(in: 0...255, using: &generator)
            })
            _ = try? AgentFraming.decode(from: &buffer)
        }
    }

    // MARK: - JSON values

    func testJSONValuePreservesBoolsThroughFoundation() throws {
        let value = JSONValue.object(["flag": .bool(true), "count": .int(1)])
        let round = try JSONValue.decode(try value.encoded())
        // NSNumber erases Bool into a number; getting this wrong turns
        // `"isError": false` into `"isError": 0`, which clients read as truthy.
        XCTAssertEqual(round["flag"], .bool(true))
        XCTAssertEqual(round["count"], .int(1))
    }

    // MARK: - MCP server

    private func server(
        invoke: @escaping @Sendable (String, JSONValue) async -> AgentToolOutcome = { _, _ in .success(.object([:])) }
    ) -> MCPServer {
        MCPServer(
            info: MCPServer.ServerInfo(name: "maruedit", version: "test"),
            tools: AgentToolCatalog.tools(throughPhase: 1),
            invoke: invoke)
    }

    func testInitializeEchoesAClientRevisionItSpeaks() async throws {
        // Measured 2026-08-22: Codex asks for 2025-06-18 and Claude Code for
        // 2025-11-25. Forcing either to downgrade would be gratuitous.
        for requested in ["2025-06-18", "2025-11-25"] {
            let reply = await server().handle(JSONRPCMessage(
                id: .int(1), method: "initialize",
                params: .object(["protocolVersion": .string(requested)])))
            XCTAssertEqual(reply?.result?["protocolVersion"], .string(requested))
        }
    }

    func testInitializeOffersOurRevisionWhenTheClientAsksForSomethingElse() async {
        let reply = await server().handle(JSONRPCMessage(
            id: .int(1), method: "initialize",
            params: .object(["protocolVersion": .string("1999-01-01")])))
        XCTAssertEqual(
            reply?.result?["protocolVersion"],
            .string(MCPServer.preferredProtocolVersion))
    }

    func testNotificationsGetNoReply() async {
        let reply = await server().handle(
            JSONRPCMessage(method: "notifications/initialized"))
        XCTAssertNil(reply, "a notification has no id and must not be answered")
    }

    func testToolsListAdvertisesOnlyWhatIsWiredUp() async throws {
        let reply = await server().handle(JSONRPCMessage(id: .int(2), method: "tools/list"))
        let tools = try XCTUnwrap(reply?.result?["tools"]?.arrayValue)
        let names = tools.compactMap { $0["name"]?.stringValue }
        XCTAssertEqual(names, [
            "get_outline", "get_selection", "list_documents",
            "list_editors", "read_document", "search_documents",
        ])
        XCTAssertFalse(names.contains("apply_edits"), "phase 2 tools are not advertised in phase 1")

        let read = try XCTUnwrap(tools.first { $0["name"]?.stringValue == "read_document" })
        XCTAssertEqual(read["annotations"]?["readOnlyHint"], .bool(true))
        XCTAssertEqual(read["inputSchema"]?["required"], .array([.string("documentId")]))
    }

    func testUnknownToolIsAProtocolErrorAndUnknownMethodToo() async {
        let unknownTool = await server().handle(JSONRPCMessage(
            id: .int(3), method: "tools/call",
            params: .object(["name": .string("no_such_tool")])))
        XCTAssertEqual(unknownTool?.error?["code"], .int(-32602))

        let unknownMethod = await server().handle(JSONRPCMessage(id: .int(4), method: "nope"))
        XCTAssertEqual(unknownMethod?.error?["code"], .int(-32601))
    }

    func testToolFailuresTravelAsResultsSoTheModelCanRecover() async throws {
        let failing = server { _, _ in
            .failure(code: "state.conflict", message: "The document moved.", details: .object(["revision": .int(9)]))
        }
        let reply = await failing.handle(JSONRPCMessage(
            id: .int(5), method: "tools/call",
            params: .object(["name": .string("read_document"), "arguments": .object([:])])))

        // A JSON-RPC error is rarely recoverable by a model; a tool result with
        // isError is what the spec says to use for something it can fix.
        XCTAssertNil(reply?.error)
        XCTAssertEqual(reply?.result?["isError"], .bool(true))
        let text = try XCTUnwrap(reply?.result?["content"]?.arrayValue?.first?["text"]?.stringValue)
        XCTAssertTrue(text.contains("state.conflict"))
        XCTAssertTrue(text.contains("The document moved."))
        XCTAssertEqual(reply?.result?["structuredContent"]?["error"], .string("state.conflict"))
    }

    func testSuccessCarriesBothStructuredContentAndATextMirror() async throws {
        let succeeding = server { _, _ in .success(.object(["revision": .int(4)])) }
        let reply = await succeeding.handle(JSONRPCMessage(
            id: .int(6), method: "tools/call",
            params: .object(["name": .string("list_documents"), "arguments": .object([:])])))
        XCTAssertEqual(reply?.result?["structuredContent"]?["revision"], .int(4))
        // Both measured clients predate structured content being honoured
        // widely, so the mirror is what they actually read.
        let text = try XCTUnwrap(reply?.result?["content"]?.arrayValue?.first?["text"]?.stringValue)
        XCTAssertTrue(text.contains("\"revision\":4"))
    }

    // MARK: - Envelope

    func testEnvelopeRoundTrips() throws {
        let hello = AgentEnvelope.Hello(
            token: "t", credential: "c", clientName: "claude-code", bridgePID: 42)
        XCTAssertEqual(AgentEnvelope.Hello.parse(hello.json), hello)

        let call = AgentEnvelope.Call(id: 7, tool: "read_document", arguments: .object(["a": .int(1)]))
        XCTAssertEqual(AgentEnvelope.Call.parse(call.json), call)

        let ok = AgentEnvelope.Reply(id: 7, outcome: .success(.object(["x": .int(2)])))
        XCTAssertEqual(AgentEnvelope.Reply.parse(ok.json), ok)

        let bad = AgentEnvelope.Reply(id: 8, outcome: .failure(code: "e", message: "m", details: nil))
        XCTAssertEqual(AgentEnvelope.Reply.parse(bad.json), bad)

        let auth = AgentEnvelope.AuthorizationState(status: .pending, message: "waiting")
        XCTAssertEqual(AgentEnvelope.AuthorizationState.parse(auth.json), auth)
    }

    func testEnvelopeRejectsFramesOfTheWrongKind() {
        let call = AgentEnvelope.Call(id: 1, tool: "x", arguments: .object([:])).json
        XCTAssertNil(AgentEnvelope.Hello.parse(call))
        XCTAssertNil(AgentEnvelope.Reply.parse(call))
        XCTAssertNil(AgentEnvelope.AuthorizationState.parse(call))
    }

    // MARK: - Endpoint discovery

    func testDiscoveryFailsClosedWhenTwoInstancesAreLive() {
        let a = AgentEndpoint.Instance(
            serverInstanceID: "aaa", pid: 1, startTime: 1, socketPath: "/tmp/a.sock")
        let b = AgentEndpoint.Instance(
            serverInstanceID: "bbb", pid: 2, startTime: 2, socketPath: "/tmp/b.sock")

        // Guessing newest or frontmost could hand an agent the wrong window's
        // documents, so ambiguity is an error the human resolves.
        guard case .failure(let error) = AgentEndpoint.resolve(instances: [a, b], requestedID: nil) else {
            return XCTFail("expected ambiguity")
        }
        XCTAssertEqual(error, .ambiguous(["aaa", "bbb"]))

        guard case .success(let chosen) = AgentEndpoint.resolve(instances: [a, b], requestedID: "bbb") else {
            return XCTFail("explicit selection should succeed")
        }
        XCTAssertEqual(chosen.serverInstanceID, "bbb")

        guard case .failure(let missing) = AgentEndpoint.resolve(instances: [], requestedID: nil) else {
            return XCTFail("expected notRunning")
        }
        XCTAssertEqual(missing, .notRunning)
    }

    func testLivenessNeedsAMatchingStartTimeNotJustAPID() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let socket = directory.appendingPathComponent("control.sock")
        FileManager.default.createFile(atPath: socket.path, contents: Data())

        let instance = AgentEndpoint.Instance(
            serverInstanceID: "x", pid: 1234, startTime: 1000, socketPath: socket.path)
        XCTAssertTrue(AgentEndpoint.isAlive(instance) { _ in 1000 })
        // A reused pid must not resurrect a dead instance's endpoint.
        XCTAssertFalse(AgentEndpoint.isAlive(instance) { _ in 5000 })
        XCTAssertFalse(AgentEndpoint.isAlive(instance) { _ in nil })
    }

    func testRegistryRoundTripsUnderItsLock() throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }

        try AgentEndpoint.updateRegistry(home: home) { _ in
            [AgentEndpoint.Instance(serverInstanceID: "one", pid: 1, startTime: 1, socketPath: "/tmp/1")]
        }
        try AgentEndpoint.updateRegistry(home: home) { existing in
            existing + [AgentEndpoint.Instance(
                serverInstanceID: "two", pid: 2, startTime: 2, socketPath: "/tmp/2")]
        }
        XCTAssertEqual(
            AgentEndpoint.readRegistry(home: home).map(\.serverInstanceID), ["one", "two"])
    }

    func testEndpointFileNeverCarriesTheToken() throws {
        let instance = AgentEndpoint.Instance(
            serverInstanceID: "x", pid: 1, startTime: 1, socketPath: "/tmp/x.sock")
        let rendered = try instance.json.encodedString()
        // ADR-011 §3.1: discovery data is not a credential store.
        XCTAssertFalse(rendered.lowercased().contains("token"))
    }

    // MARK: - Catalog

    func testCatalogIsTheSingleSchemaSource() {
        for tool in AgentToolCatalog.all {
            XCTAssertEqual(tool.inputSchema["type"], .string("object"), tool.name)
            XCTAssertNotNil(tool.inputSchema["properties"], tool.name)
            XCTAssertNotNil(tool.outputSchema["properties"], tool.name)
            XCTAssertFalse(tool.summary.isEmpty, tool.name)
            XCTAssertTrue(tool.name.allSatisfy { $0.isLowercase || $0 == "_" }, tool.name)
        }
        XCTAssertEqual(
            Set(AgentToolCatalog.all.map(\.name)).count,
            AgentToolCatalog.all.count,
            "tool names must be unique")
        XCTAssertTrue(AgentToolCatalog.tools(throughPhase: 1).allSatisfy(\.isReadOnly),
                      "phase 1 is read-only by definition")
    }
}
