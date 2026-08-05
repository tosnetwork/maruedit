import XCTest
@testable import MaruEditCore

final class DelimitedTableModelTests: XCTestCase {
    func testCSVQuotesCommasAndEscapedQuotes() {
        let model = DelimitedTableModel(text: "name,note\nA,\"x,y\"\nB,\"say \"\"hi\"\"\"")
        XCTAssertEqual(model.rows.map { $0.map(\.value) }, [
            ["name", "note"], ["A", "x,y"], ["B", "say \"hi\""],
        ])
        XCTAssertEqual(model.columnWidths, [4, 8])
    }

    func testTSVIsDetectedAndRangesRemainUTF16() {
        let model = DelimitedTableModel(text: "😀\t日本\nx\ty")
        XCTAssertEqual(model.delimiter, "\t")
        XCTAssertEqual(model.rows[0][1].range.location, 3)
        XCTAssertEqual(model.rows[0][1].range.length, 2)
    }
}
