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
        server.control.proposals.onChange = { [weak self] in self?.scheduleRefresh() }
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

        stack.addArrangedSubview(heading(AppLocalization.string("agent.roots")))
        if server.control.offeredRoots.isEmpty {
            stack.addArrangedSubview(label(AppLocalization.string("agent.noRoots"), secondary: true))
        } else {
            for root in server.control.offeredRoots {
                let remove = NSButton(
                    title: AppLocalization.string("agent.removeRoot"),
                    target: self, action: #selector(removeRoot(_:)))
                remove.identifier = NSUserInterfaceItemIdentifier(root)
                stack.addArrangedSubview(row([label(root, monospaced: true), remove]))
            }
        }
        stack.addArrangedSubview(NSButton(
            title: AppLocalization.string("agent.addRoot"),
            target: self, action: #selector(addRoot)))

        let pending = server.control.proposals.pending
        if !pending.isEmpty {
            stack.addArrangedSubview(heading(AppLocalization.string("agent.pendingEdits")))
            for proposal in pending {
                stack.addArrangedSubview(proposalRow(proposal))
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
            return NSStackView(views: [row(views), capabilityRow(connection)]).configuredAsColumn()
        default:
            break
        }
        return row(views)
    }

    /// What this client may do, each granted on its own.
    ///
    /// One Approve button used to hand over reading, editing, saving, opening
    /// files, and running commands together. They are separate switches now,
    /// because they are separate decisions.
    private func capabilityRow(_ connection: AgentControlService.Connection) -> NSView {
        let options: [(String, AgentControlService.Capabilities)] = [
            ("agent.capEdit", .writeDocuments),
            ("agent.capSelection", .writeSelection),
            ("agent.capSave", .saveDocuments),
            ("agent.capOpen", .openDocuments),
            ("agent.capCommands", .runCommands),
        ]
        var views: [NSView] = options.map { key, capability in
            let box = NSButton(
                checkboxWithTitle: AppLocalization.string(key),
                target: self, action: #selector(toggleCapability(_:)))
            box.state = connection.capabilities.contains(capability) ? .on : .off
            box.identifier = NSUserInterfaceItemIdentifier(
                "\(connection.id.rawValue)|\(capability.rawValue)")
            return box
        }
        let auto = NSButton(
            checkboxWithTitle: AppLocalization.string("agent.autoApply"),
            target: self, action: #selector(toggleWriteMode(_:)))
        auto.state = connection.writeMode == .auto ? .on : .off
        auto.identifier = NSUserInterfaceItemIdentifier(connection.id.rawValue)
        views.append(auto)

        if !server.control.offeredRoots.isEmpty {
            let grantRoots = NSButton(
                title: AppLocalization.string("agent.grantRoots"),
                target: self, action: #selector(grantRoots(_:)))
            grantRoots.identifier = NSUserInterfaceItemIdentifier(connection.id.rawValue)
            views.append(grantRoots)
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
        let remember = NSButton(
            checkboxWithTitle: AppLocalization.string("agent.remember"),
            target: self, action: #selector(toggleRemembered(_:)))
        remember.state = server.control.rememberedCredentials.contains(id) ? .on : .off
        remember.identifier = NSUserInterfaceItemIdentifier(id)
        let revoke = NSButton(
            title: AppLocalization.string("agent.revokeCredential"),
            target: self, action: #selector(revokeCredential(_:)))
        revoke.identifier = NSUserInterfaceItemIdentifier(id)
        return row([label(name), remember, revoke])
    }

    /// One pending edit, with the diff the human is actually deciding about.
    ///
    /// Showing the label alone would ask them to approve a sentence rather than
    /// a change, which is not review.
    private func proposalRow(_ proposal: AgentProposalStore.Proposal) -> NSView {
        let apply = NSButton(
            title: AppLocalization.string("agent.applyEdit"),
            target: self, action: #selector(applyProposal(_:)))
        apply.identifier = NSUserInterfaceItemIdentifier(proposal.id)
        let reject = NSButton(
            title: AppLocalization.string("agent.rejectEdit"),
            target: self, action: #selector(rejectProposal(_:)))
        reject.identifier = NSUserInterfaceItemIdentifier(proposal.id)

        let column = NSStackView(views: [
            label(proposal.label),
            label(diffPreview(proposal), secondary: true, monospaced: true),
            row([apply, reject]),
        ])
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = 4
        return column
    }

    private func diffPreview(_ proposal: AgentProposalStore.Proposal) -> String {
        guard let target = AppDelegate.sharedCoordinator?.agentVisibleTargets()
            .first(where: { $0.document.automationID == proposal.documentID })
        else { return "(document closed)" }
        let text = target.document.content as NSString
        return proposal.edits.prefix(4).map { edit -> String in
            let before = NSMaxRange(edit.range) <= text.length
                ? text.substring(with: edit.range) : "?"
            let position = AgentTextSlicer.position(ofOffset: edit.range.location, in: text)
            return "line \(position.line): −\(oneLine(before))  +\(oneLine(edit.replacement))"
        }.joined(separator: "\n")
    }

    private func oneLine(_ text: String) -> String {
        let flattened = text.replacingOccurrences(of: "\n", with: "⏎")
        return flattened.count > 60 ? String(flattened.prefix(60)) + "…" : flattened
    }

    // MARK: - Actions

    private func connection(for sender: NSButton) -> AgentControlService.Connection? {
        guard let raw = sender.identifier?.rawValue else { return nil }
        return server.control.connections.first { $0.id.rawValue == raw }
    }

    @objc private func approve(_ sender: NSButton) {
        guard let connection = connection(for: sender) else { return }
        // The grant freezes here, covering what is open at this moment. Nothing
        // opened afterwards joins it unless the human ticks the box — and
        // Approve grants reading only, with everything else a separate switch.
        let documents = AppDelegate.sharedCoordinator?
            .agentVisibleTargets().map(\.document.automationID) ?? []
        server.control.approve(
            connection, documents: Array(Set(documents)),
            capabilities: .readOnly, writeMode: .review)
        server.notifyAuthorization(connection)
    }

    @objc private func toggleCapability(_ sender: NSButton) {
        guard let raw = sender.identifier?.rawValue else { return }
        let parts = raw.split(separator: "|")
        guard parts.count == 2, let bits = Int(parts[1]),
              let connection = server.control.connections.first(where: { $0.id.rawValue == parts[0] })
        else { return }
        let capability = AgentControlService.Capabilities(rawValue: bits)
        var capabilities = connection.capabilities
        if sender.state == .on {
            capabilities.insert(capability)
            // Anything that writes needs to be able to read what it is editing.
            capabilities.formUnion(.readOnly)
        } else {
            capabilities.remove(capability)
        }
        server.control.setCapabilities(connection, capabilities)
    }

    @objc private func toggleWriteMode(_ sender: NSButton) {
        guard let connection = connection(for: sender) else { return }
        server.control.setWriteMode(connection, sender.state == .on ? .auto : .review)
    }

    @objc private func grantRoots(_ sender: NSButton) {
        guard let connection = connection(for: sender) else { return }
        server.control.grantRoots(connection, server.control.offeredRoots)
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

    @objc private func applyProposal(_ sender: NSButton) {
        guard let id = sender.identifier?.rawValue,
              let proposal = server.control.proposals.proposal(id),
              let target = AppDelegate.sharedCoordinator?.agentVisibleTargets()
                  .first(where: { $0.document.automationID == proposal.documentID })
        else { return }
        _ = AgentToolExecutor.applyProposal(
            proposal,
            target: AgentToolExecutor.Target(document: target.document, editor: target.editor),
            store: server.control.proposals)
    }

    @objc private func rejectProposal(_ sender: NSButton) {
        guard let id = sender.identifier?.rawValue else { return }
        server.control.proposals.mark(id, .rejected)
    }

    @objc private func addRoot() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = AppLocalization.string("agent.addRoot")
        // Non-modal, like everything else here: the human opens this window
        // deliberately, so a panel they summoned is not an interruption.
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.server.control.addAuthorizedRoot(url.path)
        }
    }

    @objc private func removeRoot(_ sender: NSButton) {
        guard let path = sender.identifier?.rawValue else { return }
        server.control.removeAuthorizedRoot(path)
    }

    @objc private func toggleRemembered(_ sender: NSButton) {
        guard let id = sender.identifier?.rawValue else { return }
        server.control.setRemembered(id, sender.state == .on)
    }

    @objc private func revokeCredential(_ sender: NSButton) {
        guard let id = sender.identifier?.rawValue else { return }
        server.control.revokeCredential(id)
    }
}

private extension NSStackView {
    /// Stacks rows vertically, left-aligned, for the two-line connection entry.
    func configuredAsColumn() -> NSStackView {
        orientation = .vertical
        alignment = .leading
        spacing = 4
        return self
    }
}
