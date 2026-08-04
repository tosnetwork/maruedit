import AppKit
import XCTest
@testable import MaruEditApp

final class SyntaxHighlightCoordinatorTests: XCTestCase {
    private let font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)

    func testInvalidRuleIsIgnoredWhileValidRulesStillMatch() {
        let highlighter = SyntaxHighlighter(definitions: [
            ("[", .red),
            ("\\blet\\b", .green),
        ])

        let matches = highlighter.matches(
            in: "let value = 1", range: NSRange(location: 0, length: 13))

        XCTAssertEqual(matches.count, 1)
        XCTAssertEqual(matches.first?.range, NSRange(location: 0, length: 3))
        XCTAssertEqual(matches.first?.color, .green)
    }

    func testVisibleRangeExpandsToBufferedWholeLinesAndClamps() {
        let text = "zero\none\ntwo\nthree\n"
        let range = SyntaxHighlightCoordinator.requiredContextRange(
            for: NSRange(location: 9, length: 1), in: text, buffer: 3)

        XCTAssertEqual((text as NSString).substring(with: range), "one\ntwo\n")
        XCTAssertLessThanOrEqual(NSMaxRange(range), (text as NSString).length)
    }

    func testNewRevisionPreventsQueuedStaleWorkFromApplying() {
        let worker = DispatchQueue(label: "SyntaxHighlightCoordinatorTests.suspended")
        worker.suspend()
        let coordinator = SyntaxHighlightCoordinator(workerQueue: worker)
        let storage = NSTextStorage(string: "let old = 1")
        var firstCompleted = false
        coordinator.schedule(
            storage: storage, language: .swift, visibleRange: nil, font: font, delay: 0
        ) { firstCompleted = true }
        runMainLoopBriefly()

        storage.replaceCharacters(in: NSRange(location: 0, length: storage.length), with: "plain")
        let latest = expectation(description: "latest revision applied")
        coordinator.schedule(
            storage: storage, language: .plainText, visibleRange: nil, font: font, delay: 0
        ) { latest.fulfill() }
        runMainLoopBriefly()
        worker.resume()

        wait(for: [latest], timeout: 1)
        XCTAssertFalse(firstCompleted)
        XCTAssertEqual(storage.string, "plain")
        XCTAssertEqual(coordinator.revision, 2)
    }

    func testDebounceOnlyAppliesNewestRequest() {
        let coordinator = SyntaxHighlightCoordinator()
        let storage = NSTextStorage(string: "let value = 1")
        var firstCompleted = false
        coordinator.schedule(
            storage: storage, language: .swift, visibleRange: nil, font: font, delay: 0.08
        ) { firstCompleted = true }
        let latest = expectation(description: "latest request")
        coordinator.schedule(
            storage: storage, language: .swift, visibleRange: nil, font: font, delay: 0.01
        ) { latest.fulfill() }

        wait(for: [latest], timeout: 1)
        XCTAssertFalse(firstCompleted)
        XCTAssertEqual(coordinator.revision, 2)
    }

    func testLargeFileModeDisablesRegexColorsWithoutChangingText() {
        let text = String(repeating: "let value = 1\n", count: 8_000)
        XCTAssertGreaterThan((text as NSString).length, SyntaxHighlightCoordinator.largeFileThreshold)
        let storage = NSTextStorage(string: text)
        storage.addAttribute(.foregroundColor, value: NSColor.red,
                             range: NSRange(location: 0, length: storage.length))
        let coordinator = SyntaxHighlightCoordinator()

        coordinator.schedule(
            storage: storage, language: .swift, visibleRange: NSRange(location: 0, length: 100),
            font: font, delay: 0)

        XCTAssertTrue(coordinator.isLargeFileMode)
        XCTAssertNil(coordinator.lastAppliedRange)
        XCTAssertEqual(storage.string, text)
        XCTAssertEqual(storage.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor,
                       Theme.foreground)
    }

    func testThemeRefreshChangesAttributesOnly() {
        let storage = NSTextStorage(string: "let value = 1")
        let original = storage.string
        let applied = expectation(description: "highlight applied")
        let coordinator = SyntaxHighlightCoordinator()
        coordinator.schedule(
            storage: storage, language: .swift, visibleRange: nil, font: font, delay: 0
        ) { applied.fulfill() }

        wait(for: [applied], timeout: 1)
        XCTAssertEqual(storage.string, original)
        XCTAssertEqual(storage.length, (original as NSString).length)
    }

    func testPerformanceHighlightingRequiredViewportContext() {
        let text = String(repeating: "func render(value: Int) -> String { return \"\\(value)\" }\n", count: 2_000)
        let highlighter = SyntaxHighlighter(language: .swift)
        let center = (text as NSString).length / 2
        let range = SyntaxHighlightCoordinator.requiredContextRange(
            for: NSRange(location: center, length: 1_000), in: text)

        measure {
            XCTAssertFalse(highlighter.matches(in: text, range: range).isEmpty)
        }
    }

    func testRegexBudgetCapsInputMatchesAndPathologicalWork() throws {
        let fixtureURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Fixtures/Syntax/stress.swift")
        let fixture = try String(contentsOf: fixtureURL, encoding: .utf8)
        let text = String(repeating: fixture, count: 200)
        let highlighter = SyntaxHighlighter(definitions: [
            ("(a+)+$", .red),
            ("\\b(let|func|struct|return)\\b", .green),
        ])
        let budget = SyntaxHighlighter.WorkBudget(
            maximumDuration: 0.02, maximumMatches: 25, maximumUTF16Length: 4_096)
        let started = CFAbsoluteTimeGetCurrent()

        let batch = highlighter.matchBatch(
            in: text, range: NSRange(location: 0, length: (text as NSString).length),
            budget: budget)

        XCTAssertTrue(batch.wasTruncated)
        XCTAssertLessThanOrEqual(batch.matches.count, 25)
        XCTAssertLessThan(CFAbsoluteTimeGetCurrent() - started, 0.5)
    }

    func testStressFixtureSurvivesRapidRevisionChurn() throws {
        let fixtureURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Fixtures/Syntax/stress.swift")
        let fixture = try String(contentsOf: fixtureURL, encoding: .utf8)
        let storage = NSTextStorage(string: String(repeating: fixture, count: 40))
        let coordinator = SyntaxHighlightCoordinator()
        var staleCompletions = 0
        for offset in 0..<50 {
            coordinator.schedule(
                storage: storage, language: .swift,
                visibleRange: NSRange(location: offset, length: 200), font: font, delay: 0.01
            ) { staleCompletions += 1 }
        }
        let latest = expectation(description: "latest stress revision")
        coordinator.schedule(
            storage: storage, language: .swift,
            visibleRange: NSRange(location: 500, length: 200), font: font, delay: 0
        ) { latest.fulfill() }

        wait(for: [latest], timeout: 2)
        XCTAssertEqual(staleCompletions, 0)
        XCTAssertEqual(coordinator.revision, 51)
        XCTAssertLessThan(coordinator.lastAppliedRange?.length ?? .max, 8_000)
    }

    private func runMainLoopBriefly() {
        RunLoop.main.run(until: Date().addingTimeInterval(0.03))
    }
}
