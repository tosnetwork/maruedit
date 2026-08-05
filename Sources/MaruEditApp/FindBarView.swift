import AppKit
import MaruEditCore

enum FindBarAction {
    case findNext
    case findPrevious
    /// Re-run on every keystroke and option change.
    case incremental
    case replace
    case replaceAll
}

enum FindOption { case caseSensitive, wholeWord, regularExpression, fuzzy }

/// The Find Bar is input and presentation only (ROADMAP.md M3-02): it
/// builds a `SearchQuery` and asks its delegate to carry it out, then
/// displays whatever the delegate reports back. It never touches text,
/// never matches anything itself, and knows nothing about `NSTextView`.
@MainActor
protocol FindBarDelegate: AnyObject {
    @discardableResult
    func findBar(_ bar: FindBarView, perform action: FindBarAction, query: SearchQuery) -> FindOutcome
    func findBarDidDismiss(_ bar: FindBarView)
}

final class FindBarView: NSView, NSTextFieldDelegate {
    weak var delegate: FindBarDelegate?

    let searchField  = MultilineTextField()
    private var returnDirection: SearchDirection = .next
    let replaceField = MultilineTextField()
    private let matchLabel  = NSTextField(labelWithString: "")
    private let caseBtn     = NSButton()
    private let wordBtn     = NSButton()
    private let regexBtn    = NSButton()
    private let fuzzyBtn    = NSButton()
    private let prevBtn     = NSButton()
    private let nextBtn     = NSButton()
    private let replBtn     = NSButton()
    private let replAllBtn  = NSButton()
    private let closeBtn    = NSButton()
    private let expandBtn   = NSButton()
    private let resizeBtn   = NSButton()
    private var showReplace  = false
    private var replaceRow: NSView!
    private var searchRowHeight: NSLayoutConstraint!
    private var replaceRowHeight: NSLayoutConstraint!
    private var inputsExpanded = false

    /// Most-recent-first history, supplied by the owner and recalled with
    /// Up/Down in the matching field. The bar only presents it; persistence
    /// and limits belong to the owner (ROADMAP.md M3-07).
    var searchHistory: [String] = []
    var replacementHistory: [String] = []
    private var searchHistoryIndex: Int?
    private var replacementHistoryIndex: Int?

    override var intrinsicContentSize: NSSize {
        let rowHeight: CGFloat = inputsExpanded ? 72 : 34
        return NSSize(width: NSView.noIntrinsicMetric, height: showReplace ? rowHeight * 2 : rowHeight)
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = Theme.findBarBg.cgColor
        buildUI()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Build

    private func buildUI() {
        func style(_ button: NSButton, title: String, tip: String, action: Selector, accessibility: String) {
            button.title = title
            button.bezelStyle = .inline
            button.isBordered = false
            button.font = Theme.uiFontSmall
            button.contentTintColor = Theme.tabText
            button.toolTip = tip
            button.target = self
            button.action = action
            button.translatesAutoresizingMaskIntoConstraints = false
            button.setAccessibilityLabel(accessibility)
        }

        searchField.placeholderString = "Find"
        searchField.font = Theme.uiFontSmall
        searchField.focusRingType = .none
        searchField.delegate = self
        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.setAccessibilityLabel("Find")
        searchField.setAccessibilityHelp("Type to search. Return finds the next match, Shift-Return the previous one, Escape closes the find bar. Up and Down recall earlier searches.")

        replaceField.placeholderString = "Replace"
        replaceField.font = Theme.uiFontSmall
        replaceField.focusRingType = .none
        replaceField.delegate = self
        replaceField.translatesAutoresizingMaskIntoConstraints = false
        replaceField.setAccessibilityLabel("Replace with")
        replaceField.setAccessibilityHelp("Replacement text. Return replaces the current match; Replace All is in the Find menu. Up and Down recall earlier replacements.")

        matchLabel.font = Theme.uiFontSmall
        matchLabel.textColor = Theme.statusText
        matchLabel.translatesAutoresizingMaskIntoConstraints = false
        matchLabel.setAccessibilityLabel("Search status")

        style(expandBtn, title: "⇅", tip: "Toggle Replace", action: #selector(toggleReplace), accessibility: "Toggle replace row")
        style(resizeBtn, title: "↕", tip: "Expand multiline fields", action: #selector(toggleInputSize), accessibility: "Resize search fields")
        style(caseBtn, title: "Aa", tip: "Case Sensitive (⌥⌘C)", action: #selector(toggleCase), accessibility: "Case sensitive")
        style(wordBtn, title: "W", tip: "Whole Word (⌥⌘W)", action: #selector(toggleWholeWord), accessibility: "Whole word")
        style(regexBtn, title: ".*", tip: "Regular Expression (⌥⌘R)", action: #selector(toggleRegex), accessibility: "Regular expression")
        style(fuzzyBtn, title: "≋", tip: "Fuzzy Width Search (⌥⌘Z)", action: #selector(toggleFuzzy), accessibility: "Fuzzy width search")
        style(prevBtn, title: "▲", tip: "Previous (⇧⌘G)", action: #selector(doPrev), accessibility: "Find previous")
        style(nextBtn, title: "▼", tip: "Next (⌘G)", action: #selector(doNext), accessibility: "Find next")
        style(closeBtn, title: "✕", tip: "Close (Esc)", action: #selector(doClose), accessibility: "Close find bar")
        style(replBtn, title: "Replace", tip: "Replace", action: #selector(doReplace), accessibility: "Replace this match")
        style(replAllBtn, title: "All", tip: "Replace All", action: #selector(doReplaceAll), accessibility: "Replace all matches")

        // The option toggles are momentary buttons whose `state` the
        // action methods flip by hand. A `.pushOnPushOff` button toggles
        // its own state before sending the action, so the handler's flip
        // would cancel it out and the option would never change.

        let searchRow = NSView()
        searchRow.translatesAutoresizingMaskIntoConstraints = false
        for v: NSView in [expandBtn, searchField, matchLabel, caseBtn, wordBtn, regexBtn, fuzzyBtn, prevBtn, nextBtn, resizeBtn, closeBtn] {
            searchRow.addSubview(v)
        }

        replaceRow = NSView()
        replaceRow.translatesAutoresizingMaskIntoConstraints = false
        replaceRow.isHidden = true
        for v: NSView in [replaceField, replBtn, replAllBtn] {
            replaceRow.addSubview(v)
        }

        addSubview(searchRow)
        addSubview(replaceRow)

        searchRowHeight = searchRow.heightAnchor.constraint(equalToConstant: 34)
        replaceRowHeight = replaceRow.heightAnchor.constraint(equalToConstant: 32)
        NSLayoutConstraint.activate([
            searchRow.topAnchor.constraint(equalTo: topAnchor),
            searchRow.leadingAnchor.constraint(equalTo: leadingAnchor),
            searchRow.trailingAnchor.constraint(equalTo: trailingAnchor),
            searchRowHeight,

            expandBtn.leadingAnchor.constraint(equalTo: searchRow.leadingAnchor, constant: 6),
            expandBtn.centerYAnchor.constraint(equalTo: searchRow.centerYAnchor),
            expandBtn.widthAnchor.constraint(equalToConstant: 24),

            searchField.leadingAnchor.constraint(equalTo: expandBtn.trailingAnchor, constant: 4),
            searchField.centerYAnchor.constraint(equalTo: searchRow.centerYAnchor),
            searchField.widthAnchor.constraint(greaterThanOrEqualToConstant: 180),

            matchLabel.leadingAnchor.constraint(equalTo: searchField.trailingAnchor, constant: 8),
            matchLabel.centerYAnchor.constraint(equalTo: searchRow.centerYAnchor),

            caseBtn.leadingAnchor.constraint(equalTo: matchLabel.trailingAnchor, constant: 8),
            caseBtn.centerYAnchor.constraint(equalTo: searchRow.centerYAnchor),

            wordBtn.leadingAnchor.constraint(equalTo: caseBtn.trailingAnchor, constant: 4),
            wordBtn.centerYAnchor.constraint(equalTo: searchRow.centerYAnchor),

            regexBtn.leadingAnchor.constraint(equalTo: wordBtn.trailingAnchor, constant: 4),
            regexBtn.centerYAnchor.constraint(equalTo: searchRow.centerYAnchor),

            fuzzyBtn.leadingAnchor.constraint(equalTo: regexBtn.trailingAnchor, constant: 4),
            fuzzyBtn.centerYAnchor.constraint(equalTo: searchRow.centerYAnchor),

            prevBtn.leadingAnchor.constraint(equalTo: fuzzyBtn.trailingAnchor, constant: 8),
            prevBtn.centerYAnchor.constraint(equalTo: searchRow.centerYAnchor),

            nextBtn.leadingAnchor.constraint(equalTo: prevBtn.trailingAnchor, constant: 4),
            nextBtn.centerYAnchor.constraint(equalTo: searchRow.centerYAnchor),

            resizeBtn.trailingAnchor.constraint(equalTo: closeBtn.leadingAnchor, constant: -6),
            resizeBtn.centerYAnchor.constraint(equalTo: searchRow.centerYAnchor),
            nextBtn.trailingAnchor.constraint(lessThanOrEqualTo: resizeBtn.leadingAnchor, constant: -6),

            closeBtn.trailingAnchor.constraint(equalTo: searchRow.trailingAnchor, constant: -8),
            closeBtn.centerYAnchor.constraint(equalTo: searchRow.centerYAnchor),

            replaceRow.topAnchor.constraint(equalTo: searchRow.bottomAnchor),
            replaceRow.leadingAnchor.constraint(equalTo: leadingAnchor),
            replaceRow.trailingAnchor.constraint(equalTo: trailingAnchor),
            replaceRowHeight,

            replaceField.leadingAnchor.constraint(equalTo: searchField.leadingAnchor),
            replaceField.centerYAnchor.constraint(equalTo: replaceRow.centerYAnchor),
            replaceField.widthAnchor.constraint(equalTo: searchField.widthAnchor),

            replBtn.leadingAnchor.constraint(equalTo: replaceField.trailingAnchor, constant: 8),
            replBtn.centerYAnchor.constraint(equalTo: replaceRow.centerYAnchor),

            replAllBtn.leadingAnchor.constraint(equalTo: replBtn.trailingAnchor, constant: 6),
            replAllBtn.centerYAnchor.constraint(equalTo: replaceRow.centerYAnchor),
        ])

        setAccessibilityLabel("Find bar")
    }

    @objc private func toggleInputSize() {
        setInputsExpanded(!inputsExpanded)
    }

    func setInputsExpanded(_ expanded: Bool) {
        inputsExpanded = expanded
        searchField.visibleLines = inputsExpanded ? 3 : 1
        replaceField.visibleLines = inputsExpanded ? 3 : 1
        searchRowHeight.constant = inputsExpanded ? 72 : 34
        replaceRowHeight.constant = inputsExpanded ? 72 : 32
        invalidateIntrinsicContentSize()
        superview?.needsLayout = true
    }

    var areInputsExpandedForTesting: Bool { inputsExpanded }

    /// Handles the option toggles' ⌥⌘ shortcuts directly instead of
    /// assigning them as `NSButton.keyEquivalent`s, which were verified
    /// live not to fire for these buttons. Changing options has to work
    /// for a keyboard-only user (ROADMAP.md M3-02 acceptance) — it decides
    /// what the current search means.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard !isHidden else { return super.performKeyEquivalent(with: event) }
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        guard modifiers == [.command, .option],
              let key = event.charactersIgnoringModifiers?.lowercased()
        else { return super.performKeyEquivalent(with: event) }

        switch key {
        case "c": toggleCase(); return true
        case "w": toggleWholeWord(); return true
        case "r": toggleRegex(); return true
        case "z": toggleFuzzy(); return true
        default: return super.performKeyEquivalent(with: event)
        }
    }

    func activate(direction: SearchDirection = .next) {
        returnDirection = direction
        window?.makeFirstResponder(searchField)
        searchField.currentEditor()?.selectAll(nil)
    }

    func setSearchPattern(_ pattern: String) {
        searchField.stringValue = pattern
        searchField.currentEditor()?.string = pattern
    }

    // MARK: - Query

    /// The query described by the bar's current input and toggles. Every
    /// action sends this same value, so an option change can never apply
    /// to Find but not to Replace All.
    var currentQuery: SearchQuery {
        SearchQuery(
            pattern: text(of: searchField),
            replacement: text(of: replaceField),
            mode: regexBtn.state == .on ? .regularExpression : .literal,
            isCaseSensitive: caseBtn.state == .on,
            wholeWord: wordBtn.state == .on,
            isFuzzy: fuzzyBtn.state == .on,
            wraps: true,
            scope: .document
        )
    }

    /// A field being edited holds its in-progress text in the shared field
    /// editor; `stringValue` only catches up when editing ends. Reading it
    /// directly would run Replace All against a stale — often empty —
    /// replacement, which was observed live.
    private func text(of field: NSTextField) -> String {
        field.currentEditor()?.string ?? field.stringValue
    }

    /// Shows the replace row (used when Find is opened via a Replace
    /// command rather than a plain Find).
    func setReplaceRowVisible(_ visible: Bool) {
        guard showReplace != visible else { return }
        toggleReplace()
    }

    var isReplaceRowVisible: Bool { showReplace }
    func isOptionEnabled(_ option: FindOption) -> Bool {
        switch option {
        case .caseSensitive: caseBtn.state == .on
        case .wholeWord: wordBtn.state == .on
        case .regularExpression: regexBtn.state == .on
        case .fuzzy: fuzzyBtn.state == .on
        }
    }

    func toggleOption(_ option: FindOption) {
        switch option {
        case .caseSensitive: toggleCase()
        case .wholeWord: toggleWholeWord()
        case .regularExpression: toggleRegex()
        case .fuzzy: toggleFuzzy()
        }
    }

    // MARK: - Actions

    @objc private func doNext() { run(.findNext) }
    @objc private func doPrev() { run(.findPrevious) }
    @objc private func doReplace() { run(.replace) }
    @objc private func doReplaceAll() { run(.replaceAll) }

    @objc private func doClose() {
        isHidden = true
        delegate?.findBarDidDismiss(self)
    }

    @objc func toggleCase() {
        caseBtn.state = caseBtn.state == .on ? .off : .on
        optionDidChange()
    }

    @objc func toggleWholeWord() {
        wordBtn.state = wordBtn.state == .on ? .off : .on
        optionDidChange()
    }

    @objc func toggleRegex() {
        regexBtn.state = regexBtn.state == .on ? .off : .on
        optionDidChange()
    }

    @objc func toggleFuzzy() {
        fuzzyBtn.state = fuzzyBtn.state == .on ? .off : .on
        optionDidChange()
    }

    /// Momentary buttons don't draw their `state`, so an enabled option
    /// has to announce itself some other way — otherwise a keyboard user
    /// who pressed ⌥⌘C has no way to tell whether it took effect.
    private func optionDidChange() {
        for button in [caseBtn, wordBtn, regexBtn, fuzzyBtn] {
            button.contentTintColor = button.state == .on ? Theme.accent : Theme.tabText
            button.setAccessibilityValue(button.state == .on ? "on" : "off")
        }
        run(.incremental)
    }

    @objc private func toggleReplace() {
        showReplace.toggle()
        replaceRow.isHidden = !showReplace
        invalidateIntrinsicContentSize()
        superview?.needsLayout = true
    }

    private func run(_ action: FindBarAction) {
        guard let outcome = delegate?.findBar(self, perform: action, query: currentQuery) else { return }
        present(outcome, for: action)
    }

    private func present(_ outcome: FindOutcome, for action: FindBarAction) {
        if let message = outcome.errorMessage {
            matchLabel.textColor = .systemRed
            matchLabel.stringValue = message
            matchLabel.toolTip = message
            return
        }
        matchLabel.textColor = Theme.statusText
        matchLabel.toolTip = nil

        if action == .replaceAll {
            let n = outcome.replacementCount
            matchLabel.stringValue = "Replaced \(n)"
            matchLabel.setAccessibilityValue("Replaced \(n) \(n == 1 ? "match" : "matches")")
            return
        }
        if searchField.stringValue.isEmpty {
            matchLabel.stringValue = ""
            matchLabel.setAccessibilityValue("")
            return
        }
        if outcome.totalMatches == 0 {
            matchLabel.stringValue = "No results"
            matchLabel.setAccessibilityValue("No results")
            return
        }
        if let index = outcome.currentIndex {
            matchLabel.stringValue = "\(index) of \(outcome.totalMatches)"
            matchLabel.setAccessibilityValue("Match \(index) of \(outcome.totalMatches)")
        } else {
            let n = outcome.totalMatches
            matchLabel.stringValue = "\(n) match\(n == 1 ? "" : "es")"
            matchLabel.setAccessibilityValue("\(n) \(n == 1 ? "match" : "matches")")
        }
    }

    /// The status text currently shown next to the search field ("3 of
    /// 12", "No results", or a regex diagnostic). Read-only presentation
    /// state, exposed so tests can assert what the user would see.
    var statusText: String { matchLabel.stringValue }

    /// Runs an action the owner initiated (e.g. the Replace All menu
    /// command) against the bar's current input, and displays the result.
    func perform(_ action: FindBarAction) {
        run(action)
    }

    /// Exposed for the owner to refresh the status line after an action it
    /// initiated itself (e.g. the Find Next menu command while the bar is
    /// open).
    func showOutcome(_ outcome: FindOutcome) {
        present(outcome, for: .findNext)
    }

    // MARK: - History recall

    private func recallHistory(_ history: [String], index: inout Int?, into field: NSTextField, offset: Int) -> Bool {
        guard !history.isEmpty else { return false }
        let next: Int?
        switch (index, offset) {
        case (nil, 1): next = 0
        case (nil, -1): next = nil
        case (let current?, _):
            let candidate = current + offset
            next = candidate < 0 ? nil : min(candidate, history.count - 1)
        default: next = nil
        }
        index = next
        field.stringValue = next.map { history[$0] } ?? ""
        field.currentEditor()?.selectAll(nil)
        return true
    }

    // MARK: - NSTextFieldDelegate

    func controlTextDidChange(_ n: Notification) {
        guard (n.object as? NSTextField) === searchField else { return }
        // Typing invalidates the recall position: the field no longer
        // shows a history entry.
        searchHistoryIndex = nil
        run(.incremental)
    }

    func control(_ control: NSControl, textView tv: NSTextView, doCommandBy sel: Selector) -> Bool {
        let isSearchField = control === searchField

        if sel == #selector(insertNewline(_:)) {
            run(isSearchField
                ? (NSEvent.modifierFlags.contains(.shift)
                    ? (returnDirection == .next ? .findPrevious : .findNext)
                    : (returnDirection == .next ? .findNext : .findPrevious))
                : .replace)
            return true
        }
        if sel == #selector(cancelOperation(_:)) { doClose(); return true }
        if sel == #selector(moveUp(_:)) {
            return isSearchField
                ? recallHistory(searchHistory, index: &searchHistoryIndex, into: searchField, offset: 1)
                : recallHistory(replacementHistory, index: &replacementHistoryIndex, into: replaceField, offset: 1)
        }
        if sel == #selector(moveDown(_:)) {
            return isSearchField
                ? recallHistory(searchHistory, index: &searchHistoryIndex, into: searchField, offset: -1)
                : recallHistory(replacementHistory, index: &replacementHistoryIndex, into: replaceField, offset: -1)
        }
        return false
    }
}
