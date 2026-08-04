import XCTest
@testable import MaruEditCore

final class MacroCatalogTests: XCTestCase {
    func testScansNestedJavaScriptAndParsesMetadata() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let nested = directory.appendingPathComponent("Tools")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        let url = nested.appendingPathComponent("upper.js")
        try """
        // @maru-name: Uppercase Selection
        // @maru-description: Makes text loud
        // @maru-shortcut: cmd+shift+u
        // @maru-permissions: currentDocument, clipboard
        maru.editor.replaceSelections('X');
        """.write(to: url, atomically: true, encoding: .utf8)
        try "ignored".write(to: directory.appendingPathComponent("notes.txt"), atomically: true, encoding: .utf8)

        let catalog = MacroCatalogLoader.load(from: directory)
        XCTAssertEqual(catalog.issues, [])
        XCTAssertEqual(catalog.macros.count, 1)
        XCTAssertEqual(catalog.macros[0].metadata.name, "Uppercase Selection")
        XCTAssertEqual(catalog.macros[0].metadata.shortcut, "cmd+shift+u")
        XCTAssertEqual(catalog.macros[0].metadata.requiredPermissions, [.currentDocument, .clipboard])
        XCTAssertEqual(catalog.macros[0].id.rawValue, "macro.user.tools_upper_js")
    }

    func testFallbackMetadataEnablementAndStableSorting() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try "1".write(to: directory.appendingPathComponent("Zulu.js"), atomically: true, encoding: .utf8)
        try "1".write(to: directory.appendingPathComponent("alpha.js"), atomically: true, encoding: .utf8)
        let disabled: Set<CommandID> = ["macro.user.zulu_js"]
        let catalog = MacroCatalogLoader.load(from: directory, disabledIDs: disabled)
        XCTAssertEqual(catalog.macros.map(\.metadata.name), ["alpha", "Zulu"])
        XCTAssertEqual(catalog.macros.map(\.isEnabled), [true, false])
    }

    func testEnablementStorePersistsOnlyDisabledCommandIDs() {
        let suite = "MacroCatalogTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let store = MacroEnablementStore(defaults: defaults)
        let id: CommandID = "macro.user.test_js"
        store.setEnabled(false, id: id)
        XCTAssertEqual(store.disabledIDs(), [id])
        store.setEnabled(true, id: id)
        XCTAssertTrue(store.disabledIDs().isEmpty)
    }
}
