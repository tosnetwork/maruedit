import MaruEditCore

/// Stable command identifiers for MaruEdit's static, app-level menu
/// commands. Naming follows the `domain.action` convention from
/// ROADMAP.md ADR-006 (`file.new`, `search.find`, ...).
extension CommandID {
    static let appSettings      = CommandID("app.settings")
    static let appMacroMenu     = CommandID("app.macroMenu")
    static let appHelp          = CommandID("app.help")
    static let fileNew          = CommandID("file.new")
    static let fileNewFromTemplate = CommandID("file.newFromTemplate")
    static let fileOpen         = CommandID("file.open")
    static let fileOpenFolder   = CommandID("file.openFolder")
    static let fileSave         = CommandID("file.save")
    static let fileSaveAs       = CommandID("file.saveAs")
    static let fileCloseTab     = CommandID("file.closeTab")
    static let windowNextTab    = CommandID("window.nextTab")
    static let windowPreviousTab = CommandID("window.previousTab")
    static let fileClearRecoveryData = CommandID("file.clearRecoveryData")
    static let filePageSetup = CommandID("file.pageSetup")
    static let filePrint = CommandID("file.print")
    static let searchFind       = CommandID("search.find")
    static let searchFindNext   = CommandID("search.findNext")
    static let searchReplace    = CommandID("search.replace")
    static let searchReplaceAll = CommandID("search.replaceAll")
    static let searchFindPrevious = CommandID("search.findPrevious")
    static let searchGoToLine   = CommandID("search.goToLine")
    static let searchQuickOpen  = CommandID("search.quickOpen")
    static let searchGrep       = CommandID("search.grep")
    static let searchGrepCurrentDocument = CommandID("search.grepCurrentDocument")
    static let searchGrepOpenDocuments = CommandID("search.grepOpenDocuments")
    static let searchRefineGrepResults = CommandID("search.refineGrepResults")
    static let searchOutputGrepDocument = CommandID("search.outputGrepDocument")
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
    static let editMoveWordLeft = CommandID("edit.moveWordLeft")
    static let editMoveWordRight = CommandID("edit.moveWordRight")
    static let editMoveParagraphStart = CommandID("edit.moveParagraphStart")
    static let editMoveParagraphEnd = CommandID("edit.moveParagraphEnd")
    static let editDeleteWordBackward = CommandID("edit.deleteWordBackward")
    static let editDeleteWordForward = CommandID("edit.deleteWordForward")
    static let editTitlecase = CommandID("edit.titlecase")
    static let editCompleteWord = CommandID("edit.completeWord")
    static let insertDateTime = CommandID("insert.dateTime")
    static let insertPageBreak = CommandID("insert.pageBreak")
    static let viewToggleTableMode = CommandID("view.toggleTableMode")
    static let navigateMarkerRed = CommandID("navigate.markerRed")
    static let navigateMarkerYellow = CommandID("navigate.markerYellow")
    static let navigateMarkerBlue = CommandID("navigate.markerBlue")
    static let navigateNextMarker = CommandID("navigate.nextMarker")
    static let navigatePreviousMarker = CommandID("navigate.previousMarker")
    static let navigateClearMarkers = CommandID("navigate.clearMarkers")
    static let viewSplitVertical = CommandID("view.splitVertical")
    static let viewSplitHorizontal = CommandID("view.splitHorizontal")
    static let viewCloseSplit = CommandID("view.closeSplit")
    static let viewToggleLinkedScrolling = CommandID("view.toggleLinkedScrolling")
    static let navigateCompareNextDocument = CommandID("navigate.compareNextDocument")
    static let navigateNextDifference = CommandID("navigate.nextDifference")
    static let navigatePreviousDifference = CommandID("navigate.previousDifference")
    static let navigateMergeDifferenceFromRight = CommandID("navigate.mergeDifferenceFromRight")
    static let navigateTagJump = CommandID("navigate.tagJump")
    static let navigateDirectTagJump = CommandID("navigate.directTagJump")
    static let navigateBackTagJump = CommandID("navigate.backTagJump")
    static let navigateToggleBookmark = CommandID("navigate.toggleBookmark")
    static let navigateNextBookmark = CommandID("navigate.nextBookmark")
    static let navigatePreviousBookmark = CommandID("navigate.previousBookmark")
    static let navigateClearBookmarks = CommandID("navigate.clearBookmarks")
    static let navigateToggleFold = CommandID("navigate.toggleFold")
    static let navigateCollapseAllFolds = CommandID("navigate.collapseAllFolds")
    static let navigateExpandAllFolds = CommandID("navigate.expandAllFolds")
    static let navigateBeginPartialOutline = CommandID("navigate.beginPartialOutline")
    static let navigateEndPartialOutline = CommandID("navigate.endPartialOutline")
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
        registry.register(CommandDefinition(id: .appMacroMenu, title: "Macro Menu") { ctx in
            ctx.coordinator.showMacroMenu()
        })
        registry.register(CommandDefinition(id: .appHelp, title: "MaruEdit Help") {
            $0.coordinator.showHelp()
        })
        registry.register(CommandDefinition(id: .fileNew, title: "New File") { ctx in
            ctx.coordinator.newDocument()
        })
        registry.register(CommandDefinition(id: .fileNewFromTemplate, title: "New from Template…") { $0.coordinator.newDocumentFromTemplate() })
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
        registry.register(CommandDefinition(id: .windowNextTab, title: "Next Tab") {
            $0.coordinator.selectNextTab()
        })
        registry.register(CommandDefinition(id: .windowPreviousTab, title: "Previous Tab") {
            $0.coordinator.selectPreviousTab()
        })
        registry.register(CommandDefinition(id: .fileClearRecoveryData, title: "Clear Recovery Data...") { ctx in
            ctx.coordinator.clearRecoveryData()
        })
        registry.register(CommandDefinition(id: .filePageSetup, title: "Page Setup…") { $0.coordinator.showPageSetup() })
        registry.register(CommandDefinition(id: .filePrint, title: "Print…") { $0.coordinator.printDocument() })
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
        registry.register(CommandDefinition(id: .searchGrepCurrentDocument, title: "Grep Current Document") { $0.coordinator.grepCurrentDocument() })
        registry.register(CommandDefinition(id: .searchGrepOpenDocuments, title: "Grep All Open Documents") { $0.coordinator.grepOpenDocuments() })
        registry.register(CommandDefinition(id: .searchRefineGrepResults, title: "Refine Grep Results") { $0.coordinator.refineGrepResults() })
        registry.register(CommandDefinition(id: .searchOutputGrepDocument, title: "Output Grep Results as Document") { $0.coordinator.outputGrepResultsAsDocument() })
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
        registry.register(CommandDefinition(id: .editMoveWordLeft, title: "Move Word Left") { $0.coordinator.moveWordLeft() })
        registry.register(CommandDefinition(id: .editMoveWordRight, title: "Move Word Right") { $0.coordinator.moveWordRight() })
        registry.register(CommandDefinition(id: .editMoveParagraphStart, title: "Move to Paragraph Start") { $0.coordinator.moveToParagraphStart() })
        registry.register(CommandDefinition(id: .editMoveParagraphEnd, title: "Move to Paragraph End") { $0.coordinator.moveToParagraphEnd() })
        registry.register(CommandDefinition(id: .editDeleteWordBackward, title: "Delete Word Backward") { $0.coordinator.deleteWordBackward() })
        registry.register(CommandDefinition(id: .editDeleteWordForward, title: "Delete Word Forward") { $0.coordinator.deleteWordForward() })
        registry.register(CommandDefinition(id: .editTitlecase, title: "Convert to Title Case") { $0.coordinator.performLineCommand(.titlecase) })
        registry.register(CommandDefinition(id: .editCompleteWord, title: "Complete Word") { $0.coordinator.showCompletions() })
        registry.register(CommandDefinition(id: .insertDateTime, title: "Date and Time") {
            $0.coordinator.insertDateTime()
        })
        registry.register(CommandDefinition(id: .insertPageBreak, title: "Page Break") {
            $0.coordinator.insertPageBreak()
        })
        registry.register(CommandDefinition(id: .viewToggleTableMode, title: "CSV/TSV Table Mode") { $0.coordinator.toggleTableMode() })
        registry.register(CommandDefinition(id: .navigateMarkerRed, title: "Toggle Red Marker") { $0.coordinator.toggleMarker(.red) })
        registry.register(CommandDefinition(id: .navigateMarkerYellow, title: "Toggle Yellow Marker") { $0.coordinator.toggleMarker(.yellow) })
        registry.register(CommandDefinition(id: .navigateMarkerBlue, title: "Toggle Blue Marker") { $0.coordinator.toggleMarker(.blue) })
        registry.register(CommandDefinition(id: .navigateNextMarker, title: "Next Marker") { $0.coordinator.nextMarker() })
        registry.register(CommandDefinition(id: .navigatePreviousMarker, title: "Previous Marker") { $0.coordinator.previousMarker() })
        registry.register(CommandDefinition(id: .navigateClearMarkers, title: "Clear Markers") { $0.coordinator.clearMarkers() })
        registry.register(CommandDefinition(id: .viewSplitVertical, title: "Split Editor Vertically") { $0.coordinator.splitEditorVertical() })
        registry.register(CommandDefinition(id: .viewSplitHorizontal, title: "Split Editor Horizontally") { $0.coordinator.splitEditorHorizontal() })
        registry.register(CommandDefinition(id: .viewCloseSplit, title: "Close Editor Split") { $0.coordinator.closeEditorSplit() })
        registry.register(CommandDefinition(id: .viewToggleLinkedScrolling, title: "Linked Editor Scrolling") { $0.coordinator.toggleLinkedEditorScrolling() })
        registry.register(CommandDefinition(id: .navigateCompareNextDocument, title: "Compare with Next Document") { $0.coordinator.compareWithNextDocument() })
        registry.register(CommandDefinition(id: .navigateNextDifference, title: "Next Difference") { $0.coordinator.nextDifference() })
        registry.register(CommandDefinition(id: .navigatePreviousDifference, title: "Previous Difference") { $0.coordinator.previousDifference() })
        registry.register(CommandDefinition(id: .navigateMergeDifferenceFromRight, title: "Accept Difference from Right") { $0.coordinator.mergeCurrentDifferenceFromRight() })
        registry.register(CommandDefinition(id: .navigateTagJump, title: "Jump to Tag…") { $0.coordinator.showTagJump() })
        registry.register(CommandDefinition(id: .navigateDirectTagJump, title: "Direct Tag Jump") { $0.coordinator.directTagJump() })
        registry.register(CommandDefinition(id: .navigateBackTagJump, title: "Back from Tag") { $0.coordinator.backTagJump() })
        registry.register(CommandDefinition(id: .navigateToggleBookmark, title: "Toggle Bookmark") { $0.coordinator.toggleBookmark() })
        registry.register(CommandDefinition(id: .navigateNextBookmark, title: "Next Bookmark") { $0.coordinator.nextBookmark() })
        registry.register(CommandDefinition(id: .navigatePreviousBookmark, title: "Previous Bookmark") { $0.coordinator.previousBookmark() })
        registry.register(CommandDefinition(id: .navigateClearBookmarks, title: "Clear Bookmarks") { $0.coordinator.clearBookmarks() })
        registry.register(CommandDefinition(id: .navigateToggleFold, title: "Toggle Fold") { $0.coordinator.toggleFold() })
        registry.register(CommandDefinition(id: .navigateBeginPartialOutline, title: "Edit Current Outline Region") { $0.coordinator.beginPartialOutlineEditing() })
        registry.register(CommandDefinition(id: .navigateEndPartialOutline, title: "Show Full Document") { $0.coordinator.endPartialOutlineEditing() })
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
