import AppKit
import MaruEditCore
import ObjectiveC

@MainActor
struct AuthorizedMacroRun {
    let permissions: Set<MacroPermission>
    let stopAccessing: () -> Void
}

@MainActor
final class MacroPermissionAuthorizer {
    let store: MacroPermissionStore
    private let chooseDirectory: (UserMacro) -> URL?
    private let confirmExternalCommands: (UserMacro) -> Bool

    init(store: MacroPermissionStore = MacroPermissionStore(),
         chooseDirectory: ((UserMacro) -> URL?)? = nil,
         confirmExternalCommands: ((UserMacro) -> Bool)? = nil) {
        self.store = store
        self.chooseDirectory = chooseDirectory ?? { macro in
            let panel = NSOpenPanel()
            panel.title = "Allow \(macro.metadata.name) to Access a Folder"
            panel.message = "The macro can access only the folder you select."
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            panel.allowsMultipleSelection = false
            return panel.runModal() == .OK ? panel.url : nil
        }
        self.confirmExternalCommands = confirmExternalCommands ?? { macro in
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Allow External Commands?"
            alert.informativeText = "\(macro.metadata.name) requests permission to launch external programs."
            alert.addButton(withTitle: "Allow")
            alert.addButton(withTitle: "Deny")
            return alert.runModal() == .alertFirstButtonReturn
        }
    }

    func authorize(_ macro: UserMacro) -> Result<AuthorizedMacroRun, MacroAuthorizationError> {
        var allowed: Set<MacroPermission> = [.currentDocument]
        if macro.metadata.requiredPermissions.contains(.clipboard) { allowed.insert(.clipboard) }
        if macro.metadata.requiredPermissions.contains(.network) {
            return .failure(.init(macroID: macro.id, permission: .network,
                                  reason: "network access is never available to macros"))
        }
        var accessed: [URL] = []
        if macro.metadata.requiredPermissions.contains(.otherFiles) {
            let existing = store.decision(for: macro.id, permission: .otherFiles)
            if existing?.decision == .denied {
                return .failure(.init(macroID: macro.id, permission: .otherFiles,
                                      reason: "the remembered decision is Deny"))
            }
            var directory: URL?
            if let bookmark = existing?.directoryBookmark {
                var stale = false
                directory = try? URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope],
                                     relativeTo: nil, bookmarkDataIsStale: &stale)
                if stale { directory = nil }
            }
            if directory == nil {
                directory = chooseDirectory(macro)
                guard let directory else {
                    store.save(.init(macroID: macro.id, permission: .otherFiles, decision: .denied))
                    return .failure(.init(macroID: macro.id, permission: .otherFiles,
                                          reason: "no directory was authorized"))
                }
                guard let bookmark = try? directory.bookmarkData(
                    options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil) else {
                    return .failure(.init(macroID: macro.id, permission: .otherFiles,
                                          reason: "the security-scoped bookmark could not be created"))
                }
                store.save(.init(macroID: macro.id, permission: .otherFiles, decision: .allowed,
                                 directoryBookmark: bookmark, directoryDisplayPath: directory.path))
            }
            if let directory {
                _ = directory.startAccessingSecurityScopedResource()
                accessed.append(directory)
                allowed.insert(.otherFiles)
            }
        }
        if macro.metadata.requiredPermissions.contains(.externalCommands) {
            let existing = store.decision(for: macro.id, permission: .externalCommands)
            let approved: Bool
            if let existing { approved = existing.decision == .allowed }
            else {
                approved = confirmExternalCommands(macro)
                store.save(.init(macroID: macro.id, permission: .externalCommands,
                                 decision: approved ? .allowed : .denied))
            }
            guard approved else {
                accessed.forEach { $0.stopAccessingSecurityScopedResource() }
                return .failure(.init(macroID: macro.id, permission: .externalCommands,
                                      reason: "the remembered decision is Deny"))
            }
            allowed.insert(.externalCommands)
        }
        return .success(.init(permissions: allowed) {
            accessed.forEach { $0.stopAccessingSecurityScopedResource() }
        })
    }
}

private final class FlippedMacroPermissionStackView: NSStackView {
    override var isFlipped: Bool { true }
}

final class MacroPermissionWindowController: NSWindowController {
    private let store: MacroPermissionStore
    private let stack = FlippedMacroPermissionStackView()
    var onRevoke: (() -> Void)?
    init(store: MacroPermissionStore) {
        self.store = store
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 360),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "Macro Permissions"
        super.init(window: window)
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 8
        stack.edgeInsets = .init(top: 16, left: 16, bottom: 16, right: 16)
        let scroll = NSScrollView(frame: window.contentView!.bounds)
        scroll.autoresizingMask = [.width, .height]; scroll.hasVerticalScroller = true
        scroll.documentView = stack
        stack.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor).isActive = true
        window.contentView?.addSubview(scroll)
        reload()
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }
    func reload() {
        for view in stack.arrangedSubviews { stack.removeArrangedSubview(view); view.removeFromSuperview() }
        let grants = store.load().grants
        if grants.isEmpty { stack.addArrangedSubview(NSTextField(labelWithString: "No remembered macro permissions.")) }
        for grant in grants {
            let row = NSStackView(); row.orientation = .horizontal; row.spacing = 10
            let detail = grant.directoryDisplayPath.map { " — \($0)" } ?? ""
            row.addArrangedSubview(NSTextField(labelWithString:
                "\(grant.macroID.rawValue): \(grant.permission.rawValue) = \(grant.decision.rawValue)\(detail)"))
            let button = NSButton(title: "Revoke", target: self, action: #selector(revoke(_:)))
            button.representedGrant = grant
            row.addArrangedSubview(button); stack.addArrangedSubview(row)
        }
    }
    @objc private func revoke(_ sender: NSButton) {
        guard let grant = sender.representedGrant else { return }
        store.revoke(macroID: grant.macroID, permission: grant.permission)
        reload(); onRevoke?()
    }
    var displayedRowsForTesting: Int { store.load().grants.count }
    func revokeForTesting(_ grant: MacroPermissionGrant) {
        store.revoke(macroID: grant.macroID, permission: grant.permission); reload(); onRevoke?()
    }
}

@MainActor private var grantKey: UInt8 = 0
private extension NSButton {
    var representedGrant: MacroPermissionGrant? {
        get { objc_getAssociatedObject(self, &grantKey) as? MacroPermissionGrant }
        set { objc_setAssociatedObject(self, &grantKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }
}
