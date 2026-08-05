import XCTest
import MaruEditCore
@preconcurrency @testable import MaruEditApp

@preconcurrency @MainActor
final class ClassicWorkspaceTests: XCTestCase {
    func testClassicIsDefaultAndCanSwitchToModernWithoutChangingDocument() async {
        let controller = MainWindowController()
        controller.macroEditor.textView.string = "classic content"

        controller.applyPreferences(.defaults)
        XCTAssertTrue(controller.isClassicWorkspace)
        XCTAssertTrue(controller.isClassicChromeVisibleForTesting)
        XCTAssertEqual(controller.classicHeadingForTesting, "Untitled")

        var modern = Preferences.defaults
        modern.workspaceStyle = .modern
        controller.applyPreferences(modern)
        XCTAssertFalse(controller.isClassicWorkspace)
        XCTAssertFalse(controller.isClassicChromeVisibleForTesting)
        XCTAssertEqual(controller.macroEditor.textView.string, "classic content")
    }

    func testClassicChromeAndStatusExposeAccessibilityInformation() async {
        let controller = MainWindowController()
        controller.applyPreferences(.defaults)
        let root = try! XCTUnwrap(controller.window?.contentView)
        let labels = descendants(of: root).compactMap { $0.accessibilityLabel() }
        XCTAssertTrue(labels.contains("Current document heading"))
        XCTAssertTrue(labels.contains("Character column ruler"))
        XCTAssertTrue(labels.contains("Favorite command strip"))
    }

    func testClassicToolbarUsesStableCommandIdentifiers() async {
        let controller = MainWindowController()
        controller.applyPreferences(.defaults)
        XCTAssertEqual(controller.classicToolbarIdentifiersForTesting, [
            "file.new", "file.open", "file.save", "file.print",
            "search.find", "search.replace", "search.findNext", "search.findPrevious",
            "search.grep", "navigate.toggleBookmark", "navigate.nextBookmark",
            "search.goToLine", "navigate.toggleFold", "app.macroMenu",
            "view.toggleSidebar", "app.settings",
        ])

        var received: CommandID?
        controller.onClassicToolbarCommand = { received = $0 }
        controller.activateClassicToolbarCommandForTesting(.searchGrep)
        XCTAssertEqual(received, .searchGrep)
        let labels = descendants(of: try! XCTUnwrap(controller.window?.contentView))
            .compactMap { $0.accessibilityLabel() }
        XCTAssertTrue(labels.contains("Maru Classic command toolbar"))
        XCTAssertTrue(labels.contains("Undo"))
        XCTAssertTrue(labels.contains("Replace"))
        XCTAssertTrue(labels.contains("Print"))
    }

    func testClassicToolbarUsesAColorCodedOriginalIconPalette() async {
        let controller = MainWindowController()
        controller.applyPreferences(.defaults)
        let root = try! XCTUnwrap(controller.window?.contentView)
        let toolbar = try! XCTUnwrap(descendants(of: root).first {
            $0.accessibilityLabel() == "Maru Classic command toolbar"
        })
        let buttons = descendants(of: toolbar).compactMap { $0 as? NSButton }
        XCTAssertEqual(buttons.count, 21)
        let palette = Set(buttons.compactMap { $0.contentTintColor?.description })
        XCTAssertGreaterThanOrEqual(palette.count, 8)
        XCTAssertTrue(buttons.allSatisfy { $0.image != nil && $0.contentTintColor != nil })
    }

    func testClassicToolbarRebuildsFromOrderedPersistentLayout() async {
        let controller = MainWindowController()
        controller.setClassicToolbarLayoutForTesting([
            "search.grep", "-", "file.open", "search.grep", "unknown.command", "-",
        ])
        XCTAssertEqual(controller.classicToolbarLayoutForTesting, ["search.grep", "-", "file.open"])
        XCTAssertEqual(controller.classicToolbarIdentifiersForTesting, ["search.grep", "file.open"])

        let root = try! XCTUnwrap(controller.window?.contentView)
        let toolbar = try! XCTUnwrap(descendants(of: root).first {
            $0.accessibilityLabel() == "Maru Classic command toolbar"
        })
        let labels = descendants(of: toolbar).compactMap { ($0 as? NSButton)?.accessibilityLabel() }
        XCTAssertEqual(labels, ["Grep", "Open"])
    }

    func testClassicToolbarSupportsIconTextAndTextOnlyDisplayModes() async {
        let controller = MainWindowController()
        controller.setClassicToolbarLayoutForTesting(["file.open", "search.grep"])
        let root = try! XCTUnwrap(controller.window?.contentView)
        let toolbar = try! XCTUnwrap(descendants(of: root).first {
            $0.accessibilityLabel() == "Maru Classic command toolbar"
        })

        controller.setClassicToolbarDisplayModeForTesting(.iconAndText)
        var buttons = descendants(of: toolbar).compactMap { $0 as? NSButton }
        XCTAssertEqual(buttons.map(\.title), ["Open", "Grep"])
        XCTAssertTrue(buttons.allSatisfy { $0.imagePosition == .imageLeading && $0.image != nil })

        controller.setClassicToolbarDisplayModeForTesting(.textOnly)
        buttons = descendants(of: toolbar).compactMap { $0 as? NSButton }
        XCTAssertEqual(controller.classicToolbarDisplayModeForTesting, .textOnly)
        XCTAssertTrue(buttons.allSatisfy { $0.imagePosition == .noImage && !$0.title.isEmpty })
    }

    func testFunctionKeyStripHasTwelveConfigurableStableCommandSlots() async {
        let controller = MainWindowController()
        controller.setClassicFunctionKeyCommandsForTesting([.searchGrep, nil, .fileSave])
        XCTAssertEqual(controller.classicFunctionKeyCommandsForTesting.count, 12)
        XCTAssertEqual(Array(controller.classicFunctionKeyCommandsForTesting.prefix(3)),
                       ["search.grep", nil, "file.save"])
        let labels = descendants(of: try! XCTUnwrap(controller.window?.contentView))
            .compactMap { ($0 as? NSButton)?.accessibilityLabel() }
        XCTAssertTrue(labels.contains("F1 Grep"))
        XCTAssertTrue(labels.contains("F2 Unassigned"))
        XCTAssertTrue(labels.contains("F3 Save"))
        var received: CommandID?
        controller.onClassicToolbarCommand = { received = $0 }
        controller.activateClassicFunctionKeyForTesting(0)
        XCTAssertEqual(received, .searchGrep)
        controller.activateClassicFunctionKeyForTesting(1)
        XCTAssertEqual(received, .searchGrep, "an unassigned slot must be a no-op")
    }

    func testClassicLightAndModernThemesSwitchWithoutChangingDocument() async {
        let controller = MainWindowController()
        controller.macroEditor.textView.string = "theme-safe content"
        controller.applyPreferences(.defaults)
        let classicBackground = Theme.background

        var modern = Preferences.defaults
        modern.workspaceStyle = .modern
        modern.theme = .monokai
        controller.applyPreferences(modern)

        XCTAssertNotEqual(Theme.background, classicBackground)
        XCTAssertEqual(controller.macroEditor.textView.string, "theme-safe content")
    }

    func testUtilityPaneSwitchesBetweenFilesOutlineAndResults() async {
        let sidebar = SidebarViewController()
        _ = sidebar.view
        XCTAssertEqual(sidebar.utilityPaneLabelsForTesting, ["Files", "Outline", "Results"])
        sidebar.showUtilityPane(.outline)
        XCTAssertEqual(sidebar.selectedUtilityPane, .outline)
        sidebar.showUtilityPane(.results)
        XCTAssertEqual(sidebar.selectedUtilityPane, .results)
    }

    func testOutlinePaneListsSymbolsAndTracksCurrentHeading() async {
        let sidebar = SidebarViewController()
        _ = sidebar.view
        sidebar.updateOutline(
            text: "preamble\n# First\nbody\n## Second\n", language: .markdown)
        sidebar.showUtilityPane(.outline)
        XCTAssertEqual(sidebar.outlineTitlesForTesting, ["First", "Second"])
        XCTAssertNil(sidebar.selectOutlineSymbol(containingLine: 0))
        XCTAssertEqual(sidebar.selectOutlineSymbol(containingLine: 3), "Second")
        XCTAssertEqual(sidebar.selectOutlineSymbol(containingLine: 2), "First")
    }

    func testClassicChromeComponentsCanBeHiddenIndependently() async {
        let controller = MainWindowController()
        var preferences = Preferences.defaults
        preferences.classicChrome = ClassicChromeOptions(
            showHeading: false, showRuler: true, showCommandStrip: false)
        controller.applyPreferences(preferences)
        XCTAssertEqual(controller.classicChromeVisibilityForTesting, preferences.classicChrome)
    }

    func testSingleDocumentDoesNotRepeatFilenameAboveLineNumbers() async {
        let controller = MainWindowController()
        controller.applyPreferences(.defaults)
        XCTAssertFalse(controller.isClassicHeadingVisibleForTesting)

        controller.newDocument()
        XCTAssertTrue(controller.isClassicHeadingVisibleForTesting)
        controller.closeCurrentTab()
        XCTAssertFalse(controller.isClassicHeadingVisibleForTesting)
    }

    func testInsertMenuCommandsMutateTextThroughEditor() async {
        let controller = MainWindowController()
        controller.insertPageBreak()
        XCTAssertEqual(controller.editorTextForTesting, "\u{000C}")
        controller.insertDateTime(now: Date(timeIntervalSince1970: 0))
        XCTAssertGreaterThan(controller.editorTextForTesting.count, 1)
    }

    func testViewModeImmediatelyLocksAndUnlocksTheEditor() async {
        let controller = MainWindowController()
        XCTAssertTrue(controller.macroEditor.textView.isEditable)
        controller.toggleViewMode()
        XCTAssertFalse(controller.macroEditor.textView.isEditable)
        controller.toggleViewMode()
        XCTAssertTrue(controller.macroEditor.textView.isEditable)
    }

    func testRulerTracksEditorOriginAndCurrentDisplayColumn() async {
        let controller = MainWindowController()
        controller.applyPreferences(.defaults)
        controller.toggleSidebar()
        controller.editorCursorMoved(
            controller.macroEditor,
            state: EditorCursorState(lineNumber: 1, displayColumn: 37, utf16Offset: 36,
                                     selectedCharacterCount: 0, selectedUTF16Length: 0,
                                     selectionRangeCount: 1))
        XCTAssertEqual(controller.classicRulerStateForTesting.column, 37)
        XCTAssertEqual(controller.classicRulerMaximumColumnForTesting, 160)
        XCTAssertLessThan(controller.classicRulerStateForTesting.origin, 64,
                          "a collapsed sidebar must not leave stale horizontal space before the ruler")
    }

    private func descendants(of view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + descendants(of: $0) }
    }
}
