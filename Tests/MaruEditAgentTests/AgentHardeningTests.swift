import XCTest
@testable import MaruEditCore

/// Cases from the implementation review. Each one is a crash, a data loss, or a
/// silent authorization hole that shipped in the first version.
final class AgentHardeningTests: XCTestCase {

    // MARK: - Numeric input

    func testHugeAndNegativeNumbersAreRefusedRatherThanTrapping() {
        // `Int(1e300)` traps rather than returning anything, and an approved
        // client could reach it with one malformed argument.
        XCTAssertNil(JSONValue.double(1e300).intValue)
        XCTAssertNil(JSONValue.double(-1e300).intValue)
        XCTAssertNil(JSONValue.double(.infinity).intValue)
        XCTAssertNil(JSONValue.double(.nan).intValue)

        // `UInt64(-1)` traps too, which is what every revision field used to do.
        XCTAssertNil(JSONValue.int(-1).unsignedValue)
        XCTAssertNil(JSONValue.double(-3).unsignedValue)
        XCTAssertEqual(JSONValue.int(7).unsignedValue, 7)

        // Offsets must be non-negative or the NSRange built from them traps.
        XCTAssertNil(JSONValue.int(-5).offsetValue)
        XCTAssertEqual(JSONValue.int(0).offsetValue, 0)

        // A double that is not integral is not an integer.
        XCTAssertNil(JSONValue.double(1.5).intValue)
        XCTAssertEqual(JSONValue.double(3.0).intValue, 3)
    }

    func testEveryNumericFieldSurvivesFuzzing() throws {
        let hostile: [JSONValue] = [
            .double(1e308), .double(-1e308), .double(.infinity), .double(-.infinity),
            .double(.nan), .int(.max), .int(.min), .string("12"), .bool(true),
            .null, .array([]), .object([:]),
        ]
        for value in hostile {
            // No assertion about the result — only that reading it cannot crash.
            _ = value.intValue
            _ = value.unsignedValue
            _ = value.offsetValue
        }

        // And through a real decode, where NSNumber does the conversion.
        let payload = Data(#"{"a":1e308,"b":-1,"c":1.5,"d":9007199254740993}"#.utf8)
        let decoded = try JSONValue.decode(payload)
        _ = decoded["a"]?.intValue
        _ = decoded["b"]?.unsignedValue
        _ = decoded["c"]?.offsetValue
        _ = decoded["d"]?.intValue
    }

    func testMalformedPIDsDoNotTrapWhenParsingEndpointsAndHellos() {
        let endpoint = JSONValue.object([
            "serverInstanceID": .string("x"),
            "pid": .double(1e300),
            "socketPath": .string("/tmp/x.sock"),
        ])
        XCTAssertNil(AgentEndpoint.Instance.parse(endpoint))

        let hello = JSONValue.object([
            "kind": .string("control.hello"),
            "envelopeVersion": .int(1),
            "catalogVersion": .int(1),
            "token": .string("t"),
            "bridgePid": .int(Int(Int32.max) + 1),
        ])
        XCTAssertNil(AgentEnvelope.Hello.parse(hello))
    }

    // MARK: - Anchors

    func testAnchorsDieWithTheirRevisionAndAreBounded() {
        let store = AgentAnchorStore()
        let anchor = store.mint(revision: 4, start: 0, end: 5, text: "hello")
        XCTAssertNotNil(store.anchor(anchor.id))

        store.invalidate(atOrBefore: 4)
        XCTAssertNil(store.anchor(anchor.id), "an anchor cannot outlive its snapshot")

        for index in 0..<(AgentAnchorStore.maximumPerConnection + 10) {
            _ = store.mint(revision: 9, start: index, end: index, text: "x")
        }
        XCTAssertEqual(store.count, AgentAnchorStore.maximumPerConnection)
    }

    func testDigestsAreStableAndCanonicalizeFirst() {
        // Two texts that differ only in line endings hash the same, because the
        // buffer never holds a carriage return in the first place.
        XCTAssertEqual(AgentDigest.of("a\r\nb"), AgentDigest.of("a\nb"))
        XCTAssertNotEqual(AgentDigest.of("a"), AgentDigest.of("b"))
        XCTAssertTrue(AgentDigest.of("x").hasPrefix("sha256:"))
    }

    // MARK: - Authorization frames

    func testAuthorizationStatusRoundTripsForEveryCase() {
        for status in [
            AgentEnvelope.AuthorizationState.Status.pending, .approved,
            .denied, .disconnected, .expired,
        ] {
            let state = AgentEnvelope.AuthorizationState(status: status, message: "m")
            XCTAssertEqual(AgentEnvelope.AuthorizationState.parse(state.json), state)
        }
    }

    func testAnAuthorizationFrameIsNotAReply() {
        // The bridge used to treat the frame the app sends after hello as the
        // answer to the first call, so an approved call reported "pending"
        // while the app went ahead and ran it — and pairing could never
        // complete. They are different kinds and must not parse as each other.
        let state = AgentEnvelope.AuthorizationState(status: .approved, message: "").json
        XCTAssertNil(AgentEnvelope.Reply.parse(state))

        let reply = AgentEnvelope.Reply(id: 1, outcome: .success(.object([:]))).json
        XCTAssertNil(AgentEnvelope.AuthorizationState.parse(reply))
    }
}
