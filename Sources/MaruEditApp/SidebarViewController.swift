import AppKit
import MaruEditCore

@MainActor
protocol SidebarDelegate: AnyObject {
    func sidebarDidSelectFile(_ url: URL, inNewTab: Bool)
    func sidebarDidSelectOutlineSymbol(_ symbol: OutlineSymbol)
}

final class FileItem: NSObject {
    let url: URL
    let isDirectory: Bool
    private var childrenLoaded = false
    var children: [FileItem]?

    var name: String { url.lastPathComponent }

    private static let skippedDirs: Set<String> = [
        ".git", ".svn", ".hg", "node_modules", ".build", ".swiftpm",
        "Pods", "DerivedData", ".next", "__pycache__", ".cache",
        "build", "dist", ".DS_Store", ".Trash",
    ]

    init(url: URL, isDir: Bool? = nil) {
        self.url = url
        if let known = isDir {
            self.isDirectory = known
        } else {
            var d: ObjCBool = false
            FileManager.default.fileExists(atPath: url.path, isDirectory: &d)
            self.isDirectory = d.boolValue
        }
        super.init()
    }

    func loadChildrenIfNeeded() {
        guard isDirectory, !childrenLoaded else { return }
        childrenLoaded = true
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { children = []; return }

        children = items
            .filter { !FileItem.skippedDirs.contains($0.lastPathComponent) }
            .sorted {
                let aDir = (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                let bDir = (try? $1.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                if aDir != bDir { return aDir }
                return $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending
            }
            .map {
                let isDir = (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                return FileItem(url: $0, isDir: isDir)
            }
    }
}

// MARK: - Custom outline view that intercepts Cmd+Click

private final class SidebarOutlineView: NSOutlineView {
    var onCmdClick: ((_ row: Int) -> Void)?

    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command) {
            let pt = convert(event.locationInWindow, from: nil)
            let row = self.row(at: pt)
            if row >= 0 {
                onCmdClick?(row)
                return
            }
        }
        super.mouseDown(with: event)
    }
}

// MARK: - Sidebar

final class SidebarViewController: NSViewController, NSOutlineViewDataSource, NSOutlineViewDelegate {
    enum UtilityPane: Int, CaseIterable { case files, outline, results }
    weak var sidebarDelegate: SidebarDelegate?

    private var outlineView: SidebarOutlineView!
    private var headerLabel: NSTextField!
    private var paneSelector: NSSegmentedControl!
    private var fileScrollView: NSScrollView!
    private var placeholderLabel: NSTextField!
    private(set) var selectedUtilityPane: UtilityPane = .files
    private var rootItems: [FileItem] = []
    private(set) var rootFolderURL: URL?
    private var suppressSelectionCallback = false
    private var outlineSymbols: [OutlineSymbol] = []
    private var markerResultText = "No color markers."
    private var searchResultText = ""

    func focusCurrentPane(in window: NSWindow?) {
        _ = view
        window?.makeFirstResponder(outlineView)
    }

    override func loadView() {
        let wrapper = NSView()
        wrapper.wantsLayer = true
        wrapper.layer?.backgroundColor = Theme.sidebarBg.cgColor

        headerLabel = NSTextField(labelWithString: "EXPLORER")
        headerLabel.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        headerLabel.textColor = Theme.sidebarText.withAlphaComponent(0.5)
        headerLabel.translatesAutoresizingMaskIntoConstraints = false
        wrapper.addSubview(headerLabel)

        paneSelector = NSSegmentedControl(labels: ["Files", "Outline", "Results"],
                                          trackingMode: .selectOne,
                                          target: self, action: #selector(selectUtilityPane(_:)))
        paneSelector.selectedSegment = UtilityPane.files.rawValue
        paneSelector.segmentStyle = .texturedRounded
        paneSelector.translatesAutoresizingMaskIntoConstraints = false
        paneSelector.setAccessibilityLabel("Utility pane")
        wrapper.addSubview(paneSelector)

        let sv = NSScrollView()
        fileScrollView = sv
        sv.translatesAutoresizingMaskIntoConstraints = false
        sv.hasVerticalScroller = true
        sv.autohidesScrollers = true
        sv.borderType = .noBorder
        sv.drawsBackground = false
        sv.scrollerStyle = .overlay

        outlineView = SidebarOutlineView()
        outlineView.headerView = nil
        outlineView.backgroundColor = Theme.sidebarBg
        outlineView.indentationPerLevel = 16
        outlineView.rowHeight = 24
        outlineView.selectionHighlightStyle = .regular
        outlineView.allowsMultipleSelection = false

        outlineView.onCmdClick = { [weak self] row in
            self?.handleNewTab(row: row)
        }

        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("F"))
        col.isEditable = false
        outlineView.addTableColumn(col)
        outlineView.outlineTableColumn = col

        outlineView.dataSource = self
        outlineView.delegate = self

        let contextMenu = NSMenu()
        contextMenu.delegate = self
        outlineView.menu = contextMenu

        sv.documentView = outlineView
        wrapper.addSubview(sv)

        placeholderLabel = NSTextField(wrappingLabelWithString: "")
        placeholderLabel.alignment = .center
        placeholderLabel.textColor = .secondaryLabelColor
        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        placeholderLabel.isHidden = true
        wrapper.addSubview(placeholderLabel)

        NSLayoutConstraint.activate([
            paneSelector.topAnchor.constraint(equalTo: wrapper.topAnchor, constant: 8),
            paneSelector.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor, constant: 8),
            paneSelector.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor, constant: -8),
            headerLabel.topAnchor.constraint(equalTo: paneSelector.bottomAnchor, constant: 8),
            headerLabel.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor, constant: 14),

            sv.topAnchor.constraint(equalTo: headerLabel.bottomAnchor, constant: 8),
            sv.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor),
            sv.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor),
            sv.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor),
            placeholderLabel.centerXAnchor.constraint(equalTo: wrapper.centerXAnchor),
            placeholderLabel.centerYAnchor.constraint(equalTo: wrapper.centerYAnchor),
            placeholderLabel.leadingAnchor.constraint(greaterThanOrEqualTo: wrapper.leadingAnchor, constant: 16),
            placeholderLabel.trailingAnchor.constraint(lessThanOrEqualTo: wrapper.trailingAnchor, constant: -16),
        ])

        view = wrapper
    }

    @objc private func selectUtilityPane(_ sender: NSSegmentedControl) {
        guard let pane = UtilityPane(rawValue: sender.selectedSegment) else { return }
        showUtilityPane(pane)
    }

    func showUtilityPane(_ pane: UtilityPane) {
        selectedUtilityPane = pane
        paneSelector.selectedSegment = pane.rawValue
        let showsList = pane != .results
        fileScrollView.isHidden = !showsList
        placeholderLabel.isHidden = showsList
        switch pane {
        case .files:
            headerLabel.stringValue = rootFolderURL?.lastPathComponent.uppercased() ?? "FILES"
        case .outline:
            headerLabel.stringValue = "OUTLINE"
        case .results:
            headerLabel.stringValue = "RESULTS"
            placeholderLabel.stringValue = searchResultText.isEmpty ? markerResultText : searchResultText
        }
        outlineView.reloadData()
    }

    func updateOutline(text: String, language: Language, customRules: [OutlineRule] = []) {
        outlineSymbols = OutlineModel(
            text: text, language: language, customRules: customRules).symbols
        if selectedUtilityPane == .outline { outlineView.reloadData() }
    }

    func updateSearchOutline(_ ranges: [NSRange], text: String) {
        let ns = text as NSString
        let index = LineIndex(text)
        outlineSymbols = ranges.prefix(5_000).map { range in
            let safe = min(max(0, range.location), ns.length)
            let line = index.line(atUTF16Offset: safe)
            let lineRange = ns.lineRange(for: NSRange(location: safe, length: 0))
            let preview = ns.substring(with: lineRange).trimmingCharacters(in: .whitespacesAndNewlines)
            return OutlineSymbol(
                kind: .section, title: "Ln \(line + 1): \(preview)", line: line,
                utf16Range: range, level: 0)
        }
        if selectedUtilityPane == .outline { outlineView.reloadData() }
    }

    @discardableResult
    func selectOutlineSymbol(containingLine line: Int) -> String? {
        guard let index = outlineSymbols.lastIndex(where: { $0.line <= line }) else { return nil }
        if selectedUtilityPane == .outline {
            suppressSelectionCallback = true
            outlineView.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
            outlineView.scrollRowToVisible(index)
            suppressSelectionCallback = false
        }
        return outlineSymbols[index].title
    }

    var outlineTitlesForTesting: [String] { outlineSymbols.map(\.title) }

    func updateMarkerResults(_ markers: [Int: MarkerColor], text: String) {
        let ns = text as NSString
        markerResultText = markers.sorted { $0.key < $1.key }.map { offset, color in
            let safe = min(max(0, offset), ns.length)
            let line = LineIndex(text).line(atUTF16Offset: safe) + 1
            let range = ns.lineRange(for: NSRange(location: safe, length: 0))
            let preview = ns.substring(with: range).trimmingCharacters(in: .whitespacesAndNewlines)
            return "\(color.rawValue.capitalized) · Ln \(line): \(preview)"
        }.joined(separator: "\n")
        if markerResultText.isEmpty { markerResultText = "No color markers." }
        if selectedUtilityPane == .results, searchResultText.isEmpty { placeholderLabel.stringValue = markerResultText }
    }


    func updateSearchResults(_ ranges: [NSRange], text: String) {
        let ns = text as NSString
        let index = LineIndex(text)
        searchResultText = ranges.prefix(500).map { match in
            let safe = min(max(0, match.location), ns.length)
            let line = index.line(atUTF16Offset: safe) + 1
            let lineRange = ns.lineRange(for: NSRange(location: safe, length: 0))
            let preview = ns.substring(with: lineRange).trimmingCharacters(in: .whitespacesAndNewlines)
            return "Search · Ln \(line): \(preview)"
        }.joined(separator: "\n")
        if ranges.count > 500 { searchResultText += "\n… \(ranges.count - 500) more matches" }
        if selectedUtilityPane == .results {
            placeholderLabel.stringValue = searchResultText.isEmpty ? markerResultText : searchResultText
        }
    }

    func updateSearchColorList(_ lines: [String]) {
        searchResultText = lines.isEmpty ? "No search color layers." : lines.joined(separator: "\n")
        if selectedUtilityPane == .results { placeholderLabel.stringValue = searchResultText }
    }

    func showMarkerResults() {
        searchResultText = ""
        showUtilityPane(.results)
    }

    var searchResultTextForTesting: String { searchResultText }

    var markerResultTextForTesting: String { markerResultText }

    func applyTheme() {
        view.layer?.backgroundColor = Theme.sidebarBg.cgColor
        headerLabel.textColor = Theme.sidebarText.withAlphaComponent(0.65)
        outlineView.backgroundColor = Theme.sidebarBg
        outlineView.reloadData()
    }

    var utilityPaneLabelsForTesting: [String] {
        (0..<paneSelector.segmentCount).map { paneSelector.label(forSegment: $0) ?? "" }
    }

    func openFolder(_ url: URL) {
        rootFolderURL = url
        let root = FileItem(url: url, isDir: true)
        root.loadChildrenIfNeeded()
        rootItems = root.children ?? []
        if selectedUtilityPane == .files {
            headerLabel.stringValue = url.lastPathComponent.uppercased()
        }
        outlineView.reloadData()
    }

    /// Expand parent directories and select the row matching `url`.
    func revealFile(_ url: URL) {
        guard let root = rootFolderURL else { return }
        let rootPath = root.path.hasSuffix("/") ? root.path : root.path + "/"
        guard url.path.hasPrefix(rootPath) else { return }

        let relative = String(url.path.dropFirst(rootPath.count))
        let components = relative.split(separator: "/").map(String.init)
        guard !components.isEmpty else { return }

        var currentItems = rootItems

        for (i, name) in components.enumerated() {
            guard let match = currentItems.first(where: { $0.name == name }) else { return }

            if i < components.count - 1 {
                guard match.isDirectory else { return }
                match.loadChildrenIfNeeded()
                outlineView.expandItem(match)
                currentItems = match.children ?? []
            } else {
                let row = outlineView.row(forItem: match)
                guard row >= 0 else { return }
                suppressSelectionCallback = true
                outlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
                outlineView.scrollRowToVisible(row)
                suppressSelectionCallback = false
            }
        }
    }

    // MARK: - New tab handling

    private func handleNewTab(row: Int) {
        guard selectedUtilityPane == .files else { return }
        guard let fi = outlineView.item(atRow: row) as? FileItem, !fi.isDirectory else { return }
        sidebarDelegate?.sidebarDidSelectFile(fi.url, inNewTab: true)
    }

    @objc private func contextOpenInNewTab(_ sender: Any?) {
        let row = outlineView.clickedRow
        guard row >= 0 else { return }
        handleNewTab(row: row)
    }

    // MARK: - Data source

    func outlineView(_ ov: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        if selectedUtilityPane == .outline { return item == nil ? outlineSymbols.count : 0 }
        if item == nil { return rootItems.count }
        guard let fi = item as? FileItem else { return 0 }
        fi.loadChildrenIfNeeded()
        return fi.children?.count ?? 0
    }

    func outlineView(_ ov: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        if selectedUtilityPane == .outline { return outlineSymbols[index] }
        if item == nil { return rootItems[index] }
        return (item as! FileItem).children![index]
    }

    func outlineView(_ ov: NSOutlineView, isItemExpandable item: Any) -> Bool {
        if item is OutlineSymbol { return false }
        return (item as? FileItem)?.isDirectory ?? false
    }

    // MARK: - Delegate

    func outlineView(_ ov: NSOutlineView, viewFor col: NSTableColumn?, item: Any) -> NSView? {
        if let symbol = item as? OutlineSymbol {
            let cell = NSTableCellView()
            let label = NSTextField(labelWithString: symbol.title)
            label.font = Theme.uiFontSmall
            label.textColor = Theme.sidebarText
            label.lineBreakMode = .byTruncatingTail
            label.translatesAutoresizingMaskIntoConstraints = false
            label.setAccessibilityLabel("\(symbol.kind.rawValue): \(symbol.title), line \(symbol.line + 1)")
            cell.addSubview(label)
            cell.textField = label
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: CGFloat(6 + symbol.level * 12)),
                label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
                label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])
            return cell
        }
        guard let fi = item as? FileItem else { return nil }

        let cell = NSTableCellView()
        let iv = NSImageView()
        iv.translatesAutoresizingMaskIntoConstraints = false
        let iconName = fi.isDirectory ? "folder.fill" : fileIcon(fi.url)
        iv.image = NSImage(systemSymbolName: iconName, accessibilityDescription: nil)
        iv.contentTintColor = fi.isDirectory
            ? NSColor(srgbRed: 0.4, green: 0.85, blue: 0.94, alpha: 1)
            : Theme.sidebarText
        iv.imageScaling = .scaleProportionallyDown

        let tf = NSTextField(labelWithString: fi.name)
        tf.font = Theme.uiFontSmall
        tf.textColor = Theme.sidebarText
        tf.lineBreakMode = .byTruncatingTail
        tf.translatesAutoresizingMaskIntoConstraints = false

        cell.addSubview(iv)
        cell.addSubview(tf)
        cell.imageView = iv
        cell.textField = tf

        NSLayoutConstraint.activate([
            iv.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
            iv.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            iv.widthAnchor.constraint(equalToConstant: 16),
            iv.heightAnchor.constraint(equalToConstant: 16),
            tf.leadingAnchor.constraint(equalTo: iv.trailingAnchor, constant: 6),
            tf.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
            tf.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }

    func outlineViewSelectionDidChange(_ n: Notification) {
        guard !suppressSelectionCallback else { return }
        let row = outlineView.selectedRow
        if selectedUtilityPane == .outline {
            guard outlineSymbols.indices.contains(row) else { return }
            sidebarDelegate?.sidebarDidSelectOutlineSymbol(outlineSymbols[row])
            return
        }
        guard row >= 0, let fi = outlineView.item(atRow: row) as? FileItem, !fi.isDirectory else { return }
        sidebarDelegate?.sidebarDidSelectFile(fi.url, inNewTab: false)
    }

    private func fileIcon(_ url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "swift":                        return "swift"
        case "html", "htm":                  return "globe"
        case "css", "scss":                  return "paintbrush"
        case "json":                         return "curlybraces"
        case "md", "markdown":               return "doc.richtext"
        case "sh", "bash", "zsh":            return "terminal"
        case "png", "jpg", "jpeg", "gif":    return "photo"
        case "pdf":                          return "doc.fill"
        case "zip", "tar", "gz":             return "archivebox"
        case "js", "ts", "jsx", "tsx":       return "chevron.left.forwardslash.chevron.right"
        case "py":                           return "text.word.spacing"
        case "rs":                           return "gearshape.2"
        case "go":                           return "arrow.right.arrow.left"
        case "yml", "yaml", "toml":          return "list.bullet.indent"
        default:                             return "doc"
        }
    }
}

// MARK: - Context menu

extension SidebarViewController: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        guard selectedUtilityPane == .files else { return }
        let row = outlineView.clickedRow
        guard row >= 0, let fi = outlineView.item(atRow: row) as? FileItem else { return }

        if !fi.isDirectory {
            let openItem = NSMenuItem(title: "Open", action: #selector(contextOpen(_:)), keyEquivalent: "")
            openItem.target = self
            menu.addItem(openItem)

            let newTabItem = NSMenuItem(title: "Open in New Tab", action: #selector(contextOpenInNewTab(_:)), keyEquivalent: "")
            newTabItem.target = self
            menu.addItem(newTabItem)

            menu.addItem(.separator())
        }

        let revealItem = NSMenuItem(title: "Reveal in Finder", action: #selector(contextRevealInFinder(_:)), keyEquivalent: "")
        revealItem.target = self
        menu.addItem(revealItem)
    }

    @objc private func contextOpen(_ sender: Any?) {
        let row = outlineView.clickedRow
        guard row >= 0, let fi = outlineView.item(atRow: row) as? FileItem, !fi.isDirectory else { return }
        sidebarDelegate?.sidebarDidSelectFile(fi.url, inNewTab: false)
    }

    @objc private func contextRevealInFinder(_ sender: Any?) {
        let row = outlineView.clickedRow
        guard row >= 0, let fi = outlineView.item(atRow: row) as? FileItem else { return }
        NSWorkspace.shared.activateFileViewerSelecting([fi.url])
    }
}
