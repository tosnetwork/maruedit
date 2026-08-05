import AppKit
import MaruEditCore
import XCTest
@preconcurrency @testable import MaruEditApp

@MainActor
final class ConversionDialogTests: XCTestCase {
    private var windows: [NSWindow] = []

    override func tearDown() {
        windows.removeAll()
        super.tearDown()
    }
    func testDialogPersistsAndAppliesOrderedCustomPreset() {
        let suite = "ConversionDialogTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = TextConversionPresetStore(defaults: defaults)
        var applied: [TextConversionStep] = []
        let controller = ConversionDialogWindowController(store: store) { applied = $0 }
        let steps = [
            TextConversionStep(moduleID: "replace.literal", parameters: ["search": "a", "replacement": "b"]),
            TextConversionStep(moduleID: "case.uppercase"),
        ]
        controller.setStepsForTesting(steps)
        controller.savePresetForTesting(name: "Project Cleanup")
        controller.applyForTesting()
        XCTAssertEqual(applied, steps)
        XCTAssertEqual(store.load().first?.name, "Project Cleanup")
        XCTAssertEqual(controller.customPresetsForTesting.first?.steps, steps)
    }

    func testEditorAppliesPipelineToEverySelectionAsOneOperation() throws {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 240),
            styleMask: [.titled], backing: .buffered, defer: true)
        windows.append(window)
        let editor = EditorViewController(); window.contentView = editor.view
        editor.document = Document(content: "abc def abc")
        editor.textView.undoManager?.removeAllActions()
        editor.setSelections([
            NSRange(location: 0, length: 3), NSRange(location: 8, length: 3),
        ])
        try editor.applyConversionPipeline([
            .init(moduleID: "replace.literal", parameters: ["search": "a", "replacement": "x"]),
            .init(moduleID: "case.uppercase"),
        ])
        XCTAssertEqual(editor.textView.string, "XBC def XBC")
        editor.textView.undoManager?.undo()
        XCTAssertEqual(editor.textView.string, "abc def abc")
    }

    func testConvertMenuExposesPipelineBeforeDirectConversions() {
        let app = AppDelegate(); app.buildMenu()
        let menu = NSApp.mainMenu?.items.compactMap(\.submenu).first { $0.title == "Convert" }
        XCTAssertEqual(menu?.items.first?.title, "Conversion Pipeline…")
    }
}
