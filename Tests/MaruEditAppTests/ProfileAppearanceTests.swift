import XCTest
import MaruEditCore
@preconcurrency @testable import MaruEditApp

@preconcurrency @MainActor
final class ProfileAppearanceTests: XCTestCase {
    func testProfileFontColorsAndFoldingApplyWithoutChangingText() throws {
        let editor = EditorViewController()
        _ = editor.view
        let document = Document(content: "func one() {\n  print(1)\n}\n")
        document.fileTypeProfile = FileTypeProfile(
            id: "visual", name: "Visual", settings: FileTypeSettings(
                syntax: .swift,
                appearance: ProfileAppearanceSettings(
                    fontName: "Menlo", fontSize: 19,
                    foregroundHex: "#112233", backgroundHex: "#F0E0D0",
                    selectionHex: "#ABCDEF"),
                foldingEnabled: false))
        editor.document = document
        editor.applyPreferences(.defaults)

        XCTAssertEqual(editor.currentEditorFont.pointSize, 19)
        let red = try XCTUnwrap(editor.textView.backgroundColor.usingColorSpace(.deviceRGB)?.redComponent)
        XCTAssertEqual(red, CGFloat(240.0 / 255), accuracy: 0.001)
        XCTAssertEqual(editor.foldRegionCountForTesting, 0)
        XCTAssertEqual(editor.textView.string, document.content)
    }
}
