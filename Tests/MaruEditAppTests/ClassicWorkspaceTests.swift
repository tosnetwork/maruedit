import XCTest
import MaruEditCore
@preconcurrency @testable import MaruEditApp

@preconcurrency @MainActor
final class ClassicWorkspaceTests: XCTestCase {
    func testClassicToolbarHasConfigurableExecutableSearchBox() {
        let controller = MainWindowController()
        controller.prepareUITestDocument(content: "zero needle one needle", selections: [])
        controller.setClassicToolbarSearchVisibleForTesting(true)
        XCTAssertTrue(controller.isClassicToolbarSearchVisibleForTesting)
        controller.performClassicToolbarSearchForTesting("needle")
        XCTAssertEqual(controller.macroEditor.selectionSet.primaryRange,
                       NSRange(location: 5, length: 6))
        XCTAssertEqual(controller.macroEditor.searchHighlightRangesForTesting.count, 2)
        controller.setClassicToolbarSearchVisibleForTesting(false)
        XCTAssertFalse(controller.isClassicToolbarSearchVisibleForTesting)
    }

    func testToolbarSupportsThreeExplicitIconSizes() {
        let controller = MainWindowController()
        for size in ToolbarIconSize.allCases {
            controller.setClassicToolbarIconSizeForTesting(size)
            XCTAssertEqual(controller.classicToolbarIconSizeForTesting, size)
        }
        XCTAssertEqual(ToolbarIconSize.allCases.map(\.pointSize), [13, 17, 21])
    }

    func testFunctionKeysCanShareOnePhysicalRowWithStatusBar() {
        let controller = MainWindowController()
        controller.setFunctionKeyStripMergedForTesting(true)
        XCTAssertTrue(controller.isFunctionKeyStripMergedForTesting)
        XCTAssertGreaterThan(controller.statusBarFrameForTesting.minX, 0)
        XCTAssertEqual(controller.statusBarFrameForTesting.minY,
                       controller.classicChromeFrameForTesting.minY, accuracy: 0.5)

        controller.setFunctionKeyStripMergedForTesting(false)
        XCTAssertEqual(controller.statusBarFrameForTesting.minX, 0)
        XCTAssertGreaterThan(controller.classicChromeFrameForTesting.minY,
                             controller.statusBarFrameForTesting.minY)
    }
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

    func testWindowHasACompleteForwardAndReverseKeyboardFocusLoop() {
        let controller = MainWindowController()
        controller.applyPreferences(.defaults)
        controller.newDocument() // make the tab bar visible under the Hidemaru default
        controller.showFind(showingReplace: true)
        controller.showOutputPane()

        let loop = controller.keyboardFocusLoopForTesting
        let labels = loop.compactMap { $0.accessibilityLabel() }
        XCTAssertTrue(labels.contains("New"), "toolbar is absent from the focus loop")
        XCTAssertTrue(labels.contains("Find"), "find bar is absent from the focus loop")
        XCTAssertTrue(labels.contains(where: { $0.hasPrefix("Tab 1:") }))
        XCTAssertTrue(labels.contains("Editor"))
        XCTAssertTrue(labels.contains("Utility pane"))
        XCTAssertTrue(labels.contains("Search results list"))
        XCTAssertTrue(labels.contains("Cursor line and display column"))
        XCTAssertTrue(labels.contains(where: { $0.hasPrefix("F1 ") }))

        let window = try! XCTUnwrap(controller.window)
        for index in loop.indices {
            let current = loop[index]
            let next = loop[(index + 1) % loop.count]
            XCTAssertTrue(current.nextKeyView === next, "broken forward focus link at \(index)")
            XCTAssertTrue(next.previousKeyView === current, "broken reverse focus link at \(index)")
            XCTAssertTrue(window.makeFirstResponder(current),
                          "focus loop contains a non-focusable view: \(current)")
            let expectedResponder: NSResponder? = (current as? NSTextField)?.isEditable == true
                ? window.fieldEditor(false, for: current) : current
            XCTAssertTrue(window.firstResponder === expectedResponder)
        }
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

    func testClassicToolbarAndFunctionKeysAcceptAnyRegisteredCommand() async {
        let controller = MainWindowController()
        controller.configureClassicCommands([
            (.fileOpen, "Open"), (.editSortLines, "Sort Lines"),
        ])
        controller.setClassicToolbarLayoutForTesting(["edit.sortLines"])
        XCTAssertEqual(controller.classicToolbarLayoutForTesting, ["edit.sortLines"])
        XCTAssertEqual(controller.classicToolbarIdentifiersForTesting, ["edit.sortLines"])

        controller.setClassicFunctionKeyCommandsForTesting([.editSortLines])
        XCTAssertEqual(controller.classicFunctionKeyCommandsForTesting.first!, "edit.sortLines")
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

    func testFunctionKeyStripSupportsOneThroughTwelveVisibleSlots() async {
        let controller = MainWindowController()
        controller.setClassicFunctionKeyCommandsForTesting(Array(repeating: .fileSave, count: 12))
        for count in 1...12 {
            controller.setClassicFunctionKeyCountForTesting(count)
            XCTAssertEqual(controller.classicFunctionKeyCountForTesting, count)
            XCTAssertNotNil(controller.classicFunctionKeyPresentationForTesting(count - 1))
            if count < 12 {
                XCTAssertNil(controller.classicFunctionKeyPresentationForTesting(count))
            }
        }
    }

    func testToolbarAndFunctionKeysReflectLiveEnabledAndToggleState() async {
        let controller = MainWindowController()
        controller.configureClassicCommands([
            (.fileSave, "Save"), (.viewToggleWrap, "Wrap"),
        ])
        controller.setClassicToolbarLayoutForTesting(["file.save", "view.toggleWrap"])
        controller.setClassicFunctionKeyCommandsForTesting([.fileSave, .viewToggleWrap])
        var saveEnabled = false
        var wrapSelected = true
        controller.configureClassicCommandPresentation { command in
            if command == .fileSave { return (saveEnabled, false) }
            if command == .viewToggleWrap { return (true, wrapSelected) }
            return (true, false)
        }

        XCTAssertEqual(controller.classicToolbarPresentationForTesting(.fileSave)?.enabled, false)
        XCTAssertEqual(controller.classicToolbarPresentationForTesting(.viewToggleWrap)?.selected, true)
        XCTAssertEqual(controller.classicFunctionKeyPresentationForTesting(0)?.enabled, false)
        XCTAssertEqual(controller.classicFunctionKeyPresentationForTesting(1)?.selected, true)

        saveEnabled = true; wrapSelected = false
        controller.refreshClassicCommandPresentation()
        XCTAssertEqual(controller.classicToolbarPresentationForTesting(.fileSave)?.enabled, true)
        XCTAssertEqual(controller.classicToolbarPresentationForTesting(.viewToggleWrap)?.selected, false)
        XCTAssertEqual(controller.classicFunctionKeyPresentationForTesting(0)?.enabled, true)
        XCTAssertEqual(controller.classicFunctionKeyPresentationForTesting(1)?.selected, false)
    }

    func testCoordinatorCanWireLiveCommandPresentationWithoutRecursiveWindowCreation() async {
        let coordinator = AppCoordinator(preferencesStore: PreferencesStore(
            defaults: UserDefaults(suiteName: "ClassicPresentation.\(UUID().uuidString)")!))
        let controller = coordinator.ensureWindowControllerReady(restoreSession: false)
        XCTAssertTrue(controller === coordinator.ensureWindowControllerReady(restoreSession: false))
        XCTAssertNotNil(controller.classicToolbarPresentationForTesting(.fileSave))
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
        controller.insertTab()
        controller.insertNewline()
        controller.insertPageBreak()
        XCTAssertEqual(controller.editorTextForTesting, "\t\n\t\u{000C}")
        controller.macroEditor.textView.string = "  alpha\n"
        controller.macroEditor.textView.setSelectedRange(NSRange(location: 4, length: 0))
        controller.insertBlankLine()
        XCTAssertEqual(controller.editorTextForTesting, "  \n  alpha\n")
    }

    func testInsertTemplateUsesEverySelectionAndOneUndoTransaction() {
        let controller = MainWindowController()
        controller.prepareUITestDocument(
            content: "ab", selections: [NSRange(location: 0, length: 0), NSRange(location: 2, length: 0)])

        controller.insertTemplateContentsForTesting("<T>")
        XCTAssertEqual(controller.editorTextForTesting, "<T>ab<T>")

        controller.macroEditor.textView.undoManager?.undo()
        XCTAssertEqual(controller.editorTextForTesting, "ab")
    }

    func testControlCodeInsertionAcceptsC0AndDELOnly() async {
        let controller = MainWindowController()
        controller.macroEditor.textView.string = "AB"
        controller.macroEditor.textView.setSelectedRange(NSRange(location: 1, length: 0))
        XCTAssertTrue(controller.insertControlCode(0x1B))
        XCTAssertEqual(controller.macroEditor.textView.string, "A\u{001B}B")
        XCTAssertFalse(controller.insertControlCode(0x20))
    }

    func testCurrentFileNameInsertionUsesLastPathComponent() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("MaruEdit-insert-name-\(UUID().uuidString).txt")
        try "".write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }
        let controller = MainWindowController()
        controller.openFile(url)
        controller.insertCurrentFileName()
        XCTAssertEqual(controller.currentDocumentTextForTesting, url.lastPathComponent)
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

    func testRulerSupportsEightColumnMarksAndVisibleProfileTabStops() {
        let controller = MainWindowController()
        var preferences = Preferences.defaults
        preferences.classicChrome.rulerInterval = 8
        preferences.classicChrome.showTabStops = true
        preferences.tabWidth = 8
        controller.applyPreferences(preferences)

        XCTAssertEqual(controller.classicRulerConfigurationForTesting.interval, 8)
        XCTAssertTrue(controller.classicRulerConfigurationForTesting.showsTabStops)
        XCTAssertEqual(controller.classicRulerConfigurationForTesting.tabWidth, 8)
    }

    func testToolbarVisibilityIsIndependentAndPersistentInPreferences() {
        let controller = MainWindowController()
        var preferences = Preferences.defaults
        preferences.classicChrome.showToolbar = false
        controller.applyPreferences(preferences)
        XCTAssertFalse(controller.isClassicToolbarVisibleForTesting)

        let encoded = try! JSONEncoder().encode(preferences)
        let decoded = try! JSONDecoder().decode(Preferences.self, from: encoded)
        XCTAssertFalse(decoded.classicChrome.showToolbar)
    }

    private func descendants(of view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + descendants(of: $0) }
    }
}
