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
            .appSettings, .appMacroMenu, .appHelp,
            .fileNew, .fileNewFromTemplate, .fileOpen, .fileOpenFolder, .fileSave, .fileSaveAs,
            .fileCloseTab, .windowNextTab, .windowPreviousTab,
            .fileClearRecoveryData, .filePageSetup, .filePrint,
            .fileReload, .fileToggleViewMode, .fileProperties,
            .fileAppendRead, .fileAppendSave,
            .fileRename,
            .searchFind, .searchReplace, .searchReplaceAll, .searchFindNext,
            .searchFindPrevious, .searchGoToLine, .searchQuickOpen, .searchGrep,
            .searchGrepCurrentDocument, .searchGrepOpenDocuments,
            .searchRefineGrepResults, .searchOutputGrepDocument,
            .searchClearHistory, .viewToggleSidebar, .viewToggleWrap, .viewToggleTableMode,
            .viewToggleSpaces, .viewToggleTabs, .viewToggleLineEndings,
            .viewToggleFullWidthSpaces, .viewTabWidth2, .viewTabWidth4,
            .viewTabWidth8, .viewShowFonts, .viewCustomizeMenus
            , .editAddCursorAbove, .editAddCursorBelow, .editSelectNextOccurrence,
            .editSelectAllOccurrences, .editUndoLastAddedCursor, .editBeginColumnSelection,
            .editDeleteLine, .editDuplicateLine, .editMoveLineUp, .editMoveLineDown,
            .editJoinLines, .editTrimTrailingWhitespace, .editUppercase, .editLowercase,
            .editSortLines, .editReverseLines, .editIndent, .editOutdent, .editToggleComment,
            .editToggleInputMode,
            .editMoveWordLeft, .editMoveWordRight, .editMoveParagraphStart,
            .editMoveParagraphEnd, .editDeleteWordBackward, .editDeleteWordForward,
            .editTitlecase, .editCompleteWord, .insertDateTime, .insertPageBreak,
            .insertFileContents,
            .convertHalfWidth, .convertFullWidth, .convertHiragana, .convertKatakana,
            .convertTabsToSpaces, .convertSpacesToTabs,
            .navigateMarkerRed, .navigateMarkerYellow, .navigateMarkerBlue,
            .navigateNextMarker, .navigatePreviousMarker, .navigateClearMarkers,
            .viewSplitVertical, .viewSplitHorizontal, .viewCloseSplit,
            .viewToggleLinkedScrolling,
            .navigateCompareNextDocument, .navigateNextDifference,
            .navigatePreviousDifference, .navigateMergeDifferenceFromRight,
            .navigateTagJump, .navigateDirectTagJump, .navigateBackTagJump,
            .navigateToggleBookmark, .navigateNextBookmark,
            .navigatePreviousBookmark, .navigateClearBookmarks
            , .navigateToggleFold, .navigateCollapseAllFolds, .navigateExpandAllFolds,
            .navigateBeginPartialOutline, .navigateEndPartialOutline
        ]
        for id in ids {
            XCTAssertNotNil(registry.definition(for: id), "\(id.rawValue) should be registered")
        }
        XCTAssertEqual(registry.allDefinitions.count, ids.count)
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
