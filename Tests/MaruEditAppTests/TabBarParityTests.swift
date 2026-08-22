import XCTest
@preconcurrency @testable import MaruEditApp

@MainActor
final class TabBarParityTests: XCTestCase {
    override func setUp() {
        super.setUp()
        UserDefaults.standard.set(AppLanguage.english.rawValue, forKey: AppLocalization.defaultsKey)
    }
    private final class Delegate: TabBarViewDelegate {
        var selected: [Int] = []
        var closed: [Int] = []
        func tabBarDidSelectTab(at index: Int) { selected.append(index) }
        func tabBarDidCloseTab(at index: Int) { closed.append(index) }
        func tabBarDidMoveTab(from source: Int, to destination: Int) {}
        func tabBarDidRequestClose(_ scope: TabCloseScope, at index: Int) {}
        func tabBarLayoutOptionsDidChange() {}
    }
    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: AppLocalization.defaultsKey)
        UserDefaults.standard.removeObject(forKey: "MaruTabBarPosition")
        UserDefaults.standard.removeObject(forKey: "MaruTabBarHideSingle")
        UserDefaults.standard.removeObject(forKey: "MaruTabModeEnabled")
        UserDefaults.standard.removeObject(forKey: "MaruTabActiveLine")
        UserDefaults.standard.removeObject(forKey: "MaruTabActiveFace")
        super.tearDown()
    }

    func testTabModeCanHideAndRestoreTheBarWithoutDiscardingTabs() {
        let bar = TabBarView(frame: NSRect(x: 0, y: 0, width: 500, height: 32))
        bar.setTabs([
            TabItem(title: "one", isModified: false),
            TabItem(title: "two", isModified: true),
        ], selectedIndex: 1)
        XCTAssertTrue(bar.isTabModeEnabled)
        XCTAssertEqual(bar.effectiveHeight, 32)

        bar.isTabModeEnabled = false
        XCTAssertEqual(bar.effectiveHeight, 0)
        XCTAssertEqual(bar.tabs.count, 2)
        XCTAssertEqual(bar.selectedIndex, 1)

        bar.isTabModeEnabled = true
        XCTAssertEqual(bar.effectiveHeight, 32)
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

    func testSingleTabIsHiddenByDefaultAndExplicitVisibleChoiceIsRespected() {
        let bar = TabBarView(frame: NSRect(x: 0, y: 0, width: 500, height: 32))
        bar.setTabs([TabItem(title: "one", isModified: false)], selectedIndex: 0)
        XCTAssertTrue(bar.hidesForSingleTab)
        XCTAssertEqual(bar.effectiveHeight, 0)

        bar.hidesForSingleTab = false
        XCTAssertFalse(bar.hidesForSingleTab)
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

    func testTabsAndCloseAffordancesAreKeyboardAndVoiceOverOperable() {
        let bar = TabBarView(frame: NSRect(x: 0, y: 0, width: 500, height: 32))
        let delegate = Delegate(); bar.delegate = delegate
        bar.setTabs([
            TabItem(title: "one.swift", isModified: false),
            TabItem(title: "two.txt", isModified: true),
        ], selectedIndex: 1)
        bar.layoutSubtreeIfNeeded()

        let controls = bar.accessibilityTabControlsForTesting
        XCTAssertEqual(controls.count, 2)
        XCTAssertTrue(controls.allSatisfy { $0.tab.acceptsFirstResponder })
        XCTAssertEqual(controls[0].tab.accessibilityRole(), .radioButton)
        XCTAssertEqual(controls[1].tab.accessibilityValue() as? String, "selected")
        XCTAssertEqual(controls[0].close.accessibilityRole(), .button)
        XCTAssertEqual(controls[0].tab.accessibilityLabel(), "Tab 1: one.swift")
        XCTAssertEqual(controls[1].close.accessibilityLabel(), "Close tab 2: two.txt")

        XCTAssertTrue(controls[0].tab.accessibilityPerformPress())
        XCTAssertTrue(controls[1].close.accessibilityPerformPress())
        XCTAssertEqual(delegate.selected, [0])
        XCTAssertEqual(delegate.closed, [1])
    }

    func testActiveTabIsDistinguishedByFaceLineWeightAndHeight() {
        let bar = TabBarView(frame: NSRect(x: 0, y: 0, width: 500, height: 32))
        bar.setTabs([
            TabItem(title: "one", isModified: false),
            TabItem(title: "two", isModified: false),
        ], selectedIndex: 1)
        bar.layoutSubtreeIfNeeded()

        XCTAssertTrue(bar.isActiveLineVisibleForTesting(at: 1))
        XCTAssertFalse(bar.isActiveLineVisibleForTesting(at: 0))

        let activeFace = try? XCTUnwrap(bar.tabFaceColorForTesting(at: 1))
        let inactiveFace = try? XCTUnwrap(bar.tabFaceColorForTesting(at: 0))
        XCTAssertNotEqual(activeFace, inactiveFace)

        let activeWeight = bar.titleFontForTesting(at: 1)?.fontDescriptor.symbolicTraits.contains(.bold)
        let inactiveWeight = bar.titleFontForTesting(at: 0)?.fontDescriptor.symbolicTraits.contains(.bold)
        XCTAssertEqual(activeWeight, true)
        XCTAssertEqual(inactiveWeight, false)

        let active = try? XCTUnwrap(bar.tabFrameForTesting(at: 1))
        let inactive = try? XCTUnwrap(bar.tabFrameForTesting(at: 0))
        XCTAssertGreaterThan(active?.height ?? 0, inactive?.height ?? 0)
        XCTAssertEqual(active?.height, 32)
    }

    func testActiveTabCoversTheDocumentEdgeOnBothBarPositions() {
        let bar = TabBarView(frame: NSRect(x: 0, y: 0, width: 500, height: 32))
        bar.setTabs([
            TabItem(title: "one", isModified: false),
            TabItem(title: "two", isModified: false),
        ], selectedIndex: 0)

        bar.position = .top
        bar.needsLayout = true
        bar.layoutSubtreeIfNeeded()
        // Top bar: the document is below, so the active tab reaches the bottom edge.
        XCTAssertEqual(bar.tabFrameForTesting(at: 0)?.maxY, 32)
        XCTAssertLessThan(bar.tabFrameForTesting(at: 1)?.maxY ?? 32, 32)

        bar.position = .bottom
        bar.needsLayout = true
        bar.layoutSubtreeIfNeeded()
        // Bottom bar: the document is above, so the active tab reaches the top edge.
        XCTAssertEqual(bar.tabFrameForTesting(at: 0)?.minY, 0)
        XCTAssertGreaterThan(bar.tabFrameForTesting(at: 1)?.minY ?? 0, 0)
    }

    func testActiveTabEmphasisOptionsPersistAndCanBeTurnedOff() {
        let bar = TabBarView(frame: NSRect(x: 0, y: 0, width: 500, height: 32))
        bar.setTabs([
            TabItem(title: "one", isModified: false),
            TabItem(title: "two", isModified: false),
        ], selectedIndex: 0)
        bar.layoutSubtreeIfNeeded()
        XCTAssertTrue(bar.showsActiveLine)
        XCTAssertTrue(bar.showsActiveFace)

        bar.showsActiveLine = false
        XCTAssertFalse(bar.isActiveLineVisibleForTesting(at: 0))

        bar.showsActiveFace = false
        XCTAssertEqual(bar.tabFaceColorForTesting(at: 0), NSColor(cgColor: Theme.tabBarBg.cgColor))
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

    func testDetachingTransfersDocumentOwnershipToManagedKeyWindow() {
        _ = NSApplication.shared
        let coordinator = AppCoordinator()
        let source = coordinator.ensureWindowControllerReady(restoreSession: false)
        source.prepareUITestDocument(content: "detached content", selections: [])
        let document = source.macroEditor.document

        coordinator.detachCurrentTab()

        XCTAssertEqual(coordinator.managedWindowCountForTesting, 2)
        let target = try! XCTUnwrap(coordinator.lastDetachedWindowControllerForTesting)
        XCTAssertTrue(target.macroEditor.document === document)
        XCTAssertEqual(target.macroEditor.textView.string, "detached content")
        XCTAssertEqual(source.tabCountForTesting, 1)
        NSApp.windows.filter { $0.windowController is MainWindowController }.forEach { $0.close() }
    }

    func testCrossDocumentScrollLinkPropagatesWithoutFeedback() {
        _ = NSApplication.shared
        let coordinator = AppCoordinator()
        let source = coordinator.ensureWindowControllerReady(restoreSession: false)
        source.prepareUITestDocument(content: String(repeating: "line\n", count: 500), selections: [])
        coordinator.detachCurrentTab()
        let target = try! XCTUnwrap(coordinator.lastDetachedWindowControllerForTesting)
        coordinator.toggleCrossDocumentScrollLink()

        source.onCrossDocumentScroll?(NSPoint(x: 0, y: 120))

        XCTAssertTrue(coordinator.crossDocumentScrollLinkEnabled)
        XCTAssertEqual(target.lastCrossDocumentScrollRequestForTesting, NSPoint(x: 0, y: 120))
        NSApp.windows.filter { $0.windowController is MainWindowController }.forEach { $0.close() }
    }
}
