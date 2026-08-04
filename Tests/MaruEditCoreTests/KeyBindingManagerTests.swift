import XCTest
@testable import MaruEditCore

final class KeyBindingManagerTests: XCTestCase {
    func testDynamicBindingsOverlayProfileWithoutChangingExport() throws {
        let manager = KeyBindingManager(profile: .macOSStandard)
        let dynamic = KeyBinding(keys: [KeyGesture("cmd+shift+m")!], command: "macro.user.test")
        manager.setDynamicBindings([dynamic])
        XCTAssertEqual(manager.command(for: dynamic.keys), dynamic.command)
        XCTAssertEqual(manager.keys(for: dynamic.command), dynamic.keys)
        XCTAssertFalse(String(decoding: try manager.exportJSON(), as: UTF8.self).contains("macro.user.test"))
        manager.setDynamicBindings([])
        XCTAssertNil(manager.command(for: dynamic.keys))
    }
    func testSchemaV1RoundTripsPortableGestureStrings() throws {
        let manager = KeyBindingManager(profile: KeyBindingProfile(name: "Custom", bindings: [
            KeyBinding(keys: [KeyGesture("cmd+k")!, KeyGesture("cmd+c")!], command: "edit.commentLine"),
        ]))
        let data = try manager.exportJSON()
        let json = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(json.contains("\"schemaVersion\" : 1"))
        XCTAssertTrue(json.contains("\"cmd+k\""))
        XCTAssertTrue(json.contains("\"command\" : \"edit.commentLine\""))
        XCTAssertFalse(json.contains("rawValue"))

        let imported = try KeyBindingManager().importJSON(data)
        XCTAssertEqual(imported, manager.activeProfile)
    }

    func testRejectsUnsupportedSchemaAndEmptySequence() throws {
        let manager = KeyBindingManager()
        XCTAssertThrowsError(try manager.activate(KeyBindingProfile(
            name: "Future", bindings: [], schemaVersion: 2))) {
            XCTAssertEqual($0 as? KeyBindingError, .unsupportedSchema(2))
        }
        XCTAssertThrowsError(try manager.activate(KeyBindingProfile(name: "Bad", bindings: [
            KeyBinding(keys: [], command: "file.save"),
        ]))) {
            XCTAssertEqual($0 as? KeyBindingError, .emptySequence("file.save"))
        }
    }

    func testConflictDetectionReportsCommandsSharingASequence() {
        let shared = [KeyGesture("cmd+f")!]
        let manager = KeyBindingManager(profile: KeyBindingProfile(name: "Conflict", bindings: [
            KeyBinding(keys: shared, command: "search.find"),
            KeyBinding(keys: shared, command: "search.grep"),
            KeyBinding(keys: [KeyGesture("cmd+s")!], command: "file.save"),
        ]))
        XCTAssertEqual(manager.conflicts, [KeyBindingConflict(
            keys: shared, commands: ["search.find", "search.grep"]
        )])
    }

    func testBuiltInProfilesAreIndependentAndConflictFree() {
        let standard = KeyBindingManager(profile: .macOSStandard)
        let classic = KeyBindingManager(profile: .maruClassic)
        XCTAssertEqual(standard.command(for: [KeyGesture("cmd+f")!]), "search.find")
        XCTAssertEqual(classic.command(for: [KeyGesture("ctrl+f")!]), "search.find")
        XCTAssertNil(classic.command(for: [KeyGesture("cmd+f")!]))
        XCTAssertTrue(standard.conflicts.isEmpty)
        XCTAssertTrue(classic.conflicts.isEmpty)
    }

    func testImportExportFilesAndRestoreDefaults() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("bindings.json")
        let manager = KeyBindingManager(profile: .maruClassic)
        try manager.export(to: url)
        manager.restoreDefaults(.macOSStandard)
        XCTAssertEqual(manager.activeProfile.name, "macOS Standard")
        try manager.import(from: url)
        XCTAssertEqual(manager.activeProfile.name, "Maru Classic")
    }
}
