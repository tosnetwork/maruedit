import AppKit
import MaruEditCore

final class MainWindowController: NSWindowController,
    NSSplitViewDelegate,
    EditorViewControllerDelegate,
    TabBarViewDelegate,
    SidebarDelegate,
    FindBarDelegate,
    QuickOpenDelegate,
    StatusBarViewDelegate
{
    private var splitView: NSSplitView!
    private var sidebarVC: SidebarViewController!
    private var tabBar: TabBarView!
    private var findBar: FindBarView!
    private var editorVC: EditorViewController!
    private var statusBar: StatusBarView!

    private var quickOpen: QuickOpenPanel?
    private var keyMonitor: Any?

    private let documentController = DocumentController()
    private let sessionStore = SessionStore()
    private let sessionSaveDebouncer = Debouncer(delay: 1.5)
    private var sidebarManuallyCollapsed = false

    /// Convenience shims onto `documentController` so the UI-orchestration
    /// code below (largely unchanged from before the M1-02 extraction)
    /// doesn't need to spell out `documentController.` at every call site.
    private var curIdx: Int { documentController.currentIndex }
    private var curDoc: Document? { documentController.currentDocument }

    convenience init() {
        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1100, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false
        )
        w.minSize = NSSize(width: 640, height: 420)
        w.title = "MaruEdit"
        w.isReleasedWhenClosed = false
        if !w.setFrameUsingName("MainWindow") { w.center() }
        w.setFrameAutosaveName("MainWindow")
        w.backgroundColor = Theme.background

        self.init(window: w)
        buildUI()
        newDocument()
        installKeyMonitor()
    }

    deinit {
        if let monitor = keyMonitor { NSEvent.removeMonitor(monitor) }
    }

    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if flags == .command, event.charactersIgnoringModifiers == "p" {
                self.showQuickOpen()
                return nil
            }
            return event
        }
    }

    // MARK: - UI setup
    // Tab bar and status bar are OUTSIDE the NSSplitView (direct children of contentView).
    // This avoids NSSplitView layer compositing issues that made the tab bar invisible.

    private func buildUI() {
        guard let cv = window?.contentView else { return }

        let tabH: CGFloat = 32
        let statusH: CGFloat = 24

        tabBar = TabBarView()
        tabBar.delegate = self
        tabBar.autoresizingMask = [.minYMargin]
        tabBar.frame = NSRect(x: 0, y: cv.bounds.height - tabH, width: cv.bounds.width, height: tabH)
        cv.addSubview(tabBar)

        statusBar = StatusBarView()
        statusBar.delegate = self
        statusBar.autoresizingMask = [.width, .maxYMargin]
        statusBar.frame = NSRect(x: 0, y: 0, width: cv.bounds.width, height: statusH)
        cv.addSubview(statusBar)

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
        let editorView = editorVC.view
        editorView.setFrameSize(NSSize(width: splitView.bounds.width - 221, height: splitView.bounds.height))

        splitView.addSubview(sideView)
        splitView.addSubview(editorView)
        splitView.setHoldingPriority(.defaultHigh, forSubviewAt: 0)
        splitView.setHoldingPriority(.defaultLow, forSubviewAt: 1)

        updateTabBarFrame()

        DispatchQueue.main.async { [weak self] in
            self?.splitView.setPosition(220, ofDividerAt: 0)
        }
    }

    private func updateTabBarFrame() {
        guard let cv = window?.contentView else { return }
        let tabH: CGFloat = 32
        let editorX: CGFloat
        if sidebarVC.view.isHidden {
            editorX = 0
        } else {
            editorX = sidebarVC.view.frame.width + splitView.dividerThickness
        }
        tabBar.frame = NSRect(
            x: editorX,
            y: cv.bounds.height - tabH,
            width: cv.bounds.width - editorX,
            height: tabH
        )
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

    func newDocument() {
        let doc = documentController.newDocument()
        editorVC.document = doc
        refreshTabs()
        refreshStatus()
        scheduleSessionSave()
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

    func openFile(_ url: URL) {
        saveCursorPosition()
        do {
            let result = try documentController.open(url: url)
            editorVC.document = result.document
            refreshTabs(); refreshStatus()
            if !result.wasAlreadyOpen {
                window?.title = "MaruEdit — \(result.document.displayName)"
            }
            RecentItems.addFile(url)
            sidebarVC.revealFile(url)
            if result.wasAlreadyOpen {
                deferredRestoreCursor()
            }
            scheduleSessionSave()
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    private func openFileInCurrentTab(_ url: URL) {
        saveCursorPosition()
        do {
            let result = try documentController.openInCurrentTab(url: url)
            editorVC.document = result.document
            refreshTabs(); refreshStatus()
            window?.title = "MaruEdit — \(result.document.displayName)"
            RecentItems.addFile(url)
            sidebarVC.revealFile(url)
            if result.wasAlreadyOpen {
                deferredRestoreCursor()
            }
            scheduleSessionSave()
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    func saveDocument() {
        guard let doc = curDoc else { return }
        if doc.fileURL != nil {
            do { try doc.save(); refreshTabs() } catch { NSAlert(error: error).runModal() }
        } else { saveDocumentAs() }
    }

    func saveDocumentAs() {
        guard let doc = curDoc else { return }
        let p = NSSavePanel()
        p.canCreateDirectories = true
        p.beginSheetModal(for: window!) { [weak self] r in
            guard r == .OK, let url = p.url else { return }
            do {
                try doc.save(to: url)
                self?.refreshTabs(); self?.refreshStatus()
                self?.window?.title = "MaruEdit — \(doc.displayName)"
                RecentItems.addFile(url)
            } catch { NSAlert(error: error).runModal() }
        }
    }

    func closeCurrentTab() {
        guard let doc = curDoc else { return }
        let indexToClose = curIdx
        if doc.isModified {
            let a = NSAlert()
            a.messageText = "Save changes to \(doc.displayName)?"
            a.informativeText = "Your changes will be lost if you don't save them."
            a.addButton(withTitle: "Save")
            a.addButton(withTitle: "Don't Save")
            a.addButton(withTitle: "Cancel")
            let resp = a.runModal()
            if resp == .alertFirstButtonReturn { saveDocument() }
            else if resp == .alertThirdButtonReturn { return }
        }
        let emptiedAndReplaced = documentController.closeDocument(at: indexToClose)
        editorVC.document = curDoc
        refreshTabs(); refreshStatus()
        scheduleSessionSave()
        if emptiedAndReplaced { return }
        deferredRestoreCursor()
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
        updateTabBarFrame()
        scheduleSessionSave()
    }

    func showFind() {
        guard let cv = window?.contentView else { return }
        let tabH: CGFloat = 32
        let findH: CGFloat = 34
        let statusH: CGFloat = 24
        findBar.isHidden = false
        findBar.frame = NSRect(x: 0, y: cv.bounds.height - tabH - findH, width: cv.bounds.width, height: findH)
        splitView.frame = NSRect(x: 0, y: statusH, width: cv.bounds.width, height: cv.bounds.height - tabH - findH - statusH)
        findBar.activate()
    }

    func showGoToLine() {
        let a = NSAlert()
        a.messageText = "Go to Line"
        a.addButton(withTitle: "Go")
        a.addButton(withTitle: "Cancel")
        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        input.placeholderString = "Line number"
        a.accessoryView = input
        a.beginSheetModal(for: window!) { [weak self] r in
            guard r == .alertFirstButtonReturn, let ln = Int(input.stringValue) else { return }
            self?.editorVC.goToLine(ln)
        }
    }

    func showQuickOpen() {
        guard let w = window else { return }
        guard let rootURL = sidebarVC.rootFolderURL else {
            let a = NSAlert()
            a.messageText = "No Folder Open"
            a.informativeText = "Open a folder first (Cmd+Shift+O) to use Quick Open."
            a.addButton(withTitle: "OK")
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
        let items = documentController.documents.map { TabItem(title: $0.displayName, isModified: $0.isModified) }
        tabBar.setTabs(items, selectedIndex: curIdx)
    }

    private func refreshStatus() {
        if let doc = curDoc {
            statusBar.updateLanguage(doc.language)
            statusBar.updateEncoding(doc.encoding)
        }
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
        let recent = RecentEncodings.encodings
        if !recent.isEmpty {
            let header = NSMenuItem(title: "Recent", action: nil, keyEquivalent: "")
            header.isEnabled = false
            menu.addItem(header)
            for encoding in recent {
                menu.addItem(encodingMenuItem(for: encoding))
            }
            menu.addItem(.separator())
        }
        for encoding in TextEncoding.userSelectable {
            menu.addItem(encodingMenuItem(for: encoding))
        }
        return menu
    }

    private func encodingMenuItem(for encoding: TextEncoding) -> NSMenuItem {
        let mi = NSMenuItem(title: encoding.displayName, action: #selector(didSelectEncodingMenuItem(_:)), keyEquivalent: "")
        mi.target = self
        mi.representedObject = encoding
        mi.state = (curDoc?.encoding == encoding) ? .on : .off
        return mi
    }

    @objc private func didSelectEncodingMenuItem(_ sender: NSMenuItem) {
        guard let encoding = sender.representedObject as? TextEncoding else { return }
        reopenCurrentDocument(with: encoding)
    }

    func statusBar(_ statusBar: StatusBarView, didClickEncodingAt point: NSPoint) {
        guard curDoc?.fileURL != nil else { return } // nothing to reopen for an unsaved document
        buildEncodingMenu().popUp(positioning: nil, at: point, in: statusBar)
    }

    /// Re-reads the current document's file with `encoding`, resolving
    /// unsaved changes first (ROADMAP.md M2-02 acceptance: never silently
    /// lose unsaved edits).
    func reopenCurrentDocument(with encoding: TextEncoding) {
        guard let doc = curDoc, doc.fileURL != nil else { return }

        if doc.isModified {
            let a = NSAlert()
            a.messageText = "Save changes to \(doc.displayName) before reopening?"
            a.informativeText = "Reopening with a different encoding will discard unsaved changes unless you save first."
            a.addButton(withTitle: "Save")
            a.addButton(withTitle: "Don't Save")
            a.addButton(withTitle: "Cancel")
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

    func splitView(_ sv: NSSplitView, constrainMinCoordinate pos: CGFloat, ofSubviewAt idx: Int) -> CGFloat {
        idx == 0 ? 150 : pos
    }

    func splitView(_ sv: NSSplitView, constrainMaxCoordinate pos: CGFloat, ofSubviewAt idx: Int) -> CGFloat {
        idx == 0 ? sv.bounds.width - 400 : pos
    }

    func splitView(_ sv: NSSplitView, canCollapseSubview subview: NSView) -> Bool {
        subview === sidebarVC.view && sidebarManuallyCollapsed
    }

    func splitView(_ sv: NSSplitView, shouldCollapseSubview subview: NSView, forDoubleClickOnDividerAt dividerIndex: Int) -> Bool {
        if subview === sidebarVC.view {
            sidebarManuallyCollapsed = true
            return true
        }
        return false
    }

    func splitViewDidResizeSubviews(_ notification: Notification) {
        updateTabBarFrame()
    }

    // MARK: - EditorViewControllerDelegate

    func editorTextDidChange(_ vc: EditorViewController) {
        if let doc = curDoc {
            tabBar.updateTab(at: curIdx, item: TabItem(title: doc.displayName, isModified: doc.isModified))
        }
        scheduleSessionSave()
    }
    func editorCursorMoved(_ vc: EditorViewController, line: Int, col: Int) { statusBar.updateCursor(line: line, col: col) }

    // MARK: - TabBarViewDelegate

    func tabBarDidSelectTab(at index: Int) {
        guard let doc = documentController.document(at: index) else { return }
        saveCursorPosition()
        documentController.selectDocument(at: index)
        editorVC.document = doc
        tabBar.selectTab(at: index)
        refreshStatus()
        window?.title = "MaruEdit — \(doc.displayName)"
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

    // MARK: - SidebarDelegate

    func sidebarDidSelectFile(_ url: URL, inNewTab: Bool) {
        if inNewTab {
            openFile(url)
        } else {
            openFileInCurrentTab(url)
        }
    }

    // MARK: - FindBarDelegate

    func findBarNext(_ text: String, caseSensitive: Bool, regex: Bool) {
        _ = editorVC.findNext(text, caseSensitive: caseSensitive, regex: regex)
    }
    func findBarPrev(_ text: String, caseSensitive: Bool) {
        _ = editorVC.findPrev(text, caseSensitive: caseSensitive)
    }
    func findBarReplace(_ search: String, with replacement: String, caseSensitive: Bool) {
        _ = editorVC.replaceCurrent(search, with: replacement, caseSensitive: caseSensitive)
    }
    func findBarReplaceAll(_ search: String, with replacement: String, caseSensitive: Bool) {
        _ = editorVC.replaceAll(search, with: replacement, caseSensitive: caseSensitive)
    }
    func findBarDismissed() {
        guard let cv = window?.contentView else { return }
        let tabH: CGFloat = 32
        let statusH: CGFloat = 24
        findBar.isHidden = true
        findBar.frame.size.height = 0
        splitView.frame = NSRect(x: 0, y: statusH, width: cv.bounds.width, height: cv.bounds.height - tabH - statusH)
        window?.makeFirstResponder(editorVC.textView)
    }
    func findBarMatchCount(_ text: String, caseSensitive: Bool) -> Int {
        editorVC.matchCount(text, caseSensitive: caseSensitive)
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
        saveCursorPosition()
        let openFiles: [OpenFileState] = documentController.documents.compactMap { doc in
            guard let path = doc.fileURL?.path else { return nil }
            return OpenFileState(
                path: path,
                cursorPosition: doc.cursorPosition,
                scrollOffsetX: doc.scrollOffset.x,
                scrollOffsetY: doc.scrollOffset.y
            )
        }
        let state = SessionState(
            rootFolderPath: sidebarVC.rootFolderURL?.path,
            openFiles: openFiles,
            activeIndex: curIdx,
            windowZoomed: window?.isZoomed ?? false,
            sidebarCollapsed: sidebarManuallyCollapsed
        )
        sessionStore.save(state)
    }

    func restoreSession() {
        let state = sessionStore.load()
        let existingFiles = state.openFiles.filter { FileManager.default.fileExists(atPath: $0.path) }

        guard state.rootFolderPath != nil || !existingFiles.isEmpty else { return }

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
        }

        documentController.selectDocumentClamped(to: state.activeIndex)
        if let doc = curDoc {
            editorVC.document = doc
        }
        refreshTabs()
        refreshStatus()
        if let name = curDoc?.displayName {
            window?.title = "MaruEdit — \(name)"
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
}
