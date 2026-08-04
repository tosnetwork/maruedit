import XCTest
import MaruEditCore
@testable import MaruEditApp

final class SaveAsFormatAccessoryViewTests: XCTestCase {

    func testInitialSelectionMatchesConstructorArguments() {
        let view = SaveAsFormatAccessoryView(initialEncoding: .eucJP, initialHasByteOrderMark: false)
        XCTAssertEqual(view.selectedEncoding, .eucJP)
        XCTAssertFalse(view.includesByteOrderMark)
    }

    func testBOMCheckboxStartsCheckedWhenRequested() {
        let view = SaveAsFormatAccessoryView(initialEncoding: .utf8, initialHasByteOrderMark: true)
        XCTAssertTrue(view.includesByteOrderMark)
    }

    func testListsEveryUserSelectableEncoding() {
        for encoding in TextEncoding.userSelectable {
            let view = SaveAsFormatAccessoryView(initialEncoding: encoding, initialHasByteOrderMark: false)
            XCTAssertEqual(view.selectedEncoding, encoding, "\(encoding.rawValue) should be selectable and initially selected")
        }
    }
}
