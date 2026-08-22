import Foundation
import XCTest
@testable import MaruEditCore

/// A client-supplied pattern is untrusted input that runs inside an
/// uninterruptible library call, so the tests are about what gets refused and
/// what happens when a refusal was not enough.
final class AgentRegexGuardTests: XCTestCase {

    private func rejection(_ pattern: String) -> AgentRegexGuard.Rejection? {
        do {
            try AgentRegexGuard.validate(pattern)
            return nil
        } catch let rejection as AgentRegexGuard.Rejection {
            return rejection
        } catch {
            return nil
        }
    }

    // MARK: - What must be refused

    func testNestedUnboundedQuantifiersAreRefused() {
        // The classic exponential shapes. Each of these against a 30-character
        // near-match runs longer than the machine will be switched on.
        for pattern in ["(a+)+", "(a*)*", "(a+)*", "([a-z]+)+$", "(\\w+\\s?)*", "(x+x+)+y"] {
            XCTAssertNotNil(rejection(pattern), "\(pattern) must not be accepted")
        }
    }

    func testRepeatedAlternationIsRefused() {
        XCTAssertEqual(rejection("(a|a)*"), .repeatedAlternation)
        XCTAssertEqual(rejection("(a|ab)+"), .repeatedAlternation)
        XCTAssertEqual(rejection("(foo|bar){2,}"), .repeatedAlternation)
    }

    func testUnboundedRepetitionOfSomethingOptionalIsRefused() {
        XCTAssertEqual(rejection("(a?)*"), .unboundedRepetitionOfOptional)
        XCTAssertEqual(rejection("(a*b?)+"), .nestedUnboundedQuantifier)
    }

    func testExponentialShapeIsStillCaughtThroughAnExtraGroupLayer() {
        // `(a+)` is bounded here, but the inner `+` still propagates outward,
        // so wrapping it again is the same exponential pattern one level up.
        XCTAssertEqual(rejection("((a+){1,4})+"), .nestedUnboundedQuantifier)
        XCTAssertEqual(rejection("((?:a+))+"), .nestedUnboundedQuantifier)
    }

    func testPatternLengthIsBounded() {
        XCTAssertEqual(
            rejection(String(repeating: "a", count: 600)),
            .patternTooLong(600))
    }

    func testMalformedPatternsAreRejectedWithAReason() {
        XCTAssertNotNil(rejection("(unclosed"))
        XCTAssertNotNil(rejection("unopened)"))
        XCTAssertNotNil(rejection("[z-a]"))
    }

    // MARK: - What must still work

    func testOrdinaryPatternsAreAccepted() {
        for pattern in [
            "TODO", "^\\s*func\\s+\\w+", "[0-9]{1,3}(\\.[0-9]{1,3}){3}",
            "\\bclass\\s+[A-Z]\\w*", "(?i)error|warning", "a+b+c+",
            "(foo|bar)", "https?://[^\\s]+", "\\(\\d+\\)", "[*+?]{1,4}",
            "(a+)?", "x{2,8}", "(?:abc)+",
        ] {
            XCTAssertNil(rejection(pattern), "\(pattern) is safe and must be accepted")
        }
    }

    func testQuantifierCharactersInsideAClassAreLiteral() {
        // `[+*]` is a class of two literals, not two quantifiers, so wrapping
        // it in `+` must not read as nesting.
        XCTAssertNil(rejection("[+*]+"))
        XCTAssertNil(rejection("[]()+]+"))
        XCTAssertNil(rejection("\\(+"))
    }

    func testLazyAndPossessiveSuffixesDoNotHideTheQuantifier() {
        // `+?` is still unbounded; only the search strategy differs.
        XCTAssertEqual(rejection("(a+?)+?"), .nestedUnboundedQuantifier)
    }

    // MARK: - The bound that runs

    func testABoundedRunReturnsItsValue() throws {
        let value = try AgentRegexGuard.runBounded { 21 * 2 }
        XCTAssertEqual(value, 42)
        XCTAssertEqual(
            AgentRegexGuard.abandonedThreadCount, 0,
            "a run that finished must give its slot back")
    }

    func testAnOverrunningRunIsAbandonedAndThenReclaimed() throws {
        let started = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)

        XCTAssertThrowsError(
            try AgentRegexGuard.runBounded(timeout: 0.2) { () -> Int in
                started.signal()
                release.wait()
                return 1
            }
        ) { error in
            XCTAssertEqual(error as? AgentRegexGuard.Rejection, .timedOut(seconds: 0.2))
        }

        XCTAssertEqual(started.wait(timeout: .now() + 1), .success)
        XCTAssertEqual(
            AgentRegexGuard.abandonedThreadCount, 1,
            "the thread is still running, and saying otherwise would be a lie")

        // Slots are finite, so the next caller is refused rather than allowed
        // to add a second spinning core.
        release.signal()

        // The worker returns the slot once it finally finishes.
        let deadline = Date().addingTimeInterval(2)
        while AgentRegexGuard.abandonedThreadCount > 0, Date() < deadline {
            usleep(10_000)
        }
        XCTAssertEqual(AgentRegexGuard.abandonedThreadCount, 0)
    }

    func testRegexSearchIsRefusedWhileTooManyRunsAreAbandoned() throws {
        var releases: [DispatchSemaphore] = []
        for _ in 0..<AgentRegexGuard.maximumAbandonedThreads {
            let release = DispatchSemaphore(value: 0)
            releases.append(release)
            XCTAssertThrowsError(
                try AgentRegexGuard.runBounded(timeout: 0.1) { () -> Int in
                    release.wait()
                    return 0
                })
        }

        XCTAssertThrowsError(try AgentRegexGuard.runBounded(timeout: 0.1) { 0 }) { error in
            XCTAssertEqual(error as? AgentRegexGuard.Rejection, .tooManyAbandoned)
        }

        releases.forEach { $0.signal() }
        let deadline = Date().addingTimeInterval(2)
        while AgentRegexGuard.abandonedThreadCount > 0, Date() < deadline {
            usleep(10_000)
        }
        XCTAssertEqual(AgentRegexGuard.abandonedThreadCount, 0)
    }

    // MARK: - The two halves together

    func testAcceptedPatternsActuallyFinishQuicklyOnHostileInput() throws {
        // The analysis claims accepted patterns cannot blow up. This runs them
        // against the input designed to make a bad pattern blow up, under the
        // real bound, and asserts none of them needs it.
        let hostile = String(repeating: "a", count: 40) + "!"
        for pattern in ["a+b+c+", "[a-z]+@[a-z]+", "^\\s*\\w{1,32}$", "(?:ab)+c"] {
            let expression = try NSRegularExpression(pattern: pattern)
            let count = try AgentRegexGuard.runBounded(timeout: 1.0) {
                expression.numberOfMatches(
                    in: hostile, range: NSRange(location: 0, length: hostile.utf16.count))
            }
            XCTAssertGreaterThanOrEqual(count, 0)
        }
    }

    func testResultsHaveTheSameShapeWhicheverSearchProducedThem() throws {
        let documents = [(id: "doc_1", revision: UInt64(3), metadataRevision: UInt64(1),
                          text: "alpha\nbeta gamma\ndelta\n")]
        let literal = AgentTextSlicer.searchLiteral(
            in: documents, query: "gamma", ignoreCase: false, limit: 10)
        let pattern = AgentTextSlicer.searchRegularExpression(
            in: documents,
            expression: try NSRegularExpression(pattern: "gam+a"),
            limit: 10)

        XCTAssertEqual(literal.matches.count, 1)
        XCTAssertEqual(pattern.matches.count, 1)
        // Same offsets, same line and column, same context — a client must not
        // have to know which engine answered.
        XCTAssertEqual(literal.matches.first, pattern.matches.first)
    }

    func testRegexResultsAreBoundedByTheSameLimit() throws {
        let documents = [(id: "doc_1", revision: UInt64(1), metadataRevision: UInt64(1),
                          text: String(repeating: "x\n", count: 500))]
        let results = AgentTextSlicer.searchRegularExpression(
            in: documents, expression: try NSRegularExpression(pattern: "x"), limit: 10)
        XCTAssertEqual(results.matches.count, 10)
        XCTAssertTrue(results.truncated)
    }
}
