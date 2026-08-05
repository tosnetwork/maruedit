import AppKit
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

    func testOfficialMacroRecordingCommandTogglesOneSharedState() {
        let coordinator = AppCoordinator()
        let context = CommandContext(coordinator: coordinator)
        let registry = CommandRegistry(); AppCommands.registerAll(in: registry)

        XCTAssertFalse(coordinator.isRecordingCommands)
        XCTAssertTrue(registry.execute(.macroToggleRecording, context: context))
        XCTAssertTrue(coordinator.isRecordingCommands)
        XCTAssertTrue(registry.execute(.macroToggleRecording, context: context))
        XCTAssertFalse(coordinator.isRecordingCommands)
        NSApp.windows.filter { $0.windowController is MainWindowController }.forEach { $0.close() }
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
            .appSettings, .appMacroMenu, .macroStartRecording, .macroStopRecording, .macroToggleRecording,
            .macroPlayRecording, .macroRepeatPlayback, .macroSaveRecording,
            .macroRun, .macroReload, .macroOpenFolder, .macroHelp,
            .appHelp, .helpMacros, .helpShortcuts,
            .helpCheckUpdates, .helpSupport, .helpConfigureExternal,
            .helpExternal1, .helpExternal2, .helpExternal3,
            .helpExternal4, .helpExternal5, .helpExternal6,
            .otherFileTypeProfiles, .otherKeyAssignments, .otherCommandList,
            .otherCorrectSpelling,
            .toolsOpenFinder, .toolsConfigureUserMenus,
            .fileNew, .fileNewFromTemplate, .fileOpen, .fileOpenFolder, .fileOpenPartial,
            .fileOpenBinary,
            .fileProjectHistory, .fileSaveWorkspace, .fileOpenWorkspace,
            .fileWorkspaceHistory,
            .fileSave, .fileSaveAs, .fileSaveAll, .fileSaveAllModified, .fileSaveLF,
            .fileSaveAndClose, .fileSaveAllAndClose, .fileDiscardAndClose,
            .fileDiscardAllAndClose, .fileOpenCursorTargetAssociated,
            .fileOpenCursorTargetInEditor,
            .fileCloseAndOpen, .fileCloseWorkspace, .fileCloseTab, .windowNextTab, .windowPreviousTab,
            .windowTabList, .windowCloseOtherTabs, .windowCloseTabsLeft,
            .windowCloseTabsRight, .windowFocusEditor, .windowFocusUtilityPane,
            .windowTileVertical, .windowTileHorizontal, .windowCascade, .windowTileGrid,
            .windowMinimizeAll, .windowAlwaysOnTop, .windowFullScreen,
            .windowDetachTab, .windowMinimizeTab,
            .windowShowFilesPane, .windowShowOutlinePane,
            .windowNextManaged, .windowPreviousManaged,
            .windowNextManagedIncludingMinimized, .windowPreviousManagedIncludingMinimized,
            .windowPreviousActive,
            .fileClearRecoveryData, .filePageSetup, .filePrint,
            .fileReload, .fileToggleViewMode, .fileToggleOverwriteProtection,
            .fileToggleHistoryRecording, .fileProperties,
            .fileAppendRead, .fileAppendSave,
            .fileRename,
            .searchFind, .searchFindUpward, .searchFindWord, .searchCaptureString,
            .searchReplace, .searchReplaceAll, .searchFindNext,
            .searchFindPrevious, .searchGoToLine, .searchQuickOpen, .searchGrep,
            .searchGrepCurrentDocument, .searchGrepOpenDocuments,
            .searchRefineGrepResults, .searchOutputGrepDocument,
            .searchGrepReplace,
            .searchClearHistory, .viewToggleSidebar, .viewToggleToolbar, .viewToggleWrap, .viewToggleTableMode,
            .navigateDocumentStart, .navigateDocumentEnd,
            .navigateScreenStart, .navigateScreenEnd,
            .navigateWordStart, .navigateWordEnd, .navigateWordRightSalnen,
            .navigateLineStart, .navigateLineEnd, .navigateLineEndAfterCharacter,
            .navigateLogicalLineStart, .navigateLogicalLineEnd,
            .navigateNextPage, .navigatePreviousPage,
            .navigateHalfNextPage, .navigateHalfPreviousPage,
            .navigateScrollUp, .navigateScrollDown, .navigateScrollUp2, .navigateScrollDown2,
            .navigatePreviousTabStop, .navigateNextTabStop,
            .navigateMatchingBracket, .navigateOpeningBrace, .navigateClosingBrace,
            .navigateMatchingTag, .navigateLastEdit, .navigatePreviousCursor,
            .viewToggleVerticalLayout, .viewToggleColumnLayout,
            .viewToggleLineNumbers, .viewToggleHeading, .viewToggleFunctionKeys,
            .viewToggleStatusBar, .viewToggleOutputPane, .viewFocusOutputPane,
            .viewToggleSpellChecking, .viewShowCharacterCode, .viewShowCharacterCount,
            .viewRedraw, .viewToggleFullScreen,
            .searchToggleCaseSensitive, .searchToggleWholeWord, .searchToggleRegex, .searchToggleFuzzy,
            .searchNextEditMark, .searchPreviousEditMark, .searchClearEditMarks,
            .searchToggleHighlight, .searchSelectAllMatches, .searchColorAllMatches,
            .searchClearMatchColors, .searchListAllMatches, .searchReturnToStart,
            .searchOutlineAllMatches, .searchListColorLayers,
            .searchToggleMark, .searchListMarks, .searchClearAllMarks, .searchClearCurrentMarks,
            .searchNextResult, .searchPreviousResult, .searchNextGrepResult, .searchPreviousGrepResult,
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
            .editAppendCopy, .editAppendCut, .editDeleteToLineStart, .editDeleteToLineEnd,
            .editInvertSelections, .editReserveSelections, .editRestoreReservedSelections,
            .editBoxPaste, .editPastePreviousClipboard,
            .editRepeatLastOperation,
            .editSelectAllOccurrences, .editUndoLastAddedCursor, .editBeginColumnSelection,
            .editDeleteLine, .editDuplicateLine, .editMoveLineUp, .editMoveLineDown,
            .editJoinLines, .editTrimTrailingWhitespace, .editUppercase, .editLowercase,
            .editSortLines, .editReverseLines, .editIndent, .editOutdent, .editToggleComment,
            .editToggleInputMode,
            .editMoveWordLeft, .editMoveWordRight, .editMoveParagraphStart,
            .editMoveParagraphEnd, .editDeleteWordBackward, .editDeleteWordForward,
            .editTitlecase, .editCompleteWord, .insertDateTime, .insertNewline,
            .insertTab, .insertPageBreak, .insertBlankLine, .insertCurrentFileName,
            .insertFileContents, .insertControlCode, .insertTemplate,
            .convertHalfWidth, .convertFullWidth, .convertHiragana, .convertKatakana,
            .convertHalfWidthAlphanumeric, .convertFullWidthAlphanumeric,
            .convertHalfWidthKatakana, .convertFullWidthKatakana,
            .convertPipelineDialog,
            .convertTabsToSpaces, .convertSpacesToTabs,
            .navigateMarkerRed, .navigateMarkerYellow, .navigateMarkerBlue,
            .highlightTemporaryConfigure, .highlightTemporaryApply,
            .highlightTemporaryRemove, .highlightTemporaryClear,
            .highlightTemporarySelect, .highlightTemporaryNext,
            .highlightTemporaryPrevious,
            .highlightOutlineAnalysis, .highlightNextLine, .highlightPreviousLine,
            .highlightSelectLineArea,
            .navigateNextMarker, .navigatePreviousMarker, .navigateHighlightList,
            .navigateClearMarkers,
            .viewSplitVertical, .viewSplitHorizontal, .viewCloseSplit,
            .viewToggleLinkedScrolling,
            .navigateCompareNextDocument, .navigateNextDifference,
            .navigatePreviousDifference, .navigateMergeDifferenceFromRight,
            .navigateGenerateTags, .navigateTagJump, .navigateDirectTagJump, .navigateBackTagJump,
            .navigateToggleBookmark, .navigateNextBookmark,
            .navigatePreviousBookmark, .navigateBookmarkList, .navigateClearBookmarks
            , .navigateToggleFold, .navigateCollapseAllFolds, .navigateExpandAllFolds,
            .navigateBeginPartialOutline, .navigateEndPartialOutline,
            .otherClearFindHistory, .otherClearReplaceHistory, .otherClearGrepHistory,
            .otherClearClipboardHistory, .otherClearRecentFiles, .otherClearRecentFolders,
            .otherClearRecentWorkspaces, .otherClearRecentEncodings, .otherClearAllHistories
            , .otherToggleFreeCursor, .otherExportSettings, .otherImportSettings, .otherRestoreSettings,
            .otherJapaneseUserDictionary
        ]
        for id in ids {
            XCTAssertNotNil(registry.definition(for: id), "\(id.rawValue) should be registered")
        }
        XCTAssertEqual(registry.allDefinitions.count, ids.count)
    }

    func testRecordedMacroSupportsBoundedRepeatPlayback() {
        let coordinator = AppCoordinator()
        let id = CommandID("test.recorded.repeat")
        var executions = 0
        coordinator.commandRegistry.register(CommandDefinition(id: id, title: "Repeat") { _ in
            executions += 1
        })
        coordinator.startMacroRecording()
        XCTAssertTrue(coordinator.commandRegistry.execute(
            id, context: CommandContext(coordinator: coordinator)))
        coordinator.stopMacroRecording()
        coordinator.playMacroRecording(repeatCount: 3)
        XCTAssertEqual(executions, 4)
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

    func testRepeatLastEditTracksOnlySuccessfulDeterministicEdits() {
        let coordinator = AppCoordinator()
        let context = CommandContext(coordinator: coordinator)
        XCTAssertFalse(coordinator.commandRegistry.isEnabled(.editRepeatLastOperation, context: context))
        coordinator.prepareUITestDocument(content: "one two", selections: [NSRange(location: 0, length: 3)])
        XCTAssertTrue(coordinator.commandRegistry.execute(.editUppercase, context: context))
        let editor = coordinator.ensureWindowControllerReady().macroEditor
        XCTAssertEqual(editor.textView.string, "ONE two")
        editor.setSelections([NSRange(location: 4, length: 3)])
        XCTAssertTrue(coordinator.commandRegistry.isEnabled(.editRepeatLastOperation, context: context))
        XCTAssertTrue(coordinator.commandRegistry.execute(.editRepeatLastOperation, context: context))
        XCTAssertEqual(editor.textView.string, "ONE TWO")
    }

    func testAppCommandsAreEnabledByDefault() async {
        let registry = CommandRegistry()
        AppCommands.registerAll(in: registry)
        let context = makeContext()
        let configurationDependentCommands: Set<CommandID> = [
            .helpExternal1, .helpExternal2, .helpExternal3,
            .helpExternal4, .helpExternal5, .helpExternal6,
            .editRepeatLastOperation,
        ]

        for definition in registry.allDefinitions where !configurationDependentCommands.contains(definition.id) {
            XCTAssertTrue(
                registry.isEnabled(definition.id, context: context),
                "\(definition.id.rawValue) should be enabled with no document open yet"
            )
        }
    }
}
