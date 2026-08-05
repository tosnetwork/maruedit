import AppKit
import MaruEditCore

/// Converts the active AppKit editor into the value-only `MacroHost` surface.
/// Every closure enters the main thread before touching UI state.
/// The bridge itself is passed into JavaScriptCore callbacks. Every access to
/// its AppKit-owned references is synchronously confined to the main queue by
/// `onMain`; the references are never dereferenced on the macro engine queue.
final class MacroCommandBridge: @unchecked Sendable {
    private unowned let coordinator: AppCoordinator
    private unowned let editor: EditorViewController
    private let pasteboard: NSPasteboard
    private let permissions: Set<MacroPermission>
    private let messageHandler: (String) -> Void
    private let promptHandler: (String, String) -> String?

    @MainActor
    init(
        coordinator: AppCoordinator,
        editor: EditorViewController,
        permissions: Set<MacroPermission> = [.currentDocument, .clipboard],
        pasteboard: NSPasteboard = .general,
        message: ((String) -> Void)? = nil,
        prompt: ((String, String) -> String?)? = nil
    ) {
        self.coordinator = coordinator
        self.editor = editor
        self.permissions = permissions
        self.pasteboard = pasteboard
        messageHandler = message ?? { coordinator.showStatusMessage($0, duration: 2.5) }
        promptHandler = prompt ?? { message, initial in
            let alert = NSAlert()
            alert.messageText = message
            alert.addButton(withTitle: AppLocalization.string(.commonOK))
            alert.addButton(withTitle: AppLocalization.string(.commonCancel))
            let field = NSTextField(string: initial)
            field.frame.size = NSSize(width: 320, height: 24)
            alert.accessoryView = field
            return alert.runModal() == .alertFirstButtonReturn ? field.stringValue : nil
        }
    }

    var host: MacroHost {
        MacroHost(
            allowedPermissions: permissions,
            runCommand: { [self] raw in onMain {
                if raw.hasPrefix("external."), !permissions.contains(.externalCommands) {
                    return false
                }
                return coordinator.commandRegistry.execute(
                    CommandID(raw), context: CommandContext(coordinator: coordinator))
            } },
            documentText: { [self] in onMain { editor.textView.string } },
            setDocumentText: { [self] text in onMain {
                let length = (editor.textView.string as NSString).length
                editor.batchReplace([NSRange(location: 0, length: length)], with: text)
            } },
            selectionsJSON: { [self] in onMain {
                let values = editor.selectionSet.ranges.map {
                    ["location": $0.location, "length": $0.length]
                }
                let data = try! JSONSerialization.data(withJSONObject: values, options: [.sortedKeys])
                return String(decoding: data, as: UTF8.self)
            } },
            setSelectionsJSON: { [self] json in onMain {
                guard let data = json.data(using: .utf8),
                      let values = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
                else { return false }
                let length = (editor.textView.string as NSString).length
                let ranges = values.compactMap { value -> NSRange? in
                    guard let location = value["location"] as? Int,
                          let rangeLength = value["length"] as? Int,
                          location >= 0, rangeLength >= 0, location + rangeLength <= length
                    else { return nil }
                    return NSRange(location: location, length: rangeLength)
                }
                guard ranges.count == values.count, !ranges.isEmpty else { return false }
                editor.setSelections(ranges, primaryRange: ranges.first)
                return true
            } },
            replaceSelections: { [self] text in onMain {
                editor.batchReplace(editor.selectionSet.ranges, with: text)
            } },
            readClipboard: { [self] in onMain {
                pasteboard.string(forType: .string) ?? ""
            } },
            writeClipboard: { [self] text in onMain {
                pasteboard.clearContents()
                pasteboard.setString(text, forType: .string)
            } },
            showMessage: { [self] text in onMain { messageHandler(text) } },
            prompt: { [self] text, initial in onMain { promptHandler(text, initial) } },
            beginUndoGroup: { [self] _ in onMain {
                editor.textView.undoManager?.beginUndoGrouping()
            } },
            endUndoGroup: { [self] in onMain {
                editor.textView.undoManager?.endUndoGrouping()
                editor.textView.undoManager?.setActionName("Macro")
            } }
        )
    }

    private func onMain<T: Sendable>(_ work: @Sendable @MainActor () -> T) -> T {
        if Thread.isMainThread {
            return MainActor.assumeIsolated { work() }
        }
        return DispatchQueue.main.sync {
            MainActor.assumeIsolated { work() }
        }
    }
}
