import AppKit
import MaruEditCore
import XCTest
@testable import MaruEditApp

final class StatusBarViewTests: XCTestCase {
    private final class Delegate: StatusBarViewDelegate {
        var controls: [StatusBarControl] = []
        func statusBar(
            _ statusBar: StatusBarView, didClick control: StatusBarControl, at point: NSPoint
        ) {
            controls.append(control)
        }
    }

    func testTransientMessageRestoresCursorText() {
        let status = StatusBarView(frame: NSRect(x: 0, y: 0, width: 600, height: 24))
        status.updateCursor(EditorCursorState(
            lineNumber: 4, displayColumn: 9, utf16Offset: 42,
            selectedCharacterCount: 0, selectedUTF16Length: 0, selectionRangeCount: 1))
        status.showTransientMessage("Chord: ctrl+k …", duration: 0.01)
        XCTAssertEqual(status.displayedLeadingText, "Chord: ctrl+k …")

        let restored = expectation(description: "cursor text restored")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) {
            XCTAssertEqual(status.displayedLeadingText, "Ln 4, Col 9")
            restored.fulfill()
        }
        wait(for: [restored], timeout: 1)
    }

    func testCursorSelectionAndFormatFieldsAreExplicit() {
        let status = StatusBarView(frame: NSRect(x: 0, y: 0, width: 900, height: 24))
        status.updateCursor(EditorCursorState(
            lineNumber: 2, displayColumn: 7, utf16Offset: 4,
            selectedCharacterCount: 9, selectedUTF16Length: 11, selectionRangeCount: 3))
        status.updateEncoding(.windows31J)
        status.updateByteOrderMark(false)
        status.updateLineEnding(.crlf)
        status.updateLanguage(.swift, profileName: "Swift")

        XCTAssertEqual(status.displayedLeadingText, "Ln 2, Col 7")
        XCTAssertEqual(status.displayedSelectionText, "Sel 9 (3 ranges)")
        XCTAssertEqual(status.displayedEncodingText, "Windows-31J (Shift-JIS)")
        XCTAssertEqual(status.displayedBOMText, "No BOM")
        XCTAssertEqual(status.displayedLineEndingText, "CRLF")
        XCTAssertEqual(status.displayedLanguageProfileText, "Swift · Swift")
    }

    func testEveryFormatFieldRoutesAsAClickableControl() {
        let status = StatusBarView(frame: NSRect(x: 0, y: 0, width: 900, height: 24))
        let delegate = Delegate()
        status.delegate = delegate
        status.layoutSubtreeIfNeeded()

        for control in StatusBarControl.allCases {
            XCTAssertNotNil(status.frame(for: control))
            status.activate(control)
        }

        XCTAssertEqual(delegate.controls.count, StatusBarControl.allCases.count)
    }
}

final class EditorCursorStateTests: XCTestCase {
    private final class Delegate: EditorViewControllerDelegate {
        var state: EditorCursorState?
        func editorTextDidChange(_ vc: EditorViewController) {}
        func editorCursorMoved(_ vc: EditorViewController, state: EditorCursorState) {
            self.state = state
        }
    }

    func testDisplayColumnIsNotUTF16OffsetAndSelectionCountsAllRanges() {
        let editor = EditorViewController()
        _ = editor.view
        editor.document = Document(content: "\t日e\u{301}\nnext")
        let delegate = Delegate()
        editor.delegate = delegate
        editor.setSelections([
            NSRange(location: 2, length: 2),
            NSRange(location: 7, length: 1),
        ], primaryRange: NSRange(location: 2, length: 2))
        editor.textViewDidChangeSelection(Notification(name: NSTextView.didChangeSelectionNotification))

        XCTAssertEqual(delegate.state, EditorCursorState(
            lineNumber: 1, displayColumn: 7, utf16Offset: 2,
            selectedCharacterCount: 2, selectedUTF16Length: 3, selectionRangeCount: 2))
    }
}
