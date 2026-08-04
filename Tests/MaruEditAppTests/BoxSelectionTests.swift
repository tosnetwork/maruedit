import AppKit
import XCTest
@testable import MaruEditApp

final class BoxSelectionTests: XCTestCase {
    private var windows: [NSWindow] = []

    override func tearDown() {
        windows.removeAll()
        super.tearDown()
    }

    private func editor(_ text: String) -> EditorViewController {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled], backing: .buffered, defer: true)
        let editor = EditorViewController()
        window.contentView = editor.view
        windows.append(window)
        editor.textView.string = text
        editor.textView.undoManager?.removeAllActions()
        return editor
    }

    func testVisualWidthHandlesTabsFullWidthAndCombiningCharacters() {
        XCTAssertEqual(BoxSelectionModel.visualWidth(of: "\tA", tabWidth: 4), 5)
        XCTAssertEqual(BoxSelectionModel.visualWidth(of: "日e\u{301}", tabWidth: 4), 3)
        XCTAssertEqual(BoxSelectionModel.visualWidth(of: "ａｂ", tabWidth: 4), 4)
    }

    func testRowsUseVisualColumnsAndVirtualSpaceOnShortLines() {
        let rows = BoxSelectionModel.rows(
            in: "abc\nx\n日本",
            anchor: TextCoordinate(line: 0, visualColumn: 2),
            current: TextCoordinate(line: 2, visualColumn: 4)
        )
        XCTAssertEqual(rows, [
            BoxSelectionRow(line: 0, range: NSRange(location: 2, length: 1), leadingVirtualSpaces: 0),
            BoxSelectionRow(line: 1, range: NSRange(location: 5, length: 0), leadingVirtualSpaces: 1),
            BoxSelectionRow(line: 2, range: NSRange(location: 7, length: 1), leadingVirtualSpaces: 0),
        ])
    }

    func testColumnCopyDeleteAndInsert() {
        let selectedEditor = editor("abc\nxyz")
        selectedEditor.beginColumnSelection(atUTF16Offset: 1)
        selectedEditor.updateColumnSelection(toUTF16Offset: 6)
        XCTAssertEqual(selectedEditor.copiedColumnText(), "b\ny")

        selectedEditor.multiEditForwardDelete()
        XCTAssertEqual(selectedEditor.textView.string, "ac\nxz")

        let virtual = editor("a\nbb")
        let rows = BoxSelectionModel.rows(
            in: virtual.textView.string,
            anchor: TextCoordinate(line: 0, visualColumn: 3),
            current: TextCoordinate(line: 1, visualColumn: 3))
        virtual.columnSelectionRows = rows
        virtual.setSelections(rows.map(\.range))
        virtual.isMultiEditActive = true
        virtual.multiEditInsert("Z")
        XCTAssertEqual(virtual.textView.string, "a  Z\nbb Z")
    }

    func testMultilinePasteMapsRowsAndSingleLineRepeats() {
        let mapped = editor("abc\nxyz")
        mapped.beginColumnSelection(atUTF16Offset: 1)
        mapped.updateColumnSelection(toUTF16Offset: 6)
        mapped.multiEditPaste("1\n2")
        XCTAssertEqual(mapped.textView.string, "a1c\nx2z")

        let repeated = editor("abc\nxyz")
        repeated.beginColumnSelection(atUTF16Offset: 1)
        repeated.updateColumnSelection(toUTF16Offset: 6)
        repeated.multiEditPaste("Q")
        XCTAssertEqual(repeated.textView.string, "aQc\nxQz")
    }

    func testEditorRemainsAccessibleAndColumnModeIsNoWrap() {
        let editor = editor("abc")
        XCTAssertEqual(editor.textView.accessibilityLabel(), "Editor")
        XCTAssertTrue(editor.textView.isHorizontallyResizable)
        XCTAssertFalse(editor.textView.textContainer?.widthTracksTextView ?? true)
    }
}
