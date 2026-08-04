import XCTest
@testable import MaruEditCore

final class MacroEngineTests: XCTestCase {
    func testAPIVersionAndPureTextAPIs() throws {
        let engine = MacroEngine()
        XCTAssertEqual(try value(engine.execute("maru.apiVersion")), .number(1))
        XCTAssertEqual(try value(engine.execute(
            "maru.text.uppercase(maru.text.trim('  Straße  '))")), .string("STRASSE"))
        XCTAssertEqual(try value(engine.execute(
            "maru.text.lowercase('ABC')")), .string("abc"))
        XCTAssertEqual(try value(engine.execute(
            "maru.text.normalizeLineEndings('a\\r\\nb\\rc')")), .string("a\nb\nc"))
    }

    func testEveryRunGetsAFreshControlledContext() throws {
        let engine = MacroEngine()
        XCTAssertEqual(try value(engine.execute("globalThis.leak = 42; leak")), .number(42))
        XCTAssertEqual(try value(engine.execute("typeof globalThis.leak")), .string("undefined"))
        XCTAssertEqual(try value(engine.execute("typeof maru.document + ':' + typeof readFile")),
                       .string("undefined:undefined"))
        XCTAssertEqual(try value(engine.execute(
            "Object.isFrozen(maru) && Object.isFrozen(maru.text)")), .boolean(true))
    }

    func testReportsJavaScriptMessageStackAndLocation() {
        let result = MacroEngine().execute("function explode() { throw new Error('boom') }\nexplode()")
        guard case .failure(.javascript(let error)) = result else {
            return XCTFail("Expected JavaScript error, got \(result)")
        }
        XCTAssertEqual(error.message, "boom")
        XCTAssertTrue(error.stack?.contains("explode") == true)
        XCTAssertNotNil(error.line)
    }

    func testCancellationBeforeRunAndAtHostBoundary() {
        let token = MacroCancellationToken()
        token.cancel()
        XCTAssertEqual(MacroEngine().execute("1", cancellation: token), .failure(.cancelled))

        let boundaryToken = MacroCancellationToken()
        let engine = MacroEngine()
        boundaryToken.cancel()
        XCTAssertEqual(engine.execute("maru.text.trim('x')", cancellation: boundaryToken),
                       .failure(.cancelled))
    }

    func testTimeoutBeforeRunAndAfterFinitePureJavaScript() {
        XCTAssertEqual(MacroEngine().execute("1", timeout: 0), .failure(.timedOut))
        let result = MacroEngine().execute(
            "let x = 0; for (let i = 0; i < 20000000; i++) x += i; x", timeout: 0.001)
        XCTAssertEqual(result, .failure(.timedOut))
    }

    func testAsyncRunDoesNotUseCallingThreadAndCanBeCancelledBeforeItStarts() {
        let queue = DispatchQueue(label: "MacroEngineTests.suspended")
        queue.suspend()
        let engine = MacroEngine(queue: queue)
        let completed = expectation(description: "cancelled queued macro")
        let token = engine.run("1") { result in
            XCTAssertEqual(result, .failure(.cancelled))
            completed.fulfill()
        }
        token.cancel()
        queue.resume()
        wait(for: [completed], timeout: 1)
    }

    func testRunningMacroCooperativelyObservesCancellation() {
        let completed = expectation(description: "running macro cancelled")
        let token = MacroEngine().run(
            "for (let i = 0; i < 10000000; i++) maru.checkCancellation()"
        ) { result in
            XCTAssertEqual(result, .failure(.cancelled))
            completed.fulfill()
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.01) { token.cancel() }
        wait(for: [completed], timeout: 1)
    }

    private func value(
        _ result: Result<MacroRunResult, MacroExecutionError>
    ) throws -> MacroValue {
        try result.get().value
    }
}
