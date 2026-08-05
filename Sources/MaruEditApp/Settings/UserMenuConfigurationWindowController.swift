import AppKit
import MaruEditCore

final class UserMenuConfigurationWindowController: NSWindowController, NSTextViewDelegate {
    private let definitions: [CommandDefinition]
    private var configuration: UserMenuConfiguration
    private let onChange: (UserMenuConfiguration) -> Void
    private let menuPopup = NSPopUpButton()
    private let editor = NSTextView()
    private let reference = NSTextView()
    private var selectedMenu = 0
    private var isLoading = false

    init(
        definitions: [CommandDefinition], configuration: UserMenuConfiguration,
        onChange: @escaping (UserMenuConfiguration) -> Void
    ) {
        self.definitions = definitions.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        self.configuration = configuration
        self.onChange = onChange
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 520),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        window.title = AppLocalization.string("settings.userMenus.title")
        window.minSize = NSSize(width: 560, height: 360)
        window.center()
        super.init(window: window)
        buildUI()
        loadSelectedMenu()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private func buildUI() {
        guard let root = window?.contentView else { return }
        let explanation = NSTextField(wrappingLabelWithString:
            AppLocalization.string("settings.userMenus.explanation"))
        explanation.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(explanation)

        menuPopup.addItems(withTitles: (1...8).map { AppLocalization.string("settings.userMenus.number", [$0]) })
        menuPopup.target = self; menuPopup.action = #selector(menuChanged)
        menuPopup.translatesAutoresizingMaskIntoConstraints = false
        menuPopup.setAccessibilityLabel(AppLocalization.string("settings.userMenus.numberLabel"))
        root.addSubview(menuPopup)

        let editScroll = scrollView(for: editor, editable: true)
        editor.delegate = self
        editor.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        editor.setAccessibilityLabel(AppLocalization.string("settings.userMenus.orderedIDs"))
        root.addSubview(editScroll)

        let referenceScroll = scrollView(for: reference, editable: false)
        reference.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        reference.string = definitions.map {
            "\($0.id.rawValue)  —  \(AppLocalization.commandTitle(id: $0.id.rawValue, english: $0.title))"
        }.joined(separator: "\n")
        reference.setAccessibilityLabel(AppLocalization.string("settings.userMenus.availableIDs"))
        root.addSubview(referenceScroll)

        let reset = NSButton(title: AppLocalization.string("settings.userMenus.clear"), target: self, action: #selector(clearMenu))
        reset.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(reset)
        NSLayoutConstraint.activate([
            explanation.topAnchor.constraint(equalTo: root.topAnchor, constant: 16),
            explanation.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            explanation.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),
            menuPopup.topAnchor.constraint(equalTo: explanation.bottomAnchor, constant: 12),
            menuPopup.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            reset.centerYAnchor.constraint(equalTo: menuPopup.centerYAnchor),
            reset.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),
            editScroll.topAnchor.constraint(equalTo: menuPopup.bottomAnchor, constant: 10),
            editScroll.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            editScroll.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -16),
            editScroll.widthAnchor.constraint(equalTo: root.widthAnchor, multiplier: 0.38, constant: -20),
            referenceScroll.topAnchor.constraint(equalTo: editScroll.topAnchor),
            referenceScroll.leadingAnchor.constraint(equalTo: editScroll.trailingAnchor, constant: 12),
            referenceScroll.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),
            referenceScroll.bottomAnchor.constraint(equalTo: editScroll.bottomAnchor),
        ])
    }

    private func scrollView(for textView: NSTextView, editable: Bool) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.hasVerticalScroller = true; scroll.borderType = .bezelBorder
        textView.isEditable = editable; textView.isSelectable = true
        textView.isVerticallyResizable = true; textView.autoresizingMask = [.width]
        scroll.documentView = textView
        return scroll
    }

    @objc private func menuChanged() {
        persistEditor()
        selectedMenu = max(0, menuPopup.indexOfSelectedItem)
        loadSelectedMenu()
    }

    @objc private func clearMenu() {
        configuration[selectedMenu] = []
        loadSelectedMenu(); onChange(configuration)
    }

    func textDidChange(_ notification: Notification) {
        guard !isLoading else { return }
        persistEditor()
    }

    private func persistEditor() {
        configuration[selectedMenu] = editor.string.components(separatedBy: .newlines)
        onChange(configuration)
    }

    private func loadSelectedMenu() {
        isLoading = true
        editor.string = configuration[selectedMenu].joined(separator: "\n")
        isLoading = false
    }

    var configurationForTesting: UserMenuConfiguration { configuration }
    func setEntriesForTesting(_ entries: [String], menu: Int) {
        configuration[menu] = entries; onChange(configuration)
        if selectedMenu == menu { loadSelectedMenu() }
    }
}
