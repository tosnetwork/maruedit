import AppKit
import MaruEditCore

protocol EditorViewControllerDelegate: AnyObject {
    func editorTextDidChange(_ vc: EditorViewController)
    func editorCursorMoved(_ vc: EditorViewController, line: Int, col: Int)
}

private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

final class EditorViewController: NSViewController, NSTextViewDelegate {
    weak var delegate: EditorViewControllerDelegate?

    private(set) var scrollView: NSScrollView!
    private(set) var textView: NSTextView!
    private var lineNumbers: LineNumberView?
    private var highlighter: SyntaxHighlighter?

    private static var highlighterCache: [Language: SyntaxHighlighter] = [:]
    private static let fullHighlightThreshold = 100_000
    private var highlightWorkItem: DispatchWorkItem?
    private var scrollHighlightItem: DispatchWorkItem?

    private var suppressTextChange = false
    private var suppressAutoIndent = false
    private var isApplyingSelectionSet = false
    private var markedTextSnapshot: (text: String, ranges: [NSRange], primary: NSRange)?
    private var isCompositionCommitScheduled = false
    private var preferences = Preferences.defaults
    var appliedPreferences: Preferences { preferences }
    var areLineNumbersHidden: Bool { lineNumbers?.isHidden ?? false }
    private var preferredEditorFont: NSFont {
        preferences.fontName == "SF Mono"
            ? NSFont.monospacedSystemFont(ofSize: preferences.fontSize, weight: .regular)
            : (NSFont(name: preferences.fontName, size: preferences.fontSize)
                ?? NSFont.monospacedSystemFont(ofSize: preferences.fontSize, weight: .regular))
    }

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

    var document: Document? {
        didSet {
            guard document !== oldValue else { return }
            isMultiEditActive = false
            if isViewLoaded { loadDoc() }
        }
    }

    private static func cachedHighlighter(for language: Language) -> SyntaxHighlighter {
        if let h = highlighterCache[language] { return h }
        let h = SyntaxHighlighter(language: language)
        highlighterCache[language] = h
        return h
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
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
        _ = textView.layoutManager

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

        view = wrapper
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        DispatchQueue.main.async { [weak self] in
            self?.textView.window?.makeFirstResponder(self?.textView)
        }
    }

    @objc private func boundsChanged(_ n: Notification) {
        lineNumbers?.needsDisplay = true
        scheduleScrollHighlight()
    }

    private func scheduleScrollHighlight() {
        scrollHighlightItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.highlightVisible()
        }
        scrollHighlightItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03, execute: item)
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
        highlightWorkItem?.cancel()
        scrollHighlightItem?.cancel()
        highlighter = Self.cachedHighlighter(for: doc.language)

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
        let cursor = NSRange(location: min(doc.cursorPosition, lm.textStorage?.length ?? 0), length: 0)
        setSelections([cursor], primaryRange: cursor)
        refreshBookmarkGutter()
        lineNumbers?.needsDisplay = true
        applyPreferences(preferences)
        deferredHighlightVisible()
    }

    func refreshBookmarkGutter() {
        lineNumbers?.bookmarkOffsets = document?.bookmarks.offsets ?? []
    }

    func applyPreferences(_ preferences: Preferences) {
        self.preferences = preferences
        guard isViewLoaded else { return }
        var effectivePreferences = preferences
        if let settings = document?.fileTypeProfile?.settings {
            effectivePreferences.tabWidth = settings.tabWidth
            effectivePreferences.wrapLines = settings.wrapLines
        }
        let font = preferredEditorFont
        let paragraph = NSMutableParagraphStyle()
        paragraph.tabStops = []
        paragraph.defaultTabInterval = " ".size(withAttributes: [.font: font]).width
            * CGFloat(max(1, effectivePreferences.tabWidth))
        textView.font = font
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
        lineNumbers?.needsDisplay = true
    }

    /// Deferred to next run-loop so the scroll view geometry is settled
    /// after replaceTextStorage.  For small files the full document is
    /// highlighted; large files get viewport-only (scroll handles the rest).
    private func deferredHighlightVisible() {
        let item = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            guard let ts = self.textView.textStorage, ts.length > 0 else { return }

            let visible = self.visibleCharacterRange()
            if ts.length <= Self.fullHighlightThreshold {
                ts.beginEditing()
                self.highlighter?.highlight(ts, in: NSRange(location: 0, length: ts.length), font: self.preferredEditorFont)
                ts.endEditing()
            } else if visible.length > 0 {
                ts.beginEditing()
                self.highlighter?.highlight(ts, in: visible, font: self.preferredEditorFont)
                ts.endEditing()
            }
        }
        highlightWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02, execute: item)
    }

    /// Highlights the visible range plus a buffer for smooth scrolling.
    private func highlightVisible() {
        guard let ts = textView.textStorage, ts.length > 0 else { return }
        let visible = visibleCharacterRange()
        guard visible.length > 0 else { return }

        let buffer = 3000
        let start = max(0, visible.location - buffer)
        let end = min(ts.length, NSMaxRange(visible) + buffer)
        let range = NSRange(location: start, length: end - start)

        ts.beginEditing()
        highlighter?.highlight(ts, in: range, font: preferredEditorFont)
        ts.endEditing()
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
        guard let ts = textView.textStorage, ts.length > 0 else { return }
        if ts.length > Self.fullHighlightThreshold {
            highlightVisible()
            return
        }
        ts.beginEditing()
        highlighter?.highlight(ts, in: NSRange(location: 0, length: ts.length), font: preferredEditorFont)
        ts.endEditing()
    }

    // MARK: - NSTextViewDelegate

    func textView(_ textView: NSTextView, shouldChangeTextIn range: NSRange,
                  replacementString text: String?) -> Bool {
        let replacement = text ?? ""
        if suppressAutoIndent || replacement != "\n" {
            document?.bookmarks.applyEdit(range: range, replacement: replacement)
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
        document?.bookmarks.normalize(in: content as NSString)
        document?.content = content
        document?.markModified()
        delegate?.editorTextDidChange(self)
        lineNumbers?.needsDisplay = true
        lineNumbers?.bookmarkOffsets = document?.bookmarks.offsets ?? []
        emitCursor()

        if let ts = textView.textStorage, ts.length > 0 {
            let rehighlightRange: NSRange
            if document?.language == .markdown {
                rehighlightRange = visibleCharacterRange()
            } else {
                let sel = textView.selectedRange()
                let ns = content as NSString
                rehighlightRange = ns.lineRange(for: NSRange(location: min(sel.location, ns.length), length: 0))
            }
            ts.beginEditing()
            highlighter?.highlight(ts, in: rehighlightRange, font: preferredEditorFont)
            ts.endEditing()
        }
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
        guard markedTextSnapshot == nil, isMultiEditActive else { return }
        markedTextSnapshot = (textView.string, selectionSet.ranges, selectionSet.primaryRange)
        pollMarkedTextUntilSettled()
    }

    func commitMarkedText(_ text: String) {
        guard let snapshot = markedTextSnapshot else { return }
        markedTextSnapshot = nil
        isCompositionCommitScheduled = false
        restoreCompositionBaseline(snapshot)
        batchReplace(snapshot.ranges, with: text)
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
        textView.undoManager?.enableUndoRegistration()
        document?.content = snapshot.text
        document?.markModified()
        setSelections(snapshot.ranges, primaryRange: snapshot.primary)
    }

    private func emitCursor() {
        let sel = textView.selectedRange()
        let ns = textView.string as NSString
        var line = 1
        var i = 0
        while i < sel.location && i < ns.length {
            if ns.character(at: i) == 0x0A { line += 1 }
            i += 1
        }
        let lineStart = ns.lineRange(for: NSRange(location: min(sel.location, ns.length), length: 0)).location
        delegate?.editorCursorMoved(self, line: line, col: sel.location - lineStart + 1)
    }

    func goToLine(_ line: Int) {
        let ns = textView.string as NSString
        var cur = 1, idx = 0
        while cur < line && idx < ns.length {
            if ns.character(at: idx) == 0x0A { cur += 1 }
            idx += 1
        }
        if cur == line {
            let lr = ns.lineRange(for: NSRange(location: idx, length: 0))
            textView.setSelectedRange(NSRange(location: lr.location, length: 0))
            textView.scrollRangeToVisible(lr)
        }
    }
}
