import XCTest
@preconcurrency @testable import MaruEditApp

@preconcurrency @MainActor
final class EditorSplitTests: XCTestCase {
    func testVerticalAndHorizontalSplitShareTextButOwnSelections() throws {
        let controller = MainWindowController()
        controller.prepareUITestDocument(content: "alpha\nbeta", selections: [NSRange(location: 0, length: 0)])
        controller.showEditorSplit(.vertical)
        let secondary = try XCTUnwrap(controller.secondaryEditorForTesting)
        XCTAssertTrue(controller.isEditorSplitForTesting)
        XCTAssertTrue(controller.editorSplitIsVerticalForTesting)
        XCTAssertTrue(secondary.document === controller.macroEditor.document)

        secondary.setSelections([NSRange(location: 6, length: 0)], primaryRange: NSRange(location: 6, length: 0))
        XCTAssertEqual(controller.macroEditor.selectionSet.primaryRange.location, 0)
        secondary.textView.insertText("X", replacementRange: secondary.textView.selectedRange())
        XCTAssertEqual(controller.macroEditor.textView.string, "alpha\nXbeta")

        controller.showEditorSplit(.horizontal)
        XCTAssertFalse(controller.editorSplitIsVerticalForTesting)
        controller.closeEditorSplit()
        XCTAssertFalse(controller.isEditorSplitForTesting)
    }

    func testLinkedScrollingIsExplicitlyOptional() {
        let controller = MainWindowController()
        controller.showEditorSplit(.vertical)
        XCTAssertFalse(controller.isLinkedEditorScrollingForTesting)
        controller.toggleLinkedEditorScrolling()
        XCTAssertTrue(controller.isLinkedEditorScrollingForTesting)
    }
}
