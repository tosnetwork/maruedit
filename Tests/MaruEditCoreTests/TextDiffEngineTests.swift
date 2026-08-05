import XCTest
@testable import MaruEditCore

final class TextDiffEngineTests: XCTestCase {
    func testProducesSeparateReplacementInsertionAndDeletionHunks() {
        let old = "a\nb\nc\nd\n"
        let new = "a\nB\nc\nd\ne\n"
        let hunks = TextDiffEngine.compare(old, new)
        XCTAssertEqual(hunks.count, 2)
        XCTAssertEqual(hunks[0].originalRange, NSRange(location: 2, length: 2))
        XCTAssertEqual(hunks[0].replacement, "B\n")
        XCTAssertEqual(hunks[1].originalRange.location, (old as NSString).length)
        XCTAssertEqual(TextDiffEngine.applying(hunks[0], to: old), "a\nB\nc\nd\n")
    }

    func testUnicodeRangesAndDeletionAreUTF16Safe() {
        let old = "😀\n削除\nkeep"
        let new = "😀\nkeep"
        let hunk = TextDiffEngine.compare(old, new).first!
        XCTAssertEqual((old as NSString).substring(with: hunk.originalRange), "削除\n")
        XCTAssertEqual(TextDiffEngine.applying(hunk, to: old), new)
    }

    func testEqualTextHasNoHunksAndInvalidApplyIsRejected() {
        XCTAssertTrue(TextDiffEngine.compare("same", "same").isEmpty)
        let invalid = TextDiffHunk(
            id: 0, originalRange: NSRange(location: 99, length: 1), replacement: "x",
            originalStartLine: 0, replacementStartLine: 0)
        XCTAssertNil(TextDiffEngine.applying(invalid, to: "short"))
    }

    func testHugeInputDegradesToOneBoundedWholeDocumentHunk() {
        let old = Array(repeating: "a", count: 1_001).joined(separator: "\n")
        let new = Array(repeating: "b", count: 1_001).joined(separator: "\n")
        let hunks = TextDiffEngine.compare(old, new)
        XCTAssertEqual(hunks.count, 1)
        XCTAssertEqual(TextDiffEngine.applying(hunks[0], to: old), new)
    }
}
