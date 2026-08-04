import AppKit
import XCTest
import MaruEditCore
@preconcurrency @testable import MaruEditApp


@preconcurrency @MainActor
final class MacroManagerTests: XCTestCase {
    func testReloadRegistersMenusShortcutsEnablementAndExecutes() async throws {
        let directory = try makeDirectory()
        let upper = directory.appendingPathComponent("upper.js")
        try """
        // @maru-name: Upper Selection
        // @maru-description: Test macro
        // @maru-shortcut: cmd+shift+9
        maru.editor.replaceSelections('UP');
        """.write(to: upper, atomically: true, encoding: .utf8)
        let coordinator = AppCoordinator(preferencesStore: isolatedPreferences())
        coordinator.prepareUITestDocument(content: "abc", selections: [NSRange(location: 0, length: 3)])
        let bindings = KeyBindingManager()
        let store = MacroEnablementStore(defaults: isolatedDefaults())
        let manager = MacroManager(directory: directory, coordinator: coordinator,
                                   keyBindings: bindings, enablementStore: store)
        manager.reload()
        let macro = try XCTUnwrap(manager.catalog.macros.first)
        XCTAssertNotNil(coordinator.commandRegistry.definition(for: macro.id))
        XCTAssertEqual(bindings.keys(for: macro.id), [KeyGesture("cmd+shift+9")!])
        XCTAssertTrue(manager.menu.items.contains { $0.title == "Upper Selection" })

        let finished = expectation(description: "macro executed")
        manager.executionDidFinish = { _, result in
            if case .failure(let error) = result { XCTFail("Unexpected macro failure: \(error)") }
            finished.fulfill()
        }
        manager.runForTesting(macro.id)
        await fulfillment(of: [finished], timeout: 2)
        XCTAssertEqual(coordinator.ensureWindowControllerReady().macroEditor.textView.string, "UP")

        manager.toggleForTesting(macro.id)
        XCTAssertFalse(manager.catalog.macros[0].isEnabled)
        XCTAssertNil(bindings.keys(for: macro.id))
        XCTAssertFalse(coordinator.commandRegistry.isEnabled(
            macro.id, context: CommandContext(coordinator: coordinator)))
        manager.toggleForTesting(macro.id)
        XCTAssertTrue(manager.catalog.macros[0].isEnabled)
    }

    func testReloadRemovesDeletedCommandsAndErrorConsoleShowsStack() async throws {
        let directory = try makeDirectory()
        let broken = directory.appendingPathComponent("broken.js")
        try "// @maru-name: Broken\nthrow new Error('kaboom')"
            .write(to: broken, atomically: true, encoding: .utf8)
        let coordinator = AppCoordinator(preferencesStore: isolatedPreferences())
        let manager = MacroManager(directory: directory, coordinator: coordinator,
                                   keyBindings: KeyBindingManager(),
                                   enablementStore: MacroEnablementStore(defaults: isolatedDefaults()))
        manager.reload()
        let id = try XCTUnwrap(manager.catalog.macros.first?.id)
        let finished = expectation(description: "broken macro")
        manager.executionDidFinish = { _, _ in finished.fulfill() }
        manager.runForTesting(id)
        await fulfillment(of: [finished], timeout: 2)
        manager.showErrorConsoleForTesting()
        XCTAssertTrue(manager.errorConsoleTextForTesting.contains("Broken"))
        XCTAssertTrue(manager.errorConsoleTextForTesting.contains("kaboom"))

        try FileManager.default.removeItem(at: broken)
        manager.reload()
        XCTAssertNil(coordinator.commandRegistry.definition(for: id))
        XCTAssertEqual(manager.catalog.macros, [])
    }

    func testUnauthorizedNetworkMacroIsRejectedBeforeScriptRuns() async throws {
        let directory = try makeDirectory()
        try """
        // @maru-name: Network Attempt
        // @maru-permissions: network
        maru.document.setText('should not run');
        """.write(to: directory.appendingPathComponent("network.js"), atomically: true, encoding: .utf8)
        let coordinator = AppCoordinator(preferencesStore: isolatedPreferences())
        coordinator.prepareUITestDocument(content: "safe", selections: [NSRange(location: 0, length: 0)])
        let manager = MacroManager(directory: directory, coordinator: coordinator,
                                   keyBindings: KeyBindingManager(),
                                   enablementStore: MacroEnablementStore(defaults: isolatedDefaults()),
                                   authorizer: MacroPermissionAuthorizer(
                                    store: MacroPermissionStore(defaults: isolatedDefaults()),
                                    chooseDirectory: { _ in nil }, confirmExternalCommands: { _ in false }))
        manager.reload()
        let id = try XCTUnwrap(manager.catalog.macros.first?.id)
        let finished = expectation(description: "permission rejection")
        manager.executionDidFinish = { _, result in
            guard case .failure = result else { return XCTFail("Expected denial") }
            finished.fulfill()
        }
        manager.runForTesting(id)
        await fulfillment(of: [finished], timeout: 1)
        XCTAssertEqual(coordinator.ensureWindowControllerReady().macroEditor.textView.string, "safe")
        XCTAssertTrue(manager.errors.last?.message.contains("network access is never available") == true)
    }

    func testExperimentalCompatibilityMustBeEnabledAndExecutesThroughNativeHost() async throws {
        let directory = try makeDirectory()
        try "selectall; toupper;".write(
            to: directory.appendingPathComponent("upper.mac"), atomically: true, encoding: .utf8)
        let coordinator = AppCoordinator(preferencesStore: isolatedPreferences())
        coordinator.prepareUITestDocument(content: "Mixed", selections: [NSRange(location: 0, length: 0)])
        let disabled = MacroManager(directory: directory, coordinator: coordinator,
                                    keyBindings: KeyBindingManager(), enableHidemaruCompatibility: false)
        disabled.reload(); XCTAssertTrue(disabled.catalog.macros.isEmpty)
        let enabled = MacroManager(directory: directory, coordinator: coordinator,
                                   keyBindings: KeyBindingManager(), enableHidemaruCompatibility: true)
        enabled.reload()
        let macro = try XCTUnwrap(enabled.catalog.macros.first)
        let finished = expectation(description: "compatibility macro")
        enabled.executionDidFinish = { _, _ in finished.fulfill() }
        enabled.runForTesting(macro.id); await fulfillment(of: [finished], timeout: 2)
        XCTAssertEqual(coordinator.ensureWindowControllerReady().macroEditor.textView.string, "MIXED")
        XCTAssertTrue(macro.metadata.name.contains("Experimental"))
    }

    private func makeDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    private func isolatedDefaults() -> UserDefaults {
        UserDefaults(suiteName: "MacroManagerTests.\(UUID().uuidString)")!
    }
    private func isolatedPreferences() -> PreferencesStore {
        PreferencesStore(defaults: isolatedDefaults())
    }
}
