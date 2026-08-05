import XCTest
@preconcurrency @testable import MaruEditApp

@preconcurrency @MainActor
final class ColorMarkerTests: XCTestCase {
    override func setUp() {
        super.setUp()
        UserDefaults.standard.set(AppLanguage.english.rawValue, forKey: AppLocalization.defaultsKey)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: AppLocalization.defaultsKey)
        super.tearDown()
    }
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

    func testTemporaryRangeMarkersApplyNavigateSelectRemoveAndClear() {
        let editor = EditorViewController()
        _ = editor.view
        editor.document = Document(content: "alpha beta gamma")
        let alpha = NSRange(location: 0, length: 5)
        let gamma = NSRange(location: 11, length: 5)
        editor.setSelections([alpha, gamma], primaryRange: alpha)
        editor.addTemporaryColorMarkers(.green)
        XCTAssertEqual(editor.temporaryColorMarkers, [
            .init(range: alpha, color: .green), .init(range: gamma, color: .green),
        ])

        editor.setSelections([NSRange(location: 6, length: 0)], primaryRange: NSRange(location: 6, length: 0))
        editor.nextTemporaryColorMarker()
        XCTAssertEqual(editor.selectionSet.primaryRange, gamma)
        editor.nextTemporaryColorMarker()
        XCTAssertEqual(editor.selectionSet.primaryRange, alpha)
        editor.selectTemporaryColorMarkers()
        XCTAssertEqual(editor.selectionSet.ranges, [alpha, gamma])

        editor.setSelections([alpha], primaryRange: alpha)
        editor.removeTemporaryColorMarkersInSelection()
        XCTAssertEqual(editor.temporaryColorMarkers.map(\.range), [gamma])
        editor.applyTemporaryColorMarkerEdit(
            range: NSRange(location: 0, length: 0), replacement: "prefix ")
        XCTAssertEqual(editor.temporaryColorMarkers.map(\.range), [NSRange(location: 18, length: 5)])
        editor.clearTemporaryColorMarkers()
        XCTAssertTrue(editor.temporaryColorMarkers.isEmpty)
        XCTAssertEqual(editor.textView.string, "alpha beta gamma")
    }

    func testHighlightedLineNavigationAndAreaSelectionUseLanguageRules() {
        let editor = EditorViewController()
        _ = editor.view
        let document = Document(content: "plain\nfunc foo() {}\nplain\nlet value = 1\n")
        document.language = .swift
        editor.document = document
        editor.setSelections([NSRange(location: 0, length: 0)], primaryRange: NSRange(location: 0, length: 0))

        editor.nextHighlightedLine()
        XCTAssertEqual(editor.selectionSet.primaryRange.location, 6)
        editor.nextHighlightedLine()
        XCTAssertEqual(editor.selectionSet.primaryRange.location, 26)
        editor.previousHighlightedLine()
        XCTAssertEqual(editor.selectionSet.primaryRange.location, 6)
        editor.selectHighlightedLineArea()
        XCTAssertEqual(editor.selectionSet.primaryRange, NSRange(location: 6, length: 14))
    }
}
