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
    var externalTopGap: CGFloat = 0 { didSet { needsLayout = true } }

    var headingText: String { heading.stringValue }
    var topChromeHeight: CGFloat {
        Self.toolbarHeight + (heading.isHidden ? 0 : Self.headingHeight)
            + (ruler.isHidden ? 0 : Self.rulerHeight)
    }
    var bottomChromeHeight: CGFloat { commandStrip.isHidden ? 0 : Self.commandStripHeight }

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
        toolbar.frame = NSRect(
            x: 0, y: top - Self.toolbarHeight,
            width: bounds.width, height: Self.toolbarHeight)
        heading.frame = NSRect(
            x: 8, y: top - Self.toolbarHeight - externalTopGap - Self.headingHeight + 3,
            width: max(0, bounds.width - 16), height: 16)
        ruler.frame = NSRect(
            x: 0, y: top - Self.toolbarHeight
                - externalTopGap - (heading.isHidden ? 0 : Self.headingHeight) - Self.rulerHeight,
            width: bounds.width, height: Self.rulerHeight)
        commandStrip.frame = NSRect(
            x: 0, y: 0, width: bounds.width, height: Self.commandStripHeight)
    }

    func updateHeading(_ value: String) { heading.stringValue = value }
    func updateRuler(editorOrigin: CGFloat, currentColumn: Int) {
        ruler.editorOrigin = editorOrigin
        ruler.currentColumn = currentColumn
    }

    var onCommand: ((CommandID) -> Void)? {
        get { toolbar.onCommand }
        set { toolbar.onCommand = newValue; commandStrip.onCommand = newValue }
    }

    var toolbarCommandIDs: [String] { toolbar.commandIDs.map(\.rawValue) }

    func activateToolbarCommand(_ command: CommandID) { toolbar.activate(command) }

    func applyVisibility(_ options: ClassicChromeOptions) {
        heading.isHidden = !options.showHeading
        ruler.isHidden = !options.showRuler
        commandStrip.isHidden = !options.showCommandStrip
        needsLayout = true
    }

    var visibilityForTesting: ClassicChromeOptions {
        ClassicChromeOptions(
            showHeading: !heading.isHidden,
            showRuler: !ruler.isHidden,
            showCommandStrip: !commandStrip.isHidden)
    }
    var rulerStateForTesting: (origin: CGFloat, column: Int) {
        (ruler.editorOrigin, ruler.currentColumn)
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
    private var buttons: [NSButton] = []
    private var items: [Item] = []
    private var separators: [NSView] = []
    private var hiddenKeys: Set<String> = []
    private static let hiddenDefaultsKey = "MaruClassicToolbarHiddenItems"
    var commandIDs: [CommandID] { items.compactMap(\.command) }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        hiddenKeys = Set(UserDefaults.standard.stringArray(forKey: Self.hiddenDefaultsKey) ?? [])
        setAccessibilityRole(.toolbar)
        setAccessibilityLabel("Maru Classic command toolbar")
        for (groupIndex, group) in Self.groups.enumerated() {
            if groupIndex > 0 {
                let separator = NSView()
                separator.wantsLayer = true
                separator.layer?.backgroundColor = NSColor.separatorColor.cgColor
                separators.append(separator)
                addSubview(separator)
            }
            for item in group {
                let button = ClassicToolbarButton()
                button.bezelStyle = .inline
                button.isBordered = false
                button.imagePosition = .imageOnly
                button.imageScaling = .scaleProportionallyDown
                button.image = NSImage(
                    systemSymbolName: item.symbol, accessibilityDescription: item.title)
                button.contentTintColor = item.tint
                button.toolTip = item.title
                button.setAccessibilityLabel(item.title)
                button.target = self
                button.action = #selector(activateButton(_:))
                button.tag = items.count
                items.append(item)
                buttons.append(button)
                addSubview(button)
                button.isHidden = hiddenKeys.contains(key(for: item))
            }
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        var x: CGFloat = 5
        var separatorIndex = 0
        var itemIndex = 0
        for (groupIndex, group) in Self.groups.enumerated() {
            if groupIndex > 0 {
                separators[separatorIndex].frame = NSRect(x: x + 2, y: 6, width: 1, height: 20)
                separatorIndex += 1
                x += 8
            }
            for _ in group {
                let button = buttons[itemIndex]
                button.frame = NSRect(x: x, y: 3, width: 27, height: 26)
                if !button.isHidden { x += 27 }
                itemIndex += 1
            }
        }
        let border = NSBezierPath()
        NSColor.separatorColor.setStroke()
        border.move(to: NSPoint(x: 0, y: 0.5))
        border.line(to: NSPoint(x: bounds.maxX, y: 0.5))
        border.stroke()
    }

    @objc private func activateButton(_ sender: NSButton) {
        guard items.indices.contains(sender.tag) else { return }
        let item = items[sender.tag]
        if let command = item.command { onCommand?(command) }
        else if let action = item.responderAction { NSApp.sendAction(action, to: nil, from: sender) }
    }

    func activate(_ command: CommandID) {
        guard items.contains(where: { $0.command == command }) else { return }
        onCommand?(command)
    }

    override func rightMouseDown(with event: NSEvent) {
        let menu = NSMenu(title: "Customize Maru Classic Toolbar")
        for item in items {
            let key = key(for: item)
            let menuItem = NSMenuItem(
                title: item.title, action: #selector(toggleToolbarItem(_:)), keyEquivalent: "")
            menuItem.target = self
            menuItem.representedObject = key
            menuItem.state = hiddenKeys.contains(key) ? .off : .on
            menu.addItem(menuItem)
        }
        menu.addItem(.separator())
        let restore = NSMenuItem(
            title: "Restore Default Toolbar", action: #selector(restoreDefaultToolbar),
            keyEquivalent: "")
        restore.target = self
        menu.addItem(restore)
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    @objc private func toggleToolbarItem(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String else { return }
        if hiddenKeys.contains(key) { hiddenKeys.remove(key) } else { hiddenKeys.insert(key) }
        applyCustomization()
    }

    @objc private func restoreDefaultToolbar() {
        hiddenKeys.removeAll()
        applyCustomization()
    }

    private func applyCustomization() {
        for (index, item) in items.enumerated() {
            buttons[index].isHidden = hiddenKeys.contains(key(for: item))
        }
        UserDefaults.standard.set(Array(hiddenKeys).sorted(), forKey: Self.hiddenDefaultsKey)
        needsLayout = true
    }

    private func key(for item: Item) -> String {
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
    var editorOrigin: CGFloat = 46 { didSet { needsDisplay = true } }
    var currentColumn: Int = 1 { didSet { needsDisplay = true } }
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

        let cell: CGFloat = 8
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 8, weight: .regular),
            .foregroundColor: NSColor.secondaryLabelColor,
        ]
        var column = 1
        var x: CGFloat = editorOrigin
        while x < bounds.maxX {
            let major = column.isMultiple(of: 10)
            let middle = column.isMultiple(of: 5)
            let tick = NSBezierPath()
            tick.move(to: NSPoint(x: x + 0.5, y: bounds.maxY - (major ? 8 : middle ? 6 : 3)))
            tick.line(to: NSPoint(x: x + 0.5, y: bounds.maxY))
            tick.stroke()
            if major { String(column).draw(at: NSPoint(x: x + 2, y: 0), withAttributes: attributes) }
            column += 1
            x += cell
        }
        let cursorX = editorOrigin + CGFloat(max(0, currentColumn - 1)) * cell
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
    private let items: [(String, CommandID?)] = [
        ("F1 Help", nil), ("F2 Save", .fileSave), ("F3 Find", .searchFind),
        ("F4 Next", .searchFindNext), ("F5 Grep", .searchGrep), ("F6 Macro", .appMacroMenu),
    ]
    private var buttons: [NSButton] = []
    var onCommand: ((CommandID) -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        for (index, item) in items.enumerated() {
            let button = NSButton(title: item.0, target: self, action: #selector(activate(_:)))
            button.font = .systemFont(ofSize: 10)
            button.alignment = .center
            button.bezelStyle = .inline
            button.isBordered = false
            button.tag = index
            button.setAccessibilityLabel(item.0)
            button.isEnabled = item.1 != nil
            buttons.append(button)
            addSubview(button)
        }
        setAccessibilityRole(.group)
        setAccessibilityLabel("Favorite command strip")
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
        guard items.indices.contains(sender.tag), let command = items[sender.tag].1 else { return }
        onCommand?(command)
    }
}
