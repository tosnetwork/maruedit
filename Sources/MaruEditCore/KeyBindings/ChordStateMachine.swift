import Foundation

public enum ChordResult: Equatable, Sendable {
    case ignored
    case waiting(prefix: KeyGesture)
    case command(CommandID)
    case cancelled
    case invalid
    case timedOut
}

public final class ChordStateMachine {
    public let timeout: TimeInterval
    public private(set) var pendingPrefix: KeyGesture?
    private var deadline: TimeInterval?

    public init(timeout: TimeInterval = 1.5) {
        precondition(timeout > 0)
        self.timeout = timeout
    }

    public func handle(
        _ gesture: KeyGesture,
        bindings: [KeyBinding],
        now: TimeInterval = ProcessInfo.processInfo.systemUptime
    ) -> ChordResult {
        if let prefix = pendingPrefix {
            if gesture.key == "escape" {
                reset()
                return .cancelled
            }
            guard let deadline, now < deadline else {
                reset()
                return .timedOut
            }
            let sequence = [prefix, gesture]
            reset()
            return bindings.first(where: { $0.keys == sequence }).map { .command($0.command) } ?? .invalid
        }

        if let command = bindings.first(where: { $0.keys == [gesture] })?.command {
            return .command(command)
        }
        if bindings.contains(where: { $0.keys.count == 2 && $0.keys[0] == gesture }) {
            pendingPrefix = gesture
            deadline = now + timeout
            return .waiting(prefix: gesture)
        }
        return .ignored
    }

    @discardableResult
    public func expire(now: TimeInterval = ProcessInfo.processInfo.systemUptime) -> Bool {
        guard let deadline, now >= deadline else { return false }
        reset()
        return true
    }

    public func cancel() { reset() }

    private func reset() {
        pendingPrefix = nil
        deadline = nil
    }
}
