import AppKit
import MaruEditCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
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
    private var menuCustomizationWindowController: MenuCustomizationWindowController?
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

    func applicationDidFinishLaunching(_ notification: Notification) {
        coordinator.onShowMenuCustomization = { [weak self] in self?.showMenuCustomization() }
        EditorShortcuts.install(
            keyBindings: keyBindings,
            execute: { [coordinator] id in
                coordinator.commandRegistry.execute(id, context: CommandContext(coordinator: coordinator))
            },
            showStatus: { [coordinator] message, duration in
                coordinator.showStatusMessage(message, duration: duration)
            })
        macroManager.reload()
        externalCommandManager.reload()
        buildMenu()
        coordinator.ensureWindowControllerReady(restoreSession: !isUITestMode)
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
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationWillTerminate(_ notification: Notification) {
        if !isUITestMode { coordinator.saveActiveSession() }
    }

    func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        guard !isUITestMode else { return false }
        coordinator.openFile(URL(fileURLWithPath: filename))
        return true
    }

    // MARK: - Menu bar

    func buildMenu() {
        let main = NSMenu()

        // App menu
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About MaruEdit", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(commandItem(.appSettings))
        appMenu.addItem(.separator())
        let servicesItem = NSMenuItem(title: "Services", action: nil, keyEquivalent: "")
        let servicesMenu = NSMenu(title: "Services")
        servicesItem.submenu = servicesMenu
        appMenu.addItem(servicesItem)
        NSApp.servicesMenu = servicesMenu
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide MaruEdit", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = appMenu.addItem(
            withTitle: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)),
            keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit MaruEdit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        // File menu
        let fileItem = NSMenuItem()
        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(commandItem(.fileNew))
        fileMenu.addItem(commandItem(.fileOpen))
        fileMenu.addItem(commandItem(.fileOpenFolder))

        recentMenu = NSMenu(title: "Open Recent")
        recentMenu.delegate = self
        let recentItem = NSMenuItem(title: "Open Recent", action: nil, keyEquivalent: "")
        recentItem.submenu = recentMenu
        recentItem.identifier = NSUserInterfaceItemIdentifier("menu.dynamic.openRecent")
        fileMenu.addItem(recentItem)

        reopenWithEncodingMenu = NSMenu(title: "Reopen with Encoding")
        reopenWithEncodingMenu.delegate = self
        let reopenItem = NSMenuItem(title: "Reopen with Encoding", action: nil, keyEquivalent: "")
        reopenItem.submenu = reopenWithEncodingMenu
        reopenItem.identifier = NSUserInterfaceItemIdentifier("menu.dynamic.reopenEncoding")
        fileMenu.addItem(reopenItem)

        fileMenu.addItem(.separator())
        fileMenu.addItem(commandItem(.fileSave))
        fileMenu.addItem(commandItem(.fileSaveAs))
        fileMenu.addItem(.separator())
        fileMenu.addItem(commandItem(.fileCloseTab))
        fileMenu.addItem(.separator())
        fileMenu.addItem(commandItem(.fileClearRecoveryData))
        fileItem.submenu = fileMenu
        main.addItem(fileItem)

        // Edit menu
        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenu.addItem(.separator())
        editMenu.addItem(commandItem(.editAddCursorAbove))
        editMenu.addItem(commandItem(.editAddCursorBelow))
        editMenu.addItem(commandItem(.editSelectNextOccurrence))
        editMenu.addItem(commandItem(.editSelectAllOccurrences))
        editMenu.addItem(commandItem(.editUndoLastAddedCursor))
        editMenu.addItem(commandItem(.editBeginColumnSelection))
        editMenu.addItem(.separator())
        let linesItem = NSMenuItem(title: "Lines", action: nil, keyEquivalent: "")
        let linesMenu = NSMenu(title: "Lines")
        for id: CommandID in [
            .editDeleteLine, .editDuplicateLine, .editMoveLineUp, .editMoveLineDown,
            .editJoinLines, .editTrimTrailingWhitespace, .editUppercase, .editLowercase,
            .editSortLines, .editReverseLines, .editIndent, .editOutdent, .editToggleComment,
        ] { linesMenu.addItem(commandItem(id)) }
        linesItem.submenu = linesMenu
        linesItem.identifier = NSUserInterfaceItemIdentifier("menu.group.lines")
        editMenu.addItem(linesItem)
        editMenu.addItem(commandItem(.editToggleInputMode))
        for id: CommandID in [
            .editMoveWordLeft, .editMoveWordRight, .editMoveParagraphStart,
            .editMoveParagraphEnd, .editDeleteWordBackward, .editDeleteWordForward,
            .editTitlecase,
        ] { editMenu.addItem(commandItem(id)) }
        for id: CommandID in [
            .navigateMarkerRed, .navigateMarkerYellow, .navigateMarkerBlue,
            .navigateNextMarker, .navigatePreviousMarker, .navigateClearMarkers,
        ] { editMenu.addItem(commandItem(id)) }
        editMenu.addItem(.separator())
        editMenu.addItem(commandItem(.navigateToggleBookmark))
        editMenu.addItem(commandItem(.navigateNextBookmark))
        editMenu.addItem(commandItem(.navigatePreviousBookmark))
        editMenu.addItem(commandItem(.navigateClearBookmarks))
        editMenu.addItem(.separator())
        editMenu.addItem(commandItem(.navigateToggleFold))
        editMenu.addItem(commandItem(.navigateCollapseAllFolds))
        editMenu.addItem(commandItem(.navigateExpandAllFolds))
        editItem.submenu = editMenu
        main.addItem(editItem)

        // Find menu
        let findItem = NSMenuItem()
        let findMenu = NSMenu(title: "Find")
        findMenu.addItem(commandItem(.searchFind))
        findMenu.addItem(commandItem(.searchReplace))
        findMenu.addItem(commandItem(.searchReplaceAll))
        findMenu.addItem(commandItem(.searchFindNext))
        findMenu.addItem(commandItem(.searchFindPrevious))
        findMenu.addItem(.separator())
        // Go to Line moves off ⌘G, which macOS reserves for Find Next.
        findMenu.addItem(commandItem(.searchGoToLine))
        findMenu.addItem(.separator())
        findMenu.addItem(commandItem(.searchQuickOpen))
        findMenu.addItem(commandItem(.searchGrep))
        findMenu.addItem(.separator())
        findMenu.addItem(commandItem(.searchClearHistory))
        findItem.submenu = findMenu
        main.addItem(findItem)

        let toolsItem = NSMenuItem(title: "Tools", action: nil, keyEquivalent: "")
        toolsItem.submenu = externalCommandManager.menu
        main.addItem(toolsItem)

        let macroItem = NSMenuItem(title: "Macro", action: nil, keyEquivalent: "")
        macroItem.submenu = macroManager.menu
        main.addItem(macroItem)

        // View menu
        let viewItem = NSMenuItem()
        let viewMenu = NSMenu(title: "View")
        viewMenu.addItem(commandItem(.viewToggleSidebar))
        viewMenu.addItem(commandItem(.viewToggleWrap))
        let invisiblesItem = NSMenuItem(title: "Show Invisibles", action: nil, keyEquivalent: "")
        let invisiblesMenu = NSMenu(title: "Show Invisibles")
        invisiblesMenu.addItem(commandItem(.viewToggleSpaces))
        invisiblesMenu.addItem(commandItem(.viewToggleTabs))
        invisiblesMenu.addItem(commandItem(.viewToggleLineEndings))
        invisiblesMenu.addItem(commandItem(.viewToggleFullWidthSpaces))
        invisiblesItem.submenu = invisiblesMenu
        invisiblesItem.identifier = NSUserInterfaceItemIdentifier("menu.group.invisibles")
        viewMenu.addItem(invisiblesItem)
        let tabWidthItem = NSMenuItem(title: "Tab Width", action: nil, keyEquivalent: "")
        let tabWidthMenu = NSMenu(title: "Tab Width")
        tabWidthMenu.addItem(commandItem(.viewTabWidth2))
        tabWidthMenu.addItem(commandItem(.viewTabWidth4))
        tabWidthMenu.addItem(commandItem(.viewTabWidth8))
        tabWidthItem.submenu = tabWidthMenu
        tabWidthItem.identifier = NSUserInterfaceItemIdentifier("menu.group.tabWidth")
        viewMenu.addItem(tabWidthItem)
        viewMenu.addItem(.separator())
        viewMenu.addItem(commandItem(.viewShowFonts))
        viewMenu.addItem(.separator())
        viewMenu.addItem(commandItem(.viewCustomizeMenus))
        viewItem.submenu = viewMenu
        main.addItem(viewItem)

        // Window menu
        let winItem = NSMenuItem()
        let winMenu = NSMenu(title: "Window")
        winMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.miniaturize(_:)), keyEquivalent: "m")
        winMenu.addItem(withTitle: "Zoom", action: #selector(NSWindow.zoom(_:)), keyEquivalent: "")
        winItem.submenu = winMenu
        main.addItem(winItem)

        NSApp.mainMenu = main
        NSApp.windowsMenu = winMenu
        applyMenuCustomization(to: main)
        syncCommandMenuBindings()
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

    func applyMenuCustomization(to root: NSMenu) {
        Self.applyMenuCustomization(
            menuCustomization, protectedCommandIDs: Self.protectedCommandIDs, to: root)
    }

    static func applyMenuCustomization(
        _ customization: MenuCustomization,
        protectedCommandIDs: Set<CommandID>,
        to root: NSMenu
    ) {
        func apply(_ menu: NSMenu) {
            for item in menu.items {
                item.isHidden = false
                if let id = item.representedObject as? CommandID {
                    item.isHidden = customization.hiddenCommands.contains(id)
                        && !protectedCommandIDs.contains(id)
                }
                if let submenu = item.submenu { apply(submenu) }
                if item.identifier?.rawValue.hasPrefix("menu.group.") == true,
                   let submenu = item.submenu {
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
        apply(root)
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
            title: definition.title,
            action: #selector(performCommand(_:)),
            keyEquivalent: gesture?.menuKeyEquivalent ?? "")
        mi.keyEquivalentModifierMask = gesture?.menuModifierFlags ?? []
        mi.target = self
        mi.representedObject = id
        mi.isHidden = menuCustomization.hiddenCommands.contains(id)
            && !Self.protectedCommandIDs.contains(id)
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
            .viewToggleLineEndings, .viewToggleFullWidthSpaces,
            .viewTabWidth2, .viewTabWidth4, .viewTabWidth8,
        ]
        if statefulViewCommands.contains(id) {
            menuItem.state = coordinator.isViewCommandActive(id) ? .on : .off
        }
        return coordinator.commandRegistry.isEnabled(id, context: CommandContext(coordinator: coordinator))
    }

    // MARK: - NSMenuDelegate (Open Recent, Reopen with Encoding)

    func menuNeedsUpdate(_ menu: NSMenu) {
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
            let empty = NSMenuItem(title: "No Recent Items", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
            return
        }

        if !recentFolders.isEmpty {
            let header = NSMenuItem(title: "Folders", action: nil, keyEquivalent: "")
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
            let header = NSMenuItem(title: "Files", action: nil, keyEquivalent: "")
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
        let clear = NSMenuItem(title: "Clear Recent", action: #selector(doClearRecent), keyEquivalent: "")
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
