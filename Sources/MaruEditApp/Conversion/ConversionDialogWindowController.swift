import AppKit
import MaruEditCore

@MainActor
final class ConversionDialogWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
    private let registry: TextConversionRegistry
    private let store: TextConversionPresetStore
    private let onApply: ([TextConversionStep]) -> Void
    private var builtIns = TextConversionRegistry.defaultPresets
    private var customPresets: [TextConversionPreset]
    private(set) var steps: [TextConversionStep] = []

    private let presetPopup = NSPopUpButton()
    private let modulePopup = NSPopUpButton()
    private let parameterField = NSTextField()
    private let replacementField = NSTextField()
    private let widthField = NSTextField(string: "4")
    private let presetNameField = NSTextField()
    private let table = NSTableView()

    init(
        registry: TextConversionRegistry = TextConversionRegistry(),
        store: TextConversionPresetStore = TextConversionPresetStore(),
        onApply: @escaping ([TextConversionStep]) -> Void
    ) {
        self.registry = registry; self.store = store; self.onApply = onApply
        customPresets = store.load()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 480),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Conversion Pipeline"
        super.init(window: window)
        buildUI()
        reloadPresets()
        if let first = builtIns.first { select(first) }
    }

    required init?(coder: NSCoder) { nil }

    private func buildUI() {
        guard let content = window?.contentView else { return }
        let root = NSStackView(); root.orientation = .vertical; root.alignment = .leading; root.spacing = 10
        root.translatesAutoresizingMaskIntoConstraints = false; content.addSubview(root)
        NSLayoutConstraint.activate([
            root.topAnchor.constraint(equalTo: content.topAnchor, constant: 18),
            root.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 18),
            root.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -18),
            root.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -18),
        ])

        presetPopup.target = self; presetPopup.action = #selector(presetChanged)
        presetPopup.setAccessibilityLabel("Conversion preset")
        root.addArrangedSubview(row("Preset", presetPopup))

        let modules = registry.availableModules
        modulePopup.addItems(withTitles: modules.map(\.title))
        for (index, module) in modules.enumerated() { modulePopup.item(at: index)?.representedObject = module.id }
        modulePopup.setAccessibilityLabel("Conversion module")
        root.addArrangedSubview(row("Add module", modulePopup))
        parameterField.placeholderString = "Search text or regular expression"
        replacementField.placeholderString = "Replacement text"
        widthField.formatter = NumberFormatter()
        for (label, field) in [("Search/Pattern", parameterField), ("Replacement", replacementField), ("Tab width", widthField)] {
            field.setAccessibilityLabel(label); root.addArrangedSubview(row(label, field))
        }
        let add = NSButton(title: "Add to Pipeline", target: self, action: #selector(addModule))
        add.setAccessibilityLabel("Add conversion module")
        root.addArrangedSubview(add)

        let column = NSTableColumn(identifier: .init("module")); column.title = "Ordered conversion modules"; column.width = 560
        table.addTableColumn(column); table.headerView = nil; table.delegate = self; table.dataSource = self
        table.setAccessibilityLabel("Conversion module pipeline")
        let scroll = NSScrollView(); scroll.documentView = table; scroll.hasVerticalScroller = true
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.heightAnchor.constraint(equalToConstant: 150).isActive = true
        root.addArrangedSubview(scroll)
        scroll.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true
        let remove = NSButton(title: "Remove", target: self, action: #selector(removeModule))
        let up = NSButton(title: "Move Up", target: self, action: #selector(moveModuleUp))
        let down = NSButton(title: "Move Down", target: self, action: #selector(moveModuleDown))
        root.addArrangedSubview(NSStackView(views: [remove, up, down]))

        presetNameField.placeholderString = "Custom preset name"
        presetNameField.setAccessibilityLabel("Custom preset name")
        let save = NSButton(title: "Save Preset", target: self, action: #selector(savePreset))
        let delete = NSButton(title: "Delete Preset", target: self, action: #selector(deletePreset))
        root.addArrangedSubview(NSStackView(views: [presetNameField, save, delete]))
        let apply = NSButton(title: "Apply", target: self, action: #selector(applyPipeline))
        apply.keyEquivalent = "\r"; apply.setAccessibilityLabel("Apply conversion pipeline")
        root.addArrangedSubview(apply)
    }

    private func row(_ title: String, _ view: NSView) -> NSView {
        let label = NSTextField(labelWithString: title); label.alignment = .right
        label.widthAnchor.constraint(equalToConstant: 105).isActive = true
        if let control = view as? NSControl { control.widthAnchor.constraint(greaterThanOrEqualToConstant: 300).isActive = true }
        return NSStackView(views: [label, view])
    }

    private var allPresets: [TextConversionPreset] { builtIns + customPresets }
    private func reloadPresets() {
        presetPopup.removeAllItems(); presetPopup.addItems(withTitles: allPresets.map(\.name))
    }
    private func select(_ preset: TextConversionPreset) {
        steps = preset.steps; presetNameField.stringValue = preset.name; table.reloadData()
    }
    @objc private func presetChanged() {
        guard allPresets.indices.contains(presetPopup.indexOfSelectedItem) else { return }
        select(allPresets[presetPopup.indexOfSelectedItem])
    }
    @objc private func addModule() {
        guard let id = modulePopup.selectedItem?.representedObject as? String else { return }
        var parameters: [String: String] = [:]
        if id == "replace.literal" { parameters = ["search": parameterField.stringValue, "replacement": replacementField.stringValue] }
        else if id == "replace.regex" { parameters = ["pattern": parameterField.stringValue, "replacement": replacementField.stringValue] }
        else if id.hasPrefix("whitespace.") { parameters = ["width": String(max(1, widthField.integerValue))] }
        steps.append(.init(moduleID: id, parameters: parameters)); table.reloadData()
        table.selectRowIndexes(IndexSet(integer: steps.count - 1), byExtendingSelection: false)
    }
    @objc private func removeModule() {
        guard steps.indices.contains(table.selectedRow) else { return }
        steps.remove(at: table.selectedRow); table.reloadData()
    }
    @objc private func moveModuleUp() { moveSelected(delta: -1) }
    @objc private func moveModuleDown() { moveSelected(delta: 1) }
    private func moveSelected(delta: Int) {
        let source = table.selectedRow, destination = source + delta
        guard steps.indices.contains(source), steps.indices.contains(destination) else { return }
        steps.swapAt(source, destination); table.reloadData()
        table.selectRowIndexes(IndexSet(integer: destination), byExtendingSelection: false)
    }
    @objc private func savePreset() {
        let name = presetNameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !steps.isEmpty else { NSSound.beep(); return }
        if let index = customPresets.firstIndex(where: { $0.name == name }) {
            customPresets[index].steps = steps
        } else { customPresets.append(.init(name: name, steps: steps)) }
        store.save(customPresets); reloadPresets()
        if let index = allPresets.firstIndex(where: { $0.name == name }) { presetPopup.selectItem(at: index) }
    }
    @objc private func deletePreset() {
        let name = presetNameField.stringValue
        guard let index = customPresets.firstIndex(where: { $0.name == name }) else { NSSound.beep(); return }
        customPresets.remove(at: index); store.save(customPresets); reloadPresets()
        if let first = allPresets.first { presetPopup.selectItem(at: 0); select(first) }
    }
    @objc private func applyPipeline() { guard !steps.isEmpty else { NSSound.beep(); return }; onApply(steps) }

    func numberOfRows(in tableView: NSTableView) -> Int { steps.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let id = steps[row].moduleID
        let title = registry.availableModules.first { $0.id == id }?.title ?? id
        let parameters = steps[row].parameters.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: ", ")
        return NSTextField(labelWithString: parameters.isEmpty ? "\(row + 1). \(title)" : "\(row + 1). \(title) — \(parameters)")
    }

    func setStepsForTesting(_ value: [TextConversionStep]) { steps = value; table.reloadData() }
    func savePresetForTesting(name: String) { presetNameField.stringValue = name; savePreset() }
    func applyForTesting() { applyPipeline() }
    var customPresetsForTesting: [TextConversionPreset] { customPresets }
}
