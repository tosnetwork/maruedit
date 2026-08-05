import AppKit
import MaruEditCore
import XCTest
@preconcurrency @testable import MaruEditApp

@MainActor
final class ExternalHelpTests: XCTestCase {
    func testStoreAlwaysPersistsExactlySixNamedSlots() {
        let defaults = UserDefaults(suiteName: "ExternalHelp.\(UUID().uuidString)")!
        let store = ExternalHelpStore(defaults: defaults)
        store.save([ExternalHelpEntry(name: "API", target: "https://example.com/api")])
        let loaded = store.load()
        XCTAssertEqual(loaded.count, 6)
        XCTAssertEqual(loaded[0], ExternalHelpEntry(name: "API", target: "https://example.com/api"))
        XCTAssertEqual(loaded[5].name, "External Help 6")
        XCTAssertFalse(loaded[5].isConfigured)
    }

    func testConfiguredSlotControlsEnablementAndOpensURL() {
        let defaults = UserDefaults(suiteName: "ExternalHelp.\(UUID().uuidString)")!
        let coordinator = AppCoordinator(
            preferencesStore: PreferencesStore(defaults: defaults),
            externalHelpStore: ExternalHelpStore(defaults: defaults))
        var opened: URL?
        coordinator.openDocumentationURL = { opened = $0 }
        let context = CommandContext(coordinator: coordinator)
        XCTAssertFalse(coordinator.commandRegistry.isEnabled(.helpExternal1, context: context))
        coordinator.setExternalHelpEntriesForTesting([
            ExternalHelpEntry(name: "API", target: "https://example.com/reference"),
        ])
        XCTAssertTrue(coordinator.commandRegistry.isEnabled(.helpExternal1, context: context))
        XCTAssertTrue(coordinator.commandRegistry.execute(.helpExternal1, context: context))
        XCTAssertEqual(opened?.absoluteString, "https://example.com/reference")
        XCTAssertFalse(coordinator.commandRegistry.isEnabled(.helpExternal2, context: context))
    }

    func testConfigurationControllerSavesEditedSlot() {
        var saved: [ExternalHelpEntry] = []
        let entries = (1...6).map { ExternalHelpEntry(name: "External Help \($0)", target: "") }
        let controller = ExternalHelpWindowController(entries: entries, onSave: { saved = $0 })
        controller.setEntryForTesting(slot: 2, name: "SDK", target: "/tmp/sdk-help.html")
        controller.saveForTesting()
        XCTAssertEqual(saved.count, 6)
        XCTAssertEqual(saved[2], ExternalHelpEntry(name: "SDK", target: "/tmp/sdk-help.html"))
    }
}
