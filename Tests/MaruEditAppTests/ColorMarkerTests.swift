import XCTest
@preconcurrency @testable import MaruEditApp

@preconcurrency @MainActor
final class ColorMarkerTests: XCTestCase {
    func testColorsToggleNavigateWrapAndMoveWithEdits() {
        let text = "a\nb\nc\n" as NSString
        let markers = ColorMarkerSet()
        XCTAssertTrue(markers.toggle(lineAt: 0, color: .red, in: text))
        XCTAssertTrue(markers.toggle(lineAt: 2, color: .blue, in: text))
        XCTAssertEqual(markers.next(after: 0), 2)
        XCTAssertEqual(markers.next(after: 2), 0)
        XCTAssertEqual(markers.previous(before: 2), 0)
        markers.applyEdit(range: NSRange(location: 0, length: 0), replacement: "x\n")
        XCTAssertEqual(Set(markers.markers.keys), [2, 4])
        XCTAssertFalse(markers.toggle(lineAt: 2, color: .red, in: "x\na\nb\nc\n" as NSString))
    }

    func testHighlightListIsSortedAndSupportsRemoval() {
        let markers = ColorMarkerSet()
        let text = "a\nb\nc" as NSString
        markers.toggle(lineAt: 4, color: .blue, in: text)
        markers.toggle(lineAt: 0, color: .red, in: text)
        XCTAssertEqual(markers.sortedMarkers.map(\.offset), [0, 4])
        XCTAssertEqual(markers.sortedMarkers.map(\.color), [.red, .blue])
        markers.remove(at: 0)
        XCTAssertEqual(markers.sortedMarkers.map(\.offset), [4])
    }

    func testEditorMarkerCommandsDoNotMutateText() {
        let editor = EditorViewController()
        _ = editor.view
        editor.document = Document(content: "a\nb\n")
        editor.setSelections([NSRange(location: 2, length: 0)], primaryRange: NSRange(location: 2, length: 0))
        editor.toggleMarker(.yellow)
        XCTAssertEqual(editor.document?.colorMarkers.markers[2], .yellow)
        XCTAssertEqual(editor.textView.string, "a\nb\n")
        editor.clearMarkers()
        XCTAssertTrue(editor.document?.colorMarkers.markers.isEmpty == true)
    }

    func testResultsPaneFormatsMarkerList() {
        let sidebar = SidebarViewController()
        _ = sidebar.view
        sidebar.updateMarkerResults([0: .red, 4: .blue], text: "one\ntwo\n")
        sidebar.showUtilityPane(.results)
        XCTAssertTrue(sidebar.markerResultTextForTesting.contains("Red · Ln 1: one"))
        XCTAssertTrue(sidebar.markerResultTextForTesting.contains("Blue · Ln 2: two"))
    }
}
