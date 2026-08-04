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

    func testHostAPIsAreValueOnlyAndCommandPromiseCompletes() throws {
        var calls: [String] = []
        var document = "hello"
        var clipboard = "clip"
        let host = MacroHost(
            runCommand: { calls.append("command:\($0)"); return $0 == "edit.test" },
            documentText: { document }, setDocumentText: { document = $0 },
            selectionsJSON: { #"[{"length":5,"location":0}]"# },
            setSelectionsJSON: { calls.append("selections:\($0)"); return true },
            replaceSelections: { calls.append("replace:\($0)") },
            readClipboard: { clipboard }, writeClipboard: { clipboard = $0 },
            showMessage: { calls.append("message:\($0)") },
            prompt: { message, initial in calls.append("prompt:\(message):\(initial)"); return "answer" },
            beginUndoGroup: { calls.append("begin:\($0)") }, endUndoGroup: { calls.append("end") })
        let script = """
        const command = maru.commands.run('edit.test');
        if (!(command instanceof Promise)) throw new Error('commands.run must return a Promise');
        maru.undo.group('Transform', () => {
          maru.document.setText(maru.document.getText().toUpperCase());
          maru.editor.replaceSelections(maru.ui.prompt('Question', 'initial'));
          maru.editor.setSelections([{location: 1, length: 2}]);
          maru.clipboard.writeText(maru.clipboard.readText() + '!');
          maru.ui.message('done');
        });
        command;
        """
        XCTAssertEqual(try value(MacroEngine().execute(script, host: host)), .boolean(true))
        XCTAssertEqual(try value(MacroEngine().execute(
            "maru.commands.run(1).catch(error => error instanceof TypeError)", host: host
        )), .boolean(true))
        XCTAssertEqual(document, "HELLO")
        XCTAssertEqual(clipboard, "clip!")
        XCTAssertEqual(calls, ["command:edit.test", "begin:Transform", "prompt:Question:initial",
                               "replace:answer", "selections:[{\"location\":1,\"length\":2}]",
                               "message:done", "end"])
    }

    func testCapabilitySurfaceAndNetworkGlobalsFailClosed() throws {
        var host = inertHost()
        host.allowedPermissions = [.currentDocument]
        XCTAssertEqual(try value(MacroEngine().execute(
            "typeof maru.document + ':' + typeof maru.clipboard + ':' + typeof fetch + ':' + typeof WebSocket",
            host: host)), .string("object:undefined:undefined:undefined"))
        host.allowedPermissions.insert(.clipboard)
        XCTAssertEqual(try value(MacroEngine().execute("typeof maru.clipboard", host: host)),
                       .string("object"))
    }

    private func value(
        _ result: Result<MacroRunResult, MacroExecutionError>
    ) throws -> MacroValue {
        try result.get().value
    }

    private func inertHost() -> MacroHost {
        MacroHost(runCommand: { _ in false }, documentText: { "" }, setDocumentText: { _ in },
                  selectionsJSON: { "[]" }, setSelectionsJSON: { _ in false },
                  replaceSelections: { _ in }, readClipboard: { "" }, writeClipboard: { _ in },
                  showMessage: { _ in }, prompt: { _, _ in nil },
                  beginUndoGroup: { _ in }, endUndoGroup: {})
    }
}
