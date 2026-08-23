import AppKit
import XCTest
@preconcurrency @testable import MaruEditApp

/// Covers the promise the tab bar's batch-close items make: one decision for
/// the whole batch instead of one save prompt per tab.
@MainActor
final class TabBatchCloseTests: XCTestCase {
    private var directory: URL!

    override func setUp() {
        super.setUp()
        UserDefaults.standard.set(AppLanguage.english.rawValue, forKey: AppLocalization.defaultsKey)
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MaruEdit-batch-close-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: AppLocalization.defaultsKey)
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    /// Opens `names.count` files, each edited so it is modified on arrival.
    private func controllerWithModifiedFiles(_ names: [String]) throws -> (MainWindowController, [URL]) {
        let controller = MainWindowController()
        var urls: [URL] = []
        for name in names {
            let url = directory.appendingPathComponent(name)
            try "old".write(to: url, atomically: true, encoding: .utf8)
            controller.openFile(url)
            controller.macroEditor.batchReplace([NSRange(location: 0, length: 3)], with: "new")
            XCTAssertTrue(controller.macroEditor.document?.isModified == true)
            urls.append(url)
        }
        return (controller, urls)
    }

    private func contents(of urls: [URL]) throws -> [String] {
        try urls.map { try String(contentsOf: $0, encoding: .utf8) }
    }

    private func performMenuItem(_ title: String, in controller: MainWindowController) throws {
        let menu = controller.tabBarForTesting.contextMenu(forTabAt: nil)
        let index = try XCTUnwrap(
            menu.items.firstIndex(where: { $0.title == title }),
            "the tab context menu is missing \"\(title)\"")
        XCTAssertTrue(menu.items[index].isEnabled, "\"\(title)\" must be usable")
        menu.performActionForItem(at: index)
    }

    // MARK: - The reported problem

    func testClosingManyModifiedTabsAsksOnceInsteadOfOncePerTab() throws {
        let (controller, urls) = try controllerWithModifiedFiles(["a.txt", "b.txt", "c.txt"])
        var prompts: [[String]] = []
        controller.presentBatchCloseChoice = { documents in
            prompts.append(documents.map(\.localizedDisplayName))
            return .saveAll
        }

        controller.closeTabs(.all)

        XCTAssertEqual(prompts.count, 1, "one batch, one question")
        XCTAssertEqual(prompts.first?.sorted(), ["a.txt", "b.txt", "c.txt"])
        XCTAssertEqual(try contents(of: urls), ["new", "new", "new"])
        XCTAssertEqual(controller.tabCountForTesting, 1)
    }

    func testCloseOtherTabsAlsoAsksOnceAndKeepsTheClickedTabUntouched() throws {
        let (controller, urls) = try controllerWithModifiedFiles(["a.txt", "b.txt", "c.txt"])
        var promptCount = 0
        controller.presentBatchCloseChoice = { _ in promptCount += 1; return .saveAll }

        // Tab 0 is the pristine Untitled tab, so 1...3 are the opened files
        // and tab 2 is b.txt.
        controller.tabBarDidRequestClose(.others, at: 2)

        XCTAssertEqual(promptCount, 1, "three tabs closed, one question")
        XCTAssertEqual(controller.tabCountForTesting, 1)
        XCTAssertEqual(controller.currentDocumentTextForTesting, "new")
        XCTAssertEqual(
            try contents(of: urls), ["new", "old", "new"],
            "the kept tab must not be saved along with the batch")
        XCTAssertTrue(controller.macroEditor.document?.isModified == true)
    }

    func testSingleModifiedTabStillUsesTheOrdinaryPerDocumentPrompt() throws {
        let (controller, urls) = try controllerWithModifiedFiles(["a.txt", "b.txt"])
        var batchPrompts = 0
        var perDocumentPrompts: [String] = []
        controller.presentBatchCloseChoice = { _ in batchPrompts += 1; return .saveAll }
        controller.presentSingleCloseChoice = { document in
            perDocumentPrompts.append(document.localizedDisplayName)
            return .alertFirstButtonReturn  // Save
        }

        // Closing tabs left of b.txt covers the Untitled tab and a.txt; only
        // a.txt is unsaved, which is not enough to be worth a batch question.
        controller.tabBarDidRequestClose(.left, at: 2)

        XCTAssertEqual(batchPrompts, 0)
        XCTAssertEqual(perDocumentPrompts, ["a.txt"])
        XCTAssertEqual(try contents(of: urls), ["new", "old"])
    }

    // MARK: - The new menu items, driven through the real menu

    func testSaveAllAndCloseAllMenuItemWritesEveryFileAndClosesEveryTab() throws {
        let (controller, urls) = try controllerWithModifiedFiles(["a.txt", "b.txt"])
        controller.presentBatchCloseChoice = { _ in
            XCTFail("an explicit Save All choice must not ask again"); return nil
        }

        try performMenuItem("Save All and Close All Tabs", in: controller)

        XCTAssertEqual(try contents(of: urls), ["new", "new"])
        XCTAssertEqual(controller.tabCountForTesting, 1)
    }

    func testCloseAllWithoutSavingMenuItemConfirmsOnceAndDiscardsEveryChange() throws {
        let (controller, urls) = try controllerWithModifiedFiles(["a.txt", "b.txt"])
        var confirmations: [[String]] = []
        controller.presentDiscardConfirmation = { documents in
            confirmations.append(documents.map(\.localizedDisplayName))
            return true
        }

        try performMenuItem("Close All Tabs Without Saving", in: controller)

        XCTAssertEqual(confirmations.count, 1)
        XCTAssertEqual(confirmations.first?.sorted(), ["a.txt", "b.txt"])
        XCTAssertEqual(try contents(of: urls), ["old", "old"], "nothing may be written")
        XCTAssertEqual(controller.tabCountForTesting, 1)
    }

    func testDecliningTheDiscardConfirmationLeavesEveryTabOpenAndUnsaved() throws {
        let (controller, urls) = try controllerWithModifiedFiles(["a.txt", "b.txt"])
        let openTabs = controller.tabCountForTesting
        controller.presentDiscardConfirmation = { _ in false }

        try performMenuItem("Close All Tabs Without Saving", in: controller)

        XCTAssertEqual(controller.tabCountForTesting, openTabs)
        XCTAssertEqual(try contents(of: urls), ["old", "old"])
    }

    func testCancellingTheBatchQuestionLeavesEveryTabOpenAndUnsaved() throws {
        let (controller, urls) = try controllerWithModifiedFiles(["a.txt", "b.txt"])
        let openTabs = controller.tabCountForTesting
        controller.presentBatchCloseChoice = { _ in nil }

        try performMenuItem("Close All Tabs", in: controller)

        XCTAssertEqual(controller.tabCountForTesting, openTabs)
        XCTAssertEqual(try contents(of: urls), ["old", "old"])
    }

    func testAnsweringDontSaveOnTheBatchQuestionClosesWithoutWriting() throws {
        let (controller, urls) = try controllerWithModifiedFiles(["a.txt", "b.txt"])
        controller.presentBatchCloseChoice = { _ in .discardAll }
        controller.presentDiscardConfirmation = { _ in
            XCTFail("the batch question already answered this"); return false
        }

        try performMenuItem("Close All Tabs", in: controller)

        XCTAssertEqual(try contents(of: urls), ["old", "old"])
        XCTAssertEqual(controller.tabCountForTesting, 1)
    }

    func testClosingEveryTabClearsTheClosedDocumentFromTheWindowTitle() throws {
        let (controller, _) = try controllerWithModifiedFiles(["a.txt", "b.txt"])
        XCTAssertEqual(controller.window?.title.contains("b.txt"), true)
        controller.presentDiscardConfirmation = { _ in true }

        try performMenuItem("Close All Tabs Without Saving", in: controller)

        XCTAssertEqual(
            controller.window?.title.contains("b.txt"), false,
            "the title must not keep naming a document that is no longer open")
    }

    func testUnmodifiedTabsCloseWithNoQuestionAtAll() throws {
        let controller = MainWindowController()
        for name in ["a.txt", "b.txt"] {
            let url = directory.appendingPathComponent(name)
            try "old".write(to: url, atomically: true, encoding: .utf8)
            controller.openFile(url)
        }
        controller.presentBatchCloseChoice = { _ in XCTFail("nothing to save"); return nil }
        controller.presentDiscardConfirmation = { _ in XCTFail("nothing to discard"); return false }

        try performMenuItem("Close All Tabs", in: controller)

        XCTAssertEqual(controller.tabCountForTesting, 1)
    }
}
