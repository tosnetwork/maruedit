import AppKit
import MaruEditCore

struct MacroErrorEntry: Equatable {
    let date: Date
    let macroName: String
    let message: String
}

final class MacroErrorConsoleWindowController: NSWindowController {
    private let textView = NSTextView()
    convenience init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 360),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "Macro Error Console"
        self.init(window: window)
        let scroll = NSScrollView(frame: window.contentView!.bounds)
        scroll.autoresizingMask = [.width, .height]
        scroll.hasVerticalScroller = true
        textView.isEditable = false
        textView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        scroll.documentView = textView
        window.contentView?.addSubview(scroll)
    }
    func display(_ entries: [MacroErrorEntry]) {
        let formatter = ISO8601DateFormatter()
        textView.string = entries.map {
            "[\(formatter.string(from: $0.date))] \($0.macroName)\n\($0.message)"
        }.joined(separator: "\n\n")
        textView.scrollToEndOfDocument(nil)
    }
    var displayedText: String { textView.string }
}

final class MacroManager: NSObject, @unchecked Sendable {
    let directory: URL
    private let coordinator: AppCoordinator
    private let keyBindings: KeyBindingManager
    private let enablementStore: MacroEnablementStore
    private let authorizer: MacroPermissionAuthorizer
    private let engine = MacroEngine()
    private(set) var catalog = MacroCatalog(macros: [], issues: [])
    private(set) var errors: [MacroErrorEntry] = []
    var executionDidFinish: ((CommandID, Result<MacroRunResult, MacroExecutionError>) -> Void)?
    private var registeredIDs: Set<CommandID> = []
    private(set) lazy var menu = NSMenu(title: "Macro")
    private var errorConsole: MacroErrorConsoleWindowController?
    private var permissionWindow: MacroPermissionWindowController?

    init(directory: URL = MacroManager.defaultDirectory,
         coordinator: AppCoordinator, keyBindings: KeyBindingManager,
         enablementStore: MacroEnablementStore = MacroEnablementStore(),
         authorizer: MacroPermissionAuthorizer = MacroPermissionAuthorizer()) {
        self.directory = directory
        self.coordinator = coordinator
        self.keyBindings = keyBindings
        self.enablementStore = enablementStore
        self.authorizer = authorizer
    }

    static var defaultDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("MaruEdit/Macros", isDirectory: true)
    }

    func reload() {
        for id in registeredIDs { coordinator.commandRegistry.unregister(id) }
        registeredIDs.removeAll()
        catalog = MacroCatalogLoader.load(from: directory, disabledIDs: enablementStore.disabledIDs())
        for macro in catalog.macros {
            let definition = CommandDefinition(
                id: macro.id, title: macro.metadata.name,
                isEnabled: { _ in macro.isEnabled },
                execute: { [weak self] _ in self?.execute(macro) })
            coordinator.commandRegistry.register(definition)
            registeredIDs.insert(macro.id)
        }
        keyBindings.setDynamicBindings(catalog.macros.compactMap { macro in
            guard macro.isEnabled, let shortcut = macro.metadata.shortcut,
                  let gesture = KeyGesture(shortcut) else { return nil }
            return KeyBinding(keys: [gesture], command: macro.id)
        })
        rebuildMenu()
        for issue in catalog.issues { appendError(name: issue.url.lastPathComponent, message: issue.message) }
    }

    private func execute(_ macro: UserMacro) {
        let authorization: AuthorizedMacroRun
        switch authorizer.authorize(macro) {
        case .success(let value): authorization = value
        case .failure(let error):
            let message = error.localizedDescription
            appendError(name: macro.metadata.name, message: message)
            executionDidFinish?(macro.id, .failure(.javascript(.init(
                message: message, stack: nil, line: nil, column: nil))))
            return
        }
        engine.run(macro.source, host: coordinator.makeMacroHost(
            permissions: authorization.permissions)) { [weak self] result in
            authorization.stopAccessing()
            DispatchQueue.main.async {
                if case .failure(let error) = result {
                    let message: String
                    switch error {
                    case .cancelled: message = "Macro cancelled."
                    case .timedOut: message = "Macro timed out."
                    case .javascript(let js):
                        message = [js.message, js.stack].compactMap { $0 }.joined(separator: "\n")
                    }
                    self?.appendError(name: macro.metadata.name, message: message)
                }
                self?.executionDidFinish?(macro.id, result)
            }
        }
    }

    private func rebuildMenu() {
        menu.removeAllItems()
        for macro in catalog.macros where macro.isEnabled {
            let item = NSMenuItem(title: macro.metadata.name, action: #selector(runMacro(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = macro.id
            item.toolTip = macro.metadata.description
            if let shortcut = macro.metadata.shortcut, let gesture = KeyGesture(shortcut) {
                item.keyEquivalent = gesture.menuKeyEquivalent ?? ""
                item.keyEquivalentModifierMask = gesture.menuModifierFlags
            }
            menu.addItem(item)
        }
        if catalog.macros.filter({ $0.isEnabled }).isEmpty {
            let empty = NSMenuItem(title: "No Enabled Macros", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        }
        menu.addItem(.separator())
        let manage = NSMenuItem(title: "Enable Macros", action: nil, keyEquivalent: "")
        let manageMenu = NSMenu(title: "Enable Macros")
        for macro in catalog.macros {
            let item = NSMenuItem(title: macro.metadata.name, action: #selector(toggleMacro(_:)), keyEquivalent: "")
            item.target = self; item.representedObject = macro.id
            item.state = macro.isEnabled ? NSControl.StateValue.on : NSControl.StateValue.off
            manageMenu.addItem(item)
        }
        manage.submenu = manageMenu
        menu.addItem(manage)
        menu.addItem(NSMenuItem(title: "Reload Macros", action: #selector(reloadAction), keyEquivalent: ""))
        menu.items.last?.target = self
        menu.addItem(NSMenuItem(title: "Open Macro Folder", action: #selector(openFolder), keyEquivalent: ""))
        menu.items.last?.target = self
        menu.addItem(NSMenuItem(title: "Show Error Console", action: #selector(showErrorConsole), keyEquivalent: ""))
        menu.items.last?.target = self
        menu.addItem(NSMenuItem(title: "Manage Permissions", action: #selector(showPermissions), keyEquivalent: ""))
        menu.items.last?.target = self
    }

    @objc private func runMacro(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? CommandID else { return }
        _ = coordinator.commandRegistry.execute(id, context: CommandContext(coordinator: coordinator))
    }
    @objc private func toggleMacro(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? CommandID,
              let macro = catalog.macros.first(where: { $0.id == id }) else { return }
        enablementStore.setEnabled(!macro.isEnabled, id: id)
        reload()
    }
    @objc private func reloadAction() { reload() }
    @objc private func openFolder() {
        _ = MacroCatalogLoader.load(from: directory)
        NSWorkspace.shared.open(directory)
    }
    @objc private func showErrorConsole() {
        if errorConsole == nil { errorConsole = MacroErrorConsoleWindowController() }
        errorConsole?.display(errors)
        errorConsole?.showWindow(nil)
        errorConsole?.window?.makeKeyAndOrderFront(nil)
    }
    @objc private func showPermissions() {
        if permissionWindow == nil {
            permissionWindow = MacroPermissionWindowController(store: authorizer.store)
        }
        permissionWindow?.reload()
        permissionWindow?.showWindow(nil)
        permissionWindow?.window?.makeKeyAndOrderFront(nil)
    }
    private func appendError(name: String, message: String) {
        errors.append(.init(date: Date(), macroName: name, message: message))
        if errors.count > 500 { errors.removeFirst(errors.count - 500) }
        errorConsole?.display(errors)
    }

    func runForTesting(_ id: CommandID) { runMacro(itemForTesting(id)) }
    func toggleForTesting(_ id: CommandID) { toggleMacro(itemForTesting(id)) }
    func showErrorConsoleForTesting() { showErrorConsole() }
    func showPermissionsForTesting() { showPermissions() }
    var permissionWindowForTesting: MacroPermissionWindowController? { permissionWindow }
    var errorConsoleTextForTesting: String { errorConsole?.displayedText ?? "" }
    private func itemForTesting(_ id: CommandID) -> NSMenuItem {
        let item = NSMenuItem(); item.representedObject = id; return item
    }
}
