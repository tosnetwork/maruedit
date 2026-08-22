import AppKit
import MaruEditCore

private final class TitlebarCursorPositionLabel: NSTextField {
    var onActivate: (() -> Void)?

    init() {
        super.init(frame: .zero)
        stringValue = "1:1"
        font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        alignment = .right
        isBordered = false
        isEditable = false
        drawsBackground = false
        textColor = .secondaryLabelColor
        setAccessibilityRole(.button)
        setAccessibilityLabel(AppLocalization.string("status.accessibility.cursor"))
        toolTip = AppLocalization.string("titlebar.cursorTooltip", [1, 1])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func update(line: Int, column: Int) {
        let line = max(1, line), column = max(1, column)
        stringValue = "\(line):\(column)"
        toolTip = AppLocalization.string("titlebar.cursorTooltip", [line, column])
    }

    override var acceptsFirstResponder: Bool { true }
    override func mouseDown(with event: NSEvent) { onActivate?() }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 || event.keyCode == 76 || event.charactersIgnoringModifiers == " " {
            onActivate?()
        } else {
            super.keyDown(with: event)
        }
    }
    override func accessibilityPerformPress() -> Bool {
        onActivate?()
        return true
    }
}

@MainActor
final class MainWindowController: NSWindowController,
    EditorViewControllerDelegate,
    TabBarViewDelegate,
    SidebarDelegate,
    FindBarDelegate,
    QuickOpenDelegate,
    StatusBarViewDelegate,
    GrepPanelDelegate,
    OutputPaneViewDelegate
{
    private var splitView: NSSplitView!
    private var sidebarVC: SidebarViewController!
    private var tabBar: TabBarView!
    private var findBar: FindBarView!
    private var editorVC: EditorViewController!
    private var editorSplitView: NSSplitView!
    private var secondaryEditorVC: EditorViewController?
    private var linkedEditorScrolling = false
    private var diffTargetDocument: Document?
    private var diffHunks: [TextDiffHunk] = []
    private var currentDiffIndex = 0
    private var tagBackStack: [(url: URL, offset: Int)] = []
    var openAssociatedURL: (URL) -> Void = { NSWorkspace.shared.open($0) }
    private var statusBar: StatusBarView!
    private var cursorPositionAccessory: NSTitlebarAccessoryViewController!
    private var cursorPositionLabel: TitlebarCursorPositionLabel!
    private var modifierFlagsMonitor: Any?
    private var classicChrome: ClassicWorkspaceChrome!
    private var workspaceStyle: WorkspaceStyle = .classic
    private var isStatusBarVisible = true
    private var fontSizePopover: NSPopover?
    private var statusFontResetSize: CGFloat?
    var macroEditor: EditorViewController { editorVC }

    private var quickOpen: QuickOpenPanel?

    /// The last query actually executed, so Find Next works after the bar
    /// is closed.
    private var lastQuery: SearchQuery?
    private var searchStartOffset: Int?
    private var searchColorIndex = 0
    private let searchHistoryStore = SearchHistoryStore()
    private var searchHistory = SearchHistoryState()

    private var grepPanel: GrepPanel?
    private var outputPane: OutputPaneView?
    private var lastGrepRequest: GrepRequest?
    private var grepCancellation: CancellationToken?
    private var grepReplaceCancellation: CancellationToken?
    private var grepReplacePreview: GrepReplacePreviewWindowController?
    var externalCommandCancellation: ExternalCommandCancellation?
    /// Grep reads and decodes every file it visits, so it never runs on
    /// the main thread (ROADMAP.md M3-04, "No main-actor traversal").
    private let grepQueue = DispatchQueue(label: "com.maruedit.grep", qos: .userInitiated)
    /// Files at or above the reduced-features threshold are decoded and
    /// normalized here. Only the completed Document crosses to MainActor.
    private let fileIOQueue = DispatchQueue(label: "com.maruedit.file-io", qos: .userInitiated)

    private var documentController = DocumentController()
    private let sessionStore = SessionStore()
    private let sessionSaveDebouncer = Debouncer(delay: 1.5)
    private let recoveryStore = RecoveryStore()
    private let recoverySaveDebouncer = Debouncer(delay: 1.5)
    private var sidebarManuallyCollapsed = false
    var onEditorFontChange: ((NSFont) -> Void)?
    var onClassicToolbarCommand: ((CommandID) -> Void)?
    var onCrossDocumentScroll: ((NSPoint) -> Void)? {
        didSet { editorVC.onCrossDocumentScroll = onCrossDocumentScroll }
    }
    var onStatusMacroControl: (() -> Void)?
    private var floatingToolbarPanel: NSPanel?
    private static let floatingToolbarDefaultsKey = "MaruClassicToolbarFloating"

    /// Convenience shims onto `documentController` so the UI-orchestration
    /// code below (largely unchanged from before the M1-02 extraction)
    /// doesn't need to spell out `documentController.` at every call site.
    private var curIdx: Int { documentController.currentIndex }
    private var curDoc: Document? { documentController.currentDocument }

    convenience init() {
        self.init(fileTypeResolver: .builtIn)
    }

    convenience init(fileTypeResolver: FileTypeProfileResolver) {
        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1100, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false
        )
        w.minSize = NSSize(width: 640, height: 420)
        w.tabbingMode = .disallowed
        w.title = AppLocalization.string("window.document.untitledTitle")
        w.isReleasedWhenClosed = false
        if !w.setFrameUsingName("MainWindow") { w.center() }
        w.setFrameAutosaveName("MainWindow")
        w.backgroundColor = Theme.background

        self.init(window: w)
        documentController = DocumentController(fileTypeResolver: fileTypeResolver)
        buildUI()
        if UserDefaults.standard.bool(forKey: Self.floatingToolbarDefaultsKey) {
            setClassicToolbarFloating(true)
        }
        searchHistory = searchHistoryStore.load()
        syncSearchHistoryUI()
        newDocument()
        NotificationCenter.default.addObserver(
            self, selector: #selector(windowDidBecomeKey),
            name: NSWindow.didBecomeKeyNotification, object: w
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(windowDidResize),
            name: NSWindow.didResizeNotification, object: w
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        if let modifierFlagsMonitor { NSEvent.removeMonitor(modifierFlagsMonitor) }
    }

    // MARK: - UI setup
    // Tab bar and status bar are OUTSIDE the NSSplitView (direct children of contentView).
    // This avoids NSSplitView layer compositing issues that made the tab bar invisible.

    private func buildUI() {
        guard let cv = window?.contentView else { return }

        cursorPositionLabel = TitlebarCursorPositionLabel()
        cursorPositionLabel.onActivate = { [weak self] in self?.showGoToLine() }
        let cursorHost = NSView(frame: NSRect(x: 0, y: 0, width: 72, height: 22))
        cursorPositionLabel.frame = NSRect(x: 4, y: 3, width: 62, height: 16)
        cursorPositionLabel.autoresizingMask = [.minXMargin]
        cursorHost.addSubview(cursorPositionLabel)
        cursorPositionAccessory = NSTitlebarAccessoryViewController()
        cursorPositionAccessory.view = cursorHost
        cursorPositionAccessory.layoutAttribute = .right
        window?.addTitlebarAccessoryViewController(cursorPositionAccessory)

        let tabH: CGFloat = 32
        let statusH: CGFloat = isStatusBarVisible ? 24 : 0

        tabBar = TabBarView()
        tabBar.delegate = self
        tabBar.autoresizingMask = [.minYMargin]
        tabBar.frame = NSRect(x: 0, y: cv.bounds.height - tabH, width: cv.bounds.width, height: tabH)
        cv.addSubview(tabBar)

        statusBar = StatusBarView()
        statusBar.delegate = self
        statusBar.setClassicAppearance(workspaceStyle == .classic)
        statusBar.autoresizingMask = [.width, .maxYMargin]
        statusBar.frame = NSRect(x: 0, y: 0, width: cv.bounds.width, height: statusH)
        cv.addSubview(statusBar)
        statusBar.updateCapsLock(NSEvent.modifierFlags.contains(.capsLock))
        modifierFlagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.statusBar.updateCapsLock(event.modifierFlags.contains(.capsLock))
            return event
        }

        classicChrome = ClassicWorkspaceChrome()
        classicChrome.onCommand = { [weak self] command in
            self?.onClassicToolbarCommand?(command)
        }
        classicChrome.onToolbarSearch = { [weak self] pattern in
            self?.performToolbarSearch(pattern)
        }
        classicChrome.onLayoutChange = { [weak self] in self?.layoutContentViews() }
        statusBar.onPreferredWidthChange = { [weak self] in self?.layoutContentViews() }
        classicChrome.autoresizingMask = [.width, .height]
        cv.addSubview(classicChrome)

        findBar = FindBarView()
        findBar.delegate = self
        findBar.isHidden = true
        findBar.autoresizingMask = [.width, .minYMargin]
        findBar.frame = NSRect(x: 0, y: cv.bounds.height - tabH, width: cv.bounds.width, height: 0)
        cv.addSubview(findBar)

        splitView = NSSplitView()
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        splitView.delegate = self
        splitView.autoresizingMask = [.width, .height]
        splitView.frame = NSRect(x: 0, y: statusH, width: cv.bounds.width, height: cv.bounds.height - tabH - statusH)
        cv.addSubview(splitView)

        sidebarVC = SidebarViewController()
        sidebarVC.sidebarDelegate = self
        let sideView = sidebarVC.view
        sideView.setFrameSize(NSSize(width: 220, height: splitView.bounds.height))

        editorVC = EditorViewController()
        editorVC.delegate = self
        editorSplitView = NSSplitView()
        editorSplitView.isVertical = true
        editorSplitView.dividerStyle = .thin
        editorSplitView.setFrameSize(NSSize(
            width: splitView.bounds.width - 221, height: splitView.bounds.height))
        let editorView = editorVC.view
        editorView.frame = editorSplitView.bounds
        editorSplitView.addSubview(editorView)

        splitView.addSubview(sideView)
        splitView.addSubview(editorSplitView)
        splitView.setHoldingPriority(.defaultHigh, forSubviewAt: 0)
        splitView.setHoldingPriority(.defaultLow, forSubviewAt: 1)

        updateTabBarFrame()

        DispatchQueue.main.async { [weak self] in
            self?.splitView.setPosition(220, ofDividerAt: 0)
        }
    }

    func showStatusMessage(_ message: String, duration: TimeInterval = 1.5) {
        statusBar.showTransientMessage(message, duration: duration)
    }

    func showLocalizedStatus(
        _ key: String, _ arguments: [CVarArg] = [], duration: TimeInterval = 1.5
    ) {
        showStatusMessage(AppLocalization.string(key, arguments), duration: duration)
    }

    func refreshLocalizedInterface() {
        if let quickOpen {
            window?.removeChildWindow(quickOpen)
            quickOpen.close()
            self.quickOpen = nil
        }
        grepPanel?.window.close()
        grepPanel = nil
        grepReplacePreview?.close()
        grepReplacePreview = nil
        classicChrome.refreshLocalization()
        statusBar.refreshLocalization()
        sidebarVC.refreshLocalization()
        layoutContentViews()
        showStatusMessage(AppLocalization.string(.languageChanged))
    }

    func updateMacroActivity(isRunning: Bool) {
        statusBar.updateMacroActivity(isRunning: isRunning)
    }
    func updateMacroRecording(isRecording: Bool) {
        statusBar.updateMacroRecording(isRecording: isRecording)
    }

    func applyPreferences(_ preferences: Preferences) {
        Theme.activeName = preferences.theme
        workspaceStyle = preferences.workspaceStyle
        classicChrome.isHidden = workspaceStyle != .classic
        cursorPositionAccessory.view.isHidden = workspaceStyle != .classic
        classicChrome.applyVisibility(preferences.classicChrome)
        tabBar.compactStyle = workspaceStyle == .classic
        configureWorkspaceToolbar()
        window?.backgroundColor = Theme.background
        tabBar.applyTheme()
        statusBar.applyTheme()
        statusBar.setCursorPositionVisible(workspaceStyle != .classic)
        sidebarVC.applyTheme()
        editorVC.applyPreferences(preferences)
        secondaryEditorVC?.applyPreferences(preferences)
        layoutContentViews()
        refreshStatus()
    }

    var isClassicWorkspace: Bool { workspaceStyle == .classic }
    var isClassicChromeVisibleForTesting: Bool { !classicChrome.isHidden }
    var isClassicToolbarVisibleForTesting: Bool { classicChrome.isToolbarVisible }
    var classicHeadingForTesting: String { classicChrome.headingText }
    var classicChromeVisibilityForTesting: ClassicChromeOptions { classicChrome.visibilityForTesting }
    var classicRulerStateForTesting: (origin: CGFloat, column: Int) { classicChrome.rulerStateForTesting }
    var classicCursorPositionForTesting: (text: String, placement: NSLayoutConstraint.Attribute, hidden: Bool) {
        (cursorPositionLabel.stringValue, cursorPositionAccessory.layoutAttribute,
         cursorPositionAccessory.view.isHidden)
    }
    var classicRulerMaximumColumnForTesting: Int { classicChrome.rulerMaximumColumnForTesting }
    var classicRulerConfigurationForTesting: (interval: Int, showsTabStops: Bool, tabWidth: Int) {
        classicChrome.rulerConfigurationForTesting
    }
    var isClassicHeadingVisibleForTesting: Bool { classicChrome.isHeadingActuallyVisibleForTesting }
    var classicToolbarIdentifiersForTesting: [String] {
        classicChrome.toolbarCommandIDs
    }
    var classicToolbarLayoutForTesting: [String] { classicChrome.toolbarLayoutEntries }
    var classicToolbarDisplayModeForTesting: ToolbarDisplayMode { classicChrome.toolbarDisplayMode }
    var classicToolbarIconSizeForTesting: ToolbarIconSize { classicChrome.toolbarIconSize }
    var classicToolbarIconSymbolsForTesting: [String: String] {
        classicChrome.toolbarIconSymbolsForTesting
    }
    var isClassicToolbarSearchVisibleForTesting: Bool { classicChrome.isToolbarSearchVisible }
    var isClassicToolbarFloatingForTesting: Bool { classicChrome.isToolbarFloating }
    var isFunctionKeyStripMergedForTesting: Bool { classicChrome.isFunctionKeyStripMerged }
    var classicFunctionKeyCommandsForTesting: [String?] { classicChrome.functionKeyCommandIDs }
    var classicFunctionKeyCountForTesting: Int { classicChrome.functionKeyCount }
    var classicFunctionKeyTitlesForTesting: [String] { classicChrome.functionKeyTitlesForTesting }
    var classicFunctionKeyVisualStyleForTesting: (flatButtons: Bool, separatorSlots: [Int]) {
        classicChrome.functionKeyVisualStyleForTesting
    }
    func classicToolbarPresentationForTesting(
        _ command: CommandID
    ) -> (enabled: Bool, selected: Bool)? {
        classicChrome.toolbarPresentation(for: command)
    }
    func classicFunctionKeyPresentationForTesting(
        _ index: Int
    ) -> (enabled: Bool, selected: Bool)? {
        classicChrome.functionKeyPresentation(at: index)
    }

    func setClassicToolbarLayoutForTesting(_ entries: [String]) {
        classicChrome.setToolbarLayoutForTesting(entries)
    }
    func configureClassicCommands(_ commands: [(CommandID, String)]) {
        classicChrome.configureAvailableCommands(commands)
    }
    func configureClassicCommandPresentation(
        _ provider: @escaping (CommandID) -> (enabled: Bool, selected: Bool)
    ) {
        classicChrome.configureCommandPresentation(provider)
    }
    func refreshClassicCommandPresentation() {
        classicChrome.refreshCommandPresentation()
    }
    func setClassicToolbarDisplayModeForTesting(_ mode: ToolbarDisplayMode) {
        classicChrome.setToolbarDisplayModeForTesting(mode)
    }
    func setClassicToolbarSearchVisibleForTesting(_ visible: Bool) {
        classicChrome.setToolbarSearchVisibleForTesting(visible)
    }

    func toggleClassicToolbarFloating() {
        setClassicToolbarFloating(!classicChrome.isToolbarFloating)
    }

    func setClassicToolbarFloating(_ floating: Bool) {
        guard floating != classicChrome.isToolbarFloating else { return }
        if floating {
            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 760, height: ClassicWorkspaceChrome.toolbarHeight),
                styleMask: [.titled, .utilityWindow, .resizable], backing: .buffered, defer: false)
            panel.title = AppLocalization.string("classic.toolbarWindowTitle")
            panel.isFloatingPanel = true
            panel.level = .floating
            panel.hidesOnDeactivate = false
            let toolbar = classicChrome.detachToolbarForFloating()
            toolbar.frame = panel.contentView?.bounds ?? .zero
            toolbar.autoresizingMask = [.width, .height]
            panel.contentView?.addSubview(toolbar)
            panel.setFrameAutosaveName("MaruClassicFloatingToolbar")
            panel.orderFront(nil)
            floatingToolbarPanel = panel
        } else {
            floatingToolbarPanel?.orderOut(nil)
            classicChrome.attachFloatingToolbar()
            floatingToolbarPanel = nil
        }
        UserDefaults.standard.set(floating, forKey: Self.floatingToolbarDefaultsKey)
        layoutContentViews()
    }
    func setClassicToolbarIconSizeForTesting(_ size: ToolbarIconSize) {
        classicChrome.setToolbarIconSizeForTesting(size)
    }
    func setFunctionKeyStripMergedForTesting(_ merged: Bool) {
        classicChrome.setFunctionKeyMergeForTesting(merged)
        layoutContentViews()
    }
    var statusBarFrameForTesting: NSRect { statusBar.frame }
    var statusBarEncodingFrameForTesting: NSRect? { statusBar.frame(for: .encoding) }
    var statusBarInputModeFrameForTesting: NSRect? { statusBar.frame(for: .inputMode) }
    var classicChromeFrameForTesting: NSRect { classicChrome.frame }
    func performClassicToolbarSearchForTesting(_ pattern: String) {
        classicChrome.performToolbarSearchForTesting(pattern)
    }
    func setClassicFunctionKeyCommandsForTesting(_ ids: [CommandID?]) {
        classicChrome.setFunctionKeyCommandsForTesting(ids)
    }
    func setClassicFunctionKeyCountForTesting(_ count: Int) {
        classicChrome.setFunctionKeyCountForTesting(count)
    }
    func activateClassicFunctionKeyForTesting(_ index: Int) {
        classicChrome.activateFunctionKeyForTesting(index)
    }

    func activateClassicToolbarCommandForTesting(_ command: CommandID) {
        classicChrome.activateToolbarCommand(command)
    }

    private func configureWorkspaceToolbar() {
        guard let window else { return }
        // The Classic workspace owns its dense command bar inside the content
        // area. Removing NSToolbar also clears autosaved oversized toolbar
        // presentation from older builds.
        window.toolbar = nil
        if workspaceStyle == .classic {
            window.titleVisibility = .visible
        }
    }

    var effectiveWrapLines: Bool { editorVC.effectiveWrapLines }
    var effectiveTabWidth: Int { editorVC.effectiveTabWidth }

    func toggleWrapLines() {
        editorVC.toggleWrapLines()
        refreshStatus()
    }

    func setTabWidth(_ width: Int) {
        editorVC.setTabWidth(width)
        refreshStatus()
    }

    func showFontPanel() {
        NSFontManager.shared.setSelectedFont(editorVC.currentEditorFont, isMultiple: false)
        NSFontManager.shared.orderFrontFontPanel(nil)
    }

    /// Positions the tab bar, Find Bar, Output Pane, split view, and status
    /// bar from the current visibility state. One place to compute these
    /// frames, because as of M3-06 three different things can appear and
    /// disappear above and below the editor.
    private func layoutContentViews() {
        guard let cv = window?.contentView else { return }
        let tabH = tabBar.effectiveHeight
        let statusH: CGFloat = isStatusBarVisible ? 24 : 0
        let findH: CGFloat = findBar.isHidden ? 0 : (findBar.isReplaceRowVisible ? 66 : 34)
        let paneH: CGFloat = (outputPane?.isHidden == false) ? Self.outputPaneHeight : 0
        let topTabH = tabBar.position == .top ? tabH : 0
        let bottomTabH = tabBar.position == .bottom ? tabH : 0
        classicChrome.setStatusBarVisible(isStatusBarVisible)
        let classicTop = workspaceStyle == .classic ? classicChrome.topChromeHeight : 0
        let classicBottom = workspaceStyle == .classic ? classicChrome.bottomChromeHeight : 0
        let baseY = bottomTabH + paneH
        let merged = workspaceStyle == .classic && classicChrome.isFunctionKeyStripMerged
            && isStatusBarVisible
        statusBar.setMergedMode(merged)
        statusBar.setClassicAppearance(workspaceStyle == .classic)
        let mergedFunctionWidth = classicChrome.mergedFunctionKeyWidth(
            totalWidth: cv.bounds.width,
            trailingStatusWidth: merged ? statusBar.preferredMergedWidth : 0)

        classicChrome.externalTopGap = topTabH + findH
        findBar.frame = NSRect(
            x: 0, y: cv.bounds.height
                - (workspaceStyle == .classic ? classicChrome.visibleToolbarHeight : 0)
                - topTabH - findH,
            width: cv.bounds.width, height: findH
        )
        outputPane?.frame = NSRect(
            x: 0, y: bottomTabH + (merged ? 0 : statusH),
            width: cv.bounds.width, height: paneH)
        let statusX = merged ? mergedFunctionWidth : 0
        statusBar.frame = NSRect(
            x: statusX, y: bottomTabH + (merged ? paneH : 0),
            width: max(0, cv.bounds.width - statusX), height: statusH)
        classicChrome.frame = NSRect(
            x: 0, y: (merged ? bottomTabH : statusH + bottomTabH) + paneH,
            width: cv.bounds.width,
            height: cv.bounds.height - (merged ? 0 : statusH) - bottomTabH - paneH)
        splitView.frame = NSRect(
            x: 0, y: statusH + baseY + classicBottom,
            width: cv.bounds.width,
            height: cv.bounds.height - topTabH - findH - statusH - bottomTabH - paneH - classicTop - classicBottom
        )
        updateTabBarFrame()
        updateClassicRuler(currentColumn: lastCursorColumn)
        configureKeyboardFocusLoop()
    }

    private func keyboardFocusLoop() -> [NSView] {
        statusBar.layoutSubtreeIfNeeded()
        var views: [NSView] = []
        if workspaceStyle == .classic && !classicChrome.isHidden {
            views += classicChrome.keyboardFocusableViews
            if !cursorPositionAccessory.view.isHidden { views.append(cursorPositionLabel) }
        }
        if !findBar.isHidden { views += findBar.keyboardFocusableViews }
        if !tabBar.isHidden { views += tabBar.keyboardFocusableViews }
        views.append(editorVC.textView)
        if !sidebarVC.view.isHidden && !splitView.isSubviewCollapsed(sidebarVC.view) {
            views += sidebarVC.keyboardFocusableViews
        }
        if let outputPane, !outputPane.isHidden { views += outputPane.keyboardFocusableViews }
        if isStatusBarVisible { views += statusBar.keyboardFocusableViews }
        var seen = Set<ObjectIdentifier>()
        return views.filter { seen.insert(ObjectIdentifier($0)).inserted && !$0.isHidden }
    }

    private func configureKeyboardFocusLoop() {
        let views = keyboardFocusLoop()
        guard views.count > 1 else { return }
        for index in views.indices {
            views[index].nextKeyView = views[(index + 1) % views.count]
        }
    }

    var keyboardFocusLoopForTesting: [NSView] {
        configureKeyboardFocusLoop()
        return keyboardFocusLoop()
    }

    private static let outputPaneHeight: CGFloat = 200

    @objc private func windowDidResize() {
        layoutContentViews()
    }

    private func updateTabBarFrame() {
        guard let cv = window?.contentView else { return }
        let tabH = tabBar.effectiveHeight
        let editorX = editorXForTabBar()
        tabBar.frame = NSRect(
            x: editorX,
            y: tabBar.position == .top
                ? cv.bounds.height - tabH - (workspaceStyle == .classic ? classicChrome.visibleToolbarHeight : 0)
                : (isStatusBarVisible ? 24 : 0),
            width: cv.bounds.width - editorX,
            height: tabH
        )
        tabBar.isHidden = tabH == 0
    }

    private func editorXForTabBar() -> CGFloat {
        // The sidebar can retain a stale frame and inconsistent hidden/collapsed
        // flags while a restored NSSplitView is settling. The editor container's
        // actual origin is the authoritative geometry for tabs and the ruler.
        return max(0, editorSplitView.frame.minX)
    }

    private var lastCursorColumn = 1

    private func rulerOrigin() -> CGFloat {
        // Maru's character ruler begins immediately after the fixed line
        // number gutter and is not indented by auxiliary panes.
        48
    }

    private func updateClassicRuler(currentColumn: Int) {
        let cellWidth = ("0" as NSString).size(withAttributes: [.font: editorVC.currentEditorFont]).width
        classicChrome.updateRuler(
            editorOrigin: rulerOrigin(), currentColumn: currentColumn, cellWidth: cellWidth,
            tabWidth: editorVC.effectiveTabWidth)
    }

    // MARK: - Cursor persistence across tab switches

    private func saveCursorPosition() {
        guard let doc = curDoc else { return }
        doc.cursorPosition = editorVC.textView.selectedRange().location
        doc.scrollOffset = editorVC.scrollView.contentView.bounds.origin
    }

    private func restoreCursorPosition() {
        guard let doc = curDoc else { return }
        let tv = editorVC.textView!
        let sv = editorVC.scrollView!
        let len = (tv.string as NSString).length
        let pos = min(doc.cursorPosition, len)

        if let lm = tv.layoutManager, len > 0 {
            if doc.scrollOffset != .zero {
                // Full layout needed so the text view frame is tall enough
                // for the entire viewport, not just up to the cursor.
                lm.ensureLayout(forCharacterRange: NSRange(location: 0, length: len))
            } else if pos > 0 {
                lm.ensureLayout(forCharacterRange: NSRange(location: 0, length: min(pos + 1, len)))
            }
        }

        tv.setSelectedRange(NSRange(location: pos, length: 0))
        if doc.scrollOffset != .zero {
            sv.contentView.scroll(to: doc.scrollOffset)
            sv.reflectScrolledClipView(sv.contentView)
        } else {
            tv.scrollRangeToVisible(NSRange(location: pos, length: 0))
        }
    }

    /// Defers cursor restoration to the next run-loop iteration so it
    /// survives the layout pass that `replaceTextStorage` triggers.
    private func deferredRestoreCursor() {
        let targetDoc = curDoc
        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.curDoc === targetDoc else { return }
            self.restoreCursorPosition()
        }
    }

    // MARK: - Document management

    private enum LargeFileOpenChoice: Equatable {
        case open(LargeFileMode?)
        case cancel

        var mode: LargeFileMode? {
            guard case let .open(mode) = self else { return nil }
            return mode
        }
    }

    private func chooseLargeFileMode(for url: URL) throws -> LargeFileOpenChoice {
        let size = try LargeFilePolicy.fileSize(at: url)
        switch LargeFilePolicy.recommendation(forByteCount: size) {
        case .normal:
            return .open(nil)
        case .reducedFeatures:
            return .open(.reducedFeatures)
        case .tooLarge:
            throw DocumentOpenError.fileTooLarge(
                size: size, maximum: LargeFilePolicy.maximumMaterializedSize)
        case .confirmationRequired:
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = SettingsLocalization.text("openLargeFile")
            alert.informativeText = AppLocalization.string("settings.largeFileInfo", [
                ByteCountFormatter.string(fromByteCount: size, countStyle: .file),
                SettingsLocalization.text("largeFileExplanation"),
            ])
            alert.addButton(withTitle: SettingsLocalization.text("continueReduced"))
            alert.addButton(withTitle: SettingsLocalization.text("openReadOnly"))
            alert.addButton(withTitle: SettingsLocalization.text("cancel"))
            switch alert.runModal() {
            case .alertFirstButtonReturn: return .open(.reducedFeatures)
            case .alertSecondButtonReturn: return .open(.readOnly)
            default: return .cancel
            }
        }
    }

    func newDocument() {
        let doc = documentController.newDocument()
        editorVC.document = doc
        refreshTabs()
        refreshStatus()
        scheduleSessionSave()
    }

    func newDocumentFromTemplate() {
        let profiles = documentController.templateProfiles
        guard !profiles.isEmpty else { showLocalizedStatus("status.noProfileTemplates"); return }
        let popup = NSPopUpButton(); popup.addItems(withTitles: profiles.map(\.name)); popup.frame.size.width = 260
        let alert = NSAlert(); alert.messageText = AppLocalization.string("dialog.template.newTitle")
        alert.informativeText = AppLocalization.string("dialog.template.choose")
        alert.accessoryView = popup; alert.addButton(withTitle: AppLocalization.string("common.create"))
        alert.addButton(withTitle: AppLocalization.string(.commonCancel))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            let document = try Document.fromTemplate(profile: profiles[popup.indexOfSelectedItem])
            documentController.addDocument(document); editorVC.document = document
            refreshTabs(); refreshStatus(); scheduleSessionSave()
        } catch { showStatusMessage(error.localizedDescription, duration: 4) }
    }

    func showPageSetup() {
        guard let window else { return }
        NSPageLayout().beginSheet(
            with: NSPrintInfo.shared, modalFor: window,
            delegate: nil, didEnd: nil, contextInfo: nil)
    }

    func printDocument() {
        guard let window else { return }
        let printable = NSTextView(frame: NSRect(x: 0, y: 0, width: 540, height: 720))
        printable.string = curDoc?.content ?? ""
        printable.font = editorVC.currentEditorFont
        printable.isEditable = false
        let operation = NSPrintOperation(view: printable, printInfo: NSPrintInfo.shared)
        operation.showsPrintPanel = true; operation.showsProgressPanel = true
        operation.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
    }

    func openDocument() {
        let p = NSOpenPanel()
        p.allowsMultipleSelection = true
        p.canChooseDirectories = false
        p.canChooseFiles = true
        p.beginSheetModal(for: window!) { [weak self] r in
            guard r == .OK else { return }
            p.urls.forEach { self?.openFile($0) }
        }
    }

    /// Maru's “Close and Open” keeps the editor window in place while
    /// applying the normal unsaved-changes protection to the current tab.
    func closeAndOpen() {
        guard closeCurrentTab() else { return }
        openDocument()
    }

    func openPartialFile() {
        guard let window else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false; panel.canChooseFiles = true
        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .OK, let url = panel.url else { return }
            let offsetField = NSTextField(string: "0")
            let fileSize = (try? LargeFilePolicy.fileSize(at: url)) ?? 1
            let defaultLength = max(1, min(1_048_576, fileSize))
            let lengthField = NSTextField(string: String(defaultLength))
            for field in [offsetField, lengthField] { field.widthAnchor.constraint(equalToConstant: 180).isActive = true }
            let stack = NSStackView(views: [
                NSTextField(labelWithString: AppLocalization.string("dialog.partial.startOffset")), offsetField,
                NSTextField(labelWithString: AppLocalization.string("dialog.partial.byteCount")), lengthField,
            ])
            stack.orientation = .vertical; stack.spacing = 5
            let alert = NSAlert()
            alert.messageText = AppLocalization.string("dialog.partial.title")
            alert.informativeText = AppLocalization.string("dialog.partial.explanation")
            alert.accessoryView = stack
            alert.addButton(withTitle: AppLocalization.string(.commonOpen))
            alert.addButton(withTitle: AppLocalization.string(.commonCancel))
            alert.beginSheetModal(for: window) { result in
                guard result == .alertFirstButtonReturn,
                      let offset = Int64(offsetField.stringValue),
                      let length = Int(lengthField.stringValue) else { return }
                do {
                    let document = try Document.openPartial(url: url, offset: offset, length: length)
                    let adopted = self.documentController.adoptOpenedDocument(document)
                    self.finishOpening(adopted, url: url)
                } catch { NSAlert(error: error).beginSheetModal(for: window) }
            }
        }
    }

    func openBinaryFile() {
        guard let window else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.openBinaryFile(url)
        }
    }

    func openBinaryFile(_ url: URL) {
        do {
            let document = try Document.openBinary(url: url)
            documentController.addDocument(document)
            finishOpening((document, false), url: url)
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    func openFile(_ url: URL) {
        saveCursorPosition()
        do {
            if documentController.indexOfDocument(withURL: url) != nil {
                finishOpening(try documentController.open(url: url), url: url)
                return
            }
            let mode = documentController.indexOfDocument(withURL: url) == nil
                ? try chooseLargeFileMode(for: url) : nil
            if mode == .cancel { return }
            if try LargeFilePolicy.fileSize(at: url) >= LargeFilePolicy.reducedFeaturesThreshold {
                loadLargeDocument(url, mode: mode?.mode, inCurrentTab: false)
                return
            }
            let result = try documentController.open(url: url, largeFileMode: mode?.mode)
            finishOpening(result, url: url)
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    private func openFileInCurrentTab(_ url: URL) {
        saveCursorPosition()
        do {
            let mode = documentController.indexOfDocument(withURL: url) == nil
                ? try chooseLargeFileMode(for: url) : nil
            if mode == .cancel { return }
            if documentController.indexOfDocument(withURL: url) == nil,
               try LargeFilePolicy.fileSize(at: url) >= LargeFilePolicy.reducedFeaturesThreshold {
                loadLargeDocument(url, mode: mode?.mode, inCurrentTab: true)
                return
            }
            let result = try documentController.openInCurrentTab(
                url: url, largeFileMode: mode?.mode)
            finishOpening(result, url: url)
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    private func loadLargeDocument(
        _ url: URL, mode: LargeFileMode?, inCurrentTab: Bool
    ) {
        showStatusMessage(SettingsLocalization.text("openingLargeFile"), duration: 30)
        fileIOQueue.async { [self] in
            let loaded = Result { try Document.open(url: url, largeFileMode: mode) }
            Task { @MainActor in
                switch loaded {
                case .failure(let error):
                    NSAlert(error: error).runModal()
                case .success(let document):
                    let result = inCurrentTab
                        ? self.documentController.adoptOpenedDocumentInCurrentTab(document)
                        : self.documentController.adoptOpenedDocument(document)
                    self.finishOpening(result, url: url)
                }
            }
        }
    }

    private func finishOpening(
        _ result: (document: Document, wasAlreadyOpen: Bool), url: URL
    ) {
        editorVC.document = result.document
        refreshTabs(); refreshStatus()
        window?.title = AppLocalization.string("window.document.title", [result.document.localizedDisplayName])
        // Report after the document model, text storage, tabs, and status are
        // installed. AppKit may lay out additional offscreen glyphs later;
        // deferred highlighting and ancillary history/sidebar/session work
        // remain outside the editable-ready gate.
        BenchmarkProbe.record("file-open-ready", detail: url.path)
        RecentItems.addFile(url)
        sidebarVC.revealFile(url)
        if result.wasAlreadyOpen { deferredRestoreCursor() }
        scheduleSessionSave()
    }

    func saveDocument() {
        guard let doc = curDoc else { return }
        guard doc.fileURL != nil else { saveDocumentAs(); return }
        // Checked before the mixed-line-ending prompt: no point asking the
        // user to pick LF/CRLF/CR for a write that can't happen anyway
        // (ROADMAP.md M2-08, "never presented as normally overwriteable").
        if doc.isEditingDisabled || doc.isOverwriteProhibited {
            presentReadOnlySaveBlocked(doc)
            return
        }
        guard resolveMixedLineEndingIfNeeded(for: doc) else { return }
        performSave(doc)
    }

    func saveAllDocuments(onlyModified: Bool = false) {
        let documents = documentController.documents.filter { document in
            // The initial pristine Untitled tab is a workspace placeholder,
            // not a user document that should interrupt Save All with a panel.
            guard document.fileURL != nil || document.isModified else { return false }
            return !onlyModified || document.isModified
        }
        saveDocuments(documents)
    }

    private func saveDocuments(_ documents: [Document]) {
        guard let document = documents.first else { showLocalizedStatus("status.allDocumentsSaved"); return }
        guard let index = documentController.documents.firstIndex(where: { $0 === document }) else {
            saveDocuments(Array(documents.dropFirst())); return
        }
        tabBarDidSelectTab(at: index)
        guard document.fileURL == nil else {
            if document.isEditingDisabled || document.isOverwriteProhibited {
                presentReadOnlySaveBlocked(document); return
            }
            guard resolveMixedLineEndingIfNeeded(for: document) else { return }
            performSaveSynchronously(document)
            guard !document.isModified else { return }
            saveDocuments(Array(documents.dropFirst()))
            return
        }
        guard resolveMixedLineEndingIfNeeded(for: document), let window else { return }
        let panel = NSSavePanel(); panel.canCreateDirectories = true
        let accessory = SaveAsFormatAccessoryView(
            initialEncoding: document.encoding,
            initialHasByteOrderMark: document.hasByteOrderMark)
        panel.accessoryView = accessory
        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .OK, let url = panel.url else { return }
            document.encoding = accessory.selectedEncoding
            document.hasByteOrderMark = accessory.includesByteOrderMark
            guard self.performSaveAs(document, to: url) else { return }
            self.saveDocuments(Array(documents.dropFirst()))
        }
    }

    func saveDocumentWithLFLineEndings() {
        guard let doc = curDoc else { return }
        doc.lineEnding = .lf
        saveDocument()
    }

    /// ROADMAP.md M2-08: intercepts Save on a read-only file before any
    /// write is attempted. `TextFileSaver` would fail on its own too (the
    /// OS denies the write), but surfacing this up front — with a "Save
    /// As…" escape hatch — is friendlier than a bare I/O error after the
    /// fact.
    private func presentReadOnlySaveBlocked(_ doc: Document) {
        let a = NSAlert()
        a.alertStyle = .warning
        a.messageText = AppLocalization.string("dialog.readOnly.title", [doc.localizedDisplayName])
        a.informativeText = doc.isOverwriteProhibited
            ? AppLocalization.string("dialog.readOnly.protected")
            : AppLocalization.string("dialog.readOnly.disk")
        a.addButton(withTitle: AppLocalization.string("common.saveAs"))
        a.addButton(withTitle: AppLocalization.string(.commonCancel))
        if a.runModal() == .alertFirstButtonReturn {
            saveDocumentAs()
        }
    }

    func toggleOverwriteProtection() {
        guard let doc = curDoc else { return }
        doc.isOverwriteProhibited.toggle()
        refreshStatus()
        showLocalizedStatus(doc.isOverwriteProhibited
            ? "status.overwriteProtectionOn" : "status.overwriteProtectionOff")
    }

    func toggleHistoryRecording() {
        RecentItems.isRecordingSuspended.toggle()
        showLocalizedStatus(RecentItems.isRecordingSuspended
            ? "status.historyRecordingSuspended" : "status.historyRecordingResumed")
    }

    func saveDocumentAs() {
        guard let doc = curDoc else { return }
        guard resolveMixedLineEndingIfNeeded(for: doc) else { return }

        let p = NSSavePanel()
        p.canCreateDirectories = true
        let accessory = SaveAsFormatAccessoryView(initialEncoding: doc.encoding, initialHasByteOrderMark: doc.hasByteOrderMark)
        p.accessoryView = accessory
        p.beginSheetModal(for: window!) { [weak self] r in
            guard let self = self, r == .OK, let url = p.url else { return }
            doc.encoding = accessory.selectedEncoding
            doc.hasByteOrderMark = accessory.includesByteOrderMark
            self.performSaveAs(doc, to: url)
        }
    }

    /// Saves `doc` to its existing `fileURL`. If the content can't be
    /// represented in `doc.encoding`, shows the ROADMAP.md M2-04
    /// unrepresentable-character alert (with line/column detail) and
    /// offers to convert to UTF-8 and retry, rather than a bare error.
    /// Human Save.
    ///
    /// Synchronous, and deliberately so. Moving the encode off the main actor
    /// would keep typing smooth on a very large file, but Save All, save-and-
    /// close, and app termination all sequence something immediately after the
    /// save, and an asynchronous write let a tab close before the bytes landed.
    /// The defect this work set out to fix — a document reported clean in a
    /// state it was never saved in — is fixed by recording the planned
    /// snapshot, not by the hop. Agents get the off-main path, because they
    /// await their result and nothing is sequenced behind them.
    private func performSave(_ doc: Document) {
        _ = performSaveSynchronously(doc)
    }

    /// Human Save As.
    ///
    /// Reports synchronously because callers branch on the result — closing a
    /// tab, for one — and the coordinator's completion runs on the main actor
    /// before `save` returns whenever the prepare step is short. When it is
    /// not, the result is reported through the same completion and the caller
    /// sees `false` until it lands.
    /// Human Save As.
    ///
    /// Synchronous, because every caller branches on the result — closing a
    /// tab, advancing Save All — and an asynchronous write would let that next
    /// step run before the bytes landed.
    @discardableResult
    private func performSaveAs(_ doc: Document, to url: URL) -> Bool {
        let wasUnnamed = doc.fileURL == nil
        SaveCoordinator.shared.supersede(doc)
        switch SaveCoordinator.shared.saveSynchronously(document: doc, as: url) {
        case .succeeded:
            refreshTabs(); refreshStatus()
            window?.title = AppLocalization.string(
                "window.document.title", [doc.localizedDisplayName])
            RecentItems.addFile(url)
            if wasUnnamed {
                // This document now has a real file, which is its own
                // recovery mechanism from here on — the crash-recovery
                // record for its unnamed life is no longer needed.
                recoveryStore.delete(doc.recoveryID)
            }
            return true
        case .failedBeforeIrreversible("unrepresentable"):
            let preflight = doc.preflightSave()
            offerUTF8Conversion(
                for: doc, encoding: doc.encoding,
                characters: preflight.unrepresentableCharacters
            ) { [weak self] in self?.performSaveAs(doc, to: url) }
            return !doc.isModified
        case .failedAfterIrreversible(let reason):
            NSAlert(error: DocumentSaveError.policyFailed(reason)).runModal()
            return false
        case .failedBeforeIrreversible(let reason), .conflicted(let reason):
            showStatusMessage(reason, duration: 3)
            return false
        case .superseded, .inProgress:
            return false
        }
    }

    /// Saves without yielding, for callers that sequence something after it.
    @discardableResult
    private func performSaveSynchronously(_ doc: Document) -> Bool {
        SaveCoordinator.shared.supersede(doc)
        switch SaveCoordinator.shared.saveSynchronously(document: doc) {
        case .succeeded:
            refreshTabs(); refreshStatus()
            return true
        case .conflicted("external_change"):
            presentExternalChangeConflict(.modified, for: doc)
            return false
        case .failedBeforeIrreversible("unrepresentable"):
            let preflight = doc.preflightSave()
            offerUTF8Conversion(
                for: doc, encoding: doc.encoding,
                characters: preflight.unrepresentableCharacters
            ) { [weak self] in _ = self?.performSaveSynchronously(doc) }
            return false
        case .failedAfterIrreversible(let reason):
            NSAlert(error: DocumentSaveError.policyFailed(reason)).runModal()
            return false
        case .failedBeforeIrreversible(let reason), .conflicted(let reason):
            showStatusMessage(reason, duration: 3)
            return false
        case .superseded, .inProgress:
            return false
        }
    }

    func saveAndCloseCurrentTab() {
        saveAndCloseCurrentTab { _ in }
    }

    func saveAllAndClose() {
        saveAndClose(documents: documentController.documents)
    }

    private func saveAndClose(documents: [Document]) {
        guard let document = documents.first else { return }
        guard let index = documentController.documents.firstIndex(where: { $0 === document }) else {
            saveAndClose(documents: Array(documents.dropFirst()))
            return
        }
        tabBarDidSelectTab(at: index)
        saveAndCloseCurrentTab { [weak self] closed in
            guard closed else { return }
            self?.saveAndClose(documents: Array(documents.dropFirst()))
        }
    }

    private func saveAndCloseCurrentTab(completion: @escaping (Bool) -> Void) {
        guard let doc = curDoc else { completion(false); return }
        guard doc.isModified else { completion(closeCurrentTab()); return }

        if doc.fileURL != nil {
            saveDocument()
            completion(!doc.isModified && closeCurrentTab())
            return
        }

        guard resolveMixedLineEndingIfNeeded(for: doc), let window else {
            completion(false)
            return
        }
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        let accessory = SaveAsFormatAccessoryView(
            initialEncoding: doc.encoding,
            initialHasByteOrderMark: doc.hasByteOrderMark)
        panel.accessoryView = accessory
        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .OK, let url = panel.url else {
                completion(false)
                return
            }
            doc.encoding = accessory.selectedEncoding
            doc.hasByteOrderMark = accessory.includesByteOrderMark
            let saved = self.performSaveAs(doc, to: url)
            completion(saved && self.closeCurrentTab())
        }
    }

    /// Shows the unrepresentable-character detail (character, line,
    /// column — up to a handful, with a count of any remainder) and, if
    /// the user chooses to proceed, converts `doc` to UTF-8 (which can
    /// represent everything) and calls `retry`. Lossy save is
    /// deliberately not offered as an option here — only Save as UTF-8
    /// or Cancel, per ROADMAP.md M2-04 ("disable lossy save by default").
    private func offerUTF8Conversion(
        for doc: Document,
        encoding: TextEncoding,
        characters: [UnrepresentableCharacter],
        retry: @escaping () -> Void
    ) {
        let a = NSAlert()
        a.alertStyle = .warning
        a.messageText = AppLocalization.string("dialog.encoding.cannotSave", [encoding.displayName])
        let shown = characters.prefix(5)
            .map { AppLocalization.string("dialog.encoding.characterLocation", [$0.line, $0.column, $0.character]) }
            .joined(separator: "\n")
        let remainder = characters.count > 5
            ? "\n" + AppLocalization.string("dialog.encoding.more", [characters.count - 5]) : ""
        a.informativeText = characters.isEmpty
            ? AppLocalization.string("dialog.encoding.unrepresentableUnknown", [encoding.displayName])
            : AppLocalization.string("dialog.encoding.unrepresentable", [characters.count, encoding.displayName, shown, remainder])
        a.addButton(withTitle: AppLocalization.string("dialog.encoding.saveUTF8"))
        a.addButton(withTitle: AppLocalization.string(.commonCancel))
        guard a.runModal() == .alertFirstButtonReturn else { return }
        doc.encoding = .utf8
        doc.hasByteOrderMark = false
        retry()
    }

    /// If `doc.lineEnding` is still `.mixed`, requires the user to pick a
    /// single style to use going forward before any save proceeds
    /// (ROADMAP.md M2-03 acceptance: never silently pick one). Returns
    /// `false` if the user cancelled — callers must abort the save.
    /// Uniform (`.lf`/`.crlf`/`.cr`) and `.none` documents need no prompt
    /// and always return `true` immediately.
    private func resolveMixedLineEndingIfNeeded(for doc: Document) -> Bool {
        guard case .mixed = doc.lineEnding else { return true }

        let a = NSAlert()
        a.messageText = AppLocalization.string("dialog.lineEndings.title")
        a.informativeText = AppLocalization.string("dialog.lineEndings.explanation", [doc.localizedDisplayName])
        a.addButton(withTitle: AppLocalization.string("lineEnding.lfLong"))
        a.addButton(withTitle: AppLocalization.string("lineEnding.crlfLong"))
        a.addButton(withTitle: AppLocalization.string("lineEnding.crLong"))
        a.addButton(withTitle: AppLocalization.string(.commonCancel))
        switch a.runModal() {
        case .alertFirstButtonReturn: doc.lineEnding = .lf
        case .alertSecondButtonReturn: doc.lineEnding = .crlf
        case .alertThirdButtonReturn: doc.lineEnding = .cr
        default: return false
        }
        return true
    }

    // MARK: - External-modification detection (M2-06)
    //
    // Revalidation, not live monitoring — checked when the window regains
    // focus and again right before every same-file save, rather than a
    // continuous FSEvents watcher (ROADMAP.md M2-06 explicitly allows
    // either approach). No "auto-reload an unmodified file" preference
    // exists yet — that's gated on a real Preferences UI (M5); until
    // then, every detected change is surfaced explicitly, never applied
    // silently.

    @objc private func windowDidBecomeKey() {
        guard let doc = curDoc else { return }
        // ROADMAP.md M2-08: "React to permission changes while the
        // document is open" — re-checked here alongside the external-
        // modification revalidation below, on the same trigger (window
        // regaining focus), rather than a separate live watcher.
        if doc.refreshReadOnlyState() {
            refreshStatus()
        }
        guard let url = doc.fileURL else { return }
        let status = ExternalChangeDetector.check(url: url, knownIdentity: doc.fileIdentity, knownModificationDate: doc.lastKnownModificationDate)
        guard status != .unchanged else { return }
        presentExternalChangeConflict(status, for: doc)
    }

    private func presentExternalChangeConflict(_ status: ExternalChangeStatus, for doc: Document) {
        switch status {
        case .unchanged:
            return

        case .deletedOrMoved:
            let a = NSAlert()
            a.alertStyle = .warning
            a.messageText = AppLocalization.string("dialog.externalChange.missingTitle", [doc.localizedDisplayName])
            a.informativeText = AppLocalization.string("dialog.externalChange.missingExplanation")
            a.addButton(withTitle: AppLocalization.string(.commonOK))
            a.runModal()

        case .modified:
            let a = NSAlert()
            a.alertStyle = .warning
            a.messageText = AppLocalization.string("dialog.externalChange.changedTitle", [doc.localizedDisplayName])
            if doc.isModified {
                a.informativeText = AppLocalization.string("dialog.externalChange.conflictExplanation")
                a.addButton(withTitle: AppLocalization.string("common.reloadFromDisk"))
                a.addButton(withTitle: AppLocalization.string("common.saveAs"))
                a.addButton(withTitle: AppLocalization.string(.commonCancel))
                switch a.runModal() {
                case .alertFirstButtonReturn: reloadFromDisk(doc)
                case .alertSecondButtonReturn: saveDocumentAs()
                default: break
                }
            } else {
                a.informativeText = AppLocalization.string("dialog.externalChange.changedExplanation")
                a.addButton(withTitle: AppLocalization.string("common.reloadFromDisk"))
                a.addButton(withTitle: AppLocalization.string(.commonCancel))
                if a.runModal() == .alertFirstButtonReturn {
                    reloadFromDisk(doc)
                }
            }
        }
    }

    @discardableResult
    private func reloadFromDisk(_ doc: Document) -> Bool {
        do {
            try doc.reopen(forcing: doc.encoding)
            editorVC.reloadCurrentDocument()
            refreshTabs(); refreshStatus()
            return true
        } catch {
            NSAlert(error: error).runModal()
            return false
        }
    }

    func reloadDocument() {
        guard let doc = curDoc, doc.fileURL != nil else { return }
        if doc.isModified {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = AppLocalization.string("dialog.reload.title", [doc.localizedDisplayName])
            alert.informativeText = AppLocalization.string("dialog.reload.explanation")
            alert.addButton(withTitle: AppLocalization.string(.commonReload))
            alert.addButton(withTitle: AppLocalization.string(.commonCancel))
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        _ = reloadFromDisk(doc)
    }

    func toggleViewMode() {
        guard let doc = curDoc else { return }
        doc.isViewMode.toggle()
        editorVC.reloadCurrentDocument(); refreshStatus()
    }

    func showFileProperties() {
        guard let doc = curDoc, let window else { return }
        let alert = NSAlert()
        alert.messageText = doc.localizedDisplayName
        alert.informativeText = doc.propertiesSummary
        alert.addButton(withTitle: AppLocalization.string(.commonOK))
        alert.beginSheetModal(for: window)
    }

    func insertFileContents() { chooseAndInsertFile(atDocumentEnd: false) }
    func insertTemplate() {
        let profiles = documentController.templateProfiles
        guard !profiles.isEmpty else {
            showLocalizedStatus("status.noProfileTemplates"); return
        }
        let popup = NSPopUpButton(); popup.addItems(withTitles: profiles.map(\.name))
        popup.frame.size.width = 260
        let alert = NSAlert(); alert.messageText = AppLocalization.string("dialog.template.insertTitle")
        alert.informativeText = AppLocalization.string("dialog.template.insertExplanation")
        alert.accessoryView = popup; alert.addButton(withTitle: AppLocalization.string(.commonInsert))
        alert.addButton(withTitle: AppLocalization.string(.commonCancel))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            guard let path = profiles[popup.indexOfSelectedItem].settings.templatePath else { return }
            insertTemplateContents(try ProfileFilePolicy.loadTemplate(path: path))
        } catch { showStatusMessage(error.localizedDescription, duration: 4) }
    }

    private func insertTemplateContents(_ text: String) {
        editorVC.textView.insertText(text, replacementRange: editorVC.textView.selectedRange())
    }
    func insertTemplateContentsForTesting(_ text: String) { insertTemplateContents(text) }
    func appendRead() { chooseAndInsertFile(atDocumentEnd: true) }

    private func chooseAndInsertFile(atDocumentEnd: Bool) {
        guard let window else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .OK, let url = panel.url else { return }
            do {
                let text = try Document.normalizedText(contentsOf: url)
                let range = atDocumentEnd
                    ? NSRange(location: (self.editorVC.textView.string as NSString).length, length: 0)
                    : self.editorVC.textView.selectedRange()
                self.editorVC.textView.insertText(text, replacementRange: range)
            } catch {
                NSAlert(error: error).beginSheetModal(for: window)
            }
        }
    }

    func appendSave() {
        guard let doc = curDoc, let window else { return }
        let panel = NSSavePanel()
        panel.title = AppLocalization.string("dialog.appendSave.title")
        panel.prompt = AppLocalization.string("common.append")
        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let url = panel.url else { return }
            do { try doc.appendContent(to: url) }
            catch { NSAlert(error: error).beginSheetModal(for: window) }
        }
    }

    func renameFile() {
        guard let doc = curDoc, let source = doc.fileURL, let window else { return }
        let panel = NSSavePanel()
        panel.title = AppLocalization.string("dialog.rename.title")
        panel.prompt = AppLocalization.string("common.rename")
        panel.directoryURL = source.deletingLastPathComponent()
        panel.nameFieldStringValue = source.lastPathComponent
        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .OK, let destination = panel.url else { return }
            do {
                try doc.rename(to: destination)
                self.refreshTabs(); self.refreshStatus()
                self.window?.title = AppLocalization.string("window.document.title", [doc.localizedDisplayName])
                RecentItems.addFile(destination)
                self.scheduleSessionSave()
            } catch { NSAlert(error: error).beginSheetModal(for: window) }
        }
    }

    @discardableResult
    func closeCurrentTab() -> Bool {
        guard let doc = curDoc else { return false }
        let indexToClose = curIdx
        if doc.isModified {
            let a = NSAlert()
            a.messageText = AppLocalization.string("dialog.close.saveTitle", [doc.localizedDisplayName])
            a.informativeText = AppLocalization.string("dialog.close.explanation")
            a.addButton(withTitle: AppLocalization.string(.commonSave))
            a.addButton(withTitle: AppLocalization.string(.commonDontSave))
            a.addButton(withTitle: AppLocalization.string(.commonCancel))
            let resp = a.runModal()
            if resp == .alertFirstButtonReturn {
                saveDocument()
                // Save panels can themselves be cancelled.
                if doc.isModified { return false }
            }
            else if resp == .alertThirdButtonReturn { return false }
            else if resp == .alertSecondButtonReturn, doc.fileURL == nil {
                // Explicitly discarded (ROADMAP.md M2-07: "Delete recovery
                // data after a normal close with 'Don't Save.'").
                recoveryStore.delete(doc.recoveryID)
            }
        } else if doc.fileURL == nil {
            recoveryStore.delete(doc.recoveryID)
        }
        let emptiedAndReplaced = documentController.closeDocument(at: indexToClose)
        editorVC.document = curDoc
        refreshTabs(); refreshStatus()
        scheduleSessionSave()
        if emptiedAndReplaced { return true }
        deferredRestoreCursor()
        return true
    }

    func takeCurrentDocumentForDetaching() -> Document? {
        guard let document = documentController.takeDocument(at: curIdx) else { return nil }
        editorVC.document = curDoc
        refreshTabs(); refreshStatus(); layoutContentViews()
        return document
    }

    /// Adds a document the agent interface opened from a verified descriptor.
    ///
    /// It goes through the ordinary document lifecycle from here on — profile
    /// resolution, encoding, tabs, status — so an agent-opened file behaves
    /// exactly like one the human opened.
    @discardableResult
    func adoptAgentOpenedDocument(url: URL, loaded: LoadedText) -> Document {
        let document = Document(
            fileURL: url,
            content: loaded.content,
            language: Language.detect(for: url))
        document.encoding = loaded.encoding
        document.hasByteOrderMark = loaded.hasByteOrderMark
        document.lineEnding = LineEndingDetector.detect(loaded.content)
        document.markSaved()
        _ = documentController.addDocument(document)
        editorVC.document = document
        refreshTabs(); refreshStatus(); layoutContentViews()
        return document
    }

    func adoptDetachedDocument(_ document: Document) {
        documentController.replaceCurrentDocument(with: document)
        editorVC.document = document
        refreshTabs(); refreshStatus(); layoutContentViews()
        window?.title = AppLocalization.string("window.document.title", [document.localizedDisplayName])
    }

    @discardableResult
    func discardAndCloseCurrentTab() -> Bool {
        guard let doc = curDoc else { return false }
        let index = curIdx
        if doc.fileURL == nil { recoveryStore.delete(doc.recoveryID) }
        let replaced = documentController.closeDocument(at: index)
        editorVC.document = curDoc
        refreshTabs(); refreshStatus(); scheduleSessionSave()
        if !replaced { deferredRestoreCursor() }
        return true
    }

    func discardAllAndClose() {
        let count = documentController.documents.count
        for _ in 0..<count { _ = discardAndCloseCurrentTab() }
    }

    func closeWorkspace() {
        let documents = documentController.documents
        for document in documents {
            guard let index = documentController.documents.firstIndex(where: { $0 === document }) else {
                continue
            }
            tabBarDidSelectTab(at: index)
            guard closeCurrentTab() else { return }
        }
    }

    func openCursorTargetWithAssociatedApplication() {
        guard let target = cursorTarget(), let url = resolvedTargetURL(target) else {
            showLocalizedStatus("status.noURLTarget"); return
        }
        openAssociatedURL(url)
    }

    func openCursorTargetInMaruEdit() {
        guard let target = cursorTarget(), let url = resolvedTargetURL(target), url.isFileURL,
              FileManager.default.fileExists(atPath: url.path) else {
            showLocalizedStatus("status.noFileTarget"); return
        }
        openFile(url)
    }

    private func cursorTarget() -> String? {
        let source = editorVC.textView.string as NSString
        let selection = editorVC.selectionSet.primaryRange
        if selection.length > 0, NSMaxRange(selection) <= source.length {
            return source.substring(with: selection).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard selection.location < source.length else { return nil }
        let line = source.lineRange(for: NSRange(location: selection.location, length: 0))
        let value = source.substring(with: line)
        let offset = selection.location - line.location
        let nsValue = value as NSString
        let separators = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "\"'<>"))
        var start = min(offset, nsValue.length), end = start
        while start > 0, let scalar = UnicodeScalar(nsValue.character(at: start - 1)), !separators.contains(scalar) { start -= 1 }
        while end < nsValue.length, let scalar = UnicodeScalar(nsValue.character(at: end)), !separators.contains(scalar) { end += 1 }
        guard start < end else { return nil }
        return nsValue.substring(with: NSRange(location: start, length: end - start))
            .trimmingCharacters(in: CharacterSet(charactersIn: ",;()[]{}"))
    }

    private func resolvedTargetURL(_ target: String) -> URL? {
        if let url = URL(string: target), let scheme = url.scheme, !scheme.isEmpty { return url }
        let expanded = (target as NSString).expandingTildeInPath
        if expanded.hasPrefix("/") { return URL(fileURLWithPath: expanded) }
        guard let base = curDoc?.fileURL?.deletingLastPathComponent() else { return nil }
        return base.appendingPathComponent(expanded).standardizedFileURL
    }

    /// Maru-style tab-order traversal. Both directions wrap at the ends.
    func selectRelativeTab(_ offset: Int) {
        let count = documentController.documents.count
        guard count > 1 else { return }
        let destination = (curIdx + offset % count + count) % count
        tabBarDidSelectTab(at: destination)
    }

    func showTabList() {
        let documents = documentController.documents
        guard documents.count > 1 else {
            showStatusMessage(curDoc?.localizedDisplayName ?? AppLocalization.string("status.noOpenDocument")); return
        }
        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 420, height: 26))
        popup.addItems(withTitles: documents.enumerated().map { index, document in
            "\(index + 1). \(document.isModified ? "● " : "")\(document.localizedDisplayName)"
        })
        popup.selectItem(at: curIdx)
        let alert = NSAlert()
        alert.messageText = AppLocalization.string("dialog.tabs.title")
        alert.informativeText = AppLocalization.string("dialog.tabs.explanation")
        alert.accessoryView = popup
        alert.addButton(withTitle: AppLocalization.string(.commonSelect))
        alert.addButton(withTitle: AppLocalization.string(.commonCancel))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        tabBarDidSelectTab(at: popup.indexOfSelectedItem)
    }

    func closeTabs(_ scope: TabCloseScope) {
        tabBarDidRequestClose(scope, at: curIdx)
    }

    func focusEditor() { window?.makeFirstResponder(editorVC.textView) }

    func focusUtilityPane() {
        if sidebarVC.view.isHidden || splitView.isSubviewCollapsed(sidebarVC.view) { toggleSidebar() }
        sidebarVC.focusCurrentPane(in: window)
    }

    func insertDateTime(now: Date = Date()) {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateStyle = .short; formatter.timeStyle = .medium
        editorVC.textView.insertText(
            formatter.string(from: now), replacementRange: editorVC.textView.selectedRange())
    }

    func insertNewline() {
        editorVC.textView.insertText("\n", replacementRange: editorVC.textView.selectedRange())
    }

    func insertTab() {
        editorVC.textView.insertText("\t", replacementRange: editorVC.textView.selectedRange())
    }

    func insertPageBreak() {
        editorVC.textView.insertText("\u{000C}", replacementRange: editorVC.textView.selectedRange())
    }

    func insertBlankLine() {
        let text = editorVC.textView.string as NSString
        let selection = editorVC.selectionSet.primaryRange
        let location = min(selection.location, text.length)
        let line = text.lineRange(for: NSRange(location: location, length: 0))
        let contents = text.substring(with: line)
        let indentation = contents.prefix { $0 == " " || $0 == "\t" }
        editorVC.batchReplace([NSRange(location: line.location, length: 0)], with: String(indentation) + "\n")
    }

    func insertCurrentFileName() {
        guard let name = curDoc?.fileURL?.lastPathComponent else {
            showLocalizedStatus("status.currentDocumentNoFileName"); return
        }
        editorVC.textView.insertText(name, replacementRange: editorVC.textView.selectedRange())
    }

    /// Title and byte for every offered control code.
    ///
    /// The entries used to be a bare list whose *row index* was the byte, with
    /// the last row special-cased as DEL. That made the display order and the
    /// emitted value the same fact, so removing a row silently shifted every
    /// code after it. They are pairs now, which is also what lets CR be dropped
    /// safely: the buffer is LF-only (ADR-012 §3), so a picker cannot honestly
    /// offer to insert a carriage return.
    static let controlCodeChoices: [(title: String, value: UInt8)] = [
        ("NUL  00", 0x00), ("SOH  01", 0x01), ("STX  02", 0x02), ("ETX  03", 0x03),
        ("EOT  04", 0x04), ("ENQ  05", 0x05), ("ACK  06", 0x06), ("BEL  07", 0x07),
        ("BS   08", 0x08), ("TAB  09", 0x09), ("LF   0A", 0x0A), ("VT   0B", 0x0B),
        ("FF   0C", 0x0C), ("SO   0E", 0x0E), ("SI   0F", 0x0F),
        ("DLE  10", 0x10), ("DC1  11", 0x11), ("DC2  12", 0x12), ("DC3  13", 0x13),
        ("DC4  14", 0x14), ("NAK  15", 0x15), ("SYN  16", 0x16), ("ETB  17", 0x17),
        ("CAN  18", 0x18), ("EM   19", 0x19), ("SUB  1A", 0x1A), ("ESC  1B", 0x1B),
        ("FS   1C", 0x1C), ("GS   1D", 0x1D), ("RS   1E", 0x1E), ("US   1F", 0x1F),
        ("DEL  7F", 0x7F),
    ]

    func insertControlCode() {
        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 180, height: 26))
        popup.addItems(withTitles: Self.controlCodeChoices.map(\.title))
        let alert = NSAlert()
        alert.messageText = AppLocalization.string("dialog.controlCode.title")
        alert.informativeText = AppLocalization.string("dialog.controlCode.explanation")
        alert.accessoryView = popup
        alert.addButton(withTitle: AppLocalization.string(.commonInsert))
        alert.addButton(withTitle: AppLocalization.string(.commonCancel))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let index = popup.indexOfSelectedItem
        guard Self.controlCodeChoices.indices.contains(index) else { return }
        _ = insertControlCode(Self.controlCodeChoices[index].value)
    }

    @discardableResult
    func insertControlCode(_ value: UInt8) -> Bool {
        // 0x0D is refused rather than normalized: this command exists for byte
        // precision, so silently inserting something else would be worse than
        // saying no.
        guard value != 0x0D, value <= 0x1F || value == 0x7F,
              editorVC.textView.isEditable else { return false }
        guard let scalar = UnicodeScalar(Int(value)) else { return false }
        editorVC.textView.insertText(String(Character(scalar)), replacementRange: editorVC.textView.selectedRange())
        return true
    }

    func openFolder() {
        let p = NSOpenPanel()
        p.canChooseDirectories = true
        p.canChooseFiles = false
        p.allowsMultipleSelection = false
        p.beginSheetModal(for: window!) { [weak self] r in
            guard r == .OK, let url = p.url else { return }
            self?.showSidebarAndOpen(url)
        }
    }

    func openFolderDirect(_ url: URL) {
        showSidebarAndOpen(url)
    }

    private func showSidebarAndOpen(_ url: URL) {
        sidebarManuallyCollapsed = false
        sidebarVC.view.isHidden = false
        splitView.adjustSubviews()
        splitView.setPosition(220, ofDividerAt: 0)
        RecentItems.addFolder(url)
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if self.sidebarVC.view.frame.width < 10 {
                self.splitView.setPosition(220, ofDividerAt: 0)
            }
            self.sidebarVC.openFolder(url)
        }
        scheduleSessionSave()
    }

    func toggleSidebar() {
        if sidebarVC.view.isHidden || splitView.isSubviewCollapsed(sidebarVC.view) {
            sidebarManuallyCollapsed = false
            sidebarVC.view.isHidden = false
            splitView.adjustSubviews()
            splitView.setPosition(220, ofDividerAt: 0)
        } else {
            sidebarManuallyCollapsed = true
            splitView.setPosition(0, ofDividerAt: 0)
            sidebarVC.view.isHidden = true
        }
        layoutContentViews()
        scheduleSessionSave()
    }

    func showFilesPane() {
        sidebarVC.showUtilityPane(.files)
        if sidebarVC.view.isHidden || splitView.isSubviewCollapsed(sidebarVC.view) { toggleSidebar() }
        sidebarVC.focusCurrentPane(in: window)
    }

    func showBrowserPane(useDocumentURL: Bool) {
        let url = useDocumentURL ? curDoc?.fileURL : nil
        sidebarVC.showBrowser(url: url)
        if sidebarVC.view.isHidden || splitView.isSubviewCollapsed(sidebarVC.view) { toggleSidebar() }
        sidebarVC.focusCurrentPane(in: window)
    }

    func toggleBrowserPane() {
        if sidebarVC.selectedUtilityPane == .browser,
           !sidebarVC.view.isHidden, !splitView.isSubviewCollapsed(sidebarVC.view) {
            toggleSidebar()
        } else {
            showBrowserPane(useDocumentURL: false)
        }
    }

    func focusBrowserPane() {
        if sidebarVC.selectedUtilityPane != .browser { sidebarVC.showBrowser() }
        if sidebarVC.view.isHidden || splitView.isSubviewCollapsed(sidebarVC.view) { toggleSidebar() }
        sidebarVC.focusCurrentPane(in: window)
    }

    func showFind(showingReplace: Bool = false, direction: SearchDirection = .next) {
        if showingReplace { findBar.setReplaceRowVisible(true) }
        findBar.isHidden = false
        layoutContentViews()
        // Incremental search restarts from wherever the caret was when the
        // bar opened, not from the previous keystroke's match.
        let selection = editorVC.textView.selectedRange()
        searchStartOffset = selection.location
        editorVC.incrementalSearchAnchor = selection.location
        if !editorVC.hasExplicitSearchScope {
            editorVC.searchScopeSelection = selection.length > 0 ? selection : nil
        }
        syncSearchHistoryUI()
        findBar.activate(direction: direction)
    }

    func showFindUpward() { showFind(direction: .previous) }

    func findWordAtCursor() {
        guard let pattern = searchTextAtCursor(), !pattern.isEmpty else { showFind(); return }
        let query = SearchQuery(pattern: pattern, wholeWord: true)
        lastQuery = query
        searchStartOffset = editorVC.selectionSet.primaryRange.location
        findBar.setSearchPattern(pattern)
        findAgain(direction: .next)
    }

    func captureSearchStringAtCursor() {
        guard let pattern = searchTextAtCursor(), !pattern.isEmpty else {
            showLocalizedStatus("status.noSearchTextAtCursor"); return
        }
        lastQuery = SearchQuery(pattern: pattern)
        findBar.setSearchPattern(pattern)
        showLocalizedStatus("status.capturedSearchText", [pattern])
    }

    private func searchTextAtCursor() -> String? {
        let text = editorVC.textView.string as NSString
        let selected = editorVC.selectionSet.primaryRange
        if selected.length > 0, NSMaxRange(selected) <= text.length {
            return text.substring(with: selected)
        }
        guard selected.location < text.length else { return nil }
        let word = editorVC.textView.selectionRange(
            forProposedRange: NSRange(location: selected.location, length: 0),
            granularity: .selectByWord)
        guard word.length > 0, NSMaxRange(word) <= text.length else { return nil }
        return text.substring(with: word)
    }

    func moveToDocumentStart() { editorVC.moveToDocumentStart() }
    func moveToDocumentEnd() { editorVC.moveToDocumentEnd() }
    func moveToScreenStart() { editorVC.moveToScreenStart() }
    func moveToScreenEnd() { editorVC.moveToScreenEnd() }
    func moveToWordStart() { editorVC.moveToWordStart() }
    func moveToWordEnd() { editorVC.moveToWordEnd() }
    func moveWordRightSalnen() { editorVC.moveWordRightSalnen() }
    func moveToLineStart() { editorVC.moveToLineStart() }
    func moveToLineEnd() { editorVC.moveToLineEnd() }
    func moveToLineEndAfterCharacter() { editorVC.moveToLineEndAfterCharacter() }
    func moveToLogicalLineStart() { editorVC.moveToLogicalLineStart() }
    func moveToLogicalLineEnd() { editorVC.moveToLogicalLineEnd() }
    func movePage(forward: Bool) { editorVC.movePage(forward: forward) }
    func moveHalfPage(forward: Bool) { editorVC.moveHalfPage(forward: forward) }
    func scrollEditor(forward: Bool, preserveCursor: Bool) { editorVC.scrollEditor(forward: forward, preserveCursor: preserveCursor) }
    func moveToAdjacentTab(forward: Bool) { editorVC.moveToAdjacentTab(forward: forward) }
    func moveToMatchingBracket() { editorVC.moveToMatchingBracket() }
    func moveToBrace(opening: Bool) { editorVC.moveToBrace(opening: opening) }
    func moveToMatchingTag() { editorVC.moveToMatchingTag() }
    func moveToLastEditMark() { editorVC.moveToLastEditMark() }
    func moveToPreviousCursorPosition() { editorVC.moveToPreviousCursorPosition() }

    func toggleFindOption(_ option: FindOption) {
        if findBar.isHidden { showFind() }
        findBar.toggleOption(option)
    }

    func isFindOptionEnabled(_ option: FindOption) -> Bool { findBar.isOptionEnabled(option) }

    /// Replace All from the menu. Opens the Find Bar first when it isn't
    /// showing: bulk replacement must never run against a query the user
    /// can't currently see.
    func replaceAllFromFindBar() {
        guard !findBar.isHidden else {
            showFind(showingReplace: true)
            return
        }
        findBar.setReplaceRowVisible(true)
        findBar.perform(.replaceAll)
    }

    /// Runs Find Next/Previous from the menu, whether or not the Find Bar
    /// is open — the bar is an input surface, not a prerequisite for
    /// searching (ROADMAP.md M3-02).
    func findAgain(direction: SearchDirection) {
        let query = findBar.isHidden ? lastQuery : findBar.currentQuery
        guard let query = query, !query.pattern.isEmpty else {
            showFind()
            return
        }
        if searchStartOffset == nil { searchStartOffset = editorVC.selectionSet.primaryRange.location }
        let outcome = editorVC.find(query, direction: direction)
        if !findBar.isHidden { findBar.showOutcome(outcome) }
    }

    private func performToolbarSearch(_ pattern: String) {
        let query = SearchQuery(pattern: pattern)
        lastQuery = query
        searchStartOffset = editorVC.selectionSet.primaryRange.location
        let ranges = (try? SearchEngine.matches(for: query, in: curDoc?.content ?? ""))?.map(\.range) ?? []
        editorVC.showSearchHighlights(ranges)
        editorVC.showSearchMarkers(ranges)
        sidebarVC.updateSearchResults(ranges, text: curDoc?.content ?? "")
        let outcome = editorVC.find(query, direction: .next)
        if outcome.totalMatches == 0 { showLocalizedStatus("find.noResults") }
        else { showLocalizedStatus("status.matchPosition", [1, outcome.totalMatches]) }
        recordSearchHistory(query)
    }

    private func currentSearchMatches() -> (SearchQuery, [NSRange])? {
        guard var query = activeSearchQuery(), !query.pattern.isEmpty else {
            showFind(); return nil
        }
        if let scope = editorVC.searchScopeSelection, scope.length > 0 {
            query.scope = .selection(scope)
        }
        guard let matches = try? SearchEngine.matches(for: query, in: curDoc?.content ?? "") else {
            showLocalizedStatus("status.invalidSearchPattern"); return nil
        }
        return (query, matches.map(\.range))
    }

    func toggleSearchHighlight() {
        if !editorVC.searchHighlightRangesForTesting.isEmpty {
            editorVC.showSearchHighlights([]); editorVC.showSearchMarkers([]); return
        }
        guard let (_, ranges) = currentSearchMatches() else { return }
        editorVC.showSearchHighlights(ranges)
        editorVC.showSearchMarkers(ranges)
        showLocalizedStatus("status.highlightedMatches", [ranges.count])
    }

    func selectAllSearchMatches() {
        guard let (query, _) = currentSearchMatches() else { return }
        let outcome = editorVC.selectAllMatches(for: query)
        showLocalizedStatus("status.selectedMatches", [outcome.totalMatches])
    }

    func colorAllSearchMatches() {
        guard let (query, ranges) = currentSearchMatches() else { return }
        let colors: [NSColor] = [.systemYellow, .systemGreen, .systemCyan, .systemPink]
        editorVC.addSearchColorLayer(
            query: query.pattern, ranges: ranges, color: colors[searchColorIndex % colors.count])
        editorVC.showSearchMarkers(ranges)
        searchColorIndex += 1
        showLocalizedStatus("status.coloredMatches", [ranges.count])
    }

    func clearSearchColors() {
        editorVC.clearSearchColorLayers()
        editorVC.showSearchHighlights([])
        editorVC.showSearchMarkers([])
    }

    func listAllSearchMatches() {
        guard let (_, ranges) = currentSearchMatches() else { return }
        sidebarVC.updateSearchResults(ranges, text: curDoc?.content ?? "")
        sidebarVC.showUtilityPane(.results)
        if sidebarVC.view.isHidden || splitView.isSubviewCollapsed(sidebarVC.view) { toggleSidebar() }
    }

    func outlineAllSearchMatches() {
        guard let (_, ranges) = currentSearchMatches() else { return }
        sidebarVC.updateSearchOutline(ranges, text: curDoc?.content ?? "")
        sidebarVC.showUtilityPane(.outline)
        if sidebarVC.view.isHidden || splitView.isSubviewCollapsed(sidebarVC.view) { toggleSidebar() }
    }

    func listSearchColorLayers() {
        let lines = editorVC.searchColorLayers.enumerated().map { index, layer in
            "\(index + 1). \(layer.query) — \(layer.ranges.count) matches"
        }
        sidebarVC.updateSearchColorList(lines)
        sidebarVC.showUtilityPane(.results)
        if sidebarVC.view.isHidden || splitView.isSubviewCollapsed(sidebarVC.view) { toggleSidebar() }
    }

    func showMarkerList() {
        refreshMarkerResults()
        sidebarVC.showMarkerResults()
        if sidebarVC.view.isHidden || splitView.isSubviewCollapsed(sidebarVC.view) { toggleSidebar() }
    }

    func clearAllDocumentMarkers() {
        documentController.documents.forEach { $0.colorMarkers.clear() }
        editorVC.refreshBookmarkGutter()
        refreshMarkerResults()
    }

    func navigateResult(forward: Bool, grepOnly: Bool) {
        if !grepOnly, !diffHunks.isEmpty {
            navigateDifference(delta: forward ? 1 : -1)
            return
        }
        if !grepOnly, editorVC.navigateSearchResult(forward: forward) { return }
        guard outputPane?.activateAdjacentGrepResult(forward: forward) == true else {
            showLocalizedStatus(grepOnly ? "status.noGrepResults" : "find.noResults")
            return
        }
    }

    func returnToSearchStart() {
        guard let offset = searchStartOffset else { showLocalizedStatus("status.noSearchStart"); return }
        let safe = min(offset, (editorVC.textView.string as NSString).length)
        let range = NSRange(location: safe, length: 0)
        editorVC.setSelections([range], primaryRange: range)
        editorVC.textView.scrollRangeToVisible(range)
    }

    func setSearchRangeFromSelection() {
        let selection = editorVC.selectionSet.primaryRange
        guard selection.length > 0 else { showLocalizedStatus("status.selectSearchRangeFirst"); return }
        editorVC.searchScopeSelection = selection
        editorVC.hasExplicitSearchScope = true
        showLocalizedStatus("status.searchRangeSet")
    }

    func selectSearchRange() {
        guard let range = editorVC.searchScopeSelection else { showLocalizedStatus("status.noSearchRange"); return }
        editorVC.setSelections([range], primaryRange: range)
        editorVC.textView.scrollRangeToVisible(range)
    }

    func clearSearchRange() {
        editorVC.searchScopeSelection = nil
        editorVC.hasExplicitSearchScope = false
        showLocalizedStatus("status.searchRangeCleared")
    }

    func showGoToLine() {
        let a = NSAlert()
        a.messageText = AppLocalization.string("dialog.goToLine.title")
        a.addButton(withTitle: AppLocalization.string(.commonGo))
        a.addButton(withTitle: AppLocalization.string(.commonCancel))
        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        input.placeholderString = AppLocalization.string("dialog.goToLine.placeholder")
        a.accessoryView = input
        a.beginSheetModal(for: window!) { [weak self] r in
            guard r == .alertFirstButtonReturn else { return }
            let parts = input.stringValue.split(whereSeparator: { $0 == ":" || $0.isWhitespace })
            guard let first = parts.first, let line = Int(first) else { return }
            let column = parts.count > 1 ? (Int(parts[1]) ?? 1) : 1
            self?.editorVC.goTo(line: line, column: column)
        }
    }

    func showQuickOpen() {
        guard let w = window else { return }
        guard let rootURL = sidebarVC.rootFolderURL else {
            let a = NSAlert()
            a.messageText = AppLocalization.string("dialog.quickOpen.noFolderTitle")
            a.informativeText = AppLocalization.string("dialog.quickOpen.noFolderExplanation")
            a.addButton(withTitle: AppLocalization.string(.commonOK))
            a.beginSheetModal(for: w, completionHandler: nil)
            return
        }

        if let qo = quickOpen, qo.isVisible {
            qo.orderOut(nil)
            w.removeChildWindow(qo)
            w.makeFirstResponder(editorVC.textView)
            return
        }

        if quickOpen == nil {
            quickOpen = QuickOpenPanel(relativeTo: w)
            quickOpen?.quickOpenDelegate = self
        } else {
            let panelW: CGFloat = 520
            let panelH: CGFloat = 340
            let x = w.frame.midX - panelW / 2
            let y = w.frame.maxY - panelH - 60
            quickOpen?.setFrame(NSRect(x: x, y: y, width: panelW, height: panelH), display: false)
        }
        quickOpen?.loadFiles(from: rootURL)
        quickOpen?.activate()
        w.addChildWindow(quickOpen!, ordered: .above)
        quickOpen?.makeKeyAndOrderFront(nil)
    }

    // MARK: - Grep (M3-06)

    /// Opens the Find in Folder sheet, pre-filled from the Find Bar's
    /// current query and the most sensible folder available.
    func showGrep() {
        guard let window = window else { return }
        let panel = grepPanel ?? {
            let created = GrepPanel()
            created.delegate = self
            created.searchHistory = searchHistory.grep
            grepPanel = created
            return created
        }()

        panel.prefill(with: findBar.isHidden ? lastQuery : findBar.currentQuery)
        if panel.folderURL == nil {
            panel.folderURL = sidebarVC.rootFolderURL
                ?? curDoc?.fileURL?.deletingLastPathComponent()
        }
        window.beginSheet(panel.window)
        panel.focusPattern()
    }

    func grepPanel(_ panel: GrepPanel, didSubmit request: GrepRequest) {
        window?.endSheet(panel.window)
        searchHistoryStore.record(request.query.pattern, in: .grep, state: &searchHistory)
        syncSearchHistoryUI()
        runGrep(request)
    }

    func grepPanel(_ panel: GrepPanel, didRequestReplace request: GrepRequest, replacement: String) {
        window?.endSheet(panel.window)
        searchHistoryStore.record(request.query.pattern, in: .grep, state: &searchHistory)
        syncSearchHistoryUI()
        runGrepReplacePreview(request: request, replacement: replacement)
    }

    func grepPanelDidCancel(_ panel: GrepPanel) {
        window?.endSheet(panel.window)
    }

    func grepPanelDidRequestFolderChoice(_ panel: GrepPanel) {
        let open = NSOpenPanel()
        open.canChooseDirectories = true
        open.canChooseFiles = false
        open.allowsMultipleSelection = false
        open.directoryURL = panel.folderURL
        open.beginSheetModal(for: panel.window) { response in
            guard response == .OK, let url = open.url else { return }
            panel.folderURL = url
        }
    }

    private func runGrep(_ request: GrepRequest) {
        lastGrepRequest = request
        grepCancellation?.cancel()
        externalCommandCancellation?.cancel()
        let token = CancellationToken()
        grepCancellation = token

        let pane = ensureOutputPane()
        pane.beginRun(pattern: request.query.pattern)
        layoutContentViews()

        grepQueue.async { [self] in
            GrepService.run(request, isCancelled: { token.isCancelled }) { event in
                // Every event hops back to the main thread; the search
                // itself — traversal, decoding, matching — stays here on
                // the background queue.
                Task { @MainActor in
                    guard self.grepCancellation === token else { return }
                    self.handle(event)
                }
            }
        }
    }

    func grepCurrentDocument() {
        guard let document = curDoc else { return }
        runInMemoryGrep(documents: [memorySearchDocument(document, index: curIdx)])
    }

    func grepOpenDocuments() {
        runInMemoryGrep(documents: documentController.documents.enumerated().map {
            memorySearchDocument($0.element, index: $0.offset)
        })
    }

    func refineGrepResults() {
        guard let query = activeSearchQuery(), !query.pattern.isEmpty,
              let pane = outputPane, !pane.matches.isEmpty else {
            showLocalizedStatus("status.refineGrepFirst")
            return
        }
        let existing = pane.matches
        grepQueue.async { [self] in
            let result = Result { try InMemoryGrepService.refine(existing, query: query) }
            Task { @MainActor in
                switch result {
                case .success(let matches): self.presentMemoryGrep(matches, pattern: query.pattern)
                case .failure(let error): self.showStatusMessage(error.localizedDescription)
                }
            }
        }
    }

    func outputGrepResultsAsDocument() {
        guard let pane = outputPane, !pane.matches.isEmpty else {
            showLocalizedStatus("status.noGrepOutput")
            return
        }
        let summary = GrepSummary(
            scannedFiles: Set(pane.matches.map(\.url)).count,
            matchedFiles: Set(pane.matches.map(\.url)).count,
            matchCount: pane.matches.count)
        let text = TextCanonicalization.canonical(GrepResultFormatter.plainText(
            matches: pane.matches, summary: summary, pattern: activeSearchQuery()?.pattern ?? ""))
        newDocument()
        curDoc?.content = text
        curDoc?.markModified()
        curDoc?.cachedTextStorage = nil
        editorVC.reloadCurrentDocument()
        refreshTabs()
    }

    private func runInMemoryGrep(documents: [InMemorySearchDocument]) {
        guard let query = activeSearchQuery(), !query.pattern.isEmpty else {
            showFind(); showLocalizedStatus("status.enterSearchPattern"); return
        }
        let pane = ensureOutputPane()
        pane.beginRun(pattern: query.pattern)
        layoutContentViews()
        grepQueue.async { [self] in
            let result = Result { try InMemoryGrepService.search(documents, query: query) }
            Task { @MainActor in
                switch result {
                case .success(let matches): self.presentMemoryGrep(matches, pattern: query.pattern)
                case .failure(let error): self.showStatusMessage(error.localizedDescription)
                }
            }
        }
    }

    private func presentMemoryGrep(_ matches: [GrepMatch], pattern: String) {
        let pane = ensureOutputPane()
        pane.beginRun(pattern: pattern)
        matches.forEach(pane.append)
        let fileCount = Set(matches.map(\.url)).count
        pane.finish(GrepSummary(
            scannedFiles: fileCount, matchedFiles: fileCount, matchCount: matches.count))
        layoutContentViews()
    }

    private func activeSearchQuery() -> SearchQuery? {
        findBar.isHidden ? lastQuery : findBar.currentQuery
    }

    private func memorySearchDocument(_ document: Document, index: Int) -> InMemorySearchDocument {
        let url = document.fileURL
            ?? URL(string: "maruedit-memory://document/\(index)")
            ?? URL(fileURLWithPath: "/MaruEdit/Untitled-\(index)")
        return InMemorySearchDocument(
            url: url, displayName: document.displayName,
            text: document.content, encoding: document.encoding)
    }

    private func runGrepReplacePreview(request: GrepRequest, replacement: String) {
        grepReplaceCancellation?.cancel()
        let token = CancellationToken(); grepReplaceCancellation = token
        beginOutputOperation("Building Grep Replace preview…")
        grepQueue.async { [self] in
            let result = Result { try GrepReplaceService.scan(
                request: request, replacement: replacement, isCancelled: { token.isCancelled }) }
            Task { @MainActor in
                guard self.grepReplaceCancellation === token else { return }
                self.grepReplaceCancellation = nil
                switch result {
                case .failure(let error):
                    self.outputPane?.appendSystem(error.localizedDescription, severity: .error)
                    self.outputPane?.finishOperation("Grep Replace preview failed.")
                case .success(let set):
                    guard !set.wasCancelled else {
                        self.outputPane?.finishOperation("Grep Replace scan cancelled."); return
                    }
                    self.outputPane?.appendSystem(
                        "Preview: \(set.selectedFileCount) files, \(set.selectedMatchCount) replacements.")
                    self.outputPane?.finishOperation("Grep Replace preview ready.")
                    let preview = GrepReplacePreviewWindowController(changeSet: set)
                    preview.onCancel = { [weak self, weak preview] in
                        if let sheet = preview?.window { self?.window?.endSheet(sheet) }
                        self?.grepReplacePreview = nil
                    }
                    preview.onApply = { [weak self, weak preview] selected in
                        guard let self else { return }
                        if let sheet = preview?.window { self.window?.endSheet(sheet) }
                        self.grepReplacePreview = nil
                        self.applyGrepReplace(selected)
                    }
                    self.grepReplacePreview = preview
                    if let sheet = preview.window { self.window?.beginSheet(sheet) }
                }
            }
        }
    }

    private func applyGrepReplace(_ set: GrepReplaceChangeSet) {
        let token = CancellationToken(); grepReplaceCancellation = token
        beginOutputOperation("Applying Grep Replace…")
        grepQueue.async { [self] in
            let summary = GrepReplaceService.apply(set, isCancelled: { token.isCancelled })
            Task { @MainActor in
                guard self.grepReplaceCancellation === token else { return }
                self.grepReplaceCancellation = nil
                self.outputPane?.appendSystem(
                    "Grep Replace: \(summary.writtenFiles) written, \(summary.failedFiles) not written.",
                    severity: summary.failedFiles == 0 ? .info : .warning)
                self.outputPane?.appendSystem("Recovery: \(summary.transactionDirectory.path)")
                for (url, result) in summary.results where {
                    if case .written = result { return false }; return true
                }() {
                    self.outputPane?.appendSystem("\(url.path): \(result)", severity: .error)
                }
                self.outputPane?.finishOperation(summary.wasCancelled
                    ? "Grep Replace cancelled with partial results." : "Grep Replace finished.")
            }
        }
    }

    private func handle(_ event: GrepEvent) {
        guard let pane = outputPane else { return }
        switch event {
        case .started:
            break
        case .match(let match):
            pane.append(match)
        case .skippedFile(let url, let reason):
            pane.appendSkipped(url, reason: reason)
        case .progress(let scannedFiles):
            pane.updateProgress(scannedFiles: scannedFiles)
        case .finished(let summary):
            pane.finish(summary)
            pane.focusResults()
        }
    }

    private func ensureOutputPane() -> OutputPaneView {
        if let existing = outputPane {
            existing.isHidden = false
            return existing
        }
        let pane = OutputPaneView()
        pane.delegate = self
        pane.autoresizingMask = [.width, .maxYMargin]
        window?.contentView?.addSubview(pane)
        outputPane = pane
        return pane
    }

    func toggleOutputPane() {
        if let outputPane, !outputPane.isHidden {
            outputPaneDidRequestClose(outputPane)
        } else {
            let isNew = outputPane == nil
            let pane = ensureOutputPane()
            if isNew { pane.beginOperation("Output") }
            layoutContentViews()
            pane.focusResults()
        }
    }

    func focusOutputPane() {
        guard let outputPane, !outputPane.isHidden else {
            toggleOutputPane()
            return
        }
        outputPane.focusResults()
    }

    func toggleStatusBar() {
        isStatusBarVisible.toggle()
        statusBar.isHidden = !isStatusBarVisible
        layoutContentViews()
    }

    func toggleSpellChecking() {
        let enabled = !editorVC.textView.isContinuousSpellCheckingEnabled
        curDoc?.spellCheckingOverride = enabled
        editorVC.textView.isContinuousSpellCheckingEnabled = enabled
        showLocalizedStatus(enabled ? "status.spellCheckingOn" : "status.spellCheckingOff")
    }
    func showSpellingCorrections() {
        window?.makeFirstResponder(editorVC.textView)
        editorVC.textView.showGuessPanel(nil)
    }
    func openCurrentFolderInFinder() {
        if let file = curDoc?.fileURL {
            NSWorkspace.shared.activateFileViewerSelecting([file])
        } else if let folder = sidebarVC.rootFolderURL {
            NSWorkspace.shared.open(folder)
        } else {
            NSWorkspace.shared.open(FileManager.default.homeDirectoryForCurrentUser)
        }
    }

    func showCharacterCode() {
        let alert = NSAlert()
        alert.messageText = AppLocalization.string("dialog.characterCode.title")
        alert.informativeText = statusBar.characterCodeDetail
        alert.addButton(withTitle: AppLocalization.string(.commonOK))
        if let window { alert.beginSheetModal(for: window) }
    }

    func showCharacterCount() { showCharacterCountConfiguration() }

    func redrawEditor() {
        editorVC.redraw()
        classicChrome.needsDisplay = true
        statusBar.needsDisplay = true
    }

    func toggleFullScreen() { window?.toggleFullScreen(nil) }

    var isStatusBarVisibleForTesting: Bool { isStatusBarVisible }
    func setStatusBarFieldsForTesting(_ fields: Set<StatusBarField>) {
        statusBar.setConfiguredFieldsForTesting(fields)
    }
    var isOutputPaneVisibleForTesting: Bool { outputPane?.isHidden == false }

    func beginExternalCommandOutput(name: String, workingDirectory: URL? = nil,
                                    cancellation: ExternalCommandCancellation?) {
        grepCancellation?.cancel()
        externalCommandCancellation?.cancel()
        externalCommandCancellation = cancellation
        let pane = ensureOutputPane()
        pane.beginExternalCommand(name: name, workingDirectory: workingDirectory)
        layoutContentViews()
    }

    func appendExternalCommandOutput(_ data: Data, isError: Bool) {
        outputPane?.appendExternal(data, isError: isError)
    }

    func finishExternalCommandOutput(status: Int32, cancelled: Bool) {
        outputPane?.finishExternal(status: status, cancelled: cancelled)
        externalCommandCancellation = nil
    }
    var externalCommandOutputTextForTesting: String { outputPane?.resultsText ?? "" }

    func appendMacroError(name: String, message: String, timestamp: Date = Date()) {
        grepCancellation?.cancel()
        externalCommandCancellation?.cancel()
        let pane = ensureOutputPane()
        pane.appendMacroError(name: name, message: message, timestamp: timestamp)
        layoutContentViews()
    }
    func showOutputPane() {
        ensureOutputPane().show(); layoutContentViews()
    }
    private func beginOutputOperation(_ title: String) {
        let pane = ensureOutputPane(); pane.beginOperation(title); layoutContentViews()
    }
    var outputTextForTesting: String { outputPane?.resultsText ?? "" }
    var outputMatchCountForTesting: Int { outputPane?.matches.count ?? 0 }
    var currentDocumentTextForTesting: String { curDoc?.content ?? "" }
    func setSearchQueryForTesting(_ query: SearchQuery) { lastQuery = query }
    var currentSearchQueryForTesting: SearchQuery? { lastQuery }

    // MARK: - OutputPaneViewDelegate

    func outputPane(_ pane: OutputPaneView, didActivate match: GrepMatch) {
        // Goes through the normal open path, so a file that is already
        // open is re-selected rather than opened a second time
        // (`DocumentController.open` reports `wasAlreadyOpen`).
        if match.url.scheme == "maruedit-memory",
           let index = Int(match.url.lastPathComponent),
           let document = documentController.document(at: index) {
            documentController.selectDocument(at: index)
            editorVC.document = document
            refreshTabs(); refreshStatus()
        } else {
            openFile(match.url)
        }
        let length = (editorVC.textView.string as NSString).length
        guard match.range.location <= length else { return }
        let clamped = NSRange(
            location: match.range.location,
            length: min(match.range.length, length - match.range.location)
        )
        editorVC.select(clamped)
        window?.makeFirstResponder(editorVC.textView)
    }

    func outputPane(_ pane: OutputPaneView, didActivate location: OutputLocation) {
        openFile(location.url)
        let text = editorVC.textView.string as NSString
        var line = 1, offset = 0
        while line < location.line, offset < text.length {
            offset = NSMaxRange(text.lineRange(for: NSRange(location: offset, length: 0)))
            line += 1
        }
        let lineRange = text.lineRange(for: NSRange(location: min(offset, text.length), length: 0))
        offset = min(offset + location.column - 1, NSMaxRange(lineRange))
        editorVC.select(NSRange(location: offset, length: 0))
        window?.makeFirstResponder(editorVC.textView)
    }

    func outputPaneDidRequestRerun(_ pane: OutputPaneView) {
        guard let request = lastGrepRequest else { return }
        runGrep(request)
    }

    func outputPaneDidRequestCancel(_ pane: OutputPaneView) {
        grepCancellation?.cancel()
        grepReplaceCancellation?.cancel()
        externalCommandCancellation?.cancel()
    }

    func outputPaneDidRequestClose(_ pane: OutputPaneView) {
        grepCancellation?.cancel()
        pane.isHidden = true
        layoutContentViews()
        window?.makeFirstResponder(editorVC.textView)
    }

    func outputPaneDidRequestSave(_ pane: OutputPaneView, text: String) {
        guard let window = window else { return }
        let save = NSSavePanel()
        save.nameFieldStringValue = "maruedit-output.txt"
        save.beginSheetModal(for: window) { response in
            guard response == .OK, let url = save.url else { return }
            do {
                try AtomicFileWriter.write(Data(text.utf8), to: url)
            } catch {
                let alert = NSAlert()
                alert.alertStyle = .critical
                alert.messageText = AppLocalization.string("dialog.outputSave.title")
                alert.informativeText = AppLocalization.string("dialog.outputSave.explanation")
                alert.addButton(withTitle: AppLocalization.string(.commonOK))
                alert.beginSheetModal(for: window)
            }
        }
    }

    // MARK: - QuickOpenDelegate

    func quickOpenDidSelectFile(_ url: URL) {
        openFile(url)
    }

    func quickOpenDismissed() {
        if let qo = quickOpen { window?.removeChildWindow(qo) }
        window?.makeFirstResponder(editorVC.textView)
    }

    // MARK: - Refresh

    private func refreshTabs() {
        let items = documentController.documents.map { TabItem(title: $0.localizedDisplayName, isModified: $0.isModified) }
        classicChrome.setDocumentCount(items.count)
        tabBar.setTabs(items, selectedIndex: curIdx)
        classicChrome.updateHeading(curDoc?.localizedDisplayName ?? AppLocalization.string("window.untitled"))
        layoutContentViews()
    }

    private func refreshStatus() {
        if let doc = curDoc {
            if diffTargetDocument == nil, secondaryEditorVC?.document !== doc {
                secondaryEditorVC?.document = doc
            }
            refreshOutline(for: doc)
            refreshMarkerResults()
            statusBar.updateLanguage(doc.language, profileName: doc.fileTypeProfile?.name)
            statusBar.updateEncoding(doc.encoding)
            statusBar.updateByteOrderMark(doc.hasByteOrderMark)
            statusBar.updateLineEnding(doc.lineEnding)
            let settings = doc.fileTypeProfile?.settings
            statusBar.updateIndentation(
                style: settings?.indentStyle ?? .spaces,
                width: editorVC.effectiveTabWidth)
            statusBar.updateLayoutMode(
                isVertical: editorVC.isVerticalLayout, isColumn: editorVC.isColumnLayout,
                columnCount: editorVC.columnCountForTesting)
            statusBar.updateAccessMode(
                isReadOnly: doc.isReadOnly || doc.isOverwriteProhibited,
                isViewMode: doc.isViewMode)
            statusBar.updateLargeFileMode(doc.largeFileMode)
            statusBar.updateDocumentMetrics(
                text: doc.content, fontSize: editorVC.currentEditorFont.pointSize)
        }
        classicChrome.refreshCommandPresentation()
    }

    // MARK: - Encoding selection and reopen (M2-02)

    /// Builds the "Reopen with Encoding" menu — shared by the status bar's
    /// clickable encoding label and `AppCoordinator.reopenWithEncodingMenu()`
    /// (which `AppDelegate`'s File menu submenu rebuilds from). Not routed
    /// through the Command Registry: like "Open Recent", this is a
    /// dynamically-populated list of choices, not a single fixed action —
    /// see docs/commands.md.
    func buildEncodingMenu() -> NSMenu {
        let menu = NSMenu()
        let automatic = NSMenuItem(
            title: AppLocalization.string("encoding.reloadAutomatic"),
            action: #selector(didSelectAutomaticEncodingDetection(_:)), keyEquivalent: "")
        automatic.target = self
        automatic.isEnabled = curDoc?.fileURL != nil
        menu.addItem(automatic)
        menu.addItem(.separator())

        let common: [(String, TextEncoding)] = [
            (AppLocalization.string("encoding.shiftJIS"), .windows31J),
            (AppLocalization.string("encoding.eucJP"), .eucJP),
            (AppLocalization.string("encoding.jis"), .iso2022JP),
            (AppLocalization.string("encoding.utf16"), .utf16LittleEndian),
            (AppLocalization.string("encoding.utf16BE"), .utf16BigEndian),
            (AppLocalization.string("encoding.utf8"), .utf8),
            (AppLocalization.string("encoding.utf7"), .utf7),
        ]
        for (title, encoding) in common {
            menu.addItem(encodingMenuItem(for: encoding, title: title))
        }

        let other = NSMenuItem(title: AppLocalization.string("encoding.other"), action: nil, keyEquivalent: "")
        let otherMenu = NSMenu(title: other.title)
        let commonEncodings = Set(common.map(\.1))
        for encoding in TextEncoding.userSelectable where !commonEncodings.contains(encoding) {
            otherMenu.addItem(encodingMenuItem(for: encoding))
        }
        for encoding in RecentEncodings.encodings where !commonEncodings.contains(encoding)
            && !otherMenu.items.contains(where: { $0.representedObject as? TextEncoding == encoding }) {
            otherMenu.addItem(encodingMenuItem(for: encoding))
        }
        other.submenu = otherMenu
        menu.addItem(other)
        menu.addItem(.separator())

        for (title, value) in [
            (AppLocalization.string("encoding.lineEndingCRLF"), "crlf"),
            (AppLocalization.string("encoding.lineEndingCR"), "cr"),
            (AppLocalization.string("encoding.lineEndingLF"), "lf"),
        ] {
            let item = NSMenuItem(
                title: title, action: #selector(didSelectLineEnding(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = value
            let active = curDoc?.lineEnding.displayName
            item.state = active == (value == "crlf" ? "CRLF" : value.uppercased()) ? .on : .off
            menu.addItem(item)
        }
        let bom = NSMenuItem(title: AppLocalization.string("encoding.bom"), action: #selector(didToggleEncodingMenuBOM(_:)), keyEquivalent: "")
        bom.target = self
        bom.state = curDoc?.hasByteOrderMark == true ? .on : .off
        bom.isEnabled = curDoc?.encoding.byteOrderMark != nil
        menu.addItem(bom)
        return menu
    }

    private func encodingMenuItem(for encoding: TextEncoding, title: String? = nil) -> NSMenuItem {
        let mi = NSMenuItem(title: title ?? encoding.displayName, action: #selector(didSelectEncodingMenuItem(_:)), keyEquivalent: "")
        mi.target = self
        mi.representedObject = encoding
        mi.state = (curDoc?.encoding == encoding) ? .on : .off
        return mi
    }

    @objc private func didToggleEncodingMenuBOM(_ sender: NSMenuItem) {
        guard let doc = curDoc, doc.encoding.byteOrderMark != nil else { return }
        let proxy = NSMenuItem()
        proxy.representedObject = NSNumber(value: !doc.hasByteOrderMark)
        didSelectByteOrderMark(proxy)
    }

    @objc private func didSelectAutomaticEncodingDetection(_ sender: NSMenuItem) {
        guard let doc = curDoc, doc.fileURL != nil else { return }
        if doc.isModified {
            let alert = NSAlert()
            alert.messageText = AppLocalization.string("dialog.reload.title", [doc.localizedDisplayName])
            alert.informativeText = AppLocalization.string("dialog.encoding.autoReloadExplanation")
            alert.addButton(withTitle: AppLocalization.string(.commonReload))
            alert.addButton(withTitle: AppLocalization.string(.commonCancel))
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        do {
            try doc.reopenWithAutomaticEncodingDetection()
            editorVC.reloadCurrentDocument()
            refreshTabs(); refreshStatus()
            scheduleSessionSave()
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    @objc private func didSelectEncodingMenuItem(_ sender: NSMenuItem) {
        guard let encoding = sender.representedObject as? TextEncoding,
              let document = curDoc else { return }
        if document.fileURL != nil {
            reopenCurrentDocument(with: encoding)
        } else {
            document.encoding = encoding
            RecentEncodings.add(encoding)
            refreshStatus()
            scheduleSessionSave()
        }
    }

    func buildInputModeMenu() -> NSMenu {
        let menu = NSMenu()
        for (title, mode) in [(AppLocalization.string(.inputOverwrite), EditorInputMode.overwrite),
                              (AppLocalization.string(.inputInsert), EditorInputMode.insert)] {
            let item = NSMenuItem(title: title, action: #selector(didSelectInputMode(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = mode.rawValue
            item.state = curDoc?.inputMode == mode ? .on : .off
            menu.addItem(item)
        }
        return menu
    }

    @objc private func didSelectInputMode(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let mode = EditorInputMode(rawValue: rawValue) else { return }
        editorVC.setInputMode(mode)
        refreshStatus()
        scheduleSessionSave()
    }

    func statusBar(
        _ statusBar: StatusBarView, didClick control: StatusBarControl, at point: NSPoint
    ) {
        let menu: NSMenu
        switch control {
        case .cursorPosition:
            showGoToLine(); return
        case .totals:
            showCharacterCountConfiguration(); return
        case .characterCode:
            let alert = NSAlert()
            alert.messageText = AppLocalization.string("dialog.characterCode.title")
            alert.informativeText = statusBar.characterCodeDetail
            alert.addButton(withTitle: AppLocalization.string(.commonOK))
            alert.beginSheetModal(for: window!); return
        case .inputMode:
            menu = buildInputModeMenu()
        case .layoutMode:
            menu = buildLayoutModeMenu()
        case .fontSize:
            showStatusFontSizeControl(); return
        case .macroActivity:
            onStatusMacroControl?(); return
        case .largeFileMode:
            menu = buildLargeFileModeMenu()
        case .encoding:
            menu = buildEncodingMenu()
        case .byteOrderMark: menu = buildByteOrderMarkMenu()
        case .lineEnding: menu = buildLineEndingMenu()
        case .languageProfile: menu = buildLanguageProfileMenu()
        }
        menu.popUp(positioning: nil, at: point, in: statusBar)
    }

    private func showCharacterCountConfiguration() {
        let alert = NSAlert()
        alert.messageText = AppLocalization.string("dialog.characterCount.title")
        alert.informativeText = AppLocalization.string("dialog.characterCount.explanation")
        let configuration = statusBar.characterCountConfiguration
        let entries: [(String, Double)] = [
            (AppLocalization.string("dialog.characterCount.fullWidth"), configuration.fullWidth),
            (AppLocalization.string("dialog.characterCount.halfWidth"), configuration.halfWidth),
            (AppLocalization.string("dialog.characterCount.fullWidthSpaces"), configuration.fullWidthSpace),
            (AppLocalization.string("dialog.characterCount.halfWidthSpaces"), configuration.halfWidthSpace),
            (AppLocalization.string("dialog.characterCount.tabs"), configuration.tab),
            (AppLocalization.string("dialog.characterCount.lineBreaks"), configuration.lineBreak),
        ]
        let grid = NSGridView()
        var fields: [NSTextField] = []
        for (title, value) in entries {
            let field = NSTextField(string: String(value))
            field.alignment = .right; field.setAccessibilityLabel(title)
            fields.append(field)
            grid.addRow(with: [NSTextField(labelWithString: title), field])
        }
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 1).width = 72
        alert.accessoryView = grid
        alert.addButton(withTitle: AppLocalization.string(.commonApply))
        alert.addButton(withTitle: AppLocalization.string(.commonCancel))
        alert.addButton(withTitle: AppLocalization.string(.commonReset))
        alert.beginSheetModal(for: window!) { [weak self] response in
            guard let self else { return }
            if response == .alertThirdButtonReturn {
                self.statusBar.setCharacterCountConfiguration(.standard)
                return
            }
            guard response == .alertFirstButtonReturn else { return }
            let values = fields.map { max(0, Double($0.stringValue) ?? 0) }
            self.statusBar.setCharacterCountConfiguration(CharacterCountConfiguration(
                fullWidth: values[0], halfWidth: values[1], fullWidthSpace: values[2],
                halfWidthSpace: values[3], tab: values[4], lineBreak: values[5]))
        }
    }

    private func showStatusFontSizeControl() {
        let baseline = editorVC.currentEditorFont.pointSize
        statusFontResetSize = baseline
        let controller = StatusFontSizePopoverController(size: baseline)
        controller.onChange = { [weak self] size in self?.applyStatusFontSize(size) }
        controller.onReset = { [weak self] in
            guard let self, let size = self.statusFontResetSize else { return }
            self.applyStatusFontSize(size)
        }
        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = controller
        fontSizePopover = popover
        let frame = statusBar.frame(for: .fontSize) ?? .zero
        popover.show(relativeTo: frame, of: statusBar, preferredEdge: .maxY)
    }

    private func applyStatusFontSize(_ size: CGFloat) {
        let clamped = min(72, max(8, size))
        guard let font = NSFont(descriptor: editorVC.currentEditorFont.fontDescriptor, size: clamped) else { return }
        editorVC.applyEditorFont(font)
        refreshStatus()
    }

    func adjustStatusFontSizeForTesting(_ size: CGFloat) { applyStatusFontSize(size) }
    var currentStatusFontSizeForTesting: CGFloat { editorVC.currentEditorFont.pointSize }

    func buildLayoutModeMenu() -> NSMenu {
        let menu = NSMenu()
        for (title, tag) in [("Horizontal Writing", 0), ("Vertical Writing", 1), ("Column Layout", 2)] {
            let item = NSMenuItem(title: title, action: #selector(didSelectLayoutMode(_:)), keyEquivalent: "")
            item.target = self; item.tag = tag
            item.state = tag == (editorVC.isColumnLayout ? 2 : editorVC.isVerticalLayout ? 1 : 0) ? .on : .off
            menu.addItem(item)
        }
        return menu
    }

    @objc private func didSelectLayoutMode(_ sender: NSMenuItem) {
        if sender.tag == 0 {
            if editorVC.isColumnLayout { editorVC.toggleColumnLayout() }
            if editorVC.isVerticalLayout { editorVC.toggleVerticalLayout() }
        } else if sender.tag == 1 {
            if editorVC.isColumnLayout { editorVC.toggleColumnLayout() }
            if !editorVC.isVerticalLayout { editorVC.toggleVerticalLayout() }
        } else if sender.tag == 2 {
            if editorVC.isVerticalLayout { editorVC.toggleVerticalLayout() }
            if !editorVC.isColumnLayout { editorVC.toggleColumnLayout() }
        }
        refreshStatus()
    }

    func buildLargeFileModeMenu() -> NSMenu {
        let menu = NSMenu()
        let current = NSMenuItem(
            title: SettingsLocalization.text("reducedFeatures"), action: nil, keyEquivalent: "")
        current.state = curDoc?.largeFileMode.usesReducedFeatures == true ? .on : .off
        menu.addItem(current)
        let enable = NSMenuItem(
            title: SettingsLocalization.text("enableAllFeatures") + "…",
            action: #selector(enableAllLargeFileFeatures),
            keyEquivalent: "")
        enable.target = self
        enable.isEnabled = curDoc?.largeFileMode == .reducedFeatures
        menu.addItem(enable)
        return menu
    }

    @objc private func enableAllLargeFileFeatures() {
        guard curDoc?.largeFileMode == .reducedFeatures else { return }
        let alert = NSAlert()
        alert.messageText = SettingsLocalization.text("enableAllLargeTitle")
        alert.informativeText = SettingsLocalization.text("enableAllLargeExplanation")
        alert.addButton(withTitle: SettingsLocalization.text("enableAllFeatures"))
        alert.addButton(withTitle: SettingsLocalization.text("keepReduced"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        editorVC.enableAllLargeFileFeatures()
        refreshStatus()
    }

    func buildByteOrderMarkMenu() -> NSMenu {
        let menu = NSMenu()
        for (title, enabled) in [("With BOM", true), ("Without BOM", false)] {
            let item = NSMenuItem(
                title: title, action: #selector(didSelectByteOrderMark(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = NSNumber(value: enabled)
            item.state = curDoc?.hasByteOrderMark == enabled ? .on : .off
            item.isEnabled = !enabled || curDoc?.encoding.byteOrderMark != nil
            menu.addItem(item)
        }
        return menu
    }

    @objc private func didSelectByteOrderMark(_ sender: NSMenuItem) {
        guard let doc = curDoc,
              let enabled = (sender.representedObject as? NSNumber)?.boolValue,
              !enabled || doc.encoding.byteOrderMark != nil else { return }
        guard doc.hasByteOrderMark != enabled else { return }
        doc.hasByteOrderMark = enabled
        doc.markFormatModified()
        refreshTabs(); refreshStatus()
    }

    func buildLineEndingMenu() -> NSMenu {
        let menu = NSMenu()
        for (title, value) in [("LF", "lf"), ("CRLF", "crlf"), ("CR", "cr")] {
            let item = NSMenuItem(
                title: title, action: #selector(didSelectLineEnding(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = value
            item.state = curDoc?.lineEnding.displayName == title ? .on : .off
            menu.addItem(item)
        }
        return menu
    }

    @objc private func didSelectLineEnding(_ sender: NSMenuItem) {
        guard let doc = curDoc, let value = sender.representedObject as? String else { return }
        let state: LineEndingState
        switch value {
        case "lf": state = .lf
        case "crlf": state = .crlf
        case "cr": state = .cr
        default: return
        }
        guard doc.lineEnding != state else { return }
        doc.lineEnding = state
        doc.markFormatModified()
        refreshTabs(); refreshStatus()
    }

    func buildLanguageProfileMenu() -> NSMenu {
        let menu = NSMenu()
        for source in [FileTypeProfileSource.user, .builtIn] {
            let profiles = documentController.availableFileTypeProfiles.filter { $0.source == source }
            guard !profiles.isEmpty else { continue }
            let heading = NSMenuItem(
                title: AppLocalization.string(source == .user
                    ? "profile.userProfiles" : "profile.builtInProfiles"),
                action: nil, keyEquivalent: "")
            heading.isEnabled = false; menu.addItem(heading)
            for sourced in profiles.sorted(by: { $0.profile.name < $1.profile.name }) {
                let item = NSMenuItem(
                    title: sourced.profile.name, action: #selector(didSelectFileTypeProfile(_:)),
                    keyEquivalent: "")
                item.target = self; item.representedObject = sourced.profile.id
                item.state = curDoc?.fileTypeProfile?.id == sourced.profile.id ? .on : .off
                menu.addItem(item)
            }
            menu.addItem(.separator())
        }
        let languageHeading = NSMenuItem(title: AppLocalization.string("profile.syntaxOnly"), action: nil, keyEquivalent: "")
        languageHeading.isEnabled = false; menu.addItem(languageHeading)
        for language in Language.allCases where language != .plainText {
            menu.addItem(languageMenuItem(language))
        }
        menu.addItem(languageMenuItem(.plainText))
        return menu
    }

    @objc private func didSelectFileTypeProfile(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String,
              let profile = documentController.fileTypeProfile(id: id), let doc = curDoc else { return }
        doc.applyFileTypeProfile(profile)
        editorVC.applyPreferences(editorVC.appliedPreferences)
        editorVC.rehighlightEntireDocument()
        refreshStatus()
    }

    private func languageMenuItem(_ language: Language) -> NSMenuItem {
        let item = NSMenuItem(
            title: language.displayName, action: #selector(didSelectLanguage(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = language.rawValue
        item.state = curDoc?.language == language ? .on : .off
        return item
    }

    @objc private func didSelectLanguage(_ sender: NSMenuItem) {
        guard let doc = curDoc, let raw = sender.representedObject as? String,
              let language = Language(rawValue: raw) else { return }
        doc.language = language
        editorVC.rehighlightEntireDocument()
        refreshStatus()
    }

    /// Re-reads the current document's file with `encoding`, resolving
    /// unsaved changes first (ROADMAP.md M2-02 acceptance: never silently
    /// lose unsaved edits).
    func reopenCurrentDocument(with encoding: TextEncoding) {
        guard let doc = curDoc, doc.fileURL != nil else { return }

        if doc.isModified {
            let a = NSAlert()
            a.messageText = AppLocalization.string("dialog.encoding.saveBeforeReopen", [doc.localizedDisplayName])
            a.informativeText = AppLocalization.string("dialog.encoding.reopenExplanation")
            a.addButton(withTitle: AppLocalization.string(.commonSave))
            a.addButton(withTitle: AppLocalization.string(.commonDontSave))
            a.addButton(withTitle: AppLocalization.string(.commonCancel))
            let resp = a.runModal()
            if resp == .alertFirstButtonReturn { saveDocument() }
            else if resp == .alertThirdButtonReturn { return }
        }

        do {
            try doc.reopen(forcing: encoding)
            editorVC.reloadCurrentDocument()
            refreshTabs(); refreshStatus()
            RecentEncodings.add(encoding)
            scheduleSessionSave()
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    // MARK: - NSSplitViewDelegate

    nonisolated func splitView(_ sv: NSSplitView, constrainMinCoordinate pos: CGFloat, ofSubviewAt idx: Int) -> CGFloat {
        MainActor.assumeIsolated { idx == 0 ? 150 : pos }
    }

    nonisolated func splitView(_ sv: NSSplitView, constrainMaxCoordinate pos: CGFloat, ofSubviewAt idx: Int) -> CGFloat {
        MainActor.assumeIsolated { idx == 0 ? sv.bounds.width - 400 : pos }
    }

    nonisolated func splitView(_ sv: NSSplitView, canCollapseSubview subview: NSView) -> Bool {
        MainActor.assumeIsolated { subview === sidebarVC.view && sidebarManuallyCollapsed }
    }

    nonisolated func splitView(_ sv: NSSplitView, shouldCollapseSubview subview: NSView, forDoubleClickOnDividerAt dividerIndex: Int) -> Bool {
        MainActor.assumeIsolated {
            if subview === sidebarVC.view {
                sidebarManuallyCollapsed = true
                return true
            }
            return false
        }
    }

    nonisolated func splitViewDidResizeSubviews(_ notification: Notification) {
        MainActor.assumeIsolated { updateTabBarFrame() }
    }

    // MARK: - EditorViewControllerDelegate

    func editorTextDidChange(_ vc: EditorViewController) {
        if let doc = curDoc {
            (NSApp.delegate as? AppDelegate)?.agentServer.documentDidChange(doc.automationID)
            doc.cachedTextStorage = vc.textView.textStorage
            tabBar.updateTab(at: curIdx, item: TabItem(title: doc.localizedDisplayName, isModified: doc.isModified))
            scheduleRecoverySaveIfUnnamed(doc)
            refreshOutline(for: doc)
            statusBar.updateDocumentMetrics(
                text: doc.content, fontSize: editorVC.currentEditorFont.pointSize)
        }
        scheduleSessionSave()
        if vc === editorVC { secondaryEditorVC?.synchronizeSharedDocumentState() }
        else { editorVC.synchronizeSharedDocumentState() }
        if diffTargetDocument != nil, vc === editorVC { refreshDiffHunks() }
    }
    func editorCursorMoved(_ vc: EditorViewController, state: EditorCursorState) {
        lastCursorColumn = state.displayColumn
        updateClassicRuler(currentColumn: state.displayColumn)
        cursorPositionLabel.update(line: state.lineNumber, column: state.displayColumn)
        statusBar.updateCursor(state)
        statusBar.updateInputMode(curDoc?.inputMode ?? .insert)
        if let title = sidebarVC.selectOutlineSymbol(containingLine: state.lineNumber - 1) {
            classicChrome.updateHeading(title)
        } else {
            classicChrome.updateHeading(curDoc?.localizedDisplayName ?? AppLocalization.string("window.untitled"))
        }
    }
    func editorDidChooseFont(_ vc: EditorViewController, font: NSFont) {
        onEditorFontChange?(font)
    }
    func editorCompletionMessage(_ vc: EditorViewController, message: String) {
        showStatusMessage(message)
    }

    // MARK: - TabBarViewDelegate

    func tabBarDidSelectTab(at index: Int) {
        guard let doc = documentController.document(at: index) else { return }
        saveCursorPosition()
        documentController.selectDocument(at: index)
        editorVC.document = doc
        tabBar.selectTab(at: index)
        refreshStatus()
        window?.title = AppLocalization.string("window.document.title", [doc.localizedDisplayName])
        if let url = doc.fileURL { sidebarVC.revealFile(url) }
        deferredRestoreCursor()
        scheduleSessionSave()
    }

    func tabBarDidCloseTab(at index: Int) {
        let prev = curIdx
        documentController.selectDocument(at: index)
        closeCurrentTab()
        if curIdx != prev { refreshTabs() }
    }

    func tabBarDidMoveTab(from source: Int, to destination: Int) {
        documentController.moveDocument(from: source, to: destination)
        refreshTabs()
        scheduleSessionSave()
    }

    func tabBarDidRequestClose(_ scope: TabCloseScope, at index: Int) {
        guard documentController.documents.indices.contains(index) else { return }
        switch scope {
        case .current:
            tabBarDidCloseTab(at: index)
        case .others, .left, .right:
            let anchor = documentController.documents[index]
            let indices: [Int]
            switch scope {
            case .others: indices = documentController.documents.indices.filter { $0 != index }
            case .left: indices = Array(documentController.documents.indices.prefix(index))
            case .right: indices = Array(documentController.documents.indices.suffix(from: index + 1))
            case .current: indices = []
            }
            for target in indices.reversed() {
                documentController.selectDocument(at: target)
                if !closeCurrentTab() { break }
            }
            if let anchorIndex = documentController.documents.firstIndex(where: { $0 === anchor }) {
                tabBarDidSelectTab(at: anchorIndex)
            }
        }
    }

    func tabBarLayoutOptionsDidChange() { layoutContentViews() }

    func toggleTabMode() { tabBar.isTabModeEnabled.toggle() }
    var isTabModeEnabled: Bool { tabBar.isTabModeEnabled }

    var selectedTabIndexForTesting: Int { curIdx }
    var tabCountForTesting: Int { documentController.documents.count }
    var editorTextForTesting: String { editorVC.textView.string }

    // MARK: - SidebarDelegate

    func sidebarDidSelectFile(_ url: URL, inNewTab: Bool) {
        if inNewTab {
            openFile(url)
        } else {
            openFileInCurrentTab(url)
        }
    }

    func sidebarDidSelectOutlineSymbol(_ symbol: OutlineSymbol) {
        let range = NSRange(location: symbol.utf16Range.location, length: 0)
        editorVC.textView.setSelectedRange(range)
        editorVC.textView.scrollRangeToVisible(range)
        window?.makeFirstResponder(editorVC.textView)
    }

    private func refreshOutline(for document: Document) {
        sidebarVC.updateOutline(
            text: document.content, language: document.language,
            customRules: document.fileTypeProfile?.settings.outlineRules ?? [])
    }

    // MARK: - FindBarDelegate

    func findBar(_ bar: FindBarView, perform action: FindBarAction, query: SearchQuery) -> FindOutcome {
        if action != .incremental { lastQuery = query }
        let ranges = (try? SearchEngine.matches(for: query, in: curDoc?.content ?? ""))?.map(\.range) ?? []
        editorVC.showSearchMarkers(ranges)
        sidebarVC.updateSearchResults(ranges, text: curDoc?.content ?? "")

        switch action {
        case .incremental:
            return editorVC.find(query, direction: .incremental)
        case .findNext:
            recordSearchHistory(query)
            return editorVC.find(query, direction: .next)
        case .findPrevious:
            recordSearchHistory(query)
            return editorVC.find(query, direction: .previous)
        case .replace:
            recordSearchHistory(query)
            return editorVC.replaceCurrent(query)
        case .replaceAll:
            recordSearchHistory(query)
            return editorVC.replaceAll(query)
        }
    }

    func findBarDidDismiss(_ bar: FindBarView) {
        findBar.isHidden = true
        layoutContentViews()
        editorVC.incrementalSearchAnchor = nil
        if !editorVC.hasExplicitSearchScope { editorVC.searchScopeSelection = nil }
        editorVC.showSearchHighlights([])
        editorVC.showSearchMarkers([])
        sidebarVC.updateSearchResults([], text: curDoc?.content ?? "")
        window?.makeFirstResponder(editorVC.textView)
    }

    private func recordSearchHistory(_ query: SearchQuery) {
        searchHistoryStore.record(query.pattern, in: .find, state: &searchHistory)
        if let replacement = query.replacement {
            searchHistoryStore.record(replacement, in: .replace, state: &searchHistory)
        }
        syncSearchHistoryUI()
    }

    private func syncSearchHistoryUI() {
        findBar.searchHistory = searchHistory.find
        findBar.replacementHistory = searchHistory.replace
        grepPanel?.searchHistory = searchHistory.grep
    }

    func clearSearchHistory() {
        searchHistoryStore.clear(&searchHistory)
        syncSearchHistoryUI()
    }

    func clearSearchHistory(_ kind: SearchHistoryStore.Kind) {
        searchHistoryStore.clear(kind, state: &searchHistory)
        syncSearchHistoryUI()
        let key: String = switch kind {
        case .find: "status.findHistoryCleared"
        case .replace: "status.replaceHistoryCleared"
        case .grep: "status.grepHistoryCleared"
        }
        showLocalizedStatus(key)
    }

    func addCursorAbove() { editorVC.addCursorAbove() }
    func addCursorBelow() { editorVC.addCursorBelow() }
    func selectNextOccurrence() { editorVC.selectNextOccurrence() }
    func selectAllOccurrences() { editorVC.selectAllOccurrences() }
    func undoLastAddedCursor() { editorVC.undoLastAddedCursor() }
    func beginColumnSelection() { editorVC.beginColumnSelectionCommand() }
    func performLineCommand(_ command: LineEditCommand) { editorVC.performLineCommand(command) }
    func toggleBookmark() { editorVC.toggleBookmark() }
    func nextBookmark() { editorVC.nextBookmark() }
    func previousBookmark() { editorVC.previousBookmark() }
    func clearBookmarks() { editorVC.clearBookmarks() }

    func showBookmarkList() {
        guard let document = curDoc else { return }
        let offsets = document.bookmarks.sortedOffsets
        guard !offsets.isEmpty else { showLocalizedStatus("status.noBookmarks"); return }
        let text = editorVC.textView.string as NSString
        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 420, height: 26))
        for (index, offset) in offsets.enumerated() {
            let safe = min(offset, text.length)
            let line = text.substring(to: safe).reduce(1) { $1 == "\n" ? $0 + 1 : $0 }
            let range = text.lineRange(for: NSRange(location: safe, length: 0))
            let preview = text.substring(with: range).trimmingCharacters(in: .whitespacesAndNewlines)
            popup.addItem(withTitle: AppLocalization.string("dialog.list.line", [index + 1, line, preview]))
        }
        let alert = NSAlert()
        alert.messageText = AppLocalization.string("dialog.bookmarks.title")
        alert.informativeText = AppLocalization.string("dialog.bookmarks.explanation")
        alert.accessoryView = popup
        alert.addButton(withTitle: AppLocalization.string("common.goTo"))
        alert.addButton(withTitle: AppLocalization.string(.commonRemove))
        alert.addButton(withTitle: AppLocalization.string(.commonCancel))
        let response = alert.runModal()
        guard offsets.indices.contains(popup.indexOfSelectedItem) else { return }
        let offset = offsets[popup.indexOfSelectedItem]
        if response == .alertFirstButtonReturn {
            let range = NSRange(location: offset, length: 0)
            editorVC.setSelections([range], primaryRange: range)
            editorVC.textView.scrollRangeToVisible(range)
        } else if response == .alertSecondButtonReturn {
            document.bookmarks.remove(at: offset)
            editorVC.refreshBookmarkGutter()
        }
    }
    func toggleInputMode() { editorVC.toggleInputMode() }
    func moveWordLeft() { editorVC.textView.moveWordLeft(nil) }
    func moveWordRight() { editorVC.textView.moveWordRight(nil) }
    func moveToParagraphStart() { editorVC.textView.moveToBeginningOfParagraph(nil) }
    func moveToParagraphEnd() { editorVC.textView.moveToEndOfParagraph(nil) }
    func deleteWordBackward() { editorVC.textView.deleteWordBackward(nil) }
    func deleteWordForward() { editorVC.textView.deleteWordForward(nil) }
    func toggleMarker(_ color: MarkerColor) { editorVC.toggleMarker(color); refreshMarkerResults() }
    func nextMarker() { editorVC.nextMarker() }
    func previousMarker() { editorVC.previousMarker() }
    func clearMarkers() { editorVC.clearMarkers(); refreshMarkerResults() }
    func configureTemporaryColorMarker() {
        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 180, height: 26))
        popup.addItems(withTitles: MarkerColor.allCases.map { $0.rawValue.capitalized })
        if let index = MarkerColor.allCases.firstIndex(of: editorVC.temporaryColorMarkerColor) {
            popup.selectItem(at: index)
        }
        let alert = NSAlert()
        alert.messageText = AppLocalization.string("dialog.marker.title")
        alert.informativeText = AppLocalization.string("dialog.marker.explanation")
        alert.accessoryView = popup
        alert.addButton(withTitle: AppLocalization.string(.commonApply))
        alert.addButton(withTitle: AppLocalization.string(.commonCancel))
        guard alert.runModal() == .alertFirstButtonReturn,
              MarkerColor.allCases.indices.contains(popup.indexOfSelectedItem) else { return }
        editorVC.addTemporaryColorMarkers(MarkerColor.allCases[popup.indexOfSelectedItem])
    }
    func applyTemporaryColorMarker() { editorVC.addTemporaryColorMarkers() }
    func removeTemporaryColorMarker() { editorVC.removeTemporaryColorMarkersInSelection() }
    func clearTemporaryColorMarkers() { editorVC.clearTemporaryColorMarkers() }
    func selectTemporaryColorMarkers() { editorVC.selectTemporaryColorMarkers() }
    func nextTemporaryColorMarker() { editorVC.nextTemporaryColorMarker() }
    func previousTemporaryColorMarker() { editorVC.previousTemporaryColorMarker() }
    func nextHighlightedLine() { editorVC.nextHighlightedLine() }
    func showOutlineAnalysis() {
        guard let document = curDoc else { return }
        refreshOutline(for: document)
        sidebarVC.showUtilityPane(.outline)
        if sidebarVC.view.isHidden || splitView.isSubviewCollapsed(sidebarVC.view) { toggleSidebar() }
    }
    func previousHighlightedLine() { editorVC.previousHighlightedLine() }
    func selectHighlightedLineArea() { editorVC.selectHighlightedLineArea() }
    func nextEditMark() { editorVC.nextEditMark() }
    func previousEditMark() { editorVC.previousEditMark() }
    func clearEditMarks() { editorVC.clearEditMarks() }

    func showHighlightList() {
        guard let document = curDoc else { return }
        let markers = document.colorMarkers.sortedMarkers
        guard !markers.isEmpty else { showLocalizedStatus("status.noHighlights"); return }
        let text = editorVC.textView.string as NSString
        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 440, height: 26))
        for marker in markers {
            let safe = min(marker.offset, text.length)
            let line = text.substring(to: safe).reduce(1) { $1 == "\n" ? $0 + 1 : $0 }
            let preview = text.substring(with: text.lineRange(for: NSRange(location: safe, length: 0)))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            popup.addItem(withTitle: AppLocalization.string(
                "dialog.highlight.line", [marker.color.rawValue.capitalized, line, preview]))
        }
        let alert = NSAlert()
        alert.messageText = AppLocalization.string("dialog.highlights.title")
        alert.informativeText = AppLocalization.string("dialog.highlights.explanation")
        alert.accessoryView = popup
        alert.addButton(withTitle: AppLocalization.string("common.goTo"))
        alert.addButton(withTitle: AppLocalization.string(.commonRemove))
        alert.addButton(withTitle: AppLocalization.string(.commonCancel))
        let response = alert.runModal()
        guard markers.indices.contains(popup.indexOfSelectedItem) else { return }
        let marker = markers[popup.indexOfSelectedItem]
        if response == .alertFirstButtonReturn {
            let range = NSRange(location: marker.offset, length: 0)
            editorVC.setSelections([range], primaryRange: range)
            editorVC.textView.scrollRangeToVisible(range)
        } else if response == .alertSecondButtonReturn {
            document.colorMarkers.remove(at: marker.offset)
            editorVC.refreshBookmarkGutter(); refreshMarkerResults()
        }
    }
    func showCompletions() { editorVC.showCompletions() }
    func toggleTableMode() { editorVC.toggleDelimitedTableMode() }
    func toggleVerticalLayout() {
        if secondaryEditorVC != nil { closeEditorSplit() }
        editorVC.toggleVerticalLayout()
        refreshStatus()
    }

    func toggleColumnLayout() {
        if secondaryEditorVC != nil { closeEditorSplit() }
        editorVC.toggleColumnLayout()
        refreshStatus()
    }

    enum EditorSplitOrientation { case vertical, horizontal }

    func showEditorSplit(_ orientation: EditorSplitOrientation) {
        editorSplitView.isVertical = orientation == .vertical
        if secondaryEditorVC == nil {
            let secondary = EditorViewController()
            secondary.delegate = self
            secondary.reusesDocumentTextStorage = false
            _ = secondary.view
            secondary.document = curDoc
            secondary.applyPreferences(editorVC.appliedPreferences)
            secondary.onScroll = { [weak self] origin in
                guard let self, self.linkedEditorScrolling else { return }
                self.editorVC.setLinkedScrollOffset(origin)
            }
            editorVC.onScroll = { [weak self] origin in
                guard let self, self.linkedEditorScrolling else { return }
                self.secondaryEditorVC?.setLinkedScrollOffset(origin)
            }
            secondaryEditorVC = secondary
            editorSplitView.addSubview(secondary.view)
        }
        if diffTargetDocument == nil {
            // A read-only or view-mode document used to become editable in its
            // second pane, defeating all three read-only sources at once.
            secondaryEditorVC?.textView.isEditable = !(curDoc?.isEditingDisabled ?? false)
        }
        editorSplitView.adjustSubviews()
    }

    func closeEditorSplit() {
        secondaryEditorVC?.view.removeFromSuperview()
        secondaryEditorVC = nil
        editorVC.onScroll = nil
        diffTargetDocument = nil
        diffHunks = []
        currentDiffIndex = 0
        editorSplitView.adjustSubviews()
    }

    func toggleLinkedEditorScrolling() { linkedEditorScrolling.toggle() }
    private(set) var lastCrossDocumentScrollRequestForTesting: NSPoint?
    func applyCrossDocumentScroll(_ origin: NSPoint) {
        lastCrossDocumentScrollRequestForTesting = origin
        editorVC.setLinkedScrollOffset(origin)
    }
    var isEditorSplitForTesting: Bool { secondaryEditorVC != nil }
    var editorSplitIsVerticalForTesting: Bool { editorSplitView.isVertical }
    var isLinkedEditorScrollingForTesting: Bool { linkedEditorScrolling }
    var secondaryEditorForTesting: EditorViewController? { secondaryEditorVC }

    /// Documents in this window paired with the panes showing them.
    func agentTargets() -> [(document: Document, editor: EditorViewController)] {
        var targets: [(Document, EditorViewController)] = []
        for document in documentController.documents {
            // The primary pane always shows the current document; other
            // documents are represented by it too, since switching tabs is what
            // makes them visible.
            targets.append((document, editorVC))
        }
        if let secondary = secondaryEditorVC, let current = curDoc {
            targets.append((current, secondary))
        }
        return targets.map { (document: $0.0, editor: $0.1) }
    }

    func compareWithNextDocument() {
        guard documentController.documents.count > 1, let current = curDoc else { return }
        let nextIndex = (curIdx + 1) % documentController.documents.count
        guard let target = documentController.document(at: nextIndex), target !== current else { return }
        showEditorSplit(.vertical)
        diffTargetDocument = target
        secondaryEditorVC?.document = target
        secondaryEditorVC?.textView.isEditable = false
        currentDiffIndex = 0
        refreshDiffHunks()
        navigateDifference(delta: 0)
    }

    func nextDifference() { navigateDifference(delta: 1) }
    func previousDifference() { navigateDifference(delta: -1) }

    func mergeCurrentDifferenceFromRight() {
        guard diffHunks.indices.contains(currentDiffIndex) else { return }
        let hunk = diffHunks[currentDiffIndex]
        editorVC.batchReplace([hunk.originalRange], with: hunk.replacement)
        refreshDiffHunks()
    }

    private func refreshDiffHunks() {
        guard let current = curDoc, let target = diffTargetDocument else { return }
        diffHunks = TextDiffEngine.compare(current.content, target.content)
        currentDiffIndex = min(currentDiffIndex, max(0, diffHunks.count - 1))
    }

    private func navigateDifference(delta: Int) {
        guard !diffHunks.isEmpty else { return }
        currentDiffIndex = (currentDiffIndex + delta + diffHunks.count) % diffHunks.count
        let hunk = diffHunks[currentDiffIndex]
        let range = NSRange(location: hunk.originalRange.location, length: 0)
        editorVC.setSelections([range], primaryRange: range)
        editorVC.textView.scrollRangeToVisible(range)
        secondaryEditorVC?.goToLine(hunk.replacementStartLine + 1)
    }

    var diffHunkCountForTesting: Int { diffHunks.count }
    var currentDiffIndexForTesting: Int { currentDiffIndex }
    var isComparingDocumentsForTesting: Bool { diffTargetDocument != nil }

    func generateTagsFile() {
        let panel = NSOpenPanel()
        panel.title = AppLocalization.string("dialog.tags.generateTitle")
        panel.prompt = AppLocalization.string("common.generate")
        panel.message = AppLocalization.string("dialog.tags.generateExplanation")
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = curDoc?.fileURL?.deletingLastPathComponent()
        guard panel.runModal() == .OK, let root = panel.url else { return }
        do {
            let summary = try TagFileGenerator().generate(in: root)
            showLocalizedStatus("status.generatedTags", [summary.tagCount, summary.fileCount])
        } catch {
            let alert = NSAlert(error: error)
            alert.messageText = AppLocalization.string("dialog.tags.generateFailed")
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }

    func showTagJump() {
        let alert = NSAlert()
        alert.messageText = AppLocalization.string("dialog.tags.jumpTitle")
        alert.informativeText = AppLocalization.string("dialog.tags.jumpExplanation")
        let field = NSTextField(string: identifierAtCursor() ?? "")
        field.frame = NSRect(x: 0, y: 0, width: 280, height: 24)
        field.setAccessibilityLabel(AppLocalization.string("dialog.tags.nameAccessibility"))
        alert.accessoryView = field
        alert.addButton(withTitle: AppLocalization.string(.commonJump))
        alert.addButton(withTitle: AppLocalization.string(.commonCancel))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        jumpToTag(named: field.stringValue)
    }

    func directTagJump() {
        guard let name = identifierAtCursor(), !name.isEmpty else {
            showLocalizedStatus("status.noTagName")
            return
        }
        jumpToTag(named: name)
    }

    func jumpToTag(named name: String) {
        guard let sourceURL = curDoc?.fileURL,
              let (index, root) = loadNearestTagIndex(from: sourceURL.deletingLastPathComponent()),
              let destination = index.matches(named: name).first,
              let targetURL = TagIndex.fileURL(for: destination, relativeTo: root),
              FileManager.default.fileExists(atPath: targetURL.path) else {
            showLocalizedStatus("status.tagNotFound", [name])
            return
        }
        let origin = (sourceURL, editorVC.selectionSet.primaryRange.location)
        openFile(targetURL)
        guard let target = curDoc,
              let offset = TagIndex.utf16Offset(for: destination, in: target.content) else {
            showLocalizedStatus("status.tagLocationInvalid", [name])
            return
        }
        tagBackStack.append(origin)
        let range = NSRange(location: offset, length: 0)
        editorVC.setSelections([range], primaryRange: range)
        editorVC.textView.scrollRangeToVisible(range)
    }

    func backTagJump() {
        guard let destination = tagBackStack.popLast() else {
            showLocalizedStatus("status.tagBackStackEmpty")
            return
        }
        openFile(destination.url)
        let length = (curDoc?.content as NSString?)?.length ?? 0
        let range = NSRange(location: min(destination.offset, length), length: 0)
        editorVC.setSelections([range], primaryRange: range)
        editorVC.textView.scrollRangeToVisible(range)
    }

    private func identifierAtCursor() -> String? {
        let ns = editorVC.textView.string as NSString
        let selection = editorVC.selectionSet.primaryRange
        if selection.length > 0, NSMaxRange(selection) <= ns.length { return ns.substring(with: selection) }
        guard ns.length > 0 else { return nil }
        var start = min(selection.location, ns.length)
        var end = start
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_"))
        while start > 0, let scalar = UnicodeScalar(ns.character(at: start - 1)), allowed.contains(scalar) { start -= 1 }
        while end < ns.length, let scalar = UnicodeScalar(ns.character(at: end)), allowed.contains(scalar) { end += 1 }
        return start < end ? ns.substring(with: NSRange(location: start, length: end - start)) : nil
    }

    private func loadNearestTagIndex(from directory: URL) -> (TagIndex, URL)? {
        var candidate = directory.standardizedFileURL
        for _ in 0..<32 {
            let tagsURL = candidate.appendingPathComponent("tags")
            if let data = try? Data(contentsOf: tagsURL, options: .mappedIfSafe),
               data.count <= 32 * 1_024 * 1_024,
               let contents = String(data: data, encoding: .utf8) {
                return (TagIndex(contents: contents), candidate)
            }
            let parent = candidate.deletingLastPathComponent()
            if parent.path == candidate.path { break }
            candidate = parent
        }
        return nil
    }

    private func refreshMarkerResults() {
        guard let doc = curDoc else { return }
        sidebarVC.updateMarkerResults(doc.colorMarkers.markers, text: doc.content)
    }
    func toggleFold() { editorVC.toggleFoldAtCursor() }
    func toggleFoldMargin() { editorVC.toggleFoldMargin() }
    func copyCurrentWord() { editorVC.copyCurrentWord() }
    func cutCurrentWord() { editorVC.cutCurrentWord() }
    func deleteCurrentWord() { editorVC.deleteCurrentWord() }
    func copyCurrentLine() { editorVC.copyCurrentLine() }
    func cutCurrentLine() { editorVC.cutCurrentLine() }
    func cutToLineEnd() { editorVC.cutToLineEnd() }
    func clearUndoBuffer() { editorVC.clearUndoBuffer() }
    func beginPartialOutlineEditing() { _ = editorVC.beginPartialOutlineEditing() }
    func endPartialOutlineEditing() { editorVC.endPartialOutlineEditing() }
    func collapseAllFolds() { editorVC.collapseAllFolds() }
    func expandAllFolds() { editorVC.expandAllFolds() }

    func prepareUITestDocument(content: String, selections: [NSRange]) {
        guard let document = curDoc else { return }
        document.content = content
        document.cachedTextStorage = nil
        editorVC.reloadCurrentDocument()
        if !selections.isEmpty {
            editorVC.setSelections(selections, primaryRange: selections.first)
            editorVC.isMultiEditActive = selections.count > 1
        }
        editorVC.emitCursor()
    }

    // MARK: - Session persistence
    //
    // Backed by `SessionStore` (a JSON file under Application Support),
    // not UserDefaults — see ROADMAP.md M1-05. Window frame is
    // deliberately not part of this: AppKit's own
    // `setFrameAutosaveName("MainWindow")` (see `init`) already persists
    // and restores it.

    /// Debounced so normal typing/tab-switching doesn't write to disk on
    /// every keystroke, while a crash or force-quit still only loses at
    /// most a few seconds of session state — `applicationWillTerminate`
    /// (via `AppCoordinator`) still calls `saveSession()` directly for a
    /// final synchronous flush on a clean quit.
    private func scheduleSessionSave() {
        sessionSaveDebouncer.schedule { [weak self] in
            self?.saveSession()
        }
    }

    func saveSession() {
        sessionStore.save(currentSessionState())
    }

    private func currentSessionState() -> SessionState {
        saveCursorPosition()
        let openFiles: [OpenFileState] = documentController.documents.compactMap { doc in
            guard let path = doc.fileURL?.path else { return nil }
            return OpenFileState(
                path: path,
                cursorPosition: doc.cursorPosition,
                scrollOffsetX: doc.scrollOffset.x,
                scrollOffsetY: doc.scrollOffset.y,
                collapsedFoldIDs: doc.foldModel.collapsedRegionIDs.sorted()
            )
        }
        let activePath = curDoc?.fileURL?.path
        let savedActiveIndex = activePath.flatMap { path in
            openFiles.firstIndex(where: { $0.path == path })
        } ?? max(0, min(curIdx, max(0, openFiles.count - 1)))
        return SessionState(
            rootFolderPath: sidebarVC.rootFolderURL?.path,
            openFiles: openFiles,
            activeIndex: savedActiveIndex,
            windowZoomed: window?.isZoomed ?? false,
            sidebarCollapsed: sidebarManuallyCollapsed
        )
    }

    func restoreSession() {
        let state = sessionStore.load()
        let recoveredCount = restoreUnnamedDocumentRecovery()
        applySessionState(state, recoveredCount: recoveredCount)
    }

    private func applySessionState(_ state: SessionState, recoveredCount: Int = 0) {
        let existingFiles = state.openFiles.filter { FileManager.default.fileExists(atPath: $0.path) }

        // Recovery can have something to restore even when the normal
        // file-based session doesn't (e.g. a crash with only unnamed
        // Untitled tabs open, which the session never tracked) — checked
        // independently rather than folded into the guard below.
        guard state.rootFolderPath != nil || !existingFiles.isEmpty || recoveredCount > 0 else { return }

        if let fp = state.rootFolderPath, FileManager.default.fileExists(atPath: fp) {
            openFolderDirect(URL(fileURLWithPath: fp))
        }

        for fileState in existingFiles {
            openFile(URL(fileURLWithPath: fileState.path))
        }

        documentController.pruneLeftoverBlankDocument()

        for fileState in existingFiles {
            guard let doc = documentController.documents.first(where: { $0.fileURL?.path == fileState.path }) else { continue }
            doc.cursorPosition = fileState.cursorPosition
            doc.scrollOffset = NSPoint(x: fileState.scrollOffsetX, y: fileState.scrollOffsetY)
            let outline = OutlineModel(
                text: doc.content, language: doc.language,
                customRules: doc.fileTypeProfile?.settings.outlineRules ?? [])
            doc.foldModel = FoldModel(
                text: doc.content, symbols: outline.symbols,
                collapsedRegionIDs: Set(fileState.collapsedFoldIDs ?? []))
        }

        if state.openFiles.indices.contains(state.activeIndex),
           let activeDocumentIndex = documentController.documents.firstIndex(where: {
               $0.fileURL?.path == state.openFiles[state.activeIndex].path
           }) {
            documentController.selectDocument(at: activeDocumentIndex)
        } else {
            documentController.selectDocumentClamped(to: state.activeIndex)
        }
        if let doc = curDoc {
            editorVC.document = doc
            editorVC.reloadCurrentDocument()
        }
        refreshTabs()
        refreshStatus()
        if let name = curDoc?.localizedDisplayName {
            window?.title = AppLocalization.string("window.document.title", [name])
        }

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.restoreCursorPosition()
            if let url = self.curDoc?.fileURL {
                self.sidebarVC.revealFile(url)
            }
            if state.windowZoomed, !(self.window?.isZoomed ?? true) {
                self.window?.zoom(nil)
            }
            // Applied last, after showSidebarAndOpen's own async
            // repositioning (scheduled above via openFolderDirect), so a
            // saved "collapsed" state wins even when a folder was also
            // restored.
            if state.sidebarCollapsed {
                self.sidebarManuallyCollapsed = true
                self.splitView.setPosition(0, ofDividerAt: 0)
                self.sidebarVC.view.isHidden = true
                self.updateTabBarFrame()
            }
        }
    }

    func saveWorkspaceAs() {
        guard let window else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Workspace.\(WorkspaceFile.pathExtension)"
        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .OK, var url = panel.url else { return }
            if url.pathExtension.lowercased() != WorkspaceFile.pathExtension {
                url.appendPathExtension(WorkspaceFile.pathExtension)
            }
            do {
                try WorkspaceFile.save(self.currentSessionState(), to: url)
                RecentItems.addWorkspace(url)
                self.showLocalizedStatus("status.workspaceSaved")
            } catch { NSAlert(error: error).beginSheetModal(for: window) }
        }
    }

    func openWorkspace() {
        guard let window else { return }
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.openWorkspace(url)
        }
    }

    func openWorkspace(_ url: URL) {
        do {
            let state = try WorkspaceFile.load(from: url)
            applySessionState(state)
            RecentItems.addWorkspace(url)
            showLocalizedStatus("status.workspaceRestored")
        } catch { NSAlert(error: error).runModal() }
    }

    func showProjectHistory() {
        let folders = RecentItems.folders
        guard !folders.isEmpty else { showLocalizedStatus("status.projectHistoryEmpty"); return }
        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 420, height: 26))
        popup.addItems(withTitles: folders.map(\.path))
        let alert = NSAlert()
        alert.messageText = AppLocalization.string("dialog.projectHistory.title")
        alert.informativeText = AppLocalization.string("dialog.projectHistory.explanation")
        alert.accessoryView = popup
        alert.addButton(withTitle: AppLocalization.string(.commonOpen))
        alert.addButton(withTitle: AppLocalization.string(.commonCancel))
        guard alert.runModal() == .alertFirstButtonReturn,
              folders.indices.contains(popup.indexOfSelectedItem) else { return }
        openFolderDirect(folders[popup.indexOfSelectedItem])
    }

    func showWorkspaceHistory() {
        let workspaces = RecentItems.workspaces
        guard !workspaces.isEmpty else { showLocalizedStatus("status.workspaceHistoryEmpty"); return }
        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 420, height: 26))
        popup.addItems(withTitles: workspaces.map(\.lastPathComponent))
        let alert = NSAlert()
        alert.messageText = AppLocalization.string("dialog.workspaceHistory.title")
        alert.informativeText = AppLocalization.string("dialog.workspaceHistory.explanation")
        alert.accessoryView = popup
        alert.addButton(withTitle: AppLocalization.string(.commonRestore))
        alert.addButton(withTitle: AppLocalization.string(.commonCancel))
        guard alert.runModal() == .alertFirstButtonReturn,
              workspaces.indices.contains(popup.indexOfSelectedItem) else { return }
        openWorkspace(workspaces[popup.indexOfSelectedItem])
    }

    // MARK: - Autosave and crash recovery (M2-07)
    //
    // Scoped to unnamed documents only — a document with a real file
    // already has one on save, and extending this to named documents'
    // *unsaved* edits is a reasonable future enhancement but not what
    // this task's checklist asks for ("Give each unnamed document a
    // stable Recovery ID").

    /// Debounced so normal typing doesn't write to disk on every
    /// keystroke. Never persists empty content — an empty Untitled tab
    /// has nothing worth recovering, and `Document.recovered(from:)`
    /// relies on every real record being non-empty to reliably mark the
    /// restored document as modified.
    private func scheduleRecoverySaveIfUnnamed(_ doc: Document) {
        guard doc.fileURL == nil, !doc.content.isEmpty else { return }
        recoverySaveDebouncer.schedule { [weak self, weak doc] in
            guard let doc = doc else { return }
            self?.recoveryStore.save(RecoveryRecord(
                recoveryID: doc.recoveryID,
                content: doc.content,
                encoding: doc.encoding,
                selectionLocation: doc.cursorPosition,
                selectionLength: 0
            ))
        }
    }

    /// Restores every recovery record found on disk as a new unsaved tab.
    /// Returns how many were restored.
    @discardableResult
    private func restoreUnnamedDocumentRecovery() -> Int {
        let records = recoveryStore.loadAll()
        for record in records {
            documentController.addRecoveredDocument(.recovered(from: record))
        }
        return records.count
    }

    /// ROADMAP.md M2-07: "Add a command to clear recovery data." Only
    /// removes saved snapshots on disk — does not touch any currently
    /// open document, which will simply write a fresh one on its next
    /// debounced autosave if it's still unnamed and modified.
    func clearRecoveryData() {
        let a = NSAlert()
        a.alertStyle = .informational
        a.messageText = AppLocalization.string("dialog.recovery.clearTitle")
        a.informativeText = AppLocalization.string("dialog.recovery.clearExplanation")
        a.addButton(withTitle: AppLocalization.string(.commonClear))
        a.addButton(withTitle: AppLocalization.string(.commonCancel))
        guard a.runModal() == .alertFirstButtonReturn else { return }
        recoveryStore.clearAll()
    }
}

@MainActor
private final class StatusFontSizePopoverController: NSViewController {
    var onChange: ((CGFloat) -> Void)?
    var onReset: (() -> Void)?
    private let initialSize: CGFloat
    private let valueLabel = NSTextField(labelWithString: "")

    init(size: CGFloat) {
        initialSize = size
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 270, height: 82))
        let slider = NSSlider(value: Double(initialSize), minValue: 8, maxValue: 72,
                              target: self, action: #selector(changed(_:)))
        slider.frame = NSRect(x: 16, y: 42, width: 190, height: 24)
        slider.numberOfTickMarks = 17
        slider.allowsTickMarkValuesOnly = false
        slider.setAccessibilityLabel(AppLocalization.string("status.accessibility.fontSize"))
        valueLabel.frame = NSRect(x: 212, y: 44, width: 46, height: 20)
        valueLabel.alignment = .right
        updateLabel(initialSize)
        let reset = NSButton(title: AppLocalization.string(.commonReset), target: self, action: #selector(resetSize))
        reset.bezelStyle = .rounded
        reset.frame = NSRect(x: 16, y: 10, width: 76, height: 26)
        reset.setAccessibilityLabel(AppLocalization.string("dialog.fontSize.resetAccessibility"))
        root.addSubview(slider); root.addSubview(valueLabel); root.addSubview(reset)
        view = root
    }

    @objc private func changed(_ sender: NSSlider) {
        let value = CGFloat(sender.doubleValue.rounded())
        updateLabel(value); onChange?(value)
    }

    @objc private func resetSize() {
        updateLabel(initialSize); onReset?()
    }

    private func updateLabel(_ size: CGFloat) {
        valueLabel.stringValue = "\(Int(size.rounded())) pt"
    }
}

extension MainWindowController: NSSplitViewDelegate {}
