import XCTest
@testable import MaruEditCore

private final class LockedBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value
    init(_ value: Value) { self.value = value }
    func mutate(_ body: (inout Value) -> Void) { lock.lock(); body(&value); lock.unlock() }
    func read() -> Value { lock.lock(); defer { lock.unlock() }; return value }
}

final class ExternalCommandTests: XCTestCase {
    func testConfigurationRoundTripEnvironmentAllowlistAndValidation() throws {
        let value = ExternalCommandConfiguration(
            id: "format_swift", name: "Format Swift", executable: "/usr/bin/env",
            arguments: ["true"], workingDirectory: .explicit, workingDirectoryPath: "/tmp",
            inheritedEnvironment: ["PATH", "LANG"], environment: ["LANG": "ja_JP.UTF-8"],
            input: .selection, output: .replaceSelection)
        let decoded = try ExternalCommandConfigurationStore.decode(
            ExternalCommandConfigurationStore.encode([value]))
        XCTAssertEqual(decoded, [value])
        XCTAssertEqual(value.resolvedEnvironment(from: ["PATH": "/bin", "HOME": "/secret"]),
                       ["PATH": "/bin", "LANG": "ja_JP.UTF-8"])
        XCTAssertThrowsError(try ExternalCommandConfiguration(
            id: "bad", name: "Bad", executable: "/bin/zsh").validate())
        XCTAssertThrowsError(try ExternalCommandConfiguration(
            id: "bad", name: "Bad", executable: "relative").validate())
        XCTAssertNotNil(ExternalCommandConfiguration(
            id: "shell", name: "Shell", executable: "", shellMode: true,
            shellCommand: "echo risky").riskDescription)
    }

    func testArgumentsArePassedLiterallyAndInputStreamsToStandardInput() throws {
        let runner = ExternalCommandRunner()
        let literal = expectation(description: "literal arguments")
        let config = ExternalCommandConfiguration(
            id: "literal", name: "Literal", executable: "/usr/bin/python3",
            arguments: ["-c", "import sys; print('|'.join(sys.argv[1:])); print(sys.stdin.read(), end='')",
                        "a b", "$(touch /tmp/maruedit-should-not-exist)"])
        let chunks = LockedBox(Data())
        _ = runner.run(configuration: config, input: Data("INPUT".utf8), onChunk: { chunk in
            if chunk.stream == .standardOutput { chunks.mutate { $0.append(chunk.data) } }
        }, completion: { result in
            let value = try! result.get()
            XCTAssertEqual(value.terminationStatus, 0)
            XCTAssertEqual(String(decoding: value.standardOutput, as: UTF8.self),
                           "a b|$(touch /tmp/maruedit-should-not-exist)\nINPUT")
            XCTAssertEqual(chunks.read(), value.standardOutput)
            XCTAssertFalse(FileManager.default.fileExists(atPath: "/tmp/maruedit-should-not-exist"))
            literal.fulfill()
        })
        wait(for: [literal], timeout: 3)
    }

    func testStdoutStderrStreamAndCancellation() throws {
        let runner = ExternalCommandRunner()
        let streamed = expectation(description: "both streams")
        let config = ExternalCommandConfiguration(
            id: "streams", name: "Streams", executable: "/usr/bin/python3",
            arguments: ["-c", "import sys; print('out', flush=True); print('err', file=sys.stderr, flush=True)"])
        let streams = LockedBox(Set<String>())
        _ = runner.run(configuration: config, onChunk: { chunk in
            streams.mutate { $0.insert(chunk.stream == .standardOutput ? "out" : "err") }
        }, completion: { result in
            let value = try! result.get()
            XCTAssertEqual(String(decoding: value.standardOutput, as: UTF8.self), "out\n")
            XCTAssertEqual(String(decoding: value.standardError, as: UTF8.self), "err\n")
            XCTAssertEqual(streams.read(), ["out", "err"])
            streamed.fulfill()
        })
        wait(for: [streamed], timeout: 3)

        let cancelled = expectation(description: "cancelled")
        let slow = ExternalCommandConfiguration(
            id: "slow", name: "Slow", executable: "/bin/sleep", arguments: ["10"])
        let token = runner.run(configuration: slow, onChunk: { _ in }, completion: { result in
            XCTAssertTrue(try! result.get().wasCancelled)
            cancelled.fulfill()
        })
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.05) { token.cancel() }
        wait(for: [cancelled], timeout: 3)

        let immediate = expectation(description: "immediate cancellation")
        let immediateToken = runner.run(
            configuration: .init(
                id: "immediate", name: "Immediate", executable: "/bin/sleep", arguments: ["5"]),
            onChunk: { _ in }, completion: { result in
                XCTAssertTrue(try! result.get().wasCancelled)
                immediate.fulfill()
            })
        immediateToken.cancel()
        wait(for: [immediate], timeout: 2)
    }
}
