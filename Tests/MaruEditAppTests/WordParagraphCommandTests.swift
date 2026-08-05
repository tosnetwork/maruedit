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

    func testWholeWordAndLineClipboardCommands() {
        controller.prepareUITestDocument(content: "alpha beta\ngamma\n", selections: [NSRange(location: 7, length: 0)])
        controller.copyCurrentWord()
        XCTAssertEqual(NSPasteboard.general.string(forType: .string), "beta")
        controller.cutCurrentWord()
        XCTAssertEqual(controller.macroEditor.textView.string, "alpha \ngamma\n")
        controller.macroEditor.textView.undoManager?.undo()
        XCTAssertEqual(controller.macroEditor.textView.string, "alpha beta\ngamma\n")

        controller.macroEditor.setSelections([NSRange(location: 1, length: 0)])
        controller.cutCurrentLine()
        XCTAssertEqual(NSPasteboard.general.string(forType: .string), "alpha beta\n")
        XCTAssertEqual(controller.macroEditor.textView.string, "gamma\n")
    }

    func testCutToLineEndAndClearUndoBuffer() {
        controller.prepareUITestDocument(content: "alpha beta\ngamma", selections: [NSRange(location: 6, length: 0)])
        controller.cutToLineEnd()
        XCTAssertEqual(NSPasteboard.general.string(forType: .string), "beta")
        XCTAssertEqual(controller.macroEditor.textView.string, "alpha \ngamma")
        XCTAssertTrue(controller.macroEditor.textView.undoManager?.canUndo == true)
        controller.clearUndoBuffer()
        XCTAssertFalse(controller.macroEditor.textView.undoManager?.canUndo == true)
    }
}
