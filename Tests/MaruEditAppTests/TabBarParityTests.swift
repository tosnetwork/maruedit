import XCTest
@preconcurrency @testable import MaruEditApp

@MainActor
final class TabBarParityTests: XCTestCase {
    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: "MaruTabBarPosition")
        UserDefaults.standard.removeObject(forKey: "MaruTabBarHideSingle")
        super.tearDown()
    }

    func testPositionAndSingleTabVisibilityOptionsPersist() {
        let bar = TabBarView(frame: NSRect(x: 0, y: 0, width: 500, height: 32))
        bar.position = .bottom
        bar.hidesForSingleTab = true
        bar.setTabs([TabItem(title: "one", isModified: false)], selectedIndex: 0)
        XCTAssertEqual(bar.position, .bottom)
        XCTAssertEqual(bar.effectiveHeight, 0)
        bar.setTabs([
            TabItem(title: "one", isModified: false),
            TabItem(title: "two", isModified: true),
        ], selectedIndex: 1)
        XCTAssertEqual(bar.effectiveHeight, 32)
    }

    func testAutomaticWidthsKeepAllTabsInsideAvailableRow() {
        let bar = TabBarView(frame: NSRect(x: 0, y: 0, width: 320, height: 32))
        bar.setTabs((0..<10).map { TabItem(title: "tab-\($0)", isModified: false) }, selectedIndex: 0)
        bar.layoutSubtreeIfNeeded()
        XCTAssertEqual(bar.tabWidthForTesting, 32)
        XCTAssertLessThanOrEqual(bar.tabWidthForTesting * 10, bar.bounds.width)
    }

    func testCloseAffordanceFollowsSelectionAndHover() {
        let bar = TabBarView(frame: NSRect(x: 0, y: 0, width: 500, height: 32))
        bar.setTabs([
            TabItem(title: "one", isModified: false),
            TabItem(title: "two", isModified: false),
        ], selectedIndex: 0)
        bar.layoutSubtreeIfNeeded()
        XCTAssertEqual(bar.visibleCloseIndicesForTesting, [0])
        bar.setHoveredIndexForTesting(1)
        XCTAssertEqual(bar.visibleCloseIndicesForTesting, [0, 1])
        bar.setHoveredIndexForTesting(nil)
        XCTAssertEqual(bar.visibleCloseIndicesForTesting, [0])
    }

    func testRelativeTabSelectionWrapsInBothDirections() {
        let controller = MainWindowController()
        controller.newDocument()
        controller.newDocument()
        XCTAssertEqual(controller.tabCountForTesting, 3)
        XCTAssertEqual(controller.selectedTabIndexForTesting, 2)
        controller.selectRelativeTab(1)
        XCTAssertEqual(controller.selectedTabIndexForTesting, 0)
        controller.selectRelativeTab(-1)
        XCTAssertEqual(controller.selectedTabIndexForTesting, 2)
    }

    func testCloseOtherTabsKeepsClickedTab() {
        let controller = MainWindowController()
        controller.newDocument()
        controller.newDocument()
        controller.tabBarDidRequestClose(.others, at: 1)
        XCTAssertEqual(controller.tabCountForTesting, 1)
        XCTAssertEqual(controller.selectedTabIndexForTesting, 0)
    }
}
