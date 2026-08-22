import AppKit
import MaruEditCore

/// The window that shows who is connected and lets the human approve, revoke,
/// and read the audit trail.
///
/// It is an ordinary non-modal window on purpose. A sheet is window-modal and
/// stops the human editing in that window, which R9 forbids — and a background
/// agent's connection attempt has no business interrupting someone mid-sentence.
/// The cost is that approval is something the human goes and does; the benefit
/// is that nothing an agent does can take the keyboard away from them.
@MainActor
final class AgentIndicatorController: NSWindowController {
    private let server: AgentServer
    private let stack = NSStackView()
    private let scroll = NSScrollView()
    private var refreshScheduled = false

    init(server: AgentServer) {
        self.server = server
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 420),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered, defer: false)
        window.title = AppLocalization.string("agent.window.title")
        window.isReleasedWhenClosed = false
        super.init(window: window)

        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        stack.translatesAutoresizingMaskIntoConstraints = false

        scroll.documentView = stack
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        window.contentView = scroll

        NSLayoutConstraint.activate([
            stack.widthAnchor.constraint(equalTo: scroll.widthAnchor),
        ])

        server.control.onChange = { [weak self] in self?.scheduleRefresh() }
        refresh()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private func scheduleRefresh() {
        guard !refreshScheduled else { return }
        refreshScheduled = true
        DispatchQueue.main.async { [weak self] in
            self?.refreshScheduled = false
            self?.refresh()
        }
    }

    func show() {
        refresh()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    // MARK: - Rendering

    private func refresh() {
        stack.arrangedSubviews.forEach {
            stack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }

        stack.addArrangedSubview(heading(AgentServer.isEnabledInSettings
            ? AppLocalization.string("agent.status.on")
            : AppLocalization.string("agent.status.off")))

        if let pairing = server.control.pendingPairing {
            stack.addArrangedSubview(pairingRow(pairing))
        }

        if server.control.connections.isEmpty {
            stack.addArrangedSubview(label(AppLocalization.string("agent.noClients"), secondary: true))
        } else {
            for connection in server.control.connections {
                stack.addArrangedSubview(connectionRow(connection))
            }
        }

        if !server.control.pairedCredentials.isEmpty {
            stack.addArrangedSubview(heading(AppLocalization.string("agent.paired")))
            for (id, name) in server.control.pairedCredentials.sorted(by: { $0.value < $1.value }) {
                stack.addArrangedSubview(credentialRow(id: id, name: name))
            }
        }

        stack.addArrangedSubview(heading(AppLocalization.string("agent.activity")))
        let recent = server.control.audit.suffix(30).reversed()
        if recent.isEmpty {
            stack.addArrangedSubview(label(AppLocalization.string("agent.noActivity"), secondary: true))
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm:ss"
            for entry in recent {
                let line = "\(formatter.string(from: entry.at))  \(entry.tool)  \(entry.outcome)"
                stack.addArrangedSubview(label(line, secondary: true, monospaced: true))
            }
        }
    }

    private func heading(_ text: String) -> NSView {
        let field = NSTextField(labelWithString: text)
        field.font = .boldSystemFont(ofSize: 13)
        return field
    }

    private func label(_ text: String, secondary: Bool = false, monospaced: Bool = false) -> NSView {
        let field = NSTextField(labelWithString: text)
        field.font = monospaced
            ? .monospacedSystemFont(ofSize: 11, weight: .regular)
            : .systemFont(ofSize: 12)
        if secondary { field.textColor = .secondaryLabelColor }
        field.lineBreakMode = .byTruncatingTail
        return field
    }

    private func row(_ views: [NSView]) -> NSView {
        let row = NSStackView(views: views)
        row.orientation = .horizontal
        row.spacing = 8
        row.alignment = .centerY
        return row
    }

    private func connectionRow(_ connection: AgentControlService.Connection) -> NSView {
        var views: [NSView] = [
            label("\(connection.displayName) · pid \(connection.bridgePID) · \(connection.status.rawValue)"),
        ]
        switch connection.status {
        case .pending:
            let approve = NSButton(
                title: AppLocalization.string("agent.approve"),
                target: self, action: #selector(approve(_:)))
            approve.identifier = NSUserInterfaceItemIdentifier(connection.id.rawValue)
            let deny = NSButton(
                title: AppLocalization.string("agent.deny"),
                target: self, action: #selector(deny(_:)))
            deny.identifier = NSUserInterfaceItemIdentifier(connection.id.rawValue)
            views.append(contentsOf: [approve, deny])
        case .approved:
            let inherit = NSButton(
                checkboxWithTitle: AppLocalization.string("agent.inheritNew"),
                target: self, action: #selector(toggleInheritance(_:)))
            inherit.state = connection.inheritsNewDocuments ? .on : .off
            inherit.identifier = NSUserInterfaceItemIdentifier(connection.id.rawValue)
            let revoke = NSButton(
                title: AppLocalization.string("agent.revoke"),
                target: self, action: #selector(revoke(_:)))
            revoke.identifier = NSUserInterfaceItemIdentifier(connection.id.rawValue)
            views.append(contentsOf: [inherit, revoke])
        default:
            break
        }
        return row(views)
    }

    private func pairingRow(_ pairing: AgentControlService.PairingRequest) -> NSView {
        let confirm = NSButton(
            title: AppLocalization.string("agent.confirmPairing"),
            target: self, action: #selector(confirmPairing))
        let cancel = NSButton(
            title: AppLocalization.string(.commonCancel),
            target: self, action: #selector(cancelPairing))
        return row([
            label(AppLocalization.string("agent.verificationCode", [pairing.verificationCode])),
            confirm, cancel,
        ])
    }

    private func credentialRow(id: String, name: String) -> NSView {
        let revoke = NSButton(
            title: AppLocalization.string("agent.revokeCredential"),
            target: self, action: #selector(revokeCredential(_:)))
        revoke.identifier = NSUserInterfaceItemIdentifier(id)
        return row([label(name), revoke])
    }

    // MARK: - Actions

    private func connection(for sender: NSButton) -> AgentControlService.Connection? {
        guard let raw = sender.identifier?.rawValue else { return nil }
        return server.control.connections.first { $0.id.rawValue == raw }
    }

    @objc private func approve(_ sender: NSButton) {
        guard let connection = connection(for: sender) else { return }
        // The grant freezes here, covering what is open at this moment. Nothing
        // opened afterwards joins it unless the human ticks the box.
        let documents = server.control.connections.isEmpty
            ? []
            : AppDelegate.sharedCoordinator?.agentVisibleTargets().map(\.document.automationID) ?? []
        server.control.approve(connection, documents: Array(Set(documents)))
        server.notifyAuthorization(connection)
    }

    @objc private func deny(_ sender: NSButton) {
        guard let connection = connection(for: sender) else { return }
        server.control.deny(connection)
        server.notifyAuthorization(connection)
    }

    @objc private func revoke(_ sender: NSButton) {
        guard let connection = connection(for: sender) else { return }
        server.control.revoke(connection)
        server.notifyAuthorization(connection)
    }

    @objc private func toggleInheritance(_ sender: NSButton) {
        guard let connection = connection(for: sender) else { return }
        server.control.setInheritance(connection, enabled: sender.state == .on)
    }

    @objc private func confirmPairing() {
        server.control.confirmPairing(label: AppLocalization.string("agent.pairedClient"))
    }

    @objc private func cancelPairing() {
        server.control.cancelPairing()
    }

    @objc private func revokeCredential(_ sender: NSButton) {
        guard let id = sender.identifier?.rawValue else { return }
        server.control.revokeCredential(id)
    }
}
