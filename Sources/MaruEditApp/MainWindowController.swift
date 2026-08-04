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
    private let recoveryStore = RecoveryStore()
    private let recoverySaveDebouncer = Debouncer(delay: 1.5)
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
        NotificationCenter.default.addObserver(
            self, selector: #selector(windowDidBecomeKey),
            name: NSWindow.didBecomeKeyNotification, object: w
        )
    }

    deinit {
        if let monitor = keyMonitor { NSEvent.removeMonitor(monitor) }
        NotificationCenter.default.removeObserver(self)
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
        guard doc.fileURL != nil else { saveDocumentAs(); return }
        // Checked before the mixed-line-ending prompt: no point asking the
        // user to pick LF/CRLF/CR for a write that can't happen anyway
        // (ROADMAP.md M2-08, "never presented as normally overwriteable").
        if doc.isReadOnly {
            presentReadOnlySaveBlocked(doc)
            return
        }
        guard resolveMixedLineEndingIfNeeded(for: doc) else { return }
        performSave(doc)
    }

    /// ROADMAP.md M2-08: intercepts Save on a read-only file before any
    /// write is attempted. `TextFileSaver` would fail on its own too (the
    /// OS denies the write), but surfacing this up front — with a "Save
    /// As…" escape hatch — is friendlier than a bare I/O error after the
    /// fact.
    private func presentReadOnlySaveBlocked(_ doc: Document) {
        let a = NSAlert()
        a.alertStyle = .warning
        a.messageText = "\(doc.displayName) Is Read-Only"
        a.informativeText = "This file can't be overwritten because it's read-only on disk. Use Save As to save your changes to a new location."
        a.addButton(withTitle: "Save As…")
        a.addButton(withTitle: "Cancel")
        if a.runModal() == .alertFirstButtonReturn {
            saveDocumentAs()
        }
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
    private func performSave(_ doc: Document) {
        // Revalidate before writing: an external editor's changes must
        // never be silently overwritten (ROADMAP.md M2-06 acceptance).
        // Scoped to same-file Save only — Save As already gets its own
        // protection from NSSavePanel's native overwrite confirmation
        // (M2-05), and doc's known baseline describes the *old* path, not
        // whatever new location the user might pick there.
        if let url = doc.fileURL {
            let status = ExternalChangeDetector.check(url: url, knownIdentity: doc.fileIdentity, knownModificationDate: doc.lastKnownModificationDate)
            if status == .modified {
                presentExternalChangeConflict(status, for: doc)
                return
            }
        }
        do {
            try doc.save()
            refreshTabs(); refreshStatus()
        } catch let DocumentSaveError.unrepresentable(encoding, characters) {
            offerUTF8Conversion(for: doc, encoding: encoding, characters: characters) { [weak self] in
                self?.performSave(doc)
            }
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    private func performSaveAs(_ doc: Document, to url: URL) {
        let wasUnnamed = doc.fileURL == nil
        do {
            try doc.save(to: url)
            refreshTabs(); refreshStatus()
            window?.title = "MaruEdit — \(doc.displayName)"
            RecentItems.addFile(url)
            if wasUnnamed {
                // This document now has a real file, which is its own
                // recovery mechanism from here on — the crash-recovery
                // record for its unnamed life is no longer needed.
                recoveryStore.delete(doc.recoveryID)
            }
        } catch let DocumentSaveError.unrepresentable(encoding, characters) {
            offerUTF8Conversion(for: doc, encoding: encoding, characters: characters) { [weak self] in
                self?.performSaveAs(doc, to: url)
            }
        } catch {
            NSAlert(error: error).runModal()
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
        a.messageText = "Cannot Save in \(encoding.displayName)"
        let shown = characters.prefix(5)
            .map { "Line \($0.line), Col \($0.column): \u{201C}\($0.character)\u{201D}" }
            .joined(separator: "\n")
        let remainder = characters.count > 5 ? "\n…and \(characters.count - 5) more" : ""
        a.informativeText = characters.isEmpty
            ? "This document contains characters that cannot be represented in \(encoding.displayName)."
            : "\(characters.count) character\(characters.count == 1 ? "" : "s") cannot be represented in \(encoding.displayName):\n\n\(shown)\(remainder)"
        a.addButton(withTitle: "Save as UTF-8")
        a.addButton(withTitle: "Cancel")
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
        a.messageText = "Mixed Line Endings"
        a.informativeText = "\(doc.displayName) mixes line-ending styles (LF, CRLF, CR). Choose one to use consistently when saving."
        a.addButton(withTitle: "LF (Unix)")
        a.addButton(withTitle: "CRLF (Windows)")
        a.addButton(withTitle: "CR (Classic Mac)")
        a.addButton(withTitle: "Cancel")
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
            a.messageText = "\(doc.displayName) Can't Be Found"
            a.informativeText = "The file at its original location has been deleted or moved. Your content here is unaffected — use Save As to write it somewhere."
            a.addButton(withTitle: "OK")
            a.runModal()

        case .modified:
            let a = NSAlert()
            a.alertStyle = .warning
            a.messageText = "\(doc.displayName) Changed on Disk"
            if doc.isModified {
                a.informativeText = "This file has unsaved changes here and has also been modified outside MaruEdit. Reloading will discard your changes here."
                a.addButton(withTitle: "Reload from Disk")
                a.addButton(withTitle: "Save As…")
                a.addButton(withTitle: "Cancel")
                switch a.runModal() {
                case .alertFirstButtonReturn: reloadFromDisk(doc)
                case .alertSecondButtonReturn: saveDocumentAs()
                default: break
                }
            } else {
                a.informativeText = "This file has been modified outside MaruEdit."
                a.addButton(withTitle: "Reload from Disk")
                a.addButton(withTitle: "Cancel")
                if a.runModal() == .alertFirstButtonReturn {
                    reloadFromDisk(doc)
                }
            }
        }
    }

    private func reloadFromDisk(_ doc: Document) {
        do {
            try doc.reopen(forcing: doc.encoding)
            editorVC.reloadCurrentDocument()
            refreshTabs(); refreshStatus()
        } catch {
            NSAlert(error: error).runModal()
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
            statusBar.updateLineEnding(doc.lineEnding)
            statusBar.updateReadOnly(doc.isReadOnly)
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
            scheduleRecoverySaveIfUnnamed(doc)
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
        let recoveredCount = restoreUnnamedDocumentRecovery()

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
        a.messageText = "Clear Recovery Data?"
        a.informativeText = "This removes saved recovery snapshots for unsaved, unnamed documents from previous crashes or forced quits. Currently open documents are not affected."
        a.addButton(withTitle: "Clear")
        a.addButton(withTitle: "Cancel")
        guard a.runModal() == .alertFirstButtonReturn else { return }
        recoveryStore.clearAll()
    }
}
