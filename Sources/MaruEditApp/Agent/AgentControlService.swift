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

    /// What a connection is allowed to do.
    ///
    /// One Approve button used to grant reads, direct edits, selection changes,
    /// saves, file opening, and commands together — every capability the ADR
    /// says must be separable. They are separable now, and the write mode is
    /// part of the grant rather than something an agent chooses per call.
    struct Capabilities: OptionSet {
        let rawValue: Int
        static let readDocuments = Capabilities(rawValue: 1 << 0)
        static let readSelection = Capabilities(rawValue: 1 << 1)
        static let writeDocuments = Capabilities(rawValue: 1 << 2)
        static let writeSelection = Capabilities(rawValue: 1 << 3)
        static let saveDocuments = Capabilities(rawValue: 1 << 4)
        static let openDocuments = Capabilities(rawValue: 1 << 5)
        static let runCommands = Capabilities(rawValue: 1 << 6)

        /// What Approve grants on its own: reading, and nothing else.
        static let readOnly: Capabilities = [.readDocuments, .readSelection]
        static let editing: Capabilities = [.readOnly, .writeDocuments, .writeSelection]
        static let everything: Capabilities = [.editing, .saveDocuments, .openDocuments, .runCommands]

        /// Which capability each tool needs. A tool absent from this table is
        /// refused rather than allowed by default.
        static func required(for tool: String) -> Capabilities? {
            switch tool {
            case "list_documents", "list_editors", "read_document",
                 "get_outline", "search_documents":
                return .readDocuments
            case "get_selection":
                return .readSelection
            case "apply_edits", "review_status":
                return .writeDocuments
            case "set_selection", "reveal":
                return .writeSelection
            case "save_document":
                return .saveDocuments
            case "open_document":
                return .openDocuments
            case "run_command":
                return .runCommands
            default:
                return nil
            }
        }
    }

    /// How a granted client's edits reach the document.
    enum WriteMode: String {
        /// Edits are queued for the human to accept or reject.
        case review
        /// Edits apply immediately, still as one undo entry each.
        case auto
    }

    /// One live bridge connection.
    final class Connection {
        let id: AutomationID
        /// The paired configuration this connection presented, if any.
        var credentialID: String? { pairedCredentialID }
        fileprivate(set) var pairedCredentialID: String?
        /// Self-reported and therefore display-only, always labelled as such.
        let claimedName: String?
        let bridgePID: Int32
        var status: ConnectionStatus = .pending
        /// Documents this connection may see. Frozen at approval: a grant that
        /// silently grew to cover whatever the human opened next would turn
        /// "read what I have open" into "read anything I open".
        var grantedDocuments: Set<AutomationID> = []
        /// Reading only, until the human says otherwise.
        var capabilities: Capabilities = []
        /// Review by default: an edit the human has not seen is the thing this
        /// interface is most likely to get wrong.
        var writeMode: WriteMode = .review
        /// Folders this connection may open files from. Per connection, not per
        /// process: a root authorized for one configuration must not silently
        /// authorize every other one.
        var authorizedRoots: [String] = []
        /// Opt-in, default off, and lapses with the connection.
        var inheritsNewDocuments = false
        /// Bumped on revoke so an in-flight call can notice before it commits.
        var grantGeneration: UInt64 = 0
        var requestTimestamps: [Date] = []
        /// Anchors belong to the connection, not to a "client": Phase 1 has no
        /// persistent identity to hang them on, and a self-declared name would
        /// make the quota spoofable.
        let anchors = AgentAnchorStore()
        /// Outcomes keyed by (tool, idempotency key), so a client that loses a
        /// reply and retries gets the first answer instead of a second edit.
        ///
        /// Bounded and per connection, and deliberately not surviving a
        /// reconnect: without persistent identity there is nothing to key it to
        /// on the far side, and the ADR says so rather than pretending.
        var idempotency: [IdempotencyKey: IdempotencyRecord] = [:]
        var idempotencyOrder: [IdempotencyKey] = []

        init(id: AutomationID, credentialID: String?, claimedName: String?, bridgePID: Int32) {
            self.id = id
            self.pairedCredentialID = credentialID
            self.claimedName = claimedName
            self.bridgePID = bridgePID
        }

        var displayName: String {
            claimedName.map { "\($0) (unverified)" } ?? "Unidentified MCP client"
        }
    }

    struct IdempotencyKey: Hashable {
        let tool: String
        let key: String
    }

    struct IdempotencyRecord {
        /// Digest of the canonical arguments, so the same key with different
        /// arguments is refused rather than answered with someone else's
        /// result.
        let argumentDigest: String
        let outcome: AgentToolOutcome
        let at: Date
    }

    static let idempotencyRecordLimit = 64
    static let idempotencyLifetime: TimeInterval = 600
    static let maximumIdempotencyKeyCharacters = 128

    /// Failures that describe a passing condition rather than the request.
    ///
    /// Caching one would refuse the same operation for ten minutes after the
    /// human cleared the queue or closed the split — the retry the agent is
    /// supposed to make would keep getting the stale answer.
    private static let transientFailureCodes: Set<String> = [
        "limit.pending_proposals", "limit.proposal_bytes", "limit.rate",
        "document.multiple_panes", "save.in_progress", "state.superseded",
        "authorization.pending", "editor.unavailable", "transport.closed",
    ]

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
        /// The secret the agent presents. Shown once, at pairing, and never
        /// written anywhere the editor can read it back.
        let secret: String
        let protection: AgentCredentialStore.Protection
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
    /// recognized after a restart.
    /// Paired credentials by public id.
    ///
    /// The editor keeps a label and the secret's digest — never the secret. A
    /// reader of everything MaruEdit writes to disk therefore gets no usable
    /// credential, which was not true when the id *was* the bearer token and
    /// sat in this file as its own key.
    struct PairedCredential: Equatable {
        let label: String
        let secretDigest: String
    }

    private(set) var pairedCredentials: [String: PairedCredential] = [:]

    /// Credentials the human chose to trust across restarts.
    ///
    /// This is the whole of "persistent grants" at the level this trust model
    /// supports, and the limit is worth naming: the credential is a bearer
    /// capability, so remembering it skips the approval click; it does not
    /// become authentication by being remembered.
    ///
    /// How much the secret is protected depends on whether this build is
    /// signed — see `AgentCredentialStore`. On a signed build `securityd`
    /// enforces which code may read it, so unattended trust rests on something
    /// real; on a local build it does not, and the indicator says so rather
    /// than implying otherwise.
    private(set) var rememberedCredentials: Set<String> = []
    let proposals = AgentProposalStore()

    /// Folders offered when approving a connection. A connection only ever
    /// uses the copy on its own grant.
    private(set) var offeredRoots: [String] = []

    private let home: URL
    private let vault: AgentCredentialVault
    let sessionToken: String
    let serverInstanceID: String

    /// Called when the set of connections changes, so the UI can refresh
    /// without polling.
    var onChange: (() -> Void)?

    init(
        home: URL = URL(fileURLWithPath: NSHomeDirectory()),
        vault: AgentCredentialVault = .keychain
    ) {
        self.home = home
        self.vault = vault
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

    func setRemembered(_ credentialID: String, _ remembered: Bool) {
        if remembered { rememberedCredentials.insert(credentialID) }
        else { rememberedCredentials.remove(credentialID) }
        saveCredentials()
        onChange?()
    }

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
            credentialID: hello.credential.flatMap(resolveCredential),
            claimedName: hello.clientName,
            bridgePID: hello.bridgePID)
        connections.append(connection)
        record(connection: connection, tool: "control.hello", document: nil,
               outcome: connection.credentialID == nil ? "unpaired" : "paired")
        // A remembered credential skips the approval click. The grant it
        // receives is still frozen to what is open right now, because a grant
        // that also persisted would quietly cover documents the human has never
        // seen this session.
        if let credential = connection.credentialID, rememberedCredentials.contains(credential),
           let coordinator = AppDelegate.sharedCoordinator {
            approve(connection, documents: coordinator.agentVisibleTargets().map(\.document.automationID))
        }
        onChange?()
        return .success(connection)
    }

    func disconnect(_ connection: Connection) {
        connection.anchors.removeAll()
        proposals.dropAll(for: connection.id)
        connection.status = .disconnected
        connections.removeAll { $0 === connection }
        record(connection: connection, tool: "control.disconnect", document: nil, outcome: "closed")
        onChange?()
    }

    /// Approval is granted in the non-modal indicator, never a sheet: a sheet is
    /// window-modal and would stop the human typing, which R9 forbids and which
    /// would let a background agent interrupt someone mid-sentence.
    /// Whether this connection may be approved at all.
    ///
    /// ADR-012 requires pairing before anything is disclosed: approving an
    /// anonymous connection means approving whichever process happened to
    /// arrive at the moment the human clicked, which is not a decision about
    /// anyone in particular.
    func canApprove(_ connection: Connection) -> Bool {
        connection.credentialID != nil
    }

    @discardableResult
    func approve(
        _ connection: Connection,
        documents: [AutomationID],
        capabilities: Capabilities = .readOnly,
        writeMode: WriteMode = .review
    ) -> Bool {
        guard canApprove(connection) else {
            record(connection: connection, tool: "control.approve", document: nil,
                   outcome: "refused: not paired")
            return false
        }
        connection.status = .approved
        connection.grantedDocuments = Set(documents)
        connection.capabilities = capabilities
        connection.writeMode = writeMode
        connection.grantGeneration &+= 1
        record(connection: connection, tool: "control.approve", document: nil,
               outcome: "granted \(documents.count) document(s), \(capabilities.rawValue), \(writeMode.rawValue)")
        onChange?()
        return true
    }

    func setCapabilities(_ connection: Connection, _ capabilities: Capabilities) {
        connection.capabilities = capabilities
        connection.grantGeneration &+= 1
        record(connection: connection, tool: "control.capabilities", document: nil,
               outcome: String(capabilities.rawValue))
        onChange?()
    }

    func setWriteMode(_ connection: Connection, _ mode: WriteMode) {
        connection.writeMode = mode
        connection.grantGeneration &+= 1
        record(connection: connection, tool: "control.writeMode", document: nil,
               outcome: mode.rawValue)
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
        connection.anchors.removeAll()
        proposals.dropAll(for: connection.id)
        connection.status = .denied
        connection.grantedDocuments = []
        connection.capabilities = []
        connection.authorizedRoots = []
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
    /// Snapshot of a grant, taken when a call is dispatched and re-checked
    /// immediately before anything sensitive is returned or committed.
    ///
    /// Without this, a revocation during a suspended read or save would arrive
    /// too late to matter: the counter was incremented and nobody read it.
    struct GrantStamp: Equatable {
        let connectionID: AutomationID
        let generation: UInt64
    }

    func stamp(_ connection: Connection) -> GrantStamp {
        GrantStamp(connectionID: connection.id, generation: connection.grantGeneration)
    }

    /// Whether a stamped grant is still the grant that was checked.
    func isStillValid(_ stamp: GrantStamp) -> Bool {
        guard let connection = connections.first(where: { $0.id == stamp.connectionID }) else {
            return false
        }
        return connection.status == .approved && connection.grantGeneration == stamp.generation
    }

    func authorize(_ connection: Connection, tool: String) -> AgentToolOutcome? {
        if tool == "control.pair" { return nil }
        switch connection.status {
        case .approved:
            break
        case .pending:
            guard canApprove(connection) else {
                return .failure(
                    code: "authorization.pairing_required",
                    message: """
                        This client is not paired with MaruEdit. Run \
                        `maruedit-mcp --pair` once and point your MCP server \
                        config at the credential it writes.
                        """,
                    details: nil)
            }
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
        guard let required = Capabilities.required(for: tool) else {
            return .failure(
                code: "tool.unknown",
                message: "MaruEdit does not implement \(tool).",
                details: nil)
        }
        guard connection.capabilities.contains(required) else {
            return .failure(
                code: "authorization.capability",
                message: """
                    This client has not been granted that. Capabilities are \
                    separate — reading, editing, moving the cursor, saving, \
                    opening files, and running commands are each granted on \
                    their own in MaruEdit's agent window.
                    """,
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

    /// Finds which paired credential a presented secret belongs to.
    ///
    /// Every candidate is compared, and the comparison itself is constant
    /// time, so neither the number of matched characters nor which credential
    /// matched is observable from how long the answer took.
    private func resolveCredential(_ presented: String) -> String? {
        var matched: String?
        for (id, credential) in pairedCredentials
        where AgentCredentialStore.matches(presented: presented, digest: credential.secretDigest) {
            matched = id
        }
        return matched
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
        // The id is a public handle — it appears in the registry, the audit
        // trail, and the revoke button. The secret is separate, so knowing how
        // a credential is named never means holding it.
        guard let secret = try? AgentCredentialStore.randomSecret() else {
            return .failure(AgentToolFailure(
                code: "internal",
                message: "The system refused to provide randomness, so no credential was issued."))
        }
        let request = PairingRequest(
            verificationCode: code,
            credentialID: credentialID,
            secret: secret,
            protection: .keychainOnly,
            requestedAt: Date())
        pendingPairing = request
        onChange?()
        return .success(request)
    }

    /// Confirms the pending pairing, putting the secret in the Keychain and
    /// keeping only its digest.
    ///
    /// Returns the protection actually achieved, or nil if the Keychain
    /// refused. Failing loudly is deliberate: quietly falling back to a file
    /// would give the human a stronger-sounding pairing than they got.
    @discardableResult
    func confirmPairing(label: String) -> AgentCredentialStore.Protection? {
        guard let request = pendingPairing else { return nil }
        guard let protection = try? vault.store(
            request.secret, request.credentialID, label, Self.trustedExecutablePaths())
        else { return nil }

        pairedCredentials[request.credentialID] = PairedCredential(
            label: label,
            secretDigest: AgentCredentialStore.digest(of: request.secret))
        saveCredentials()
        pendingPairing = nil
        onChange?()
        return protection
    }

    /// The binaries allowed to read a credential without prompting: this app
    /// and the bridge it ships.
    private static func trustedExecutablePaths() -> [String] {
        var paths: [String] = []
        if let executable = Bundle.main.executablePath { paths.append(executable) }
        let bridge = Bundle.main.bundleURL
            .appendingPathComponent("Contents/MacOS/MaruEditMCPBridge")
        if FileManager.default.fileExists(atPath: bridge.path) { paths.append(bridge.path) }
        return paths
    }

    func cancelPairing() {
        pendingPairing = nil
        onChange?()
    }

    func revokeCredential(_ credentialID: String) {
        // The secret goes with the record. Leaving it in the Keychain would
        // make "revoked" mean "hidden from this list".
        try? vault.remove(credentialID)
        pairedCredentials.removeValue(forKey: credentialID)
        rememberedCredentials.remove(credentialID)
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
        // New-format entries only. The earlier scheme used the credential id
        // as the bearer secret and stored it here in plaintext, so any such
        // entry is a secret that has been readable by every same-user process
        // for as long as it existed. Carrying it forward would preserve
        // exactly the weakness this store exists to remove, so those entries
        // are dropped and the human re-pairs once.
        pairedCredentials = members.compactMapValues { entry in
            guard let object = entry.objectValue,
                  let label = object["label"]?.stringValue,
                  let digest = object["secretDigest"]?.stringValue
            else { return nil }
            return PairedCredential(label: label, secretDigest: digest)
        }
        if members.count > pairedCredentials.count {
            // Rewritten immediately so the plaintext secrets stop existing on
            // disk, rather than lingering until the next pairing.
            saveCredentials()
        }
        rememberedCredentials = Set(
            (value["remembered"]?.arrayValue ?? []).compactMap(\.stringValue)
        ).intersection(pairedCredentials.keys)
    }

    private func saveCredentials() {
        let directory = AgentEndpoint.supportDirectory(home: home)
        try? FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        let payload = JSONValue.object([
            "credentials": .object(pairedCredentials.mapValues { credential in
                JSONValue.object([
                    "label": .string(credential.label),
                    "secretDigest": .string(credential.secretDigest),
                ])
            }),
            "remembered": .array(rememberedCredentials.sorted().map(JSONValue.string)),
        ])
        try? payload.encoded().write(to: AgentEndpoint.credentialsURL(home: home), options: .atomic)
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o600], ofItemAtPath: AgentEndpoint.credentialsURL(home: home).path)
    }

    /// Test seam: registers and approves a connection over everything open.
    ///
    /// Only the approval path is short-circuited; the grant is still frozen to
    /// what exists at the moment it is called, exactly as the UI does it.
    func approveForTesting(
        _ connection: Connection,
        coordinator: AppCoordinator,
        capabilities: Capabilities = .readOnly,
        writeMode: WriteMode = .auto,
        roots: [String] = []
    ) {
        if !connections.contains(where: { $0 === connection }) {
            connections.append(connection)
        }
        // Approval requires pairing, so a test connection is paired first
        // rather than the rule being bypassed.
        if connection.credentialID == nil {
            let credential = Self.randomToken(bytes: 8)
            pairedCredentials[credential] = PairedCredential(
                label: "test", secretDigest: AgentCredentialStore.digest(of: credential))
            connection.pairedCredentialID = credential
        }
        approve(
            connection,
            documents: coordinator.agentVisibleTargets().map(\.document.automationID),
            capabilities: capabilities,
            writeMode: writeMode)
        if !roots.isEmpty { grantRoots(connection, roots) }
    }

    func addAuthorizedRoot(_ path: String) {
        let standardized = URL(fileURLWithPath: path).standardizedFileURL.path
        guard !offeredRoots.contains(standardized) else { return }
        offeredRoots.append(standardized)
        onChange?()
    }

    func removeAuthorizedRoot(_ path: String) {
        offeredRoots.removeAll { $0 == path }
        for connection in connections {
            connection.authorizedRoots.removeAll { $0 == path }
            connection.grantGeneration &+= 1
        }
        onChange?()
    }

    func grantRoots(_ connection: Connection, _ roots: [String]) {
        connection.authorizedRoots = roots
        connection.grantGeneration &+= 1
        record(connection: connection, tool: "control.roots", document: nil,
               outcome: "\(roots.count) folder(s)")
        onChange?()
    }

    /// Adds one document to a grant, which only `open_document` may do: the
    /// human already authorized the folder it came from.
    func extendGrant(_ connection: Connection, with document: AutomationID) {
        connection.grantedDocuments.insert(document)
        onChange?()
    }

    // MARK: - Idempotency

    /// The remembered outcome for this key, or a refusal if the key was reused
    /// with different arguments.
    func rememberedOutcome(
        _ connection: Connection, tool: String, key: String, arguments: JSONValue
    ) -> AgentToolOutcome? {
        guard key.count <= Self.maximumIdempotencyKeyCharacters else {
            return .failure(
                code: "argument.invalid",
                message: "idempotencyKey must be at most \(Self.maximumIdempotencyKeyCharacters) characters.",
                details: nil)
        }
        prune(connection)
        let identifier = IdempotencyKey(tool: tool, key: key)
        guard let record = connection.idempotency[identifier] else { return nil }
        guard record.argumentDigest == Self.digest(of: arguments) else {
            return .failure(
                code: "idempotency.mismatch",
                message: "That idempotency key was used with different arguments.",
                details: nil)
        }
        return record.outcome
    }

    /// Records an outcome — including a failure, so a blind retry after a
    /// conflict gets the same conflict rather than re-running validation.
    func remember(
        _ connection: Connection, tool: String, key: String,
        arguments: JSONValue, outcome: AgentToolOutcome
    ) {
        // Successes and genuine conflicts are worth remembering; a passing
        // condition is not.
        if case .failure(let code, _, _) = outcome,
           Self.transientFailureCodes.contains(code) {
            return
        }
        let identifier = IdempotencyKey(tool: tool, key: key)
        if connection.idempotency[identifier] == nil {
            connection.idempotencyOrder.append(identifier)
        }
        connection.idempotency[identifier] = IdempotencyRecord(
            argumentDigest: Self.digest(of: arguments), outcome: outcome, at: Date())
        prune(connection)
    }

    private func prune(_ connection: Connection) {
        let now = Date()
        connection.idempotencyOrder.removeAll { identifier in
            guard let record = connection.idempotency[identifier] else { return true }
            if now.timeIntervalSince(record.at) > Self.idempotencyLifetime {
                connection.idempotency.removeValue(forKey: identifier)
                return true
            }
            return false
        }
        while connection.idempotencyOrder.count > Self.idempotencyRecordLimit {
            let oldest = connection.idempotencyOrder.removeFirst()
            connection.idempotency.removeValue(forKey: oldest)
        }
    }

    private static func digest(of arguments: JSONValue) -> String {
        AgentDigest.of((try? arguments.encodedString()) ?? "")
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
