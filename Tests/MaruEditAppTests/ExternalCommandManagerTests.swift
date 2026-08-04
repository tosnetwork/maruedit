import XCTest
import MaruEditCore
@testable import MaruEditApp

final class ExternalCommandManagerTests: XCTestCase {
    func testReloadRegistersCommandsBuildsRiskMarkedMenuAndRemovesDeletedCommands() throws {
        let url = temporaryConfigurationURL()
        let direct = ExternalCommandConfiguration(
            id: "direct", name: "Direct", executable: "/usr/bin/true")
        let shell = ExternalCommandConfiguration(
            id: "shell", name: "Shell Example", executable: "",
            shellMode: true, shellCommand: "true")
        try ExternalCommandConfigurationStore.encode([direct, shell]).write(to: url)
        let coordinator = coordinator()
        var shellConfirmations = 0
        let manager = ExternalCommandManager(
            configurationURL: url, coordinator: coordinator,
            confirmShell: { _ in shellConfirmations += 1; return false })
        manager.reload()

        XCTAssertNotNil(coordinator.commandRegistry.definition(for: direct.commandID))
        XCTAssertNotNil(coordinator.commandRegistry.definition(for: shell.commandID))
        XCTAssertTrue(manager.menu.items.contains { $0.title == "⚠︎ Shell Example (Shell)" })
        manager.runForTesting(shell.commandID)
        XCTAssertEqual(shellConfirmations, 1)

        try ExternalCommandConfigurationStore.encode([direct]).write(to: url)
        manager.reload()
        XCTAssertNil(coordinator.commandRegistry.definition(for: shell.commandID))
    }

    func testInvalidConfigurationFailsClosedWithoutRegisteringCommands() throws {
        let url = temporaryConfigurationURL()
        try Data("[{\"schemaVersion\":99}]".utf8).write(to: url)
        let coordinator = coordinator()
        let manager = ExternalCommandManager(configurationURL: url, coordinator: coordinator)
        manager.reload()
        XCTAssertTrue(manager.configurations.isEmpty)
        XCTAssertNotNil(manager.lastError)
        XCTAssertEqual(manager.menu.items.first?.title, "Configuration Error")
    }

    private func temporaryConfigurationURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("ExternalCommandManagerTests-\(UUID().uuidString).json")
    }
    private func coordinator() -> AppCoordinator {
        AppCoordinator(preferencesStore: PreferencesStore(defaults: UserDefaults(
            suiteName: "ExternalCommandManagerTests.\(UUID().uuidString)")!))
    }
}
