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

        XCTAssertEqual(try vault.store(secret, "id_1", "Agent", []), .keychainOnly)
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

        // No trusted executables: an ACL cannot be built, so the honest report
        // is reduced protection rather than a success that claims more.
        let protection = try AgentCredentialStore.store(
            secret: secret, id: id, label: "MaruEdit test", trustedExecutables: [])
        XCTAssertEqual(protection, .keychainOnly)
        XCTAssertEqual(try AgentCredentialStore.secret(id: id), secret)

        // Storing again under the same id replaces rather than duplicating, or
        // re-pairing would leave an unreachable item behind every time.
        let replacement = try AgentCredentialStore.randomSecret()
        _ = try AgentCredentialStore.store(
            secret: replacement, id: id, label: "MaruEdit test", trustedExecutables: [])
        XCTAssertEqual(try AgentCredentialStore.secret(id: id), replacement)

        try AgentCredentialStore.remove(id: id)
        XCTAssertThrowsError(try AgentCredentialStore.secret(id: id)) { error in
            XCTAssertEqual(error as? AgentCredentialStore.StoreError, .notFound)
        }
    }
}
