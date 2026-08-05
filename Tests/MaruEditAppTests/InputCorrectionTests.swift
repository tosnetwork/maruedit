import AppKit
import XCTest
@testable import MaruEditApp

@MainActor
final class InputCorrectionTests: XCTestCase {
    func testCapsLockCorrectionTogglesSelectedCaseInOneEdit() {
        let editor = EditorViewController()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled], backing: .buffered, defer: true)
        window.contentView = editor.view
        editor.textView.string = "HELLO world"
        editor.setSelections([
            NSRange(location: 0, length: 5),
            NSRange(location: 6, length: 5),
        ])

        XCTAssertTrue(editor.correctCapsLockMistake())
        XCTAssertEqual(editor.textView.string, "hello WORLD")
        editor.textView.undoManager?.undo()
        XCTAssertEqual(editor.textView.string, "HELLO world")
    }

    func testCapsLockCorrectionUsesCurrentWordWithoutSelection() {
        let editor = EditorViewController()
        _ = editor.view
        editor.textView.string = "prefix MISTAKE suffix"
        editor.textView.setSelectedRange(NSRange(location: 10, length: 0))
        editor.setSelections([NSRange(location: 10, length: 0)])

        XCTAssertTrue(editor.correctCapsLockMistake())
        XCTAssertEqual(editor.textView.string, "prefix mistake suffix")
    }
}
