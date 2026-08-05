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

    var keyboardFocusableViews: [NSView] {
        var views: [NSView] = [searchField, expandBtn, resizeBtn, caseBtn, wordBtn,
                               regexBtn, fuzzyBtn, prevBtn, nextBtn, closeBtn]
        if showReplace {
            views.insert(replaceField, at: 1)
            views.append(contentsOf: [replBtn, replAllBtn])
        }
        return views.filter { !$0.isHidden && (($0 as? NSControl)?.isEnabled ?? true) }
    }

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

        searchField.placeholderString = AppLocalization.string("find.placeholder")
        searchField.font = Theme.uiFontSmall
        searchField.focusRingType = .none
        searchField.delegate = self
        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.setAccessibilityLabel(AppLocalization.string("find.accessibility.search"))
        searchField.setAccessibilityHelp(AppLocalization.string("find.help.search"))

        replaceField.placeholderString = AppLocalization.string("find.replacePlaceholder")
        replaceField.font = Theme.uiFontSmall
        replaceField.focusRingType = .none
        replaceField.delegate = self
        replaceField.translatesAutoresizingMaskIntoConstraints = false
        replaceField.setAccessibilityLabel(AppLocalization.string("find.accessibility.replace"))
        replaceField.setAccessibilityHelp(AppLocalization.string("find.help.replace"))

        matchLabel.font = Theme.uiFontSmall
        matchLabel.textColor = Theme.statusText
        matchLabel.translatesAutoresizingMaskIntoConstraints = false
        matchLabel.setAccessibilityLabel(AppLocalization.string("find.accessibility.status"))

        style(expandBtn, title: "⇅", tip: AppLocalization.string("find.tip.toggleReplace"), action: #selector(toggleReplace), accessibility: AppLocalization.string("find.tip.toggleReplace"))
        style(resizeBtn, title: "↕", tip: AppLocalization.string("find.tip.expand"), action: #selector(toggleInputSize), accessibility: AppLocalization.string("find.tip.expand"))
        style(caseBtn, title: "Aa", tip: AppLocalization.string("find.tip.case"), action: #selector(toggleCase), accessibility: AppLocalization.string("find.tip.case"))
        style(wordBtn, title: "W", tip: AppLocalization.string("find.tip.word"), action: #selector(toggleWholeWord), accessibility: AppLocalization.string("find.tip.word"))
        style(regexBtn, title: ".*", tip: AppLocalization.string("find.tip.regex"), action: #selector(toggleRegex), accessibility: AppLocalization.string("find.tip.regex"))
        style(fuzzyBtn, title: "≋", tip: AppLocalization.string("find.tip.fuzzy"), action: #selector(toggleFuzzy), accessibility: AppLocalization.string("find.tip.fuzzy"))
        style(prevBtn, title: "▲", tip: AppLocalization.string("find.tip.previous"), action: #selector(doPrev), accessibility: AppLocalization.string("find.tip.previous"))
        style(nextBtn, title: "▼", tip: AppLocalization.string("find.tip.next"), action: #selector(doNext), accessibility: AppLocalization.string("find.tip.next"))
        style(closeBtn, title: "✕", tip: AppLocalization.string("find.tip.close"), action: #selector(doClose), accessibility: AppLocalization.string("find.tip.close"))
        style(replBtn, title: AppLocalization.string("find.replace"), tip: AppLocalization.string("find.replace"), action: #selector(doReplace), accessibility: AppLocalization.string("find.replace"))
        style(replAllBtn, title: AppLocalization.string("find.allShort"), tip: AppLocalization.string("find.replaceAll"), action: #selector(doReplaceAll), accessibility: AppLocalization.string("find.replaceAll"))

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

        setAccessibilityLabel(AppLocalization.string("find.accessibility.bar"))
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
            matchLabel.setAccessibilityValue(AppLocalization.string("find.replacedMatches", [n]))
            return
        }
        if searchField.stringValue.isEmpty {
            matchLabel.stringValue = ""
            matchLabel.setAccessibilityValue("")
            return
        }
        if outcome.totalMatches == 0 {
            matchLabel.stringValue = AppLocalization.string("find.noResults")
            matchLabel.setAccessibilityValue(AppLocalization.string("find.noResults"))
            return
        }
        if let index = outcome.currentIndex {
            matchLabel.stringValue = "\(index) of \(outcome.totalMatches)"
            matchLabel.setAccessibilityValue("Match \(index) of \(outcome.totalMatches)")
        } else {
            let n = outcome.totalMatches
            matchLabel.stringValue = "\(n) match\(n == 1 ? "" : "es")"
            matchLabel.setAccessibilityValue(AppLocalization.string("find.matches", [n]))
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
