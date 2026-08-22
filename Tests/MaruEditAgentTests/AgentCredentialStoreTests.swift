import Foundation
import XCTest
@testable import MaruEditCore

/// The parts of the credential store that can be checked without touching the
/// human's real Keychain, plus one round-trip against it that is opt-in.
final class AgentCredentialStoreTests: XCTestCase {

    // MARK: - Verification

    func testASecretIsVerifiedByDigestNotByHoldingIt() throws {
        let secret = try AgentCredentialStore.randomSecret()
        let digest = AgentCredentialStore.digest(of: secret)

        XCTAssertTrue(AgentCredentialStore.matches(presented: secret, digest: digest))
        XCTAssertFalse(AgentCredentialStore.matches(presented: secret + "0", digest: digest))
        XCTAssertFalse(AgentCredentialStore.matches(presented: "", digest: digest))
        XCTAssertFalse(AgentCredentialStore.matches(presented: secret, digest: "sha256:"))

        // The digest is not the secret, so knowing it authenticates nothing.
        XCTAssertFalse(AgentCredentialStore.matches(presented: digest, digest: digest))
    }

    func testASecretIsLongEnoughToBeUnguessableAndAlwaysDifferent() throws {
        var seen: Set<String> = []
        for _ in 0..<200 {
            let secret = try AgentCredentialStore.randomSecret()
            XCTAssertEqual(secret.count, 64, "32 bytes as hex")
            XCTAssertTrue(seen.insert(secret).inserted, "randomness repeated itself")
        }
    }

    func testComparisonIsLengthCheckedBeforeItIsByteCompared() {
        // A digest of a different length can never match, and must not be able
        // to walk off the end of the shorter array while finding that out.
        let digest = AgentCredentialStore.digest(of: "x")
        XCTAssertFalse(AgentCredentialStore.matches(presented: "x", digest: String(digest.dropLast())))
        XCTAssertFalse(AgentCredentialStore.matches(presented: "x", digest: digest + "0"))
    }

    // MARK: - The in-memory vault used by the pairing tests

    func testTheInMemoryVaultBehavesLikeTheRealOneForStoreReadRemove() throws {
        let vault = AgentCredentialVault.inMemory()
        let secret = try AgentCredentialStore.randomSecret()

        XCTAssertEqual(try vault.store(secret, "id_1", "Agent", []), .fileOnly)
        XCTAssertEqual(try vault.secret("id_1"), secret)

        try vault.remove("id_1")
        XCTAssertThrowsError(try vault.secret("id_1")) { error in
            XCTAssertEqual(error as? AgentCredentialStore.StoreError, .notFound)
        }
        // Removing something absent is not an error; revocation must be
        // idempotent or a second click reports a failure that did not happen.
        XCTAssertNoThrow(try vault.remove("id_1"))
    }

    func testTwoVaultsDoNotShareSecrets() throws {
        let first = AgentCredentialVault.inMemory()
        let second = AgentCredentialVault.inMemory()
        _ = try first.store("s", "id", "Agent", [])
        XCTAssertThrowsError(try second.secret("id"))
    }

    // MARK: - Choosing a backend

    func testTheBackendFollowsWhetherTheKeychainCouldEnforceAnything() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("maruedit-vault-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }

        let automatic = AgentCredentialVault.automatic(directory: directory)
        let secret = try AgentCredentialStore.randomSecret()

        // Whichever backend this build gets, the contract is the same: what was
        // stored comes back, and removal is idempotent.
        let protection = try automatic.store(secret, "id_a", "Agent", [])
        XCTAssertEqual(try automatic.secret("id_a"), secret)
        try automatic.remove("id_a")
        XCTAssertNoThrow(try automatic.remove("id_a"))

        // And the reported protection matches the identity that decided it,
        // rather than being an aspiration.
        XCTAssertEqual(
            protection,
            AgentCredentialStore.hasStableCodeIdentity ? .codeIdentityEnforced : .fileOnly)
    }

    func testAnAdHocBuildDoesNotClaimAStableCodeIdentity() {
        // The test bundle is ad-hoc signed, like the shipping app. If this ever
        // reports true here, the Keychain path would be selected for a build
        // whose signature changes on every release — which is precisely the
        // configuration that cannot read its own items back after an update.
        XCTAssertFalse(
            AgentCredentialStore.hasStableCodeIdentity,
            "an ad-hoc build has no Team Identifier to bind a Keychain ACL to")
    }

    func testTheKeychainRefusesToStoreWithoutAnEnforceableACL() {
        // Storing an unprotected Keychain item would combine the update
        // problem with none of the benefit, so it is refused rather than
        // quietly written.
        XCTAssertThrowsError(
            try AgentCredentialStore.store(
                secret: "s", id: "id_never", label: "L", trustedExecutables: [])
        ) { error in
            XCTAssertEqual(
                error as? AgentCredentialStore.StoreError, .noStableCodeIdentity)
        }
    }

    // MARK: - The file backend

    func testTheFileBackendKeepsTheSecretReadableOnlyByThisAccount() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("maruedit-credfile-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }

        let secret = try AgentCredentialStore.randomSecret()
        try AgentCredentialFile.store(secret: secret, id: "id_f", directory: directory)

        let url = AgentCredentialFile.url(directory: directory, id: "id_f")
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        XCTAssertEqual(attributes[.posixPermissions] as? Int, 0o600)
        XCTAssertEqual(
            try FileManager.default.attributesOfItem(
                atPath: directory.path)[.posixPermissions] as? Int,
            0o700)

        XCTAssertEqual(try AgentCredentialFile.secret(id: "id_f", directory: directory), secret)
    }

    func testTheFileBackendNarrowsPermissionsOnAFileThatAlreadyExisted() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("maruedit-credfile-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        // Something else got there first with loose permissions. `O_CREAT` does
        // not narrow an existing file, so writing alone would leave it open.
        let url = AgentCredentialFile.url(directory: directory, id: "id_g")
        FileManager.default.createFile(
            atPath: url.path, contents: Data("old".utf8),
            attributes: [.posixPermissions: 0o644])

        try AgentCredentialFile.store(secret: "new-secret", id: "id_g", directory: directory)
        XCTAssertEqual(
            try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int,
            0o600)
        XCTAssertEqual(try AgentCredentialFile.secret(id: "id_g", directory: directory), "new-secret")
    }

    func testAMissingCredentialFileReportsNotFoundRatherThanEmpty() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("maruedit-credfile-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }

        XCTAssertThrowsError(try AgentCredentialFile.secret(id: "absent", directory: directory)) {
            XCTAssertEqual($0 as? AgentCredentialStore.StoreError, .notFound)
        }
        // An empty string would sail through as a credential and match nothing,
        // which is a confusing failure rather than a clear one.
        XCTAssertNoThrow(try AgentCredentialFile.remove(id: "absent", directory: directory))
    }

    // MARK: - The real Keychain

    /// Opt-in, because it writes into the login keychain of whoever runs it.
    ///
    /// Run with `MARUEDIT_TEST_KEYCHAIN=1 swift test`. It is not in the default
    /// suite: a test that leaves items in someone's keychain, or that blocks on
    /// an unlock prompt in CI, is a bad neighbour regardless of what it proves.
    func testARealKeychainRoundTrip() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["MARUEDIT_TEST_KEYCHAIN"] == "1",
            "set MARUEDIT_TEST_KEYCHAIN=1 to exercise the real Keychain")

        let id = "test_\(UUID().uuidString)"
        let secret = try AgentCredentialStore.randomSecret()
        defer { try? AgentCredentialStore.remove(id: id) }

        // A real ACL naming this test binary, which is the only configuration
        // the store now accepts.
        let protection = try AgentCredentialStore.store(
            secret: secret, id: id, label: "MaruEdit test",
            trustedExecutables: [CommandLine.arguments[0]])
        XCTAssertEqual(protection, .codeIdentityEnforced)
        XCTAssertEqual(try AgentCredentialStore.secret(id: id), secret)

        // Storing again under the same id replaces rather than duplicating, or
        // re-pairing would leave an unreachable item behind every time.
        let replacement = try AgentCredentialStore.randomSecret()
        _ = try AgentCredentialStore.store(
            secret: replacement, id: id, label: "MaruEdit test",
            trustedExecutables: [CommandLine.arguments[0]])
        XCTAssertEqual(try AgentCredentialStore.secret(id: id), replacement)

        try AgentCredentialStore.remove(id: id)
        XCTAssertThrowsError(try AgentCredentialStore.secret(id: id)) { error in
            XCTAssertEqual(error as? AgentCredentialStore.StoreError, .notFound)
        }
    }
}
