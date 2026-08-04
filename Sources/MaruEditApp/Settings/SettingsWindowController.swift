import AppKit
import MaruEditCore

final class SettingsWindowController: NSWindowController, NSSearchFieldDelegate {
    enum Group: String, CaseIterable {
        case general, editor, appearance, files, searchGroup, keyBindings, macros, advanced
        var localizedTitle: String { SettingsLocalization.text(rawValue) }
    }

    private var preferences: Preferences
    private let onChange: (Preferences) -> Void
    private let transferStore = PreferencesStore()
    private let searchField = NSSearchField()
    private let sidebar = NSStackView()
    private let content = NSView()
    private var groupButtons: [Group: NSButton] = [:]
    private var selectedGroup: Group = .general

    private let fontNameField = NSTextField()
    private let fontSizeField = NSTextField()
    private let tabWidthField = NSTextField()
    private let lineNumbersButton = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let wrapLinesButton = NSButton(checkboxWithTitle: "", target: nil, action: nil)

    init(preferences: Preferences, onChange: @escaping (Preferences) -> Void) {
        self.preferences = preferences
        self.onChange = onChange
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 440),
            styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = SettingsLocalization.text("settings")
        window.center()
        window.setFrameAutosaveName("SettingsWindow")
        super.init(window: window)
        buildUI()
        select(.general)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private func buildUI() {
        guard let root = window?.contentView else { return }
        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.placeholderString = SettingsLocalization.text("search")
        searchField.setAccessibilityLabel(SettingsLocalization.text("search"))
        searchField.delegate = self
        root.addSubview(searchField)

        sidebar.orientation = .vertical
        sidebar.alignment = .leading
        sidebar.spacing = 4
        sidebar.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(sidebar)
        for group in Group.allCases {
            let button = NSButton(title: group.localizedTitle, target: self, action: #selector(selectGroup(_:)))
            button.bezelStyle = .recessed
            button.setButtonType(.toggle)
            button.identifier = NSUserInterfaceItemIdentifier("settings.group.\(group.rawValue)")
            button.setAccessibilityLabel(group.localizedTitle)
            button.tag = Group.allCases.firstIndex(of: group)!
            sidebar.addArrangedSubview(button)
            groupButtons[group] = button
        }

        content.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(content)
        let restore = NSButton(
            title: SettingsLocalization.text("restore"), target: self, action: #selector(restoreGroupDefaults))
        restore.translatesAutoresizingMaskIntoConstraints = false
        restore.identifier = NSUserInterfaceItemIdentifier("settings.restoreDefaults")
        root.addSubview(restore)

        NSLayoutConstraint.activate([
            searchField.topAnchor.constraint(equalTo: root.topAnchor, constant: 16),
            searchField.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            searchField.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),
            sidebar.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 16),
            sidebar.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            sidebar.widthAnchor.constraint(equalToConstant: 150),
            content.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 16),
            content.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: 24),
            content.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),
            content.bottomAnchor.constraint(equalTo: restore.topAnchor, constant: -12),
            restore.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            restore.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -16),
        ])
        window?.initialFirstResponder = searchField
    }

    @objc private func selectGroup(_ sender: NSButton) {
        select(Group.allCases[sender.tag])
    }

    private func select(_ group: Group) {
        selectedGroup = group
        groupButtons.forEach { $0.value.state = $0.key == group ? .on : .off }
        content.subviews.forEach { $0.removeFromSuperview() }
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor),
        ])
        let heading = NSTextField(labelWithString: group.localizedTitle)
        heading.font = .systemFont(ofSize: 18, weight: .semibold)
        stack.addArrangedSubview(heading)

        switch group {
        case .editor:
            configureNumeric(tabWidthField, value: preferences.tabWidth, id: "settings.tabWidth")
            stack.addArrangedSubview(row(SettingsLocalization.text("tabWidth"), tabWidthField))
            lineNumbersButton.title = SettingsLocalization.text("lineNumbers")
            lineNumbersButton.state = preferences.showLineNumbers ? .on : .off
            lineNumbersButton.target = self; lineNumbersButton.action = #selector(controlChanged)
            lineNumbersButton.identifier = NSUserInterfaceItemIdentifier("settings.showLineNumbers")
            wrapLinesButton.title = SettingsLocalization.text("wrapLines")
            wrapLinesButton.state = preferences.wrapLines ? .on : .off
            wrapLinesButton.target = self; wrapLinesButton.action = #selector(controlChanged)
            wrapLinesButton.identifier = NSUserInterfaceItemIdentifier("settings.wrapLines")
            stack.addArrangedSubview(lineNumbersButton)
            stack.addArrangedSubview(wrapLinesButton)
        case .appearance:
            fontNameField.stringValue = preferences.fontName
            fontNameField.target = self; fontNameField.action = #selector(controlChanged)
            fontNameField.identifier = NSUserInterfaceItemIdentifier("settings.fontName")
            configureNumeric(fontSizeField, value: Int(preferences.fontSize), id: "settings.fontSize")
            stack.addArrangedSubview(row(SettingsLocalization.text("fontName"), fontNameField))
            stack.addArrangedSubview(row(SettingsLocalization.text("fontSize"), fontSizeField))
        case .general:
            stack.addArrangedSubview(NSTextField(wrappingLabelWithString: SettingsLocalization.text("immediate")))
        case .advanced:
            stack.addArrangedSubview(NSTextField(
                wrappingLabelWithString: SettingsLocalization.text("settingsTransfer")))
            let export = NSButton(
                title: SettingsLocalization.text("exportSettings"),
                target: self, action: #selector(showExportPanel))
            let importButton = NSButton(
                title: SettingsLocalization.text("importSettings"),
                target: self, action: #selector(showImportPanel))
            let restoreAll = NSButton(
                title: SettingsLocalization.text("restoreAll"),
                target: self, action: #selector(restoreAllSettings))
            for button in [export, importButton, restoreAll] {
                button.setAccessibilityLabel(button.title)
                stack.addArrangedSubview(button)
            }
        default:
            stack.addArrangedSubview(NSTextField(wrappingLabelWithString: SettingsLocalization.text("comingSoon")))
        }
    }

    private func row(_ title: String, _ control: NSView) -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal; row.spacing = 12; row.alignment = .centerY
        let label = NSTextField(labelWithString: title)
        label.widthAnchor.constraint(equalToConstant: 120).isActive = true
        control.widthAnchor.constraint(equalToConstant: 180).isActive = true
        control.setAccessibilityLabel(title)
        row.addArrangedSubview(label); row.addArrangedSubview(control)
        return row
    }

    private func configureNumeric(_ field: NSTextField, value: Int, id: String) {
        field.integerValue = value
        field.formatter = NumberFormatter()
        field.target = self; field.action = #selector(controlChanged)
        field.identifier = NSUserInterfaceItemIdentifier(id)
    }

    @objc private func controlChanged() {
        switch selectedGroup {
        case .editor:
            preferences.tabWidth = max(1, min(16, tabWidthField.integerValue))
            preferences.showLineNumbers = lineNumbersButton.state == .on
            preferences.wrapLines = wrapLinesButton.state == .on
        case .appearance:
            preferences.fontName = fontNameField.stringValue.isEmpty
                ? Preferences.defaults.fontName : fontNameField.stringValue
            preferences.fontSize = Double(max(8, min(72, fontSizeField.integerValue)))
        default: break
        }
        onChange(preferences)
    }

    @objc private func restoreGroupDefaults() {
        let defaults = Preferences.defaults
        switch selectedGroup {
        case .editor:
            preferences.tabWidth = defaults.tabWidth
            preferences.showLineNumbers = defaults.showLineNumbers
            preferences.wrapLines = defaults.wrapLines
        case .appearance:
            preferences.fontName = defaults.fontName
            preferences.fontSize = defaults.fontSize
            preferences.theme = defaults.theme
        case .advanced:
            preferences = defaults
        default: break
        }
        onChange(preferences)
        select(selectedGroup)
    }

    @objc private func showExportPanel() {
        guard let window else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "MaruEdit-settings.json"
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let self, let url = panel.url else { return }
            do { try self.exportSettings(to: url) }
            catch { self.presentTransferError(error) }
        }
    }

    @objc private func showImportPanel() {
        guard let window else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let self, let url = panel.url else { return }
            do { try self.importSettings(from: url) }
            catch { self.presentTransferError(error) }
        }
    }

    @objc private func restoreAllSettings() {
        preferences = .defaults
        onChange(preferences)
        select(selectedGroup)
    }

    private func presentTransferError(_ error: Error) {
        guard let window else { return }
        let alert = NSAlert(error: error)
        alert.beginSheetModal(for: window)
    }

    func exportSettings(to url: URL) throws {
        try transferStore.export(preferences, to: url)
    }

    func importSettings(from url: URL) throws {
        preferences = try transferStore.importSettings(from: url)
        onChange(preferences)
        select(selectedGroup)
    }

    func controlTextDidChange(_ obj: Notification) {
        guard obj.object as AnyObject? === searchField else { return }
        let query = searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let visible = Group.allCases.filter { query.isEmpty || $0.localizedTitle.lowercased().contains(query) }
        groupButtons.forEach { $0.value.isHidden = !visible.contains($0.key) }
        if !visible.contains(selectedGroup), let first = visible.first { select(first) }
    }

    // Deterministic test surface without exposing the controls publicly.
    var currentPreferences: Preferences { preferences }
    var visibleGroups: [Group] { Group.allCases.filter { groupButtons[$0]?.isHidden == false } }
    func selectForTesting(_ group: Group) { select(group) }
    func restoreForTesting() { restoreGroupDefaults() }
    func restoreAllForTesting() { restoreAllSettings() }
    func searchForTesting(_ query: String) {
        searchField.stringValue = query
        controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: searchField))
    }
}
