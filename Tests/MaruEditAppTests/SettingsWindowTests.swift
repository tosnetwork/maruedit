import AppKit
import XCTest
@preconcurrency @testable import MaruEditApp
import MaruEditCore


@preconcurrency @MainActor
final class SettingsWindowTests: XCTestCase {
    func testDirectEntryCanSelectFilesAndKeyBindingGroups() async {
        let controller = SettingsWindowController(preferences: .defaults) { _ in }
        controller.show(group: .files)
        XCTAssertEqual(controller.selectedGroupForTesting, .files)
        controller.show(group: .keyBindings)
        XCTAssertEqual(controller.selectedGroupForTesting, .keyBindings)
    }
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
        controller.setLevelForTesting(.advanced)
        XCTAssertEqual(controller.visibleGroups, SettingsWindowController.Group.allCases)
    }

    func testWorkspaceStyleAppliesImmediatelyAndDefaultsToClassic() async {
        var received: Preferences?
        let controller = SettingsWindowController(preferences: .defaults) { received = $0 }
        XCTAssertEqual(controller.currentPreferences.workspaceStyle, .classic)
        controller.setWorkspaceForTesting(.modern)
        XCTAssertEqual(received?.workspaceStyle, .modern)
        XCTAssertEqual(received?.theme, .monokai)
        controller.restoreForTesting()
        XCTAssertEqual(received?.workspaceStyle, .classic)
        XCTAssertEqual(received?.theme, .classicLight)
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

    func testClassicChromeVisibilityAppliesImmediately() async {
        var received: Preferences?
        let controller = SettingsWindowController(preferences: .defaults) { received = $0 }
        let options = ClassicChromeOptions(
            showHeading: false, showRuler: true, showCommandStrip: false)
        controller.setClassicChromeForTesting(options)
        XCTAssertEqual(received?.classicChrome, options)
    }

    func testWrapModeAndColumnApplyImmediatelyAndClamp() async {
        var received: Preferences?
        let controller = SettingsWindowController(preferences: .defaults) { received = $0 }
        controller.setWrappingForTesting(.fixed, column: 120)
        XCTAssertEqual(received?.wrapMode, .fixed)
        XCTAssertEqual(received?.wrapColumn, 120)
        XCTAssertEqual(received?.wrapLines, true)
        controller.setWrappingForTesting(.none, column: 9)
        XCTAssertEqual(received?.wrapMode, WrapMode.none)
        XCTAssertEqual(received?.wrapColumn, 20)
        XCTAssertEqual(received?.wrapLines, false)
    }

    func testFileTypeProfileCanSetFixedWrapWidth() async {
        let editor = EditorViewController(); _ = editor.view
        let document = Document(content: String(repeating: "x", count: 200))
        document.fileTypeProfile = FileTypeProfile(
            id: "fixed", name: "Fixed", settings: FileTypeSettings(
                wrapLines: true, wrapMode: .fixed, wrapColumn: 72))
        editor.document = document
        editor.applyPreferences(.defaults)
        XCTAssertEqual(editor.effectiveWrapMode, .fixed)
        XCTAssertEqual(editor.effectiveWrapColumn, 72)
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
        XCTAssertEqual(editor.effectiveWrapMode, .fixed)
        XCTAssertTrue(editor.textView.textContainer?.widthTracksTextView == false)
        let cell = "0".size(withAttributes: [.font: try! XCTUnwrap(editor.textView.font)]).width
        XCTAssertEqual(editor.textView.textContainer?.containerSize.width ?? 0,
                       cell * 160 + (editor.textView.textContainer?.lineFragmentPadding ?? 0) * 2,
                       accuracy: 0.1)
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
        XCTAssertEqual(editor.effectiveWrapMode, .window)
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

    func testBasicAdvancedLevelsAndPerSectionTransfer() async throws {
        var source = Preferences.defaults
        source.tabWidth = 8
        source.fontSize = 21
        let exporter = SettingsWindowController(preferences: source) { _ in }
        XCTAssertFalse(exporter.visibleGroups.contains(.advanced))
        exporter.setLevelForTesting(.advanced)
        XCTAssertTrue(exporter.visibleGroups.contains(.advanced))

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("MaruEdit-section-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try exporter.exportSection(.editor, to: url)

        var target = Preferences.defaults
        target.fontSize = 17
        var received: Preferences?
        let importer = SettingsWindowController(preferences: target) { received = $0 }
        try importer.importSection(.editor, from: url)
        XCTAssertEqual(received?.tabWidth, 8)
        XCTAssertEqual(received?.fontSize, 17, "section import must not overwrite Appearance")
        XCTAssertThrowsError(try importer.importSection(.appearance, from: url))
    }

    func testCoordinatorSettingsTransferRoundTripsPersistsAndRestores() throws {
        let suite = "CoordinatorSettingsTransfer-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = PreferencesStore(defaults: defaults)
        let coordinator = AppCoordinator(preferencesStore: store)
        _ = coordinator.commandRegistry.execute(.otherToggleFreeCursor, context: CommandContext(coordinator: coordinator))
        XCTAssertTrue(coordinator.preferences.freeCursorEnabled)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(suite).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try coordinator.exportSettings(to: url)
        coordinator.restoreDefaultSettings()
        XCTAssertFalse(coordinator.preferences.freeCursorEnabled)
        try coordinator.importSettings(from: url)
        XCTAssertTrue(coordinator.preferences.freeCursorEnabled)
        XCTAssertTrue(store.load().freeCursorEnabled)
    }

    func testJapaneseDictionaryCommandUsesOfficialMacOSNativeWorkflow() {
        let coordinator = AppCoordinator()
        var opened: URL?
        coordinator.openDocumentationURL = { opened = $0 }
        coordinator.confirmOnlineHelpAccess = { _, _ in true }
        XCTAssertTrue(coordinator.commandRegistry.execute(
            .otherJapaneseUserDictionary, context: CommandContext(coordinator: coordinator)))
        XCTAssertEqual(opened?.host, "support.apple.com")
        XCTAssertTrue(opened?.path.contains("japanese-input-method") == true)
    }

    private func descendants(of view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + descendants(of: $0) }
    }
}
