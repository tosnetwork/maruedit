import AppKit
import XCTest
import MaruEditCore
@testable import MaruEditApp

final class MacroCommandBridgeTests: XCTestCase {
    func testSelectionTransformClipboardPromptMessageAndSingleUndo() throws {
        let coordinator = AppCoordinator(preferencesStore: isolatedPreferences())
        coordinator.prepareUITestDocument(
            content: "one two one", selections: [
                NSRange(location: 0, length: 3), NSRange(location: 8, length: 3)])
        let editor = coordinator.ensureWindowControllerReady(restoreSession: false).macroEditor
        let pasteboard = NSPasteboard(name: .init("MacroCommandBridgeTests"))
        pasteboard.clearContents()
        pasteboard.setString("seed", forType: .string)
        var messages: [String] = []
        var prompts: [(String, String)] = []
        let host = coordinator.makeMacroHost(
            pasteboard: pasteboard,
            message: { messages.append($0) },
            prompt: { message, initial in prompts.append((message, initial)); return "X" })

        let source = """
        const ranges = maru.editor.getSelections();
        const original = maru.document.getText();
        maru.undo.group('Sample', () => {
          maru.editor.replaceSelections(maru.ui.prompt('Replace', 'value'));
          maru.editor.setSelections([{location: 1, length: 3}]);
          maru.editor.replaceSelections('MID');
        });
        maru.clipboard.writeText(original.substring(ranges[0].location,
          ranges[0].location + ranges[0].length));
        maru.ui.message('finished');
        "ok";
        """
        XCTAssertEqual(try MacroEngine().execute(source, host: host).get().value, .string("ok"))
        XCTAssertEqual(editor.textView.string, "XMIDo X")
        XCTAssertEqual(pasteboard.string(forType: .string), "one")
        XCTAssertEqual(messages, ["finished"])
        XCTAssertEqual(prompts.map { "\($0.0):\($0.1)" }, ["Replace:value"])
        XCTAssertTrue(editor.textView.undoManager?.canUndo == true)
        editor.textView.undoManager?.undo()
        XCTAssertEqual(editor.textView.string, "one two one")
    }

    func testCommandsRunThroughRegistryAndInvalidRangesAreRejected() throws {
        let coordinator = AppCoordinator(preferencesStore: isolatedPreferences())
        coordinator.prepareUITestDocument(content: "abc", selections: [NSRange(location: 0, length: 0)])
        let host = coordinator.makeMacroHost(
            pasteboard: NSPasteboard(name: .init("MacroCommandBridgeTests.commands")),
            message: { _ in }, prompt: { _, _ in nil })
        let result = try MacroEngine().execute("""
          const invalidRejected = !maru.editor.setSelections([{location: 99, length: 1}]);
          maru.commands.run('view.toggleWrap').then(ran => ran && invalidRejected);
          """, host: host).get()
        XCTAssertEqual(result.value, .boolean(true))
    }

    private func isolatedPreferences() -> PreferencesStore {
        let suite = "MacroCommandBridgeTests.\(UUID().uuidString)"
        return PreferencesStore(defaults: UserDefaults(suiteName: suite)!)
    }
}
