import XCTest
@testable import MaruEditCore

final class SharedOutputTests: XCTestCase {
    func testChannelsSeverityOrderingClearAndLimits() {
        var buffer = SharedOutputBuffer(maximumEntries: 4, maximumUTF8Bytes: 256)
        buffer.append("one", channel: .grep)
        buffer.append("two", channel: .standardOutput)
        buffer.append("three", channel: .standardError, severity: .error)
        buffer.append("four", channel: .macro, severity: .warning)
        buffer.append("five", channel: .system)
        XCTAssertTrue(buffer.didTruncate)
        XCTAssertLessThanOrEqual(buffer.entries.count, 4)
        XCTAssertLessThanOrEqual(buffer.currentUTF8Bytes, 256)
        XCTAssertEqual(buffer.entries.first?.severity, .warning)
        XCTAssertEqual(buffer.entries.last?.message, "five")
        buffer.clear()
        XCTAssertTrue(buffer.entries.isEmpty)
        XCTAssertFalse(buffer.didTruncate)
    }

    func testLocationParserSupportsAbsoluteRelativeAndColumns() {
        let base = URL(fileURLWithPath: "/tmp/project", isDirectory: true)
        XCTAssertEqual(OutputLocationParser.parse("Sources/a.swift:12:7: error", relativeTo: base),
                       OutputLocation(url: base.appendingPathComponent("Sources/a.swift"), line: 12, column: 7))
        XCTAssertEqual(OutputLocationParser.parse("/tmp/a.txt:3: hello")?.line, 3)
        XCTAssertNil(OutputLocationParser.parse("ordinary output"))
    }
}
