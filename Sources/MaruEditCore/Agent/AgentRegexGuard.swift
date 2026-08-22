import Foundation

/// Runs a client-supplied regular expression without handing the client a way
/// to hang the editor.
///
/// The difficulty is specific and does not go away by being careful: ICU's
/// matcher, which `NSRegularExpression` wraps, is one synchronous call with no
/// cancellation point. A catastrophically backtracking pattern against a modest
/// string can run for hours inside a single `matches(in:)`, and nothing this
/// process owns — no timer, no `Task.cancel`, no `Thread.exit` — can interrupt
/// it partway. Threads cannot be safely killed from outside.
///
/// So there is no way to make an arbitrary pattern safe after starting it. Two
/// bounds are applied instead, and each covers what the other cannot:
///
/// 1. **Refuse patterns that can blow up.** Catastrophic backtracking needs an
///    unbounded quantifier wrapped around something that can match the same
///    text more than one way. That is a syntactic property, so it can be
///    decided before running anything. This is conservative: it rejects some
///    patterns that would have been fine. That is the correct direction to err,
///    and the rejection says how to rewrite.
/// 2. **Bound what does run.** Analysis is a heuristic and ICU has surprises,
///    so a surviving pattern still runs on a thread that can be *abandoned*.
///    An abandoned thread keeps burning a core until ICU finishes — pretending
///    otherwise would be the lie — so abandonment is itself capped. Past the
///    cap, regex search is refused until the abandoned threads drain, which
///    turns "hang the editor" into "lose one feature, briefly".
public enum AgentRegexGuard {

    public enum Rejection: Error, Equatable {
        case invalid(String)
        case patternTooLong(Int)
        case nestedUnboundedQuantifier
        case repeatedAlternation
        case unboundedRepetitionOfOptional
        case timedOut(seconds: Double)
        case tooManyAbandoned

        public var code: String {
            switch self {
            case .invalid: "regex.invalid"
            case .patternTooLong: "regex.too_long"
            case .nestedUnboundedQuantifier, .repeatedAlternation,
                 .unboundedRepetitionOfOptional: "regex.unbounded"
            case .timedOut: "regex.timeout"
            case .tooManyAbandoned: "regex.busy"
            }
        }

        public var message: String {
            switch self {
            case .invalid(let reason):
                "That is not a valid regular expression: \(reason)"
            case .patternTooLong(let length):
                "The pattern is \(length) characters, past the \(maximumPatternLength)-character limit."
            case .nestedUnboundedQuantifier:
                """
                That pattern nests an unbounded quantifier inside another one \
                (like (a+)+), which can take exponential time on input that \
                almost matches. Rewrite the inner part as a character class, or \
                give one of the quantifiers an upper bound such as {1,64}.
                """
            case .repeatedAlternation:
                """
                That pattern repeats a group containing | without an upper \
                bound. When the branches can match the same text, backtracking \
                is exponential. Use a character class, or bound the repetition \
                such as {1,64}.
                """
            case .unboundedRepetitionOfOptional:
                """
                That pattern repeats a group whose contents are all optional \
                (like (a?)*), which lets the matcher loop without consuming \
                input. Make the inner part required, or bound the repetition.
                """
            case .timedOut(let seconds):
                """
                The search did not finish within \(seconds) seconds and was \
                abandoned. Narrow the pattern or search a single document.
                """
            case .tooManyAbandoned:
                """
                Earlier regular-expression searches are still running and have \
                not been reclaimed. Regex search is unavailable until they \
                finish; literal search still works.
                """
            }
        }
    }

    public static let maximumPatternLength = 512
    /// Long enough that no reasonable pattern over a document-sized string
    /// reaches it, short enough that a human notices nothing.
    public static let timeoutSeconds: Double = 2.0
    /// Each abandoned thread is a core spinning until ICU returns on its own.
    /// Two is a degraded machine; ten is an unusable one.
    public static let maximumAbandonedThreads = 2

    // MARK: - Static analysis

    /// One group's frame while scanning.
    private struct Frame {
        var hasUnboundedQuantifier = false
        var hasAlternation = false
        /// Whether every alternative seen so far could match the empty string.
        /// `(a?)*` and `(|a)*` loop without consuming input.
        var currentBranchCanBeEmpty = true
        var anyBranchCanBeEmpty = false
    }

    /// Rejects patterns whose shape permits exponential backtracking.
    ///
    /// Decided syntactically and conservatively — deciding it exactly is
    /// equivalent to deciding the matcher's runtime, which is not something to
    /// attempt in a text editor's automation surface.
    public static func validate(_ pattern: String) throws {
        let characters = Array(pattern)
        guard characters.count <= maximumPatternLength else {
            throw Rejection.patternTooLong(characters.count)
        }

        var stack: [Frame] = [Frame()]
        var index = 0

        while index < characters.count {
            let character = characters[index]

            switch character {
            case "\\":
                // An escape consumes its operand, so a `\(` never opens a group
                // and a `\*` never quantifies anything.
                index += 2
                stack[stack.count - 1].currentBranchCanBeEmpty = false
                continue

            case "[":
                // Inside a class every metacharacter is literal. `[]]` and
                // `[^]]` put a literal `]` first, so the first position never
                // closes.
                var scan = index + 1
                if scan < characters.count, characters[scan] == "^" { scan += 1 }
                if scan < characters.count, characters[scan] == "]" { scan += 1 }
                while scan < characters.count, characters[scan] != "]" {
                    scan += characters[scan] == "\\" ? 2 : 1
                }
                index = min(scan + 1, characters.count)
                stack[stack.count - 1].currentBranchCanBeEmpty = false
                let quantifier = readQuantifier(characters, at: index)
                if quantifier.isUnbounded { stack[stack.count - 1].hasUnboundedQuantifier = true }
                index = quantifier.next
                continue

            case "(":
                stack.append(Frame())
                index += 1
                // Group prefixes — (?:, (?=, (?!, (?<=, (?<!, (?i) — are read
                // past so their characters are not mistaken for content.
                if index < characters.count, characters[index] == "?" {
                    index += 1
                    if index < characters.count, characters[index] == "<",
                       index + 1 < characters.count,
                       characters[index + 1] == "=" || characters[index + 1] == "!" {
                        index += 2
                    } else if index < characters.count,
                              ":=!".contains(characters[index]) {
                        index += 1
                    }
                }
                continue

            case ")":
                guard stack.count > 1 else { throw Rejection.invalid("unbalanced )") }
                var frame = stack.removeLast()
                frame.anyBranchCanBeEmpty = frame.anyBranchCanBeEmpty || frame.currentBranchCanBeEmpty
                index += 1

                let quantifier = readQuantifier(characters, at: index)
                index = quantifier.next
                if quantifier.isUnbounded {
                    // This is the whole rule: an unbounded quantifier wrapped
                    // around something that can match the same text more than
                    // one way is what makes backtracking exponential.
                    if frame.hasUnboundedQuantifier { throw Rejection.nestedUnboundedQuantifier }
                    if frame.hasAlternation { throw Rejection.repeatedAlternation }
                    if frame.anyBranchCanBeEmpty { throw Rejection.unboundedRepetitionOfOptional }
                    stack[stack.count - 1].hasUnboundedQuantifier = true
                } else if quantifier.consumed {
                    // A bounded repetition of an unbounded inner quantifier is
                    // polynomial, not exponential, but it still propagates:
                    // (a+){1,8} inside another + is the exponential case again.
                    if frame.hasUnboundedQuantifier {
                        stack[stack.count - 1].hasUnboundedQuantifier = true
                    }
                    if quantifier.minimum == 0 {
                        stack[stack.count - 1].currentBranchCanBeEmpty = true
                        continue
                    }
                } else if frame.hasUnboundedQuantifier {
                    stack[stack.count - 1].hasUnboundedQuantifier = true
                }
                if !frame.anyBranchCanBeEmpty {
                    stack[stack.count - 1].currentBranchCanBeEmpty = false
                }
                continue

            case "|":
                stack[stack.count - 1].hasAlternation = true
                stack[stack.count - 1].anyBranchCanBeEmpty =
                    stack[stack.count - 1].anyBranchCanBeEmpty
                    || stack[stack.count - 1].currentBranchCanBeEmpty
                stack[stack.count - 1].currentBranchCanBeEmpty = true
                index += 1
                continue

            case "*", "+", "?", "{":
                // A quantifier with nothing before it is a syntax error ICU
                // would reject anyway; refuse it here so the message is ours.
                let quantifier = readQuantifier(characters, at: index)
                if quantifier.consumed {
                    if quantifier.isUnbounded { stack[stack.count - 1].hasUnboundedQuantifier = true }
                    if quantifier.minimum == 0 {
                        stack[stack.count - 1].currentBranchCanBeEmpty = true
                    }
                    index = quantifier.next
                } else {
                    // A `{` that is not a repetition is a literal brace.
                    stack[stack.count - 1].currentBranchCanBeEmpty = false
                    index += 1
                }
                continue

            default:
                stack[stack.count - 1].currentBranchCanBeEmpty = false
                index += 1
                let quantifier = readQuantifier(characters, at: index)
                if quantifier.isUnbounded { stack[stack.count - 1].hasUnboundedQuantifier = true }
                if quantifier.consumed, quantifier.minimum == 0 {
                    stack[stack.count - 1].currentBranchCanBeEmpty = true
                }
                index = quantifier.next
                continue
            }
        }

        guard stack.count == 1 else { throw Rejection.invalid("unbalanced (") }

        // Last word to ICU: the analysis above says nothing about whether the
        // pattern is well-formed, only about its shape.
        do {
            _ = try NSRegularExpression(pattern: pattern)
        } catch {
            throw Rejection.invalid((error as NSError).localizedDescription)
        }
    }

    private struct Quantifier {
        var consumed = false
        var isUnbounded = false
        var minimum = 1
        var next = 0
    }

    /// Reads a quantifier at `index`, if there is one, including a lazy or
    /// possessive suffix.
    private static func readQuantifier(_ characters: [Character], at index: Int) -> Quantifier {
        var result = Quantifier(next: index)
        guard index < characters.count else { return result }

        switch characters[index] {
        case "*":
            result = Quantifier(consumed: true, isUnbounded: true, minimum: 0, next: index + 1)
        case "+":
            result = Quantifier(consumed: true, isUnbounded: true, minimum: 1, next: index + 1)
        case "?":
            result = Quantifier(consumed: true, isUnbounded: false, minimum: 0, next: index + 1)
        case "{":
            var scan = index + 1
            var minimumDigits = ""
            while scan < characters.count, characters[scan].isNumber {
                minimumDigits.append(characters[scan])
                scan += 1
            }
            guard !minimumDigits.isEmpty else { return result }
            var unbounded = false
            if scan < characters.count, characters[scan] == "," {
                scan += 1
                // `{n,}` has no ceiling; `{n,m}` does.
                unbounded = scan < characters.count && !characters[scan].isNumber
                while scan < characters.count, characters[scan].isNumber { scan += 1 }
            }
            guard scan < characters.count, characters[scan] == "}" else { return result }
            result = Quantifier(
                consumed: true,
                isUnbounded: unbounded,
                minimum: Int(minimumDigits) ?? 1,
                next: scan + 1)
        default:
            return result
        }

        // `*?` and `*+` change the search strategy, not the bound.
        if result.next < characters.count, characters[result.next] == "?" || characters[result.next] == "+" {
            result.next += 1
        }
        return result
    }

    // MARK: - Bounded execution

    /// The handoff between the waiter and the worker.
    ///
    /// Both may reach the end at the same instant, and exactly one of them must
    /// conclude "this run was abandoned". Two separate flags cannot decide
    /// that: whichever is read first can be stale, and the outcomes are a
    /// permanently-leaked counter slot or a double decrement. So the decision
    /// is a single compare-and-set under one lock, and whoever loses does
    /// nothing.
    private final class RunState<Value>: @unchecked Sendable {
        private let lock = NSLock()
        private var value: Value?
        private var settled = false

        /// Called by the worker. Returns true if the waiter had already left,
        /// meaning this thread is the one that must return the counter slot.
        func finish(_ produced: Value) -> Bool {
            lock.lock(); defer { lock.unlock() }
            value = produced
            let wasAbandoned = settled
            settled = true
            return wasAbandoned
        }

        /// Called by the waiter when its deadline passed. Returns true if the
        /// worker had not finished yet, meaning the run really is abandoned.
        func abandon() -> Bool {
            lock.lock(); defer { lock.unlock() }
            guard !settled else { return false }
            settled = true
            return true
        }

        func result() -> Value? {
            lock.lock(); defer { lock.unlock() }
            return value
        }
    }

    private final class AbandonedCounter: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0

        /// Takes a slot if one is free. Taking it up front — rather than only
        /// on timeout — is what keeps concurrent callers from all passing a
        /// check and then all abandoning past the cap.
        func acquire(limit: Int) -> Bool {
            lock.lock(); defer { lock.unlock() }
            guard count < limit else { return false }
            count += 1
            return true
        }

        func release() {
            lock.lock(); count = max(0, count - 1); lock.unlock()
        }

        var current: Int {
            lock.lock(); defer { lock.unlock() }
            return count
        }
    }

    private static let abandoned = AbandonedCounter()

    /// How many regex runs are currently occupying a slot — running normally,
    /// or abandoned and still burning a core.
    public static var abandonedThreadCount: Int { abandoned.current }

    /// Runs `work` on a thread this call is willing to walk away from.
    ///
    /// Returns `work`'s result, or throws `.timedOut` — in which case the
    /// thread is still running. It is not killed, because killing a thread
    /// inside ICU corrupts the allocator; it is left to finish and keeps
    /// occupying its slot until it does.
    public static func runBounded<Value: Sendable>(
        timeout: Double = timeoutSeconds,
        _ work: @escaping @Sendable () -> Value
    ) throws -> Value {
        guard abandoned.acquire(limit: maximumAbandonedThreads) else {
            throw Rejection.tooManyAbandoned
        }

        let state = RunState<Value>()
        let finished = DispatchSemaphore(value: 0)

        let thread = Thread {
            let wasAbandoned = state.finish(work())
            if wasAbandoned {
                // The waiter is long gone; nobody else will free this slot.
                abandoned.release()
            } else {
                finished.signal()
            }
        }
        thread.stackSize = 4 * 1024 * 1024
        thread.start()

        if finished.wait(timeout: .now() + timeout) == .timedOut {
            if state.abandon() {
                // The slot stays taken; the worker returns it when ICU
                // eventually lets go.
                throw Rejection.timedOut(seconds: timeout)
            }
            // The worker finished in the same instant the deadline passed, so
            // it signalled after this wait gave up. Consume that signal rather
            // than leaving it to unbalance the next use of this semaphore.
            finished.wait()
        }
        abandoned.release()
        guard let value = state.result() else {
            throw Rejection.invalid("the search produced no result")
        }
        return value
    }
}
