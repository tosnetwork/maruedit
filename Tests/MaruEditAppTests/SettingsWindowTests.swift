import AppKit
import XCTest
@preconcurrency @testable import MaruEditApp
import MaruEditCore


@preconcurrency @MainActor
final class SettingsWindowTests: XCTestCase {
    func testLocalizationCoversEnglishJapaneseAndSimplifiedChinese() async {
        XCTAssertEqual(SettingsLocalization.text("settings", language: .english), "Settings")
        XCTAssertEqual(SettingsLocalization.text("settings", language: .japanese), "設定")
        XCTAssertEqual(SettingsLocalization.text("settings", language: .simplifiedChinese), "设置")
        for group in SettingsWindowController.Group.allCases {
            XCTAssertNotEqual(SettingsLocalization.text(group.rawValue, language: .japanese), group.rawValue)
            XCTAssertNotEqual(SettingsLocalization.text(group.rawValue, language: .simplifiedChinese), group.rawValue)
        }
    }

    func testSettingsSearchFiltersGroups() async {
        let controller = SettingsWindowController(preferences: .defaults) { _ in }
        controller.searchForTesting(SettingsLocalization.text("appearance"))
        XCTAssertEqual(controller.visibleGroups, [.appearance])
        controller.searchForTesting("")
        XCTAssertEqual(controller.visibleGroups, SettingsWindowController.Group.allCases)
    }

    func testWorkspaceStyleAppliesImmediatelyAndDefaultsToClassic() async {
        var received: Preferences?
        let controller = SettingsWindowController(preferences: .defaults) { received = $0 }
        XCTAssertEqual(controller.currentPreferences.workspaceStyle, .classic)
        controller.setWorkspaceForTesting(.modern)
        XCTAssertEqual(received?.workspaceStyle, .modern)
        controller.restoreForTesting()
        XCTAssertEqual(received?.workspaceStyle, .classic)
    }

    func testRestoreDefaultsAffectsOnlySelectedGroupAndNotifies() async {
        var custom = Preferences.defaults
        custom.fontSize = 22
        custom.tabWidth = 8
        custom.wrapLines = true
        var received: Preferences?
        let controller = SettingsWindowController(preferences: custom) { received = $0 }
        controller.selectForTesting(.editor)
        controller.restoreForTesting()
        XCTAssertEqual(received?.tabWidth, Preferences.defaults.tabWidth)
        XCTAssertEqual(received?.wrapLines, Preferences.defaults.wrapLines)
        XCTAssertEqual(received?.fontSize, 22, "restoring Editor must not reset Appearance")
    }

    func testEditorPreferencesApplyImmediatelyWithoutChangingText() async {
        let editor = EditorViewController()
        _ = editor.view
        editor.textView.string = "let value = 1"
        var preferences = Preferences.defaults
        preferences.fontSize = 18
        preferences.tabWidth = 2
        preferences.wrapLines = true
        preferences.showLineNumbers = false
        editor.applyPreferences(preferences)

        XCTAssertEqual(editor.textView.string, "let value = 1")
        XCTAssertEqual(editor.textView.font?.pointSize, 18)
        XCTAssertTrue(editor.textView.textContainer?.widthTracksTextView == true)
        XCTAssertTrue(editor.areLineNumbersHidden)
        XCTAssertEqual(editor.appliedPreferences, preferences)
    }

    func testFileTypeProfileOverridesGlobalTabWidthAndWrapping() async throws {
        let editor = EditorViewController()
        _ = editor.view
        let document = Document(content: "a\tb")
        document.fileTypeProfile = FileTypeProfile(
            id: "user.profile", name: "Profile", extensions: ["profile"],
            settings: FileTypeSettings(tabWidth: 7, wrapLines: true))
        editor.document = document
        var preferences = Preferences.defaults
        preferences.tabWidth = 2
        preferences.wrapLines = false
        editor.applyPreferences(preferences)

        XCTAssertTrue(editor.textView.textContainer?.widthTracksTextView == true)
        let paragraph = try XCTUnwrap(editor.textView.defaultParagraphStyle)
        let spaceWidth = " ".size(withAttributes: [.font: try XCTUnwrap(editor.textView.font)]).width
        XCTAssertEqual(paragraph.defaultTabInterval, spaceWidth * 7, accuracy: 0.01)
        XCTAssertEqual(editor.appliedPreferences, preferences,
                       "the persisted global preference must remain unchanged")
    }

    func testSearchAndControlsHaveAccessibilityLabels() async throws {
        let controller = SettingsWindowController(preferences: .defaults) { _ in }
        let root = try XCTUnwrap(controller.window?.contentView)
        let views = descendants(of: root)
        let search = try XCTUnwrap(views.compactMap { $0 as? NSSearchField }.first)
        XCTAssertFalse((search.accessibilityLabel() ?? "").isEmpty)
        let groupButtons = views.compactMap { $0 as? NSButton }
            .filter { $0.identifier?.rawValue.hasPrefix("settings.group.") == true }
        XCTAssertEqual(groupButtons.count, SettingsWindowController.Group.allCases.count)
        XCTAssertTrue(groupButtons.allSatisfy { !($0.accessibilityLabel() ?? "").isEmpty })
    }

    func testSettingsExportImportAndRestoreAll() async throws {
        var original = Preferences.defaults
        original.fontSize = 19
        original.invisibleCharacters.tabs = true
        var received: Preferences?
        let controller = SettingsWindowController(preferences: original) { received = $0 }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("SettingsWindowTests-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        try controller.exportSettings(to: url)
        controller.restoreAllForTesting()
        XCTAssertEqual(received, .defaults)
        try controller.importSettings(from: url)
        XCTAssertEqual(received, original)
        XCTAssertEqual(controller.currentPreferences, original)
    }

    private func descendants(of view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + descendants(of: $0) }
    }
}
