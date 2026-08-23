import AppKit

@MainActor
protocol TabBarViewDelegate: AnyObject {
    func tabBarDidSelectTab(at index: Int)
    func tabBarDidCloseTab(at index: Int)
    func tabBarDidMoveTab(from source: Int, to destination: Int)
    func tabBarDidRequestClose(_ scope: TabCloseScope, disposition: TabCloseDisposition, at index: Int)
    func tabBarLayoutOptionsDidChange()
}

enum TabBarPosition: String { case top, bottom }
enum TabCloseScope { case current, others, left, right, all }

/// How a close request treats documents with unsaved changes. Deciding once
/// for the whole batch is what keeps closing ten tabs from raising ten
/// separate save prompts.
enum TabCloseDisposition { case ask, saveAll, discardAll }

struct TabItem: Equatable {
    let title: String
    let isModified: Bool
}

private final class AccessibleTabLabel: NSTextField {
    var onPress: (() -> Void)?
    var forwardsMouseToTabBar = true
    var accessibilitySelectionValue: Bool?

    override var acceptsFirstResponder: Bool { true }

    override func accessibilityValue() -> String? {
        accessibilitySelectionValue.map { $0 ? "selected" : "not selected" }
            ?? super.accessibilityValue()
    }

    override func accessibilityPerformPress() -> Bool {
        guard !isHidden, let onPress else { return false }
        onPress()
        return true
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 || event.keyCode == 76 || event.charactersIgnoringModifiers == " " {
            onPress?()
        } else {
            super.keyDown(with: event)
        }
    }

    override func mouseDown(with event: NSEvent) {
        if forwardsMouseToTabBar { superview?.mouseDown(with: event) } else { onPress?() }
    }
    override func mouseDragged(with event: NSEvent) { superview?.mouseDragged(with: event) }
    override func mouseUp(with event: NSEvent) { superview?.mouseUp(with: event) }
}

final class TabBarView: NSView {
    weak var delegate: TabBarViewDelegate?

    private(set) var tabs: [TabItem] = []
    private(set) var selectedIndex: Int = 0

    private let tabHeight: CGFloat = 32
    /// How far inactive tabs are pushed away from the document edge.
    private let inactiveInset: CGFloat = 3
    private let activeLineThickness: CGFloat = 3
    private var tabWidth: CGFloat = 180
    var compactStyle = false { didSet { needsLayout = true; updateAppearance() } }
    var position: TabBarPosition {
        get { TabBarPosition(rawValue: UserDefaults.standard.string(forKey: "MaruTabBarPosition") ?? "top") ?? .top }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "MaruTabBarPosition"); delegate?.tabBarLayoutOptionsDidChange() }
    }
    var hidesForSingleTab: Bool {
        get {
            // Match Maru's compact single-document workspace while still
            // respecting an explicit user choice to keep the bar visible.
            UserDefaults.standard.object(forKey: "MaruTabBarHideSingle") == nil
                ? true
                : UserDefaults.standard.bool(forKey: "MaruTabBarHideSingle")
        }
        set { UserDefaults.standard.set(newValue, forKey: "MaruTabBarHideSingle"); delegate?.tabBarLayoutOptionsDidChange() }
    }
    var isTabModeEnabled: Bool {
        get {
            UserDefaults.standard.object(forKey: "MaruTabModeEnabled") == nil
                ? true : UserDefaults.standard.bool(forKey: "MaruTabModeEnabled")
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "MaruTabModeEnabled")
            delegate?.tabBarLayoutOptionsDidChange()
        }
    }
    /// Accent edge drawn along the outer side of the active tab.
    var showsActiveLine: Bool {
        get {
            UserDefaults.standard.object(forKey: "MaruTabActiveLine") == nil
                ? true : UserDefaults.standard.bool(forKey: "MaruTabActiveLine")
        }
        set { UserDefaults.standard.set(newValue, forKey: "MaruTabActiveLine"); updateAppearance() }
    }
    /// Distinct face color for the active tab instead of the plain bar color.
    var showsActiveFace: Bool {
        get {
            UserDefaults.standard.object(forKey: "MaruTabActiveFace") == nil
                ? true : UserDefaults.standard.bool(forKey: "MaruTabActiveFace")
        }
        set { UserDefaults.standard.set(newValue, forKey: "MaruTabActiveFace"); updateAppearance() }
    }
    var effectiveHeight: CGFloat {
        guard isTabModeEnabled else { return 0 }
        return hidesForSingleTab && tabs.count <= 1 ? 0 : tabHeight
    }
    private var pressedIndex: Int?
    private var hoveredIndex: Int? { didSet { updateAppearance() } }
    private var trackingArea: NSTrackingArea?

    private var bgLayers: [NSView] = []
    private var accentLayers: [NSView] = []
    private var titleLabels: [AccessibleTabLabel] = []
    private var closeLabels: [AccessibleTabLabel] = []
    private var separators: [NSView] = []
    private let bottomBorder = NSView()

    override var isFlipped: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = Theme.tabBarBg.cgColor

        bottomBorder.wantsLayer = true
        bottomBorder.layer?.backgroundColor = Theme.border.cgColor
        addSubview(bottomBorder)
    }

    func applyTheme() {
        layer?.backgroundColor = Theme.tabBarBg.cgColor
        bottomBorder.layer?.backgroundColor = Theme.border.cgColor
        separators.forEach { $0.layer?.backgroundColor = Theme.border.cgColor }
        updateAppearance()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Public update API

    func setTabs(_ newTabs: [TabItem], selectedIndex idx: Int) {
        let previousHeight = effectiveHeight
        let needsRebuild = newTabs.count != tabs.count
        tabs = newTabs
        selectedIndex = idx
        if needsRebuild {
            rebuildTabs()
        } else {
            updateLabels()
            // Tab geometry depends on which tab is active, so relayout as well.
            needsLayout = true
            updateAppearance()
        }
        if effectiveHeight != previousHeight {
            delegate?.tabBarLayoutOptionsDidChange()
        }
    }

    func selectTab(at index: Int) {
        guard index != selectedIndex else { return }
        selectedIndex = index
        needsLayout = true
        updateAppearance()
    }

    func updateTab(at index: Int, item: TabItem) {
        guard index >= 0, index < tabs.count, tabs[index] != item else { return }
        tabs[index] = item
        let displayTitle = item.isModified ? "● \(item.title)" : item.title
        titleLabels[index].stringValue = displayTitle
    }

    override func layout() {
        super.layout()
        let b = bounds
        // Maru's automatic-width mode keeps every tab in the available
        // row instead of introducing a horizontal scroller.
        tabWidth = tabs.isEmpty ? 180 : min(220, max(1, floor(b.width / CGFloat(tabs.count))))
        // The document sits on the far side of the bar; the active tab is the only
        // one that reaches that edge, so the separating rule breaks underneath it.
        let documentEdgeAtTop = position == .bottom
        bottomBorder.frame = NSRect(x: 0, y: documentEdgeAtTop ? 0 : tabHeight - 1, width: b.width, height: 1)

        for (i, bg) in bgLayers.enumerated() {
            let x = CGFloat(i) * tabWidth
            let active = (i == selectedIndex)
            let top: CGFloat = active ? 0 : (documentEdgeAtTop ? 1 : inactiveInset)
            let height = active ? tabHeight : tabHeight - inactiveInset - 1
            bg.frame = NSRect(x: x, y: top, width: tabWidth, height: height)
            accentLayers[i].frame = NSRect(
                x: x,
                y: documentEdgeAtTop ? tabHeight - activeLineThickness : 0,
                width: tabWidth,
                height: activeLineThickness
            )
            let textY = top + (height - 16) / 2
            titleLabels[i].frame = NSRect(x: x + (compactStyle ? 8 : 14), y: textY, width: max(0, tabWidth - (compactStyle ? 34 : 42)), height: 16)
            closeLabels[i].frame = NSRect(x: x + tabWidth - 24, y: textY, width: 14, height: 16)
            separators[i].frame = NSRect(x: x + tabWidth - 1, y: top + 4, width: 1, height: max(0, height - 8))
        }
    }

    override func updateTrackingAreas() {
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: bounds, options: [.activeInKeyWindow, .mouseMoved, .mouseEnteredAndExited], owner: self)
        addTrackingArea(area)
        trackingArea = area
        super.updateTrackingAreas()
    }

    override func mouseMoved(with event: NSEvent) {
        hoveredIndex = tabIndex(at: convert(event.locationInWindow, from: nil))
    }

    override func mouseExited(with event: NSEvent) { hoveredIndex = nil }

    private func clearAll() {
        for arr: [NSView] in [bgLayers, accentLayers, titleLabels, closeLabels, separators] {
            arr.forEach { $0.removeFromSuperview() }
        }
        bgLayers.removeAll(); accentLayers.removeAll()
        titleLabels.removeAll(); closeLabels.removeAll(); separators.removeAll()
    }

    private func rebuildTabs() {
        clearAll()

        for (index, tab) in tabs.enumerated() {
            let bg = NSView()
            bg.wantsLayer = true
            addSubview(bg)
            bgLayers.append(bg)

            let accent = NSView()
            accent.wantsLayer = true
            accent.layer?.backgroundColor = Theme.accent.cgColor
            addSubview(accent)
            accentLayers.append(accent)

            let sep = NSView()
            sep.wantsLayer = true
            sep.layer?.backgroundColor = Theme.border.cgColor
            addSubview(sep)
            separators.append(sep)

            let displayTitle = tab.isModified ? "● \(tab.title)" : tab.title
            let lbl = AccessibleTabLabel(labelWithString: displayTitle)
            lbl.font = NSFont.systemFont(ofSize: 12)
            lbl.lineBreakMode = .byTruncatingTail
            lbl.isBordered = false
            lbl.isEditable = false
            lbl.drawsBackground = false
            lbl.setAccessibilityRole(.radioButton)
            lbl.setAccessibilityLabel(AppLocalization.string("tab.accessibility", [index + 1, tab.title]))
            lbl.onPress = { [weak self] in self?.delegate?.tabBarDidSelectTab(at: index) }
            addSubview(lbl)
            titleLabels.append(lbl)

            let close = AccessibleTabLabel(labelWithString: "×")
            close.font = NSFont.systemFont(ofSize: 14, weight: .light)
            close.alignment = .center
            close.isBordered = false
            close.isEditable = false
            close.drawsBackground = false
            close.forwardsMouseToTabBar = false
            close.setAccessibilityRole(.button)
            close.setAccessibilityLabel(AppLocalization.string("tab.closeAccessibility", [index + 1, tab.title]))
            close.onPress = { [weak self] in self?.delegate?.tabBarDidCloseTab(at: index) }
            addSubview(close)
            closeLabels.append(close)
        }

        // Keep the rule behind the tabs so the active face can cover it.
        addSubview(bottomBorder, positioned: .below, relativeTo: nil)
        needsLayout = true
        updateAppearance()
    }

    private func updateLabels() {
        for (i, tab) in tabs.enumerated() where i < titleLabels.count {
            let displayTitle = tab.isModified ? "● \(tab.title)" : tab.title
            titleLabels[i].stringValue = displayTitle
            titleLabels[i].setAccessibilityLabel(AppLocalization.string("tab.accessibility", [i + 1, tab.title]))
            closeLabels[i].setAccessibilityLabel(AppLocalization.string("tab.closeAccessibility", [i + 1, tab.title]))
        }
    }

    private func updateAppearance() {
        for i in 0..<bgLayers.count {
            let active = (i == selectedIndex)
            let face: NSColor
            if active {
                face = showsActiveFace ? Theme.tabActive : Theme.tabBarBg
            } else {
                face = i == hoveredIndex ? Theme.tabHover : Theme.tabInactive
            }
            bgLayers[i].layer?.backgroundColor = face.cgColor
            accentLayers[i].layer?.backgroundColor = Theme.accent.cgColor
            accentLayers[i].isHidden = !active || !showsActiveLine
            titleLabels[i].textColor = active ? Theme.tabTextActive : Theme.tabText
            titleLabels[i].font = NSFont.systemFont(ofSize: 12, weight: active ? .bold : .regular)
            titleLabels[i].accessibilitySelectionValue = active
            closeLabels[i].isHidden = tabWidth < 42 || (i != hoveredIndex && !active)
            closeLabels[i].textColor = active ? Theme.tabTextActive : Theme.tabText.withAlphaComponent(0.75)
            // The rule between two inactive tabs only; the active tab keeps clean edges.
            separators[i].isHidden = active || (i + 1 == selectedIndex)
        }
    }

    override func mouseDown(with event: NSEvent) {
        let pt = convert(event.locationInWindow, from: nil)
        guard let idx = tabIndex(at: pt) else { return }
        pressedIndex = idx

        let tabRight = CGFloat(idx + 1) * tabWidth
        if !closeLabels[idx].isHidden, pt.x > tabRight - 30 {
            delegate?.tabBarDidCloseTab(at: idx)
        } else {
            delegate?.tabBarDidSelectTab(at: idx)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let source = pressedIndex else { return }
        let point = convert(event.locationInWindow, from: nil)
        let destination = min(tabs.count - 1, max(0, Int(point.x / tabWidth)))
        guard source != destination else { return }
        pressedIndex = destination
        delegate?.tabBarDidMoveTab(from: source, to: destination)
    }

    override func mouseUp(with event: NSEvent) { pressedIndex = nil }

    override func otherMouseDown(with event: NSEvent) {
        guard event.buttonNumber == 2 else { return }
        let point = convert(event.locationInWindow, from: nil)
        let index = Int(point.x / tabWidth)
        if tabs.indices.contains(index) { delegate?.tabBarDidCloseTab(at: index) }
    }

    override func rightMouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let menu = contextMenu(forTabAt: tabIndex(at: point))
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    func contextMenu(forTabAt clickedIndex: Int?) -> NSMenu {
        let menu = NSMenu(title: AppLocalization.string("tab.menu.title"))
        // Enablement below is computed from the tab layout, so opt out of the
        // automatic validation that would otherwise override it.
        menu.autoenablesItems = false
        if let clickedIndex {
            addCloseItem(AppLocalization.string("tab.close"), scope: .current, index: clickedIndex, to: menu)
            addCloseItem(AppLocalization.string("tab.closeOthers"), scope: .others, index: clickedIndex, to: menu)
            addCloseItem(AppLocalization.string("tab.closeLeft"), scope: .left, index: clickedIndex, to: menu)
            addCloseItem(AppLocalization.string("tab.closeRight"), scope: .right, index: clickedIndex, to: menu)
            menu.addItem(.separator())
        }
        // Batch closes: one decision covers every tab instead of one prompt per tab.
        let anchorIndex = clickedIndex ?? selectedIndex
        addCloseItem(
            AppLocalization.string("tab.closeAll"), scope: .all, index: anchorIndex, to: menu)
        addCloseItem(
            AppLocalization.string("tab.saveAllAndCloseAll"), scope: .all,
            disposition: .saveAll, index: anchorIndex, to: menu)
        addCloseItem(
            AppLocalization.string("tab.discardAllAndCloseAll"), scope: .all,
            disposition: .discardAll, index: anchorIndex, to: menu)
        menu.addItem(.separator())
        let top = NSMenuItem(title: AppLocalization.string("tab.positionTop"), action: #selector(placeAtTop), keyEquivalent: "")
        top.target = self; top.state = position == .top ? .on : .off; menu.addItem(top)
        let bottom = NSMenuItem(title: AppLocalization.string("tab.positionBottom"), action: #selector(placeAtBottom), keyEquivalent: "")
        bottom.target = self; bottom.state = position == .bottom ? .on : .off; menu.addItem(bottom)
        let single = NSMenuItem(title: AppLocalization.string("tab.hideSingle"), action: #selector(toggleHideSingle), keyEquivalent: "")
        single.target = self; single.state = hidesForSingleTab ? .on : .off; menu.addItem(single)
        menu.addItem(.separator())
        let line = NSMenuItem(title: AppLocalization.string("tab.activeLine"), action: #selector(toggleActiveLine), keyEquivalent: "")
        line.target = self; line.state = showsActiveLine ? .on : .off; menu.addItem(line)
        let face = NSMenuItem(title: AppLocalization.string("tab.activeFace"), action: #selector(toggleActiveFace), keyEquivalent: "")
        face.target = self; face.state = showsActiveFace ? .on : .off; menu.addItem(face)
        return menu
    }

    private func tabIndex(at point: NSPoint) -> Int? {
        guard tabWidth > 0 else { return nil }
        let index = Int(point.x / tabWidth)
        return tabs.indices.contains(index) ? index : nil
    }

    private func addCloseItem(
        _ title: String, scope: TabCloseScope, disposition: TabCloseDisposition = .ask,
        index: Int, to menu: NSMenu
    ) {
        let item = NSMenuItem(title: title, action: #selector(closeFromMenu(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = [scopeValue(scope), dispositionValue(disposition), index]
        switch scope {
        case .left: item.isEnabled = index > 0
        case .right: item.isEnabled = index + 1 < tabs.count
        case .others: item.isEnabled = tabs.count > 1
        case .all: item.isEnabled = !tabs.isEmpty
        case .current: break
        }
        menu.addItem(item)
    }

    private func scopeValue(_ scope: TabCloseScope) -> Int {
        switch scope {
        case .current: 0; case .others: 1; case .left: 2; case .right: 3; case .all: 4
        }
    }

    private func dispositionValue(_ disposition: TabCloseDisposition) -> Int {
        switch disposition { case .ask: 0; case .saveAll: 1; case .discardAll: 2 }
    }

    @objc private func closeFromMenu(_ sender: NSMenuItem) {
        guard let values = sender.representedObject as? [Int], values.count == 3 else { return }
        let scopes: [TabCloseScope] = [.current, .others, .left, .right, .all]
        let dispositions: [TabCloseDisposition] = [.ask, .saveAll, .discardAll]
        guard scopes.indices.contains(values[0]), dispositions.indices.contains(values[1]) else { return }
        delegate?.tabBarDidRequestClose(
            scopes[values[0]], disposition: dispositions[values[1]], at: values[2])
    }

    // Deterministic geometry hooks for interaction tests.
    var tabWidthForTesting: CGFloat { tabWidth }
    func setHoveredIndexForTesting(_ index: Int?) { hoveredIndex = index }
    var visibleCloseIndicesForTesting: [Int] {
        closeLabels.indices.filter { !closeLabels[$0].isHidden }
    }
    var accessibilityTabControlsForTesting: [(tab: NSView, close: NSView)] {
        zip(titleLabels, closeLabels).map { ($0.0, $0.1) }
    }
    var activeTabFrameForTesting: NSRect? {
        bgLayers.indices.contains(selectedIndex) ? bgLayers[selectedIndex].frame : nil
    }
    func tabFaceColorForTesting(at index: Int) -> NSColor? {
        guard bgLayers.indices.contains(index), let color = bgLayers[index].layer?.backgroundColor else { return nil }
        return NSColor(cgColor: color)
    }
    func tabFrameForTesting(at index: Int) -> NSRect? {
        bgLayers.indices.contains(index) ? bgLayers[index].frame : nil
    }
    func isActiveLineVisibleForTesting(at index: Int) -> Bool {
        accentLayers.indices.contains(index) ? !accentLayers[index].isHidden : false
    }
    func titleFontForTesting(at index: Int) -> NSFont? {
        titleLabels.indices.contains(index) ? titleLabels[index].font : nil
    }

    var keyboardFocusableViews: [NSView] {
        titleLabels + closeLabels.filter { !$0.isHidden }
    }

    @objc private func placeAtTop() { position = .top }
    @objc private func placeAtBottom() { position = .bottom }
    @objc private func toggleHideSingle() { hidesForSingleTab.toggle() }
    @objc private func toggleActiveLine() { showsActiveLine.toggle() }
    @objc private func toggleActiveFace() { showsActiveFace.toggle() }
}
