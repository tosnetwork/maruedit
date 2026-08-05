import MaruEditCore

/// Stable command identifiers for MaruEdit's static, app-level menu
/// commands. Naming follows the `domain.action` convention from
/// ROADMAP.md ADR-006 (`file.new`, `search.find`, ...).
extension CommandID {
    static let appSettings      = CommandID("app.settings")
    static let fileNew          = CommandID("file.new")
    static let fileOpen         = CommandID("file.open")
    static let fileOpenFolder   = CommandID("file.openFolder")
    static let fileSave         = CommandID("file.save")
    static let fileSaveAs       = CommandID("file.saveAs")
    static let fileCloseTab     = CommandID("file.closeTab")
    static let fileClearRecoveryData = CommandID("file.clearRecoveryData")
    static let searchFind       = CommandID("search.find")
    static let searchFindNext   = CommandID("search.findNext")
    static let searchReplace    = CommandID("search.replace")
    static let searchReplaceAll = CommandID("search.replaceAll")
    static let searchFindPrevious = CommandID("search.findPrevious")
    static let searchGoToLine   = CommandID("search.goToLine")
    static let searchQuickOpen  = CommandID("search.quickOpen")
    static let searchGrep       = CommandID("search.grep")
    static let searchClearHistory = CommandID("search.clearHistory")
    static let viewToggleSidebar = CommandID("view.toggleSidebar")
    static let viewToggleWrap = CommandID("view.toggleWrap")
    static let viewToggleSpaces = CommandID("view.toggleSpaces")
    static let viewToggleTabs = CommandID("view.toggleTabs")
    static let viewToggleLineEndings = CommandID("view.toggleLineEndings")
    static let viewToggleFullWidthSpaces = CommandID("view.toggleFullWidthSpaces")
    static let viewTabWidth2 = CommandID("view.tabWidth2")
    static let viewTabWidth4 = CommandID("view.tabWidth4")
    static let viewTabWidth8 = CommandID("view.tabWidth8")
    static let viewShowFonts = CommandID("view.showFonts")
    static let viewCustomizeMenus = CommandID("view.customizeMenus")
    static let editAddCursorAbove = CommandID("edit.addCursorAbove")
    static let editAddCursorBelow = CommandID("edit.addCursorBelow")
    static let editSelectNextOccurrence = CommandID("edit.selectNextOccurrence")
    static let editSelectAllOccurrences = CommandID("edit.selectAllOccurrences")
    static let editUndoLastAddedCursor = CommandID("edit.undoLastAddedCursor")
    static let editBeginColumnSelection = CommandID("edit.beginColumnSelection")
    static let editDeleteLine = CommandID("edit.deleteLine")
    static let editDuplicateLine = CommandID("edit.duplicateLine")
    static let editMoveLineUp = CommandID("edit.moveLineUp")
    static let editMoveLineDown = CommandID("edit.moveLineDown")
    static let editJoinLines = CommandID("edit.joinLines")
    static let editTrimTrailingWhitespace = CommandID("edit.trimTrailingWhitespace")
    static let editUppercase = CommandID("edit.uppercase")
    static let editLowercase = CommandID("edit.lowercase")
    static let editSortLines = CommandID("edit.sortLines")
    static let editReverseLines = CommandID("edit.reverseLines")
    static let editIndent = CommandID("edit.indent")
    static let editOutdent = CommandID("edit.outdent")
    static let editToggleComment = CommandID("edit.toggleComment")
    static let editToggleInputMode = CommandID("edit.toggleInputMode")
    static let navigateToggleBookmark = CommandID("navigate.toggleBookmark")
    static let navigateNextBookmark = CommandID("navigate.nextBookmark")
    static let navigatePreviousBookmark = CommandID("navigate.previousBookmark")
    static let navigateClearBookmarks = CommandID("navigate.clearBookmarks")
    static let navigateToggleFold = CommandID("navigate.toggleFold")
    static let navigateCollapseAllFolds = CommandID("navigate.collapseAllFolds")
    static let navigateExpandAllFolds = CommandID("navigate.expandAllFolds")
}

/// The command definitions for MaruEdit's current static menu actions.
/// Each one is a thin wrapper around the equivalent `AppCoordinator`
/// method — the same method the menu called directly before M1-03,
/// unchanged in behavior, just invoked through the registry now.
@MainActor
enum AppCommands {
    static func registerAll(in registry: CommandRegistry) {
        registry.register(CommandDefinition(id: .appSettings, title: "Settings...") { ctx in
            ctx.coordinator.showSettings()
        })
        registry.register(CommandDefinition(id: .fileNew, title: "New File") { ctx in
            ctx.coordinator.newDocument()
        })
        registry.register(CommandDefinition(id: .fileOpen, title: "Open...") { ctx in
            ctx.coordinator.openDocument()
        })
        registry.register(CommandDefinition(id: .fileOpenFolder, title: "Open Folder...") { ctx in
            ctx.coordinator.openFolderPanel()
        })
        registry.register(CommandDefinition(id: .fileSave, title: "Save") { ctx in
            ctx.coordinator.saveDocument()
        })
        registry.register(CommandDefinition(id: .fileSaveAs, title: "Save As...") { ctx in
            ctx.coordinator.saveDocumentAs()
        })
        registry.register(CommandDefinition(id: .fileCloseTab, title: "Close Tab") { ctx in
            ctx.coordinator.closeCurrentTab()
        })
        registry.register(CommandDefinition(id: .fileClearRecoveryData, title: "Clear Recovery Data...") { ctx in
            ctx.coordinator.clearRecoveryData()
        })
        registry.register(CommandDefinition(id: .searchFind, title: "Find...") { ctx in
            ctx.coordinator.showFind()
        })
        registry.register(CommandDefinition(id: .searchReplace, title: "Find and Replace...") { ctx in
            ctx.coordinator.showReplace()
        })
        registry.register(CommandDefinition(id: .searchReplaceAll, title: "Replace All") { ctx in
            ctx.coordinator.replaceAll()
        })
        registry.register(CommandDefinition(id: .searchFindNext, title: "Find Next") { ctx in
            ctx.coordinator.findNext()
        })
        registry.register(CommandDefinition(id: .searchFindPrevious, title: "Find Previous") { ctx in
            ctx.coordinator.findPrevious()
        })
        registry.register(CommandDefinition(id: .searchGoToLine, title: "Go to Line...") { ctx in
            ctx.coordinator.showGoToLine()
        })
        registry.register(CommandDefinition(id: .searchQuickOpen, title: "Quick Open...") { ctx in
            ctx.coordinator.showQuickOpen()
        })
        registry.register(CommandDefinition(id: .searchGrep, title: "Find in Folder...") { ctx in
            ctx.coordinator.showGrep()
        })
        registry.register(CommandDefinition(id: .searchClearHistory, title: "Clear Search History") { ctx in
            ctx.coordinator.clearSearchHistory()
        })
        registry.register(CommandDefinition(id: .viewToggleSidebar, title: "Toggle Sidebar") { ctx in
            ctx.coordinator.toggleSidebar()
        })
        registry.register(CommandDefinition(id: .viewToggleWrap, title: "Wrap Lines") {
            $0.coordinator.toggleWrapLines()
        })
        registry.register(CommandDefinition(id: .viewToggleSpaces, title: "Show Spaces") {
            $0.coordinator.toggleInvisible(\.spaces)
        })
        registry.register(CommandDefinition(id: .viewToggleTabs, title: "Show Tabs") {
            $0.coordinator.toggleInvisible(\.tabs)
        })
        registry.register(CommandDefinition(id: .viewToggleLineEndings, title: "Show Line Endings") {
            $0.coordinator.toggleInvisible(\.lineEndings)
        })
        registry.register(CommandDefinition(
            id: .viewToggleFullWidthSpaces, title: "Show Full-Width Spaces") {
                $0.coordinator.toggleInvisible(\.fullWidthSpaces)
            })
        registry.register(CommandDefinition(id: .viewTabWidth2, title: "2 Spaces") {
            $0.coordinator.setTabWidth(2)
        })
        registry.register(CommandDefinition(id: .viewTabWidth4, title: "4 Spaces") {
            $0.coordinator.setTabWidth(4)
        })
        registry.register(CommandDefinition(id: .viewTabWidth8, title: "8 Spaces") {
            $0.coordinator.setTabWidth(8)
        })
        registry.register(CommandDefinition(id: .viewShowFonts, title: "Show Fonts") {
            $0.coordinator.showFontPanel()
        })
        registry.register(CommandDefinition(id: .viewCustomizeMenus, title: "Customize Menus...") {
            $0.coordinator.showMenuCustomization()
        })
        registry.register(CommandDefinition(id: .editAddCursorAbove, title: "Add Cursor Above") { $0.coordinator.addCursorAbove() })
        registry.register(CommandDefinition(id: .editAddCursorBelow, title: "Add Cursor Below") { $0.coordinator.addCursorBelow() })
        registry.register(CommandDefinition(id: .editSelectNextOccurrence, title: "Select Next Occurrence") { $0.coordinator.selectNextOccurrence() })
        registry.register(CommandDefinition(id: .editSelectAllOccurrences, title: "Select All Occurrences") { $0.coordinator.selectAllOccurrences() })
        registry.register(CommandDefinition(id: .editUndoLastAddedCursor, title: "Undo Last Added Cursor") { $0.coordinator.undoLastAddedCursor() })
        registry.register(CommandDefinition(id: .editBeginColumnSelection, title: "Begin Column Selection") { $0.coordinator.beginColumnSelection() })
        registerLineCommands(in: registry)
        registry.register(CommandDefinition(id: .editToggleInputMode, title: "Toggle Insert/Overwrite Mode") { $0.coordinator.toggleInputMode() })
        registry.register(CommandDefinition(id: .navigateToggleBookmark, title: "Toggle Bookmark") { $0.coordinator.toggleBookmark() })
        registry.register(CommandDefinition(id: .navigateNextBookmark, title: "Next Bookmark") { $0.coordinator.nextBookmark() })
        registry.register(CommandDefinition(id: .navigatePreviousBookmark, title: "Previous Bookmark") { $0.coordinator.previousBookmark() })
        registry.register(CommandDefinition(id: .navigateClearBookmarks, title: "Clear Bookmarks") { $0.coordinator.clearBookmarks() })
        registry.register(CommandDefinition(id: .navigateToggleFold, title: "Toggle Fold") { $0.coordinator.toggleFold() })
        registry.register(CommandDefinition(id: .navigateCollapseAllFolds, title: "Collapse All Folds") { $0.coordinator.collapseAllFolds() })
        registry.register(CommandDefinition(id: .navigateExpandAllFolds, title: "Expand All Folds") { $0.coordinator.expandAllFolds() })
    }

    private static func registerLineCommands(in registry: CommandRegistry) {
        let commands: [(CommandID, String, LineEditCommand)] = [
            (.editDeleteLine, "Delete Line", .delete),
            (.editDuplicateLine, "Duplicate Line/Selection", .duplicate),
            (.editMoveLineUp, "Move Line Up", .moveUp),
            (.editMoveLineDown, "Move Line Down", .moveDown),
            (.editJoinLines, "Join Lines", .join),
            (.editTrimTrailingWhitespace, "Trim Trailing Whitespace", .trimTrailingWhitespace),
            (.editUppercase, "Convert to Uppercase", .uppercase),
            (.editLowercase, "Convert to Lowercase", .lowercase),
            (.editSortLines, "Sort Lines", .sort),
            (.editReverseLines, "Reverse Lines", .reverse),
            (.editIndent, "Indent", .indent),
            (.editOutdent, "Outdent", .outdent),
            (.editToggleComment, "Toggle Comment", .toggleComment),
        ]
        for (id, title, command) in commands {
            registry.register(CommandDefinition(id: id, title: title) {
                $0.coordinator.performLineCommand(command)
            })
        }
    }
}
