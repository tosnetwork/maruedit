import AppKit

struct ExternalHelpEntry: Codable, Equatable {
    var name: String
    var target: String

    var isConfigured: Bool {
        !target.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

final class ExternalHelpStore {
    private let defaults: UserDefaults
    private let key = "MaruEditExternalHelpEntries"

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    func load() -> [ExternalHelpEntry] {
        let decoded = defaults.data(forKey: key)
            .flatMap { try? JSONDecoder().decode([ExternalHelpEntry].self, from: $0) } ?? []
        return (0..<6).map { index in
            decoded.indices.contains(index) ? decoded[index]
                : ExternalHelpEntry(name: "External Help \(index + 1)", target: "")
        }
    }

    func save(_ entries: [ExternalHelpEntry]) {
        var normalized = Array(entries.prefix(6))
        while normalized.count < 6 {
            normalized.append(ExternalHelpEntry(
                name: "External Help \(normalized.count + 1)", target: ""))
        }
        if let data = try? JSONEncoder().encode(normalized) { defaults.set(data, forKey: key) }
    }
}

@MainActor
final class ExternalHelpWindowController: NSWindowController {
    private var nameFields: [NSTextField] = []
    private var targetFields: [NSTextField] = []
    private let onSave: ([ExternalHelpEntry]) -> Void

    init(entries: [ExternalHelpEntry], onSave: @escaping ([ExternalHelpEntry]) -> Void) {
        self.onSave = onSave
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 330),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Configure External Help"
        window.center()
        super.init(window: window)
        buildUI(entries: entries)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private func buildUI(entries: [ExternalHelpEntry]) {
        guard let root = window?.contentView else { return }
        let grid = NSGridView()
        grid.translatesAutoresizingMaskIntoConstraints = false
        grid.addRow(with: [NSTextField(labelWithString: "Slot"),
                           NSTextField(labelWithString: "Menu Name"),
                           NSTextField(labelWithString: "URL or Local File")])
        for index in 0..<6 {
            let entry = entries[index]
            let name = NSTextField(string: entry.name)
            let target = NSTextField(string: entry.target)
            name.setAccessibilityLabel("External Help \(index + 1) name")
            target.setAccessibilityLabel("External Help \(index + 1) URL or file")
            nameFields.append(name); targetFields.append(target)
            grid.addRow(with: [NSTextField(labelWithString: "\(index + 1)"), name, target])
        }
        grid.column(at: 0).width = 34
        grid.column(at: 1).width = 180
        grid.column(at: 2).width = 390
        root.addSubview(grid)
        let save = NSButton(title: "Save", target: self, action: #selector(saveEntries))
        save.keyEquivalent = "\r"; save.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(save)
        NSLayoutConstraint.activate([
            grid.topAnchor.constraint(equalTo: root.topAnchor, constant: 18),
            grid.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 18),
            grid.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -18),
            save.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -18),
            save.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -14),
        ])
    }

    @objc private func saveEntries() {
        let entries = (0..<6).map { index in
            let name = nameFields[index].stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            return ExternalHelpEntry(
                name: name.isEmpty ? "External Help \(index + 1)" : name,
                target: targetFields[index].stringValue.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        onSave(entries); close()
    }

    func setEntryForTesting(slot: Int, name: String, target: String) {
        guard nameFields.indices.contains(slot) else { return }
        nameFields[slot].stringValue = name; targetFields[slot].stringValue = target
    }

    func saveForTesting() { saveEntries() }
}
