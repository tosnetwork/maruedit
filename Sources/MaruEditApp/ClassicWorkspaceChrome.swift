import AppKit
import MaruEditCore

/// Compact, original macOS chrome inspired by high-density text-editor
/// workflows. It contains no copied product art or bitmap assets.
final class ClassicWorkspaceChrome: NSView {
    static let toolbarHeight: CGFloat = 32
    static let headingHeight: CGFloat = 22
    static let rulerHeight: CGFloat = 20
    static let commandStripHeight: CGFloat = 24

    private let heading = NSTextField(labelWithString: "Untitled")
    private let toolbar = ClassicToolbarView()
    private let ruler = CharacterRulerView()
    private let commandStrip = ClassicCommandStripView()
    private var rulerStartX: CGFloat = 46
    private var configuredVisibility = ClassicChromeOptions.allVisible
    private var isSingleDocument = true
    private var isStatusBarVisible = true
    private(set) var isToolbarFloating = false
    var externalTopGap: CGFloat = 0 { didSet { needsLayout = true } }
    var onLayoutChange: (() -> Void)?

    var headingText: String { heading.stringValue }
    var topChromeHeight: CGFloat {
        (toolbar.isHidden || isToolbarFloating ? 0 : Self.toolbarHeight) + (heading.isHidden ? 0 : Self.headingHeight)
            + (ruler.isHidden ? 0 : Self.rulerHeight)
    }
    var bottomChromeHeight: CGFloat {
        commandStrip.isHidden || (commandStrip.isMergedWithStatusBar && isStatusBarVisible)
            ? 0 : Self.commandStripHeight
    }
    var isFunctionKeyStripMerged: Bool { commandStrip.isMergedWithStatusBar }
    func mergedFunctionKeyWidth(totalWidth: CGFloat) -> CGFloat {
        commandStrip.isHidden || !commandStrip.isMergedWithStatusBar || !isStatusBarVisible
            ? 0 : totalWidth * 0.55
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        heading.font = .systemFont(ofSize: 11, weight: .medium)
        heading.lineBreakMode = .byTruncatingMiddle
        heading.setAccessibilityLabel("Current document heading")
        addSubview(toolbar)
        addSubview(heading)
        addSubview(ruler)
        addSubview(commandStrip)
        commandStrip.onMergeChange = { [weak self] in
            self?.needsLayout = true
            self?.onLayoutChange?()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let target = super.hitTest(point)
        return target === self ? nil : target
    }

    override func layout() {
        super.layout()
        let top = bounds.height
        let toolbarHeight = toolbar.isHidden || isToolbarFloating ? 0 : Self.toolbarHeight
        toolbar.frame = NSRect(
            x: 0, y: top - Self.toolbarHeight,
            width: bounds.width, height: Self.toolbarHeight)
        heading.frame = NSRect(
            x: 8, y: top - toolbarHeight - externalTopGap - Self.headingHeight + 3,
            width: max(0, bounds.width - 16), height: 16)
        ruler.frame = NSRect(
            x: rulerStartX, y: top - toolbarHeight
                - externalTopGap - (heading.isHidden ? 0 : Self.headingHeight) - Self.rulerHeight,
            width: max(0, bounds.width - rulerStartX), height: Self.rulerHeight)
        commandStrip.frame = NSRect(
            x: 0, y: 0,
            width: commandStrip.isMergedWithStatusBar && isStatusBarVisible
                ? bounds.width * 0.55 : bounds.width,
            height: Self.commandStripHeight)
    }

    func updateHeading(_ value: String) { heading.stringValue = value }
    func setDocumentCount(_ count: Int) {
        isSingleDocument = count <= 1
        applyEffectiveVisibility()
    }
    func updateRuler(
        editorOrigin: CGFloat, currentColumn: Int, cellWidth: CGFloat, tabWidth: Int
    ) {
        rulerStartX = max(0, editorOrigin)
        ruler.editorOrigin = 0
        ruler.currentColumn = currentColumn
        ruler.cellWidth = max(1, cellWidth)
        ruler.tabWidth = max(1, tabWidth)
        needsLayout = true
    }

    var onCommand: ((CommandID) -> Void)? {
        get { toolbar.onCommand }
        set { toolbar.onCommand = newValue; commandStrip.onCommand = newValue }
    }
    var onToolbarSearch: ((String) -> Void)? {
        get { toolbar.onSearch }
        set { toolbar.onSearch = newValue }
    }

    var toolbarCommandIDs: [String] { toolbar.commandIDs.map(\.rawValue) }
    var toolbarLayoutEntries: [String] { toolbar.layoutEntries }
    var toolbarDisplayMode: ToolbarDisplayMode { toolbar.displayMode }
    var toolbarIconSize: ToolbarIconSize { toolbar.iconSize }
    var isToolbarSearchVisible: Bool { toolbar.showsSearchField }
    var isToolbarVisible: Bool { !toolbar.isHidden }
    var visibleToolbarHeight: CGFloat { toolbar.isHidden ? 0 : Self.toolbarHeight }
    var functionKeyCommandIDs: [String?] { commandStrip.commandIDs }
    var functionKeyCount: Int { commandStrip.visibleSlotCount }
    var keyboardFocusableViews: [NSView] {
        toolbar.keyboardFocusableViews + commandStrip.keyboardFocusableViews
    }
    func toolbarPresentation(for command: CommandID) -> (enabled: Bool, selected: Bool)? {
        toolbar.presentation(for: command)
    }
    func functionKeyPresentation(at index: Int) -> (enabled: Bool, selected: Bool)? {
        commandStrip.presentation(at: index)
    }

    func activateToolbarCommand(_ command: CommandID) { toolbar.activate(command) }
    func configureAvailableCommands(_ commands: [(CommandID, String)]) {
        toolbar.configureAvailableCommands(commands)
        commandStrip.configureAvailableCommands(commands)
    }
    func configureCommandPresentation(
        _ provider: @escaping (CommandID) -> (enabled: Bool, selected: Bool)
    ) {
        toolbar.presentationProvider = provider
        commandStrip.presentationProvider = provider
        refreshCommandPresentation()
    }
    func refreshCommandPresentation() {
        toolbar.refreshCommandPresentation()
        commandStrip.refreshCommandPresentation()
    }
    func setToolbarLayoutForTesting(_ entries: [String]) { toolbar.setLayoutForTesting(entries) }
    func setToolbarDisplayModeForTesting(_ mode: ToolbarDisplayMode) {
        toolbar.setDisplayModeForTesting(mode)
    }
    func setToolbarSearchVisibleForTesting(_ visible: Bool) {
        toolbar.setSearchVisibleForTesting(visible)
    }
    func setToolbarIconSizeForTesting(_ size: ToolbarIconSize) {
        toolbar.setIconSizeForTesting(size)
    }
    func performToolbarSearchForTesting(_ text: String) { toolbar.performSearchForTesting(text) }
    func detachToolbarForFloating() -> NSView {
        isToolbarFloating = true
        toolbar.removeFromSuperview()
        needsLayout = true; onLayoutChange?()
        return toolbar
    }
    func attachFloatingToolbar() {
        guard toolbar.superview !== self else { return }
        isToolbarFloating = false
        addSubview(toolbar)
        needsLayout = true; onLayoutChange?()
    }
    func setFunctionKeyCommandsForTesting(_ ids: [CommandID?]) {
        commandStrip.setCommandsForTesting(ids)
    }
    func setFunctionKeyCountForTesting(_ count: Int) {
        commandStrip.setVisibleSlotCountForTesting(count)
    }
    func activateFunctionKeyForTesting(_ index: Int) { commandStrip.activateSlotForTesting(index) }

    func applyVisibility(_ options: ClassicChromeOptions) {
        configuredVisibility = options
        ruler.majorInterval = options.rulerInterval
        ruler.showsTabStops = options.showTabStops
        applyEffectiveVisibility()
    }

    func setStatusBarVisible(_ visible: Bool) {
        isStatusBarVisible = visible; needsLayout = true
    }

    func setFunctionKeyMergeForTesting(_ merged: Bool) {
        commandStrip.setMergedForTesting(merged)
    }

    private func applyEffectiveVisibility() {
        // With one document Maru does not repeat its filename in a
        // separate strip above the line-number gutter.
        heading.isHidden = !configuredVisibility.showHeading || isSingleDocument
        toolbar.isHidden = !configuredVisibility.showToolbar
        ruler.isHidden = !configuredVisibility.showRuler
        commandStrip.isHidden = !configuredVisibility.showCommandStrip
        needsLayout = true
    }

    var visibilityForTesting: ClassicChromeOptions {
        configuredVisibility
    }
    var isHeadingActuallyVisibleForTesting: Bool { !heading.isHidden }
    var rulerStateForTesting: (origin: CGFloat, column: Int) {
        (rulerStartX, ruler.currentColumn)
    }
    var rulerMaximumColumnForTesting: Int { ruler.maximumColumn }
    var rulerConfigurationForTesting: (interval: Int, showsTabStops: Bool, tabWidth: Int) {
        (ruler.majorInterval, ruler.showsTabStops, ruler.tabWidth)
    }
}

/// Original, compact icon bar modeled after the information density and
/// command grouping of classic keyboard-oriented editors. It deliberately
/// uses SF Symbols rather than copying third-party bitmap artwork.
private final class ClassicToolbarView: NSView {
    struct Item {
        let command: CommandID?
        let title: String
        let symbol: String
        let tint: NSColor
        let responderAction: Selector?
    }

    private static let groups: [[Item]] = [
        [
            Item(command: .fileNew, title: "New", symbol: "doc.badge.plus", tint: .systemBlue, responderAction: nil),
            Item(command: .fileOpen, title: "Open", symbol: "folder.fill", tint: .systemYellow, responderAction: nil),
            Item(command: .fileSave, title: "Save", symbol: "square.and.arrow.down.fill", tint: .systemBlue, responderAction: nil),
            Item(command: .filePrint, title: "Print", symbol: "printer.fill", tint: .systemPurple, responderAction: nil),
        ],
        [
            Item(command: nil, title: "Undo", symbol: "arrow.uturn.backward", tint: .systemIndigo, responderAction: Selector(("undo:"))),
            Item(command: nil, title: "Redo", symbol: "arrow.uturn.forward", tint: .systemIndigo, responderAction: Selector(("redo:"))),
        ],
        [
            Item(command: nil, title: "Cut", symbol: "scissors", tint: .systemRed, responderAction: #selector(NSText.cut(_:))),
            Item(command: nil, title: "Copy", symbol: "doc.on.doc.fill", tint: .systemTeal, responderAction: #selector(NSText.copy(_:))),
            Item(command: nil, title: "Paste", symbol: "doc.on.clipboard.fill", tint: .systemOrange, responderAction: #selector(NSText.paste(_:))),
        ],
        [
            Item(command: .searchFind, title: "Find", symbol: "magnifyingglass", tint: .systemBlue, responderAction: nil),
            Item(command: .searchReplace, title: "Replace", symbol: "arrow.left.arrow.right", tint: .systemPurple, responderAction: nil),
            Item(command: .searchFindNext, title: "Find Next", symbol: "arrow.down.circle.fill", tint: .systemGreen, responderAction: nil),
            Item(command: .searchFindPrevious, title: "Find Previous", symbol: "arrow.up.circle.fill", tint: .systemGreen, responderAction: nil),
            Item(command: .searchGrep, title: "Grep", symbol: "text.magnifyingglass", tint: .systemCyan, responderAction: nil),
        ],
        [
            Item(command: .navigateToggleBookmark, title: "Bookmark", symbol: "bookmark.fill", tint: .systemRed, responderAction: nil),
            Item(command: .navigateNextBookmark, title: "Next Bookmark", symbol: "bookmark.circle.fill", tint: .systemOrange, responderAction: nil),
            Item(command: .searchGoToLine, title: "Go to Line", symbol: "number.circle.fill", tint: .systemBrown, responderAction: nil),
            Item(command: .navigateToggleFold, title: "Toggle Fold", symbol: "chevron.left.forwardslash.chevron.right", tint: .systemPurple, responderAction: nil),
        ],
        [
            Item(command: .appMacroMenu, title: "Macro", symbol: "play.rectangle.fill", tint: .systemPink, responderAction: nil),
            Item(command: .viewToggleSidebar, title: "Utility Pane", symbol: "sidebar.left", tint: .systemBlue, responderAction: nil),
            Item(command: .appSettings, title: "Settings", symbol: "gearshape.fill", tint: .systemGray, responderAction: nil),
        ],
    ]

    var onCommand: ((CommandID) -> Void)?
    var onSearch: ((String) -> Void)?
    var presentationProvider: ((CommandID) -> (enabled: Bool, selected: Bool))?
    private var buttons: [NSButton] = []
    private var separators: [NSView] = []
    private var displayedItems: [Item] = []
    private var toolbarLayout = ToolbarLayout(entries: [])
    private(set) var displayMode: ToolbarDisplayMode = .iconOnly
    private(set) var iconSize: ToolbarIconSize = .medium
    private var contextKey: String?
    private var contextSeparatorIndex: Int?
    private let searchField = NSSearchField()
    private(set) var showsSearchField = true
    private static let layoutDefaultsKey = "MaruClassicToolbarLayout"
    private static let displayModeDefaultsKey = "MaruClassicToolbarDisplayMode"
    private static let hiddenDefaultsKey = "MaruClassicToolbarHiddenItems"
    private static let searchDefaultsKey = "MaruClassicToolbarSearchField"
    private static let iconSizeDefaultsKey = "MaruClassicToolbarIconSize"
    private static var builtInCatalog: [String: Item] {
        Dictionary(uniqueKeysWithValues: groups.flatMap { $0 }.map { (key(for: $0), $0) })
    }
    private var catalog = builtInCatalog
    private static var defaultEntries: [String] {
        groups.enumerated().flatMap { index, group in
            (index == 0 ? [] : [ToolbarLayout.separator]) + group.map { key(for: $0) }
        }
    }
    var commandIDs: [CommandID] { displayedItems.compactMap(\.command) }
    var layoutEntries: [String] { toolbarLayout.entries }
    var keyboardFocusableViews: [NSView] {
        buttons.filter { !$0.isHidden && $0.isEnabled }
            + (searchField.isHidden || !searchField.isEnabled ? [] : [searchField])
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        setAccessibilityRole(.toolbar)
        setAccessibilityLabel("Maru Classic command toolbar")
        toolbarLayout = loadLayout()
        displayMode = UserDefaults.standard.string(forKey: Self.displayModeDefaultsKey)
            .flatMap(ToolbarDisplayMode.init(rawValue:)) ?? .iconOnly
        iconSize = UserDefaults.standard.string(forKey: Self.iconSizeDefaultsKey)
            .flatMap(ToolbarIconSize.init(rawValue:)) ?? .medium
        if UserDefaults.standard.object(forKey: Self.searchDefaultsKey) != nil {
            showsSearchField = UserDefaults.standard.bool(forKey: Self.searchDefaultsKey)
        }
        searchField.placeholderString = "Search"
        searchField.target = self; searchField.action = #selector(runToolbarSearch)
        searchField.setAccessibilityLabel("Toolbar search")
        searchField.toolTip = "Search the current document"
        addSubview(searchField)
        rebuildSubviews()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        var x: CGFloat = 5
        var separatorIndex = 0
        var itemIndex = 0
        for entry in toolbarLayout.entries {
            if entry == ToolbarLayout.separator {
                separators[separatorIndex].frame = NSRect(x: x + 2, y: 6, width: 1, height: 20)
                separatorIndex += 1
                x += 8
            } else {
                let button = buttons[itemIndex]
                let width = buttonWidth(for: button)
                button.frame = NSRect(x: x, y: 3, width: width, height: 26)
                x += width
                itemIndex += 1
            }
        }
        let searchWidth: CGFloat = 190
        searchField.isHidden = !showsSearchField || x + searchWidth + 8 > bounds.width
        if !searchField.isHidden {
            searchField.frame = NSRect(
                x: bounds.width - searchWidth - 8, y: 4, width: searchWidth, height: 24)
        }
        let border = NSBezierPath()
        NSColor.separatorColor.setStroke()
        border.move(to: NSPoint(x: 0, y: 0.5))
        border.line(to: NSPoint(x: bounds.maxX, y: 0.5))
        border.stroke()
    }

    @objc private func activateButton(_ sender: NSButton) {
        guard displayedItems.indices.contains(sender.tag) else { return }
        let item = displayedItems[sender.tag]
        if let command = item.command { onCommand?(command) }
        else if let action = item.responderAction { NSApp.sendAction(action, to: nil, from: sender) }
    }

    func activate(_ command: CommandID) {
        guard displayedItems.contains(where: { $0.command == command }) else { return }
        guard presentationProvider?(command).enabled != false else { return }
        onCommand?(command)
    }

    func presentation(for command: CommandID) -> (enabled: Bool, selected: Bool)? {
        guard let index = displayedItems.firstIndex(where: { $0.command == command }),
              buttons.indices.contains(index) else { return nil }
        return (buttons[index].isEnabled, buttons[index].state == .on)
    }

    override func rightMouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        contextKey = buttons.first(where: { $0.frame.contains(point) }).flatMap {
            displayedItems.indices.contains($0.tag) ? Self.key(for: displayedItems[$0.tag]) : nil
        }
        contextSeparatorIndex = separatorEntryIndex(at: point)
        let menu = NSMenu(title: "Customize Maru Classic Toolbar")
        if contextKey != nil {
            addContextItem("Move Left", action: #selector(moveToolbarItemLeft), to: menu)
            addContextItem("Move Right", action: #selector(moveToolbarItemRight), to: menu)
            addContextItem("Insert Separator After", action: #selector(insertToolbarSeparator), to: menu)
            addContextItem("Remove from Toolbar", action: #selector(removeToolbarItem), to: menu)
            menu.addItem(.separator())
        } else if contextSeparatorIndex != nil {
            addContextItem("Remove Separator", action: #selector(removeToolbarSeparator), to: menu)
            menu.addItem(.separator())
        }
        let addMenu = NSMenu(title: "Add Command")
        for (key, item) in catalog.sorted(by: { $0.value.title < $1.value.title })
            where !toolbarLayout.entries.contains(key) {
            let menuItem = NSMenuItem(
                title: item.title, action: #selector(addToolbarItem(_:)), keyEquivalent: "")
            menuItem.target = self
            menuItem.representedObject = key
            addMenu.addItem(menuItem)
        }
        let add = NSMenuItem(title: "Add Command", action: nil, keyEquivalent: "")
        add.submenu = addMenu
        add.isEnabled = !addMenu.items.isEmpty
        menu.addItem(add)
        let styleMenu = NSMenu(title: "Display Style")
        for mode in ToolbarDisplayMode.allCases {
            let item = NSMenuItem(
                title: title(for: mode), action: #selector(changeDisplayMode(_:)), keyEquivalent: "")
            item.target = self; item.representedObject = mode.rawValue
            item.state = displayMode == mode ? .on : .off
            styleMenu.addItem(item)
        }
        let style = NSMenuItem(title: "Display Style", action: nil, keyEquivalent: "")
        style.submenu = styleMenu; menu.addItem(style)
        let sizeMenu = NSMenu(title: "Icon Size")
        for size in ToolbarIconSize.allCases {
            let item = NSMenuItem(
                title: size.rawValue.capitalized, action: #selector(changeIconSize(_:)),
                keyEquivalent: "")
            item.target = self; item.representedObject = size.rawValue
            item.state = iconSize == size ? .on : .off
            sizeMenu.addItem(item)
        }
        let sizeItem = NSMenuItem(title: "Icon Size", action: nil, keyEquivalent: "")
        sizeItem.submenu = sizeMenu; menu.addItem(sizeItem)
        let search = NSMenuItem(
            title: "Show Search Box", action: #selector(toggleSearchField), keyEquivalent: "")
        search.target = self; search.state = showsSearchField ? .on : .off
        menu.addItem(search)
        menu.addItem(.separator())
        let restore = NSMenuItem(
            title: "Restore Default Toolbar", action: #selector(restoreDefaultToolbar),
            keyEquivalent: "")
        restore.target = self
        menu.addItem(restore)
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    @objc private func addToolbarItem(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String else { return }
        toolbarLayout.append(key, availableKeys: Set(catalog.keys))
        applyCustomization()
    }

    @objc private func removeToolbarItem() {
        guard let contextKey else { return }
        toolbarLayout.remove(contextKey)
        applyCustomization()
    }

    @objc private func moveToolbarItemLeft() { moveContextItem(by: -1) }
    @objc private func moveToolbarItemRight() { moveContextItem(by: 1) }

    private func moveContextItem(by offset: Int) {
        guard let contextKey else { return }
        toolbarLayout.move(contextKey, offset: offset, availableKeys: Set(catalog.keys))
        applyCustomization()
    }

    @objc private func insertToolbarSeparator() {
        guard let contextKey else { return }
        toolbarLayout.insertSeparator(after: contextKey)
        applyCustomization()
    }

    @objc private func removeToolbarSeparator() {
        guard let index = contextSeparatorIndex, toolbarLayout.entries.indices.contains(index),
              toolbarLayout.entries[index] == ToolbarLayout.separator else { return }
        toolbarLayout.entries.remove(at: index)
        applyCustomization()
    }

    @objc private func restoreDefaultToolbar() {
        toolbarLayout = ToolbarLayout(entries: Self.defaultEntries)
        displayMode = .iconOnly
        UserDefaults.standard.set(displayMode.rawValue, forKey: Self.displayModeDefaultsKey)
        applyCustomization()
    }

    @objc private func changeDisplayMode(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let mode = ToolbarDisplayMode(rawValue: rawValue) else { return }
        displayMode = mode
        UserDefaults.standard.set(mode.rawValue, forKey: Self.displayModeDefaultsKey)
        rebuildSubviews(); needsLayout = true
    }

    @objc private func changeIconSize(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let size = ToolbarIconSize(rawValue: raw) else { return }
        iconSize = size
        UserDefaults.standard.set(size.rawValue, forKey: Self.iconSizeDefaultsKey)
        rebuildSubviews(); needsLayout = true
    }

    @objc private func toggleSearchField() {
        showsSearchField.toggle()
        UserDefaults.standard.set(showsSearchField, forKey: Self.searchDefaultsKey)
        needsLayout = true
    }

    @objc private func runToolbarSearch() {
        let pattern = searchField.stringValue
        guard !pattern.isEmpty else { return }
        onSearch?(pattern)
    }

    private func applyCustomization() {
        toolbarLayout = toolbarLayout.normalized(availableKeys: Set(catalog.keys))
        UserDefaults.standard.set(toolbarLayout.entries, forKey: Self.layoutDefaultsKey)
        rebuildSubviews()
        needsLayout = true
    }

    private func loadLayout() -> ToolbarLayout {
        let defaults = UserDefaults.standard
        if let entries = defaults.stringArray(forKey: Self.layoutDefaultsKey) {
            // Keep registry-backed command IDs until AppCoordinator injects
            // the full catalog. Rebuilding safely skips unknown entries in
            // the brief interval before configuration.
            return ToolbarLayout(entries: entries)
        }
        let hidden = Set(defaults.stringArray(forKey: Self.hiddenDefaultsKey) ?? [])
        return ToolbarLayout(entries: Self.defaultEntries.filter { $0 == ToolbarLayout.separator || !hidden.contains($0) })
            .normalized(availableKeys: Set(catalog.keys))
    }

    private func rebuildSubviews() {
        buttons.forEach { $0.removeFromSuperview() }
        separators.forEach { $0.removeFromSuperview() }
        buttons.removeAll(); separators.removeAll(); displayedItems.removeAll()
        for entry in toolbarLayout.entries {
            if entry == ToolbarLayout.separator {
                let separator = NSView()
                separator.wantsLayer = true
                separator.layer?.backgroundColor = NSColor.separatorColor.cgColor
                separators.append(separator); addSubview(separator)
            } else if let item = catalog[entry] {
                let button = ClassicToolbarButton()
                button.bezelStyle = .inline; button.isBordered = false
                button.imageScaling = .scaleProportionallyDown
                button.image = NSImage(systemSymbolName: item.symbol, accessibilityDescription: item.title)
                button.symbolConfiguration = NSImage.SymbolConfiguration(
                    pointSize: CGFloat(iconSize.pointSize), weight: .regular)
                button.imagePosition = imagePosition(for: displayMode)
                button.title = displayMode == .iconOnly ? "" : item.title
                button.font = .systemFont(ofSize: 10)
                button.contentTintColor = item.tint; button.toolTip = item.title
                button.setAccessibilityLabel(item.title); button.target = self
                button.action = #selector(activateButton(_:)); button.tag = displayedItems.count
                displayedItems.append(item); buttons.append(button); addSubview(button)
            }
        }
        refreshCommandPresentation()
    }

    func refreshCommandPresentation() {
        for (index, item) in displayedItems.enumerated() where buttons.indices.contains(index) {
            guard let command = item.command, let state = presentationProvider?(command) else { continue }
            buttons[index].isEnabled = state.enabled
            buttons[index].state = state.selected ? .on : .off
            buttons[index].alphaValue = state.enabled ? 1 : 0.42
        }
    }

    private func addContextItem(_ title: String, action: Selector, to menu: NSMenu) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self; menu.addItem(item)
    }

    private func separatorEntryIndex(at point: NSPoint) -> Int? {
        var separatorIndex = 0
        for (entryIndex, entry) in toolbarLayout.entries.enumerated() where entry == ToolbarLayout.separator {
            defer { separatorIndex += 1 }
            guard separators.indices.contains(separatorIndex) else { continue }
            if separators[separatorIndex].frame.insetBy(dx: -3, dy: 0).contains(point) { return entryIndex }
        }
        return nil
    }

    func setLayoutForTesting(_ entries: [String]) {
        toolbarLayout = ToolbarLayout(entries: entries)
            .normalized(availableKeys: Set(catalog.keys))
        rebuildSubviews()
        needsLayout = true
    }

    func setDisplayModeForTesting(_ mode: ToolbarDisplayMode) {
        displayMode = mode
        rebuildSubviews(); needsLayout = true
    }

    func setSearchVisibleForTesting(_ visible: Bool) {
        showsSearchField = visible; needsLayout = true
    }

    func setIconSizeForTesting(_ size: ToolbarIconSize) {
        iconSize = size; rebuildSubviews(); needsLayout = true
    }

    func performSearchForTesting(_ text: String) {
        searchField.stringValue = text; runToolbarSearch()
    }

    func configureAvailableCommands(_ commands: [(CommandID, String)]) {
        var updated = Self.builtInCatalog
        for (command, title) in commands where updated[command.rawValue] == nil {
            updated[command.rawValue] = Item(
                command: command, title: title, symbol: "command",
                tint: .controlAccentColor, responderAction: nil)
        }
        catalog = updated
        toolbarLayout = toolbarLayout.normalized(availableKeys: Set(catalog.keys))
        rebuildSubviews(); needsLayout = true
    }

    private func buttonWidth(for button: NSButton) -> CGFloat {
        switch displayMode {
        case .iconOnly: CGFloat(iconSize.pointSize) + 10
        case .iconAndText: min(110, max(52, button.intrinsicContentSize.width + 8))
        case .textOnly: min(100, max(38, button.intrinsicContentSize.width + 8))
        }
    }

    private func imagePosition(for mode: ToolbarDisplayMode) -> NSControl.ImagePosition {
        switch mode {
        case .iconOnly: .imageOnly
        case .iconAndText: .imageLeading
        case .textOnly: .noImage
        }
    }

    private func title(for mode: ToolbarDisplayMode) -> String {
        switch mode {
        case .iconOnly: "Icons Only"
        case .iconAndText: "Icons and Text"
        case .textOnly: "Text Only"
        }
    }

    private static func key(for item: Item) -> String {
        item.command?.rawValue ?? "responder.\(item.title.lowercased())"
    }
}

private final class ClassicToolbarButton: NSButton {
    private var tracking: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(
            rect: bounds, options: [.activeInKeyWindow, .mouseEnteredAndExited],
            owner: self, userInfo: nil)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) {
        wantsLayer = true
        layer?.cornerRadius = 4
        layer?.backgroundColor = NSColor.selectedControlColor.withAlphaComponent(0.16).cgColor
    }

    override func mouseExited(with event: NSEvent) {
        layer?.backgroundColor = NSColor.clear.cgColor
    }
}

private final class CharacterRulerView: NSView {
    /// Maru's default fixed-width/wrapping reference is 160 columns.
    let maximumColumn = 160
    var editorOrigin: CGFloat = 46 { didSet { needsDisplay = true } }
    var currentColumn: Int = 1 { didSet { needsDisplay = true } }
    var cellWidth: CGFloat = 8 { didSet { needsDisplay = true } }
    var majorInterval = 10 { didSet { needsDisplay = true } }
    var tabWidth = 4 { didSet { needsDisplay = true } }
    var showsTabStops = false { didSet { needsDisplay = true } }
    override var isFlipped: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        setAccessibilityRole(.ruler)
        setAccessibilityLabel("Character column ruler")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSColor.separatorColor.setStroke()
        let baseline = NSBezierPath()
        baseline.move(to: NSPoint(x: 0, y: bounds.maxY - 0.5))
        baseline.line(to: NSPoint(x: bounds.maxX, y: bounds.maxY - 0.5))
        baseline.stroke()

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 8, weight: .regular),
            .foregroundColor: NSColor.secondaryLabelColor,
        ]
        var column = 1
        var x: CGFloat = editorOrigin
        while x < bounds.maxX && column <= maximumColumn {
            let interval = majorInterval == 8 ? 8 : 10
            let major = column.isMultiple(of: interval)
            let middle = column.isMultiple(of: max(1, interval / 2))
            let tick = NSBezierPath()
            tick.move(to: NSPoint(x: x + 0.5, y: bounds.maxY - (major ? 8 : middle ? 6 : 3)))
            tick.line(to: NSPoint(x: x + 0.5, y: bounds.maxY))
            tick.stroke()
            if major { String(column).draw(at: NSPoint(x: x + 2, y: 0), withAttributes: attributes) }
            if showsTabStops, (column - 1).isMultiple(of: tabWidth) {
                NSColor.systemBlue.setFill()
                let tab = NSBezierPath()
                tab.move(to: NSPoint(x: x - 3, y: bounds.maxY - 9))
                tab.line(to: NSPoint(x: x + 3, y: bounds.maxY - 9))
                tab.line(to: NSPoint(x: x, y: bounds.maxY - 5))
                tab.close(); tab.fill()
            }
            column += 1
            x += cellWidth
        }
        let cursorX = editorOrigin + CGFloat(max(0, currentColumn - 1)) * cellWidth
        if cursorX >= editorOrigin && cursorX <= bounds.maxX {
            NSColor.controlAccentColor.setFill()
            let marker = NSBezierPath()
            marker.move(to: NSPoint(x: cursorX - 3, y: 0))
            marker.line(to: NSPoint(x: cursorX + 3, y: 0))
            marker.line(to: NSPoint(x: cursorX, y: 5))
            marker.close(); marker.fill()
        }
    }
}

private final class ClassicCommandStripView: NSView {
    private static let candidates: [(String, CommandID)] = [
        ("Help", .appHelp), ("Save", .fileSave), ("Find", .searchFind),
        ("Next", .searchFindNext), ("Previous", .searchFindPrevious),
        ("Replace", .searchReplace), ("Grep", .searchGrep), ("Macro", .appMacroMenu),
        ("Bookmark", .navigateToggleBookmark), ("Next Mark", .navigateNextBookmark),
        ("Go to Line", .searchGoToLine), ("Fold", .navigateToggleFold),
        ("Utility Pane", .viewToggleSidebar), ("Wrap", .viewToggleWrap),
        ("Settings", .appSettings),
    ]
    private static let defaultCommands: [CommandID?] = [
        .appHelp, .fileSave, .searchFind, .searchFindNext, .searchGrep, .appMacroMenu,
        .navigateToggleBookmark, .searchGoToLine, .searchReplace, .viewToggleSidebar,
        .viewToggleWrap, .appSettings,
    ]
    private static let defaultsKey = "MaruClassicFunctionKeyCommands"
    private static let mergeDefaultsKey = "MaruClassicFunctionKeysMergedWithStatus"
    private static let countDefaultsKey = "MaruClassicFunctionKeyCount"
    private var functionKeyLayout = FunctionKeyLayout(assignments: defaultCommands)
    private var buttons: [NSButton] = []
    private var candidates: [(String, CommandID)] = ClassicCommandStripView.candidates
    var onCommand: ((CommandID) -> Void)?
    var onMergeChange: (() -> Void)?
    var presentationProvider: ((CommandID) -> (enabled: Bool, selected: Bool))?
    private(set) var isMergedWithStatusBar = false
    private(set) var visibleSlotCount = 12
    var commandIDs: [String?] { functionKeyLayout.assignments.map { $0?.rawValue } }
    var keyboardFocusableViews: [NSView] {
        buttons.filter { !$0.isHidden && $0.isEnabled }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        let available = Set(candidates.map(\.1))
        if let values = UserDefaults.standard.array(forKey: Self.defaultsKey) as? [String] {
            functionKeyLayout = FunctionKeyLayout(assignments: values.map { $0.isEmpty ? nil : CommandID($0) })
                .normalized(available: available)
        } else {
            functionKeyLayout = functionKeyLayout.normalized(available: available)
        }
        isMergedWithStatusBar = UserDefaults.standard.bool(forKey: Self.mergeDefaultsKey)
        if UserDefaults.standard.object(forKey: Self.countDefaultsKey) != nil {
            visibleSlotCount = min(12, max(1, UserDefaults.standard.integer(forKey: Self.countDefaultsKey)))
        }
        rebuildButtons()
        setAccessibilityRole(.group)
        setAccessibilityLabel("Favorite command strip")
    }

    private func rebuildButtons() {
        buttons.forEach { $0.removeFromSuperview() }; buttons.removeAll()
        for (index, command) in functionKeyLayout.assignments.prefix(visibleSlotCount).enumerated() {
            let title = command.flatMap(title(for:)) ?? "Unassigned"
            let button = NSButton(title: "F\(index + 1) \(title)", target: self, action: #selector(activate(_:)))
            button.font = .systemFont(ofSize: 10)
            button.alignment = .center
            button.bezelStyle = .inline
            button.isBordered = false
            button.tag = index
            button.setAccessibilityLabel("F\(index + 1) \(title)")
            button.isEnabled = command != nil
            buttons.append(button)
            addSubview(button)
        }
        refreshCommandPresentation()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        let width = buttons.isEmpty ? 0 : bounds.width / CGFloat(buttons.count)
        for (index, button) in buttons.enumerated() {
            button.frame = NSRect(x: CGFloat(index) * width, y: 1, width: width, height: 22)
        }
    }

    @objc private func activate(_ sender: NSButton) {
        guard functionKeyLayout.assignments.indices.contains(sender.tag),
              let command = functionKeyLayout.assignments[sender.tag] else { return }
        guard presentationProvider?(command).enabled != false else { return }
        onCommand?(command)
    }

    override func rightMouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard let slot = buttons.firstIndex(where: { $0.frame.contains(point) }) else {
            super.rightMouseDown(with: event); return
        }
        let menu = NSMenu(title: "Customize F\(slot + 1)")
        for (title, command) in candidates {
            let item = NSMenuItem(title: title, action: #selector(assignCommand(_:)), keyEquivalent: "")
            item.target = self; item.representedObject = "\(slot)|\(command.rawValue)"
            item.state = functionKeyLayout.assignments[slot] == command ? .on : .off
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let merge = NSMenuItem(
            title: "Merge with Status Bar", action: #selector(toggleMergeWithStatusBar),
            keyEquivalent: "")
        merge.target = self; merge.state = isMergedWithStatusBar ? .on : .off
        menu.addItem(merge)
        let countMenu = NSMenu(title: "Visible Function Keys")
        for count in 1...12 {
            let item = NSMenuItem(
                title: "F1–F\(count)", action: #selector(changeVisibleSlotCount(_:)),
                keyEquivalent: "")
            item.target = self; item.tag = count
            item.state = visibleSlotCount == count ? .on : .off
            countMenu.addItem(item)
        }
        let countItem = NSMenuItem(title: "Visible Function Keys", action: nil, keyEquivalent: "")
        countItem.submenu = countMenu; menu.addItem(countItem)
        let clear = NSMenuItem(title: "Unassign F\(slot + 1)", action: #selector(clearCommand(_:)), keyEquivalent: "")
        clear.target = self; clear.tag = slot; menu.addItem(clear)
        let restore = NSMenuItem(title: "Restore Default Function Keys", action: #selector(restoreDefaults), keyEquivalent: "")
        restore.target = self; menu.addItem(restore)
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    @objc private func toggleMergeWithStatusBar() {
        isMergedWithStatusBar.toggle()
        UserDefaults.standard.set(isMergedWithStatusBar, forKey: Self.mergeDefaultsKey)
        onMergeChange?()
    }

    @objc private func changeVisibleSlotCount(_ sender: NSMenuItem) {
        visibleSlotCount = min(12, max(1, sender.tag))
        UserDefaults.standard.set(visibleSlotCount, forKey: Self.countDefaultsKey)
        rebuildButtons(); needsLayout = true
        onMergeChange?()
    }

    @objc private func assignCommand(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? String,
              let separator = value.firstIndex(of: "|"),
              let slot = Int(value[..<separator]), functionKeyLayout.assignments.indices.contains(slot) else { return }
        functionKeyLayout.assignments[slot] = CommandID(String(value[value.index(after: separator)...]))
        persistAndRebuild()
    }

    @objc private func clearCommand(_ sender: NSMenuItem) {
        guard functionKeyLayout.assignments.indices.contains(sender.tag) else { return }
        functionKeyLayout.assignments[sender.tag] = nil; persistAndRebuild()
    }

    @objc private func restoreDefaults() {
        functionKeyLayout = FunctionKeyLayout(assignments: Self.defaultCommands); persistAndRebuild()
    }

    private func persistAndRebuild() {
        UserDefaults.standard.set(functionKeyLayout.assignments.map { $0?.rawValue ?? "" }, forKey: Self.defaultsKey)
        rebuildButtons(); needsLayout = true
    }

    private func title(for command: CommandID) -> String? {
        candidates.first { $0.1 == command }?.0
    }

    func setCommandsForTesting(_ commands: [CommandID?]) {
        functionKeyLayout = FunctionKeyLayout(assignments: commands)
            .normalized(available: Set(candidates.map(\.1)))
        rebuildButtons(); needsLayout = true
    }

    func setMergedForTesting(_ merged: Bool) {
        isMergedWithStatusBar = merged
        onMergeChange?()
    }

    func activateSlotForTesting(_ index: Int) {
        guard index < visibleSlotCount, functionKeyLayout.assignments.indices.contains(index),
              let command = functionKeyLayout.assignments[index] else { return }
        guard presentationProvider?(command).enabled != false else { return }
        onCommand?(command)
    }

    func setVisibleSlotCountForTesting(_ count: Int) {
        visibleSlotCount = min(12, max(1, count))
        rebuildButtons(); needsLayout = true
        onMergeChange?()
    }

    func refreshCommandPresentation() {
        for button in buttons where functionKeyLayout.assignments.indices.contains(button.tag) {
            guard let command = functionKeyLayout.assignments[button.tag] else {
                button.isEnabled = false; button.state = .off; continue
            }
            let state = presentationProvider?(command) ?? (enabled: true, selected: false)
            button.isEnabled = state.enabled
            button.state = state.selected ? .on : .off
            button.alphaValue = state.enabled ? 1 : 0.42
        }
    }

    func presentation(at index: Int) -> (enabled: Bool, selected: Bool)? {
        guard buttons.indices.contains(index) else { return nil }
        return (buttons[index].isEnabled, buttons[index].state == .on)
    }

    func configureAvailableCommands(_ commands: [(CommandID, String)]) {
        let builtIns = Dictionary(uniqueKeysWithValues: Self.candidates.map { ($0.1, $0.0) })
        candidates = commands.map { (builtIns[$0.0] ?? $0.1, $0.0) }
            .sorted { $0.0.localizedCaseInsensitiveCompare($1.0) == .orderedAscending }
        functionKeyLayout = functionKeyLayout.normalized(available: Set(candidates.map(\.1)))
        rebuildButtons(); needsLayout = true
    }
}
