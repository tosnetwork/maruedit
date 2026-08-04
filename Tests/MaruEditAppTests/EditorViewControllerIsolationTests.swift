import XCTest
@testable import MaruEditApp

/// Guards against the exact class of bug ROADMAP.md M1-06 exists to fix:
/// multi-cursor/edit-mode state that used to live in module-level
/// dictionaries keyed by `ObjectIdentifier`, which could — once
/// multi-window support arrives — let one window's multi-edit state leak
/// into or clobber another's. It's now a plain instance property, so
/// isolation holds by construction; this test exists as a concrete,
/// permanent regression guard for that invariant, not just documentation.
final class EditorViewControllerIsolationTests: XCTestCase {

    func testMultiEditStateIsIndependentBetweenTwoEditorInstances() {
        let editorA = EditorViewController()
        let editorB = EditorViewController()

        XCTAssertFalse(editorA.isMultiEditActive)
        XCTAssertFalse(editorB.isMultiEditActive)
        XCTAssertTrue(editorA.multiEditCursorRanges.isEmpty)
        XCTAssertTrue(editorB.multiEditCursorRanges.isEmpty)

        editorA.isMultiEditActive = true
        editorA.multiEditCursorRanges = [NSRange(location: 0, length: 3), NSRange(location: 10, length: 3)]

        XCTAssertTrue(editorA.isMultiEditActive)
        XCTAssertEqual(editorA.multiEditCursorRanges.count, 2)

        XCTAssertFalse(editorB.isMultiEditActive, "activating multi-edit on one editor must not affect another")
        XCTAssertTrue(editorB.multiEditCursorRanges.isEmpty, "cursor ranges must not leak between editor instances")
    }

    func testDeallocatingOneEditorDoesNotAffectAnother() {
        var editorA: EditorViewController? = EditorViewController()
        let editorB = EditorViewController()

        editorA?.isMultiEditActive = true
        editorA?.multiEditCursorRanges = [NSRange(location: 0, length: 1)]
        editorA = nil // deallocate — must not touch any global map editorB could be keyed into

        XCTAssertFalse(editorB.isMultiEditActive)
        XCTAssertTrue(editorB.multiEditCursorRanges.isEmpty)
    }
}
