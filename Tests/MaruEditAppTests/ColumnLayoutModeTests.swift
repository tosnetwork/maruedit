import AppKit
import XCTest
@testable import MaruEditApp

@MainActor
final class ColumnLayoutModeTests: XCTestCase {
    func testColumnModeFlowsSharedDocumentThroughOrderedTextContainers() {
        let editor = EditorViewController()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 320),
            styleMask: [.titled], backing: .buffered, defer: true)
        window.contentView = editor.view
        editor.document = Document(content: String(repeating: "continuous column text ", count: 500))

        editor.toggleColumnLayout()

        XCTAssertTrue(editor.isColumnLayout)
        XCTAssertGreaterThanOrEqual(editor.columnCountForTesting, 2)
        let manager = try! XCTUnwrap(editor.textView.layoutManager)
        XCTAssertEqual(manager.textContainers.count, editor.columnCountForTesting)
        manager.ensureLayout(for: manager.textContainers[1])
        let first = manager.glyphRange(for: manager.textContainers[0])
        let second = manager.glyphRange(for: manager.textContainers[1])
        XCTAssertGreaterThan(first.length, 0)
        XCTAssertGreaterThan(second.length, 0)
        XCTAssertEqual(second.location, NSMaxRange(first))

        editor.toggleColumnLayout()
        XCTAssertFalse(editor.isColumnLayout)
        XCTAssertEqual(manager.textContainers.count, 1)
        XCTAssertTrue(editor.scrollView.documentView === editor.textView)
    }

    func testVerticalAndColumnModesAreMutuallyExclusive() {
        let editor = EditorViewController()
        _ = editor.view
        editor.document = Document(content: "日本語\ntext")
        editor.toggleVerticalLayout()
        XCTAssertTrue(editor.isVerticalLayout)
        editor.toggleColumnLayout()
        XCTAssertFalse(editor.isVerticalLayout)
        XCTAssertTrue(editor.isColumnLayout)
        editor.toggleVerticalLayout()
        XCTAssertFalse(editor.isColumnLayout)
        XCTAssertTrue(editor.isVerticalLayout)
    }
}
