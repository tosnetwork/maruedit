import AppKit
import XCTest
@testable import MaruEditApp

@MainActor
final class VerticalWritingModeTests: XCTestCase {
    func testVerticalModeIsEditableUndoableAndRestoresSelections() {
        let editor = EditorViewController()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 400),
            styleMask: [.titled], backing: .buffered, defer: true)
        window.contentView = editor.view
        editor.document = Document(content: "縦書きの日本語\n第二列")
        editor.setSelections([NSRange(location: 3, length: 0)])

        editor.toggleVerticalLayout()
        XCTAssertEqual(editor.textView.layoutOrientation, .vertical)
        XCTAssertEqual(editor.selectionSet.primaryRange.location, 3)
        editor.textView.insertText("追", replacementRange: editor.textView.selectedRange())
        XCTAssertTrue(editor.textView.string.contains("追"))
        editor.textView.undoManager?.undo()
        XCTAssertEqual(editor.textView.string, "縦書きの日本語\n第二列")

        editor.toggleVerticalLayout()
        XCTAssertEqual(editor.textView.layoutOrientation, .horizontal)
    }
}
