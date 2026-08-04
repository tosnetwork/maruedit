import Foundation

/// Runs a closure after `delay` has elapsed with no further calls to
/// `schedule`, canceling any previously scheduled-but-not-yet-run closure.
/// Used to avoid writing state to disk on every keystroke/tab-switch —
/// see ROADMAP.md M1-05 ("Debounce and atomically write session state").
///
/// Not thread-safe by design: intended to be created and used from a
/// single queue (MaruEdit only ever calls this from the main thread
/// today). A future concurrent use case should get its own synchronized
/// variant rather than this one growing locks it doesn't need yet.
public final class Debouncer {
    private let delay: TimeInterval
    private let queue: DispatchQueue
    private var pendingWorkItem: DispatchWorkItem?

    public init(delay: TimeInterval, queue: DispatchQueue = .main) {
        self.delay = delay
        self.queue = queue
    }

    public func schedule(_ action: @escaping () -> Void) {
        pendingWorkItem?.cancel()
        let workItem = DispatchWorkItem(block: action)
        pendingWorkItem = workItem
        queue.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    /// Cancels any pending scheduled call without running it.
    public func cancel() {
        pendingWorkItem?.cancel()
        pendingWorkItem = nil
    }
}
