import AppKit
import MaruEditCore
import os.log

@MainActor
protocol EditorViewControllerDelegate: AnyObject {
    func editorTextDidChange(_ vc: EditorViewController)
    func editorCursorMoved(_ vc: EditorViewController, state: EditorCursorState)
    func editorDidChooseFont(_ vc: EditorViewController, font: NSFont)
}

extension EditorViewControllerDelegate {
    func editorDidChooseFont(_ vc: EditorViewController, font: NSFont) {}
}

private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

final class EditorViewController: NSViewController, NSTextViewDelegate, NSLayoutManagerDelegate {
    static let inputLatencyLog = OSLog(subsystem: "com.maruedit.editor", category: "InputLatency")
    weak var delegate: EditorViewControllerDelegate?

    private(set) var scrollView: NSScrollView!
    private(set) var textView: NSTextView!
    private var lineNumbers: LineNumberView?
    private let syntaxHighlightCoordinator = SyntaxHighlightCoordinator()

    private var suppressTextChange = false
    private var suppressAutoIndent = false
    private var isApplyingSelectionSet = false
    private var markedTextSnapshot: (text: String, ranges: [NSRange], primary: NSRange)?
    private var isCompositionCommitScheduled = false
    var inputLatencySignpostID: OSSignpostID?
    var lineIndex = LineIndex()
    private var preferences = Preferences.defaults
    private(set) var isHighContrast = false
    var appliedPreferences: Preferences { preferences }
    var areLineNumbersHidden: Bool { lineNumbers?.isHidden ?? false }
    private var preferredEditorFont: NSFont {
        preferences.fontName == "SF Mono"
            ? NSFont.monospacedSystemFont(ofSize: preferences.fontSize, weight: .regular)
            : (NSFont(name: preferences.fontName, size: preferences.fontSize)
                ?? NSFont.monospacedSystemFont(ofSize: preferences.fontSize, weight: .regular))
    }
    var currentEditorFont: NSFont { preferredEditorFont }
    private var editorForeground: NSColor { isHighContrast ? .white : Theme.foreground }

    /// Multi-cursor ("select all occurrences") edit-mode state. Owned by
    /// this instance — not a global dictionary keyed by identity, per
    /// ROADMAP.md M1-06 — so two editors (e.g. in two windows, once
    /// multi-window support exists) can never see or affect each other's
    /// multi-edit state, and this state is freed automatically when the
    /// editor is deallocated instead of leaking in a module-level map.
    var isMultiEditActive = false
    let selectionSet = SelectionSet()
    var selectionHistory: [[NSRange]] = []
    var columnSelectionRows: [BoxSelectionRow]?
    private var columnSelectionAnchor: TextCoordinate?

    /// Compatibility access for the M1 prototype. M4-02/M4-03 remove the
    /// remaining direct uses as commands and editing move to SelectionSet.
    var multiEditCursorRanges: [NSRange] {
        get { selectionSet.ranges }
        set { setSelections(newValue) }
    }

    func setSelections(_ ranges: [NSRange], primaryRange: NSRange? = nil) {
        selectionSet.update(ranges: ranges, primaryRange: primaryRange)
        guard isViewLoaded else { return }
        var ordered = selectionSet.ranges
        let primary = ordered.remove(at: selectionSet.primaryIndex)
        ordered.insert(primary, at: 0)
        let values = ordered.map(NSValue.init(range:))
        if textView.selectedRanges != values {
            isApplyingSelectionSet = true
            textView.setSelectedRanges(values, affinity: .downstream, stillSelecting: false)
            isApplyingSelectionSet = false
        }
    }

    func beginColumnSelection(atUTF16Offset offset: Int) {
        let coordinate = BoxSelectionModel.coordinate(atUTF16Offset: offset, in: textView.string)
        columnSelectionAnchor = coordinate
        updateColumnSelection(toUTF16Offset: offset)
    }

    func updateColumnSelection(toUTF16Offset offset: Int) {
        guard let anchor = columnSelectionAnchor else { return }
        let current = BoxSelectionModel.coordinate(atUTF16Offset: offset, in: textView.string)
        let rows = BoxSelectionModel.rows(in: textView.string, anchor: anchor, current: current)
        columnSelectionRows = rows
        let ranges = rows.map(\.range)
        setSelections(ranges, primaryRange: ranges.first)
        isMultiEditActive = ranges.count > 1
    }

    func endColumnSelection() { columnSelectionAnchor = nil }

    func beginColumnSelectionCommand() {
        beginColumnSelection(atUTF16Offset: selectionSet.primaryRange.location)
    }

    func cancelColumnSelection() {
        columnSelectionAnchor = nil
        columnSelectionRows = nil
    }

    func copiedColumnText() -> String? {
        guard let rows = columnSelectionRows else { return nil }
        let ns = textView.string as NSString
        return rows.map { ns.substring(with: $0.range) }.joined(separator: "\n")
    }

    func insertIntoColumnSelection(_ fragments: [String]) {
        guard let rows = columnSelectionRows, !rows.isEmpty else { return }
        let mapped: [String]
        if fragments.count == rows.count { mapped = fragments }
        else if fragments.count == 1 { mapped = Array(repeating: fragments[0], count: rows.count) }
        else { mapped = Array(repeating: fragments.joined(separator: "\n"), count: rows.count) }
        let replacements = zip(rows, mapped).map { row, fragment in
            String(repeating: " ", count: row.leadingVirtualSpaces) + fragment
        }
        batchReplace(rows.map(\.range), with: replacements)
        columnSelectionRows = nil
    }

    /// Where incremental Find restarts from on each keystroke — captured
    /// when the Find Bar opens, so typing a longer pattern refines the
    /// match at one place in the document instead of walking forward
    /// through it (ROADMAP.md M3-02, "Support incremental search").
    var incrementalSearchAnchor: Int?

    /// The selection that existed when the Find Bar was opened, when it
    /// spanned text. Replace All treats it as "replace inside this"
    /// (ROADMAP.md M3-03, "Support selection scope"); the selection at the
    /// moment the button is pressed can't serve that role, since by then
    /// it is usually just the current match.
    var searchScopeSelection: NSRange?

    /// Rehighlights the whole document (or just the viewport for large
    /// ones). Used after a bulk edit such as Replace All, where per-line
    /// rehighlighting can't describe what changed.
    func rehighlightEntireDocument() {
        rehighlightAll()
    }

    /// Reapplies palette attributes without touching the backing string.
    /// M5-08 can call this after switching themes.
    func refreshSyntaxTheme() {
        rehighlightAll()
    }

    var document: Document? {
        didSet {
            guard document !== oldValue else { return }
            isMultiEditActive = false
            if isViewLoaded { loadDoc() }
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    // MARK: - View lifecycle

    override func loadView() {
        let wrapper = FlippedView()

        scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true

        let maruTextView = MaruTextView(frame: .zero)
        maruTextView.minSize = NSSize(width: 0, height: 0)
        maruTextView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        maruTextView.isVerticallyResizable = true
        maruTextView.isHorizontallyResizable = true
        maruTextView.autoresizingMask = [.width]
        maruTextView.textContainer?.widthTracksTextView = false
        maruTextView.textContainer?.containerSize = NSSize(
            width: scrollView.contentSize.width, height: CGFloat.greatestFiniteMagnitude)
        maruTextView.selectionOwner = self
        scrollView.documentView = maruTextView
        scrollView.hasHorizontalScroller = true
        textView = maruTextView
        textView.setAccessibilityLabel("Editor")
        // Force TextKit 1 so layout manager APIs work reliably
        textView.layoutManager?.delegate = self

        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.isRichText = false
        textView.usesFindBar = false
        textView.backgroundColor = Theme.background
        textView.insertionPointColor = Theme.cursor
        textView.selectedTextAttributes = [
            .backgroundColor: Theme.selection,
            .foregroundColor: Theme.foreground,
        ]
        textView.font = Theme.editorFont
        textView.textColor = Theme.foreground
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.smartInsertDeleteEnabled = false
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.delegate = self

        let tabW = " ".size(withAttributes: [.font: Theme.editorFont]).width * 4
        let para = NSMutableParagraphStyle()
        para.tabStops = []
        para.defaultTabInterval = tabW
        textView.defaultParagraphStyle = para
        textView.typingAttributes = [
            .font: Theme.editorFont,
            .foregroundColor: Theme.foreground,
            .paragraphStyle: para,
        ]

        lineNumbers = LineNumberView(textView: textView)
        lineNumbers?.onToggleFold = { [weak self] id in self?.toggleFold(regionID: id) }

        wrapper.addSubview(lineNumbers!)
        wrapper.addSubview(scrollView)
        NSLayoutConstraint.activate([
            lineNumbers!.topAnchor.constraint(equalTo: wrapper.topAnchor),
            lineNumbers!.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor),
            lineNumbers!.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor),

            scrollView.topAnchor.constraint(equalTo: wrapper.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: lineNumbers!.trailingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor),
        ])

        NotificationCenter.default.addObserver(
            self, selector: #selector(boundsChanged),
            name: NSView.boundsDidChangeNotification, object: scrollView.contentView
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(accessibilityDisplayOptionsChanged),
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)

        view = wrapper
        applyHighContrast(NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast)
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        configureLargeFileEditingMode()
        DispatchQueue.main.async { [weak self] in
            self?.textView.window?.makeFirstResponder(self?.textView)
        }
    }

    @objc private func boundsChanged(_ n: Notification) {
        lineNumbers?.needsDisplay = true
        scheduleScrollHighlight()
    }

    private func scheduleScrollHighlight() {
        highlightVisible(delay: 0.03)
    }

    // MARK: - Document

    /// Rebuilds the text view from `document.content`, discarding any
    /// cached `NSTextStorage` first — for when the same `Document`
    /// instance's content changed out from under the view (e.g.
    /// "Reopen with Encoding…", ROADMAP.md M2-02) rather than a genuinely
    /// different document being switched in, which `loadDoc()` alone
    /// wouldn't pick up since it prefers `document.cachedTextStorage`.
    func reloadCurrentDocument() {
        document?.cachedTextStorage = nil
        loadDoc()
    }

    private func loadDoc() {
        guard let doc = document else { return }
        syntaxHighlightCoordinator.cancel()

        let lm = textView.layoutManager!
        suppressTextChange = true

        if let cached = doc.cachedTextStorage {
            lm.replaceTextStorage(cached)
        } else {
            let para = textView.defaultParagraphStyle ?? NSParagraphStyle.default
            let ts = NSTextStorage(string: doc.content, attributes: [
                .font: Theme.editorFont,
                .foregroundColor: Theme.foreground,
                .paragraphStyle: para,
            ])
            lm.replaceTextStorage(ts)
            doc.cachedTextStorage = ts
        }

        suppressTextChange = false
        lineIndex = LineIndex(textView.string)
        configureLargeFileEditingMode()
        let cursor = NSRange(location: min(doc.cursorPosition, lm.textStorage?.length ?? 0), length: 0)
        setSelections([cursor], primaryRange: cursor)
        refreshBookmarkGutter()
        lineNumbers?.needsDisplay = true
        applyPreferences(preferences)
        deferredHighlightVisible()
    }

    func refreshBookmarkGutter() {
        lineNumbers?.bookmarkOffsets = document?.bookmarks.offsets ?? []
        refreshFolding()
    }

    func applyPreferences(_ preferences: Preferences) {
        self.preferences = preferences
        Theme.activeName = preferences.theme
        guard isViewLoaded else { return }
        var effectivePreferences = preferences
        effectivePreferences.tabWidth = document?.tabWidthOverride
            ?? document?.fileTypeProfile?.settings.tabWidth ?? preferences.tabWidth
        effectivePreferences.wrapLines = document?.largeFileMode.usesReducedFeatures == true ? false : document?.wrapLinesOverride
            ?? document?.fileTypeProfile?.settings.wrapLines ?? preferences.wrapLines
        let font = preferredEditorFont
        let paragraph = NSMutableParagraphStyle()
        paragraph.tabStops = []
        paragraph.defaultTabInterval = " ".size(withAttributes: [.font: font]).width
            * CGFloat(max(1, effectivePreferences.tabWidth))
        textView.font = font
        (textView as? MaruTextView)?.invisibleCharacters = document?.largeFileMode.usesReducedFeatures == true
            ? .none : preferences.invisibleCharacters
        textView.defaultParagraphStyle = paragraph
        textView.typingAttributes[.font] = font
        textView.typingAttributes[.paragraphStyle] = paragraph
        if let storage = textView.textStorage, storage.length > 0 {
            storage.addAttributes([.font: font, .paragraphStyle: paragraph],
                                  range: NSRange(location: 0, length: storage.length))
        }
        lineNumbers?.setVisible(effectivePreferences.showLineNumbers)
        textView.textContainer?.widthTracksTextView = effectivePreferences.wrapLines
        textView.isHorizontallyResizable = !effectivePreferences.wrapLines
        scrollView.hasHorizontalScroller = !effectivePreferences.wrapLines
        if effectivePreferences.wrapLines {
            textView.textContainer?.containerSize.width = scrollView.contentSize.width
        } else {
            textView.textContainer?.containerSize.width = CGFloat.greatestFiniteMagnitude
        }
        applyHighContrast(isHighContrast)
        lineNumbers?.needsDisplay = true
    }

    var effectiveWrapLines: Bool {
        if document?.largeFileMode.usesReducedFeatures == true { return false }
        return document?.wrapLinesOverride ?? document?.fileTypeProfile?.settings.wrapLines
            ?? preferences.wrapLines
    }

    func enableAllLargeFileFeatures() {
        guard let document, document.largeFileMode == .reducedFeatures else { return }
        document.largeFileMode = .normal
        document.hasExplicitlyEnabledLargeFileFeatures = true
        configureLargeFileEditingMode()
        applyPreferences(preferences)
        deferredHighlightVisible()
    }

    private func configureLargeFileEditingMode() {
        textView.isEditable = !(document?.isReadOnly ?? false)
        textView.undoManager?.levelsOfUndo = document?.largeFileMode.usesReducedFeatures == true ? 20 : 0
    }

    var effectiveTabWidth: Int {
        document?.tabWidthOverride ?? document?.fileTypeProfile?.settings.tabWidth
            ?? preferences.tabWidth
    }

    func toggleWrapLines() {
        document?.wrapLinesOverride = !effectiveWrapLines
        applyPreferences(preferences)
    }

    func setTabWidth(_ width: Int) {
        document?.tabWidthOverride = max(1, min(16, width))
        applyPreferences(preferences)
        emitCursor()
    }

    @objc private func accessibilityDisplayOptionsChanged() {
        applyHighContrast(NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast)
    }

    func applyHighContrast(_ enabled: Bool) {
        isHighContrast = enabled
        guard isViewLoaded else { return }
        textView.backgroundColor = enabled ? .black : Theme.background
        textView.textColor = editorForeground
        textView.insertionPointColor = enabled ? .white : Theme.cursor
        textView.selectedTextAttributes = [
            .backgroundColor: enabled ? NSColor.white : Theme.selection,
            .foregroundColor: enabled ? NSColor.black : Theme.foreground,
        ]
        (textView as? MaruTextView)?.usesHighContrastMarkers = enabled
        if let storage = textView.textStorage, storage.length > 0 {
            storage.addAttribute(
                .foregroundColor, value: editorForeground,
                range: NSRange(location: 0, length: storage.length))
        }
        rehighlightAll()
    }

    func changeEditorFont(using manager: NSFontManager) {
        applyEditorFont(manager.convert(preferredEditorFont))
    }

    func applyEditorFont(_ converted: NSFont) {
        var updated = preferences
        updated.fontName = converted.fontName
        updated.fontSize = converted.pointSize
        applyPreferences(updated)
        delegate?.editorDidChooseFont(self, font: converted)
    }

    /// Deferred to let scroll-view geometry settle after replaceTextStorage.
    /// Small files request the full document; large-file mode skips regex work.
    private func deferredHighlightVisible() {
        guard let storage = textView.textStorage, let language = document?.language else { return }
        let range = storage.length <= SyntaxHighlightCoordinator.largeFileThreshold
            ? nil : visibleCharacterRange()
        syntaxHighlightCoordinator.schedule(
            storage: storage, language: isHighContrast ? .plainText : language, visibleRange: range,
            font: preferredEditorFont, baseForeground: editorForeground, delay: 0.02,
            allowLargeFileHighlighting: document?.hasExplicitlyEnabledLargeFileFeatures == true)
    }

    /// Highlights the visible range plus a buffer for smooth scrolling.
    private func highlightVisible(delay: TimeInterval = 0.05) {
        guard let ts = textView.textStorage, ts.length > 0,
              let language = document?.language else { return }
        guard ts.length <= SyntaxHighlightCoordinator.largeFileThreshold
                || document?.hasExplicitlyEnabledLargeFileFeatures == true else { return }
        let visible = visibleCharacterRange()
        guard visible.length > 0 else { return }
        syntaxHighlightCoordinator.schedule(
            storage: ts, language: isHighContrast ? .plainText : language, visibleRange: visible,
            font: preferredEditorFont, baseForeground: editorForeground, delay: delay,
            allowLargeFileHighlighting: document?.hasExplicitlyEnabledLargeFileFeatures == true)
    }

    private func visibleCharacterRange() -> NSRange {
        guard let lm = textView.layoutManager, let tc = textView.textContainer else {
            return NSRange(location: 0, length: textView.textStorage?.length ?? 0)
        }
        let visibleRect = scrollView.documentVisibleRect
        let glyphRange = lm.glyphRange(forBoundingRect: visibleRect, in: tc)
        return lm.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
    }

    private func rehighlightAll() {
        guard let ts = textView.textStorage, ts.length > 0,
              let language = document?.language else { return }
        syntaxHighlightCoordinator.schedule(
            storage: ts, language: isHighContrast ? .plainText : language, visibleRange: nil,
            font: preferredEditorFont, baseForeground: editorForeground, delay: 0,
            allowLargeFileHighlighting: document?.hasExplicitlyEnabledLargeFileFeatures == true)
    }

    // MARK: - NSTextViewDelegate

    func textView(_ textView: NSTextView, shouldChangeTextIn range: NSRange,
                  replacementString text: String?) -> Bool {
        beginInputLatencySignpost()
        let replacement = text ?? ""
        if lineIndex.utf16Length != (textView.string as NSString).length {
            lineIndex = LineIndex(textView.string)
        }
        if suppressAutoIndent || replacement != "\n" {
            document?.bookmarks.applyEdit(range: range, replacement: replacement)
            lineIndex.applyEdit(range: range, replacement: replacement)
            return true
        }

        let ns = textView.string as NSString
        let lineRange = ns.lineRange(for: NSRange(location: min(range.location, ns.length), length: 0))
        let line = ns.substring(with: lineRange)

        var indent = ""
        for ch in line {
            if ch == " " || ch == "\t" { indent.append(ch) }
            else { break }
        }
        guard !indent.isEmpty else {
            document?.bookmarks.applyEdit(range: range, replacement: replacement)
            lineIndex.applyEdit(range: range, replacement: replacement)
            return true
        }

        suppressAutoIndent = true
        textView.insertText("\n" + indent, replacementRange: range)
        suppressAutoIndent = false
        return false
    }

    func textDidChange(_ n: Notification) {
        guard !suppressTextChange else { return }
        if scheduleCompositionCommitAfterUnmarkIfNeeded() { return }
        let content = textView.string
        if lineIndex.utf16Length != (content as NSString).length {
            lineIndex = LineIndex(content)
        }
        document?.bookmarks.normalize(in: content as NSString)
        document?.content = content
        document?.markModified()
        refreshFolding()
        delegate?.editorTextDidChange(self)
        lineNumbers?.needsDisplay = true
        lineNumbers?.bookmarkOffsets = document?.bookmarks.offsets ?? []
        emitCursor()

        if let ts = textView.textStorage, ts.length > 0, let language = document?.language {
            let rehighlightRange: NSRange
            if document?.language == .markdown {
                rehighlightRange = visibleCharacterRange()
            } else {
                let sel = textView.selectedRange()
                let ns = content as NSString
                rehighlightRange = ns.lineRange(for: NSRange(location: min(sel.location, ns.length), length: 0))
            }
            syntaxHighlightCoordinator.schedule(
                storage: ts, language: isHighContrast ? .plainText : language,
                visibleRange: rehighlightRange, font: preferredEditorFont,
                baseForeground: editorForeground,
                allowLargeFileHighlighting: document?.hasExplicitlyEnabledLargeFileFeatures == true)
        }
        endInputLatencySignpost()
    }

    func refreshFolding() {
        guard isViewLoaded, let document, let layoutManager = textView.layoutManager else { return }
        let outline = OutlineModel(
            text: document.content, language: document.language,
            customRules: document.fileTypeProfile?.settings.outlineRules ?? [])
        document.foldModel.rebuild(text: document.content, symbols: outline.symbols)
        layoutManager.invalidateGlyphs(
            forCharacterRange: NSRange(location: 0, length: (document.content as NSString).length),
            changeInLength: 0, actualCharacterRange: nil)
        layoutManager.invalidateLayout(
            forCharacterRange: NSRange(location: 0, length: (document.content as NSString).length),
            actualCharacterRange: nil)
        layoutManager.ensureGlyphs(forCharacterRange: NSRange(
            location: 0, length: (document.content as NSString).length))
        lineNumbers?.foldRegions = document.foldModel.regions
        lineNumbers?.collapsedFoldIDs = document.foldModel.collapsedRegionIDs
        textView.needsDisplay = true
    }

    @discardableResult
    func toggleFold(regionID: String) -> Bool {
        guard let document else { return false }
        let collapsed = document.foldModel.toggle(regionID: regionID)
        refreshFolding()
        return collapsed
    }

    func toggleFoldAtCursor() {
        guard let document else { return }
        let line = LineIndex(textView.string).line(atUTF16Offset: textView.selectedRange().location)
        guard let region = document.foldModel.region(startingAtLine: line) else { return }
        _ = toggleFold(regionID: region.id)
    }

    func collapseAllFolds() { document?.foldModel.collapseAll(); refreshFolding() }
    func expandAllFolds() { document?.foldModel.expandAll(); refreshFolding() }

    var collapsedFoldCountForTesting: Int { document?.foldModel.collapsedRegionIDs.count ?? 0 }

    nonisolated func layoutManager(
        _ layoutManager: NSLayoutManager,
        shouldGenerateGlyphs glyphs: UnsafePointer<CGGlyph>,
        properties props: UnsafePointer<NSLayoutManager.GlyphProperty>,
        characterIndexes charIndexes: UnsafePointer<Int>,
        font: NSFont,
        forGlyphRange glyphRange: NSRange
    ) -> Int {
        MainActor.assumeIsolated {
            let hidden = document?.foldModel.collapsedRanges() ?? []
            guard !hidden.isEmpty else { return 0 }
            var properties = Array(UnsafeBufferPointer(start: props, count: glyphRange.length))
            for index in properties.indices where hidden.contains(where: {
                NSLocationInRange(charIndexes[index], $0)
            }) {
                properties[index].insert(.null)
            }
            properties.withUnsafeBufferPointer { propertyBuffer in
                layoutManager.setGlyphs(
                    glyphs, properties: propertyBuffer.baseAddress!,
                    characterIndexes: charIndexes, font: font, forGlyphRange: glyphRange)
            }
            return glyphRange.length
        }
    }

    nonisolated func layoutManager(
        _ layoutManager: NSLayoutManager,
        shouldUse action: NSLayoutManager.ControlCharacterAction,
        forControlCharacterAt charIndex: Int
    ) -> NSLayoutManager.ControlCharacterAction {
        MainActor.assumeIsolated {
            let hidden = document?.foldModel.collapsedRanges() ?? []
            return hidden.contains(where: { NSLocationInRange(charIndex, $0) })
                ? .zeroAdvancement : action
        }
    }

    func beginInputLatencySignpost() {
        endInputLatencySignpost()
        let identifier = OSSignpostID(log: Self.inputLatencyLog)
        inputLatencySignpostID = identifier
        os_signpost(.begin, log: Self.inputLatencyLog, name: "EditorInputLatency", signpostID: identifier)
    }

    func endInputLatencySignpost() {
        guard let identifier = inputLatencySignpostID else { return }
        os_signpost(.end, log: Self.inputLatencyLog, name: "EditorInputLatency", signpostID: identifier)
        inputLatencySignpostID = nil
    }

    func textViewDidChangeSelection(_ n: Notification) {
        if markedTextSnapshot != nil {
            _ = scheduleCompositionCommitAfterUnmarkIfNeeded()
            return
        }
        guard !isApplyingSelectionSet else { return }
        selectionSet.update(
            ranges: textView.selectedRanges.map(\.rangeValue),
            primaryRange: textView.selectedRange()
        )
        lineNumbers?.needsDisplay = true
        emitCursor()
    }

    var hasMarkedTextComposition: Bool { markedTextSnapshot != nil }

    func beginMarkedTextComposition() {
        guard markedTextSnapshot == nil,
              isMultiEditActive || document?.inputMode == .overwrite else { return }
        markedTextSnapshot = (textView.string, selectionSet.ranges, selectionSet.primaryRange)
        pollMarkedTextUntilSettled()
    }

    func commitMarkedText(_ text: String) {
        guard let snapshot = markedTextSnapshot else { return }
        markedTextSnapshot = nil
        isCompositionCommitScheduled = false
        restoreCompositionBaseline(snapshot)
        let ranges = snapshot.ranges.map { replacementRangeForInput(text, selection: $0) }
        batchReplace(ranges, with: text)
    }

    func replacementRangeForInput(_ inserted: String, selection: NSRange) -> NSRange {
        guard document?.inputMode == .overwrite, selection.length == 0,
              !inserted.contains("\n"), !inserted.contains("\r") else { return selection }
        let string = textView.string
        let ns = string as NSString
        guard selection.location < ns.length else { return selection }
        let line = ns.lineRange(for: NSRange(location: selection.location, length: 0))
        let hasLF = NSMaxRange(line) > line.location
            && ns.character(at: NSMaxRange(line) - 1) == 0x0A
        let contentEnd = NSMaxRange(line) - (hasLF ? 1 : 0)
        guard selection.location < contentEnd else { return selection }
        let start = String.Index(utf16Offset: selection.location, in: string)
        var end = start
        var remaining = inserted.count
        while remaining > 0, end < string.endIndex,
              string[end] != "\n", string[end] != "\r" {
            end = string.index(after: end)
            remaining -= 1
        }
        return NSRange(
            location: selection.location,
            length: end.utf16Offset(in: string) - selection.location)
    }

    func toggleInputMode() {
        guard let document else { return }
        document.inputMode = document.inputMode == .insert ? .overwrite : .insert
        emitCursor()
    }

    func cancelMarkedTextComposition() {
        guard let snapshot = markedTextSnapshot else { return }
        markedTextSnapshot = nil
        isCompositionCommitScheduled = false
        restoreCompositionBaseline(snapshot)
    }

    /// Some system IMEs finalize marked text by mutating TextKit and ending
    /// the marked range without calling either NSTextView insertText entry
    /// point. Detect that state transition at the delegate boundary and
    /// recover the committed candidate from the before/after UTF-16 diff.
    private func scheduleCompositionCommitAfterUnmarkIfNeeded() -> Bool {
        guard let snapshot = markedTextSnapshot,
              !isCompositionCommitScheduled,
              !textView.hasMarkedText() else { return false }
        let old = snapshot.text as NSString
        let new = textView.string as NSString
        var prefix = 0
        while prefix < old.length, prefix < new.length,
              old.character(at: prefix) == new.character(at: prefix) { prefix += 1 }
        var suffix = 0
        while suffix < old.length - prefix, suffix < new.length - prefix,
              old.character(at: old.length - suffix - 1) == new.character(at: new.length - suffix - 1) {
            suffix += 1
        }
        let committed = new.substring(with: NSRange(
            location: prefix, length: new.length - prefix - suffix))
        if committed.isEmpty {
            guard snapshot.text != textView.string else { return false }
            isCompositionCommitScheduled = true
            DispatchQueue.main.async { [weak self] in self?.cancelMarkedTextComposition() }
            return true
        }
        isCompositionCommitScheduled = true
        DispatchQueue.main.async { [weak self] in self?.commitMarkedText(committed) }
        return true
    }

    func finalizeCompositionIfUnmarked() {
        _ = scheduleCompositionCommitAfterUnmarkIfNeeded()
    }

    private func pollMarkedTextUntilSettled() {
        guard markedTextSnapshot != nil else { return }
        if !textView.hasMarkedText() {
            if scheduleCompositionCommitAfterUnmarkIfNeeded() { return }
            // Some IMEs briefly expose no marked range before their first
            // actual marked-text mutation. An empty diff is not a commit;
            // keep observing until text changes or cancellation clears the
            // snapshot.
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { [weak self] in
            self?.pollMarkedTextUntilSettled()
        }
    }

    private func restoreCompositionBaseline(
        _ snapshot: (text: String, ranges: [NSRange], primary: NSRange)
    ) {
        guard let storage = textView.textStorage else { return }
        textView.undoManager?.disableUndoRegistration()
        storage.beginEditing()
        storage.replaceCharacters(in: NSRange(location: 0, length: storage.length), with: snapshot.text)
        storage.endEditing()
        lineIndex = LineIndex(snapshot.text)
        textView.undoManager?.enableUndoRegistration()
        document?.content = snapshot.text
        document?.markModified()
        setSelections(snapshot.ranges, primaryRange: snapshot.primary)
    }

    private func emitCursor() {
        let sel = textView.selectedRange()
        let ns = textView.string as NSString
        let offset = min(sel.location, ns.length)
        let tabWidth = document?.fileTypeProfile?.settings.tabWidth ?? preferences.tabWidth
        let line = lineIndex.line(atUTF16Offset: offset)
        let displayColumn = lineIndex.displayColumn(
            atUTF16Offset: offset, in: textView.string, tabWidth: tabWidth)
        let ranges = textView.selectedRanges.map(\.rangeValue)
        delegate?.editorCursorMoved(self, state: EditorCursorState(
            lineNumber: line + 1,
            displayColumn: displayColumn + 1,
            utf16Offset: offset,
            selectedCharacterCount: ranges.reduce(0) {
                $0 + ns.substring(with: NSIntersectionRange(
                    $1, NSRange(location: 0, length: ns.length))).count
            },
            selectedUTF16Length: ranges.reduce(0) { $0 + $1.length },
            selectionRangeCount: ranges.count
        ))
    }

    func goToLine(_ line: Int) {
        let ns = textView.string as NSString
        if let idx = lineIndex.utf16Offset(forLine: line - 1) {
            let lr = ns.lineRange(for: NSRange(location: idx, length: 0))
            textView.setSelectedRange(NSRange(location: lr.location, length: 0))
            textView.scrollRangeToVisible(lr)
        }
    }
}
