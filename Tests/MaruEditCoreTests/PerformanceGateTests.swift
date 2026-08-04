import Foundation
import XCTest
@testable import MaruEditCore

/// Reproducible, non-threshold performance probes for ROADMAP M7-08.
/// They print machine-readable `M7_PERF` records; targets and interpretation
/// live in docs/performance.md so normal CI is not made flaky by wall-clock
/// assertions.
final class PerformanceGateTests: XCTestCase {
    func testLiteralFindNextInTenMegabytes() throws {
        let targetBytes = 10_000_000
        let line = "ordinary synthetic performance fixture line 0123456789\n"
        var text = String(repeating: line, count: targetBytes / line.utf8.count + 1)
        text += "unique-performance-needle"
        let query = SearchQuery(pattern: "unique-performance-needle")

        let samples = try (0..<7).map { _ -> Double in
            let start = ProcessInfo.processInfo.systemUptime
            let match = try SearchEngine.nextMatch(for: query, in: text, from: 0)
            XCTAssertNotNil(match)
            return (ProcessInfo.processInfo.systemUptime - start) * 1_000
        }

        printMetric("find_next_10mb_ms", samples: samples)
    }

    func testGrepResponsivenessAndThroughput() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MaruEditPerformanceGrep-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let payload = String(repeating: "ordinary searchable line\n", count: 4_000)
        for index in 0..<100 {
            try (payload + (index == 0 ? "unique-performance-needle\n" : ""))
                .write(to: root.appendingPathComponent("fixture-\(index).txt"),
                       atomically: true, encoding: .utf8)
        }

        let request = GrepRequest(
            query: SearchQuery(pattern: "unique-performance-needle"), roots: [root])
        let start = ProcessInfo.processInfo.systemUptime
        var firstEventMilliseconds: Double?
        var firstMatchMilliseconds: Double?
        var summary = GrepSummary()
        GrepService.run(request) { event in
            if firstEventMilliseconds == nil {
                firstEventMilliseconds = (ProcessInfo.processInfo.systemUptime - start) * 1_000
            }
            if firstMatchMilliseconds == nil, case .match = event {
                firstMatchMilliseconds = (ProcessInfo.processInfo.systemUptime - start) * 1_000
            }
            if case .finished(let value) = event { summary = value }
        }
        let totalMilliseconds = (ProcessInfo.processInfo.systemUptime - start) * 1_000

        XCTAssertEqual(summary.scannedFiles, 100)
        XCTAssertEqual(summary.matchCount, 1)
        print("M7_PERF grep_10mb_first_event_ms=\(formatted(firstEventMilliseconds ?? totalMilliseconds))")
        print("M7_PERF grep_10mb_first_match_ms=\(formatted(firstMatchMilliseconds ?? totalMilliseconds))")
        print("M7_PERF grep_10mb_total_ms=\(formatted(totalMilliseconds))")
    }

    private func printMetric(_ name: String, samples: [Double]) {
        let sorted = samples.sorted()
        let median = sorted[sorted.count / 2]
        print("M7_PERF \(name)=\(formatted(median)) min=\(formatted(sorted[0])) max=\(formatted(sorted.last!)) n=\(samples.count)")
    }

    private func formatted(_ value: Double) -> String {
        String(format: "%.1f", value)
    }
}
