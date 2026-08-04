import MaruEditCore

/// Stable command identifiers for MaruEdit's static, app-level menu
/// commands. Naming follows the `domain.action` convention from
/// ROADMAP.md ADR-006 (`file.new`, `search.find`, ...).
extension CommandID {
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
    static let editAddCursorAbove = CommandID("edit.addCursorAbove")
    static let editAddCursorBelow = CommandID("edit.addCursorBelow")
    static let editSelectNextOccurrence = CommandID("edit.selectNextOccurrence")
    static let editSelectAllOccurrences = CommandID("edit.selectAllOccurrences")
    static let editUndoLastAddedCursor = CommandID("edit.undoLastAddedCursor")
    static let editBeginColumnSelection = CommandID("edit.beginColumnSelection")
}

/// The command definitions for MaruEdit's current static menu actions.
/// Each one is a thin wrapper around the equivalent `AppCoordinator`
/// method — the same method the menu called directly before M1-03,
/// unchanged in behavior, just invoked through the registry now.
enum AppCommands {
    static func registerAll(in registry: CommandRegistry) {
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
        registry.register(CommandDefinition(id: .editAddCursorAbove, title: "Add Cursor Above") { $0.coordinator.addCursorAbove() })
        registry.register(CommandDefinition(id: .editAddCursorBelow, title: "Add Cursor Below") { $0.coordinator.addCursorBelow() })
        registry.register(CommandDefinition(id: .editSelectNextOccurrence, title: "Select Next Occurrence") { $0.coordinator.selectNextOccurrence() })
        registry.register(CommandDefinition(id: .editSelectAllOccurrences, title: "Select All Occurrences") { $0.coordinator.selectAllOccurrences() })
        registry.register(CommandDefinition(id: .editUndoLastAddedCursor, title: "Undo Last Added Cursor") { $0.coordinator.undoLastAddedCursor() })
        registry.register(CommandDefinition(id: .editBeginColumnSelection, title: "Begin Column Selection") { $0.coordinator.beginColumnSelection() })
    }
}
