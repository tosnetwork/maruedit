import Foundation

public enum ExternalCommandStream: Equatable, Sendable { case standardOutput, standardError }

public struct ExternalCommandChunk: Sendable {
    public let stream: ExternalCommandStream
    public let data: Data
}

public struct ExternalCommandResult: Equatable, Sendable {
    public let terminationStatus: Int32
    public let standardOutput: Data
    public let standardError: Data
    public let wasCancelled: Bool
}

public enum ExternalCommandRunError: LocalizedError, Equatable {
    case invalidConfiguration(String)
    case launchFailed(String)
    public var errorDescription: String? {
        switch self {
        case .invalidConfiguration(let message): message
        case .launchFailed(let message): "Could not launch external command: \(message)"
        }
    }
}

public final class ExternalCommandCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false
    public init() {}
    fileprivate func attach(_ process: Process) {
        lock.lock(); self.process = process; let shouldTerminate = cancelled; lock.unlock()
        if shouldTerminate, process.isRunning { process.terminate() }
    }
    public func cancel() {
        lock.lock(); cancelled = true; let process = process; lock.unlock()
        if process?.isRunning == true { process?.terminate() }
    }
    public var isCancelled: Bool {
        lock.lock(); defer { lock.unlock() }; return cancelled
    }
}

public final class ExternalCommandRunner: @unchecked Sendable {
    private let queue: DispatchQueue
    private let ioQueue = DispatchQueue(
        label: "jp.maruedit.external-command.io", qos: .userInitiated, attributes: .concurrent)
    private let callbackQueue = DispatchQueue(label: "jp.maruedit.external-command.stream")
    public init(queue: DispatchQueue = DispatchQueue(
        label: "jp.maruedit.external-command", qos: .userInitiated, attributes: .concurrent)) {
        self.queue = queue
    }

    @discardableResult
    public func run(
        configuration: ExternalCommandConfiguration,
        input: Data = Data(), workingDirectoryURL: URL? = nil,
        parentEnvironment: [String: String] = ProcessInfo.processInfo.environment,
        onChunk: @escaping @Sendable (ExternalCommandChunk) -> Void,
        completion: @escaping @Sendable (Result<ExternalCommandResult, ExternalCommandRunError>) -> Void
    ) -> ExternalCommandCancellation {
        let cancellation = ExternalCommandCancellation()
        queue.async {
            do { try configuration.validate() }
            catch { completion(.failure(.invalidConfiguration(error.localizedDescription))); return }
            let process = Process()
            if configuration.shellMode {
                process.executableURL = URL(fileURLWithPath: "/bin/zsh")
                process.arguments = ["-c", configuration.shellCommand!]
            } else {
                process.executableURL = URL(fileURLWithPath: configuration.executable)
                // Process passes each array element directly to execve. No
                // interpolation, quoting, escaping, or shell parsing occurs.
                process.arguments = configuration.arguments
            }
            process.currentDirectoryURL = workingDirectoryURL
            process.environment = configuration.resolvedEnvironment(from: parentEnvironment)
            let stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
            process.standardInput = stdin; process.standardOutput = stdout; process.standardError = stderr
            do { try process.run() }
            catch { completion(.failure(.launchFailed(error.localizedDescription))); return }
            // Attaching after launch also closes the race where cancellation
            // is requested while Process is configured but not yet running.
            cancellation.attach(process)

            let group = DispatchGroup()
            let collectedOutput = LockedExternalCommandOutput()
            func read(_ handle: FileHandle, stream: ExternalCommandStream) {
                group.enter()
                self.ioQueue.async {
                    while true {
                        let data = handle.availableData
                        if data.isEmpty { break }
                        collectedOutput.append(data, to: stream)
                        group.enter()
                        self.callbackQueue.async {
                            onChunk(.init(stream: stream, data: data))
                            group.leave()
                        }
                    }
                    group.leave()
                }
            }
            read(stdout.fileHandleForReading, stream: .standardOutput)
            read(stderr.fileHandleForReading, stream: .standardError)
            group.enter()
            self.ioQueue.async {
                stdin.fileHandleForWriting.write(input)
                try? stdin.fileHandleForWriting.close()
                group.leave()
            }
            process.waitUntilExit(); group.wait()
            let output = collectedOutput.snapshot()
            completion(.success(.init(
                terminationStatus: process.terminationStatus,
                standardOutput: output.standardOutput, standardError: output.standardError,
                wasCancelled: cancellation.isCancelled)))
        }
        return cancellation
    }
}

/// Mutable process output shared only by the two pipe-reader queues. The lock
/// protects both buffers and snapshots them atomically before completion.
private final class LockedExternalCommandOutput: @unchecked Sendable {
    private let lock = NSLock()
    private var standardOutput = Data()
    private var standardError = Data()

    func append(_ data: Data, to stream: ExternalCommandStream) {
        lock.withLock {
            if stream == .standardOutput {
                standardOutput.append(data)
            } else {
                standardError.append(data)
            }
        }
    }

    func snapshot() -> (standardOutput: Data, standardError: Data) {
        lock.withLock { (standardOutput, standardError) }
    }
}
