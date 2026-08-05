import AppKit
import XCTest
@preconcurrency @testable import MaruEditApp

@MainActor
final class DocumentationScreenshotTests: XCTestCase {
    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    override func setUp() {
        super.setUp()
        UserDefaults.standard.set(AppLanguage.english.rawValue, forKey: AppLocalization.defaultsKey)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: AppLocalization.defaultsKey)
        super.tearDown()
    }

    func testREADMEFeatureScreenshotsRenderCurrentUI() throws {
        let controller = makeController()
        let main = try capture(try XCTUnwrap(controller.window?.contentView))

        controller.showFind(showingReplace: true)
        let findBar = try XCTUnwrap(descendants(of: controller.window!.contentView!).first { $0 is FindBarView } as? FindBarView)
        findBar.searchField.stringValue = "MaruEdit"
        findBar.replaceField.stringValue = "Maru Classic"
        findBar.toggleCase()
        let find = try capture(controller.window!.contentView!)

        let quickOpen = QuickOpenPanel(relativeTo: controller.window!)
        quickOpen.loadFiles(from: repositoryRoot)
        quickOpen.activate()
        if let query = descendants(of: quickOpen.contentView!).compactMap({ $0 as? NSTextField })
            .first(where: { $0.isEditable }) {
            query.stringValue = "swift"
            quickOpen.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: query))
        }
        let quick = try capture(try XCTUnwrap(quickOpen.contentView))

        XCTAssertGreaterThan(main.count, 20_000)
        XCTAssertGreaterThan(find.count, 20_000)
        XCTAssertGreaterThan(quick.count, 10_000)

        if ProcessInfo.processInfo.environment["UPDATE_DOCUMENTATION_SCREENSHOTS"] == "1" {
            let directory = repositoryRoot.appendingPathComponent("screenshots", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try main.write(to: directory.appendingPathComponent("main-editor.png"), options: .atomic)
            try find.write(to: directory.appendingPathComponent("find-replace.png"), options: .atomic)
            try quick.write(to: directory.appendingPathComponent("quick-open.png"), options: .atomic)
        }
    }

    private func makeController() -> MainWindowController {
        let controller = MainWindowController()
        controller.applyPreferences(.defaults)
        controller.window?.appearance = NSAppearance(named: .aqua)
        controller.window?.setContentSize(NSSize(width: 1_200, height: 760))
        controller.setClassicToolbarLayoutForTesting([
            "file.new", "file.open", "file.save", "file.print", "-",
            "responder.undo", "responder.redo", "-",
            "responder.cut", "responder.copy", "responder.paste", "-",
            "search.find", "search.replace", "search.findNext", "search.findPrevious", "search.grep", "-",
            "bookmark.toggle", "navigate.nextBookmark", "search.goToLine", "-",
            "macro.run", "view.toggleSidebar", "app.settings", "app.help",
        ])
        controller.setClassicToolbarDisplayModeForTesting(.iconOnly)
        controller.setClassicToolbarIconSizeForTesting(.medium)
        controller.setClassicToolbarSearchVisibleForTesting(true)
        controller.setFunctionKeyStripMergedForTesting(true)
        controller.setStatusBarFieldsForTesting([.encoding, .inputMode])
        controller.prepareUITestDocument(
            content: "# MaruEdit\n\nA native, keyboard-focused editor for macOS.\n",
            selections: [NSRange(location: 2, length: 8)])
        controller.newDocument()
        controller.prepareUITestDocument(
            content: """
            // MaruEdit — native editing on macOS
            import Foundation

            struct SearchResult {
                let file: URL
                let line: Int
                let preview: String
            }

            func describe(_ result: SearchResult) -> String {
                "\\(result.file.lastPathComponent):\\(result.line)  \\(result.preview)"
            }

            let features = [
                "Find and Replace",
                "Folder Grep",
                "BOX selection and multiple cursors",
                "JavaScript macros and external commands",
            ]

            // Unicode text stays readable and editable: 日本語 / English
            features.forEach { print($0) }
            """,
            selections: [NSRange(location: 150, length: 12)])
        return controller
    }

    private func capture(_ view: NSView) throws -> Data {
        view.layoutSubtreeIfNeeded()
        view.displayIfNeeded()
        let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        return try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
    }

    private func descendants(of root: NSView) -> [NSView] {
        root.subviews.flatMap { [$0] + descendants(of: $0) }
    }
}
