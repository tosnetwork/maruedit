import XCTest
import MaruEditCore
@preconcurrency @testable import MaruEditApp


@preconcurrency @MainActor
final class MacroPermissionTests: XCTestCase {
    func testCurrentDocumentDefaultExternalDecisionRememberAndRevokeUI() async throws {
        let store = MacroPermissionStore(defaults: isolatedDefaults())
        var prompts = 0
        let authorizer = MacroPermissionAuthorizer(
            store: store, chooseDirectory: { _ in nil },
            confirmExternalCommands: { _ in prompts += 1; return true })
        let basic = macro(permissions: [.currentDocument])
        XCTAssertEqual(try authorizer.authorize(basic).get().permissions, [.currentDocument])
        let external = macro(permissions: [.currentDocument, .externalCommands])
        XCTAssertEqual(try authorizer.authorize(external).get().permissions,
                       [.currentDocument, .externalCommands])
        XCTAssertEqual(try authorizer.authorize(external).get().permissions,
                       [.currentDocument, .externalCommands])
        XCTAssertEqual(prompts, 1, "remembered Allow must not prompt again")

        let window = MacroPermissionWindowController(store: store)
        XCTAssertEqual(window.displayedRowsForTesting, 1)
        let grant = try XCTUnwrap(store.load().grants.first)
        window.revokeForTesting(grant)
        XCTAssertEqual(window.displayedRowsForTesting, 0)
    }

    func testDeniedExternalAndNetworkFailExplicitly() async {
        let store = MacroPermissionStore(defaults: isolatedDefaults())
        let authorizer = MacroPermissionAuthorizer(
            store: store, chooseDirectory: { _ in nil }, confirmExternalCommands: { _ in false })
        let external = macro(permissions: [.externalCommands])
        guard case .failure(let denied) = authorizer.authorize(external) else {
            return XCTFail("Expected external command denial")
        }
        XCTAssertEqual(denied.permission, .externalCommands)
        XCTAssertEqual(store.decision(for: external.id, permission: .externalCommands)?.decision, .denied)
        guard case .failure(let network) = authorizer.authorize(macro(permissions: [.network])) else {
            return XCTFail("Expected network denial")
        }
        XCTAssertEqual(network.permission, .network)
        XCTAssertTrue(network.localizedDescription.contains("never available"))
    }

    func testDirectoryDecisionIsRememberedWithSecurityBookmark() async throws {
        let store = MacroPermissionStore(defaults: isolatedDefaults())
        let directory = FileManager.default.temporaryDirectory
        var choices = 0
        let authorizer = MacroPermissionAuthorizer(
            store: store, chooseDirectory: { _ in choices += 1; return directory },
            confirmExternalCommands: { _ in false })
        let fileMacro = macro(permissions: [.otherFiles])
        let first = try authorizer.authorize(fileMacro).get()
        first.stopAccessing()
        let second = try authorizer.authorize(fileMacro).get()
        second.stopAccessing()
        XCTAssertEqual(choices, 1)
        XCTAssertNotNil(store.decision(for: fileMacro.id, permission: .otherFiles)?.directoryBookmark)
    }

    private func macro(permissions: Set<MacroPermission>) -> UserMacro {
        UserMacro(id: "macro.user.permissions", url: URL(fileURLWithPath: "/tmp/test.js"), source: "1",
                  metadata: .init(name: "Permission Test", description: "", shortcut: nil,
                                  requiredPermissions: permissions), isEnabled: true)
    }
    private func isolatedDefaults() -> UserDefaults {
        UserDefaults(suiteName: "MacroPermissionTests.\(UUID().uuidString)")!
    }
}
