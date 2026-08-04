import AppKit
import MaruEditCore

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
    private var settingsWindowController: SettingsWindowController?
    private let preferencesStore: PreferencesStore
    private let fileTypeProfileStore = FileTypeProfileStore()
    private(set) var preferences: Preferences
    let commandRegistry = CommandRegistry()
    var onShowMenuCustomization: (() -> Void)?

    init(preferencesStore: PreferencesStore? = nil) {
        if let preferencesStore {
            self.preferencesStore = preferencesStore
        } else if ProcessInfo.processInfo.environment["MARUEDIT_UI_TEST_MODE"] == "1" {
            let suite = "network.tos.maruedit.UITest.\(ProcessInfo.processInfo.processIdentifier)"
            let defaults = UserDefaults(suiteName: suite)!
            defaults.removePersistentDomain(forName: suite)
            self.preferencesStore = PreferencesStore(defaults: defaults)
        } else {
            self.preferencesStore = PreferencesStore()
        }
        preferences = self.preferencesStore.load()
        AppCommands.registerAll(in: commandRegistry)
    }

    @discardableResult
    func ensureWindowControllerReady(restoreSession: Bool = true) -> MainWindowController {
        if let wc = windowController { return wc }
        let wc = MainWindowController(fileTypeResolver: fileTypeProfileStore.resolver())
        wc.onEditorFontChange = { [weak self] font in
            guard let self else { return }
            self.preferences.fontName = font.fontName
            self.preferences.fontSize = font.pointSize
            self.preferencesStore.save(self.preferences)
            self.windowController?.applyPreferences(self.preferences)
        }
        windowController = wc
        wc.showWindow(nil)
        wc.applyPreferences(preferences)
        if restoreSession { wc.restoreSession() }
        return wc
    }

    func showSettings() {
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController(preferences: preferences) { [weak self] updated in
                guard let self else { return }
                self.preferences = updated
                self.preferencesStore.save(updated)
                self.windowController?.applyPreferences(updated)
            }
        }
        settingsWindowController?.showWindow(nil)
        settingsWindowController?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
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
    func showStatusMessage(_ message: String, duration: TimeInterval = 1.5) {
        ensureWindowControllerReady().showStatusMessage(message, duration: duration)
    }
    func addCursorAbove()              { ensureWindowControllerReady().addCursorAbove() }
    func addCursorBelow()              { ensureWindowControllerReady().addCursorBelow() }
    func selectNextOccurrence()        { ensureWindowControllerReady().selectNextOccurrence() }
    func selectAllOccurrences()        { ensureWindowControllerReady().selectAllOccurrences() }
    func undoLastAddedCursor()         { ensureWindowControllerReady().undoLastAddedCursor() }
    func beginColumnSelection()        { ensureWindowControllerReady().beginColumnSelection() }
    func performLineCommand(_ command: LineEditCommand) { ensureWindowControllerReady().performLineCommand(command) }
    func toggleBookmark()               { ensureWindowControllerReady().toggleBookmark() }
    func nextBookmark()                 { ensureWindowControllerReady().nextBookmark() }
    func previousBookmark()             { ensureWindowControllerReady().previousBookmark() }
    func clearBookmarks()               { ensureWindowControllerReady().clearBookmarks() }
    func toggleSidebar()               { ensureWindowControllerReady().toggleSidebar() }
    func toggleWrapLines()             { ensureWindowControllerReady().toggleWrapLines() }
    func setTabWidth(_ width: Int)      { ensureWindowControllerReady().setTabWidth(width) }
    func showFontPanel()                { ensureWindowControllerReady().showFontPanel() }
    func showMenuCustomization()        { onShowMenuCustomization?() }
    func toggleInvisible(_ keyPath: WritableKeyPath<InvisibleCharacterOptions, Bool>) {
        preferences.invisibleCharacters[keyPath: keyPath].toggle()
        preferencesStore.save(preferences)
        windowController?.applyPreferences(preferences)
    }

    func isViewCommandActive(_ id: CommandID) -> Bool {
        switch id {
        case .viewToggleWrap: ensureWindowControllerReady().effectiveWrapLines
        case .viewToggleSpaces: preferences.invisibleCharacters.spaces
        case .viewToggleTabs: preferences.invisibleCharacters.tabs
        case .viewToggleLineEndings: preferences.invisibleCharacters.lineEndings
        case .viewToggleFullWidthSpaces: preferences.invisibleCharacters.fullWidthSpaces
        case .viewTabWidth2: ensureWindowControllerReady().effectiveTabWidth == 2
        case .viewTabWidth4: ensureWindowControllerReady().effectiveTabWidth == 4
        case .viewTabWidth8: ensureWindowControllerReady().effectiveTabWidth == 8
        default: false
        }
    }
    func clearRecoveryData()           { ensureWindowControllerReady().clearRecoveryData() }
    func prepareUITestDocument(content: String, selections: [NSRange]) {
        ensureWindowControllerReady(restoreSession: false)
            .prepareUITestDocument(content: content, selections: selections)
    }

    /// Menu items for the File > Reopen with Encoding submenu, freshly
    /// built (so the "Recent" section and the checkmark on the current
    /// encoding stay current every time the submenu opens).
    func reopenWithEncodingMenu() -> NSMenu {
        ensureWindowControllerReady().buildEncodingMenu()
    }
}
