import XCTest
@testable import MaruEditCore

final class ToolbarLayoutTests: XCTestCase {
    private let available: Set<String> = ["a", "b", "c", "d"]

    func testNormalizationDropsUnknownDuplicatesAndOrphanSeparators() {
        let layout = ToolbarLayout(entries: ["-", "a", "a", "-", "-", "missing", "b", "-"])
        XCTAssertEqual(layout.normalized(availableKeys: available).entries, ["a", "-", "b"])
    }

    func testAddRemoveMoveAndSeparatorPreserveOrderedLayout() {
        var layout = ToolbarLayout(entries: ["a", "b", "c"])
        layout.move("c", offset: -2, availableKeys: available)
        layout.insertSeparator(after: "c")
        layout.remove("b")
        layout.append("d", availableKeys: available)
        XCTAssertEqual(layout.entries, ["c", "-", "a", "d"])
    }

    func testLayoutRoundTripsThroughJSON() throws {
        let original = ToolbarLayout(entries: ["a", "-", "b"])
        XCTAssertEqual(try JSONDecoder().decode(ToolbarLayout.self, from: JSONEncoder().encode(original)), original)
    }

    func testEveryDisplayModeRoundTripsByStableRawValue() throws {
        for mode in ToolbarDisplayMode.allCases {
            XCTAssertEqual(ToolbarDisplayMode(rawValue: mode.rawValue), mode)
        }
    }
}
