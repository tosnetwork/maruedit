import AppKit
import XCTest
import MaruEditCore
@preconcurrency @testable import MaruEditApp


@preconcurrency @MainActor
final class ExternalCommandControllerTests: XCTestCase {
    func testSelectionInputReplacesEverySelectionAndClipboardOutput() async throws {
        let coordinator = makeCoordinator(content: "one two one", selections: [
            NSRange(location: 0, length: 3), NSRange(location: 8, length: 3)])
        let pasteboard = NSPasteboard(name: .init("ExternalCommandControllerTests"))
        let controller = ExternalCommandController(coordinator: coordinator, pasteboard: pasteboard)
        let replace = expectation(description: "replace selections")
        controller.didFinish = { result in
            if case .failure(let error) = result { XCTFail("\(error)") }
            replace.fulfill()
        }
        controller.run(python(
            id: "upper", script: "import sys; print(sys.stdin.read().upper(), end='')",
            input: .selection, output: .replaceSelection))
        await fulfillment(of: [replace], timeout: 3)
        XCTAssertEqual(coordinator.ensureWindowControllerReady().macroEditor.textView.string,
                       "ONE two ONE")

        let clipboard = expectation(description: "clipboard")
        controller.didFinish = { _ in clipboard.fulfill() }
        controller.run(python(
            id: "clipboard", script: "import sys; print(sys.stdin.read() + '!', end='')",
            input: .currentDocument, output: .clipboard))
        await fulfillment(of: [clipboard], timeout: 3)
        XCTAssertEqual(pasteboard.string(forType: .string), "ONE two ONE!")
    }

    func testNewDocumentAndStreamingOutputPane() async {
        let coordinator = makeCoordinator(content: "original")
        let controller = ExternalCommandController(coordinator: coordinator)
        let newDocument = expectation(description: "new document")
        controller.didFinish = { _ in newDocument.fulfill() }
        controller.run(python(id: "new", script: "print('generated', end='')", output: .newDocument))
        await fulfillment(of: [newDocument], timeout: 3)
        XCTAssertEqual(coordinator.ensureWindowControllerReady().macroEditor.textView.string, "generated")

        let pane = expectation(description: "output pane")
        controller.didFinish = { _ in pane.fulfill() }
        controller.run(python(
            id: "pane", script: "import sys; print('out', flush=True); print('bad', file=sys.stderr, flush=True)",
            output: .outputPane))
        await fulfillment(of: [pane], timeout: 3)
        let output = coordinator.ensureWindowControllerReady().externalCommandOutputTextForTesting
        XCTAssertTrue(output.contains("out"))
        XCTAssertTrue(output.contains("[stderr] [error] bad"))
    }

    func testUnnamedDocumentWorkingDirectoryFailsExplicitly() async {
        let coordinator = makeCoordinator(content: "unsaved")
        let controller = ExternalCommandController(coordinator: coordinator)
        let failed = expectation(description: "unnamed failure")
        controller.didFinish = { result in
            guard case .failure(let error) = result else { return XCTFail("Expected failure") }
            XCTAssertEqual(error as? ExternalCommandControllerError,
                           .unnamedDocumentNeedsWorkingDirectory)
            failed.fulfill()
        }
        var config = python(id: "pwd", script: "import os; print(os.getcwd())")
        config.workingDirectory = .currentDocumentDirectory
        XCTAssertNil(controller.run(config))
        await fulfillment(of: [failed], timeout: 1)
        XCTAssertEqual(coordinator.ensureWindowControllerReady().macroEditor.textView.string, "unsaved")
    }

    private func python(id: String, script: String, input: ExternalCommandInput = .none,
                        output: ExternalCommandOutput = .outputPane) -> ExternalCommandConfiguration {
        ExternalCommandConfiguration(id: id, name: id, executable: "/usr/bin/python3",
                                     arguments: ["-c", script], input: input, output: output)
    }
    private func makeCoordinator(content: String, selections: [NSRange] = [NSRange(location: 0, length: 0)]) -> AppCoordinator {
        let suite = "ExternalCommandControllerTests.\(UUID().uuidString)"
        let coordinator = AppCoordinator(preferencesStore: PreferencesStore(
            defaults: UserDefaults(suiteName: suite)!))
        coordinator.prepareUITestDocument(content: content, selections: selections)
        return coordinator
    }
}
