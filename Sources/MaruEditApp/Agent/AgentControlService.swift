import AppKit
import MaruEditCore

/// Authorization, pairing, grants, rate limiting, and the audit trail for the
/// agent interface.
///
/// What this can and cannot buy is stated plainly in ADR-012 P9: same-UID is
/// one trust domain. Any unsandboxed process running as this user can read the
/// session token and any credential file, so none of this is an isolation
/// boundary against a hostile local process. What it does provide — and what is
/// worth having on its own — is that agent activity is deliberate, attributable,
/// visible, revocable, and bounded.
@MainActor
final class AgentControlService: ObservableObject {

    // MARK: - Types

    enum ConnectionStatus: String {
        case pending, approved, denied, disconnected, expired
    }

    /// One live bridge connection.
    final class Connection {
        let id: AutomationID
        /// The paired configuration this connection presented, if any.
        let credentialID: String?
        /// Self-reported and therefore display-only, always labelled as such.
        let claimedName: String?
        let bridgePID: Int32
        var status: ConnectionStatus = .pending
        /// Documents this connection may see. Frozen at approval: a grant that
        /// silently grew to cover whatever the human opened next would turn
        /// "read what I have open" into "read anything I open".
        var grantedDocuments: Set<AutomationID> = []
        /// Opt-in, default off, and lapses with the connection.
        var inheritsNewDocuments = false
        /// Bumped on revoke so an in-flight call can notice before it commits.
        var grantGeneration: UInt64 = 0
        var requestTimestamps: [Date] = []

        init(id: AutomationID, credentialID: String?, claimedName: String?, bridgePID: Int32) {
            self.id = id
            self.credentialID = credentialID
            self.claimedName = claimedName
            self.bridgePID = bridgePID
        }

        var displayName: String {
            claimedName.map { "\($0) (unverified)" } ?? "Unidentified MCP client"
        }
    }

    struct AuditEntry: Identifiable {
        let id = UUID()
        let at: Date
        let connection: String
        let credentialID: String?
        let tool: String
        let document: String?
        let outcome: String
    }

    struct PairingRequest {
        let verificationCode: String
        let credentialID: String
        let credentialPath: String
        let requestedAt: Date
    }

    // MARK: - Limits

    /// Byte-weighted, not request-counted: a handful of enormous calls cost
    /// what they actually cost.
    static let requestsPerMinute = 120
    static let auditEntryLimit = 500

    // MARK: - State

    private(set) var connections: [Connection] = []
    private(set) var audit: [AuditEntry] = []
    private(set) var pendingPairing: PairingRequest?
    /// Credential id → human-readable label, persisted so a paired config is
    /// recognized after a restart even though its *grant* is not.
    private(set) var pairedCredentials: [String: String] = [:]

    private let home: URL
    let sessionToken: String
    let serverInstanceID: String

    /// Called when the set of connections changes, so the UI can refresh
    /// without polling.
    var onChange: (() -> Void)?

    init(home: URL = URL(fileURLWithPath: NSHomeDirectory())) {
        self.home = home
        self.sessionToken = Self.randomToken()
        self.serverInstanceID = Self.randomToken(bytes: 8)
        loadCredentials()
    }

    static func randomToken(bytes count: Int = 32) -> String {
        var bytes = [UInt8](repeating: 0, count: count)
        _ = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Connections

    func register(hello: AgentEnvelope.Hello) -> Result<Connection, AgentToolFailure> {
        guard hello.token == sessionToken else {
            return .failure(AgentToolFailure(
                code: "authorization.denied",
                message: "The session token did not match. MaruEdit may have restarted."))
        }
        guard hello.envelopeVersion == AgentEnvelope.version else {
            return .failure(AgentToolFailure(
                code: "protocol.version_mismatch",
                message: "This bridge was built for envelope v\(hello.envelopeVersion); MaruEdit speaks v\(AgentEnvelope.version)."))
        }
        let connection = Connection(
            id: AutomationID.next(prefix: "conn"),
            credentialID: hello.credential.flatMap { pairedCredentials[$0] != nil ? $0 : nil },
            claimedName: hello.clientName,
            bridgePID: hello.bridgePID)
        connections.append(connection)
        record(connection: connection, tool: "control.hello", document: nil,
               outcome: connection.credentialID == nil ? "unpaired" : "paired")
        onChange?()
        return .success(connection)
    }

    func disconnect(_ connection: Connection) {
        connection.status = .disconnected
        connections.removeAll { $0 === connection }
        record(connection: connection, tool: "control.disconnect", document: nil, outcome: "closed")
        onChange?()
    }

    /// Approval is granted in the non-modal indicator, never a sheet: a sheet is
    /// window-modal and would stop the human typing, which R9 forbids and which
    /// would let a background agent interrupt someone mid-sentence.
    func approve(_ connection: Connection, documents: [AutomationID]) {
        connection.status = .approved
        connection.grantedDocuments = Set(documents)
        connection.grantGeneration &+= 1
        record(connection: connection, tool: "control.approve", document: nil,
               outcome: "granted \(documents.count) document(s)")
        onChange?()
    }

    func deny(_ connection: Connection) {
        connection.status = .denied
        connection.grantedDocuments = []
        connection.grantGeneration &+= 1
        record(connection: connection, tool: "control.deny", document: nil, outcome: "denied")
        onChange?()
    }

    func revoke(_ connection: Connection) {
        connection.status = .denied
        connection.grantedDocuments = []
        connection.inheritsNewDocuments = false
        connection.grantGeneration &+= 1
        record(connection: connection, tool: "control.revoke", document: nil, outcome: "revoked")
        onChange?()
    }

    func setInheritance(_ connection: Connection, enabled: Bool) {
        connection.inheritsNewDocuments = enabled
        record(connection: connection, tool: "control.inheritance", document: nil,
               outcome: enabled ? "enabled" : "disabled")
        onChange?()
    }

    /// Called when a document is opened while a client is connected, so an
    /// opt-in inheritance grant can pick it up. Without the opt-in, nothing
    /// happens — which is the point.
    func noteDocumentOpened(_ id: AutomationID) {
        var changed = false
        for connection in connections where connection.inheritsNewDocuments && connection.status == .approved {
            connection.grantedDocuments.insert(id)
            changed = true
        }
        if changed { onChange?() }
    }

    // MARK: - Authorization checks

    /// Cheap check before the work is queued. It is deliberately not the only
    /// one: §6.3 requires a second, atomic re-validation immediately before any
    /// commit, because a grant can be revoked in between.
    func authorize(_ connection: Connection, tool: String) -> AgentToolOutcome? {
        if tool == "control.pair" { return nil }
        switch connection.status {
        case .approved:
            break
        case .pending:
            return .failure(
                code: "authorization.pending",
                message: "Waiting for approval in MaruEdit's agent indicator. Try again shortly.",
                details: nil)
        case .denied, .disconnected, .expired:
            return .failure(
                code: "authorization.denied",
                message: "Access was declined in MaruEdit.",
                details: nil)
        }
        guard allowRequest(connection) else {
            return .failure(
                code: "limit.rate",
                message: "Too many requests. MaruEdit throttles rather than disconnecting; slow down and retry.",
                details: nil)
        }
        return nil
    }

    func mayAccess(_ connection: Connection, document: AutomationID) -> Bool {
        connection.grantedDocuments.contains(document)
    }

    private func allowRequest(_ connection: Connection) -> Bool {
        let now = Date()
        connection.requestTimestamps.removeAll { now.timeIntervalSince($0) > 60 }
        guard connection.requestTimestamps.count < Self.requestsPerMinute else { return false }
        connection.requestTimestamps.append(now)
        return true
    }

    // MARK: - Pairing

    /// Issues a verification code the human confirms in MaruEdit.
    ///
    /// The credential this produces is a revocable bearer capability, not proof
    /// of identity — see the type comment. It buys provenance at issuance and a
    /// handle to revoke, which is what makes agent activity attributable.
    func beginPairing() -> Result<PairingRequest, AgentToolFailure> {
        let code = (0..<6).map { _ in String(Int.random(in: 0...9)) }.joined()
        let credentialID = Self.randomToken(bytes: 16)
        let path = AgentEndpoint.supportDirectory(home: home)
            .appendingPathComponent("credential-\(credentialID).txt")
        let request = PairingRequest(
            verificationCode: code,
            credentialID: credentialID,
            credentialPath: path.path,
            requestedAt: Date())
        pendingPairing = request
        onChange?()
        return .success(request)
    }

    /// Confirms the pending pairing and writes the credential file `0600`.
    @discardableResult
    func confirmPairing(label: String) -> Bool {
        guard let request = pendingPairing else { return false }
        let directory = AgentEndpoint.supportDirectory(home: home)
        try? FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        let url = URL(fileURLWithPath: request.credentialPath)
        guard (try? Data(request.credentialID.utf8).write(to: url, options: .atomic)) != nil else {
            return false
        }
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o600], ofItemAtPath: url.path)
        pairedCredentials[request.credentialID] = label
        saveCredentials()
        pendingPairing = nil
        onChange?()
        return true
    }

    func cancelPairing() {
        pendingPairing = nil
        onChange?()
    }

    func revokeCredential(_ credentialID: String) {
        pairedCredentials.removeValue(forKey: credentialID)
        saveCredentials()
        for connection in connections where connection.credentialID == credentialID {
            revoke(connection)
        }
        let url = AgentEndpoint.supportDirectory(home: home)
            .appendingPathComponent("credential-\(credentialID).txt")
        try? FileManager.default.removeItem(at: url)
        onChange?()
    }

    private func loadCredentials() {
        guard let data = try? Data(contentsOf: AgentEndpoint.credentialsURL(home: home)),
              let value = try? JSONValue.decode(data),
              let members = value["credentials"]?.objectValue
        else { return }
        pairedCredentials = members.compactMapValues(\.stringValue)
    }

    private func saveCredentials() {
        let directory = AgentEndpoint.supportDirectory(home: home)
        try? FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        let payload = JSONValue.object([
            "credentials": .object(pairedCredentials.mapValues(JSONValue.string)),
        ])
        try? payload.encoded().write(to: AgentEndpoint.credentialsURL(home: home), options: .atomic)
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o600], ofItemAtPath: AgentEndpoint.credentialsURL(home: home).path)
    }

    // MARK: - Audit

    func record(connection: Connection, tool: String, document: String?, outcome: String) {
        audit.append(AuditEntry(
            at: Date(),
            connection: connection.displayName,
            credentialID: connection.credentialID,
            tool: tool,
            document: document,
            outcome: outcome))
        if audit.count > Self.auditEntryLimit {
            audit.removeFirst(audit.count - Self.auditEntryLimit)
        }
    }
}
