import AppKit
import MaruEditCore

enum ExternalCommandControllerError: LocalizedError, Equatable {
    case unnamedDocumentNeedsWorkingDirectory
    case invalidWorkingDirectory(String)
    case activeDocumentChanged
    case processFailed(Int32)
    case cancelled
    var errorDescription: String? {
        switch self {
        case .unnamedDocumentNeedsWorkingDirectory:
            "This command uses the document directory, but the active document is unnamed or unsaved."
        case .invalidWorkingDirectory(let path): "Working directory is unavailable: \(path)"
        case .activeDocumentChanged: "The active document changed before command output was applied."
        case .processFailed(let status): "The external command exited with status \(status); document and clipboard output was not applied."
        case .cancelled: "The external command was cancelled."
        }
    }
}

final class ExternalCommandController: @unchecked Sendable {
    private let coordinator: AppCoordinator
    private let runner: ExternalCommandRunner
    private let pasteboard: NSPasteboard
    var didFinish: ((Result<ExternalCommandResult, Error>) -> Void)?

    init(coordinator: AppCoordinator, runner: ExternalCommandRunner = ExternalCommandRunner(),
         pasteboard: NSPasteboard = .general) {
        self.coordinator = coordinator; self.runner = runner; self.pasteboard = pasteboard
    }

    @discardableResult
    func run(_ configuration: ExternalCommandConfiguration) -> ExternalCommandCancellation? {
        let window = coordinator.ensureWindowControllerReady()
        let editor = window.macroEditor
        guard let document = editor.document else { return nil }
        let documentID = ObjectIdentifier(document)
        let input: Data
        switch configuration.input {
        case .none: input = Data()
        case .currentDocument: input = Data(editor.textView.string.utf8)
        case .selection:
            let ns = editor.textView.string as NSString
            let range = NSIntersectionRange(editor.selectionSet.primaryRange,
                                            NSRange(location: 0, length: ns.length))
            input = Data(ns.substring(with: range).utf8)
        }
        let workingDirectory: URL?
        switch configuration.workingDirectory {
        case .none: workingDirectory = nil
        case .currentDocumentDirectory:
            guard let url = document.fileURL else {
                finishFailure(ExternalCommandControllerError.unnamedDocumentNeedsWorkingDirectory)
                return nil
            }
            workingDirectory = url.deletingLastPathComponent()
        case .explicit:
            workingDirectory = configuration.workingDirectoryPath.map {
                URL(fileURLWithPath: $0, isDirectory: true)
            }
        }
        if let workingDirectory {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: workingDirectory.path, isDirectory: &isDirectory),
                  isDirectory.boolValue else {
                finishFailure(ExternalCommandControllerError.invalidWorkingDirectory(workingDirectory.path))
                return nil
            }
        }

        var token: ExternalCommandCancellation?
        token = runner.run(
            configuration: configuration, input: input, workingDirectoryURL: workingDirectory,
            onChunk: { [weak self] chunk in
                guard configuration.output == .outputPane else { return }
                DispatchQueue.main.async {
                    self?.coordinator.ensureWindowControllerReady().appendExternalCommandOutput(
                        chunk.data,
                        isError: chunk.stream == .standardError)
                }
            }, completion: { [weak self, weak editor] result in
                DispatchQueue.main.async {
                    guard let self else { return }
                    switch result {
                    case .failure(let error): self.finishFailure(error)
                    case .success(let value):
                        if configuration.output != .outputPane {
                            if value.wasCancelled { self.finishFailure(ExternalCommandControllerError.cancelled); return }
                            guard value.terminationStatus == 0 else {
                                self.finishFailure(ExternalCommandControllerError.processFailed(value.terminationStatus)); return
                            }
                        }
                        if configuration.output == .replaceSelection {
                            guard let editor, let current = editor.document,
                                  ObjectIdentifier(current) == documentID else {
                                self.finishFailure(ExternalCommandControllerError.activeDocumentChanged); return
                            }
                        }
                        guard let editor else { return }
                        self.apply(value.standardOutput, configuration: configuration,
                                   editor: editor, window: window)
                        if configuration.output == .outputPane {
                            window.finishExternalCommandOutput(
                                status: value.terminationStatus, cancelled: value.wasCancelled)
                        }
                        self.didFinish?(.success(value))
                    }
                }
            })
        if configuration.output == .outputPane {
            window.beginExternalCommandOutput(
                name: configuration.name, workingDirectory: workingDirectory, cancellation: token)
        }
        return token
    }

    private func apply(_ data: Data, configuration: ExternalCommandConfiguration,
                       editor: EditorViewController, window: MainWindowController) {
        let text = String(decoding: data, as: UTF8.self)
        switch configuration.output {
        case .outputPane: break
        case .replaceSelection:
            editor.batchReplace(editor.selectionSet.ranges, with: text)
        case .clipboard:
            pasteboard.clearContents(); pasteboard.setString(text, forType: .string)
        case .newDocument:
            window.newDocument()
            let newEditor = window.macroEditor
            newEditor.batchReplace([NSRange(location: 0, length: 0)], with: text)
        }
    }

    private func finishFailure(_ error: Error) {
        didFinish?(.failure(error))
    }
}
