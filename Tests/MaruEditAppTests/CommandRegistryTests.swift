import XCTest
import MaruEditCore
@preconcurrency @testable import MaruEditApp


@preconcurrency @MainActor
final class CommandRegistryTests: XCTestCase {
    func testDynamicCommandCanBeUnregistered() async {
        let registry = CommandRegistry()
        let id: CommandID = "macro.user.dynamic"
        registry.register(CommandDefinition(id: id, title: "Dynamic") { _ in })
        XCTAssertNotNil(registry.definition(for: id))
        XCTAssertTrue(registry.unregister(id))
        XCTAssertNil(registry.definition(for: id))
        XCTAssertFalse(registry.unregister(id))
    }

    /// A minimal context for exercising the registry mechanism itself.
    /// `AppCoordinator()` alone is safe to construct — it doesn't create a
    /// window until `ensureWindowControllerReady()` is called, which none
    /// of these tests trigger.
    private func makeContext() -> CommandContext {
        CommandContext(coordinator: AppCoordinator())
    }

    func testEnabledCommandExecutes() async {
        let registry = CommandRegistry()
        var didRun = false
        registry.register(CommandDefinition(id: CommandID("test.enabled"), title: "Enabled") { _ in
            didRun = true
        })

        let ran = registry.execute(CommandID("test.enabled"), context: makeContext())
        XCTAssertTrue(ran)
        XCTAssertTrue(didRun)
    }

    func testDisabledCommandDoesNotExecute() async {
        let registry = CommandRegistry()
        var didRun = false
        registry.register(CommandDefinition(
            id: CommandID("test.disabled"),
            title: "Disabled",
            isEnabled: { _ in false },
            execute: { _ in didRun = true }
        ))

        XCTAssertFalse(registry.isEnabled(CommandID("test.disabled"), context: makeContext()))
        let ran = registry.execute(CommandID("test.disabled"), context: makeContext())
        XCTAssertFalse(ran)
        XCTAssertFalse(didRun, "a disabled command must never run, even if execute() is called directly")
    }

    func testUnregisteredCommandIsSafelyANoOp() async {
        let registry = CommandRegistry()
        XCTAssertFalse(registry.isEnabled(CommandID("does.not.exist"), context: makeContext()))
        XCTAssertFalse(registry.execute(CommandID("does.not.exist"), context: makeContext()))
        XCTAssertNil(registry.definition(for: CommandID("does.not.exist")))
    }

    func testAllAppCommandsAreRegisteredAndUniquelyIdentified() async {
        let registry = CommandRegistry()
        AppCommands.registerAll(in: registry)

        let ids: [CommandID] = [
            .appSettings, .appMacroMenu, .macroStartRecording, .macroStopRecording,
            .macroPlayRecording, .macroSaveRecording, .appHelp, .helpMacros, .helpShortcuts,
            .helpCheckUpdates, .helpSupport,
            .otherFileTypeProfiles, .otherKeyAssignments, .otherCommandList,
            .fileNew, .fileNewFromTemplate, .fileOpen, .fileOpenFolder, .fileOpenPartial,
            .fileOpenBinary,
            .fileProjectHistory, .fileSaveWorkspace, .fileOpenWorkspace,
            .fileWorkspaceHistory,
            .fileSave, .fileSaveAs, .fileSaveAndClose, .fileSaveAllAndClose,
            .fileCloseAndOpen, .fileCloseTab, .windowNextTab, .windowPreviousTab,
            .windowTabList, .windowCloseOtherTabs, .windowCloseTabsLeft,
            .windowCloseTabsRight, .windowFocusEditor, .windowFocusUtilityPane,
            .fileClearRecoveryData, .filePageSetup, .filePrint,
            .fileReload, .fileToggleViewMode, .fileProperties,
            .fileAppendRead, .fileAppendSave,
            .fileRename,
            .searchFind, .searchReplace, .searchReplaceAll, .searchFindNext,
            .searchFindPrevious, .searchGoToLine, .searchQuickOpen, .searchGrep,
            .searchGrepCurrentDocument, .searchGrepOpenDocuments,
            .searchRefineGrepResults, .searchOutputGrepDocument,
            .searchClearHistory, .viewToggleSidebar, .viewToggleWrap, .viewToggleTableMode,
            .viewToggleVerticalLayout, .viewToggleColumnLayout,
            .viewToggleLineNumbers, .viewToggleHeading, .viewToggleFunctionKeys,
            .viewToggleStatusBar, .viewToggleOutputPane, .viewFocusOutputPane,
            .searchToggleCaseSensitive, .searchToggleWholeWord, .searchToggleRegex, .searchToggleFuzzy,
            .searchNextEditMark, .searchPreviousEditMark, .searchClearEditMarks,
            .searchToggleHighlight, .searchSelectAllMatches, .searchColorAllMatches,
            .searchClearMatchColors, .searchListAllMatches, .searchReturnToStart,
            .searchSetRange, .searchSelectRange, .searchClearRange,
            .viewToggleSpaces, .viewToggleTabs, .viewToggleLineEndings,
            .viewToggleFullWidthSpaces, .viewTabWidth2, .viewTabWidth4,
            .viewTabWidth8, .viewShowFonts, .viewCustomizeMenus,
            .viewToggleRuler, .viewRulerInterval8, .viewRulerInterval10,
            .viewToggleTabStops
            , .editAddCursorAbove, .editAddCursorBelow, .editSelectNextOccurrence,
            .editSelectWord, .editSelectLine, .editSelectParagraph,
            .editCopyQuoted, .editPasteQuoted,
            .editClipboardHistory, .editRestoreDeletion, .editCorrectCapsLock, .editReconvert,
            .editSelectAllOccurrences, .editUndoLastAddedCursor, .editBeginColumnSelection,
            .editDeleteLine, .editDuplicateLine, .editMoveLineUp, .editMoveLineDown,
            .editJoinLines, .editTrimTrailingWhitespace, .editUppercase, .editLowercase,
            .editSortLines, .editReverseLines, .editIndent, .editOutdent, .editToggleComment,
            .editToggleInputMode,
            .editMoveWordLeft, .editMoveWordRight, .editMoveParagraphStart,
            .editMoveParagraphEnd, .editDeleteWordBackward, .editDeleteWordForward,
            .editTitlecase, .editCompleteWord, .insertDateTime, .insertPageBreak,
            .insertFileContents, .insertControlCode,
            .convertHalfWidth, .convertFullWidth, .convertHiragana, .convertKatakana,
            .convertHalfWidthAlphanumeric, .convertFullWidthAlphanumeric,
            .convertHalfWidthKatakana, .convertFullWidthKatakana,
            .convertTabsToSpaces, .convertSpacesToTabs,
            .navigateMarkerRed, .navigateMarkerYellow, .navigateMarkerBlue,
            .navigateNextMarker, .navigatePreviousMarker, .navigateHighlightList,
            .navigateClearMarkers,
            .viewSplitVertical, .viewSplitHorizontal, .viewCloseSplit,
            .viewToggleLinkedScrolling,
            .navigateCompareNextDocument, .navigateNextDifference,
            .navigatePreviousDifference, .navigateMergeDifferenceFromRight,
            .navigateTagJump, .navigateDirectTagJump, .navigateBackTagJump,
            .navigateToggleBookmark, .navigateNextBookmark,
            .navigatePreviousBookmark, .navigateBookmarkList, .navigateClearBookmarks
            , .navigateToggleFold, .navigateCollapseAllFolds, .navigateExpandAllFolds,
            .navigateBeginPartialOutline, .navigateEndPartialOutline
        ]
        for id in ids {
            XCTAssertNotNil(registry.definition(for: id), "\(id.rawValue) should be registered")
        }
        XCTAssertEqual(registry.allDefinitions.count, ids.count)
    }

    func testHelpCommandsRouteToSpecificDocumentationAndSupportDestinations() async {
        let coordinator = AppCoordinator()
        var urls: [URL] = []
        coordinator.openDocumentationURL = { urls.append($0) }
        coordinator.showHelp()
        coordinator.showMacroHelp()
        coordinator.showShortcutReference()
        coordinator.checkForUpdates()
        coordinator.showSupport()
        XCTAssertEqual(urls.map(\.absoluteString), [
            "https://github.com/tosnetwork/maruedit/blob/main/docs/user-guide.md",
            "https://github.com/tosnetwork/maruedit/blob/main/docs/macros.md",
            "https://github.com/tosnetwork/maruedit/blob/main/docs/key-bindings.md",
            "https://github.com/tosnetwork/maruedit/releases/latest",
            "https://github.com/tosnetwork/maruedit/issues",
        ])
    }

    func testRegistryReportsOnlySuccessfullyExecutedCommands() async {
        let registry = CommandRegistry()
        let allowed = CommandID("test.allowed"), denied = CommandID("test.denied")
        registry.register(CommandDefinition(id: allowed, title: "Allowed") { _ in })
        registry.register(CommandDefinition(id: denied, title: "Denied", isEnabled: { _ in false }) { _ in })
        var observed: [CommandID] = []; registry.didExecute = { observed.append($0) }
        let context = makeContext()
        XCTAssertTrue(registry.execute(allowed, context: context))
        XCTAssertFalse(registry.execute(denied, context: context))
        XCTAssertEqual(observed, [allowed])
    }

    func testAppCommandsAreEnabledByDefault() async {
        let registry = CommandRegistry()
        AppCommands.registerAll(in: registry)
        let context = makeContext()

        for definition in registry.allDefinitions {
            XCTAssertTrue(
                registry.isEnabled(definition.id, context: context),
                "\(definition.id.rawValue) should be enabled with no document open yet"
            )
        }
    }
}
