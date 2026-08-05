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
}
