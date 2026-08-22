import AppKit
import MaruEditCore

/// Listens on the private Unix socket and serves bridge connections.
///
/// Off by default and creating nothing until switched on: while the setting is
/// off there is no socket, no registry entry, and no token on disk, which is
/// the only "disabled" worth the name.
@MainActor
final class AgentServer {
    static let enabledDefaultsKey = "MaruAgentInterfaceEnabled"

    private let coordinator: AppCoordinator
    let control: AgentControlService
    private let home: URL

    private var listenerDescriptor: Int32 = -1
    private var acceptSource: DispatchSourceRead?
    private var connections: [ObjectIdentifier: ConnectionState] = [:]
    private var pendingChangeIDs: Set<AutomationID> = []

    private(set) var isRunning = false

    init(coordinator: AppCoordinator, home: URL = URL(fileURLWithPath: NSHomeDirectory())) {
        self.coordinator = coordinator
        self.control = AgentControlService(home: home)
        self.home = home
    }

    static var isEnabledInSettings: Bool {
        UserDefaults.standard.bool(forKey: enabledDefaultsKey)
    }

    // MARK: - Lifecycle

    func startIfEnabled() {
        guard Self.isEnabledInSettings, !isRunning else { return }
        start()
    }

    func start() {
        guard !isRunning else { return }
        let directory = AgentEndpoint.instanceDirectory(
            home: home, serverInstanceID: control.serverInstanceID)
        do {
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700])

            let tokenURL = AgentEndpoint.tokenURL(
                home: home, serverInstanceID: control.serverInstanceID)
            try Data(control.sessionToken.utf8).write(to: tokenURL, options: .atomic)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600], ofItemAtPath: tokenURL.path)

            let socketDirectory = AgentEndpoint.socketDirectory(home: home)
            try FileManager.default.createDirectory(
                at: socketDirectory, withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700])
            let socketURL = AgentEndpoint.socketURL(
                home: home, serverInstanceID: control.serverInstanceID)
            listenerDescriptor = try UnixSocket.listen(at: socketURL.path)

            let instance = AgentEndpoint.Instance(
                serverInstanceID: control.serverInstanceID,
                pid: ProcessInfo.processInfo.processIdentifier,
                startTime: AgentEndpoint.processStartTime(
                    pid: ProcessInfo.processInfo.processIdentifier) ?? 0,
                socketPath: socketURL.path)

            // Discovery data only — never the token, per ADR-011 §3.1.
            let endpointURL = AgentEndpoint.endpointURL(
                home: home, serverInstanceID: control.serverInstanceID)
            try instance.json.encoded().write(to: endpointURL, options: .atomic)

            try AgentEndpoint.updateRegistry(home: home) { existing in
                existing.filter {
                    $0.serverInstanceID != instance.serverInstanceID
                        && AgentEndpoint.isAlive($0, now: AgentEndpoint.processStartTime(pid:))
                } + [instance]
            }

            let source = DispatchSource.makeReadSource(
                fileDescriptor: listenerDescriptor, queue: .main)
            source.setEventHandler { [weak self] in self?.acceptOne() }
            source.resume()
            acceptSource = source
            isRunning = true
        } catch {
            stop()
        }
    }

    func stop() {
        acceptSource?.cancel()
        acceptSource = nil
        for state in connections.values { state.close() }
        connections.removeAll()
        if listenerDescriptor >= 0 {
            close(listenerDescriptor)
            listenerDescriptor = -1
        }
        let directory = AgentEndpoint.instanceDirectory(
            home: home, serverInstanceID: control.serverInstanceID)
        try? FileManager.default.removeItem(at: directory)
        try? FileManager.default.removeItem(
            at: AgentEndpoint.socketURL(home: home, serverInstanceID: control.serverInstanceID))
        try? AgentEndpoint.updateRegistry(home: home) { existing in
            existing.filter { $0.serverInstanceID != self.control.serverInstanceID }
        }
        isRunning = false
    }

    // MARK: - Connections

    private final class ConnectionState {
        let descriptor: Int32
        let source: DispatchSourceRead
        var buffer = Data()
        var connection: AgentControlService.Connection?

        init(descriptor: Int32, source: DispatchSourceRead) {
            self.descriptor = descriptor
            self.source = source
        }

        func close() {
            source.cancel()
            Foundation.close(descriptor)
        }
    }

    private func acceptOne() {
        let descriptor = accept(listenerDescriptor, nil, nil)
        guard descriptor >= 0 else { return }
        UnixSocket.prepareAccepted(descriptor)
        do {
            // Proves same user and nothing more: a precondition, never an
            // authorization (ADR-012 §4.3).
            try UnixSocket.requireSameUser(descriptor)
        } catch {
            close(descriptor)
            return
        }
        let source = DispatchSource.makeReadSource(fileDescriptor: descriptor, queue: .main)
        let state = ConnectionState(descriptor: descriptor, source: source)
        connections[ObjectIdentifier(state)] = state
        source.setEventHandler { [weak self, weak state] in
            guard let self, let state else { return }
            self.readAvailable(state)
        }
        source.setCancelHandler { [weak self, weak state] in
            guard let self, let state else { return }
            if let connection = state.connection { self.control.disconnect(connection) }
            self.connections.removeValue(forKey: ObjectIdentifier(state))
        }
        source.resume()
    }

    private func readAvailable(_ state: ConnectionState) {
        let chunk: Data
        do { chunk = try UnixSocket.read(state.descriptor) } catch { state.close(); return }
        guard !chunk.isEmpty else { state.close(); return }
        state.buffer.append(chunk)

        while true {
            let frame: Data?
            do { frame = try AgentFraming.decode(from: &state.buffer) } catch {
                // An oversized or malformed frame closes the connection rather
                // than being partially interpreted.
                state.close()
                return
            }
            guard let frame, let value = try? JSONValue.decode(frame) else { return }
            handle(value, on: state)
        }
    }

    private func handle(_ value: JSONValue, on state: ConnectionState) {
        if let hello = AgentEnvelope.Hello.parse(value) {
            switch control.register(hello: hello) {
            case .success(let connection):
                state.connection = connection
                // The true status: a remembered credential is approved on
                // arrival, and saying "pending" there would be a lie the bridge
                // used to act on.
                let approved = connection.status == .approved
                send(AgentEnvelope.AuthorizationState(
                    status: approved ? .approved : .pending,
                    message: approved
                        ? ""
                        : "Waiting for approval in MaruEdit's agent indicator.").json, on: state)
            case .failure(let failure):
                send(AgentEnvelope.Reply(id: 0, outcome: failure.outcome).json, on: state)
                state.close()
            }
            return
        }
        if let cancel = AgentEnvelope.Cancel.parse(value) {
            // Nothing here is long-running yet; recorded so the audit trail
            // shows the client asked.
            if let connection = state.connection {
                control.record(
                    connection: connection, tool: "agent.cancel",
                    document: nil, outcome: "id \(cancel.id)")
            }
            return
        }
        guard let call = AgentEnvelope.Call.parse(value) else { return }
        guard let connection = state.connection else {
            send(AgentEnvelope.Reply(id: call.id, outcome: .failure(
                code: "protocol.no_hello",
                message: "control.hello must be the first frame.",
                details: nil)).json, on: state)
            return
        }
        let executor = AgentToolExecutor(coordinator: coordinator, control: control)
        Task { @MainActor [weak self, weak state] in
            let outcome = await executor.run(
                tool: call.tool, arguments: call.arguments, connection: connection)
            guard let self, let state else { return }
            self.send(AgentEnvelope.Reply(id: call.id, outcome: outcome).json, on: state)
        }
    }

    private func send(_ value: JSONValue, on state: ConnectionState) {
        guard let payload = try? value.encoded(),
              let frame = try? AgentFraming.encode(payload)
        else { return }
        try? UnixSocket.writeAll(state.descriptor, frame)
    }

    /// Tells approved clients that a document changed, so a long-lived agent
    /// can invalidate its cache instead of polling.
    ///
    /// Coalesced per document per run-loop turn: typing produces one revision
    /// per keystroke, and a notification per keystroke would be worse than
    /// useless.
    func documentDidChange(_ documentID: AutomationID) {
        guard isRunning, !pendingChangeIDs.contains(documentID) else { return }
        pendingChangeIDs.insert(documentID)
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let ids = self.pendingChangeIDs
            self.pendingChangeIDs.removeAll()
            for id in ids {
                for state in self.connections.values {
                    guard let connection = state.connection,
                          connection.status == .approved,
                          self.control.mayAccess(connection, document: id)
                    else { continue }
                    self.send(AgentEnvelope.Event(documentID: id.rawValue).json, on: state)
                }
            }
        }
    }

    /// Pushes an approval decision to every connection that was waiting.
    func notifyAuthorization(_ connection: AgentControlService.Connection) {
        guard let state = connections.values.first(where: { $0.connection === connection }) else { return }
        let status: AgentEnvelope.AuthorizationState.Status
        switch connection.status {
        case .approved: status = .approved
        case .pending: status = .pending
        case .denied: status = .denied
        case .disconnected: status = .disconnected
        case .expired: status = .expired
        }
        send(AgentEnvelope.AuthorizationState(status: status, message: "").json, on: state)
    }
}
