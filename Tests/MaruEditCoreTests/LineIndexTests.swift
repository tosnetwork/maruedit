import XCTest
@testable import MaruEditCore

final class LineIndexTests: XCTestCase {
    func testLineAndOffsetConversionsIncludeTrailingEmptyLine() {
        let index = LineIndex("one\n二\n")
        XCTAssertEqual(index.lineCount, 3)
        XCTAssertEqual(index.line(atUTF16Offset: 0), 0)
        XCTAssertEqual(index.line(atUTF16Offset: 4), 1)
        XCTAssertEqual(index.line(atUTF16Offset: 6), 2)
        XCTAssertEqual(index.utf16Offset(forLine: 1), 4)
        XCTAssertEqual(index.contentRange(forLine: 0), NSRange(location: 0, length: 3))
        XCTAssertEqual(index.contentRange(forLine: 2), NSRange(location: 6, length: 0))
        XCTAssertNil(index.utf16Offset(forLine: 3))
    }

    func testIncrementalEditsShiftOnlyFollowingStarts() {
        var index = LineIndex("aa\nbb\ncc")
        index.applyEdit(range: NSRange(location: 3, length: 2), replacement: "B\nB\nB")
        XCTAssertEqual(index, LineIndex("aa\nB\nB\nB\ncc"))
        index.applyEdit(range: NSRange(location: 2, length: 1), replacement: "")
        XCTAssertEqual(index, LineIndex("aaB\nB\nB\ncc"))
    }

    func testDisplayColumnsHandleTabsWideAndAstralCharacters() {
        let text = "a\t日👍x"
        let index = LineIndex(text)
        XCTAssertEqual(index.displayColumn(atUTF16Offset: 2, in: text, tabWidth: 4), 4)
        XCTAssertEqual(index.displayColumn(atUTF16Offset: 3, in: text, tabWidth: 4), 6)
        XCTAssertEqual(index.displayColumn(atUTF16Offset: 5, in: text, tabWidth: 4), 8)
        XCTAssertEqual(index.utf16Offset(forLine: 0, displayColumn: 6, in: text, tabWidth: 4), 3)
    }

    func testRandomizedIncrementalEditsMatchFreshIndex() {
        var generator = LCRNG(seed: 0x4D617275)
        var text = "alpha\nβeta\n日本語\n👍"
        var index = LineIndex(text)
        let fragments = ["", "x", "\n", "ab\ncd", "日", "👍", "\n\n"]

        for _ in 0..<2_000 {
            let ns = text as NSString
            let location = generator.nextInt(upperBound: ns.length + 1)
            let maximumLength = ns.length - location
            let length = generator.nextInt(upperBound: min(5, maximumLength) + 1)
            let replacement = fragments[generator.nextInt(upperBound: fragments.count)]
            let range = NSRange(location: location, length: length)
            index.applyEdit(range: range, replacement: replacement)
            text = ns.replacingCharacters(in: range, with: replacement)
            XCTAssertEqual(index, LineIndex(text))
        }
    }
}

private struct LCRNG {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func nextInt(upperBound: Int) -> Int {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Int(state % UInt64(upperBound))
    }
}
