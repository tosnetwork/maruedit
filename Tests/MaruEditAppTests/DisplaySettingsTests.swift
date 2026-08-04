import AppKit
import MaruEditCore
import XCTest
@testable import MaruEditApp

final class DisplaySettingsTests: XCTestCase {
    private final class Delegate: EditorViewControllerDelegate {
        var chosenFont: NSFont?
        func editorTextDidChange(_ vc: EditorViewController) {}
        func editorCursorMoved(_ vc: EditorViewController, state: EditorCursorState) {}
        func editorDidChooseFont(_ vc: EditorViewController, font: NSFont) { chosenFont = font }
    }

    func testInvisibleMarkersToggleIndependently() {
        let spaces = InvisibleCharacterOptions(spaces: true)
        XCTAssertEqual(MaruTextView.marker(forUTF16CodeUnit: 0x20, options: spaces), "·")
        XCTAssertNil(MaruTextView.marker(forUTF16CodeUnit: 0x09, options: spaces))
        XCTAssertNil(MaruTextView.marker(forUTF16CodeUnit: 0x0A, options: spaces))
        XCTAssertNil(MaruTextView.marker(forUTF16CodeUnit: 0x3000, options: spaces))

        let all = InvisibleCharacterOptions(
            spaces: true, tabs: true, lineEndings: true, fullWidthSpaces: true)
        XCTAssertEqual(MaruTextView.marker(forUTF16CodeUnit: 0x09, options: all), "→")
        XCTAssertEqual(MaruTextView.marker(forUTF16CodeUnit: 0x0A, options: all), "¶")
        XCTAssertEqual(MaruTextView.marker(forUTF16CodeUnit: 0x3000, options: all), "□")
    }

    func testInvisibleRenderingDegradesForLargeFiles() {
        let view = MaruTextView()
        view.string = String(repeating: " ", count: MaruTextView.invisibleMarkerLargeFileThreshold + 1)
        view.invisibleCharacters = InvisibleCharacterOptions(spaces: true)
        XCTAssertTrue(view.isInvisibleRenderingSuppressedForLargeFile)
        XCTAssertEqual(view.string.count, MaruTextView.invisibleMarkerLargeFileThreshold + 1)
    }

    func testDocumentWrapAndTabWidthOverrideProfileWithoutChangingText() throws {
        let editor = EditorViewController()
        _ = editor.view
        let document = Document(content: "a\tb")
        document.fileTypeProfile = FileTypeProfile(
            id: "test", name: "Test", settings: FileTypeSettings(tabWidth: 8, wrapLines: false))
        editor.document = document
        XCTAssertFalse(editor.effectiveWrapLines)
        XCTAssertEqual(editor.effectiveTabWidth, 8)

        editor.toggleWrapLines()
        editor.setTabWidth(2)

        XCTAssertTrue(editor.effectiveWrapLines)
        XCTAssertEqual(editor.effectiveTabWidth, 2)
        XCTAssertEqual(editor.textView.string, "a\tb")
        XCTAssertTrue(editor.textView.textContainer?.widthTracksTextView == true)
        let paragraph = try XCTUnwrap(editor.textView.defaultParagraphStyle)
        let space = " ".size(withAttributes: [.font: try XCTUnwrap(editor.textView.font)]).width
        XCTAssertEqual(paragraph.defaultTabInterval, space * 2, accuracy: 0.01)
    }

    func testDefaultFontIsNativeMonospacedFont() {
        let editor = EditorViewController()
        _ = editor.view
        XCTAssertTrue(editor.currentEditorFont.fontDescriptor.symbolicTraits.contains(.monoSpace))
    }

    func testSystemFontPanelSelectionAppliesAndNotifiesWithoutChangingText() throws {
        let editor = EditorViewController()
        _ = editor.view
        let delegate = Delegate()
        editor.delegate = delegate
        let font = try XCTUnwrap(NSFont(name: "Menlo", size: 18))

        XCTAssertTrue(editor.textView is MaruTextView,
                      "the first responder must forward changeFont from NSFontPanel")
        editor.applyEditorFont(font)

        XCTAssertEqual(delegate.chosenFont?.fontName, font.fontName)
        XCTAssertEqual(delegate.chosenFont?.pointSize, 18)
        XCTAssertEqual(editor.currentEditorFont.fontName, font.fontName)
        XCTAssertEqual(editor.textView.string, "")
        delegate.chosenFont = nil
        editor.textView.changeFont(NSFontManager.shared)
        XCTAssertNotNil(delegate.chosenFont, "changeFont must route through the editor delegate")
    }

    func testHighContrastChangesPresentationWithoutChangingText() {
        let editor = EditorViewController()
        _ = editor.view
        editor.document = Document(content: "let value = 1")
        let original = editor.textView.string

        editor.applyHighContrast(true)

        XCTAssertTrue(editor.isHighContrast)
        XCTAssertEqual(editor.textView.backgroundColor, .black)
        XCTAssertEqual(editor.textView.textColor, .white)
        XCTAssertTrue((editor.textView as? MaruTextView)?.usesHighContrastMarkers == true)
        XCTAssertEqual(editor.textView.string, original)
    }

    func testInvisibleCommandMutatesOnlyRequestedPersistedPreference() {
        let suite = "DisplaySettingsTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = PreferencesStore(defaults: defaults)
        let coordinator = AppCoordinator(preferencesStore: store)

        coordinator.toggleInvisible(\.tabs)

        XCTAssertTrue(coordinator.preferences.invisibleCharacters.tabs)
        XCTAssertFalse(coordinator.preferences.invisibleCharacters.spaces)
        XCTAssertTrue(store.load().invisibleCharacters.tabs)
    }

}
