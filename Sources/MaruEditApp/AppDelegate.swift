import AppKit
import MaruEditCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    override init() {
        NSWindow.allowsAutomaticWindowTabbing = false
        super.init()
    }
    private let coordinator = AppCoordinator()
    private let keyBindings = KeyBindingManager(profile: .macOSStandard)
    private lazy var macroPermissionStore: MacroPermissionStore = {
        guard isUITestMode else { return MacroPermissionStore() }
        let suite = "network.tos.maruedit.MacroPermissionUITest.\(ProcessInfo.processInfo.processIdentifier)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return MacroPermissionStore(defaults: defaults)
    }()
    private lazy var macroManager: MacroManager = {
        let injected = ProcessInfo.processInfo.environment["MARUEDIT_MACRO_DIRECTORY"]
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
        return MacroManager(
            directory: injected ?? MacroManager.defaultDirectory,
            coordinator: coordinator, keyBindings: keyBindings,
            authorizer: MacroPermissionAuthorizer(store: macroPermissionStore))
    }()
    private lazy var externalCommandManager: ExternalCommandManager = {
        let injected = ProcessInfo.processInfo.environment["MARUEDIT_EXTERNAL_COMMANDS_CONFIGURATION"]
            .map { URL(fileURLWithPath: $0) }
        return ExternalCommandManager(
            configurationURL: injected ?? ExternalCommandManager.defaultConfigurationURL,
            coordinator: coordinator)
    }()
    private let isUITestMode = ProcessInfo.processInfo.environment["MARUEDIT_UI_TEST_MODE"] == "1"
    private var recentMenu: NSMenu!
    private var reopenWithEncodingMenu: NSMenu!
    private weak var classicWindowMenu: NSMenu?
    private var menuCustomizationWindowController: MenuCustomizationWindowController?
    private var userMenuWindowController: UserMenuConfigurationWindowController?
    private let userMenuStore = UserMenuConfigurationStore()
    private lazy var userMenuConfiguration = userMenuStore.load()
    private var clipboardTimer: Timer?
    private var benchmarkCommandTimer: Timer?
    private var languageObserver: NSObjectProtocol?
    private lazy var menuCustomizationStore: MenuCustomizationStore = {
        if isUITestMode {
            let suite = "network.tos.maruedit.MenuUITest.\(ProcessInfo.processInfo.processIdentifier)"
            let defaults = UserDefaults(suiteName: suite)!
            defaults.removePersistentDomain(forName: suite)
            return MenuCustomizationStore(defaults: defaults)
        }
        return MenuCustomizationStore()
    }()
    private lazy var menuCustomization = menuCustomizationStore.load()
    static let protectedCommandIDs: Set<CommandID> = [.appSettings, .viewCustomizeMenus]
    static let classicDefaultMenuPlacements: [String: Set<CommandID>] = [
        // Dynamic Recent/Encoding menus remain visible alongside File commands.
        "File": Set([
            "file.new", "file.open", "file.closeAndOpen", "file.save", "file.saveAs",
            "insert.fileContents", "file.print", "file.saveAndClose",
            "file.saveAllAndClose", "file.discardAllAndClose",
        ].map { CommandID($0) }),
        // AppKit supplies Undo/Redo/Cut/Copy/Paste/Select All in Edit.
        "Edit": Set([
            .editAppendCut, .editAppendCopy, .convertPipelineDialog,
            .editIndent, .editOutdent, .editSortLines,
            .editClipboardHistory, .editCompleteWord, .fileReload,
        ]),
        "View": Set([
            "view.toggleToolbar", "view.toggleFunctionKeys", "view.toggleStatusBar",
            "window.showFilesPane", "view.toggleOutputPane", "window.showSharedBrowserPane",
            "window.showOutlinePane", "view.toggleHeading", "view.toggleFoldMargin",
            "view.toggleLineNumbers", "view.toggleCurrentLineHighlight",
            "view.toggleRuler", "view.toggleSpellChecking",
            "window.showDocumentBrowserPane", "view.toggleWrap", "view.toggleTabStops",
            "view.toggleTabMode", "view.rulerInterval8",
            "view.toggleVerticalLayout", "view.toggleColumnLayout",
            "view.beginPartialEditing", "view.endPartialEditing", "navigate.toggleFold",
            "view.toggleFullScreen",
        ].map { CommandID($0) }),
        "Search": Set([
            "search.find", "search.findNext", "search.findPrevious", "search.replace",
            "search.toggleHighlight", "search.returnToStart", "search.goToLine",
            "navigate.documentStart", "navigate.documentEnd", "navigate.lastEdit",
            "search.nextEditMark", "search.previousEditMark", "navigate.previousCursor",
            "search.listMarks", "search.listColorLayers", "search.grepReplace", "search.grep",
            "highlight.outlineAnalysis",
            "highlight.nextLine", "highlight.previousLine", "highlight.selectLineArea",
            "highlight.temporary.configure", "highlight.temporary.apply",
            "highlight.temporary.remove", "highlight.temporary.clear",
            "highlight.temporary.select", "highlight.temporary.next",
            "highlight.temporary.previous",
        ].map { CommandID($0) }),
        "Window": Set([
            "window.tileVertical", "window.tileHorizontal", "window.cascade",
            "window.tileGrid", "window.minimizeAll", "view.splitHorizontal",
            "window.toggleCrossDocumentScrollLink", "navigate.compareNextDocument",
            "file.saveWorkspace", "file.openWorkspace", "window.alwaysOnTop",
            "window.showOutlinePane", "window.showFilesPane", "view.toggleOutputPane",
            "window.showSharedBrowserPane", "window.detachTab",
            "view.toggleTabMode",
        ].map { CommandID($0) }),
        "Macro": Set([
            "macro.toggleRecording", "macro.playRecording", "macro.saveRecording",
            "macro.reload", "macro.run", "macro.help",
            "app.macroMenu",
        ].map { CommandID($0) }),
        "Other": Set([
            "other.fileTypeProfiles", "app.settings", "other.keyAssignments",
            "view.customizeMenus", "navigate.tagJump", "navigate.directTagJump",
            "navigate.backTagJump", "insert.controlCode", "navigate.generateTags",
            "other.correctSpelling", "other.commandList", "file.toggleViewMode",
            "other.exportSettings", "help.checkUpdates", "app.help",
            "other.importSettings", "other.restoreSettings",
        ].map { CommandID($0) }),
    ]
    static let classicDefaultVisibleCommandIDs = Set(
        classicDefaultMenuPlacements.values.flatMap { $0 })

    func applicationDidFinishLaunching(_ notification: Notification) {
        languageObserver = NotificationCenter.default.addObserver(
            forName: AppLocalization.didChange, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.applyApplicationLanguageChange() }
        }
        coordinator.onShowMenuCustomization = { [weak self] in self?.showMenuCustomization() }
        coordinator.onShowMacroMenu = { [weak self] in
            guard let self else { return }
            self.macroManager.menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
        }
        coordinator.onSaveRecordedMacro = { [weak self] name, commands in
            self?.macroManager.saveRecording(name: name, commands: commands)
        }
        coordinator.onOpenMacroFolder = { [weak self] in self?.macroManager.openFolder() }
        coordinator.onReloadMacros = { [weak self] in self?.macroManager.reload() }
        coordinator.onShowUserMenuConfiguration = { [weak self] in self?.showUserMenuConfiguration() }
        EditorShortcuts.install(
            keyBindings: keyBindings,
            execute: { [coordinator] id in
                coordinator.commandRegistry.execute(id, context: CommandContext(coordinator: coordinator))
            },
            showStatus: { [coordinator] message, duration in
                coordinator.showStatusMessage(message, duration: duration)
            })
        coordinator.ensureWindowControllerReady(
            restoreSession: !isUITestMode && !BenchmarkProbe.isEnabled)
        if isUITestMode,
           let content = ProcessInfo.processInfo.environment["MARUEDIT_UI_TEST_CONTENT"] {
            let ranges = ProcessInfo.processInfo.environment["MARUEDIT_UI_TEST_SELECTIONS"]?
                .split(separator: ",").compactMap { token -> NSRange? in
                    let parts = token.split(separator: ":")
                    guard parts.count == 2, let location = Int(parts[0]), let length = Int(parts[1]) else { return nil }
                    return NSRange(location: location, length: length)
                } ?? []
            // Wait until AppKit has finished installing the window's first
            // responder; that transition otherwise collapses seeded multiple
            // selections to the primary range before an IME UI test starts.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [coordinator] in
                coordinator.prepareUITestDocument(content: content, selections: ranges)
            }
        }
        NSApp.activate(ignoringOtherApps: true)
        BenchmarkProbe.record(
            "launch-ready", detail: String(ProcessInfo.processInfo.processIdentifier))
        DispatchQueue.main.async { [weak self] in self?.startDeferredServices() }
        if BenchmarkProbe.isEnabled {
            benchmarkCommandTimer = Timer.scheduledTimer(
                withTimeInterval: 0.005, repeats: true
            ) { [coordinator] _ in
                MainActor.assumeIsolated {
                    BenchmarkProbe.consumeOpenRequests().forEach(coordinator.openFile)
                }
            }
        }
    }

    private func startDeferredServices() {
        buildMenu()
        macroManager.executionDidStart = { [coordinator] _ in
            coordinator.updateMacroActivity(isRunning: true)
        }
        macroManager.executionDidFinish = { [coordinator] _, _ in
            coordinator.updateMacroActivity(isRunning: false)
        }
        macroManager.reload()
        externalCommandManager.reload()
        coordinator.pollClipboard()
        clipboardTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.coordinator.pollClipboard() }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationWillTerminate(_ notification: Notification) {
        clipboardTimer?.invalidate()
        benchmarkCommandTimer?.invalidate()
        if let languageObserver { NotificationCenter.default.removeObserver(languageObserver) }
        if !isUITestMode { coordinator.saveActiveSession() }
    }

    func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        guard !isUITestMode else { return false }
        coordinator.openFile(URL(fileURLWithPath: filename))
        return true
    }

    // MARK: - Menu bar

    func buildMenu() {
        // AppKit retains its Services and Windows menu relationships across
        // assignments, so detach them before rebuilding for a new language.
        NSApp.servicesMenu = nil
        NSApp.windowsMenu = nil
        let main = NSMenu()
        func cloneMenu(_ source: NSMenu) -> NSMenu {
            let copy = NSMenu(title: source.title)
            for sourceItem in source.items {
                if sourceItem.isSeparatorItem { copy.addItem(.separator()); continue }
                let item = NSMenuItem(
                    title: sourceItem.title, action: sourceItem.action,
                    keyEquivalent: sourceItem.keyEquivalent)
                item.target = sourceItem.target
                item.representedObject = sourceItem.representedObject
                item.isEnabled = sourceItem.isEnabled
                if let submenu = sourceItem.submenu { item.submenu = cloneMenu(submenu) }
                copy.addItem(item)
            }
            return copy
        }

        // App menu
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: AppLocalization.string("app.about"), action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(commandItem(.appSettings))
        appMenu.addItem(.separator())
        let servicesItem = NSMenuItem(title: AppLocalization.string("app.services"), action: nil, keyEquivalent: "")
        servicesItem.identifier = NSUserInterfaceItemIdentifier("menu.dynamic.services")
        let servicesMenu = NSMenu(title: servicesItem.title)
        servicesItem.submenu = servicesMenu
        appMenu.addItem(servicesItem)
        NSApp.servicesMenu = servicesMenu
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: AppLocalization.string("app.hide"), action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = appMenu.addItem(
            withTitle: AppLocalization.string("app.hideOthers"), action: #selector(NSApplication.hideOtherApplications(_:)),
            keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(withTitle: AppLocalization.string("app.showAll"), action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: AppLocalization.string("app.quit"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        // File menu
        let fileItem = NSMenuItem()
        let fileMenu = NSMenu(title: AppLocalization.string("menu.top.file"))
        fileMenu.addItem(commandItem(.fileNew))
        fileMenu.addItem(commandItem(.fileNewFromTemplate))
        fileMenu.addItem(commandItem(.fileOpen))
        fileMenu.addItem(commandItem(.fileOpenFolder))
        fileMenu.addItem(commandItem(.fileOpenPartial))
        fileMenu.addItem(commandItem(.fileOpenBinary))
        fileMenu.addItem(commandItem(.viewWebBrowseMode))
        fileMenu.addItem(commandItem(.fileProjectHistory))
        fileMenu.addItem(commandItem(.fileOpenWorkspace))
        fileMenu.addItem(commandItem(.fileSaveWorkspace))
        fileMenu.addItem(commandItem(.fileCloseWorkspace))
        fileMenu.addItem(commandItem(.fileWorkspaceHistory))

        recentMenu = NSMenu(title: AppLocalization.string("menu.file.openRecent"))
        recentMenu.delegate = self
        let recentItem = NSMenuItem(title: AppLocalization.string("menu.file.openRecent"), action: nil, keyEquivalent: "")
        recentItem.submenu = recentMenu
        recentItem.identifier = NSUserInterfaceItemIdentifier("menu.dynamic.openRecent")
        fileMenu.addItem(recentItem)

        reopenWithEncodingMenu = NSMenu(title: AppLocalization.string("menu.file.encoding"))
        reopenWithEncodingMenu.delegate = self
        let reopenItem = NSMenuItem(title: AppLocalization.string("menu.file.encoding"), action: nil, keyEquivalent: "")
        reopenItem.submenu = reopenWithEncodingMenu
        reopenItem.identifier = NSUserInterfaceItemIdentifier("menu.dynamic.reopenEncoding")
        fileMenu.addItem(reopenItem)
        fileMenu.addItem(commandItem(.fileReload))
        fileMenu.addItem(commandItem(.fileToggleViewMode))
        fileMenu.addItem(commandItem(.fileToggleOverwriteProtection))
        fileMenu.addItem(commandItem(.fileProperties))
        fileMenu.addItem(commandItem(.fileRename))

        fileMenu.addItem(.separator())
        fileMenu.addItem(commandItem(.fileSave))
        fileMenu.addItem(commandItem(.fileSaveAs))
        fileMenu.addItem(commandItem(.fileSaveAll))
        fileMenu.addItem(commandItem(.fileSaveAllModified))
        fileMenu.addItem(commandItem(.fileSaveLF))
        fileMenu.addItem(commandItem(.fileSaveAndClose))
        fileMenu.addItem(commandItem(.fileSaveAllAndClose))
        fileMenu.addItem(commandItem(.fileDiscardAndClose))
        fileMenu.addItem(commandItem(.fileDiscardAllAndClose))
        fileMenu.addItem(commandItem(.fileAppendSave))
        fileMenu.addItem(commandItem(.fileAppendRead))
        fileMenu.addItem(commandItem(.insertFileContents))
        fileMenu.addItem(.separator())
        fileMenu.addItem(commandItem(.fileOpenCursorTargetAssociated))
        fileMenu.addItem(commandItem(.fileOpenCursorTargetInEditor))
        fileMenu.addItem(.separator())
        fileMenu.addItem(commandItem(.fileCloseAndOpen))
        fileMenu.addItem(commandItem(.fileCloseTab))
        fileMenu.addItem(.separator())
        fileMenu.addItem(commandItem(.filePageSetup))
        fileMenu.addItem(commandItem(.filePrint))
        fileMenu.addItem(.separator())
        fileMenu.addItem(commandItem(.fileClearRecoveryData))
        fileMenu.addItem(commandItem(.fileToggleHistoryRecording))
        fileItem.submenu = fileMenu
        main.addItem(fileItem)

        // Edit menu
        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: AppLocalization.string("menu.top.edit"))
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(commandItem(.editRepeatLastOperation))
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenu.addItem(commandItem(.editCopyQuoted))
        editMenu.addItem(commandItem(.editPasteQuoted))
        editMenu.addItem(commandItem(.editClipboardHistory))
        editMenu.addItem(commandItem(.editPastePreviousClipboard))
        editMenu.addItem(commandItem(.editBoxPaste))
        editMenu.addItem(commandItem(.editAppendCopy))
        editMenu.addItem(commandItem(.editAppendCut))
        editMenu.addItem(commandItem(.editRestoreDeletion))
        editMenu.addItem(commandItem(.editCorrectCapsLock))
        editMenu.addItem(commandItem(.editReconvert))
        editMenu.addItem(commandItem(.editDeleteWordAll))
        editMenu.addItem(commandItem(.editCopyWord))
        editMenu.addItem(commandItem(.editCutWord))
        editMenu.addItem(commandItem(.editCopyLine))
        editMenu.addItem(commandItem(.editCutLine))
        editMenu.addItem(commandItem(.editCutToLineEnd))
        editMenu.addItem(commandItem(.editClearUndoBuffer))
        editMenu.addItem(.separator())
        editMenu.addItem(commandItem(.editSelectWord))
        editMenu.addItem(commandItem(.editSelectLine))
        editMenu.addItem(commandItem(.editSelectParagraph))
        editMenu.addItem(commandItem(.editAddCursorAbove))
        editMenu.addItem(commandItem(.editAddCursorBelow))
        editMenu.addItem(commandItem(.editSelectNextOccurrence))
        editMenu.addItem(commandItem(.editSelectAllOccurrences))
        editMenu.addItem(commandItem(.editUndoLastAddedCursor))
        editMenu.addItem(commandItem(.editBeginColumnSelection))
        editMenu.addItem(commandItem(.editInvertSelections))
        editMenu.addItem(commandItem(.editReserveSelections))
        editMenu.addItem(commandItem(.editRestoreReservedSelections))
        editMenu.addItem(.separator())
        let linesItem = NSMenuItem(title: AppLocalization.string("menu.edit.lines"), action: nil, keyEquivalent: "")
        let linesMenu = NSMenu(title: AppLocalization.string("menu.edit.lines"))
        for id: CommandID in [
            .editDeleteLine, .editDuplicateLine, .editMoveLineUp, .editMoveLineDown,
            .editJoinLines, .editTrimTrailingWhitespace,
            .editSortLines, .editReverseLines, .editIndent, .editOutdent, .editToggleComment,
        ] { linesMenu.addItem(commandItem(id)) }
        linesItem.submenu = linesMenu
        linesItem.identifier = NSUserInterfaceItemIdentifier("menu.group.lines")
        editMenu.addItem(linesItem)
        editMenu.addItem(commandItem(.editToggleInputMode))
        for id: CommandID in [
            .editMoveWordLeft, .editMoveWordRight, .editMoveParagraphStart,
            .editMoveParagraphEnd, .editDeleteWordBackward, .editDeleteWordForward,
            .editCompleteWord,
        ] { editMenu.addItem(commandItem(id)) }
        editMenu.addItem(commandItem(.editDeleteToLineStart))
        editMenu.addItem(commandItem(.editDeleteToLineEnd))
        editMenu.addItem(.separator())
        editMenu.addItem(commandItem(.navigateToggleFold))
        editMenu.addItem(commandItem(.navigateCollapseAllFolds))
        editMenu.addItem(commandItem(.navigateExpandAllFolds))
        editMenu.addItem(commandItem(.navigateBeginPartialOutline))
        editMenu.addItem(commandItem(.navigateEndPartialOutline))
        editMenu.addItem(.separator())
        editMenu.addItem(commandItem(.insertTemplate))
        editMenu.addItem(commandItem(.searchFind))
        editMenu.addItem(commandItem(.searchReplace))
        editMenu.addItem(commandItem(.fileReload))
        editItem.submenu = editMenu
        main.addItem(editItem)

        // Search menu
        let findItem = NSMenuItem()
        let findMenu = NSMenu(title: AppLocalization.string("menu.top.search"))
        findMenu.addItem(commandItem(.searchFind))
        findMenu.addItem(commandItem(.searchFindUpward))
        findMenu.addItem(commandItem(.searchFindWord))
        findMenu.addItem(commandItem(.searchReplace))
        findMenu.addItem(commandItem(.searchReplaceAll))
        findMenu.addItem(commandItem(.searchFindNext))
        findMenu.addItem(commandItem(.searchFindPrevious))
        findMenu.addItem(commandItem(.searchReturnToStart))
        findMenu.addItem(commandItem(.searchCaptureString))
        let allMatchesItem = NSMenuItem(title: AppLocalization.string("menu.search.allMatches"), action: nil, keyEquivalent: "")
        let allMatchesMenu = NSMenu(title: AppLocalization.string("menu.search.allMatches"))
        for id: CommandID in [
            .searchToggleHighlight, .searchSelectAllMatches, .searchColorAllMatches,
            .searchClearMatchColors, .searchListAllMatches, .searchOutlineAllMatches,
        ] { allMatchesMenu.addItem(commandItem(id)) }
        allMatchesItem.submenu = allMatchesMenu
        findMenu.addItem(allMatchesItem)
        let optionsItem = NSMenuItem(title: AppLocalization.string("menu.search.options"), action: nil, keyEquivalent: "")
        let optionsMenu = NSMenu(title: AppLocalization.string("menu.search.options"))
        optionsMenu.addItem(commandItem(.searchToggleCaseSensitive))
        optionsMenu.addItem(commandItem(.searchToggleWholeWord))
        optionsMenu.addItem(commandItem(.searchToggleRegex))
        optionsMenu.addItem(commandItem(.searchToggleFuzzy))
        optionsItem.submenu = optionsMenu
        findMenu.addItem(optionsItem)
        let editMarksItem = NSMenuItem(title: AppLocalization.string("menu.search.editMarks"), action: nil, keyEquivalent: "")
        let editMarksMenu = NSMenu(title: AppLocalization.string("menu.search.editMarks"))
        editMarksMenu.addItem(commandItem(.searchPreviousEditMark))
        editMarksMenu.addItem(commandItem(.searchNextEditMark))
        editMarksMenu.addItem(commandItem(.searchClearEditMarks))
        editMarksItem.submenu = editMarksMenu
        findMenu.addItem(editMarksItem)
        let rangeItem = NSMenuItem(title: AppLocalization.string("menu.search.range"), action: nil, keyEquivalent: "")
        let rangeMenu = NSMenu(title: AppLocalization.string("menu.search.range"))
        rangeMenu.addItem(commandItem(.searchSetRange))
        rangeMenu.addItem(commandItem(.searchSelectRange))
        rangeMenu.addItem(commandItem(.searchClearRange))
        rangeItem.submenu = rangeMenu
        findMenu.addItem(rangeItem)
        findMenu.addItem(.separator())
        // Go to Line moves off ⌘G, which macOS reserves for Find Next.
        findMenu.addItem(commandItem(.searchGoToLine))
        let cursorItem = NSMenuItem(title: AppLocalization.string("menu.search.cursorNavigation"), action: nil, keyEquivalent: "")
        let cursorMenu = NSMenu(title: AppLocalization.string("menu.search.cursorNavigation"))
        for id: CommandID in [
            .navigateDocumentStart, .navigateDocumentEnd,
            .navigateScreenStart, .navigateScreenEnd,
            .editMoveWordRight, .navigateWordRightSalnen, .editMoveWordLeft,
            .navigateWordStart, .navigateWordEnd,
            .navigateLineStart, .navigateLineEnd, .navigateLineEndAfterCharacter,
            .navigateLogicalLineStart, .navigateLogicalLineEnd,
            .navigateNextPage, .navigatePreviousPage,
            .navigateHalfNextPage, .navigateHalfPreviousPage,
            .navigateScrollUp, .navigateScrollDown,
            .navigateScrollUp2, .navigateScrollDown2,
            .navigatePreviousTabStop, .navigateNextTabStop,
            .navigateMatchingBracket, .navigateOpeningBrace, .navigateClosingBrace,
            .navigateMatchingTag, .navigateLastEdit, .navigatePreviousCursor,
        ] { cursorMenu.addItem(commandItem(id)) }
        cursorItem.submenu = cursorMenu
        findMenu.addItem(cursorItem)
        findMenu.addItem(.separator())
        for id: CommandID in [
            .searchToggleMark, .searchListMarks, .navigateNextMarker, .navigatePreviousMarker,
            .searchClearAllMarks, .searchClearCurrentMarks, .searchListColorLayers,
        ] { findMenu.addItem(commandItem(id)) }
        let searchColorMarkerItem = NSMenuItem(title: AppLocalization.string("menu.search.colorMarker"), action: nil, keyEquivalent: "")
        let searchColorMarkerMenu = NSMenu(title: AppLocalization.string("menu.search.colorMarker"))
        for id: CommandID in [
            .highlightTemporaryConfigure, .highlightTemporaryApply, .highlightTemporaryRemove,
            .highlightTemporaryClear, .highlightTemporarySelect,
            .highlightTemporaryNext, .highlightTemporaryPrevious,
        ] { searchColorMarkerMenu.addItem(commandItem(id)) }
        searchColorMarkerItem.submenu = searchColorMarkerMenu
        findMenu.addItem(searchColorMarkerItem)
        for id: CommandID in [
            .searchNextResult, .searchPreviousResult, .searchNextGrepResult, .searchPreviousGrepResult,
        ] { findMenu.addItem(commandItem(id)) }
        findMenu.addItem(.separator())
        findMenu.addItem(commandItem(.searchQuickOpen))
        findMenu.addItem(commandItem(.searchGrepReplace))
        findMenu.addItem(commandItem(.searchGrep))
        findMenu.addItem(commandItem(.searchGrepCurrentDocument))
        findMenu.addItem(commandItem(.searchGrepOpenDocuments))
        findMenu.addItem(commandItem(.searchRefineGrepResults))
        findMenu.addItem(commandItem(.searchOutputGrepDocument))
        findMenu.addItem(.separator())
        findMenu.addItem(commandItem(.searchClearHistory))
        findItem.submenu = findMenu
        main.addItem(findItem)

        let toolsItem = NSMenuItem(title: AppLocalization.string("menu.other.tools"), action: nil, keyEquivalent: "")
        let toolsMenu = NSMenu(title: AppLocalization.string("menu.other.tools"))
        for index in 0..<UserMenuConfiguration.menuCount {
            let item = NSMenuItem(title: AppLocalization.string("settings.userMenus.number", [index + 1]), action: nil, keyEquivalent: "")
            item.submenu = buildUserMenu(at: index)
            toolsMenu.addItem(item)
        }
        toolsMenu.addItem(commandItem(.toolsConfigureUserMenus))
        toolsMenu.addItem(.separator())
        for id: CommandID in [
            .helpExternal1, .helpExternal2, .helpExternal3,
            .helpExternal4, .helpExternal5, .helpExternal6,
        ] { toolsMenu.addItem(commandItem(id)) }
        toolsMenu.addItem(commandItem(.toolsOpenFinder))
        toolsMenu.addItem(commandItem(.macroOpenFolder))
        toolsMenu.addItem(.separator())
        toolsMenu.addItem(commandItem(.navigateCompareNextDocument))
        toolsMenu.addItem(commandItem(.navigateNextDifference))
        toolsMenu.addItem(commandItem(.navigatePreviousDifference))
        toolsMenu.addItem(commandItem(.navigateMergeDifferenceFromRight))
        toolsMenu.addItem(.separator())
        toolsMenu.addItem(commandItem(.navigateGenerateTags))
        toolsMenu.addItem(commandItem(.navigateTagJump))
        toolsMenu.addItem(commandItem(.navigateDirectTagJump))
        toolsMenu.addItem(commandItem(.navigateBackTagJump))
        toolsMenu.addItem(.separator())
        let externalItem = NSMenuItem(title: AppLocalization.string("menu.other.externalCommands"), action: nil, keyEquivalent: "")
        externalItem.submenu = cloneMenu(externalCommandManager.menu)
        toolsMenu.addItem(externalItem)
        toolsMenu.addItem(commandItem(.otherCommandList))
        toolsMenu.addItem(.separator())
        toolsMenu.addItem(commandItem(.otherExportSettings))
        toolsMenu.addItem(commandItem(.otherFileTypeProfiles))
        toolsMenu.addItem(commandItem(.appSettings))
        toolsMenu.addItem(commandItem(.otherKeyAssignments))
        toolsMenu.addItem(commandItem(.viewCustomizeMenus))
        toolsMenu.addItem(commandItem(.otherClearAllHistories))
        toolsItem.submenu = toolsMenu
        main.addItem(toolsItem)

        let macroItem = NSMenuItem(title: AppLocalization.string("menu.top.macro"), action: nil, keyEquivalent: "")
        let macroMenu = NSMenu(title: AppLocalization.string("menu.top.macro"))
        macroMenu.addItem(commandItem(.macroToggleRecording))
        macroMenu.addItem(commandItem(.macroPlayRecording))
        macroMenu.addItem(commandItem(.macroRepeatPlayback))
        macroMenu.addItem(commandItem(.macroSaveRecording))
        macroMenu.addItem(.separator())
        macroMenu.addItem(commandItem(.macroRun))
        let registeredMacros = NSMenuItem(title: AppLocalization.string("menu.macro.registered"), action: nil, keyEquivalent: "")
        registeredMacros.identifier = NSUserInterfaceItemIdentifier("menu.dynamic.registeredMacros")
        registeredMacros.submenu = macroManager.menu
        macroMenu.addItem(registeredMacros)
        macroMenu.addItem(commandItem(.macroReload))
        macroMenu.addItem(commandItem(.macroOpenFolder))
        macroMenu.addItem(commandItem(.macroHelp))
        macroItem.submenu = macroMenu
        main.addItem(macroItem)

        // View menu
        let viewItem = NSMenuItem()
        let viewMenu = NSMenu(title: AppLocalization.string("menu.top.view"))
        viewMenu.addItem(commandItem(.viewToggleToolbar))
        viewMenu.addItem(commandItem(.viewToggleFloatingToolbar))
        viewMenu.addItem(commandItem(.viewToggleSidebar))
        viewMenu.addItem(commandItem(.viewToggleWrap))
        viewMenu.addItem(commandItem(.viewToggleTableMode))
        viewMenu.addItem(commandItem(.viewToggleVerticalLayout))
        viewMenu.addItem(commandItem(.viewToggleColumnLayout))
        for id: CommandID in [
            .viewToggleLineNumbers, .viewToggleCurrentLineHighlight, .viewToggleHeading, .viewToggleFunctionKeys,
            .viewToggleStatusBar, .viewToggleOutputPane, .viewFocusOutputPane,
            .viewToggleFoldMargin, .viewBeginPartialEditing, .viewEndPartialEditing,
            .viewWebBrowseMode,
            .windowShowFilesPane, .windowShowOutlinePane,
            .windowShowDocumentBrowserPane, .windowShowSharedBrowserPane,
            .windowToggleBrowserPane,
        ] { viewMenu.addItem(commandItem(id)) }
        let rulerItem = NSMenuItem(title: AppLocalization.string("menu.view.ruler"), action: nil, keyEquivalent: "")
        let rulerMenu = NSMenu(title: AppLocalization.string("menu.view.ruler"))
        rulerMenu.addItem(commandItem(.viewToggleRuler))
        rulerMenu.addItem(commandItem(.viewRulerInterval8))
        rulerMenu.addItem(commandItem(.viewRulerInterval10))
        rulerMenu.addItem(commandItem(.viewToggleTabStops))
        rulerItem.submenu = rulerMenu
        viewMenu.addItem(rulerItem)
        let invisiblesItem = NSMenuItem(title: AppLocalization.string("menu.view.invisibles"), action: nil, keyEquivalent: "")
        let invisiblesMenu = NSMenu(title: AppLocalization.string("menu.view.invisibles"))
        invisiblesMenu.addItem(commandItem(.viewToggleSpaces))
        invisiblesMenu.addItem(commandItem(.viewToggleTabs))
        invisiblesMenu.addItem(commandItem(.viewToggleLineEndings))
        invisiblesMenu.addItem(commandItem(.viewToggleFullWidthSpaces))
        invisiblesItem.submenu = invisiblesMenu
        invisiblesItem.identifier = NSUserInterfaceItemIdentifier("menu.group.invisibles")
        viewMenu.addItem(invisiblesItem)
        viewMenu.addItem(commandItem(.viewToggleSpellChecking))
        let tabWidthItem = NSMenuItem(title: AppLocalization.string("menu.view.tabWidth"), action: nil, keyEquivalent: "")
        let tabWidthMenu = NSMenu(title: AppLocalization.string("menu.view.tabWidth"))
        tabWidthMenu.addItem(commandItem(.viewTabWidth2))
        tabWidthMenu.addItem(commandItem(.viewTabWidth4))
        tabWidthMenu.addItem(commandItem(.viewTabWidth8))
        tabWidthItem.submenu = tabWidthMenu
        tabWidthItem.identifier = NSUserInterfaceItemIdentifier("menu.group.tabWidth")
        viewMenu.addItem(tabWidthItem)
        viewMenu.addItem(.separator())
        viewMenu.addItem(commandItem(.viewShowFonts))
        viewMenu.addItem(commandItem(.viewShowCharacterCode))
        viewMenu.addItem(commandItem(.viewShowCharacterCount))
        viewMenu.addItem(commandItem(.viewRedraw))
        viewMenu.addItem(commandItem(.viewToggleFullScreen))
        viewMenu.addItem(.separator())
        viewMenu.addItem(commandItem(.viewCustomizeMenus))
        viewMenu.addItem(commandItem(.viewSplitVertical))
        viewMenu.addItem(commandItem(.viewSplitHorizontal))
        viewMenu.addItem(commandItem(.viewCloseSplit))
        viewMenu.addItem(commandItem(.viewToggleLinkedScrolling))
        viewMenu.addItem(commandItem(.navigateCompareNextDocument))
        viewMenu.addItem(commandItem(.navigateNextDifference))
        viewMenu.addItem(commandItem(.navigatePreviousDifference))
        viewMenu.addItem(commandItem(.navigateMergeDifferenceFromRight))
        viewMenu.addItem(.separator())
        viewMenu.addItem(commandItem(.navigateTagJump))
        viewMenu.addItem(commandItem(.navigateDirectTagJump))
        viewMenu.addItem(commandItem(.navigateBackTagJump))
        viewItem.submenu = viewMenu
        main.addItem(viewItem)

        // Window menu
        let winItem = NSMenuItem()
        let winMenu = NSMenu(title: AppLocalization.string("menu.top.window"))
        winMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.miniaturize(_:)), keyEquivalent: "m")
        winMenu.addItem(withTitle: "Zoom", action: #selector(NSWindow.zoom(_:)), keyEquivalent: "")
        winMenu.addItem(.separator())
        for id: CommandID in [
            .windowTileVertical, .windowTileHorizontal, .windowCascade, .windowTileGrid,
            .windowMinimizeAll, .viewSplitHorizontal, .viewSplitVertical,
            .viewCloseSplit, .viewToggleLinkedScrolling,
            .navigateCompareNextDocument, .navigateNextDifference, .navigatePreviousDifference,
            .fileSaveWorkspace, .fileOpenWorkspace,
            .fileCloseWorkspace,
            .windowAlwaysOnTop, .windowFullScreen,
            .windowShowOutlinePane, .windowShowFilesPane,
            .windowShowDocumentBrowserPane, .windowShowSharedBrowserPane,
            .windowToggleBrowserPane, .windowFocusBrowserPane,
            .windowToggleCrossDocumentScrollLink,
            .viewToggleOutputPane, .viewFocusOutputPane, .windowFocusUtilityPane,
        ] { winMenu.addItem(commandItem(id)) }
        winMenu.addItem(.separator())
        winMenu.addItem(commandItem(.windowNextTab))
        winMenu.addItem(commandItem(.windowPreviousTab))
        winMenu.addItem(commandItem(.windowTabList))
        winMenu.addItem(.separator())
        winMenu.addItem(commandItem(.windowCloseOtherTabs))
        winMenu.addItem(commandItem(.windowCloseTabsLeft))
        winMenu.addItem(commandItem(.windowCloseTabsRight))
        winMenu.addItem(commandItem(.windowDetachTab))
        winMenu.addItem(commandItem(.windowMinimizeTab))
        for id: CommandID in [
            .windowNextManaged, .windowPreviousManaged,
            .windowNextManagedIncludingMinimized, .windowPreviousManagedIncludingMinimized,
            .windowPreviousActive,
        ] { winMenu.addItem(commandItem(id)) }
        winMenu.addItem(.separator())
        winMenu.addItem(commandItem(.windowFocusEditor))
        winMenu.addItem(commandItem(.windowFocusUtilityPane))
        winItem.submenu = winMenu
        main.addItem(winItem)

        // Maru-compatible business-menu groups. macOS keeps its required
        // application menu before this sequence.
        let convertItem = NSMenuItem()
        let convertMenu = NSMenu(title: AppLocalization.string("menu.edit.convert"))
        convertMenu.addItem(commandItem(.convertPipelineDialog))
        convertMenu.addItem(.separator())
        for id: CommandID in [.editUppercase, .editLowercase, .editTitlecase] {
            convertMenu.addItem(commandItem(id))
        }
        convertMenu.addItem(.separator())
        for id: CommandID in [
            .convertHalfWidth, .convertFullWidth, .convertHiragana, .convertKatakana,
            .convertHalfWidthAlphanumeric, .convertFullWidthAlphanumeric,
            .convertHalfWidthKatakana, .convertFullWidthKatakana,
            .convertTabsToSpaces, .convertSpacesToTabs,
            .editIndent, .editOutdent, .editSortLines,
        ] { convertMenu.addItem(commandItem(id)) }
        convertItem.submenu = convertMenu

        let insertItem = NSMenuItem()
        let insertMenu = NSMenu(title: AppLocalization.string("menu.group.insert"))
        insertMenu.addItem(commandItem(.insertDateTime))
        insertMenu.addItem(commandItem(.insertNewline))
        insertMenu.addItem(commandItem(.insertTab))
        insertMenu.addItem(commandItem(.insertPageBreak))
        insertMenu.addItem(commandItem(.editDuplicateLine))
        insertMenu.addItem(commandItem(.insertBlankLine))
        insertMenu.addItem(commandItem(.insertControlCode))
        insertMenu.addItem(commandItem(.editRestoreDeletion))
        insertMenu.addItem(commandItem(.insertCurrentFileName))
        insertMenu.addItem(commandItem(.insertFileContents))
        insertMenu.addItem(commandItem(.insertTemplate))
        insertItem.submenu = insertMenu

        let highlightItem = NSMenuItem()
        let highlightMenu = NSMenu(title: AppLocalization.string("menu.group.highlight"))
        highlightMenu.addItem(commandItem(.highlightOutlineAnalysis))
        highlightMenu.addItem(commandItem(.highlightNextLine))
        highlightMenu.addItem(commandItem(.highlightPreviousLine))
        highlightMenu.addItem(commandItem(.highlightSelectLineArea))
        highlightMenu.addItem(.separator())
        let temporaryMarkerItem = NSMenuItem(title: AppLocalization.string("menu.view.temporaryMarker"), action: nil, keyEquivalent: "")
        let temporaryMarkerMenu = NSMenu(title: AppLocalization.string("menu.view.temporaryMarker"))
        for id: CommandID in [
            .highlightTemporaryConfigure, .highlightTemporaryApply, .highlightTemporaryRemove,
            .highlightTemporaryClear, .highlightTemporarySelect,
            .highlightTemporaryNext, .highlightTemporaryPrevious,
        ] { temporaryMarkerMenu.addItem(commandItem(id)) }
        temporaryMarkerItem.submenu = temporaryMarkerMenu
        highlightMenu.addItem(temporaryMarkerItem)
        highlightMenu.addItem(.separator())
        for id: CommandID in [
            .navigateMarkerRed, .navigateMarkerYellow, .navigateMarkerBlue,
            .navigateNextMarker, .navigatePreviousMarker, .navigateHighlightList,
            .navigateClearMarkers,
        ] { highlightMenu.addItem(commandItem(id)) }
        highlightItem.submenu = highlightMenu

        let bookmarkItem = NSMenuItem()
        let bookmarkMenu = NSMenu(title: AppLocalization.string("menu.group.bookmark"))
        for id: CommandID in [
            .navigateToggleBookmark, .navigateNextBookmark,
            .navigatePreviousBookmark, .navigateBookmarkList, .navigateClearBookmarks,
        ] { bookmarkMenu.addItem(commandItem(id)) }
        bookmarkItem.submenu = bookmarkMenu

        let otherItem = NSMenuItem()
        let otherMenu = NSMenu(title: AppLocalization.string("menu.top.other"))
        otherMenu.addItem(commandItem(.appSettings))
        otherMenu.addItem(commandItem(.otherFileTypeProfiles))
        otherMenu.addItem(commandItem(.otherKeyAssignments))
        otherMenu.addItem(commandItem(.otherCommandList))
        otherMenu.addItem(commandItem(.viewShowFonts))
        otherMenu.addItem(commandItem(.viewCustomizeMenus))
        otherMenu.addItem(commandItem(.navigateTagJump))
        otherMenu.addItem(commandItem(.navigateDirectTagJump))
        otherMenu.addItem(commandItem(.navigateBackTagJump))
        otherMenu.addItem(commandItem(.insertControlCode))
        otherMenu.addItem(commandItem(.navigateGenerateTags))
        otherMenu.addItem(commandItem(.otherCorrectSpelling))
        otherMenu.addItem(commandItem(.fileToggleViewMode))
        otherMenu.addItem(commandItem(.fileToggleOverwriteProtection))
        otherMenu.addItem(commandItem(.otherToggleFreeCursor))
        otherMenu.addItem(commandItem(.viewToggleVerticalLayout))
        otherMenu.addItem(commandItem(.viewToggleColumnLayout))
        let settingsTransferItem = NSMenuItem(title: AppLocalization.string("menu.other.settingsTransferHeading"), action: nil, keyEquivalent: "")
        let settingsTransferMenu = NSMenu(title: AppLocalization.string("menu.other.settingsTransferHeading"))
        settingsTransferMenu.addItem(commandItem(.otherExportSettings))
        settingsTransferMenu.addItem(commandItem(.otherImportSettings))
        settingsTransferMenu.addItem(.separator())
        settingsTransferMenu.addItem(commandItem(.otherRestoreSettings))
        settingsTransferItem.submenu = settingsTransferMenu
        otherMenu.addItem(settingsTransferItem)
        otherMenu.addItem(commandItem(.otherJapaneseUserDictionary))
        otherMenu.addItem(.separator())
        let clearHistoryItem = NSMenuItem(title: AppLocalization.string("menu.other.clearHistory"), action: nil, keyEquivalent: "")
        let clearHistoryMenu = NSMenu(title: AppLocalization.string("menu.other.clearHistory"))
        for id: CommandID in [
            .otherClearFindHistory, .otherClearReplaceHistory, .otherClearGrepHistory,
            .otherClearClipboardHistory, .otherClearRecentFiles, .otherClearRecentFolders,
            .otherClearRecentWorkspaces, .otherClearRecentEncodings,
        ] { clearHistoryMenu.addItem(commandItem(id)) }
        clearHistoryMenu.addItem(.separator())
        clearHistoryMenu.addItem(commandItem(.otherClearAllHistories))
        clearHistoryItem.submenu = clearHistoryMenu
        otherMenu.addItem(clearHistoryItem)
        otherMenu.addItem(.separator())
        otherMenu.addItem(commandItem(.helpCheckUpdates))
        otherMenu.addItem(commandItem(.appHelp))
        otherMenu.addItem(commandItem(.helpMacros))
        otherItem.submenu = otherMenu

        let helpItem = NSMenuItem()
        let helpMenu = NSMenu(title: AppLocalization.string("menu.group.help"))
        helpMenu.addItem(commandItem(.appHelp))
        helpMenu.addItem(commandItem(.helpMacros))
        helpMenu.addItem(commandItem(.helpShortcuts))
        helpMenu.addItem(.separator())
        for id: CommandID in [
            .helpExternal1, .helpExternal2, .helpExternal3,
            .helpExternal4, .helpExternal5, .helpExternal6,
        ] { helpMenu.addItem(commandItem(id)) }
        helpMenu.addItem(commandItem(.helpConfigureExternal))
        helpMenu.addItem(.separator())
        helpMenu.addItem(commandItem(.helpCheckUpdates))
        helpMenu.addItem(commandItem(.helpSupport))
        helpMenu.addItem(.separator())
        helpMenu.addItem(withTitle: "About MaruEdit", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        helpItem.submenu = helpMenu

        // The default seven-menu presentation is intentionally compact and
        // follows the locally recorded classic menu screenshots. Items not
        // selected here remain in their original menu and can be restored by
        // the menu editor.
        func take(_ id: CommandID, from menu: NSMenu) -> NSMenuItem {
            let item = menu.items.first { $0.representedObject as? CommandID == id }
                ?? commandItem(id)
            item.menu?.removeItem(item)
            return item
        }
        func titled(_ id: CommandID, from menu: NSMenu) -> NSMenuItem {
            let item = take(id, from: menu)
            let english = coordinator.commandRegistry.definition(for: id)?.title ?? item.title
            item.title = AppLocalization.classicCommandTitle(id: id.rawValue, english: english)
            return item
        }
        func preserveExtendedItems(_ oldItems: [NSMenuItem], in menu: NSMenu) {
            func commandIDs(in items: [NSMenuItem]) -> Set<CommandID> {
                Set(items.flatMap { item -> [CommandID] in
                    let own = (item.representedObject as? CommandID).map { [$0] } ?? []
                    return own + (item.submenu.map { Array(commandIDs(in: $0.items)) } ?? [])
                })
            }
            let existingIDs = commandIDs(in: menu.items)
            func pruneDuplicates(from item: NSMenuItem) -> Bool {
                if let id = item.representedObject as? CommandID {
                    return !existingIDs.contains(id)
                }
                guard let submenu = item.submenu else { return false }
                for child in submenu.items where !child.isSeparatorItem {
                    if !pruneDuplicates(from: child) { submenu.removeItem(child) }
                }
                return !commandIDs(in: submenu.items).isEmpty
            }
            if !menu.items.isEmpty { menu.addItem(.separator()) }
            for item in oldItems {
                guard pruneDuplicates(from: item) else { continue }
                item.menu?.removeItem(item)
                menu.addItem(item)
            }
        }

        let oldFileItems = fileMenu.items
        fileMenu.removeAllItems()
        for item in [
            titled(.fileNew, from: fileMenu), titled(.fileOpen, from: fileMenu),
            titled(.fileCloseAndOpen, from: fileMenu), titled(.fileSave, from: fileMenu),
            titled(.fileSaveAs, from: fileMenu), titled(.insertFileContents, from: fileMenu),
            titled(.filePrint, from: fileMenu),
        ] { fileMenu.addItem(item) }
        fileMenu.addItem(.separator())
        reopenItem.menu?.removeItem(reopenItem); fileMenu.addItem(reopenItem)
        fileMenu.addItem(.separator())
        fileMenu.addItem(titled(.fileSaveAndClose, from: fileMenu))
        fileMenu.addItem(NSMenuItem(title: AppLocalization.string("menu.file.quit"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: ""))
        fileMenu.addItem(titled(.fileSaveAllAndClose, from: fileMenu))
        fileMenu.addItem(titled(.fileDiscardAllAndClose, from: fileMenu))
        preserveExtendedItems(oldFileItems, in: fileMenu)

        let oldEditItems = editMenu.items
        let undo = oldEditItems.first { $0.action == Selector(("undo:")) }!
        let redo = oldEditItems.first { $0.action == Selector(("redo:")) }!
        let cut = oldEditItems.first { $0.action == #selector(NSText.cut(_:)) }!
        let copy = oldEditItems.first { $0.action == #selector(NSText.copy(_:)) }!
        let paste = oldEditItems.first { $0.action == #selector(NSText.paste(_:)) }!
        let selectAll = oldEditItems.first { $0.action == #selector(NSText.selectAll(_:)) }!
        let conversionTitle = AppLocalization.string("menu.edit.convert")
        let conversion = NSMenuItem(title: conversionTitle, action: nil, keyEquivalent: "")
        let conversionMenu = NSMenu(title: conversionTitle)
        for id: CommandID in [
            .convertPipelineDialog, .editUppercase, .editLowercase, .editTitlecase,
            .convertHalfWidth, .convertFullWidth, .convertHiragana, .convertKatakana,
            .convertHalfWidthAlphanumeric, .convertFullWidthAlphanumeric,
            .convertHalfWidthKatakana, .convertFullWidthKatakana,
            .convertTabsToSpaces, .convertSpacesToTabs,
        ] { conversionMenu.addItem(commandItem(id)) }
        conversion.submenu = conversionMenu
        let formatting = oldEditItems.first { $0.identifier?.rawValue == "menu.group.lines" }!
        formatting.title = AppLocalization.string("menu.edit.format")
        editMenu.removeAllItems()
        undo.title = AppLocalization.string("menu.edit.undo")
        redo.title = AppLocalization.string("menu.edit.redo")
        editMenu.addItem(undo); editMenu.addItem(redo); editMenu.addItem(.separator())
        cut.title = AppLocalization.string("menu.edit.cut")
        copy.title = AppLocalization.string("menu.edit.copy")
        paste.title = AppLocalization.string("menu.edit.paste")
        editMenu.addItem(cut); editMenu.addItem(copy)
        editMenu.addItem(titled(.editAppendCut, from: editMenu))
        editMenu.addItem(titled(.editAppendCopy, from: editMenu))
        editMenu.addItem(paste)
        editMenu.addItem(NSMenuItem(title: AppLocalization.string("menu.edit.delete"), action: #selector(NSText.deleteForward(_:)), keyEquivalent: ""))
        editMenu.addItem(conversion); editMenu.addItem(formatting); editMenu.addItem(.separator())
        selectAll.title = AppLocalization.string("menu.edit.selectAll"); editMenu.addItem(selectAll)
        editMenu.addItem(titled(.editClipboardHistory, from: editMenu))
        editMenu.addItem(.separator())
        editMenu.addItem(titled(.editCompleteWord, from: editMenu))
        editMenu.addItem(.separator())
        editMenu.addItem(titled(.fileReload, from: editMenu))
        preserveExtendedItems(oldEditItems.filter { $0 !== formatting }, in: editMenu)

        func rebuildCommandMenu(
            _ menu: NSMenu,
            entries: [CommandID],
            separatorsAfter: Set<Int>
        ) {
            let oldItems = menu.items
            menu.removeAllItems()
            for (index, id) in entries.enumerated() {
                menu.addItem(titled(id, from: menu))
                if separatorsAfter.contains(index) { menu.addItem(.separator()) }
            }
            preserveExtendedItems(oldItems, in: menu)
        }

        rebuildCommandMenu(findMenu, entries: [
            .searchFind, .searchFindNext, .searchFindPrevious, .searchReplace,
            .searchToggleHighlight, .searchReturnToStart, .searchGoToLine,
            .navigateDocumentStart, .navigateDocumentEnd, .navigateLastEdit,
            .searchNextEditMark, .searchPreviousEditMark, .navigatePreviousCursor,
            .highlightOutlineAnalysis, .searchListMarks, .searchListColorLayers,
            .searchGrepReplace, .searchGrep,
        ], separatorsAfter: [5, 12, 15])
        if let highlight = findMenu.items.first(where: { ($0.representedObject as? CommandID) == .highlightOutlineAnalysis }) {
            highlight.action = nil
            highlight.identifier = NSUserInterfaceItemIdentifier("menu.dynamic.searchHighlight")
            let submenu = NSMenu(title: highlight.title)
            for id: CommandID in [
                .highlightOutlineAnalysis, .highlightNextLine,
                .highlightPreviousLine, .highlightSelectLineArea,
            ] { submenu.addItem(commandItem(id)) }
            highlight.submenu = submenu
        }
        if let colorMarker = findMenu.items.first(where: { ($0.representedObject as? CommandID) == .searchListColorLayers }) {
            colorMarker.action = nil
            colorMarker.identifier = NSUserInterfaceItemIdentifier("menu.dynamic.searchColorMarker")
            let submenu = NSMenu(title: colorMarker.title)
            for id: CommandID in [
                .searchListColorLayers,
                .highlightTemporaryConfigure, .highlightTemporaryApply,
                .highlightTemporaryRemove, .highlightTemporaryClear,
                .highlightTemporarySelect, .highlightTemporaryNext,
                .highlightTemporaryPrevious,
            ] { submenu.addItem(commandItem(id)) }
            colorMarker.submenu = submenu
            for duplicate in findMenu.items where
                duplicate !== colorMarker
                && ((duplicate.representedObject as? CommandID) == .searchListColorLayers
                    || duplicate.title == AppLocalization.string("menu.search.colorMarker"))
            {
                findMenu.removeItem(duplicate)
            }
        }

        rebuildCommandMenu(macroMenu, entries: [
            .macroToggleRecording, .macroPlayRecording, .macroSaveRecording,
            .macroReload, .macroRun, .appMacroMenu, .macroHelp,
        ], separatorsAfter: [4])

        rebuildCommandMenu(winMenu, entries: [
            .windowTileVertical, .windowTileHorizontal, .windowCascade, .windowTileGrid,
            .windowMinimizeAll, .viewSplitHorizontal, .windowToggleCrossDocumentScrollLink,
            .navigateCompareNextDocument, .fileSaveWorkspace, .fileOpenWorkspace,
            .windowAlwaysOnTop, .windowShowOutlinePane, .windowShowFilesPane,
            .viewToggleOutputPane, .windowShowSharedBrowserPane, .viewToggleTabMode,
            .windowDetachTab,
        ], separatorsAfter: [4, 7, 9, 10, 14, 16])

        let oldViewItems = viewMenu.items
        viewMenu.removeAllItems()
        func viewCommand(_ id: CommandID, titleKey: String? = nil) {
            let item = titled(id, from: viewMenu)
            if let titleKey { item.title = AppLocalization.string(titleKey) }
            viewMenu.addItem(item)
        }
        func viewGroup(_ title: String, primary: CommandID, children: [CommandID]) {
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.representedObject = primary
            let submenu = NSMenu(title: title)
            for id in children { submenu.addItem(commandItem(id)) }
            item.submenu = submenu
            viewMenu.addItem(item)
        }
        viewCommand(.viewToggleToolbar); viewCommand(.viewToggleTabMode)
        viewCommand(.viewToggleFunctionKeys); viewCommand(.viewToggleStatusBar); viewMenu.addItem(.separator())
        viewCommand(.windowShowFilesPane); viewCommand(.viewToggleOutputPane, titleKey: "classic.view.outputPane")
        viewCommand(.windowShowSharedBrowserPane); viewMenu.addItem(.separator())
        viewCommand(.windowShowOutlinePane); viewCommand(.viewToggleHeading)
        viewCommand(.viewToggleFoldMargin); viewCommand(.viewToggleLineNumbers)
        viewCommand(.viewToggleCurrentLineHighlight)
        viewCommand(.viewToggleRuler); viewCommand(.viewToggleSpellChecking)
        viewCommand(.windowShowDocumentBrowserPane); viewMenu.addItem(.separator())
        viewGroup(AppLocalization.string("menu.view.wrapping"), primary: .viewToggleWrap, children: [.viewToggleWrap])
        viewGroup(AppLocalization.string("menu.view.rulerDisplay"), primary: .viewRulerInterval8,
                  children: [.viewToggleRuler, .viewRulerInterval8, .viewRulerInterval10])
        viewGroup(AppLocalization.string("menu.view.tabStops"), primary: .viewToggleTabStops,
                  children: [.viewToggleTabStops, .viewTabWidth2, .viewTabWidth4, .viewTabWidth8])
        viewCommand(.viewToggleVerticalLayout)
        viewCommand(.viewToggleColumnLayout); viewMenu.addItem(.separator())
        viewCommand(.viewBeginPartialEditing); viewCommand(.viewEndPartialEditing)
        viewGroup(AppLocalization.string("menu.view.folding"), primary: .navigateToggleFold,
                  children: [.navigateToggleFold, .navigateCollapseAllFolds, .navigateExpandAllFolds])
        viewMenu.addItem(.separator())
        viewCommand(.viewToggleFullScreen)
        preserveExtendedItems(oldViewItems.filter {
            ($0.representedObject as? CommandID) != .viewCustomizeMenus
        }, in: viewMenu)

        let oldOtherItems = otherMenu.items
        otherMenu.removeAllItems()
        let otherEntries: [CommandID] = [
            .otherFileTypeProfiles, .appSettings, .otherKeyAssignments, .viewCustomizeMenus,
            .navigateTagJump, .navigateDirectTagJump, .navigateBackTagJump,
            .insertControlCode, .navigateGenerateTags,
        ]
        for (index, id) in otherEntries.enumerated() {
            otherMenu.addItem(titled(id, from: otherMenu))
            if index == 3 { otherMenu.addItem(.separator()) }
        }
        let program = NSMenuItem(title: AppLocalization.string("menu.other.runProgram"), action: nil, keyEquivalent: "")
        program.submenu = cloneMenu(externalCommandManager.menu); otherMenu.addItem(program)
        otherMenu.addItem(titled(.otherCorrectSpelling, from: otherMenu))
        otherMenu.addItem(titled(.otherCommandList, from: otherMenu))
        otherMenu.addItem(titled(.fileToggleViewMode, from: otherMenu))
        otherMenu.addItem(.separator())
        let transfer = NSMenuItem(title: AppLocalization.string("menu.other.settingsTransfer"), action: nil, keyEquivalent: "")
        let transferMenu = NSMenu(title: transfer.title)
        for id: CommandID in [.otherExportSettings, .otherImportSettings, .otherRestoreSettings] {
            transferMenu.addItem(commandItem(id))
        }
        transfer.submenu = transferMenu; otherMenu.addItem(transfer); otherMenu.addItem(.separator())
        otherMenu.addItem(titled(.helpCheckUpdates, from: otherMenu))
        otherMenu.addItem(titled(.appHelp, from: otherMenu))
        otherMenu.addItem(NSMenuItem(title: AppLocalization.string("menu.other.about"), action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: ""))
        otherMenu.addItem(.separator())
        let languageItem = NSMenuItem(title: AppLocalization.string(.languageMenu), action: nil, keyEquivalent: "")
        let languageMenu = NSMenu(title: languageItem.title)
        for language in AppLanguage.selectable {
            let item = NSMenuItem(title: AppLocalization.string(language.displayNameKey), action: #selector(changeApplicationLanguage(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = language.rawValue
            item.state = language == AppLocalization.language ? .on : .off
            languageMenu.addItem(item)
        }
        languageItem.submenu = languageMenu
        otherMenu.addItem(languageItem)
        preserveExtendedItems(oldOtherItems, in: otherMenu)

        main.removeAllItems()
        [appItem, fileItem, editItem, convertItem, viewItem, insertItem, findItem,
         highlightItem, bookmarkItem, toolsItem, winItem, macroItem, otherItem,
         helpItem].forEach(main.addItem)

        let visibleMenuTitles = [
            "menu.top.file", "menu.top.edit", "menu.top.view", "menu.top.search",
            "menu.top.window", "menu.top.macro", "menu.top.other",
        ].map { AppLocalization.string($0) }
        for (item, title) in zip(
            [fileItem, editItem, viewItem, findItem, winItem, macroItem, otherItem],
            visibleMenuTitles
        ) { item.title = title }

        NSApp.mainMenu = main
        NSApp.windowsMenu = winMenu
        classicWindowMenu = winMenu
        winMenu.delegate = self
        applyMenuCustomization(to: main)
        // The macOS menu bar renders the submenu title, not only the owning
        // menu-item title. Keep both synchronized after customization has
        // consumed the stable English menu keys.
        for (item, title) in zip(
            [fileItem, editItem, viewItem, findItem, winItem, macroItem, otherItem],
            visibleMenuTitles
        ) {
            item.title = title
            item.submenu?.title = title
        }
        syncCommandMenuBindings()
    }

    @objc private func changeApplicationLanguage(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let language = AppLanguage(rawValue: raw) else { return }
        AppLocalization.language = language
        // Unit-level menu construction does not run the application lifecycle
        // and therefore has no observer installed.
        if languageObserver == nil { applyApplicationLanguageChange() }
    }

    private func applyApplicationLanguageChange() {
        // Replacing a menu while AppKit is dispatching an action from that
        // same menu violates its submenu ownership invariant. Rebuild on the
        // next main-loop turn, after the menu has closed.
        DispatchQueue.main.async { [weak self] in
            self?.buildMenu()
            self?.coordinator.refreshLocalizedInterface()
        }
    }

    private func showMenuCustomization() {
        if menuCustomizationWindowController == nil {
            menuCustomizationWindowController = MenuCustomizationWindowController(
                definitions: coordinator.commandRegistry.allDefinitions,
                protectedCommandIDs: Self.protectedCommandIDs,
                customization: menuCustomization
            ) { [weak self] customization in
                guard let self else { return }
                self.menuCustomization = customization
                if customization == .defaults { self.menuCustomizationStore.restoreDefaults() }
                else { self.menuCustomizationStore.save(customization) }
                if let menu = NSApp.mainMenu { self.applyMenuCustomization(to: menu) }
            }
        }
        menuCustomizationWindowController?.showWindow(nil)
        menuCustomizationWindowController?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func buildUserMenu(at index: Int) -> NSMenu {
        let menu = NSMenu(title: AppLocalization.string("settings.userMenus.number", [index + 1]))
        for entry in userMenuConfiguration[index] {
            if entry == UserMenuConfiguration.separator {
                menu.addItem(.separator())
            } else {
                let id = CommandID(entry)
                guard coordinator.commandRegistry.definition(for: id) != nil else { continue }
                menu.addItem(commandItem(id))
            }
        }
        if menu.items.isEmpty {
            let empty = NSMenuItem(title: AppLocalization.string("menu.noCommands"), action: nil, keyEquivalent: "")
            empty.isEnabled = false; menu.addItem(empty)
        }
        return menu
    }

    private func showUserMenuConfiguration() {
        if userMenuWindowController == nil {
            userMenuWindowController = UserMenuConfigurationWindowController(
                definitions: coordinator.commandRegistry.allDefinitions,
                configuration: userMenuConfiguration
            ) { [weak self] value in
                guard let self else { return }
                self.userMenuConfiguration = value
                self.userMenuStore.save(value)
                self.buildMenu()
            }
        }
        userMenuWindowController?.showWindow(nil)
        userMenuWindowController?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applyMenuCustomization(to root: NSMenu) {
        Self.applyMenuCustomization(
            menuCustomization, protectedCommandIDs: Self.protectedCommandIDs,
            defaultMenuPlacements: Self.classicDefaultMenuPlacements, to: root)
    }

    static func applyMenuCustomization(
        _ customization: MenuCustomization,
        protectedCommandIDs: Set<CommandID>,
        defaultMenuPlacements: [String: Set<CommandID>],
        to root: NSMenu
    ) {
        func canonicalTopLevelTitle(_ title: String) -> String {
            let keys = [
                "menu.top.file": "File", "menu.top.edit": "Edit", "menu.top.view": "View",
                "menu.top.search": "Search", "menu.top.window": "Window",
                "menu.top.macro": "Macro", "menu.top.other": "Other",
                "menu.edit.convert": "Convert", "menu.group.insert": "Insert",
                "menu.group.highlight": "Highlight", "menu.group.bookmark": "Bookmark",
                "menu.other.tools": "Tools", "menu.group.help": "Help",
            ]
            for (key, canonical) in keys where AppLanguage.allCases.contains(where: {
                AppLocalization.localizedFormat(key, language: $0) == title
            }) {
                return canonical
            }
            return title
        }
        func apply(_ menu: NSMenu, topLevelMenu: String?) {
            for item in menu.items {
                item.isHidden = false
                if let id = item.representedObject as? CommandID {
                    item.isHidden = !protectedCommandIDs.contains(id)
                        && !customization.isCommandVisible(
                            id,
                            defaultVisible: topLevelMenu.flatMap {
                                defaultMenuPlacements[$0]?.contains(id)
                            } ?? false)
                }
                if let submenu = item.submenu {
                    apply(submenu, topLevelMenu: topLevelMenu ?? canonicalTopLevelTitle(submenu.title))
                }
                if topLevelMenu != nil,
                   item.identifier?.rawValue.hasPrefix("menu.dynamic.") != true,
                   let submenu = item.submenu, !submenu.items.isEmpty {
                    item.isHidden = !submenu.items.contains { !$0.isHidden && !$0.isSeparatorItem }
                }
            }
            for (index, item) in menu.items.enumerated() where item.isSeparatorItem {
                let hasBefore = menu.items[..<index].reversed().contains {
                    !$0.isHidden && !$0.isSeparatorItem
                }
                let hasAfter = menu.items[(index + 1)...].contains {
                    !$0.isHidden && !$0.isSeparatorItem
                }
                let previousVisibleIsSeparator = menu.items[..<index].reversed().first {
                    !$0.isHidden
                }?.isSeparatorItem == true
                item.isHidden = !hasBefore || !hasAfter || previousVisibleIsSeparator
            }
        }
        apply(root, topLevelMenu: nil)
        for item in root.items {
            guard let rawTitle = item.submenu?.title else { continue }
            let title = canonicalTopLevelTitle(rawTitle)
            if customization.hiddenMenus.contains(title) { item.isHidden = true }
        }
    }

    func activateKeyBindingProfile(_ profile: KeyBindingProfile) throws {
        try keyBindings.activate(profile)
        syncCommandMenuBindings()
    }

    private func syncCommandMenuBindings() {
        func visit(_ menu: NSMenu) {
            for item in menu.items {
                if let id = item.representedObject as? CommandID {
                    let gesture = keyBindings.keys(for: id).flatMap { $0.count == 1 ? $0[0] : nil }
                    item.keyEquivalent = gesture?.menuKeyEquivalent ?? ""
                    item.keyEquivalentModifierMask = gesture?.menuModifierFlags ?? []
                }
                if let submenu = item.submenu { visit(submenu) }
            }
        }
        if let menu = NSApp.mainMenu { visit(menu) }
    }

    /// Builds a menu item that invokes `id` through the `CommandRegistry`
    /// rather than a dedicated `@objc` method per command (ROADMAP.md
    /// M1-03, "Route menus through the registry").
    private func commandItem(
        _ id: CommandID
    ) -> NSMenuItem {
        guard let definition = coordinator.commandRegistry.definition(for: id) else {
            preconditionFailure("No command registered for \(id.rawValue)")
        }
        let gesture = keyBindings.keys(for: id).flatMap { $0.count == 1 ? $0[0] : nil }
        let mi = NSMenuItem(
            title: AppLocalization.commandTitle(id: id.rawValue, english: definition.title),
            action: #selector(performCommand(_:)),
            keyEquivalent: gesture?.menuKeyEquivalent ?? "")
        mi.keyEquivalentModifierMask = gesture?.menuModifierFlags ?? []
        mi.target = self
        mi.representedObject = id
        mi.isHidden = !Self.protectedCommandIDs.contains(id)
            && !menuCustomization.isCommandVisible(
                id, defaultVisible: Self.classicDefaultVisibleCommandIDs.contains(id))
        return mi
    }

    @objc private func performCommand(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? CommandID else { return }
        coordinator.commandRegistry.execute(id, context: CommandContext(coordinator: coordinator))
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        guard let id = menuItem.representedObject as? CommandID else { return true }
        let statefulViewCommands: Set<CommandID> = [
            .viewToggleWrap, .viewToggleSpaces, .viewToggleTabs,
            .viewToggleTabMode,
            .viewToggleLineEndings, .viewToggleFullWidthSpaces,
            .viewTabWidth2, .viewTabWidth4, .viewTabWidth8,
            .viewToggleRuler, .viewRulerInterval8, .viewRulerInterval10,
            .viewToggleTabStops, .viewToggleVerticalLayout, .viewToggleColumnLayout, .viewToggleLineNumbers,
            .viewToggleCurrentLineHighlight,
            .viewToggleHeading, .viewToggleFunctionKeys, .viewToggleStatusBar,
            .viewToggleOutputPane,
        ]
        if statefulViewCommands.contains(id) {
            menuItem.state = coordinator.isViewCommandActive(id) ? .on : .off
        }
        let findOptions: [CommandID: FindOption] = [
            .searchToggleCaseSensitive: .caseSensitive,
            .searchToggleWholeWord: .wholeWord,
            .searchToggleRegex: .regularExpression,
            .searchToggleFuzzy: .fuzzy,
        ]
        if let option = findOptions[id] {
            menuItem.state = coordinator.isFindOptionEnabled(option) ? .on : .off
        }
        return coordinator.commandRegistry.isEnabled(id, context: CommandContext(coordinator: coordinator))
    }

    // MARK: - NSMenuDelegate (Open Recent, Reopen with Encoding)

    func menuNeedsUpdate(_ menu: NSMenu) {
        if menu === classicWindowMenu {
            var index = 1
            for item in menu.items {
                guard let window = item.target as? NSWindow else { continue }
                let rawTitle = window.title
                let name = rawTitle.components(separatedBy: " — ").last ?? rawTitle
                let displayName = name == "Untitled" ? AppLocalization.string("window.untitled") : name
                let modified = window.isDocumentEdited ? AppLocalization.string("window.modifiedSuffix") : ""
                item.title = AppLocalization.string("window.menu.document", [index, displayName, modified])
                index += 1
            }
            return
        }
        if menu === reopenWithEncodingMenu {
            let fresh = coordinator.reopenWithEncodingMenu()
            menu.removeAllItems()
            for item in fresh.items {
                fresh.removeItem(item)
                menu.addItem(item)
            }
            return
        }
        guard menu === recentMenu else { return }
        menu.removeAllItems()

        let recentFiles = RecentItems.files
        let recentFolders = RecentItems.folders

        if recentFolders.isEmpty && recentFiles.isEmpty {
            let empty = NSMenuItem(title: AppLocalization.string("menu.file.noRecent"), action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
            return
        }

        if !recentFolders.isEmpty {
            let header = NSMenuItem(title: AppLocalization.string("menu.file.folders"), action: nil, keyEquivalent: "")
            header.isEnabled = false
            menu.addItem(header)
            for url in recentFolders {
                let mi = NSMenuItem(title: url.lastPathComponent, action: #selector(openRecentFolder(_:)), keyEquivalent: "")
                mi.target = self
                mi.toolTip = url.path
                mi.representedObject = url
                mi.image = NSImage(systemSymbolName: "folder", accessibilityDescription: nil)
                mi.image?.size = NSSize(width: 14, height: 14)
                menu.addItem(mi)
            }
        }

        if !recentFiles.isEmpty {
            if !recentFolders.isEmpty { menu.addItem(.separator()) }
            let header = NSMenuItem(title: AppLocalization.string("menu.file.files"), action: nil, keyEquivalent: "")
            header.isEnabled = false
            menu.addItem(header)
            for url in recentFiles {
                let mi = NSMenuItem(title: url.lastPathComponent, action: #selector(openRecentFile(_:)), keyEquivalent: "")
                mi.target = self
                mi.toolTip = url.path
                mi.representedObject = url
                mi.image = NSImage(systemSymbolName: "doc", accessibilityDescription: nil)
                mi.image?.size = NSSize(width: 14, height: 14)
                menu.addItem(mi)
            }
        }

        menu.addItem(.separator())
        let clear = NSMenuItem(title: AppLocalization.string("menu.file.clearRecent"), action: #selector(doClearRecent), keyEquivalent: "")
        clear.target = self
        menu.addItem(clear)
    }

    @objc private func openRecentFile(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        coordinator.openFile(url)
    }

    @objc private func openRecentFolder(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        coordinator.openFolder(url)
    }

    @objc private func doClearRecent() {
        RecentItems.clearAll()
    }
}
