import AppKit

/// Owns application-scoped state — currently just the (single) window
/// controller — so `AppDelegate` can stay a thin `NSApplicationDelegate`
/// shim that only forwards OS lifecycle events. Extracted from
/// `AppDelegate` per ROADMAP.md M1-02.
///
/// Not a singleton: `AppDelegate` owns exactly one instance for the life
/// of the process. When multi-window support arrives, this is where that
/// would be coordinated from.
final class AppCoordinator {
    private var windowController: MainWindowController?
    let commandRegistry = CommandRegistry()

    init() {
        AppCommands.registerAll(in: commandRegistry)
    }

    @discardableResult
    func ensureWindowControllerReady() -> MainWindowController {
        if let wc = windowController { return wc }
        let wc = MainWindowController()
        windowController = wc
        wc.showWindow(nil)
        wc.restoreSession()
        return wc
    }

    func saveActiveSession() {
        windowController?.saveSession()
    }

    // MARK: - File/menu actions
    // Mirrors the menu-action methods AppDelegate's selectors call, so
    // AppDelegate no longer needs to know MainWindowController exists.

    func openFile(_ url: URL)         { ensureWindowControllerReady().openFile(url) }
    func openFolder(_ url: URL)       { ensureWindowControllerReady().openFolderDirect(url) }
    func newDocument()                { ensureWindowControllerReady().newDocument() }
    func openDocument()               { ensureWindowControllerReady().openDocument() }
    func openFolderPanel()            { ensureWindowControllerReady().openFolder() }
    func saveDocument()               { ensureWindowControllerReady().saveDocument() }
    func saveDocumentAs()             { ensureWindowControllerReady().saveDocumentAs() }
    func closeCurrentTab()            { ensureWindowControllerReady().closeCurrentTab() }
    func showFind()                   { ensureWindowControllerReady().showFind() }
    func showReplace()                { ensureWindowControllerReady().showFind(showingReplace: true) }
    func replaceAll()                 { ensureWindowControllerReady().replaceAllFromFindBar() }
    func findNext()                   { ensureWindowControllerReady().findAgain(direction: .next) }
    func findPrevious()               { ensureWindowControllerReady().findAgain(direction: .previous) }
    func showGoToLine()                { ensureWindowControllerReady().showGoToLine() }
    func showQuickOpen()               { ensureWindowControllerReady().showQuickOpen() }
    func showGrep()                    { ensureWindowControllerReady().showGrep() }
    func clearSearchHistory()          { ensureWindowControllerReady().clearSearchHistory() }
    func toggleSidebar()               { ensureWindowControllerReady().toggleSidebar() }
    func clearRecoveryData()           { ensureWindowControllerReady().clearRecoveryData() }

    /// Menu items for the File > Reopen with Encoding submenu, freshly
    /// built (so the "Recent" section and the checkmark on the current
    /// encoding stay current every time the submenu opens).
    func reopenWithEncodingMenu() -> NSMenu {
        ensureWindowControllerReady().buildEncodingMenu()
    }
}
