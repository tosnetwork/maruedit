import Foundation
import XCTest
@testable import MaruEditApp

@MainActor
final class SaveAndCloseTests: XCTestCase {
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
}
