import XCTest
@testable import MaruEditCore

final class FunctionKeyLayoutTests: XCTestCase {
    func testNormalizationLimitsPadsAndRejectsUnknownCommands() {
        let layout = FunctionKeyLayout(assignments: [.init("a"), .init("missing"), nil, .init("b")])
        XCTAssertEqual(layout.normalized(maximumSlots: 3, available: [.init("a"), .init("b")]).assignments,
                       [.init("a"), nil, nil])
    }

    func testAssignmentsRoundTripThroughJSON() throws {
        let layout = FunctionKeyLayout(assignments: [.init("file.save"), nil, .init("search.find")])
        XCTAssertEqual(try JSONDecoder().decode(FunctionKeyLayout.self, from: JSONEncoder().encode(layout)), layout)
    }
}
