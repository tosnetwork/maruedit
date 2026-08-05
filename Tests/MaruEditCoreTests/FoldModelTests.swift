import XCTest
@testable import MaruEditCore

final class FoldModelTests: XCTestCase {
    func testRegionsFollowOutlineHierarchyAndKeepHeadingVisible() throws {
        let text = "# Parent\nintro\n## Child\nbody\n# Next\nend"
        let outline = OutlineModel(text: text, language: .markdown)
        let model = FoldModel(text: text, symbols: outline.symbols)

        XCTAssertEqual(model.regions.map(\.title), ["Parent", "Child", "Next"])
        let parent = try XCTUnwrap(model.regions.first)
        XCTAssertEqual(parent.startLine, 0)
        XCTAssertEqual(parent.endLine, 3)
        XCTAssertEqual((text as NSString).substring(with: parent.hiddenUTF16Range),
                       "intro\n## Child\nbody\n")
    }

    func testToggleCollapseAllExpandAllAndUnknownID() throws {
        let text = "# One\na\n# Two\nb"
        let outline = OutlineModel(text: text, language: .markdown)
        var model = FoldModel(text: text, symbols: outline.symbols)
        let first = try XCTUnwrap(model.regions.first)

        XCTAssertTrue(model.toggle(regionID: first.id))
        XCTAssertTrue(model.isCollapsed(first))
        XCTAssertFalse(model.toggle(regionID: first.id))
        XCTAssertFalse(model.toggle(regionID: "missing"))
        model.collapseAll()
        XCTAssertEqual(model.collapsedRegionIDs.count, 2)
        model.expandAll()
        XCTAssertTrue(model.collapsedRegionIDs.isEmpty)
    }

    func testRebuildPreservesStableCollapsedRegionsAfterLinesMove() throws {
        let original = "# Keep\nbody\n# Remove\nbody"
        let outline = OutlineModel(text: original, language: .markdown)
        var model = FoldModel(text: original, symbols: outline.symbols)
        let keep = try XCTUnwrap(model.regions.first)
        model.toggle(regionID: keep.id)

        let edited = "preamble\n# Keep\nbody"
        let editedOutline = OutlineModel(text: edited, language: .markdown)
        model.rebuild(text: edited, symbols: editedOutline.symbols)
        XCTAssertEqual(model.regions.map(\.title), ["Keep"])
        XCTAssertEqual(model.collapsedRegionIDs, [keep.id])
        XCTAssertEqual(model.regions[0].startLine, 1)
    }

    func testLeafSymbolAndEmptyDocumentProduceNoRegions() {
        let leafText = "# Only"
        let outline = OutlineModel(text: leafText, language: .markdown)
        XCTAssertTrue(FoldModel(text: leafText, symbols: outline.symbols).regions.isEmpty)
        XCTAssertTrue(FoldModel(text: "", symbols: []).regions.isEmpty)
    }
}
