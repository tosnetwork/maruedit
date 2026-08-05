import AppKit
import XCTest
@testable import MaruEditApp

@MainActor
final class EditMarkTests: XCTestCase {
    func testEditsCreateGutterMarksThatNavigateWrapAndClearIndependentlyOfDirtyState() {
        let editor = EditorViewController()
        _ = editor.view
        let document = Document(content: "one\ntwo\nthree\n")
        editor.document = document

        editor.textView.insertText("X", replacementRange: NSRange(location: 4, length: 0))
        editor.textView.insertText("Y", replacementRange: NSRange(location: 9, length: 0))
        XCTAssertEqual(document.editMarks.sortedOffsets, [4, 9])
        XCTAssertTrue(document.isModified)

        editor.setSelections([NSRange(location: 0, length: 0)])
        editor.nextEditMark()
        XCTAssertEqual(editor.selectionSet.primaryRange.location, 4)
        editor.nextEditMark()
        XCTAssertEqual(editor.selectionSet.primaryRange.location, 9)
        editor.nextEditMark()
        XCTAssertEqual(editor.selectionSet.primaryRange.location, 4)
        editor.previousEditMark()
        XCTAssertEqual(editor.selectionSet.primaryRange.location, 9)

        editor.clearEditMarks()
        XCTAssertTrue(document.editMarks.offsets.isEmpty)
        XCTAssertTrue(document.isModified, "clearing edit marks must not mark the file saved")
    }

    func testAnchorsMoveWithEditsAndNormalizeToLineStarts() {
        let text = "aa\nbb\n" as NSString
        let marks = EditMarkSet()
        marks.recordEdit(range: NSRange(location: 4, length: 0), replacement: "x", in: text)
        XCTAssertEqual(marks.sortedOffsets, [3])
        marks.applyEdit(range: NSRange(location: 0, length: 0), replacement: "z\n")
        marks.normalize(in: "z\naa\nbxb\n" as NSString)
        XCTAssertEqual(marks.sortedOffsets, [5])
    }
}
