import AppKit
import MaruEditCore

@MainActor
protocol GrepPanelDelegate: AnyObject {
    func grepPanel(_ panel: GrepPanel, didSubmit request: GrepRequest)
    func grepPanel(_ panel: GrepPanel, didRequestReplace request: GrepRequest, replacement: String)
    func grepPanelDidCancel(_ panel: GrepPanel)
    /// The panel needs a folder chosen; the host owns the open panel so
    /// this stays free of file-picker presentation.
    func grepPanelDidRequestFolderChoice(_ panel: GrepPanel)
}

/// Collects the parameters for a Grep run (ROADMAP.md M3-06). Presented as
/// a sheet, never a modal `runModal()` — a blocking modal loop is exactly
/// what makes a UI untestable and unresponsive.
@MainActor
final class GrepPanel: NSObject, NSTextFieldDelegate {
    weak var delegate: GrepPanelDelegate?

    let window: NSWindow

    let patternField = MultilineTextField()
    let replacementField = MultilineTextField()
    private let folderField = NSTextField()
    private let includeField = NSTextField()
    private let excludeField = NSTextField()
    private let caseButton = NSButton(checkboxWithTitle: "Case sensitive", target: nil, action: nil)
    private let wordButton = NSButton(checkboxWithTitle: "Whole word", target: nil, action: nil)
    private let regexButton = NSButton(checkboxWithTitle: "Regular expression", target: nil, action: nil)
    private let hiddenButton = NSButton(checkboxWithTitle: "Include hidden files", target: nil, action: nil)
    var searchHistory: [String] = []
    private var searchHistoryIndex: Int?

    override init() {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 340),
            styleMask: [.titled, .resizable], backing: .buffered, defer: true
        )
        super.init()
        window.title = "Find in Folder"
        window.minSize = NSSize(width: 520, height: 340)
        buildUI()
    }

    // MARK: - Build

    private func buildUI() {
        func label(_ text: String) -> NSTextField {
            let field = NSTextField(labelWithString: text)
            field.font = Theme.uiFont
            field.alignment = .right
            field.setContentHuggingPriority(.defaultHigh, for: .horizontal)
            return field
        }
        func input(_ field: NSTextField, _ placeholder: String, _ accessibility: String) -> NSTextField {
            field.placeholderString = placeholder
            field.font = Theme.uiFont
            field.delegate = self
            field.setAccessibilityLabel(accessibility)
            return field
        }

        let chooseButton = NSButton(title: "Choose…", target: self, action: #selector(chooseFolder))
        chooseButton.setAccessibilityLabel("Choose search folder")
        let searchButton = NSButton(title: "Search", target: self, action: #selector(submit))
        searchButton.keyEquivalent = "\r"
        let replaceButton = NSButton(title: "Preview Replace…", target: self, action: #selector(previewReplace))
        let cancelButton = NSButton(title: "Cancel", target: self, action: #selector(cancel))
        cancelButton.keyEquivalent = "\u{1b}"

        let folderRow = NSStackView(views: [
            input(folderField, "Folder to search", "Search folder"), chooseButton,
        ])
        folderRow.orientation = .horizontal

        let options = NSStackView(views: [caseButton, wordButton, regexButton, hiddenButton])
        options.orientation = .vertical
        options.alignment = .leading
        options.spacing = 4

        let grid = NSGridView(views: [
            [label("Find:"), input(patternField, "Text or pattern", "Search pattern")],
            [label("Replace:"), input(replacementField, "Replacement text", "Replacement text")],
            [label("In:"), folderRow],
            [label("Include:"), input(includeField, "*.swift, *.txt (optional)", "Include file patterns")],
            [label("Exclude:"), input(excludeField, ".build, node_modules (optional)", "Exclude file patterns")],
            [label("Options:"), options],
        ])
        grid.translatesAutoresizingMaskIntoConstraints = false
        grid.column(at: 1).width = 380
        patternField.visibleLines = 3
        replacementField.visibleLines = 3

        let buttons = NSStackView(views: [cancelButton, replaceButton, searchButton])
        buttons.orientation = .horizontal
        buttons.translatesAutoresizingMaskIntoConstraints = false

        let content = NSView()
        content.addSubview(grid)
        content.addSubview(buttons)
        NSLayoutConstraint.activate([
            grid.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
            grid.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            grid.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor, constant: -20),
            buttons.topAnchor.constraint(equalTo: grid.bottomAnchor, constant: 20),
            buttons.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            buttons.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -20),
        ])
        window.contentView = content
        window.initialFirstResponder = patternField
    }

    // MARK: - State

    var folderURL: URL? {
        get { folderField.stringValue.isEmpty ? nil : URL(fileURLWithPath: folderField.stringValue) }
        set { folderField.stringValue = newValue?.path ?? "" }
    }

    /// Pre-fills from the Find Bar so switching from "find here" to "find
    /// everywhere" doesn't mean retyping the pattern and options.
    func prefill(with query: SearchQuery?) {
        guard let query = query else { return }
        if !query.pattern.isEmpty { patternField.stringValue = query.pattern }
        caseButton.state = query.isCaseSensitive ? .on : .off
        wordButton.state = query.wholeWord ? .on : .off
        regexButton.state = query.mode == .regularExpression ? .on : .off
    }

    /// The request described by the panel's current input, or `nil` when
    /// there is nothing to search for or nowhere to search.
    var currentRequest: GrepRequest? {
        let pattern = patternField.currentEditor()?.string ?? patternField.stringValue
        guard !pattern.isEmpty, let folder = folderURL else { return nil }
        return GrepRequest(
            query: SearchQuery(
                pattern: pattern,
                mode: regexButton.state == .on ? .regularExpression : .literal,
                isCaseSensitive: caseButton.state == .on,
                wholeWord: wordButton.state == .on,
                wraps: false,
                scope: .document
            ),
            roots: [folder],
            includeGlobs: Self.globList(from: includeField),
            excludeGlobs: Self.globList(from: excludeField),
            includesHiddenFiles: hiddenButton.state == .on
        )
    }

    /// Accepts commas or whitespace between patterns, since users type
    /// both and neither is a legal glob character in practice.
    static func globList(from field: NSTextField) -> [String] {
        let raw = field.currentEditor()?.string ?? field.stringValue
        return raw
            .split(whereSeparator: { $0 == "," || $0.isWhitespace })
            .map(String.init)
    }

    // MARK: - Actions

    @objc private func submit() {
        guard let request = currentRequest else { return }
        delegate?.grepPanel(self, didSubmit: request)
    }

    @objc private func previewReplace() {
        guard let request = currentRequest else { return }
        let replacement = replacementField.currentEditor()?.string ?? replacementField.stringValue
        delegate?.grepPanel(self, didRequestReplace: request, replacement: replacement)
    }

    @objc private func cancel() {
        delegate?.grepPanelDidCancel(self)
    }

    @objc private func chooseFolder() {
        delegate?.grepPanelDidRequestFolderChoice(self)
    }

    func focusPattern() {
        window.makeFirstResponder(patternField)
    }

    func controlTextDidChange(_ notification: Notification) {
        if (notification.object as? NSTextField) === patternField { searchHistoryIndex = nil }
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        guard control === patternField else { return false }
        if commandSelector == #selector(NSResponder.moveUp(_:)) {
            guard !searchHistory.isEmpty else { return false }
            searchHistoryIndex = min((searchHistoryIndex ?? -1) + 1, searchHistory.count - 1)
        } else if commandSelector == #selector(NSResponder.moveDown(_:)) {
            guard let current = searchHistoryIndex else { return false }
            searchHistoryIndex = current == 0 ? nil : current - 1
        } else {
            return false
        }
        patternField.stringValue = searchHistoryIndex.map { searchHistory[$0] } ?? ""
        patternField.currentEditor()?.selectAll(nil)
        return true
    }
}
