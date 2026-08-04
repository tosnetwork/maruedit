import XCTest
import MaruEditCore
@preconcurrency @testable import MaruEditApp


@preconcurrency @MainActor
final class SaveAsFormatAccessoryViewTests: XCTestCase {

    func testInitialSelectionMatchesConstructorArguments() async {
        let view = SaveAsFormatAccessoryView(initialEncoding: .eucJP, initialHasByteOrderMark: false)
        XCTAssertEqual(view.selectedEncoding, .eucJP)
        XCTAssertFalse(view.includesByteOrderMark)
    }

    func testBOMCheckboxStartsCheckedWhenRequested() async {
        let view = SaveAsFormatAccessoryView(initialEncoding: .utf8, initialHasByteOrderMark: true)
        XCTAssertTrue(view.includesByteOrderMark)
    }

    func testListsEveryUserSelectableEncoding() async {
        for encoding in TextEncoding.userSelectable {
            let view = SaveAsFormatAccessoryView(initialEncoding: encoding, initialHasByteOrderMark: false)
            XCTAssertEqual(view.selectedEncoding, encoding, "\(encoding.rawValue) should be selectable and initially selected")
        }
    }
}
