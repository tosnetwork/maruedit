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
@MainActor
final class AppCoordinator {
    private var windowController: MainWindowController?
    private var settingsWindowController: SettingsWindowController?
    private var externalHelpWindowController: ExternalHelpWindowController?
    private var conversionDialogWindowController: ConversionDialogWindowController?
    private let preferencesStore: PreferencesStore
    private let fileTypeProfileStore = FileTypeProfileStore()
    private let externalHelpStore: ExternalHelpStore
    private(set) var externalHelpEntries: [ExternalHelpEntry]
    private(set) var preferences: Preferences
    private var activeMacroCount = 0
    private(set) var isRecordingCommands = false
    private(set) var recordedCommands: [CommandID] = []
    private var isPlayingRecording = false
    private var lastRepeatableCommand: CommandID?
    let clipboardHistory = ClipboardHistoryStore()
    let commandRegistry = CommandRegistry()
    var onShowMenuCustomization: (() -> Void)?
    var onShowMacroMenu: (() -> Void)?
    var onSaveRecordedMacro: ((String, [CommandID]) -> Void)?
    var openDocumentationURL: (URL) -> Void = { NSWorkspace.shared.open($0) }

    init(preferencesStore: PreferencesStore? = nil, externalHelpStore: ExternalHelpStore? = nil) {
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
        self.externalHelpStore = externalHelpStore ?? ExternalHelpStore()
        externalHelpEntries = self.externalHelpStore.load()
        AppCommands.registerAll(in: commandRegistry)
        commandRegistry.didExecute = { [weak self] id in self?.commandDidExecute(id) }
    }

    @discardableResult
    func ensureWindowControllerReady(restoreSession: Bool = true) -> MainWindowController {
        if let wc = windowController { return wc }
        let wc = MainWindowController(fileTypeResolver: fileTypeProfileStore.resolver())
        // Publish the controller before wiring presentation callbacks: their initial
        // refresh queries view state through this coordinator and must not recursively
        // create another window.
        windowController = wc
        wc.onEditorFontChange = { [weak self] font in
            guard let self else { return }
            self.preferences.fontName = font.fontName
            self.preferences.fontSize = font.pointSize
            self.preferencesStore.save(self.preferences)
            self.windowController?.applyPreferences(self.preferences)
        }
        wc.onClassicToolbarCommand = { [weak self] id in
            guard let self else { return }
            _ = self.commandRegistry.execute(id, context: CommandContext(coordinator: self))
            self.windowController?.refreshClassicCommandPresentation()
        }
        wc.onStatusMacroControl = { [weak self] in
            guard let self, self.isRecordingCommands else { return }
            self.stopMacroRecording()
        }
        wc.configureClassicCommands(commandRegistry.allDefinitions.map { ($0.id, $0.title) })
        wc.configureClassicCommandPresentation { [weak self] id in
            guard let self else { return (false, false) }
            return (
                self.commandRegistry.isEnabled(id, context: CommandContext(coordinator: self)),
                self.isCommandSelected(id))
        }
        wc.showWindow(nil)
        wc.applyPreferences(preferences)
        if restoreSession { wc.restoreSession() }
        return wc
    }

    func showSettings() {
        showSettings(group: nil)
    }

    private func showSettings(group: SettingsWindowController.Group?) {
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController(preferences: preferences) { [weak self] updated in
                guard let self else { return }
                self.preferences = updated
                self.preferencesStore.save(updated)
                self.windowController?.applyPreferences(updated)
            }
        }
        if let group { settingsWindowController?.show(group: group) }
        else {
            settingsWindowController?.showWindow(nil)
            settingsWindowController?.window?.makeKeyAndOrderFront(nil)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    func showFileTypeProfiles() { showSettings(group: .files) }
    func showKeyAssignments() { showSettings(group: .keyBindings) }

    func showConversionPipeline() {
        let controller = ConversionDialogWindowController { [weak self] steps in
            guard let self else { return }
            do {
                try self.ensureWindowControllerReady().macroEditor.applyConversionPipeline(steps)
                self.showStatusMessage("Conversion pipeline applied")
            } catch {
                let alert = NSAlert(error: error); alert.runModal()
            }
        }
        conversionDialogWindowController = controller
        controller.showWindow(nil); controller.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func showMacroMenu() { onShowMacroMenu?() }
    func hasExternalHelp(slot: Int) -> Bool {
        externalHelpEntries.indices.contains(slot) && externalHelpEntries[slot].isConfigured
    }

    func openExternalHelp(slot: Int) {
        guard hasExternalHelp(slot: slot) else {
            showStatusMessage("External Help \(slot + 1) is not configured"); return
        }
        let target = externalHelpEntries[slot].target
        let url: URL?
        if let parsed = URL(string: target), let scheme = parsed.scheme,
           ["https", "http", "file"].contains(scheme.lowercased()) {
            url = parsed
        } else {
            let expanded = (target as NSString).expandingTildeInPath
            url = FileManager.default.fileExists(atPath: expanded)
                ? URL(fileURLWithPath: expanded) : nil
        }
        guard let url else { showStatusMessage("External Help target is invalid", duration: 5); return }
        openDocumentationURL(url)
    }

    func showExternalHelpConfiguration() {
        let controller = ExternalHelpWindowController(entries: externalHelpEntries) { [weak self] entries in
            guard let self else { return }
            self.externalHelpEntries = entries
            self.externalHelpStore.save(entries)
            self.windowController?.refreshClassicCommandPresentation()
        }
        externalHelpWindowController = controller
        controller.showWindow(nil); controller.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func setExternalHelpEntriesForTesting(_ entries: [ExternalHelpEntry]) {
        externalHelpEntries = entries
        externalHelpStore.save(entries)
    }
    func startMacroRecording() {
        recordedCommands.removeAll(); isRecordingCommands = true
        ensureWindowControllerReady().updateMacroRecording(isRecording: true)
    }
    func stopMacroRecording() {
        isRecordingCommands = false
        ensureWindowControllerReady().updateMacroRecording(isRecording: false)
    }
    func playMacroRecording() {
        guard !recordedCommands.isEmpty else { showStatusMessage("No recorded commands"); return }
        let commands = recordedCommands
        isPlayingRecording = true
        for id in commands { _ = commandRegistry.execute(id, context: CommandContext(coordinator: self)) }
        isPlayingRecording = false
    }
    func saveMacroRecording() {
        guard !recordedCommands.isEmpty else { showStatusMessage("No recorded commands"); return }
        let alert = NSAlert(); alert.messageText = "Save Recording as Macro"
        alert.addButton(withTitle: "Save"); alert.addButton(withTitle: "Cancel")
        let field = NSTextField(string: "Recorded Macro")
        field.frame.size = NSSize(width: 320, height: 24); alert.accessoryView = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        onSaveRecordedMacro?(name, recordedCommands)
    }
    private func recordExecutedCommand(_ id: CommandID) {
        let controls: Set<CommandID> = [.macroStartRecording, .macroStopRecording, .macroPlayRecording, .macroSaveRecording]
        guard isRecordingCommands, !isPlayingRecording, !controls.contains(id) else { return }
        recordedCommands.append(id)
    }
    private func commandDidExecute(_ id: CommandID) {
        recordExecutedCommand(id)
        if Self.repeatableEditCommands.contains(id) { lastRepeatableCommand = id }
    }
    private static let repeatableEditCommands: Set<CommandID> = [
        .editDeleteLine, .editDuplicateLine, .editMoveLineUp, .editMoveLineDown,
        .editJoinLines, .editTrimTrailingWhitespace, .editSortLines, .editReverseLines,
        .editIndent, .editOutdent, .editToggleComment, .editUppercase, .editLowercase,
        .editTitlecase, .editDeleteWordBackward, .editDeleteWordForward,
        .editDeleteToLineStart, .editDeleteToLineEnd, .editCorrectCapsLock,
        .convertHalfWidth, .convertFullWidth, .convertHiragana, .convertKatakana,
        .convertHalfWidthAlphanumeric, .convertFullWidthAlphanumeric,
        .convertHalfWidthKatakana, .convertFullWidthKatakana,
        .convertTabsToSpaces, .convertSpacesToTabs,
    ]
    var canRepeatLastEdit: Bool { lastRepeatableCommand != nil }
    func repeatLastEdit() {
        guard let id = lastRepeatableCommand else { return }
        _ = commandRegistry.execute(id, context: CommandContext(coordinator: self))
    }
    func recordExecutedCommandForTesting(_ id: CommandID) { recordExecutedCommand(id) }
    func showHelp() {
        openHelpPath("docs/user-guide.md")
    }
    func showMacroHelp() { openHelpPath("docs/macros.md") }
    func showShortcutReference() { openHelpPath("docs/key-bindings.md") }
    func checkForUpdates() { openHelpURL("https://github.com/tosnetwork/maruedit/releases/latest") }
    func showSupport() { openHelpURL("https://github.com/tosnetwork/maruedit/issues") }

    private func openHelpPath(_ path: String) {
        openHelpURL("https://github.com/tosnetwork/maruedit/blob/main/\(path)")
    }

    private func openHelpURL(_ value: String) {
        guard let url = URL(string: value) else { return }
        openDocumentationURL(url)
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
    func newDocumentFromTemplate()    { ensureWindowControllerReady().newDocumentFromTemplate() }
    func openDocument()               { ensureWindowControllerReady().openDocument() }
    func openFolderPanel()            { ensureWindowControllerReady().openFolder() }
    func saveDocument()               { ensureWindowControllerReady().saveDocument() }
    func saveDocumentAs()             { ensureWindowControllerReady().saveDocumentAs() }
    func saveAllDocuments()           { ensureWindowControllerReady().saveAllDocuments() }
    func saveAllModifiedDocuments()   { ensureWindowControllerReady().saveAllDocuments(onlyModified: true) }
    func saveDocumentWithLFLineEndings() { ensureWindowControllerReady().saveDocumentWithLFLineEndings() }
    func saveAndCloseCurrentTab()     { ensureWindowControllerReady().saveAndCloseCurrentTab() }
    func saveAllAndClose()            { ensureWindowControllerReady().saveAllAndClose() }
    func discardAndCloseCurrentTab()  { ensureWindowControllerReady().discardAndCloseCurrentTab() }
    func discardAllAndClose()         { ensureWindowControllerReady().discardAllAndClose() }
    func openCursorTargetWithAssociatedApplication() { ensureWindowControllerReady().openCursorTargetWithAssociatedApplication() }
    func openCursorTargetInMaruEdit() { ensureWindowControllerReady().openCursorTargetInMaruEdit() }
    func closeCurrentTab()            { ensureWindowControllerReady().closeCurrentTab() }
    func insertDateTime()             { ensureWindowControllerReady().insertDateTime() }
    func insertNewline()              { ensureWindowControllerReady().insertNewline() }
    func insertTab()                  { ensureWindowControllerReady().insertTab() }
    func insertPageBreak()            { ensureWindowControllerReady().insertPageBreak() }
    func insertBlankLine()            { ensureWindowControllerReady().insertBlankLine() }
    func insertCurrentFileName()      { ensureWindowControllerReady().insertCurrentFileName() }
    func configureTemporaryColorMarker() { ensureWindowControllerReady().configureTemporaryColorMarker() }
    func applyTemporaryColorMarker()  { ensureWindowControllerReady().applyTemporaryColorMarker() }
    func removeTemporaryColorMarker() { ensureWindowControllerReady().removeTemporaryColorMarker() }
    func clearTemporaryColorMarkers() { ensureWindowControllerReady().clearTemporaryColorMarkers() }
    func selectTemporaryColorMarkers() { ensureWindowControllerReady().selectTemporaryColorMarkers() }
    func nextTemporaryColorMarker()   { ensureWindowControllerReady().nextTemporaryColorMarker() }
    func previousTemporaryColorMarker() { ensureWindowControllerReady().previousTemporaryColorMarker() }
    func nextHighlightedLine()        { ensureWindowControllerReady().nextHighlightedLine() }
    func showOutlineAnalysis()        { ensureWindowControllerReady().showOutlineAnalysis() }
    func previousHighlightedLine()    { ensureWindowControllerReady().previousHighlightedLine() }
    func selectHighlightedLineArea()  { ensureWindowControllerReady().selectHighlightedLineArea() }
    func insertFileContents()         { ensureWindowControllerReady().insertFileContents() }
    func insertControlCode()          { ensureWindowControllerReady().insertControlCode() }
    func selectNextTab()              { ensureWindowControllerReady().selectRelativeTab(1) }
    func selectPreviousTab()          { ensureWindowControllerReady().selectRelativeTab(-1) }
    func showTabList()                { ensureWindowControllerReady().showTabList() }
    func closeOtherTabs()             { ensureWindowControllerReady().closeTabs(.others) }
    func closeTabsLeft()              { ensureWindowControllerReady().closeTabs(.left) }
    func closeTabsRight()             { ensureWindowControllerReady().closeTabs(.right) }
    func focusEditor()                { ensureWindowControllerReady().focusEditor() }
    func focusUtilityPane()           { ensureWindowControllerReady().focusUtilityPane() }
    func showPageSetup()              { ensureWindowControllerReady().showPageSetup() }
    func printDocument()              { ensureWindowControllerReady().printDocument() }
    func reloadDocument()             { ensureWindowControllerReady().reloadDocument() }
    func toggleViewMode()             { ensureWindowControllerReady().toggleViewMode() }
    func toggleOverwriteProtection()  { ensureWindowControllerReady().toggleOverwriteProtection() }
    func toggleHistoryRecording()     { ensureWindowControllerReady().toggleHistoryRecording() }
    func showFileProperties()         { ensureWindowControllerReady().showFileProperties() }
    func appendRead()                 { ensureWindowControllerReady().appendRead() }
    func appendSave()                 { ensureWindowControllerReady().appendSave() }
    func renameFile()                 { ensureWindowControllerReady().renameFile() }
    func openPartialFile()            { ensureWindowControllerReady().openPartialFile() }
    func openBinaryFile()             { ensureWindowControllerReady().openBinaryFile() }
    func showProjectHistory()         { ensureWindowControllerReady().showProjectHistory() }
    func saveWorkspaceAs()            { ensureWindowControllerReady().saveWorkspaceAs() }
    func openWorkspace()              { ensureWindowControllerReady().openWorkspace() }
    func showWorkspaceHistory()       { ensureWindowControllerReady().showWorkspaceHistory() }
    func closeAndOpen()               { ensureWindowControllerReady().closeAndOpen() }
    func showFind()                   { ensureWindowControllerReady().showFind() }
    func showFindUpward()             { ensureWindowControllerReady().showFindUpward() }
    func findWordAtCursor()           { ensureWindowControllerReady().findWordAtCursor() }
    func captureSearchStringAtCursor() { ensureWindowControllerReady().captureSearchStringAtCursor() }
    func moveToDocumentStart()        { ensureWindowControllerReady().moveToDocumentStart() }
    func moveToDocumentEnd()          { ensureWindowControllerReady().moveToDocumentEnd() }
    func moveToScreenStart()          { ensureWindowControllerReady().moveToScreenStart() }
    func moveToScreenEnd()            { ensureWindowControllerReady().moveToScreenEnd() }
    func moveToWordStart()            { ensureWindowControllerReady().moveToWordStart() }
    func moveToWordEnd()              { ensureWindowControllerReady().moveToWordEnd() }
    func moveWordRightSalnen()        { ensureWindowControllerReady().moveWordRightSalnen() }
    func moveToLineStart()            { ensureWindowControllerReady().moveToLineStart() }
    func moveToLineEnd()              { ensureWindowControllerReady().moveToLineEnd() }
    func moveToLineEndAfterCharacter() { ensureWindowControllerReady().moveToLineEndAfterCharacter() }
    func moveToLogicalLineStart()     { ensureWindowControllerReady().moveToLogicalLineStart() }
    func moveToLogicalLineEnd()       { ensureWindowControllerReady().moveToLogicalLineEnd() }
    func movePage(forward: Bool)      { ensureWindowControllerReady().movePage(forward: forward) }
    func moveHalfPage(forward: Bool)  { ensureWindowControllerReady().moveHalfPage(forward: forward) }
    func scrollEditor(forward: Bool, preserveCursor: Bool) { ensureWindowControllerReady().scrollEditor(forward: forward, preserveCursor: preserveCursor) }
    func moveToAdjacentTab(forward: Bool) { ensureWindowControllerReady().moveToAdjacentTab(forward: forward) }
    func moveToMatchingBracket()      { ensureWindowControllerReady().moveToMatchingBracket() }
    func moveToBrace(opening: Bool)   { ensureWindowControllerReady().moveToBrace(opening: opening) }
    func moveToMatchingTag()          { ensureWindowControllerReady().moveToMatchingTag() }
    func moveToLastEditMark()         { ensureWindowControllerReady().moveToLastEditMark() }
    func moveToPreviousCursorPosition() { ensureWindowControllerReady().moveToPreviousCursorPosition() }
    func showReplace()                { ensureWindowControllerReady().showFind(showingReplace: true) }
    func replaceAll()                 { ensureWindowControllerReady().replaceAllFromFindBar() }
    func findNext()                   { ensureWindowControllerReady().findAgain(direction: .next) }
    func findPrevious()               { ensureWindowControllerReady().findAgain(direction: .previous) }
    func showGoToLine()                { ensureWindowControllerReady().showGoToLine() }
    func showQuickOpen()               { ensureWindowControllerReady().showQuickOpen() }
    func showGrep()                    { ensureWindowControllerReady().showGrep() }
    func showGrepReplace()             { ensureWindowControllerReady().showGrep() }
    func grepCurrentDocument()         { ensureWindowControllerReady().grepCurrentDocument() }
    func grepOpenDocuments()           { ensureWindowControllerReady().grepOpenDocuments() }
    func refineGrepResults()           { ensureWindowControllerReady().refineGrepResults() }
    func outputGrepResultsAsDocument() { ensureWindowControllerReady().outputGrepResultsAsDocument() }
    func clearSearchHistory()          { ensureWindowControllerReady().clearSearchHistory() }
    func toggleFindOption(_ option: FindOption) { ensureWindowControllerReady().toggleFindOption(option) }
    func isFindOptionEnabled(_ option: FindOption) -> Bool {
        ensureWindowControllerReady().isFindOptionEnabled(option)
    }
    func showStatusMessage(_ message: String, duration: TimeInterval = 1.5) {
        ensureWindowControllerReady().showStatusMessage(message, duration: duration)
    }
    func updateMacroActivity(isRunning: Bool) {
        activeMacroCount = max(0, activeMacroCount + (isRunning ? 1 : -1))
        ensureWindowControllerReady().updateMacroActivity(isRunning: activeMacroCount > 0)
    }
    func showMacroError(name: String, message: String, timestamp: Date = Date()) {
        ensureWindowControllerReady().appendMacroError(name: name, message: message, timestamp: timestamp)
    }
    func showOutputPane() { ensureWindowControllerReady().showOutputPane() }
    var outputTextForTesting: String { ensureWindowControllerReady().outputTextForTesting }
    func addCursorAbove()              { ensureWindowControllerReady().addCursorAbove() }
    func addCursorBelow()              { ensureWindowControllerReady().addCursorBelow() }
    func selectNextOccurrence()        { ensureWindowControllerReady().selectNextOccurrence() }
    func selectAllOccurrences()        { ensureWindowControllerReady().selectAllOccurrences() }
    func undoLastAddedCursor()         { ensureWindowControllerReady().undoLastAddedCursor() }
    func beginColumnSelection()        { ensureWindowControllerReady().beginColumnSelection() }
    func selectCurrentWord()            { ensureWindowControllerReady().macroEditor.selectCurrentWord() }
    func selectCurrentLine()            { ensureWindowControllerReady().macroEditor.selectCurrentLine() }
    func selectCurrentParagraph()       { ensureWindowControllerReady().macroEditor.selectCurrentParagraph() }
    func copyWithQuotePrefix()          { _ = ensureWindowControllerReady().macroEditor.copyWithQuotePrefix() }
    func pasteRemovingQuotePrefix()     { _ = ensureWindowControllerReady().macroEditor.pasteRemovingQuotePrefix() }
    func restoreLastDeletedText() {
        if !ensureWindowControllerReady().macroEditor.restoreLastDeletedText() {
            showStatusMessage("No deleted text to restore")
        }
    }
    func correctCapsLockMistake() {
        if !ensureWindowControllerReady().macroEditor.correctCapsLockMistake() {
            showStatusMessage("No word or selection to correct")
        }
    }
    func reconvertWithInputMethod() {
        if !ensureWindowControllerReady().macroEditor.reconvertWithCurrentInputMethod() {
            showStatusMessage("The active input method does not support reconversion")
        }
    }
    func appendCopy() { _ = ensureWindowControllerReady().macroEditor.appendSelectionToClipboard(cut: false) }
    func appendCut() { _ = ensureWindowControllerReady().macroEditor.appendSelectionToClipboard(cut: true) }
    func deleteToLineStart() { ensureWindowControllerReady().macroEditor.deleteToLineStart() }
    func deleteToLineEnd() { ensureWindowControllerReady().macroEditor.deleteToLineEnd() }
    func invertSelections() { ensureWindowControllerReady().macroEditor.invertSelections() }
    func reserveSelections() { ensureWindowControllerReady().macroEditor.reserveSelections() }
    func restoreReservedSelections() { ensureWindowControllerReady().macroEditor.restoreReservedSelections() }
    func boxPaste() { _ = ensureWindowControllerReady().macroEditor.boxPaste() }
    func pastePreviousClipboard() {
        clipboardHistory.poll()
        guard let value = clipboardHistory.entries.dropFirst().first ?? clipboardHistory.entries.first else {
            showStatusMessage("Clipboard history is empty"); return
        }
        ensureWindowControllerReady().macroEditor.multiEditPaste(value)
    }
    func pollClipboard() { clipboardHistory.poll() }
    func showClipboardHistory() {
        clipboardHistory.poll()
        let entries = clipboardHistory.entries
        guard !entries.isEmpty else { showStatusMessage("Clipboard history is empty"); return }
        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 440, height: 26))
        popup.addItems(withTitles: entries.map {
            let oneLine = $0.replacingOccurrences(of: "\n", with: " ↩ ")
            return String(oneLine.prefix(100))
        })
        let alert = NSAlert(); alert.messageText = "Clipboard History"
        alert.informativeText = "Choose an earlier text value to paste at every active selection."
        alert.accessoryView = popup
        alert.addButton(withTitle: "Paste"); alert.addButton(withTitle: "Clear History")
        alert.addButton(withTitle: "Cancel")
        let response = alert.runModal()
        if response == .alertFirstButtonReturn, entries.indices.contains(popup.indexOfSelectedItem) {
            let editor = ensureWindowControllerReady().macroEditor
            editor.batchReplace(editor.selectionSet.ranges, with: entries[popup.indexOfSelectedItem])
        } else if response == .alertSecondButtonReturn {
            clipboardHistory.clear()
        }
    }
    func clearHistory(_ kind: SearchHistoryStore.Kind) {
        ensureWindowControllerReady().clearSearchHistory(kind)
    }
    func clearClipboardHistory() {
        clipboardHistory.clear()
        showStatusMessage("Clipboard history cleared")
    }
    func clearRecentFiles() { RecentItems.clearFiles(); showStatusMessage("Recent files cleared") }
    func clearRecentFolders() { RecentItems.clearFolders(); showStatusMessage("Recent project folders cleared") }
    func clearRecentWorkspaces() { RecentItems.clearWorkspaces(); showStatusMessage("Recent workspaces cleared") }
    func clearRecentEncodings() { RecentEncodings.clearAll(); showStatusMessage("Recent encodings cleared") }
    func clearAllHistories() {
        ensureWindowControllerReady().clearSearchHistory()
        clipboardHistory.clear()
        RecentItems.clearAll()
        RecentEncodings.clearAll()
        showStatusMessage("All histories cleared")
    }
    func toggleFreeCursor() {
        preferences.freeCursorEnabled.toggle()
        saveAndApplyPreferences()
    }
    func exportSettings(to url: URL) throws { try preferencesStore.export(preferences, to: url) }
    func importSettings(from url: URL) throws {
        preferences = try preferencesStore.importSettings(from: url)
        preferencesStore.save(preferences)
        windowController?.applyPreferences(preferences)
    }
    func restoreDefaultSettings() {
        preferencesStore.resetToDefaults()
        preferences = .defaults
        windowController?.applyPreferences(preferences)
    }
    func showSettingsExportPanel() {
        let panel = NSSavePanel(); panel.nameFieldStringValue = "MaruEdit-settings.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try exportSettings(to: url); showStatusMessage("Settings exported") }
        catch { NSAlert(error: error).runModal() }
    }
    func showSettingsImportPanel() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try importSettings(from: url); showStatusMessage("Settings imported") }
        catch { NSAlert(error: error).runModal() }
    }
    func confirmRestoreDefaultSettings() {
        let alert = NSAlert(); alert.messageText = "Restore Default Settings?"
        alert.informativeText = "All MaruEdit appearance, editing, file, search, keyboard, macro, and advanced settings will return to their defaults."
        alert.addButton(withTitle: "Restore"); alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        restoreDefaultSettings(); showStatusMessage("Default settings restored")
    }
    func showJapaneseUserDictionaryHelp() {
        openDocumentationURL(URL(string: "https://support.apple.com/guide/japanese-input-method/edit-and-use-your-user-dictionaries-jpim10228/mac")!)
    }
    func performLineCommand(_ command: LineEditCommand) { ensureWindowControllerReady().performLineCommand(command) }
    func toggleBookmark()               { ensureWindowControllerReady().toggleBookmark() }
    func nextBookmark()                 { ensureWindowControllerReady().nextBookmark() }
    func previousBookmark()             { ensureWindowControllerReady().previousBookmark() }
    func clearBookmarks()               { ensureWindowControllerReady().clearBookmarks() }
    func showBookmarkList()              { ensureWindowControllerReady().showBookmarkList() }
    func toggleInputMode()               { ensureWindowControllerReady().toggleInputMode() }
    func moveWordLeft()                  { ensureWindowControllerReady().moveWordLeft() }
    func moveWordRight()                 { ensureWindowControllerReady().moveWordRight() }
    func moveToParagraphStart()          { ensureWindowControllerReady().moveToParagraphStart() }
    func moveToParagraphEnd()            { ensureWindowControllerReady().moveToParagraphEnd() }
    func deleteWordBackward()            { ensureWindowControllerReady().deleteWordBackward() }
    func deleteWordForward()             { ensureWindowControllerReady().deleteWordForward() }
    func toggleMarker(_ color: MarkerColor) { ensureWindowControllerReady().toggleMarker(color) }
    func nextMarker()                    { ensureWindowControllerReady().nextMarker() }
    func previousMarker()                { ensureWindowControllerReady().previousMarker() }
    func clearMarkers()                  { ensureWindowControllerReady().clearMarkers() }
    func nextEditMark()                  { ensureWindowControllerReady().nextEditMark() }
    func previousEditMark()              { ensureWindowControllerReady().previousEditMark() }
    func clearEditMarks()                { ensureWindowControllerReady().clearEditMarks() }
    func toggleSearchHighlight()         { ensureWindowControllerReady().toggleSearchHighlight() }
    func selectAllSearchMatches()        { ensureWindowControllerReady().selectAllSearchMatches() }
    func colorAllSearchMatches()         { ensureWindowControllerReady().colorAllSearchMatches() }
    func clearSearchColors()             { ensureWindowControllerReady().clearSearchColors() }
    func listAllSearchMatches()           { ensureWindowControllerReady().listAllSearchMatches() }
    func outlineAllSearchMatches()        { ensureWindowControllerReady().outlineAllSearchMatches() }
    func listSearchColorLayers()          { ensureWindowControllerReady().listSearchColorLayers() }
    func showMarkerList()                 { ensureWindowControllerReady().showMarkerList() }
    func clearAllDocumentMarkers()        { ensureWindowControllerReady().clearAllDocumentMarkers() }
    func navigateResult(forward: Bool, grepOnly: Bool) { ensureWindowControllerReady().navigateResult(forward: forward, grepOnly: grepOnly) }
    func returnToSearchStart()            { ensureWindowControllerReady().returnToSearchStart() }
    func setSearchRangeFromSelection()    { ensureWindowControllerReady().setSearchRangeFromSelection() }
    func selectSearchRange()              { ensureWindowControllerReady().selectSearchRange() }
    func clearSearchRange()               { ensureWindowControllerReady().clearSearchRange() }
    func showHighlightList()             { ensureWindowControllerReady().showHighlightList() }
    func showCompletions()               { ensureWindowControllerReady().showCompletions() }
    func toggleTableMode()               { ensureWindowControllerReady().toggleTableMode() }
    func toggleVerticalLayout()          { ensureWindowControllerReady().toggleVerticalLayout() }
    func toggleColumnLayout()            { ensureWindowControllerReady().toggleColumnLayout() }
    func splitEditorVertical()           { ensureWindowControllerReady().showEditorSplit(.vertical) }
    func splitEditorHorizontal()         { ensureWindowControllerReady().showEditorSplit(.horizontal) }
    func closeEditorSplit()              { ensureWindowControllerReady().closeEditorSplit() }
    func toggleLinkedEditorScrolling()   { ensureWindowControllerReady().toggleLinkedEditorScrolling() }
    func compareWithNextDocument()       { ensureWindowControllerReady().compareWithNextDocument() }
    func nextDifference()                { ensureWindowControllerReady().nextDifference() }
    func previousDifference()            { ensureWindowControllerReady().previousDifference() }
    func mergeCurrentDifferenceFromRight() { ensureWindowControllerReady().mergeCurrentDifferenceFromRight() }
    func generateTagsFile()                { ensureWindowControllerReady().generateTagsFile() }
    func showTagJump()                    { ensureWindowControllerReady().showTagJump() }
    func directTagJump()                  { ensureWindowControllerReady().directTagJump() }
    func backTagJump()                    { ensureWindowControllerReady().backTagJump() }
    func toggleFold()                    { ensureWindowControllerReady().toggleFold() }
    func collapseAllFolds()              { ensureWindowControllerReady().collapseAllFolds() }
    func expandAllFolds()                { ensureWindowControllerReady().expandAllFolds() }
    func beginPartialOutlineEditing()    { ensureWindowControllerReady().beginPartialOutlineEditing() }
    func endPartialOutlineEditing()      { ensureWindowControllerReady().endPartialOutlineEditing() }
    func toggleSidebar()               { ensureWindowControllerReady().toggleSidebar() }
    func toggleWrapLines()             { ensureWindowControllerReady().toggleWrapLines() }
    func setTabWidth(_ width: Int)      { ensureWindowControllerReady().setTabWidth(width) }
    func showFontPanel()                { ensureWindowControllerReady().showFontPanel() }
    func showMenuCustomization()        { onShowMenuCustomization?() }
    func toggleRuler() {
        preferences.classicChrome.showRuler.toggle()
        saveAndApplyPreferences()
    }
    func toggleClassicToolbar() {
        preferences.classicChrome.showToolbar.toggle()
        saveAndApplyPreferences()
    }
    func setRulerInterval(_ interval: Int) {
        preferences.classicChrome.rulerInterval = interval == 8 ? 8 : 10
        saveAndApplyPreferences()
    }
    func toggleRulerTabStops() {
        preferences.classicChrome.showTabStops.toggle()
        saveAndApplyPreferences()
    }
    func toggleLineNumbers() {
        preferences.showLineNumbers.toggle()
        saveAndApplyPreferences()
    }
    func toggleClassicHeading() {
        preferences.classicChrome.showHeading.toggle()
        saveAndApplyPreferences()
    }
    func toggleFunctionKeyStrip() {
        preferences.classicChrome.showCommandStrip.toggle()
        saveAndApplyPreferences()
    }
    func toggleStatusBar() { ensureWindowControllerReady().toggleStatusBar() }
    func toggleOutputPane() { ensureWindowControllerReady().toggleOutputPane() }
    func focusOutputPane() { ensureWindowControllerReady().focusOutputPane() }
    func toggleSpellChecking() { ensureWindowControllerReady().toggleSpellChecking() }
    func showCharacterCode() { ensureWindowControllerReady().showCharacterCode() }
    func showCharacterCount() { ensureWindowControllerReady().showCharacterCount() }
    func redrawEditor() { ensureWindowControllerReady().redrawEditor() }
    func toggleFullScreen() { ensureWindowControllerReady().toggleFullScreen() }
    private func saveAndApplyPreferences() {
        preferencesStore.save(preferences)
        windowController?.applyPreferences(preferences)
    }
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
        case .viewToggleRuler: preferences.classicChrome.showRuler
        case .viewRulerInterval8: preferences.classicChrome.rulerInterval == 8
        case .viewRulerInterval10: preferences.classicChrome.rulerInterval == 10
        case .viewToggleTabStops: preferences.classicChrome.showTabStops
        case .viewToggleVerticalLayout: ensureWindowControllerReady().macroEditor.isVerticalLayout
        case .viewToggleColumnLayout: ensureWindowControllerReady().macroEditor.isColumnLayout
        case .viewToggleLineNumbers: preferences.showLineNumbers
        case .viewToggleHeading: preferences.classicChrome.showHeading
        case .viewToggleFunctionKeys: preferences.classicChrome.showCommandStrip
        case .viewToggleStatusBar: ensureWindowControllerReady().isStatusBarVisibleForTesting
        case .viewToggleOutputPane: ensureWindowControllerReady().isOutputPaneVisibleForTesting
        case .otherToggleFreeCursor: preferences.freeCursorEnabled
        default: false
        }
    }

    private func isCommandSelected(_ id: CommandID) -> Bool {
        let findOptions: [CommandID: FindOption] = [
            .searchToggleCaseSensitive: .caseSensitive,
            .searchToggleWholeWord: .wholeWord,
            .searchToggleRegex: .regularExpression,
            .searchToggleFuzzy: .fuzzy,
        ]
        if let option = findOptions[id] { return isFindOptionEnabled(option) }
        return isViewCommandActive(id)
    }
    func clearRecoveryData()           { ensureWindowControllerReady().clearRecoveryData() }
    func makeMacroHost(
        permissions: Set<MacroPermission> = [.currentDocument, .clipboard],
        pasteboard: NSPasteboard = .general,
        message: ((String) -> Void)? = nil,
        prompt: ((String, String) -> String?)? = nil
    ) -> MacroHost {
        let window = ensureWindowControllerReady()
        return MacroCommandBridge(
            coordinator: self, editor: window.macroEditor, permissions: permissions,
            pasteboard: pasteboard,
            message: message, prompt: prompt).host
    }
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
