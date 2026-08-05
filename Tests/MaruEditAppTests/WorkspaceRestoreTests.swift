import Foundation
import MaruEditCore
import XCTest
@testable import MaruEditApp

@MainActor
final class WorkspaceRestoreTests: XCTestCase {
    func testOpeningWorkspaceRestoresFilesActiveTabAndCursor() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MaruEdit-workspace-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = directory.appendingPathComponent("first.txt")
        let second = directory.appendingPathComponent("second.txt")
        try "first contents".write(to: first, atomically: true, encoding: .utf8)
        try "second contents".write(to: second, atomically: true, encoding: .utf8)
        let workspace = directory.appendingPathComponent("test.marudesk")
        try WorkspaceFile.save(SessionState(
            rootFolderPath: directory.path,
            openFiles: [
                OpenFileState(path: first.path, cursorPosition: 2, scrollOffsetX: 0, scrollOffsetY: 0),
                OpenFileState(path: second.path, cursorPosition: 6, scrollOffsetX: 0, scrollOffsetY: 0),
            ],
            activeIndex: 1, windowZoomed: false, sidebarCollapsed: false), to: workspace)

        let controller = MainWindowController()
        controller.openWorkspace(workspace)

        XCTAssertEqual(controller.tabCountForTesting, 2)
        XCTAssertEqual(controller.editorTextForTesting, "second contents")
        XCTAssertEqual(controller.macroEditor.selectionSet.primaryRange.location, 6)
    }
}
