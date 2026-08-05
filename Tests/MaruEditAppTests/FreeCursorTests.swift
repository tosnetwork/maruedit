import AppKit
import XCTest
@preconcurrency @testable import MaruEditApp

@MainActor
final class FreeCursorTests: XCTestCase {
    func testRightLeftAndTypingBeyondLineEndMaterializeSpaces() {
        let view = MaruTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
        view.string = "abc"
        view.freeCursorEnabled = true
        view.setSelectedRange(NSRange(location: 3, length: 0))
        view.moveRight(nil); view.moveRight(nil); view.moveRight(nil)
        XCTAssertEqual(view.virtualSpaceColumns, 3)
        view.moveLeft(nil)
        XCTAssertEqual(view.virtualSpaceColumns, 2)
        view.insertText("X", replacementRange: view.selectedRange())
        XCTAssertEqual(view.string, "abc  X")
        XCTAssertEqual(view.virtualSpaceColumns, 0)
    }

    func testVerticalMovementPreservesDesiredColumnAcrossShortLines() {
        let view = MaruTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
        view.string = "abcd\nx\nlonger"
        view.freeCursorEnabled = true
        view.setSelectedRange(NSRange(location: 4, length: 0))
        view.moveDown(nil)
        XCTAssertEqual(view.selectedRange().location, 6)
        XCTAssertEqual(view.virtualSpaceColumns, 3)
        view.moveDown(nil)
        XCTAssertEqual(view.selectedRange().location, 11)
        XCTAssertEqual(view.virtualSpaceColumns, 0)
        view.moveUp(nil)
        XCTAssertEqual(view.selectedRange().location, 6)
        XCTAssertEqual(view.virtualSpaceColumns, 3)
    }

    func testDisablingFreeCursorDropsVirtualPosition() {
        let view = MaruTextView(frame: .zero)
        view.string = "a"; view.freeCursorEnabled = true
        view.setSelectedRange(NSRange(location: 1, length: 0)); view.moveRight(nil)
        view.freeCursorEnabled = false
        XCTAssertEqual(view.virtualSpaceColumns, 0)
    }
}
