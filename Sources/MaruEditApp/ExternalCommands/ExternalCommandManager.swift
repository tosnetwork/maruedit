import AppKit
import MaruEditCore

@MainActor
final class ExternalCommandManager: NSObject {
    let configurationURL: URL
    private let coordinator: AppCoordinator
    private let confirmShell: (ExternalCommandConfiguration) -> Bool
    private var registeredIDs: Set<CommandID> = []
    private var runningControllers: [ObjectIdentifier: ExternalCommandController] = [:]
    private(set) var configurations: [ExternalCommandConfiguration] = []
    private(set) var lastError: String?
    private(set) lazy var menu = NSMenu(title: AppLocalization.string("menu.other.tools"))

    init(configurationURL: URL = ExternalCommandManager.defaultConfigurationURL,
         coordinator: AppCoordinator,
         confirmShell: ((ExternalCommandConfiguration) -> Bool)? = nil) {
        self.configurationURL = configurationURL
        self.coordinator = coordinator
        self.confirmShell = confirmShell ?? { command in
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = AppLocalization.string("external.shell.title")
            alert.informativeText = AppLocalization.string("external.shell.explanation", [command.name])
            alert.addButton(withTitle: AppLocalization.string(.commonRun))
            alert.addButton(withTitle: AppLocalization.string(.commonCancel))
            return alert.runModal() == .alertFirstButtonReturn
        }
    }

    nonisolated static var defaultConfigurationURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MaruEdit/ExternalCommands.json")
    }

    func reload() {
        for id in registeredIDs { coordinator.commandRegistry.unregister(id) }
        registeredIDs.removeAll(); configurations = []; lastError = nil
        do {
            if FileManager.default.fileExists(atPath: configurationURL.path) {
                configurations = try ExternalCommandConfigurationStore.decode(Data(contentsOf: configurationURL))
            }
            for configuration in configurations {
                coordinator.commandRegistry.register(CommandDefinition(
                    id: configuration.commandID, title: configuration.name,
                    execute: { [weak self] _ in self?.execute(configuration) }))
                registeredIDs.insert(configuration.commandID)
            }
        } catch {
            lastError = error.localizedDescription
        }
        rebuildMenu()
    }

    private func execute(_ configuration: ExternalCommandConfiguration) {
        guard !configuration.shellMode || confirmShell(configuration) else { return }
        let controller = ExternalCommandController(coordinator: coordinator)
        let key = ObjectIdentifier(controller)
        runningControllers[key] = controller
        controller.didFinish = { [weak self] result in
            self?.runningControllers.removeValue(forKey: key)
            if case .failure(let error) = result {
                self?.coordinator.showStatusMessage(error.localizedDescription, duration: 5)
            }
        }
        _ = controller.run(configuration)
    }

    private func rebuildMenu() {
        menu.removeAllItems()
        for configuration in configurations {
            let title = configuration.shellMode
                ? AppLocalization.string("external.shell.menuTitle", [configuration.name]) : configuration.name
            let item = NSMenuItem(title: title, action: #selector(runCommand(_:)), keyEquivalent: "")
            item.target = self; item.representedObject = configuration.commandID
            item.toolTip = configuration.riskDescription
            menu.addItem(item)
        }
        if configurations.isEmpty {
            let item = NSMenuItem(title: AppLocalization.string(
                lastError == nil ? "external.none" : "external.configurationError"), action: nil, keyEquivalent: "")
            item.isEnabled = false; menu.addItem(item)
        }
        menu.addItem(.separator())
        let reload = NSMenuItem(title: AppLocalization.string("external.reload"), action: #selector(reloadAction), keyEquivalent: "")
        reload.target = self; menu.addItem(reload)
        let open = NSMenuItem(title: AppLocalization.string("external.openConfiguration"), action: #selector(openConfiguration), keyEquivalent: "")
        open.target = self; menu.addItem(open)
    }

    @objc private func runCommand(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? CommandID else { return }
        _ = coordinator.commandRegistry.execute(id, context: CommandContext(coordinator: coordinator))
    }
    @objc private func reloadAction() { reload() }
    @objc private func openConfiguration() {
        do {
            try FileManager.default.createDirectory(
                at: configurationURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            if !FileManager.default.fileExists(atPath: configurationURL.path) {
                try ExternalCommandConfigurationStore.encode([]).write(to: configurationURL, options: .atomic)
            }
            NSWorkspace.shared.open(configurationURL)
        } catch {
            coordinator.showStatusMessage(error.localizedDescription, duration: 5)
        }
    }

    func runForTesting(_ id: CommandID) {
        let item = NSMenuItem(); item.representedObject = id; runCommand(item)
    }
}
