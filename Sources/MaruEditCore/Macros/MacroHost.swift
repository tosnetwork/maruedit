import Foundation

/// Narrow value/function bridge supplied by the application for one run.
/// JavaScriptCore never receives the objects captured by these closures.
public struct MacroHost: @unchecked Sendable {
    public var runCommand: (String) -> Bool
    public var documentText: () -> String
    public var setDocumentText: (String) -> Void
    public var selectionsJSON: () -> String
    public var setSelectionsJSON: (String) -> Bool
    public var replaceSelections: (String) -> Void
    public var readClipboard: () -> String
    public var writeClipboard: (String) -> Void
    public var showMessage: (String) -> Void
    public var prompt: (String, String) -> String?
    public var beginUndoGroup: (String) -> Void
    public var endUndoGroup: () -> Void

    public init(
        runCommand: @escaping (String) -> Bool,
        documentText: @escaping () -> String,
        setDocumentText: @escaping (String) -> Void,
        selectionsJSON: @escaping () -> String,
        setSelectionsJSON: @escaping (String) -> Bool,
        replaceSelections: @escaping (String) -> Void,
        readClipboard: @escaping () -> String,
        writeClipboard: @escaping (String) -> Void,
        showMessage: @escaping (String) -> Void,
        prompt: @escaping (String, String) -> String?,
        beginUndoGroup: @escaping (String) -> Void,
        endUndoGroup: @escaping () -> Void
    ) {
        self.runCommand = runCommand
        self.documentText = documentText
        self.setDocumentText = setDocumentText
        self.selectionsJSON = selectionsJSON
        self.setSelectionsJSON = setSelectionsJSON
        self.replaceSelections = replaceSelections
        self.readClipboard = readClipboard
        self.writeClipboard = writeClipboard
        self.showMessage = showMessage
        self.prompt = prompt
        self.beginUndoGroup = beginUndoGroup
        self.endUndoGroup = endUndoGroup
    }
}
