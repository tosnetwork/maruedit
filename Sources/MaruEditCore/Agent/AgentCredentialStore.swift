import Foundation
import Security

/// Where a pairing credential's secret lives, and what that location is
/// actually worth.
///
/// The honest starting point is what the trust model already says: same-UID is
/// one trust domain. A `0600` file protects a secret from other accounts and
/// from nobody else — any unsandboxed process running as this user can read it,
/// so storing a bearer secret that way buys obscurity and no security.
///
/// The Keychain is different in one specific way that matters: the check is not
/// performed by the process asking. `securityd` holds the item, and a
/// legacy-keychain ACL naming trusted applications makes it decide, from the
/// asking process's *code signature*, whether to hand the secret over. That is
/// a boundary a same-user process cannot simply read past.
///
/// The size of that boundary depends entirely on code signing, and this type
/// reports which case it is rather than implying the stronger one:
///
/// - **Signed with a stable identity** — the ACL names the editor and the
///   bridge, and another same-user process is refused by `securityd`. This is
///   a real improvement over the file.
/// - **Unsigned or ad-hoc signed** (a local build) — the signature is not
///   stable across rebuilds, so the ACL cannot bind to anything durable. The
///   secret is still out of the filesystem, the human still gets a prompt when
///   something unexpected asks for it, but no code-identity guarantee exists.
///
/// Either way one thing improves unconditionally: the secret is no longer
/// sitting in a file next to its own label, which is what the previous scheme
/// did.
public enum AgentCredentialStore {

    public static let service = "MaruEdit Agent Credential"

    public enum StoreError: Error, Equatable {
        case keychainFailed(OSStatus)
        case notFound
        case randomnessUnavailable
    }

    /// How much protection the stored item actually got.
    ///
    /// Kept as data rather than a comment so the UI can tell the human the true
    /// story instead of a hopeful one.
    public enum Protection: String, Sendable {
        /// `securityd` will enforce which signed binaries may read the secret.
        case codeIdentityEnforced
        /// The secret is in the Keychain, but no stable code identity exists to
        /// bind it to — a local build.
        case keychainOnly
    }

    public struct StoredCredential: Sendable, Equatable {
        public let id: String
        public let secret: String
        public let protection: Protection
    }

    // MARK: - Secrets

    public static func randomSecret(bytes count: Int = 32) throws -> String {
        var bytes = [UInt8](repeating: 0, count: count)
        guard SecRandomCopyBytes(kSecRandomDefault, count, &bytes) == errSecSuccess else {
            throw StoreError.randomnessUnavailable
        }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    /// The digest the editor keeps, so that reading everything the editor wrote
    /// to disk yields no usable credential.
    public static func digest(of secret: String) -> String {
        AgentDigest.of(secret)
    }

    /// Compares a presented secret against a stored digest in time that does
    /// not depend on how many leading characters matched.
    ///
    /// An early-exit comparison over a socket is a real oracle: a client that
    /// can retry cheaply recovers the value one character at a time.
    public static func matches(presented: String, digest expected: String) -> Bool {
        let presentedDigest = Array(digest(of: presented).utf8)
        let expectedBytes = Array(expected.utf8)
        guard presentedDigest.count == expectedBytes.count else { return false }
        var difference: UInt8 = 0
        for index in 0..<presentedDigest.count {
            difference |= presentedDigest[index] ^ expectedBytes[index]
        }
        return difference == 0
    }

    // MARK: - Keychain

    /// Stores `secret` under `id`, replacing any previous item.
    ///
    /// `trustedExecutables` are the binaries allowed to read it without a
    /// prompt — normally the editor and the bridge. An empty list, or a system
    /// that refuses to build the ACL, degrades to `.keychainOnly` rather than
    /// failing: refusing to pair at all on an unsigned build would make the
    /// feature undeliverable for exactly the people building it.
    @discardableResult
    public static func store(
        secret: String, id: String, label: String, trustedExecutables: [String]
    ) throws -> Protection {
        try? remove(id: id)

        var protection = Protection.keychainOnly
        var attributes: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: id,
            kSecAttrLabel: label,
            kSecValueData: Data(secret.utf8),
        ]

        if let access = accessControl(label: label, trustedExecutables: trustedExecutables) {
            attributes[kSecAttrAccess] = access
            protection = .codeIdentityEnforced
        }

        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else { throw StoreError.keychainFailed(status) }
        return protection
    }

    public static func secret(id: String) throws -> String {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: id,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status != errSecItemNotFound else { throw StoreError.notFound }
        guard status == errSecSuccess,
              let data = item as? Data,
              let secret = String(data: data, encoding: .utf8)
        else { throw StoreError.keychainFailed(status) }
        return secret
    }

    public static func remove(id: String) throws {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: id,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw StoreError.keychainFailed(status)
        }
    }

    /// Builds an ACL naming the executables allowed to read the item.
    ///
    /// The legacy keychain API is what supports trusted-application ACLs at
    /// all; the data-protection keychain does not offer them on macOS. Returns
    /// nil when no ACL could be built, which the caller reports as reduced
    /// protection rather than treating as success.
    ///
    /// Marked deprecated itself so its calls into the deprecated keychain API
    /// do not each warn: the deprecation is understood and accepted here, and
    /// silencing it at the boundary keeps the build's real warnings visible.
    @available(macOS, deprecated: 10.10, message: "Uses the legacy keychain deliberately: it is the only API offering trusted-application ACLs.")
    private static func accessControl(
        label: String, trustedExecutables: [String]
    ) -> SecAccess? {
        let existing = trustedExecutables.filter { FileManager.default.fileExists(atPath: $0) }
        guard !existing.isEmpty else { return nil }

        var applications: [SecTrustedApplication] = []
        for path in existing {
            var application: SecTrustedApplication?
            guard SecTrustedApplicationCreateFromPath(path, &application) == errSecSuccess,
                  let application
            else {
                // One unreadable or unsigned binary must not silently produce
                // an ACL that omits it — the omitted one would then prompt on
                // every use, which trains the human to click through prompts.
                return nil
            }
            applications.append(application)
        }

        var access: SecAccess?
        guard SecAccessCreate(label as CFString, applications as CFArray, &access) == errSecSuccess
        else { return nil }
        return access
    }
}

/// The credential store as a value, so a caller can say which one it means.
///
/// The Keychain is process-wide and shared with everything else the human
/// owns. A test that exercised the real one would write into their login
/// keychain, possibly prompt them, and leave residue that outlives the run —
/// none of which the test is trying to check. Making the store injectable
/// keeps the production path exactly as it is while letting tests about
/// pairing logic be about pairing logic.
public struct AgentCredentialVault: Sendable {
    public var store: @Sendable (
        _ secret: String, _ id: String, _ label: String, _ trustedExecutables: [String]
    ) throws -> AgentCredentialStore.Protection
    public var secret: @Sendable (_ id: String) throws -> String
    public var remove: @Sendable (_ id: String) throws -> Void

    public init(
        store: @escaping @Sendable (String, String, String, [String]) throws -> AgentCredentialStore.Protection,
        secret: @escaping @Sendable (String) throws -> String,
        remove: @escaping @Sendable (String) throws -> Void
    ) {
        self.store = store
        self.secret = secret
        self.remove = remove
    }

    public static let keychain = AgentCredentialVault(
        store: { secret, id, label, trusted in
            try AgentCredentialStore.store(
                secret: secret, id: id, label: label, trustedExecutables: trusted)
        },
        secret: { try AgentCredentialStore.secret(id: $0) },
        remove: { try AgentCredentialStore.remove(id: $0) })

    /// A vault that keeps secrets for the lifetime of the process only.
    ///
    /// Reports `.keychainOnly`, because claiming enforced code identity from
    /// a dictionary would let a test assert a protection that does not exist.
    public static func inMemory() -> AgentCredentialVault {
        final class Storage: @unchecked Sendable {
            private let lock = NSLock()
            private var secrets: [String: String] = [:]
            func set(_ secret: String, _ id: String) { lock.lock(); secrets[id] = secret; lock.unlock() }
            func get(_ id: String) -> String? { lock.lock(); defer { lock.unlock() }; return secrets[id] }
            func remove(_ id: String) { lock.lock(); secrets[id] = nil; lock.unlock() }
        }
        let storage = Storage()
        return AgentCredentialVault(
            store: { secret, id, _, _ in
                storage.set(secret, id)
                return .keychainOnly
            },
            secret: { id in
                guard let secret = storage.get(id) else {
                    throw AgentCredentialStore.StoreError.notFound
                }
                return secret
            },
            remove: { storage.remove($0) })
    }
}
