import XCTest
@preconcurrency @testable import MaruEditApp

@preconcurrency @MainActor
final class TableModeTests: XCTestCase {
    func testTableModeChangesPresentationOnlyAndTogglesCleanly() {
        let editor = EditorViewController(); _ = editor.view
        editor.document = Document(content: "a,long\nwide,x")
        let original = editor.textView.string
        editor.toggleDelimitedTableMode()
        XCTAssertTrue(editor.isTableMode)
        XCTAssertNotNil(editor.textView.textStorage?.attribute(.kern, at: 1, effectiveRange: nil))
        XCTAssertEqual(editor.textView.string, original)
        editor.toggleDelimitedTableMode()
        XCTAssertFalse(editor.isTableMode)
        XCTAssertNil(editor.textView.textStorage?.attribute(.kern, at: 1, effectiveRange: nil))
        XCTAssertEqual(editor.textView.string, original)
    }
}
