import AppKit
import MaruEditCore

protocol OutputPaneViewDelegate: AnyObject {
    /// The user chose a result — by double-click, Return, or the Enter key.
    func outputPane(_ pane: OutputPaneView, didActivate match: GrepMatch)
    func outputPaneDidRequestRerun(_ pane: OutputPaneView)
    func outputPaneDidRequestClose(_ pane: OutputPaneView)
    func outputPaneDidRequestCancel(_ pane: OutputPaneView)
    func outputPaneDidRequestSave(_ pane: OutputPaneView, text: String)
}

/// A structured list of Grep results, not an editable text view
/// (ROADMAP.md 11.3: "Grep results should use a structured Output Pane
/// rather than pretending to be an ordinary editable document").
///
/// M6-06 turns this into the shared pane for macro and external-command
/// output; the channel concept isn't built yet, but keeping the view free
/// of Grep-specific logic beyond its row model is what makes that possible.
final class OutputPaneView: NSView, NSTableViewDataSource, NSTableViewDelegate {
    weak var delegate: OutputPaneViewDelegate?

    private let scrollView = NSScrollView()
    private let tableView = ResultTableView()
    private let statusLabel = NSTextField(labelWithString: "")
    private let rerunButton = NSButton()
    private let saveButton = NSButton()
    private let cancelButton = NSButton()
    private let closeButton = NSButton()

    private(set) var matches: [GrepMatch] = []
    private var summary = GrepSummary()
    private var searchPattern = ""
    private(set) var isRunning = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = Theme.sidebarBg.cgColor
        buildUI()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Build

    private func buildUI() {
        setAccessibilityLabel("Search results")

        func style(_ button: NSButton, _ title: String, _ action: Selector, _ label: String) {
            button.title = title
            button.bezelStyle = .inline
            button.isBordered = false
            button.font = Theme.uiFontSmall
            button.contentTintColor = Theme.tabText
            button.target = self
            button.action = action
            button.translatesAutoresizingMaskIntoConstraints = false
            button.setAccessibilityLabel(label)
        }
        style(rerunButton, "Rerun", #selector(rerun), "Rerun this search")
        style(saveButton, "Save…", #selector(save), "Save these results")
        style(cancelButton, "Stop", #selector(cancel), "Stop the running search")
        style(closeButton, "✕", #selector(close), "Close search results")
        cancelButton.isHidden = true

        statusLabel.font = Theme.uiFontSmall
        statusLabel.textColor = Theme.statusText
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.setAccessibilityLabel("Search summary")

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("result"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.rowHeight = 18
        tableView.backgroundColor = Theme.sidebarBg
        tableView.gridStyleMask = []
        tableView.allowsMultipleSelection = false
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.doubleAction = #selector(activateSelectedRow)
        tableView.menu = buildContextMenu()
        tableView.onActivate = { [weak self] in self?.activateSelectedRow() }
        tableView.setAccessibilityLabel("Search results list")

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        addSubview(scrollView)
        addSubview(statusLabel)
        addSubview(rerunButton)
        addSubview(saveButton)
        addSubview(cancelButton)
        addSubview(closeButton)

        NSLayoutConstraint.activate([
            statusLabel.topAnchor.constraint(equalTo: topAnchor, constant: 5),
            statusLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),

            closeButton.centerYAnchor.constraint(equalTo: statusLabel.centerYAnchor),
            closeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),

            saveButton.centerYAnchor.constraint(equalTo: statusLabel.centerYAnchor),
            saveButton.trailingAnchor.constraint(equalTo: closeButton.leadingAnchor, constant: -12),

            rerunButton.centerYAnchor.constraint(equalTo: statusLabel.centerYAnchor),
            rerunButton.trailingAnchor.constraint(equalTo: saveButton.leadingAnchor, constant: -12),

            cancelButton.centerYAnchor.constraint(equalTo: statusLabel.centerYAnchor),
            cancelButton.trailingAnchor.constraint(equalTo: rerunButton.leadingAnchor, constant: -12),

            scrollView.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 4),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    private func buildContextMenu() -> NSMenu {
        let menu = NSMenu()
        for (title, action) in [
            ("Copy Path", #selector(copyPathAction)),
            ("Copy Line", #selector(copyLineAction)),
            ("Reveal in Finder", #selector(revealInFinder)),
        ] {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            menu.addItem(item)
        }
        return menu
    }

    // MARK: - Content

    func beginRun(pattern: String) {
        searchPattern = pattern
        matches = []
        summary = GrepSummary()
        isRunning = true
        cancelButton.isHidden = false
        statusLabel.stringValue = "Searching for “\(pattern)”…"
        tableView.reloadData()
    }

    func append(_ match: GrepMatch) {
        matches.append(match)
        tableView.reloadData()
        // The first result is selected so Return works immediately,
        // without the user having to arrow into the list first.
        if matches.count == 1 {
            tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        }
    }

    func updateProgress(scannedFiles: Int) {
        guard isRunning else { return }
        statusLabel.stringValue = "Searching… \(scannedFiles) file\(scannedFiles == 1 ? "" : "s"), \(matches.count) match\(matches.count == 1 ? "" : "es")"
    }

    func finish(_ summary: GrepSummary) {
        self.summary = summary
        isRunning = false
        cancelButton.isHidden = true
        statusLabel.stringValue = GrepResultFormatter.describe(summary)
        statusLabel.setAccessibilityValue(statusLabel.stringValue)
        tableView.reloadData()
    }

    /// Moves keyboard focus into the results list, so a keyboard-only user
    /// can arrow through results as soon as a search finishes.
    func focusResults() {
        window?.makeFirstResponder(tableView)
        if tableView.selectedRow < 0, !matches.isEmpty {
            tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        }
    }

    var selectedMatch: GrepMatch? {
        let row = tableView.selectedRow
        guard row >= 0, row < matches.count else { return nil }
        return matches[row]
    }

    var resultsText: String {
        GrepResultFormatter.plainText(matches: matches, summary: summary, pattern: searchPattern)
    }

    // MARK: - Actions

    @objc private func rerun() { delegate?.outputPaneDidRequestRerun(self) }
    @objc private func close() { delegate?.outputPaneDidRequestClose(self) }
    @objc private func cancel() { delegate?.outputPaneDidRequestCancel(self) }
    @objc private func save() { delegate?.outputPaneDidRequestSave(self, text: resultsText) }

    @objc private func activateSelectedRow() {
        guard let match = selectedMatch else { return }
        delegate?.outputPane(self, didActivate: match)
    }

    @objc private func copyPathAction() { copyPath(to: .general) }
    @objc private func copyLineAction() { copyLine(to: .general) }

    /// Pasteboard passed in so tests don't have to write to the user's
    /// real clipboard to check what Copy produces.
    func copyPath(to pasteboard: NSPasteboard) {
        guard let match = selectedMatch else { return }
        pasteboard.clearContents()
        pasteboard.setString(match.url.path, forType: .string)
    }

    func copyLine(to pasteboard: NSPasteboard) {
        guard let match = selectedMatch else { return }
        pasteboard.clearContents()
        pasteboard.setString(GrepResultFormatter.line(for: match), forType: .string)
    }

    @objc private func revealInFinder() {
        guard let match = selectedMatch else { return }
        NSWorkspace.shared.activateFileViewerSelecting([match.url])
    }

    // MARK: - NSTableViewDataSource / Delegate

    func numberOfRows(in tableView: NSTableView) -> Int { matches.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < matches.count else { return nil }
        let identifier = NSUserInterfaceItemIdentifier("ResultCell")
        let cell = (tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView)
            ?? Self.makeCell(identifier: identifier)
        cell.textField?.attributedStringValue = Self.attributedRow(for: matches[row])
        cell.setAccessibilityLabel(Self.accessibilityDescription(for: matches[row]))
        return cell
    }

    private static func makeCell(identifier: NSUserInterfaceItemIdentifier) -> NSTableCellView {
        let cell = NSTableCellView()
        cell.identifier = identifier
        let field = NSTextField(labelWithString: "")
        field.font = Theme.uiFontSmall
        field.lineBreakMode = .byTruncatingTail
        field.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(field)
        cell.textField = field
        NSLayoutConstraint.activate([
            field.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 10),
            field.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -10),
            field.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }

    /// `path:line:` in a dimmer color, then the matching line with the
    /// match itself highlighted — so a result is scannable without opening
    /// the file.
    static func attributedRow(for match: GrepMatch) -> NSAttributedString {
        let location = NSMutableAttributedString(
            string: "\(match.relativePath):\(match.line): ",
            attributes: [.foregroundColor: Theme.statusText, .font: Theme.uiFontSmall]
        )
        let preview = NSMutableAttributedString(
            string: match.preview,
            attributes: [.foregroundColor: Theme.sidebarText, .font: Theme.uiFontSmall]
        )
        let highlight = NSRange(
            location: match.previewRange.location,
            length: min(match.previewRange.length, max(0, (match.preview as NSString).length - match.previewRange.location))
        )
        if highlight.length > 0 {
            preview.addAttributes(
                [.foregroundColor: Theme.keyword, .font: NSFont.boldSystemFont(ofSize: 11)],
                range: highlight
            )
        }
        location.append(preview)
        return location
    }

    static func accessibilityDescription(for match: GrepMatch) -> String {
        "\(match.relativePath), line \(match.line), column \(match.column): \(match.preview)"
    }
}

/// Adds Return/Enter activation to `NSTableView`, which otherwise only
/// responds to double-clicks — the difference between a results list a
/// keyboard user can use and one they can't (ROADMAP.md M3-06 acceptance).
private final class ResultTableView: NSTableView {
    var onActivate: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        if KeyGesture(event: event)?.key == "enter" {
            onActivate?()
            return
        }
        super.keyDown(with: event)
    }
}
