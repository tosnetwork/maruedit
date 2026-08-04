import AppKit
import MaruEditCore

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let coordinator = AppCoordinator()
    private let keyBindings = KeyBindingManager(profile: .macOSStandard)
    private let isUITestMode = ProcessInfo.processInfo.environment["MARUEDIT_UI_TEST_MODE"] == "1"
    private var recentMenu: NSMenu!
    private var reopenWithEncodingMenu: NSMenu!

    func applicationDidFinishLaunching(_ notification: Notification) {
        EditorShortcuts.install(
            keyBindings: keyBindings,
            execute: { [coordinator] id in
                coordinator.commandRegistry.execute(id, context: CommandContext(coordinator: coordinator))
            },
            showStatus: { [coordinator] message, duration in
                coordinator.showStatusMessage(message, duration: duration)
            })
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

    private func buildMenu() {
        let main = NSMenu()

        // App menu
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About MaruEdit", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(commandItem(.appSettings))
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
        fileMenu.addItem(recentItem)

        reopenWithEncodingMenu = NSMenu(title: "Reopen with Encoding")
        reopenWithEncodingMenu.delegate = self
        let reopenItem = NSMenuItem(title: "Reopen with Encoding", action: nil, keyEquivalent: "")
        reopenItem.submenu = reopenWithEncodingMenu
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
        editMenu.addItem(linesItem)
        editMenu.addItem(.separator())
        editMenu.addItem(commandItem(.navigateToggleBookmark))
        editMenu.addItem(commandItem(.navigateNextBookmark))
        editMenu.addItem(commandItem(.navigatePreviousBookmark))
        editMenu.addItem(commandItem(.navigateClearBookmarks))
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
        viewMenu.addItem(invisiblesItem)
        let tabWidthItem = NSMenuItem(title: "Tab Width", action: nil, keyEquivalent: "")
        let tabWidthMenu = NSMenu(title: "Tab Width")
        tabWidthMenu.addItem(commandItem(.viewTabWidth2))
        tabWidthMenu.addItem(commandItem(.viewTabWidth4))
        tabWidthMenu.addItem(commandItem(.viewTabWidth8))
        tabWidthItem.submenu = tabWidthMenu
        viewMenu.addItem(tabWidthItem)
        viewMenu.addItem(.separator())
        viewMenu.addItem(commandItem(.viewShowFonts))
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
        syncCommandMenuBindings()
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
