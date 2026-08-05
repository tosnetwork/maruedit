import AppKit
import MaruEditCore

@MainActor
protocol OutputPaneViewDelegate: AnyObject {
    /// The user chose a result — by double-click, Return, or the Enter key.
    func outputPane(_ pane: OutputPaneView, didActivate match: GrepMatch)
    func outputPane(_ pane: OutputPaneView, didActivate location: OutputLocation)
    func outputPaneDidRequestRerun(_ pane: OutputPaneView)
    func outputPaneDidRequestClose(_ pane: OutputPaneView)
    func outputPaneDidRequestCancel(_ pane: OutputPaneView)
    func outputPaneDidRequestSave(_ pane: OutputPaneView, text: String)
}

/// The bounded shared presentation for structured Grep results, macro
/// errors, and external-process channels.
final class OutputPaneView: NSView, NSTableViewDataSource, NSTableViewDelegate {
    private enum ContentMode { case grep, externalCommand }
    private enum GrepRow { case match(GrepMatch), output(OutputEntry) }
    weak var delegate: OutputPaneViewDelegate?

    private let scrollView = NSScrollView()
    private let tableView = ResultTableView()
    private let statusLabel = NSTextField(labelWithString: "")
    private let rerunButton = NSButton()
    private let copyButton = NSButton()
    private let clearButton = NSButton()
    private let saveButton = NSButton()
    private let cancelButton = NSButton()
    private let closeButton = NSButton()

    private(set) var matches: [GrepMatch] = []
    private var grepRows: [GrepRow] = []
    private var externalLines: [String] = []
    private var externalPending: [Bool: Data] = [:]
    private var outputBuffer = SharedOutputBuffer()
    private var outputBaseURL: URL?
    private var contentMode: ContentMode = .grep
    private var summary = GrepSummary()
    private var searchPattern = ""
    private(set) var isRunning = false

    var keyboardFocusableViews: [NSView] {
        [tableView, rerunButton, copyButton, clearButton, saveButton, cancelButton, closeButton]
            .filter { !$0.isHidden && $0.isEnabled }
    }

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
        setAccessibilityLabel(AppLocalization.string("output.title"))

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
        style(rerunButton, AppLocalization.string("output.rerun"), #selector(rerun), AppLocalization.string("output.rerun"))
        style(copyButton, AppLocalization.string("output.copy"), #selector(copyAll), AppLocalization.string("output.copy"))
        style(clearButton, AppLocalization.string("output.clear"), #selector(clearOutput), AppLocalization.string("output.clear"))
        style(saveButton, AppLocalization.string("output.save"), #selector(save), AppLocalization.string("output.save"))
        style(cancelButton, AppLocalization.string("output.stop"), #selector(cancel), AppLocalization.string("output.stop"))
        style(closeButton, "✕", #selector(close), AppLocalization.string("output.close"))
        cancelButton.isHidden = true

        statusLabel.font = Theme.uiFontSmall
        statusLabel.textColor = Theme.statusText
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.setAccessibilityLabel(AppLocalization.string("output.summary"))

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
        tableView.setAccessibilityLabel(AppLocalization.string("output.results"))

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        addSubview(scrollView)
        addSubview(statusLabel)
        addSubview(rerunButton)
        addSubview(copyButton)
        addSubview(clearButton)
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

            clearButton.centerYAnchor.constraint(equalTo: statusLabel.centerYAnchor),
            clearButton.trailingAnchor.constraint(equalTo: saveButton.leadingAnchor, constant: -12),

            copyButton.centerYAnchor.constraint(equalTo: statusLabel.centerYAnchor),
            copyButton.trailingAnchor.constraint(equalTo: clearButton.leadingAnchor, constant: -12),

            rerunButton.centerYAnchor.constraint(equalTo: statusLabel.centerYAnchor),
            rerunButton.trailingAnchor.constraint(equalTo: copyButton.leadingAnchor, constant: -12),

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
            (AppLocalization.string("output.copyPath"), #selector(copyPathAction)),
            (AppLocalization.string("output.copyLine"), #selector(copyLineAction)),
            (AppLocalization.string("output.reveal"), #selector(revealInFinder)),
        ] {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            menu.addItem(item)
        }
        return menu
    }

    // MARK: - Content

    func beginRun(pattern: String) {
        contentMode = .grep
        outputBuffer.clear()
        rerunButton.isHidden = false
        searchPattern = pattern
        matches = []; grepRows = []
        summary = GrepSummary()
        isRunning = true
        cancelButton.isHidden = false
        statusLabel.stringValue = AppLocalization.string("output.searchingFor", [pattern])
        tableView.reloadData()
    }

    func beginExternalCommand(name: String, workingDirectory: URL? = nil) {
        contentMode = .externalCommand
        matches = []; externalLines = []; externalPending = [:]; outputBuffer.clear(); isRunning = true
        outputBaseURL = workingDirectory
        rerunButton.isHidden = true; cancelButton.isHidden = false
        statusLabel.stringValue = AppLocalization.string("output.running", [name])
        tableView.reloadData()
    }

    func beginOperation(_ title: String) {
        contentMode = .externalCommand; matches = []; grepRows = []; externalLines = []
        externalPending = [:]; outputBuffer.clear(); isRunning = true
        rerunButton.isHidden = true; cancelButton.isHidden = false
        statusLabel.stringValue = title; tableView.reloadData()
    }

    func appendSystem(_ message: String, severity: OutputSeverity = .info) {
        outputBuffer.append(message, channel: .system, severity: severity,
                            location: OutputLocationParser.parse(message))
        externalLines = outputBuffer.entries.map(Self.formatted); tableView.reloadData()
    }

    func finishOperation(_ title: String) {
        isRunning = false; cancelButton.isHidden = true; statusLabel.stringValue = title
    }

    func appendExternal(_ data: Data, isError: Bool) {
        var pending = externalPending[isError, default: Data()]
        pending.append(data)
        while let newline = pending.firstIndex(of: 0x0A) {
            var line = pending[..<newline]
            if line.last == 0x0D { line = line.dropLast() }
            appendOutputLine(String(decoding: line, as: UTF8.self), isError: isError)
            pending.removeSubrange(...newline)
        }
        externalPending[isError] = pending
        tableView.reloadData()
        if !externalLines.isEmpty { tableView.scrollRowToVisible(externalLines.count - 1) }
    }

    func finishExternal(status: Int32, cancelled: Bool) {
        for isError in [false, true] {
            guard let pending = externalPending[isError], !pending.isEmpty else { continue }
            appendOutputLine(String(decoding: pending, as: UTF8.self), isError: isError)
        }
        externalPending.removeAll(); tableView.reloadData()
        isRunning = false; cancelButton.isHidden = true
        statusLabel.stringValue = cancelled ? AppLocalization.string("output.cancelled")
            : AppLocalization.string("output.exited", [status])
        statusLabel.setAccessibilityValue(statusLabel.stringValue)
    }

    func appendMacroError(name: String, message: String, timestamp: Date) {
        if contentMode == .grep || isRunning {
            contentMode = .externalCommand; matches = []; externalLines = []; externalPending = [:]
            outputBuffer.clear(); rerunButton.isHidden = true; cancelButton.isHidden = true
        }
        for (index, line) in message.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let text = index == 0 ? "\(name): \(line)" : String(line)
            outputBuffer.append(
                text, channel: .macro, severity: .error, timestamp: timestamp,
                location: OutputLocationParser.parse(String(line)))
        }
        externalLines = outputBuffer.entries.map(Self.formatted)
        statusLabel.stringValue = AppLocalization.string("output.macroError", [name])
        tableView.reloadData()
    }

    private func appendOutputLine(_ line: String, isError: Bool) {
        outputBuffer.append(
            line, channel: isError ? .standardError : .standardOutput,
            severity: isError ? .error : .info,
            location: OutputLocationParser.parse(line, relativeTo: outputBaseURL))
        externalLines = outputBuffer.entries.map(Self.formatted)
    }

    func append(_ match: GrepMatch) {
        outputBuffer.append(
            "\(match.relativePath):\(match.line):\(match.column): \(match.preview)",
            channel: .grep,
            location: OutputLocation(url: match.url, line: match.line, column: match.column))
        if matches.count >= 9_999 { matches.removeFirst() }
        matches.append(match)
        if grepRows.count >= 9_999 { grepRows.removeFirst() }
        grepRows.append(.match(match))
        tableView.reloadData()
        // The first result is selected so Return works immediately,
        // without the user having to arrow into the list first.
        if matches.count == 1 {
            tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        }
    }

    func appendSkipped(_ url: URL, reason: SkipReason) {
        let entry = outputBuffer.append(
            "\(url.path): \(reason.describedReason)", channel: .grep, severity: .warning,
            location: OutputLocation(url: url, line: 1))
        if grepRows.count >= 9_999 { grepRows.removeFirst() }
        grepRows.append(.output(entry)); tableView.reloadData()
    }

    func updateProgress(scannedFiles: Int) {
        guard isRunning else { return }
        statusLabel.stringValue = AppLocalization.string("output.progress", [scannedFiles, matches.count])
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
        guard row >= 0, row < grepRows.count, case .match(let match) = grepRows[row] else { return nil }
        return match
    }

    @discardableResult
    func activateAdjacentGrepResult(forward: Bool) -> Bool {
        let rows = grepRows.indices.filter {
            if case .match = grepRows[$0] { return true }
            return false
        }
        guard !rows.isEmpty else { return false }
        let current = tableView.selectedRow
        let row = forward
            ? rows.first(where: { $0 > current }) ?? rows.first
            : rows.last(where: { $0 < current }) ?? rows.last
        guard let row else { return false }
        tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        tableView.scrollRowToVisible(row)
        activateSelectedRow()
        return true
    }

    var resultsText: String {
        if contentMode == .externalCommand { return externalLines.joined(separator: "\n") }
        return outputBuffer.entries.map(Self.formatted).joined(separator: "\n")
    }

    // MARK: - Actions

    @objc private func rerun() { delegate?.outputPaneDidRequestRerun(self) }
    @objc private func close() { delegate?.outputPaneDidRequestClose(self) }
    @objc private func cancel() { delegate?.outputPaneDidRequestCancel(self) }
    @objc private func save() { delegate?.outputPaneDidRequestSave(self, text: resultsText) }
    @objc private func copyAll() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(resultsText, forType: .string)
    }
    @objc private func clearOutput() {
        if isRunning { delegate?.outputPaneDidRequestCancel(self) }
        matches.removeAll(); grepRows.removeAll(); externalLines.removeAll(); externalPending.removeAll(); outputBuffer.clear()
        isRunning = false; cancelButton.isHidden = true
        statusLabel.stringValue = AppLocalization.string("output.cleared")
        tableView.reloadData()
    }

    @objc private func activateSelectedRow() {
        if let match = selectedMatch { delegate?.outputPane(self, didActivate: match); return }
        if let location = selectedOutputLocation { delegate?.outputPane(self, didActivate: location) }
    }

    @objc private func copyPathAction() { copyPath(to: .general) }
    @objc private func copyLineAction() { copyLine(to: .general) }

    /// Pasteboard passed in so tests don't have to write to the user's
    /// real clipboard to check what Copy produces.
    func copyPath(to pasteboard: NSPasteboard) {
        guard let url = selectedMatch?.url ?? selectedOutputLocation?.url else { return }
        pasteboard.clearContents()
        pasteboard.setString(url.path, forType: .string)
    }

    func copyLine(to pasteboard: NSPasteboard) {
        let value: String
        if let match = selectedMatch { value = GrepResultFormatter.line(for: match) }
        else if contentMode == .externalCommand, tableView.selectedRow >= 0,
                tableView.selectedRow < externalLines.count { value = externalLines[tableView.selectedRow] }
        else { return }
        pasteboard.clearContents()
        pasteboard.setString(value, forType: .string)
    }

    @objc private func revealInFinder() {
        guard let url = selectedMatch?.url ?? selectedOutputLocation?.url else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    // MARK: - NSTableViewDataSource / Delegate

    func numberOfRows(in tableView: NSTableView) -> Int {
        contentMode == .grep ? grepRows.count : externalLines.count
    }

    private var selectedOutputLocation: OutputLocation? {
        guard tableView.selectedRow >= 0 else { return nil }
        if contentMode == .grep, tableView.selectedRow < grepRows.count,
           case .output(let entry) = grepRows[tableView.selectedRow] { return entry.location }
        guard contentMode == .externalCommand,
              tableView.selectedRow < outputBuffer.entries.count else { return nil }
        return outputBuffer.entries[tableView.selectedRow].location
    }

    private static let outputTimestamp: DateFormatter = {
        let value = DateFormatter(); value.locale = Locale(identifier: "en_US_POSIX")
        value.dateFormat = "HH:mm:ss"; return value
    }()
    private static func formatted(_ entry: OutputEntry) -> String {
        let channel: String
        switch entry.channel {
        case .standardOutput: channel = "stdout"
        case .standardError: channel = "stderr"
        default: channel = entry.channel.rawValue
        }
        return "[\(outputTimestamp.string(from: entry.timestamp))] [\(channel)] [\(entry.severity.rawValue)] \(entry.message)"
    }

    func clearForTesting() { clearOutput() }
    func show() { isHidden = false }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        if contentMode == .externalCommand {
            guard row < externalLines.count else { return nil }
            let identifier = NSUserInterfaceItemIdentifier("ExternalOutputCell")
            let cell = (tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView)
                ?? Self.makeCell(identifier: identifier)
            cell.textField?.stringValue = externalLines[row]
            cell.textField?.textColor = outputBuffer.entries[row].severity == .error
                ? .systemRed : Theme.sidebarText
            return cell
        }
        guard row < grepRows.count else { return nil }
        let identifier = NSUserInterfaceItemIdentifier("ResultCell")
        let cell = (tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView)
            ?? Self.makeCell(identifier: identifier)
        switch grepRows[row] {
        case .match(let match):
            cell.textField?.attributedStringValue = Self.attributedRow(for: match)
            cell.setAccessibilityLabel(Self.accessibilityDescription(for: match))
        case .output(let entry):
            cell.textField?.stringValue = Self.formatted(entry)
            cell.textField?.textColor = .systemOrange
        }
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
