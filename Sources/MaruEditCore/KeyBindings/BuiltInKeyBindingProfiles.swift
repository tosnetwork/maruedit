import Foundation

public extension KeyBindingProfile {
    static let macOSStandard = KeyBindingProfile(name: "macOS Standard", bindings: bindings([
        ("cmd+n", "file.new"), ("cmd+o", "file.open"), ("cmd+shift+o", "file.openFolder"),
        ("cmd+s", "file.save"), ("cmd+shift+s", "file.saveAs"), ("cmd+w", "file.closeTab"),
        ("cmd+f", "search.find"), ("cmd+opt+f", "search.replace"),
        ("cmd+g", "search.findNext"), ("cmd+shift+g", "search.findPrevious"),
        ("cmd+l", "search.goToLine"), ("cmd+p", "search.quickOpen"),
        ("cmd+shift+f", "search.grep"), ("cmd+b", "view.toggleSidebar"),
        ("cmd+opt+up", "edit.addCursorAbove"), ("cmd+opt+down", "edit.addCursorBelow"),
        ("cmd+d", "edit.selectNextOccurrence"), ("cmd+shift+l", "edit.selectAllOccurrences"),
        ("cmd+u", "edit.undoLastAddedCursor"), ("opt+up", "edit.moveLineUp"),
        ("opt+down", "edit.moveLineDown"), ("cmd+shift+k", "edit.deleteLine"),
    ]))

    static let maruClassic = KeyBindingProfile(name: "Maru Classic", bindings: bindings([
        ("cmd+n", "file.new"), ("cmd+o", "file.open"), ("cmd+s", "file.save"),
        ("cmd+w", "file.closeTab"), ("ctrl+f", "search.find"),
        ("f3", "search.findNext"), ("shift+f3", "search.findPrevious"),
        ("ctrl+g", "search.goToLine"), ("ctrl+shift+f", "search.grep"),
        ("ctrl+d", "edit.deleteLine"), ("ctrl+j", "edit.joinLines"),
        ("ctrl+shift+d", "edit.duplicateLine"), ("opt+up", "edit.moveLineUp"),
        ("opt+down", "edit.moveLineDown"), ("ctrl+b", "navigate.toggleBookmark"),
        ("f2", "navigate.nextBookmark"), ("shift+f2", "navigate.previousBookmark"),
    ]))

    private static func bindings(_ values: [(String, String)]) -> [KeyBinding] {
        values.map { notation, command in
            KeyBinding(keys: [KeyGesture(notation)!], command: CommandID(command))
        }
    }
}
