import AppKit
import MaruEditCore

final class SettingsWindowController: NSWindowController, NSSearchFieldDelegate {
    enum Level: Int { case basic, advanced }
    enum Group: String, CaseIterable {
        case general, editor, appearance, files, searchGroup, keyBindings, macros, advanced
        var localizedTitle: String { SettingsLocalization.text(rawValue) }
    }

    private var preferences: Preferences
    private let onChange: (Preferences) -> Void
    private let transferStore = PreferencesStore()
    private let searchField = NSSearchField()
    private let levelPopup = NSPopUpButton()
    private let sidebar = NSStackView()
    private let content = NSView()
    private var groupButtons: [Group: NSButton] = [:]
    private var selectedGroup: Group = .general
    private var level: Level = .basic
    private var settingsQuery = ""

    private let fontNameField = NSTextField()
    private let fontSizeField = NSTextField()
    private let tabWidthField = NSTextField()
    private let lineNumbersButton = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let wrapModePopup = NSPopUpButton()
    private let wrapColumnField = NSTextField()
    private let workspacePopup = NSPopUpButton()
    private let headingButton = NSButton(checkboxWithTitle: "Show document heading", target: nil, action: nil)
    private let rulerButton = NSButton(checkboxWithTitle: "Show character ruler", target: nil, action: nil)
    private let commandStripButton = NSButton(checkboxWithTitle: "Show favorite command strip", target: nil, action: nil)

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
        levelPopup.addItems(withTitles: ["Basic", "Advanced"])
        levelPopup.selectItem(at: Level.basic.rawValue)
        levelPopup.target = self; levelPopup.action = #selector(levelChanged)
        levelPopup.translatesAutoresizingMaskIntoConstraints = false
        levelPopup.setAccessibilityLabel("Settings detail level")
        root.addSubview(levelPopup)

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
            searchField.trailingAnchor.constraint(equalTo: levelPopup.leadingAnchor, constant: -12),
            levelPopup.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),
            levelPopup.centerYAnchor.constraint(equalTo: searchField.centerYAnchor),
            levelPopup.widthAnchor.constraint(equalToConstant: 110),
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
        refreshGroupVisibility()
    }

    @objc private func levelChanged() {
        level = Level(rawValue: levelPopup.indexOfSelectedItem) ?? .basic
        refreshGroupVisibility()
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
            wrapModePopup.removeAllItems()
            wrapModePopup.addItems(withTitles: ["wrapNone", "wrapWindow", "wrapFixed", "wrapMaximum"].map {
                SettingsLocalization.text($0)
            })
            wrapModePopup.selectItem(at: WrapMode.allCases.firstIndex(of: preferences.wrapMode) ?? 0)
            wrapModePopup.target = self; wrapModePopup.action = #selector(controlChanged)
            wrapModePopup.identifier = NSUserInterfaceItemIdentifier("settings.wrapMode")
            configureNumeric(wrapColumnField, value: preferences.wrapColumn, id: "settings.wrapColumn")
            stack.addArrangedSubview(lineNumbersButton)
            stack.addArrangedSubview(row(SettingsLocalization.text("wrapMode"), wrapModePopup))
            stack.addArrangedSubview(row(SettingsLocalization.text("wrapColumn"), wrapColumnField))
        case .appearance:
            fontNameField.stringValue = preferences.fontName
            fontNameField.target = self; fontNameField.action = #selector(controlChanged)
            fontNameField.identifier = NSUserInterfaceItemIdentifier("settings.fontName")
            configureNumeric(fontSizeField, value: Int(preferences.fontSize), id: "settings.fontSize")
            stack.addArrangedSubview(row(SettingsLocalization.text("fontName"), fontNameField))
            stack.addArrangedSubview(row(SettingsLocalization.text("fontSize"), fontSizeField))
        case .general:
            workspacePopup.removeAllItems()
            workspacePopup.addItems(withTitles: [
                SettingsLocalization.text("classicWorkspace"),
                SettingsLocalization.text("modernWorkspace"),
            ])
            workspacePopup.selectItem(at: preferences.workspaceStyle == .classic ? 0 : 1)
            workspacePopup.target = self; workspacePopup.action = #selector(controlChanged)
            workspacePopup.identifier = NSUserInterfaceItemIdentifier("settings.workspaceStyle")
            stack.addArrangedSubview(row(SettingsLocalization.text("workspace"), workspacePopup))
            for (button, value, id) in [
                (headingButton, preferences.classicChrome.showHeading, "settings.classicHeading"),
                (rulerButton, preferences.classicChrome.showRuler, "settings.classicRuler"),
                (commandStripButton, preferences.classicChrome.showCommandStrip, "settings.classicCommandStrip"),
            ] {
                button.state = value ? .on : .off
                button.target = self; button.action = #selector(controlChanged)
                button.identifier = NSUserInterfaceItemIdentifier(id)
                stack.addArrangedSubview(button)
            }
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
        if group != .advanced {
            let exportSection = NSButton(title: "Export This Section…", target: self, action: #selector(showSectionExportPanel))
            let importSection = NSButton(title: "Import This Section…", target: self, action: #selector(showSectionImportPanel))
            exportSection.setAccessibilityLabel(exportSection.title)
            importSection.setAccessibilityLabel(importSection.title)
            stack.addArrangedSubview(NSStackView(views: [exportSection, importSection]))
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
            preferences.wrapMode = WrapMode.allCases[wrapModePopup.indexOfSelectedItem]
            preferences.wrapLines = preferences.wrapMode != .none
            preferences.wrapColumn = max(20, min(8_000, wrapColumnField.integerValue))
        case .appearance:
            preferences.fontName = fontNameField.stringValue.isEmpty
                ? Preferences.defaults.fontName : fontNameField.stringValue
            preferences.fontSize = Double(max(8, min(72, fontSizeField.integerValue)))
        case .general:
            preferences.workspaceStyle = workspacePopup.indexOfSelectedItem == 0 ? .classic : .modern
            preferences.theme = preferences.workspaceStyle == .classic ? .classicLight : .monokai
            preferences.classicChrome = ClassicChromeOptions(
                showHeading: headingButton.state == .on,
                showRuler: rulerButton.state == .on,
                showCommandStrip: commandStripButton.state == .on)
        default: break
        }
        onChange(preferences)
    }

    @objc private func restoreGroupDefaults() {
        let defaults = Preferences.defaults
        switch selectedGroup {
        case .general:
            preferences.workspaceStyle = defaults.workspaceStyle
            preferences.theme = defaults.theme
            preferences.classicChrome = defaults.classicChrome
        case .editor:
            preferences.tabWidth = defaults.tabWidth
            preferences.showLineNumbers = defaults.showLineNumbers
            preferences.wrapLines = defaults.wrapLines
            preferences.wrapMode = defaults.wrapMode
            preferences.wrapColumn = defaults.wrapColumn
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

    @objc private func showSectionExportPanel() {
        guard let window else { return }
        let panel = NSSavePanel(); panel.nameFieldStringValue = "MaruEdit-\(selectedGroup.rawValue)-settings.json"
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let self, let url = panel.url else { return }
            do { try self.exportSection(self.selectedGroup, to: url) }
            catch { self.presentTransferError(error) }
        }
    }

    @objc private func showSectionImportPanel() {
        guard let window else { return }
        let panel = NSOpenPanel(); panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let self, let url = panel.url else { return }
            do { try self.importSection(self.selectedGroup, from: url) }
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

    private struct SectionEnvelope: Codable {
        let group: String
        let preferences: Preferences
    }

    func exportSection(_ group: Group, to url: URL) throws {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(SectionEnvelope(group: group.rawValue, preferences: preferences))
            .write(to: url, options: .atomic)
    }

    func importSection(_ group: Group, from url: URL) throws {
        let envelope = try JSONDecoder().decode(SectionEnvelope.self, from: Data(contentsOf: url))
        guard envelope.group == group.rawValue else {
            throw CocoaError(.fileReadCorruptFile, userInfo: [NSLocalizedDescriptionKey: "The settings file belongs to the \(envelope.group) section."])
        }
        let imported = envelope.preferences
        switch group {
        case .general:
            preferences.workspaceStyle = imported.workspaceStyle
            preferences.theme = imported.theme
            preferences.classicChrome = imported.classicChrome
        case .editor:
            preferences.tabWidth = imported.tabWidth
            preferences.showLineNumbers = imported.showLineNumbers
            preferences.wrapLines = imported.wrapLines
            preferences.wrapMode = imported.wrapMode
            preferences.wrapColumn = imported.wrapColumn
            preferences.invisibleCharacters = imported.invisibleCharacters
        case .appearance:
            preferences.fontName = imported.fontName
            preferences.fontSize = imported.fontSize
            preferences.theme = imported.theme
        case .advanced: preferences = imported
        default: break
        }
        onChange(preferences); select(selectedGroup)
    }

    func controlTextDidChange(_ obj: Notification) {
        guard obj.object as AnyObject? === searchField else { return }
        settingsQuery = searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        refreshGroupVisibility()
    }

    private func refreshGroupVisibility() {
        let basic: Set<Group> = [.general, .editor, .appearance, .files, .searchGroup]
        let visible = Group.allCases.filter {
            (level == .advanced || basic.contains($0))
                && (settingsQuery.isEmpty || $0.localizedTitle.lowercased().contains(settingsQuery))
        }
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
    func setLevelForTesting(_ value: Level) {
        levelPopup.selectItem(at: value.rawValue); levelChanged()
    }
    func setWorkspaceForTesting(_ style: WorkspaceStyle) {
        select(.general)
        workspacePopup.selectItem(at: style == .classic ? 0 : 1)
        controlChanged()
    }
    func setClassicChromeForTesting(_ options: ClassicChromeOptions) {
        select(.general)
        headingButton.state = options.showHeading ? .on : .off
        rulerButton.state = options.showRuler ? .on : .off
        commandStripButton.state = options.showCommandStrip ? .on : .off
        controlChanged()
    }
    func setWrappingForTesting(_ mode: WrapMode, column: Int) {
        select(.editor)
        wrapModePopup.selectItem(at: WrapMode.allCases.firstIndex(of: mode) ?? 0)
        wrapColumnField.integerValue = column
        controlChanged()
    }
}
