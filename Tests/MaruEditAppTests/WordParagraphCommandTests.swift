import AppKit
import XCTest
@preconcurrency @testable import MaruEditApp

@preconcurrency @MainActor
final class WordParagraphCommandTests: XCTestCase {
    private var window: NSWindow!
    private var controller: MainWindowController!

    override func setUp() {
        controller = MainWindowController()
        window = controller.window
        controller.prepareUITestDocument(
            content: "one two\n\nthree four", selections: [NSRange(location: 7, length: 0)])
        window.makeFirstResponder(controller.macroEditor.textView)
    }

    func testWordAndParagraphMovementCommands() {
        controller.moveWordLeft()
        XCTAssertLessThan(controller.macroEditor.textView.selectedRange().location, 7)
        controller.moveWordRight()
        XCTAssertGreaterThanOrEqual(controller.macroEditor.textView.selectedRange().location, 7)
        controller.moveToParagraphEnd()
        let paragraphEnd = controller.macroEditor.textView.selectedRange().location
        controller.moveToParagraphStart()
        XCTAssertLessThanOrEqual(controller.macroEditor.textView.selectedRange().location, paragraphEnd)
    }

    func testWordDeletionUsesNativeBoundaryAndUndo() {
        let original = controller.macroEditor.textView.string
        controller.deleteWordBackward()
        XCTAssertNotEqual(controller.macroEditor.textView.string, original)
        controller.macroEditor.textView.undoManager?.undo()
        XCTAssertEqual(controller.macroEditor.textView.string, original)
        controller.deleteWordForward()
        XCTAssertNotEqual(controller.macroEditor.textView.string, original)
    }
}
