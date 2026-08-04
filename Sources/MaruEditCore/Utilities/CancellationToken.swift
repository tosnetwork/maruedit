import Foundation

/// A thread-safe "stop what you're doing" flag.
///
/// Long scans (Grep in M3-04/M3-05, external commands in M6-05) run on a
/// background queue and check this between units of work, so cancellation
/// takes effect within one file rather than at the end of the run.
///
/// Deliberately not `Task.isCancelled`: this codebase's I/O is synchronous
/// and queue-based (see `TextFileLoader`'s note), so a token that any
/// thread can set is what the callers actually have.
public final class CancellationToken: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    public init() {}

    public func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }

    public var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }
}
