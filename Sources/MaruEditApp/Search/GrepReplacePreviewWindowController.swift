import AppKit
import MaruEditCore

final class GrepReplacePreviewWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
    private enum Row { case file(Int), match(Int, Int) }
    private let table = NSTableView()
    private let before = NSTextView(), after = NSTextView()
    private let summary = NSTextField(labelWithString: "")
    private var rows: [Row] = []
    private(set) var changeSet: GrepReplaceChangeSet
    var onApply: ((GrepReplaceChangeSet) -> Void)?
    var onCancel: (() -> Void)?

    init(changeSet: GrepReplaceChangeSet) {
        self.changeSet = changeSet
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "Grep Replace Preview"
        super.init(window: window); buildUI(); rebuildRows()
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    private func buildUI() {
        let column = NSTableColumn(identifier: .init("change")); column.width = 300
        table.addTableColumn(column); table.headerView = nil; table.dataSource = self; table.delegate = self
        table.setAccessibilityLabel("Files and matches to replace")
        let list = NSScrollView(); list.documentView = table; list.hasVerticalScroller = true
        for view in [before, after] { view.isEditable = false; view.font = .monospacedSystemFont(ofSize: 11, weight: .regular) }
        func pane(_ title: String, _ text: NSTextView) -> NSView {
            let scroll = NSScrollView(); scroll.hasVerticalScroller = true
            text.frame = NSRect(x: 0, y: 0, width: 500, height: 300)
            text.autoresizingMask = [.width]
            text.isVerticallyResizable = true; text.isHorizontallyResizable = false
            text.textContainer?.widthTracksTextView = true
            scroll.documentView = text
            scroll.widthAnchor.constraint(greaterThanOrEqualToConstant: 380).isActive = true
            let stack = NSStackView(views: [NSTextField(labelWithString: title), scroll])
            stack.orientation = .vertical; stack.alignment = .width
            return stack
        }
        let previews = NSStackView(views: [pane("Before", before), pane("After", after)])
        previews.orientation = .vertical; previews.alignment = .width; previews.distribution = .fillEqually
        let split = NSSplitView(); split.isVertical = true; split.addArrangedSubview(list); split.addArrangedSubview(previews)
        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancelAction))
        let apply = NSButton(title: "Apply Selected Changes", target: self, action: #selector(applyAction))
        apply.keyEquivalent = "\r"
        let buttons = NSStackView(views: [summary, NSView(), cancel, apply]); buttons.orientation = .horizontal
        let root = NSStackView(views: [split, buttons]); root.orientation = .vertical
        root.alignment = .width; root.spacing = 10
        root.translatesAutoresizingMaskIntoConstraints = false; window?.contentView?.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: window!.contentView!.leadingAnchor, constant: 12),
            root.trailingAnchor.constraint(equalTo: window!.contentView!.trailingAnchor, constant: -12),
            root.topAnchor.constraint(equalTo: window!.contentView!.topAnchor, constant: 12),
            root.bottomAnchor.constraint(equalTo: window!.contentView!.bottomAnchor, constant: -12),
            list.widthAnchor.constraint(greaterThanOrEqualToConstant: 280),
        ])
    }

    private func rebuildRows() {
        rows = changeSet.files.indices.flatMap { file in
            [Row.file(file)] + changeSet.files[file].matches.indices.map { Row.match(file, $0) }
        }
        summary.stringValue = "\(changeSet.selectedFileCount) files, \(changeSet.selectedMatchCount) replacements selected"
        table.reloadData(); if !rows.isEmpty { table.selectRowIndexes([0], byExtendingSelection: false); showPreview(file: 0) }
    }
    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }
    func tableViewSelectionDidChange(_ notification: Notification) {
        guard table.selectedRow >= 0 else { return }
        switch rows[table.selectedRow] { case .file(let f), .match(let f, _): showPreview(file: f) }
    }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let button = NSButton(checkboxWithTitle: "", target: self, action: #selector(toggle(_:)))
        switch rows[row] {
        case .file(let file):
            button.title = changeSet.files[file].url.lastPathComponent
            button.state = changeSet.files[file].isSelected ? .on : .off
            button.identifier = .init("f:\(file)")
        case .match(let file, let match):
            let value = changeSet.files[file].matches[match]
            button.title = "  \(value.before) → \(value.after)"
            button.state = value.isSelected ? .on : .off
            button.identifier = .init("m:\(file):\(match)")
        }
        return button
    }
    @objc private func toggle(_ sender: NSButton) {
        let parts = sender.identifier?.rawValue.split(separator: ":") ?? []
        guard parts.count >= 2, let file = Int(parts[1]) else { return }
        if parts[0] == "f" { changeSet.files[file].isSelected.toggle() }
        else if parts.count == 3, let match = Int(parts[2]) { changeSet.files[file].matches[match].isSelected.toggle() }
        rebuildRows()
    }
    private func showPreview(file: Int) {
        before.string = changeSet.files[file].originalText; after.string = changeSet.files[file].previewText
    }
    @objc private func applyAction() { onApply?(changeSet) }
    @objc private func cancelAction() { onCancel?() }

    func setFileSelectedForTesting(_ selected: Bool, file: Int) { changeSet.files[file].isSelected = selected; rebuildRows() }
    func setMatchSelectedForTesting(_ selected: Bool, file: Int, match: Int) {
        changeSet.files[file].matches[match].isSelected = selected; rebuildRows()
    }
    var beforeTextForTesting: String { before.string }
    var afterTextForTesting: String { after.string }
    var previewWidthForTesting: CGFloat {
        window?.contentView?.layoutSubtreeIfNeeded()
        return before.enclosingScrollView?.contentSize.width ?? 0
    }
}
