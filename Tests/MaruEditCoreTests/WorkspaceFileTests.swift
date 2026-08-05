import Foundation
import XCTest
@testable import MaruEditCore

final class WorkspaceFileTests: XCTestCase {
    func testWorkspaceRoundTripsAllDesktopState() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("workspace-\(UUID().uuidString).marudesk")
        defer { try? FileManager.default.removeItem(at: url) }
        let state = SessionState(
            rootFolderPath: "/project",
            openFiles: [OpenFileState(
                path: "/project/main.swift", cursorPosition: 42,
                scrollOffsetX: 3, scrollOffsetY: 90, collapsedFoldIDs: ["region"])],
            activeIndex: 0, windowZoomed: true, sidebarCollapsed: true)

        try WorkspaceFile.save(state, to: url)
        XCTAssertEqual(try WorkspaceFile.load(from: url), state)
    }
}
