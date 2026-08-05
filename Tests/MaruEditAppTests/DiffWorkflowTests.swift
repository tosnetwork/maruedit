import XCTest
@preconcurrency @testable import MaruEditApp

@preconcurrency @MainActor
final class DiffWorkflowTests: XCTestCase {
    func testCompareNavigatesWrapsMergesAndUndoRestoresText() throws {
        let controller = MainWindowController()
        controller.prepareUITestDocument(
            content: "alpha\nbeta\ngamma\ndelta\n",
            selections: [NSRange(location: 0, length: 0)])
        controller.newDocument()
        controller.prepareUITestDocument(
            content: "alpha\nBETA\ngamma\nDELTA\n",
            selections: [NSRange(location: 0, length: 0)])

        controller.compareWithNextDocument()
        XCTAssertTrue(controller.isComparingDocumentsForTesting)
        XCTAssertEqual(controller.diffHunkCountForTesting, 2)
        XCTAssertFalse(try XCTUnwrap(controller.secondaryEditorForTesting).textView.isEditable)

        controller.nextDifference()
        XCTAssertEqual(controller.currentDiffIndexForTesting, 1)
        controller.nextDifference()
        XCTAssertEqual(controller.currentDiffIndexForTesting, 0)
        controller.previousDifference()
        XCTAssertEqual(controller.currentDiffIndexForTesting, 1)

        let beforeMerge = controller.macroEditor.textView.string
        controller.mergeCurrentDifferenceFromRight()
        XCTAssertEqual(controller.diffHunkCountForTesting, 1)
        XCTAssertNotEqual(controller.macroEditor.textView.string, beforeMerge)
        controller.macroEditor.textView.undoManager?.undo()
        XCTAssertEqual(controller.macroEditor.textView.string, beforeMerge)

        controller.closeEditorSplit()
        controller.showEditorSplit(.horizontal)
        XCTAssertTrue(try XCTUnwrap(controller.secondaryEditorForTesting).textView.isEditable)
    }

    func testCompareRequiresTwoDocuments() {
        let controller = MainWindowController()
        controller.compareWithNextDocument()
        XCTAssertFalse(controller.isComparingDocumentsForTesting)
        XCTAssertFalse(controller.isEditorSplitForTesting)
    }
}
