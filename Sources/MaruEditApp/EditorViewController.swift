@preconcurrency import AppKit
import MaruEditCore
import os.log

@MainActor
protocol EditorViewControllerDelegate: AnyObject {
    func editorTextDidChange(_ vc: EditorViewController)
    func editorCursorMoved(_ vc: EditorViewController, state: EditorCursorState)
    func editorDidChooseFont(_ vc: EditorViewController, font: NSFont)
    func editorCompletionMessage(_ vc: EditorViewController, message: String)
}

extension EditorViewControllerDelegate {
    func editorDidChooseFont(_ vc: EditorViewController, font: NSFont) {}
    func editorCompletionMessage(_ vc: EditorViewController, message: String) {}
}

private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

private final class FoldLayoutDelegate: NSObject, NSLayoutManagerDelegate {
    var collapsedRanges: [NSRange] = []

    func layoutManager(
        _ layoutManager: NSLayoutManager,
        shouldGenerateGlyphs glyphs: UnsafePointer<CGGlyph>,
        properties props: UnsafePointer<NSLayoutManager.GlyphProperty>,
        characterIndexes charIndexes: UnsafePointer<Int>,
        font: NSFont,
        forGlyphRange glyphRange: NSRange
    ) -> Int {
        guard !collapsedRanges.isEmpty else { return 0 }
        var properties = Array(UnsafeBufferPointer(start: props, count: glyphRange.length))
        for index in properties.indices where collapsedRanges.contains(where: {
            NSLocationInRange(charIndexes[index], $0)
        }) { properties[index].insert(.null) }
        properties.withUnsafeBufferPointer {
            layoutManager.setGlyphs(
                glyphs, properties: $0.baseAddress!, characterIndexes: charIndexes,
                font: font, forGlyphRange: glyphRange)
        }
        return glyphRange.length
    }

    func layoutManager(
        _ layoutManager: NSLayoutManager,
        shouldUse action: NSLayoutManager.ControlCharacterAction,
        forControlCharacterAt charIndex: Int
    ) -> NSLayoutManager.ControlCharacterAction {
        collapsedRanges.contains { NSLocationInRange(charIndex, $0) }
            ? .zeroAdvancement : action
    }
}

final class EditorViewController: NSViewController, NSTextViewDelegate {
    static let inputLatencyLog = OSLog(subsystem: "com.maruedit.editor", category: "InputLatency")
    weak var delegate: EditorViewControllerDelegate?

    private(set) var scrollView: NSScrollView!
    private(set) var textView: NSTextView!
    private var lineNumbers: LineNumberView?
    private var columnLayoutHost: FlippedView?
    private var columnTextViews: [NSTextView] = []
    private let syntaxHighlightCoordinator = SyntaxHighlightCoordinator()
    private let foldLayoutDelegate = FoldLayoutDelegate()

    private var suppressTextChange = false
    private var suppressAutoIndent = false
    private var suppressScrollCallback = false
    var onScroll: ((NSPoint) -> Void)?
    var onCrossDocumentScroll: ((NSPoint) -> Void)?
    private var isApplyingSelectionSet = false
    var cursorHistory: [Int] = []
    var isRestoringCursorHistory = false
    private var markedTextSnapshot: (text: String, ranges: [NSRange], primary: NSRange)?
    private var isCompositionCommitScheduled = false
    private var completionDictionaries: [String] = []
    private var searchMarkerOffsets: Set<Int> = []
    private(set) var deletedTextHistory: [String] = []
    private(set) var isTableMode = false
    private(set) var partialEditRange: NSRange?
    var inputLatencySignpostID: OSSignpostID?
    var lineIndex = LineIndex()
    private var preferences = Preferences.defaults
    private(set) var isHighContrast = false
    var appliedPreferences: Preferences { preferences }
    var areLineNumbersHidden: Bool { lineNumbers?.isHidden ?? false }
    private var preferredEditorFont: NSFont {
        let appearance = document?.fileTypeProfile?.settings.appearance
        let name = appearance?.fontName ?? preferences.fontName
        let size = min(72, max(8, appearance?.fontSize ?? preferences.fontSize))
        return name == "SF Mono"
            ? NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
            : (NSFont(name: name, size: size)
                ?? NSFont.monospacedSystemFont(ofSize: size, weight: .regular))
    }
    var currentEditorFont: NSFont { preferredEditorFont }
    private var editorForeground: NSColor {
        if isHighContrast { return .white }
        return Self.color(hex: document?.fileTypeProfile?.settings.appearance?.foregroundHex)
            ?? Theme.foreground
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
    var reservedSelections: [NSRange] = []
    var columnSelectionRows: [BoxSelectionRow]?
    private var columnSelectionDimensions: (width: Int, height: Int)?
    private var columnSelectionAnchor: TextCoordinate?

    /// Compatibility access for the M1 prototype. M4-02/M4-03 remove the
    /// remaining direct uses as commands and editing move to SelectionSet.
    var multiEditCursorRanges: [NSRange] {
        get { selectionSet.ranges }
        set { setSelections(newValue) }
    }

    func setSelections(_ ranges: [NSRange], primaryRange: NSRange? = nil) {
        let previous = selectionSet.primaryRange.location
        selectionSet.update(ranges: ranges, primaryRange: primaryRange)
        recordCursorTransition(from: previous, to: selectionSet.primaryRange.location)
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
        columnSelectionDimensions = (
            abs(current.visualColumn - anchor.visualColumn),
            abs(current.line - anchor.line) + 1)
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
        columnSelectionDimensions = nil
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
        columnSelectionDimensions = nil
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
    var hasExplicitSearchScope = false
    private var temporarySearchHighlightRanges: [NSRange] = []
    var searchColorLayers: [SearchColorLayer] { document?.searchColorLayers ?? [] }
    struct TemporaryColorMarker: Equatable {
        var range: NSRange
        var color: MarkerColor
    }
    var temporaryColorMarkers: [TemporaryColorMarker] = []
    var temporaryColorMarkerColor: MarkerColor = .yellow

    func showSearchHighlights(_ ranges: [NSRange], color: NSColor = .systemYellow) {
        temporarySearchHighlightRanges = ranges
        searchHighlightColor = color
        refreshColorOverlays()
    }

    func addSearchColorLayer(query: String, ranges: [NSRange], color: NSColor) {
        document?.searchColorLayers.append(SearchColorLayer(query: query, ranges: ranges, color: color))
        refreshColorOverlays()
    }

    func clearSearchColorLayers() {
        document?.searchColorLayers.removeAll()
        refreshColorOverlays()
    }

    func navigateSearchResult(forward: Bool) -> Bool {
        let ranges = (searchColorLayers.flatMap(\.ranges) + temporarySearchHighlightRanges)
            .sorted { $0.location < $1.location }
        guard !ranges.isEmpty else { return false }
        let current = selectionSet.primaryRange.location
        let target = forward
            ? ranges.first(where: { $0.location > current }) ?? ranges.first
            : ranges.last(where: { $0.location < current }) ?? ranges.last
        guard let target else { return false }
        setSelections([target], primaryRange: target)
        textView.scrollRangeToVisible(target)
        return true
    }

    private var searchHighlightColor: NSColor = .systemYellow

    func refreshColorOverlays() {
        guard let layoutManager = textView.layoutManager else { return }
        let length = layoutManager.textStorage?.length ?? 0
        layoutManager.removeTemporaryAttribute(
            .backgroundColor, forCharacterRange: NSRange(location: 0, length: length))
        for range in temporarySearchHighlightRanges where range.length > 0 && NSMaxRange(range) <= length {
            layoutManager.addTemporaryAttribute(
                .backgroundColor, value: searchHighlightColor.withAlphaComponent(0.38),
                forCharacterRange: range)
        }
        for layer in searchColorLayers {
            for range in layer.ranges where range.length > 0 && NSMaxRange(range) <= length {
                layoutManager.addTemporaryAttribute(
                    .backgroundColor, value: layer.color.withAlphaComponent(0.38),
                    forCharacterRange: range)
            }
        }
        for marker in temporaryColorMarkers where marker.range.length > 0 && NSMaxRange(marker.range) <= length {
            layoutManager.addTemporaryAttribute(
                .backgroundColor, value: Self.markerDisplayColor(marker.color).withAlphaComponent(0.45),
                forCharacterRange: marker.range)
        }
        textView.needsDisplay = true
    }

    private static func markerDisplayColor(_ color: MarkerColor) -> NSColor {
        switch color {
        case .red: return .systemRed
        case .yellow: return .systemYellow
        case .blue: return .systemBlue
        case .green: return .systemGreen
        }
    }

    var searchHighlightRangesForTesting: [NSRange] { temporarySearchHighlightRanges }

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
            temporarySearchHighlightRanges.removeAll()
            searchMarkerOffsets.removeAll()
            if isViewLoaded {
                loadDoc()
                refreshColorOverlays()
            }
            cursorHistory.removeAll()
        }
    }
    /// Secondary panes must own their TextKit storage. A single
    /// `NSTextStorage` cannot safely be attached to two layout managers;
    /// shared-document panes synchronize through the controller delegate.
    var reusesDocumentTextStorage = true

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
        textView.setAccessibilityLabel(AppLocalization.string("editor.accessibility"))
        // Force TextKit 1 so layout manager APIs work reliably
        textView.layoutManager?.delegate = foldLayoutDelegate

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
        lineNumbers?.isBinaryMode = document?.isBinaryMode ?? false
        DispatchQueue.main.async { [weak self] in
            self?.textView.window?.makeFirstResponder(self?.textView)
        }
    }

    @objc private func boundsChanged(_ n: Notification) {
        lineNumbers?.needsDisplay = true
        scheduleScrollHighlight()
        if !suppressScrollCallback {
            let origin = scrollView.contentView.bounds.origin
            onScroll?(origin)
            onCrossDocumentScroll?(origin)
        }
    }

    func setLinkedScrollOffset(_ origin: NSPoint) {
        suppressScrollCallback = true
        scrollView.contentView.scroll(to: origin)
        scrollView.reflectScrolledClipView(scrollView.contentView)
        suppressScrollCallback = false
    }

    func synchronizeSharedDocumentState() {
        if let document, textView.string != document.content, let storage = textView.textStorage {
            let selections = textView.selectedRanges
            suppressTextChange = true
            storage.replaceCharacters(
                in: NSRange(location: 0, length: storage.length), with: document.content)
            suppressTextChange = false
            let length = (document.content as NSString).length
            textView.selectedRanges = selections.map {
                let range = $0.rangeValue
                let location = min(range.location, length)
                return NSValue(range: NSRange(
                    location: location,
                    length: min(range.length, max(0, length - location))))
            }
        }
        lineIndex = LineIndex(textView.string)
        refreshBookmarkGutter()
        lineNumbers?.needsDisplay = true
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
        cursorHistory.removeAll()
        document?.cachedTextStorage = nil
        loadDoc()
    }

    private func loadDoc() {
        guard let doc = document else { return }
        syntaxHighlightCoordinator.cancel()

        let lm = textView.layoutManager!
        suppressTextChange = true

        if reusesDocumentTextStorage, let cached = doc.cachedTextStorage {
            lm.replaceTextStorage(cached)
        } else {
            let para = textView.defaultParagraphStyle ?? NSParagraphStyle.default
            let ts = NSTextStorage(string: doc.content, attributes: [
                .font: Theme.editorFont,
                .foregroundColor: Theme.foreground,
                .paragraphStyle: para,
            ])
            lm.replaceTextStorage(ts)
            if reusesDocumentTextStorage { doc.cachedTextStorage = ts }
        }

        suppressTextChange = false
        lineIndex = LineIndex(textView.string)
        configureLargeFileEditingMode()
        applyTextLayoutOrientation()
        lineNumbers?.isBinaryMode = doc.isBinaryMode
        let cursor = NSRange(location: min(doc.cursorPosition, lm.textStorage?.length ?? 0), length: 0)
        setSelections([cursor], primaryRange: cursor)
        refreshBookmarkGutter()
        lineNumbers?.needsDisplay = true
        applyPreferences(preferences)
        deferredHighlightVisible()
        refreshCompletionDictionaries()
    }

    func refreshBookmarkGutter() {
        lineNumbers?.bookmarkOffsets = document?.bookmarks.offsets ?? []
        lineNumbers?.editMarkOffsets = document?.editMarks.offsets ?? []
        var colors = Dictionary(uniqueKeysWithValues: searchMarkerOffsets.map { ($0, MarkerColor.yellow) })
        for (offset, color) in document?.colorMarkers.markers ?? [:] { colors[offset] = color }
        lineNumbers?.markerColors = colors
        refreshFolding()
    }

    func redraw() {
        textView.needsDisplay = true
        lineNumbers?.needsDisplay = true
    }

    func showSearchMarkers(_ ranges: [NSRange]) {
        let ns = textView.string as NSString
        searchMarkerOffsets = Set(ranges.map {
            ns.lineRange(for: NSRange(location: min($0.location, ns.length), length: 0)).location
        })
        refreshBookmarkGutter()
    }

    func toggleDelimitedTableMode() {
        guard let storage = textView.textStorage else { return }
        isTableMode.toggle()
        let fullRange = NSRange(location: 0, length: storage.length)
        storage.removeAttribute(.kern, range: fullRange)
        guard isTableMode else { return }
        let model = DelimitedTableModel(text: textView.string)
        let space = " ".size(withAttributes: [.font: preferredEditorFont]).width
        for row in model.rows {
            for column in row.indices.dropLast() {
                let delimiterOffset = NSMaxRange(row[column].range)
                guard delimiterOffset < storage.length else { continue }
                let padding = max(1, model.columnWidths[column] - row[column].value.count + 2)
                storage.addAttribute(.kern, value: space * CGFloat(padding),
                                     range: NSRange(location: delimiterOffset, length: 1))
            }
        }
    }
    var searchMarkerOffsetsForTesting: Set<Int> { searchMarkerOffsets }
    var foldRegionCountForTesting: Int { lineNumbers?.foldRegions.count ?? 0 }
    var showsFoldMarginForTesting: Bool { lineNumbers?.showsFoldControls ?? false }
    func toggleFoldMargin() { lineNumbers?.showsFoldControls.toggle() }

    func copyCurrentWord() { selectCurrentWord(); textView.copy(nil) }
    func cutCurrentWord() { selectCurrentWord(); textView.cut(nil) }
    func deleteCurrentWord() { selectCurrentWord(); textView.delete(nil) }
    func copyCurrentLine() { selectCurrentLine(); textView.copy(nil) }
    func cutCurrentLine() { selectCurrentLine(); textView.cut(nil) }
    func cutToLineEnd() { deleteToLineEnd(copyingToClipboard: true) }
    func clearUndoBuffer() { textView.undoManager?.removeAllActions() }

    private func deleteToLineEnd(copyingToClipboard: Bool) {
        let ns = textView.string as NSString
        let cursor = min(textView.selectedRange().location, ns.length)
        let line = ns.lineRange(for: NSRange(location: cursor, length: 0))
        var end = NSMaxRange(line)
        while end > cursor, CharacterSet.newlines.contains(UnicodeScalar(ns.character(at: end - 1))!) { end -= 1 }
        textView.setSelectedRange(NSRange(location: cursor, length: max(0, end - cursor)))
        if copyingToClipboard { textView.cut(nil) } else { textView.delete(nil) }
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
        let wrapMode = resolvedWrapMode()
        let font = preferredEditorFont
        let paragraph = NSMutableParagraphStyle()
        paragraph.tabStops = []
        paragraph.defaultTabInterval = " ".size(withAttributes: [.font: font]).width
            * CGFloat(max(1, effectivePreferences.tabWidth))
        textView.font = font
        textView.textColor = editorForeground
        textView.backgroundColor = isHighContrast ? .black
            : Self.color(hex: document?.fileTypeProfile?.settings.appearance?.backgroundHex) ?? Theme.background
        textView.selectedTextAttributes[.backgroundColor] = Self.color(
            hex: document?.fileTypeProfile?.settings.appearance?.selectionHex) ?? Theme.selection
        (textView as? MaruTextView)?.invisibleCharacters = document?.largeFileMode.usesReducedFeatures == true
            ? .none : preferences.invisibleCharacters
        (textView as? MaruTextView)?.freeCursorEnabled = preferences.freeCursorEnabled
        textView.defaultParagraphStyle = paragraph
        textView.typingAttributes[.font] = font
        textView.typingAttributes[.paragraphStyle] = paragraph
        if let storage = textView.textStorage, storage.length > 0 {
            storage.addAttributes([.font: font, .paragraphStyle: paragraph],
                                  range: NSRange(location: 0, length: storage.length))
        }
        lineNumbers?.setVisible(effectivePreferences.showLineNumbers)
        if !isColumnLayout {
            textView.textContainer?.widthTracksTextView = wrapMode == .window
            textView.isHorizontallyResizable = wrapMode != .window
            scrollView.hasHorizontalScroller = wrapMode != .window
        }
        let spelling = document?.fileTypeProfile?.settings.spelling ?? SpellingSettings()
        textView.isContinuousSpellCheckingEnabled = document?.spellCheckingOverride ?? spelling.enabled
        textView.isAutomaticSpellingCorrectionEnabled = spelling.enabled && spelling.automaticCorrection
        if !isColumnLayout {
            switch wrapMode {
            case .window:
                textView.textContainer?.containerSize.width = scrollView.contentSize.width
            case .fixed, .maximum:
                let columns = wrapMode == .maximum ? 8_000 : effectiveWrapColumn
                let cell = ("0" as NSString).size(withAttributes: [.font: font]).width
                let padding = textView.textContainer?.lineFragmentPadding ?? 0
                textView.textContainer?.containerSize.width = cell * CGFloat(columns) + padding * 2
            case .none:
                textView.textContainer?.containerSize.width = CGFloat.greatestFiniteMagnitude
            }
        }
        for (index, column) in columnTextViews.enumerated() {
            configureColumnTextView(column, number: index + 2)
        }
        applyHighContrast(isHighContrast)
        lineNumbers?.needsDisplay = true
    }

    private static func color(hex: String?) -> NSColor? {
        guard var value = hex?.trimmingCharacters(in: .whitespacesAndNewlines), value.hasPrefix("#") else { return nil }
        value.removeFirst()
        guard value.count == 6, let rgb = Int(value, radix: 16) else { return nil }
        return NSColor(
            red: CGFloat((rgb >> 16) & 0xff) / 255,
            green: CGFloat((rgb >> 8) & 0xff) / 255,
            blue: CGFloat(rgb & 0xff) / 255, alpha: 1)
    }

    func showCompletions() {
        let settings = document?.fileTypeProfile?.settings.completion ?? CompletionSettings()
        let range = textView.rangeForUserCompletion
        guard range.location != NSNotFound, NSMaxRange(range) <= (textView.string as NSString).length else { return }
        let prefix = (textView.string as NSString).substring(with: range)
        let words = WordCompletionEngine.candidates(
            prefix: prefix, document: document?.content ?? textView.string,
            dictionaries: completionDictionaries, settings: settings).map(\.word)
        guard !words.isEmpty else { delegate?.editorCompletionMessage(self, message: "No completions"); return }
        switch settings.presentation {
        case .list: textView.complete(nil)
        case .tooltip:
            textView.toolTip = words.prefix(8).joined(separator: "  ")
        case .status:
            delegate?.editorCompletionMessage(self, message: words.prefix(5).joined(separator: "  "))
        }
    }

    private func refreshCompletionDictionaries() {
        let paths = document?.fileTypeProfile?.settings.completion?.dictionaryPaths ?? []
        completionDictionaries = []
        guard !paths.isEmpty else { return }
        Task { [weak self] in
            let loaded = await Task.detached { CompletionDictionaryLoader.load(paths: paths) }.value
            guard self?.document?.fileTypeProfile?.settings.completion?.dictionaryPaths == paths else { return }
            self?.completionDictionaries = loaded
        }
    }

    var effectiveWrapLines: Bool {
        resolvedWrapMode() != .none
    }

    var effectiveWrapMode: WrapMode { resolvedWrapMode() }
    var effectiveWrapColumn: Int {
        max(20, min(8_000, document?.fileTypeProfile?.settings.wrapColumn ?? preferences.wrapColumn))
    }

    private func resolvedWrapMode() -> WrapMode {
        if document?.largeFileMode.usesReducedFeatures == true { return .none }
        if let override = document?.wrapLinesOverride {
            return override ? (preferences.wrapMode == .none ? .window : preferences.wrapMode) : .none
        }
        if let profileMode = document?.fileTypeProfile?.settings.wrapMode { return profileMode }
        if let profile = document?.fileTypeProfile { return profile.settings.wrapLines ? .window : .none }
        return preferences.wrapLines ? preferences.wrapMode : .none
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
        textView.isEditable = !(document?.isEditingDisabled ?? false)
        textView.undoManager?.levelsOfUndo = document?.largeFileMode.usesReducedFeatures == true ? 20 : 0
    }

    var effectiveTabWidth: Int {
        document?.tabWidthOverride ?? document?.fileTypeProfile?.settings.tabWidth
            ?? preferences.tabWidth
    }

    var isVerticalLayout: Bool { document?.isVerticalLayout == true }
    var isColumnLayout: Bool { document?.isColumnLayout == true }
    var columnCountForTesting: Int { 1 + columnTextViews.count }

    func toggleVerticalLayout() {
        guard let document else { return }
        if document.isColumnLayout { setColumnLayout(false) }
        document.isVerticalLayout.toggle()
        let ranges = selectionSet.ranges
        applyTextLayoutOrientation()
        applyPreferences(preferences)
        setSelections(ranges, primaryRange: ranges.first)
    }

    func toggleColumnLayout() {
        guard let document else { return }
        setColumnLayout(!document.isColumnLayout)
    }

    /// TextKit flows one shared text storage through the containers in order,
    /// giving the classic newspaper-style continuous column layout rather than
    /// duplicating the document in an ordinary editor split.
    private func setColumnLayout(_ enabled: Bool) {
        guard let document, isViewLoaded, let layoutManager = textView.layoutManager else { return }
        document.isColumnLayout = enabled
        if enabled {
            document.isVerticalLayout = false
            applyTextLayoutOrientation()
            let viewport = scrollView.contentSize
            let columnWidth = max(260, min(520, (viewport.width - 18) / 2))
            let columnHeight = max(240, viewport.height)
            let estimatedCharactersPerColumn = max(1, Int(columnWidth / 8) * Int(columnHeight / 18))
            let count = max(2, min(64,
                Int(ceil(Double(max(1, (textView.string as NSString).length))
                    / Double(estimatedCharactersPerColumn)))))
            let gap: CGFloat = 18
            let host = FlippedView(frame: NSRect(
                x: 0, y: 0, width: CGFloat(count) * columnWidth + CGFloat(count - 1) * gap,
                height: columnHeight))
            textView.removeFromSuperview()
            textView.frame = NSRect(x: 0, y: 0, width: columnWidth, height: columnHeight)
            textView.autoresizingMask = []
            textView.isVerticallyResizable = false
            textView.isHorizontallyResizable = false
            textView.textContainer?.widthTracksTextView = false
            textView.textContainer?.heightTracksTextView = false
            textView.textContainer?.containerSize = NSSize(width: columnWidth, height: columnHeight)
            host.addSubview(textView)
            columnTextViews.removeAll()
            for index in 1..<count {
                let container = NSTextContainer(size: NSSize(width: columnWidth, height: columnHeight))
                layoutManager.addTextContainer(container)
                let column = NSTextView(frame: NSRect(
                    x: CGFloat(index) * (columnWidth + gap), y: 0,
                    width: columnWidth, height: columnHeight), textContainer: container)
                configureColumnTextView(column, number: index + 1)
                host.addSubview(column)
                columnTextViews.append(column)
            }
            columnLayoutHost = host
            scrollView.documentView = host
            scrollView.hasHorizontalScroller = true
            scrollView.hasVerticalScroller = false
        } else {
            columnTextViews.forEach { $0.removeFromSuperview() }
            while layoutManager.textContainers.count > 1 {
                layoutManager.removeTextContainer(at: layoutManager.textContainers.count - 1)
            }
            columnTextViews.removeAll()
            textView.removeFromSuperview()
            textView.isVerticallyResizable = true
            textView.isHorizontallyResizable = true
            textView.autoresizingMask = [.width]
            scrollView.documentView = textView
            columnLayoutHost = nil
            scrollView.hasVerticalScroller = true
            applyPreferences(preferences)
        }
        textView.needsDisplay = true
    }

    private func configureColumnTextView(_ column: NSTextView, number: Int) {
        column.isEditable = textView.isEditable
        column.isSelectable = true
        column.allowsUndo = true
        column.isRichText = false
        column.backgroundColor = textView.backgroundColor
        column.textColor = textView.textColor
        column.font = textView.font
        column.insertionPointColor = textView.insertionPointColor
        column.selectedTextAttributes = textView.selectedTextAttributes
        column.textContainerInset = textView.textContainerInset
        column.defaultParagraphStyle = textView.defaultParagraphStyle
        column.typingAttributes = textView.typingAttributes
        column.delegate = self
        column.setAccessibilityLabel(AppLocalization.string("editor.columnAccessibility", [number]))
    }

    private func applyTextLayoutOrientation() {
        let orientation: NSLayoutManager.TextLayoutOrientation = isVerticalLayout ? .vertical : .horizontal
        guard textView.layoutOrientation != orientation else { return }
        textView.setLayoutOrientation(orientation)
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        textView.needsLayout = true
        textView.needsDisplay = true
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
        textView.backgroundColor = enabled ? .black
            : Self.color(hex: document?.fileTypeProfile?.settings.appearance?.backgroundHex) ?? Theme.background
        textView.textColor = editorForeground
        textView.insertionPointColor = enabled ? .white : Theme.cursor
        textView.selectedTextAttributes = [
            .backgroundColor: enabled ? NSColor.white
                : Self.color(hex: document?.fileTypeProfile?.settings.appearance?.selectionHex) ?? Theme.selection,
            .foregroundColor: enabled ? NSColor.black : editorForeground,
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
        if replacement.isEmpty, range.length > 0,
           NSMaxRange(range) <= (textView.string as NSString).length {
            rememberDeletedText((textView.string as NSString).substring(with: range))
        }
        if lineIndex.utf16Length != (textView.string as NSString).length {
            lineIndex = LineIndex(textView.string)
        }
        if suppressAutoIndent || replacement != "\n" {
            document?.bookmarks.applyEdit(range: range, replacement: replacement)
            document?.colorMarkers.applyEdit(range: range, replacement: replacement)
            applySearchColorLayerEdit(range: range, replacement: replacement)
            applyTemporaryColorMarkerEdit(range: range, replacement: replacement)
            if let document {
                document.editMarks.recordEdit(
                    range: range, replacement: replacement, in: textView.string as NSString)
            }
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
            document?.colorMarkers.applyEdit(range: range, replacement: replacement)
            applySearchColorLayerEdit(range: range, replacement: replacement)
            applyTemporaryColorMarkerEdit(range: range, replacement: replacement)
            if let document {
                document.editMarks.recordEdit(range: range, replacement: replacement, in: ns)
            }
            lineIndex.applyEdit(range: range, replacement: replacement)
            return true
        }

        suppressAutoIndent = true
        textView.insertText("\n" + indent, replacementRange: range)
        suppressAutoIndent = false
        return false
    }

    func rememberDeletedText(_ text: String) {
        guard !text.isEmpty else { return }
        deletedTextHistory.removeAll { $0 == text }
        deletedTextHistory.insert(text, at: 0)
        if deletedTextHistory.count > 30 {
            deletedTextHistory.removeLast(deletedTextHistory.count - 30)
        }
    }

    @discardableResult
    func restoreLastDeletedText() -> Bool {
        guard let text = deletedTextHistory.first else { return false }
        batchReplace(selectionSet.ranges, with: text)
        return true
    }

    func textView(
        _ textView: NSTextView, completions words: [String],
        forPartialWordRange charRange: NSRange, indexOfSelectedItem index: UnsafeMutablePointer<Int>?
    ) -> [String] {
        guard NSMaxRange(charRange) <= (textView.string as NSString).length else { return words }
        let settings = document?.fileTypeProfile?.settings.completion ?? CompletionSettings()
        let prefix = (textView.string as NSString).substring(with: charRange)
        return WordCompletionEngine.candidates(
            prefix: prefix, document: document?.content ?? textView.string,
            dictionaries: completionDictionaries, settings: settings).map(\.word)
    }

    func textDidChange(_ n: Notification) {
        guard !suppressTextChange else { return }
        if scheduleCompositionCommitAfterUnmarkIfNeeded() { return }
        let content = textView.string
        if lineIndex.utf16Length != (content as NSString).length {
            lineIndex = LineIndex(content)
        }
        document?.bookmarks.normalize(in: content as NSString)
        document?.colorMarkers.normalize(in: content as NSString)
        document?.editMarks.normalize(in: content as NSString)
        refreshColorOverlays()
        document?.content = content
        document?.markModified()
        refreshFolding()
        delegate?.editorTextDidChange(self)
        lineNumbers?.needsDisplay = true
        lineNumbers?.bookmarkOffsets = document?.bookmarks.offsets ?? []
        refreshBookmarkGutter()
        emitCursor()

        if document?.fileTypeProfile?.settings.completion?.automatic == true,
           textView.rangeForUserCompletion.length >= 3 {
            showCompletions()
        }

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
        let documentLength = (document.content as NSString).length
        var isolatedRanges: [NSRange] = []
        if let range = partialEditRange {
            if range.location > 0 { isolatedRanges.append(NSRange(location: 0, length: range.location)) }
            let end = NSMaxRange(range)
            if end < documentLength {
                isolatedRanges.append(NSRange(location: end, length: documentLength - end))
            }
        }
        if document.fileTypeProfile?.settings.foldingEnabled == false {
            foldLayoutDelegate.collapsedRanges = isolatedRanges
            lineNumbers?.foldRegions = []
            lineNumbers?.collapsedFoldIDs = []
            layoutManager.invalidateLayout(
                forCharacterRange: NSRange(location: 0, length: documentLength),
                actualCharacterRange: nil)
            return
        }
        let outline = OutlineModel(
            text: document.content, language: document.language,
            customRules: document.fileTypeProfile?.settings.outlineRules ?? [])
        document.foldModel.rebuild(text: document.content, symbols: outline.symbols)
        foldLayoutDelegate.collapsedRanges = document.foldModel.collapsedRanges() + isolatedRanges
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

    /// Isolates the outline symbol containing the insertion point without
    /// replacing or copying document text. The next symbol at the same or a
    /// shallower level closes the editable region.
    @discardableResult
    func beginPartialOutlineEditing() -> Bool {
        guard let document else { return false }
        let outline = OutlineModel(
            text: document.content, language: document.language,
            customRules: document.fileTypeProfile?.settings.outlineRules ?? [])
        let index = LineIndex(document.content)
        let cursorLine = index.line(atUTF16Offset: textView.selectedRange().location)
        guard let symbolIndex = outline.symbols.lastIndex(where: { $0.line <= cursorLine }) else {
            return false
        }
        let symbol = outline.symbols[symbolIndex]
        let boundary = outline.symbols.dropFirst(symbolIndex + 1).first { $0.level <= symbol.level }
        guard let start = index.utf16Offset(forLine: symbol.line) else { return false }
        let end = boundary.flatMap { index.utf16Offset(forLine: $0.line) } ?? index.utf16Length
        partialEditRange = NSRange(location: start, length: max(0, end - start))
        textView.setSelectedRange(NSRange(location: start, length: 0))
        refreshFolding()
        return true
    }

    func endPartialOutlineEditing() {
        partialEditRange = nil
        refreshFolding()
    }

    var collapsedFoldCountForTesting: Int { document?.foldModel.collapsedRegionIDs.count ?? 0 }

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
        let previous = selectionSet.primaryRange.location
        selectionSet.update(
            ranges: textView.selectedRanges.map(\.rangeValue),
            primaryRange: textView.selectedRange()
        )
        recordCursorTransition(from: previous, to: selectionSet.primaryRange.location)
        lineNumbers?.needsDisplay = true
        emitCursor()
    }

    private func recordCursorTransition(from previous: Int, to current: Int) {
        guard !isRestoringCursorHistory, previous != current else { return }
        if cursorHistory.last != previous { cursorHistory.append(previous) }
        if cursorHistory.count > 100 { cursorHistory.removeFirst(cursorHistory.count - 100) }
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
        setInputMode(document.inputMode == .insert ? .overwrite : .insert)
    }

    func setInputMode(_ mode: EditorInputMode) {
        guard let document else { return }
        document.inputMode = mode
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

    func emitCursor() {
        let sel = textView.selectedRange()
        let ns = textView.string as NSString
        let offset = min(sel.location, ns.length)
        let tabWidth = document?.fileTypeProfile?.settings.tabWidth ?? preferences.tabWidth
        let line = lineIndex.line(atUTF16Offset: offset)
        let displayColumn = lineIndex.displayColumn(
            atUTF16Offset: offset, in: textView.string, tabWidth: tabWidth)
        let ranges = textView.selectedRanges.map(\.rangeValue)
        let boxWidth: Int? = columnSelectionDimensions.map { dimensions in
            guard !preferredEditorFont.isFixedPitch else { return dimensions.width }
            let cellWidth = max(1, ("0" as NSString).size(
                withAttributes: [.font: preferredEditorFont]).width)
            return Int(ceil(CGFloat(dimensions.width) * cellWidth))
        }
        delegate?.editorCursorMoved(self, state: EditorCursorState(
            lineNumber: line + 1,
            displayColumn: displayColumn + 1,
            utf16Offset: offset,
            selectedCharacterCount: ranges.reduce(0) {
                $0 + ns.substring(with: NSIntersectionRange(
                    $1, NSRange(location: 0, length: ns.length))).count
            },
            selectedUTF16Length: ranges.reduce(0) { $0 + $1.length },
            selectionRangeCount: ranges.count,
            selectedLineCount: ranges.reduce(0) { count, range in
                guard range.length > 0 else { return count }
                return count + ns.substring(with: NSIntersectionRange(
                    range, NSRange(location: 0, length: ns.length)))
                    .reduce(1) { $1 == "\n" ? $0 + 1 : $0 }
            },
            boxWidth: boxWidth,
            boxHeight: columnSelectionDimensions?.height,
            boxWidthIsPixels: columnSelectionDimensions != nil && !preferredEditorFont.isFixedPitch
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
