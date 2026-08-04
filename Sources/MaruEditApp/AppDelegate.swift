import AppKit
import MaruEditCore

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let coordinator = AppCoordinator()
    private var recentMenu: NSMenu!
    private var reopenWithEncodingMenu: NSMenu!

    func applicationDidFinishLaunching(_ notification: Notification) {
        EditorShortcuts.install()
        buildMenu()
        coordinator.ensureWindowControllerReady()
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationWillTerminate(_ notification: Notification) {
        coordinator.saveActiveSession()
    }

    func application(_ sender: NSApplication, openFile filename: String) -> Bool {
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
        appMenu.addItem(withTitle: "Quit MaruEdit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        // File menu
        let fileItem = NSMenuItem()
        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(commandItem(.fileNew, "n"))
        fileMenu.addItem(commandItem(.fileOpen, "o"))
        fileMenu.addItem(commandItem(.fileOpenFolder, "O"))

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
        fileMenu.addItem(commandItem(.fileSave, "s"))
        fileMenu.addItem(commandItem(.fileSaveAs, "S"))
        fileMenu.addItem(.separator())
        fileMenu.addItem(commandItem(.fileCloseTab, "w"))
        fileMenu.addItem(.separator())
        fileMenu.addItem(commandItem(.fileClearRecoveryData, ""))
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
        editItem.submenu = editMenu
        main.addItem(editItem)

        // Find menu
        let findItem = NSMenuItem()
        let findMenu = NSMenu(title: "Find")
        findMenu.addItem(commandItem(.searchFind, "f"))
        findMenu.addItem(commandItem(.searchFindNext, "g"))
        findMenu.addItem(commandItem(.searchFindPrevious, "G"))
        findMenu.addItem(.separator())
        // Go to Line moves off ⌘G, which macOS reserves for Find Next.
        findMenu.addItem(commandItem(.searchGoToLine, "l"))
        findMenu.addItem(.separator())
        findMenu.addItem(commandItem(.searchQuickOpen, "p"))
        findItem.submenu = findMenu
        main.addItem(findItem)

        // View menu
        let viewItem = NSMenuItem()
        let viewMenu = NSMenu(title: "View")
        viewMenu.addItem(commandItem(.viewToggleSidebar, "b"))
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
    }

    /// Builds a menu item that invokes `id` through the `CommandRegistry`
    /// rather than a dedicated `@objc` method per command (ROADMAP.md
    /// M1-03, "Route menus through the registry").
    private func commandItem(_ id: CommandID, _ key: String) -> NSMenuItem {
        guard let definition = coordinator.commandRegistry.definition(for: id) else {
            preconditionFailure("No command registered for \(id.rawValue)")
        }
        let mi = NSMenuItem(title: definition.title, action: #selector(performCommand(_:)), keyEquivalent: key)
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
