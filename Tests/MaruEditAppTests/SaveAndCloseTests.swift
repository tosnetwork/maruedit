import Foundation
import XCTest
@testable import MaruEditApp

@MainActor
final class SaveAndCloseTests: XCTestCase {
    override func tearDown() {
        RecentItems.isRecordingSuspended = false
        super.tearDown()
    }

    func testOverwriteProtectionKeepsEditingAvailableAndHistoryCanBeSuspended() {
        let controller = MainWindowController()
        controller.prepareUITestDocument(content: "editable", selections: [])
        controller.toggleOverwriteProtection()
        XCTAssertTrue(controller.macroEditor.document?.isOverwriteProhibited == true)
        XCTAssertTrue(controller.macroEditor.textView.isEditable)

        let prior = RecentItems.files
        RecentItems.isRecordingSuspended = true
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("MaruEdit-suspended-\(UUID().uuidString).txt")
        try? "x".write(to: missing, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: missing) }
        RecentItems.addFile(missing)
        XCTAssertEqual(RecentItems.files, prior)
    }

    func testSaveAndCloseWritesNamedDocumentBeforeClosingItsTab() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("MaruEdit-save-close-\(UUID().uuidString).txt")
        try "before".write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let controller = MainWindowController()
        controller.openFile(url)
        let length = (controller.macroEditor.textView.string as NSString).length
        controller.macroEditor.batchReplace(
            [NSRange(location: 0, length: length)], with: "after")
        let countBeforeClose = controller.tabCountForTesting

        controller.saveAndCloseCurrentTab()

        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "after")
        XCTAssertEqual(controller.tabCountForTesting, countBeforeClose - 1)
    }

    func testSaveAllAndCloseWritesEveryNamedDocument() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MaruEdit-save-all-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = directory.appendingPathComponent("first.txt")
        let second = directory.appendingPathComponent("second.txt")
        try "one".write(to: first, atomically: true, encoding: .utf8)
        try "two".write(to: second, atomically: true, encoding: .utf8)

        let controller = MainWindowController()
        controller.openFile(first)
        controller.macroEditor.batchReplace(
            [NSRange(location: 0, length: 3)], with: "ONE")
        controller.openFile(second)
        controller.macroEditor.batchReplace(
            [NSRange(location: 0, length: 3)], with: "TWO")

        controller.saveAllAndClose()

        XCTAssertEqual(try String(contentsOf: first, encoding: .utf8), "ONE")
        XCTAssertEqual(try String(contentsOf: second, encoding: .utf8), "TWO")
        XCTAssertEqual(controller.tabCountForTesting, 1)
    }

    func testSaveAllWritesEveryNamedDocumentWithoutClosingTabs() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MaruEdit-save-all-open-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = directory.appendingPathComponent("first.txt")
        let second = directory.appendingPathComponent("second.txt")
        try "one".write(to: first, atomically: true, encoding: .utf8)
        try "two".write(to: second, atomically: true, encoding: .utf8)

        let controller = MainWindowController()
        controller.openFile(first)
        controller.macroEditor.batchReplace([NSRange(location: 0, length: 3)], with: "ONE")
        controller.openFile(second)
        controller.macroEditor.batchReplace([NSRange(location: 0, length: 3)], with: "TWO")
        controller.saveAllDocuments()

        XCTAssertEqual(try String(contentsOf: first, encoding: .utf8), "ONE")
        XCTAssertEqual(try String(contentsOf: second, encoding: .utf8), "TWO")
        XCTAssertEqual(controller.tabCountForTesting, 3)
    }

    func testDiscardAllClosesTabsWithoutWritingChanges() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MaruEdit-discard-all-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = directory.appendingPathComponent("first.txt")
        let second = directory.appendingPathComponent("second.txt")
        try "one".write(to: first, atomically: true, encoding: .utf8)
        try "two".write(to: second, atomically: true, encoding: .utf8)

        let controller = MainWindowController()
        controller.openFile(first)
        controller.macroEditor.batchReplace([NSRange(location: 0, length: 3)], with: "ONE")
        controller.openFile(second)
        controller.macroEditor.batchReplace([NSRange(location: 0, length: 3)], with: "TWO")
        controller.discardAllAndClose()

        XCTAssertEqual(try String(contentsOf: first, encoding: .utf8), "one")
        XCTAssertEqual(try String(contentsOf: second, encoding: .utf8), "two")
        XCTAssertEqual(controller.tabCountForTesting, 1)
    }

    func testSaveWithLFNormalizesLineEndingsOnDisk() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("MaruEdit-save-lf-\(UUID().uuidString).txt")
        try Data("one\r\ntwo\r\n".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let controller = MainWindowController()
        controller.openFile(url)
        controller.saveDocumentWithLFLineEndings()

        let bytes = try Data(contentsOf: url)
        XCTAssertEqual(String(decoding: bytes, as: UTF8.self), "one\ntwo\n")
    }

    func testCursorTargetsResolveRelativeToCurrentDocument() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MaruEdit-cursor-target-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("source.txt")
        let target = directory.appendingPathComponent("target.txt")
        try "target.txt".write(to: source, atomically: true, encoding: .utf8)
        try "destination".write(to: target, atomically: true, encoding: .utf8)

        let controller = MainWindowController()
        controller.openFile(source)
        controller.macroEditor.textView.setSelectedRange(NSRange(location: 0, length: 10))
        var associatedURL: URL?
        controller.openAssociatedURL = { associatedURL = $0 }
        controller.openCursorTargetWithAssociatedApplication()
        XCTAssertEqual(associatedURL?.standardizedFileURL, target.standardizedFileURL)

        controller.openCursorTargetInMaruEdit()
        XCTAssertEqual(controller.currentDocumentTextForTesting, "destination")
        XCTAssertEqual(controller.tabCountForTesting, 3)
    }
}
