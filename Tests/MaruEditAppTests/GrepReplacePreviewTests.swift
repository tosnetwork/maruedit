import XCTest
import MaruEditCore
@preconcurrency @testable import MaruEditApp


@preconcurrency @MainActor
final class GrepReplacePreviewTests: XCTestCase {
    func testPreviewShowsBeforeAfterAndAllowsFileAndMatchSelection() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("foo and foo".utf8).write(to: root.appendingPathComponent("a.txt"))
        let set = try GrepReplaceService.scan(
            request: GrepRequest(query: SearchQuery(pattern: "foo"), roots: [root]),
            replacement: "bar")
        let preview = GrepReplacePreviewWindowController(changeSet: set)
        XCTAssertEqual(preview.beforeTextForTesting, "foo and foo")
        XCTAssertEqual(preview.afterTextForTesting, "bar and bar")
        XCTAssertGreaterThan(preview.previewWidthForTesting, 200)
        preview.setMatchSelectedForTesting(false, file: 0, match: 1)
        XCTAssertEqual(preview.afterTextForTesting, "bar and foo")
        XCTAssertEqual(preview.changeSet.selectedMatchCount, 1)
        preview.setFileSelectedForTesting(false, file: 0)
        XCTAssertEqual(preview.afterTextForTesting, "foo and foo")
        XCTAssertEqual(preview.changeSet.selectedFileCount, 0)
    }
}
