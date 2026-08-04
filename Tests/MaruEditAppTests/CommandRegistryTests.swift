import XCTest
import MaruEditCore
@testable import MaruEditApp

final class CommandRegistryTests: XCTestCase {

    /// A minimal context for exercising the registry mechanism itself.
    /// `AppCoordinator()` alone is safe to construct — it doesn't create a
    /// window until `ensureWindowControllerReady()` is called, which none
    /// of these tests trigger.
    private func makeContext() -> CommandContext {
        CommandContext(coordinator: AppCoordinator())
    }

    func testEnabledCommandExecutes() {
        let registry = CommandRegistry()
        var didRun = false
        registry.register(CommandDefinition(id: CommandID("test.enabled"), title: "Enabled") { _ in
            didRun = true
        })

        let ran = registry.execute(CommandID("test.enabled"), context: makeContext())
        XCTAssertTrue(ran)
        XCTAssertTrue(didRun)
    }

    func testDisabledCommandDoesNotExecute() {
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

    func testUnregisteredCommandIsSafelyANoOp() {
        let registry = CommandRegistry()
        XCTAssertFalse(registry.isEnabled(CommandID("does.not.exist"), context: makeContext()))
        XCTAssertFalse(registry.execute(CommandID("does.not.exist"), context: makeContext()))
        XCTAssertNil(registry.definition(for: CommandID("does.not.exist")))
    }

    func testAllAppCommandsAreRegisteredAndUniquelyIdentified() {
        let registry = CommandRegistry()
        AppCommands.registerAll(in: registry)

        let ids: [CommandID] = [
            .appSettings, .fileNew, .fileOpen, .fileOpenFolder, .fileSave, .fileSaveAs,
            .fileCloseTab, .fileClearRecoveryData, .searchFind, .searchReplace, .searchReplaceAll, .searchFindNext,
            .searchFindPrevious, .searchGoToLine, .searchQuickOpen, .searchGrep,
            .searchClearHistory, .viewToggleSidebar
            , .editAddCursorAbove, .editAddCursorBelow, .editSelectNextOccurrence,
            .editSelectAllOccurrences, .editUndoLastAddedCursor, .editBeginColumnSelection,
            .editDeleteLine, .editDuplicateLine, .editMoveLineUp, .editMoveLineDown,
            .editJoinLines, .editTrimTrailingWhitespace, .editUppercase, .editLowercase,
            .editSortLines, .editReverseLines, .editIndent, .editOutdent, .editToggleComment,
            .navigateToggleBookmark, .navigateNextBookmark,
            .navigatePreviousBookmark, .navigateClearBookmarks
        ]
        for id in ids {
            XCTAssertNotNil(registry.definition(for: id), "\(id.rawValue) should be registered")
        }
        XCTAssertEqual(registry.allDefinitions.count, ids.count)
    }

    func testAppCommandsAreEnabledByDefault() {
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
