import XCTest
import MaruEditCore
@preconcurrency @testable import MaruEditApp

@preconcurrency @MainActor
final class CompletionAndSpellingTests: XCTestCase {
    func testEditorCompletionUsesCurrentDocumentAndProfileRanking() {
        let editor = EditorViewController()
        _ = editor.view
        let document = Document(content: "apple apricot apple application ap")
        document.fileTypeProfile = profile(completion: CompletionSettings(ranking: .frequency))
        editor.document = document
        let range = NSRange(location: 32, length: 2)
        let words = editor.textView(
            editor.textView, completions: [], forPartialWordRange: range,
            indexOfSelectedItem: nil)
        XCTAssertEqual(words, ["apple", "application", "apricot"])
    }

    func testTooltipAndStatusPresentationAndProfileSpelling() {
        let editor = EditorViewController()
        let delegate = CompletionDelegate()
        editor.delegate = delegate
        _ = editor.view
        let document = Document(content: "completion complete com")
        document.fileTypeProfile = profile(
            completion: CompletionSettings(presentation: .tooltip),
            spelling: SpellingSettings(enabled: true, automaticCorrection: true))
        editor.document = document
        editor.setSelections([NSRange(location: 23, length: 0)], primaryRange: NSRange(location: 23, length: 0))
        editor.applyPreferences(.defaults)
        editor.showCompletions()
        XCTAssertNotNil(editor.textView.toolTip)
        XCTAssertTrue(editor.textView.isContinuousSpellCheckingEnabled)
        XCTAssertTrue(editor.textView.isAutomaticSpellingCorrectionEnabled)

        document.fileTypeProfile?.settings.completion?.presentation = .status
        editor.showCompletions()
        XCTAssertTrue(delegate.message?.contains("complete") == true)
    }

    private func profile(
        completion: CompletionSettings, spelling: SpellingSettings? = nil
    ) -> FileTypeProfile {
        FileTypeProfile(
            id: "test", name: "Test",
            settings: FileTypeSettings(completion: completion, spelling: spelling))
    }
}

@MainActor
private final class CompletionDelegate: EditorViewControllerDelegate {
    var message: String?
    func editorTextDidChange(_ vc: EditorViewController) {}
    func editorCursorMoved(_ vc: EditorViewController, state: EditorCursorState) {}
    func editorCompletionMessage(_ vc: EditorViewController, message: String) { self.message = message }
}
