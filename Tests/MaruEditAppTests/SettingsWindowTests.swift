import AppKit
import XCTest
@testable import MaruEditApp
import MaruEditCore

final class SettingsWindowTests: XCTestCase {
    func testLocalizationCoversEnglishJapaneseAndSimplifiedChinese() {
        XCTAssertEqual(SettingsLocalization.text("settings", language: .english), "Settings")
        XCTAssertEqual(SettingsLocalization.text("settings", language: .japanese), "設定")
        XCTAssertEqual(SettingsLocalization.text("settings", language: .simplifiedChinese), "设置")
        for group in SettingsWindowController.Group.allCases {
            XCTAssertNotEqual(SettingsLocalization.text(group.rawValue, language: .japanese), group.rawValue)
            XCTAssertNotEqual(SettingsLocalization.text(group.rawValue, language: .simplifiedChinese), group.rawValue)
        }
    }

    func testSettingsSearchFiltersGroups() {
        let controller = SettingsWindowController(preferences: .defaults) { _ in }
        controller.searchForTesting(SettingsLocalization.text("appearance"))
        XCTAssertEqual(controller.visibleGroups, [.appearance])
        controller.searchForTesting("")
        XCTAssertEqual(controller.visibleGroups, SettingsWindowController.Group.allCases)
    }

    func testRestoreDefaultsAffectsOnlySelectedGroupAndNotifies() {
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

    func testEditorPreferencesApplyImmediatelyWithoutChangingText() {
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

    func testFileTypeProfileOverridesGlobalTabWidthAndWrapping() throws {
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

    func testSearchAndControlsHaveAccessibilityLabels() throws {
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

    private func descendants(of view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + descendants(of: $0) }
    }
}
