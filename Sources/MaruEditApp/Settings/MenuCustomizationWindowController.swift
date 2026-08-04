import AppKit
import MaruEditCore

final class MenuCustomizationWindowController: NSWindowController {
    private let definitions: [CommandDefinition]
    private let protectedCommandIDs: Set<CommandID>
    private var customization: MenuCustomization
    private let onChange: (MenuCustomization) -> Void
    private var checkboxes: [CommandID: NSButton] = [:]

    init(
        definitions: [CommandDefinition],
        protectedCommandIDs: Set<CommandID>,
        customization: MenuCustomization,
        onChange: @escaping (MenuCustomization) -> Void
    ) {
        self.definitions = definitions.sorted { $0.id.rawValue < $1.id.rawValue }
        self.protectedCommandIDs = protectedCommandIDs
        self.customization = customization
        self.onChange = onChange
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        window.title = "Customize Menus"
        window.minSize = NSSize(width: 460, height: 360)
        window.center()
        super.init(window: window)
        buildUI()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private func buildUI() {
        guard let root = window?.contentView else { return }
        let explanation = NSTextField(wrappingLabelWithString:
            "Choose which MaruEdit commands appear in menus. Required macOS items are always shown.")
        explanation.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(explanation)

        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        let stack = NSStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.edgeInsets = NSEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
        for definition in definitions {
            let protected = protectedCommandIDs.contains(definition.id)
            let suffix = protected ? " — Required" : ""
            let checkbox = NSButton(
                checkboxWithTitle: "\(definition.title)  [\(definition.id.rawValue)]\(suffix)",
                target: self, action: #selector(visibilityChanged(_:)))
            checkbox.identifier = NSUserInterfaceItemIdentifier(definition.id.rawValue)
            checkbox.state = customization.hiddenCommands.contains(definition.id) ? .off : .on
            checkbox.isEnabled = !protected
            checkbox.setAccessibilityLabel("Show \(definition.title) in menus")
            stack.addArrangedSubview(checkbox)
            checkboxes[definition.id] = checkbox
        }
        scroll.documentView = stack
        // A scroll view does not infer a document view's width from its
        // intrinsic content size. Pinning the stack to the clip view gives
        // AppKit enough geometry to lay out its arranged checkboxes while its
        // intrinsic height remains scrollable.
        stack.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor).isActive = true
        root.addSubview(scroll)

        let restore = NSButton(
            title: "Restore Default Menus", target: self, action: #selector(restoreDefaults))
        restore.translatesAutoresizingMaskIntoConstraints = false
        restore.setAccessibilityLabel("Restore default menus")
        root.addSubview(restore)
        NSLayoutConstraint.activate([
            explanation.topAnchor.constraint(equalTo: root.topAnchor, constant: 16),
            explanation.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            explanation.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),
            scroll.topAnchor.constraint(equalTo: explanation.bottomAnchor, constant: 12),
            scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),
            scroll.bottomAnchor.constraint(equalTo: restore.topAnchor, constant: -12),
            restore.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            restore.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -16),
        ])
    }

    @objc private func visibilityChanged(_ sender: NSButton) {
        guard let raw = sender.identifier?.rawValue else { return }
        let id = CommandID(raw)
        guard !protectedCommandIDs.contains(id) else {
            sender.state = .on
            return
        }
        customization.setVisible(sender.state == .on, command: id)
        onChange(customization)
    }

    @objc private func restoreDefaults() {
        customization = .defaults
        for checkbox in checkboxes.values { checkbox.state = .on }
        onChange(customization)
    }

    var currentCustomization: MenuCustomization { customization }
    func setVisibleForTesting(_ visible: Bool, command: CommandID) {
        guard let checkbox = checkboxes[command] else { return }
        checkbox.state = visible ? .on : .off
        visibilityChanged(checkbox)
    }
    func restoreForTesting() { restoreDefaults() }
    func checkboxForTesting(_ command: CommandID) -> NSButton? { checkboxes[command] }
}
