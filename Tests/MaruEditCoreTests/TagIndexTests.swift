import XCTest
@testable import MaruEditCore

final class TagIndexTests: XCTestCase {
    func testParsesNumericAndSearchAddressesAndIgnoresMetadata() {
        let index = TagIndex(contents: """
        !_TAG_FILE_FORMAT\t2\t/extended format/
        Alpha\tSources/A.swift\t12;\"\tc
        beta\tSources/B.swift\t/^func beta() {$/;\"\tf
        broken
        """)
        XCTAssertEqual(index.matches(named: "Alpha").first?.line, 12)
        XCTAssertEqual(index.matches(named: "beta").first?.searchPattern, "func beta() {")
    }

    func testResolutionRejectsTraversalOutsideProject() {
        let root = URL(fileURLWithPath: "/tmp/project", isDirectory: true)
        XCTAssertNotNil(TagIndex.fileURL(for: .init(name: "x", relativePath: "Sources/x.swift", line: 1), relativeTo: root))
        XCTAssertNil(TagIndex.fileURL(for: .init(name: "x", relativePath: "../secret", line: 1), relativeTo: root))
    }

    func testLineAndUnicodePatternOffsetsAreUTF16() {
        XCTAssertEqual(TagIndex.utf16Offset(for: .init(name: "x", relativePath: "x", line: 3), in: "a\n😀\nlast"), 5)
        XCTAssertEqual(TagIndex.utf16Offset(for: .init(name: "x", relativePath: "x", searchPattern: "last"), in: "😀\nlast"), 3)
    }
}
