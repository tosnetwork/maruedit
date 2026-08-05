@preconcurrency import AppKit
@testable import MaruEditApp
import MaruEditCore
import XCTest

@MainActor
final class PartialOutlineEditingTests: XCTestCase {
    func testPartialEditingIsolatesContainingSymbolWithoutMutatingDocument() {
        let original = "# First\none\n## Child\ntwo\n# Second\nthree\n"
        let document = Document(content: original)
        document.language = .markdown
        let editor = EditorViewController()
        _ = editor.view
        editor.document = document
        let cursor = (original as NSString).range(of: "two").location
        editor.textView.setSelectedRange(NSRange(location: cursor, length: 0))

        XCTAssertTrue(editor.beginPartialOutlineEditing())
        XCTAssertEqual(editor.partialEditRange, NSRange(location: 12, length: 13))
        XCTAssertEqual(document.content, original)

        editor.endPartialOutlineEditing()
        XCTAssertNil(editor.partialEditRange)
        XCTAssertEqual(document.content, original)
    }
}
