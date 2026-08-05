import XCTest
@testable import MaruEditCore

final class OutlineModelTests: XCTestCase {
    func testSwiftSymbolsIncludeUnicodeTypesFunctionsAndProperties() {
        let model = OutlineModel(text: """
        struct 設定 {
            let value = 1
            func 保存() {}
        }
        """, language: .swift)
        XCTAssertEqual(model.symbols.map(\.title), ["設定", "value", "保存"])
        XCTAssertEqual(model.symbols.map(\.kind), [.type, .property, .function])
        XCTAssertEqual(model.symbols.map(\.level), [0, 1, 1])
    }

    func testMarkdownHeadingLevelsAndRanges() {
        let text = "# Top\ntext\n### Detail\n"
        let model = OutlineModel(text: text, language: .markdown)
        XCTAssertEqual(model.symbols.map(\.title), ["Top", "Detail"])
        XCTAssertEqual(model.symbols.map(\.level), [0, 2])
        XCTAssertEqual((text as NSString).substring(with: model.symbols[1].utf16Range), "Detail")
    }

    func testIncrementalEditPreservesPrefixAndUpdatesShiftedLines() {
        var model = OutlineModel(text: "# Keep\ntext\n# Old\n", language: .markdown)
        let prefix = model.symbols[0]
        model.applyEdit(range: NSRange(location: 14, length: 3), replacement: "New\n## Child")
        XCTAssertEqual(model.symbols[0], prefix)
        XCTAssertEqual(model.symbols.map(\.title), ["Keep", "New", "Child"])
        XCTAssertEqual(model.symbols.map(\.line), [0, 2, 3])
    }

    func testInvalidEditIsIgnoredAndPlainTextHasNoSymbols() {
        var model = OutlineModel(text: "hello", language: .plainText)
        model.applyEdit(range: NSRange(location: 99, length: 1), replacement: "x")
        XCTAssertEqual(model.text, "hello")
        XCTAssertTrue(model.symbols.isEmpty)
    }

    func testCustomProfileRuleRunsBeforeBuiltInRules() {
        let rule = OutlineRule(
            id: "region", pattern: #"^\s*//\s*MARK:\s*(.+)$"#,
            kind: .section, titleCaptureGroup: 1, fixedLevel: 2)
        let model = OutlineModel(
            text: "// MARK: Networking\nfunc load() {}", language: .swift,
            customRules: [rule])
        XCTAssertEqual(model.symbols.map(\.title), ["Networking", "load"])
        XCTAssertEqual(model.symbols.first?.level, 2)
    }

    func testMalformedAndExcessiveRulesDegradeSafely() {
        let invalid = OutlineRule(pattern: "(")
        let valid = OutlineRule(pattern: #"^SECTION (.+)$"#)
        let rules = [invalid, valid] + (0..<100).map {
            OutlineRule(id: "unused-\($0)", pattern: #"^NEVER (.+)$"#)
        }
        let oversized = "SECTION " + String(repeating: "x", count: OutlineModel.maximumScannedLineLength)
        let model = OutlineModel(
            text: "SECTION Kept\n\(oversized)", language: .plainText,
            customRules: rules)
        XCTAssertEqual(model.symbols.map(\.title), ["Kept"])
        XCTAssertEqual(model.customRules.count, OutlineModel.maximumCustomRuleCount)
    }

    func testUnsafeRegexAndInvalidCaptureGroupsAreRejected() {
        XCTAssertEqual(OutlineRule(pattern: #"^(a+)+$"#).validationError(), .unsafeBacktracking)
        XCTAssertEqual(OutlineRule(pattern: #"^(a)\1$"#).validationError(), .unsafeBacktracking)
        XCTAssertEqual(OutlineRule(pattern: "(").validationError(), .invalidPattern)
        XCTAssertEqual(
            OutlineRule(pattern: #"^(.+)$"#, titleCaptureGroup: 2).validationError(),
            .invalidCaptureGroup)
    }

    func testLargeOutlineCapsSymbolMemoryAndStillReturnsPrefixInOrder() {
        let text = (0..<(OutlineModel.maximumSymbolCount + 500)).map { "# Heading \($0)" }
            .joined(separator: "\n")
        let model = OutlineModel(text: text, language: .markdown)
        XCTAssertEqual(model.symbols.count, OutlineModel.maximumSymbolCount)
        XCTAssertEqual(model.symbols.first?.title, "Heading 0")
        XCTAssertEqual(model.symbols.last?.title, "Heading \(OutlineModel.maximumSymbolCount - 1)")
    }
}
