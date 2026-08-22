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
/// **The Keychain is not usable without that stable identity, and not merely
/// less useful.** Measured, not assumed: a binary that stores an item and is
/// then rebuilt — an ordinary app update — cannot read its own item back. The
/// request returns `errSecUserCanceled` because macOS raises an authorization
/// prompt, and it does so whether or not an explicit ACL was set, since the
/// default ACL also names the creating code. For an ad-hoc-signed build, whose
/// signature changes with every release, that means every update would break
/// every pairing, and an agent running unattended would simply fail.
///
/// So the backend follows the code identity: Keychain where the guarantee can
/// hold, a `0600` file where it cannot. The file is honest about what it is —
/// P9 already says a same-user process can read it — and it does not degrade
/// on update.
///
/// One improvement is unconditional and independent of the backend: the secret
/// is no longer the credential's own id, and the registry keeps only a digest.
/// The previous scheme stored every bearer token in plaintext under its own
/// name, so anything that could read the registry held all of them.
public enum AgentCredentialStore {

    public static let service = "MaruEdit Agent Credential"

    public enum StoreError: Error, Equatable {
        case keychainFailed(OSStatus)
        case notFound
        case randomnessUnavailable
        case noStableCodeIdentity
    }

    /// How much protection the stored item actually got.
    ///
    /// Kept as data rather than a comment so the UI can tell the human the true
    /// story instead of a hopeful one.
    public enum Protection: String, Sendable {
        /// `securityd` will enforce which signed binaries may read the secret.
        case codeIdentityEnforced
        /// The secret is in a `0600` file, because this build has no stable
        /// code identity for the Keychain to bind to. Readable by any process
        /// running as this user, exactly as P9 describes.
        case fileOnly
    }

    /// Whether this build has a code identity durable enough for the Keychain
    /// to enforce anything.
    ///
    /// A Team Identifier is the right signal precisely because it is the thing
    /// that survives a rebuild: ad-hoc signatures are content hashes and change
    /// with every release, which is what makes a Keychain ACL bound to one
    /// useless the moment the app updates.
    public static var hasStableCodeIdentity: Bool {
        var code: SecCode?
        guard SecCodeCopySelf(SecCSFlags(), &code) == errSecSuccess, let code else { return false }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, SecCSFlags(), &staticCode) == errSecSuccess,
              let staticCode
        else { return false }
        var information: CFDictionary?
        guard SecCodeCopySigningInformation(
                staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &information)
                == errSecSuccess,
              let details = information as? [String: Any]
        else { return false }
        let team = details[kSecCodeInfoTeamIdentifier as String] as? String
        return !(team?.isEmpty ?? true)
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
    /// prompt — normally the editor and the bridge. If no ACL can be built,
    /// this throws rather than storing an unprotected item: a Keychain item
    /// with no enforceable ACL has the update problem *and* none of the
    /// benefit, so the caller should be using the file backend instead.
    @discardableResult
    public static func store(
        secret: String, id: String, label: String, trustedExecutables: [String]
    ) throws -> Protection {
        try? remove(id: id)

        var protection = Protection.codeIdentityEnforced
        var attributes: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: id,
            kSecAttrLabel: label,
            kSecValueData: Data(secret.utf8),
        ]

        guard let access = accessControl(label: label, trustedExecutables: trustedExecutables)
        else { throw StoreError.noStableCodeIdentity }
        attributes[kSecAttrAccess] = access
        protection = .codeIdentityEnforced

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

/// The `0600`-file backend, used when the Keychain cannot enforce anything.
///
/// This is not a weaker version of the Keychain path pretending to be the same
/// thing. It is the storage that matches what P9 already says about same-UID
/// trust, and the pairing UI states plainly which one a credential got. What it
/// does have over the scheme it replaced is that the file holds a secret that
/// is *not* the credential's public id, and the registry holds only a digest.
public enum AgentCredentialFile {

    public static func url(directory: URL, id: String) -> URL {
        directory.appendingPathComponent("credential-\(id).secret")
    }

    public static func store(secret: String, id: String, directory: URL) throws {
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        let destination = url(directory: directory, id: id)
        // Written through a mode-restricted descriptor rather than written and
        // then chmodded: the second form leaves a window in which the secret
        // exists at the default umask.
        let descriptor = open(destination.path, O_WRONLY | O_CREAT | O_TRUNC | O_NOFOLLOW, 0o600)
        guard descriptor >= 0 else { throw AgentCredentialStore.StoreError.keychainFailed(errno) }
        defer { close(descriptor) }
        let bytes = Array(secret.utf8)
        var written = 0
        while written < bytes.count {
            let count = bytes.withUnsafeBytes { raw -> Int in
                write(descriptor, raw.baseAddress!.advanced(by: written), bytes.count - written)
            }
            if count > 0 { written += count }
            else if count < 0 && errno == EINTR { continue }
            else { throw AgentCredentialStore.StoreError.keychainFailed(errno) }
        }
        // A pre-existing file could have been created with looser permissions
        // by something else, and O_CREAT does not narrow an existing one.
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600], ofItemAtPath: destination.path)
    }

    public static func secret(id: String, directory: URL) throws -> String {
        let source = url(directory: directory, id: id)
        guard let data = try? Data(contentsOf: source),
              let secret = String(data: data, encoding: .utf8)
        else { throw AgentCredentialStore.StoreError.notFound }
        return secret.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func remove(id: String, directory: URL) throws {
        let target = url(directory: directory, id: id)
        guard FileManager.default.fileExists(atPath: target.path) else { return }
        try FileManager.default.removeItem(at: target)
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

    /// Picks the backend this build can actually honour.
    ///
    /// The choice is made once, from the running code's own identity, rather
    /// than by attempting the Keychain and catching a failure: the Keychain
    /// failure mode that matters here is not an error at write time but a
    /// prompt at read time, weeks later, after an update — which no `try?`
    /// around the write would ever see.
    public static func automatic(directory: URL) -> AgentCredentialVault {
        AgentCredentialStore.hasStableCodeIdentity ? .keychain : .file(directory: directory)
    }

    public static func file(directory: URL) -> AgentCredentialVault {
        AgentCredentialVault(
            store: { secret, id, _, _ in
                try AgentCredentialFile.store(secret: secret, id: id, directory: directory)
                return .fileOnly
            },
            secret: { try AgentCredentialFile.secret(id: $0, directory: directory) },
            remove: { try AgentCredentialFile.remove(id: $0, directory: directory) })
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
    /// Reports `.fileOnly`, because claiming enforced code identity from a
    /// dictionary would let a test assert a protection that does not exist.
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
                return .fileOnly
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
