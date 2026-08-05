import XCTest
import MaruEditCore
@preconcurrency @testable import MaruEditApp

@preconcurrency @MainActor
final class FoldingUITests: XCTestCase {
    func testCollapseAndExpandUseGlyphPropertiesWithoutChangingText() throws {
        let content = "# Heading\nbody\n# Next\nend"
        let document = Document(content: content, language: .markdown)
        let editor = EditorViewController()
        editor.document = document
        _ = editor.view
        editor.reloadCurrentDocument()

        let manager = try XCTUnwrap(editor.textView.layoutManager)
        let container = try XCTUnwrap(editor.textView.textContainer)
        manager.ensureLayout(for: container)
        let expandedHeight = manager.usedRect(for: container).height

        editor.collapseAllFolds()
        manager.ensureLayout(for: container)
        let collapsedHeight = manager.usedRect(for: container).height
        XCTAssertEqual(editor.collapsedFoldCountForTesting, 2)
        XCTAssertEqual(editor.textView.string, content)
        XCTAssertLessThan(collapsedHeight, expandedHeight)

        editor.expandAllFolds()
        XCTAssertEqual(editor.collapsedFoldCountForTesting, 0)
        XCTAssertEqual(editor.textView.string, content)
        XCTAssertFalse(document.isModified)
    }

    func testToggleFoldAtCursorChangesOnlyCurrentRegion() {
        let document = Document(content: "# One\na\n# Two\nb", language: .markdown)
        let editor = EditorViewController()
        editor.document = document
        _ = editor.view
        editor.reloadCurrentDocument()
        editor.textView.setSelectedRange(NSRange(location: 0, length: 0))
        editor.toggleFoldAtCursor()
        XCTAssertEqual(editor.collapsedFoldCountForTesting, 1)
    }
}
