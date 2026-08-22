// EditorViewController+Shortcuts.swift
// STAGING — New keyboard shortcuts for the editor.
//
//   Option+Up/Down     Move current line (or selected lines) up / down
//   Cmd+Shift+K        Delete the current line
//   Cmd+Shift+L        Select all occurrences → enters multi-edit mode
//                      (type to replace all at once, Backspace works, Escape exits)
//
// Activation: call  EditorShortcuts.install()  once at app launch,
// e.g. at the top of AppDelegate.applicationDidFinishLaunching(_:).

import AppKit
import MaruEditCore

// MARK: - Global event monitors

@MainActor
enum EditorShortcuts {
    private static var installed = false

    // Explicitly retained rather than discarding addLocalMonitorForEvents'
    // return value: `leaks` correctly flags an unretained local monitor's
    // block as unreachable memory. These two are intentionally kept alive
    // for the whole app lifetime (never removed — there's no "uninstall"
    // concept for app-wide shortcut handling today), but that should be
    // this enum's explicit choice, not an accident of the system happening
    // to keep the block alive anyway.
    private static var keyMonitor: Any?
    private static var mouseMonitor: Any?
    private static var keyBindings: KeyBindingManager?
    private static var executeCommand: ((CommandID) -> Bool)?
    private static var showStatus: ((String, TimeInterval) -> Void)?
    private static let chordMachine = ChordStateMachine(timeout: 1.5)
    private static var chordTimeoutWorkItem: DispatchWorkItem?

    static func install(
        keyBindings: KeyBindingManager,
        execute: @escaping (CommandID) -> Bool,
        showStatus: @escaping (String, TimeInterval) -> Void
    ) {
        guard !installed else { return }
        installed = true
        self.keyBindings = keyBindings
        executeCommand = execute
        self.showStatus = showStatus

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard let editor = activeEditor(for: event) else { return event }

            if editor.textView.hasMarkedText() || editor.hasMarkedTextComposition {
                if chordMachine.pendingPrefix != nil {
                    chordMachine.cancel()
                    chordTimeoutWorkItem?.cancel()
                }
            } else if let gesture = KeyGesture(event: event) {
                switch chordMachine.handle(gesture, bindings: keyBindings.bindings) {
                case .command(let command):
                    chordTimeoutWorkItem?.cancel()
                    EditorShortcuts.showStatus?("", 0)
                    if executeCommand?(command) == true { return nil }
                case .waiting(let prefix):
                    EditorShortcuts.showStatus?("Chord: \(prefix.description) …", chordMachine.timeout)
                    chordTimeoutWorkItem?.cancel()
                    let item = DispatchWorkItem {
                        if chordMachine.expire() { EditorShortcuts.showStatus?("Chord timed out", 1) }
                    }
                    chordTimeoutWorkItem = item
                    DispatchQueue.main.asyncAfter(deadline: .now() + chordMachine.timeout, execute: item)
                    return nil
                case .cancelled:
                    chordTimeoutWorkItem?.cancel()
                    EditorShortcuts.showStatus?("Chord cancelled", 1)
                    return nil
                case .invalid:
                    chordTimeoutWorkItem?.cancel()
                    if gesture.modifiers.isEmpty, gesture.key.count == 1 {
                        // Never eat ordinary text merely because a chord was
                        // pending; this is also the event that may begin IME
                        // composition before AppKit exposes marked text.
                        EditorShortcuts.showStatus?("Chord cancelled", 1)
                        break
                    }
                    EditorShortcuts.showStatus?("Unknown chord", 1)
                    return nil
                case .timedOut:
                    chordTimeoutWorkItem?.cancel()
                    EditorShortcuts.showStatus?("Chord timed out", 1)
                    return nil
                case .ignored: break
                }
            }

            if editor.isMultiEditActive {
                return editor.handleMultiEditKey(event) ? nil : event
            }
            return editor.handleShortcutEvent(event) ? nil : event
        }

        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { event in
            // Scoped to the editor that owns the clicked window, not every
            // open editor — a click in one window must never affect
            // multi-edit state in another (ROADMAP.md M1-06).
            activeEditor(for: event)?.isMultiEditActive = false
            return event
        }
    }

    fileprivate static func activeEditor(for event: NSEvent) -> EditorViewController? {
        guard let window = event.window,
              let tv = window.firstResponder as? NSTextView else { return nil }
        var next: NSResponder? = tv.nextResponder
        while let r = next {
            if let vc = r as? EditorViewController, vc.textView === tv { return vc }
            next = r.nextResponder
        }
        return nil
    }
}

// MARK: - Shortcut dispatch

extension EditorViewController {

    fileprivate func handleShortcutEvent(_ event: NSEvent) -> Bool {
        guard let gesture = KeyGesture(event: event) else { return false }
        switch (gesture.modifiers, gesture.key) {
        case ([], "tab"): if indentSelectedLines() { return true }; return false
        case ([.shift], "tab"): unindentSelectedLines(); return true
        default:                        return false
        }
    }
}

// MARK: - Option+Up / Option+Down — move line

extension EditorViewController {

    fileprivate func moveLineUp() {
        let ns = textView.string as NSString
        guard ns.length > 0 else { return }

        let sel      = textView.selectedRange()
        let curRange = ns.lineRange(for: sel)
        guard curRange.location > 0 else { return }

        let aboveRange = ns.lineRange(for: NSRange(location: curRange.location - 1, length: 0))

        var curText   = ns.substring(with: curRange)
        var aboveText = ns.substring(with: aboveRange)

        if !curText.hasSuffix("\n") && aboveText.hasSuffix("\n") {
            curText   += "\n"
            aboveText  = String(aboveText.dropLast())
        }

        let fullRange = NSRange(location: aboveRange.location,
                                length: NSMaxRange(curRange) - aboveRange.location)
        replaceText(in: fullRange, with: curText + aboveText)

        let newStart = aboveRange.location + (sel.location - curRange.location)
        textView.setSelectedRange(NSRange(location: newStart, length: sel.length))
    }

    fileprivate func moveLineDown() {
        let ns = textView.string as NSString
        guard ns.length > 0 else { return }

        let sel      = textView.selectedRange()
        let curRange = ns.lineRange(for: sel)
        guard NSMaxRange(curRange) < ns.length else { return }

        let belowRange = ns.lineRange(for: NSRange(location: NSMaxRange(curRange), length: 0))

        var curText   = ns.substring(with: curRange)
        var belowText = ns.substring(with: belowRange)

        if !belowText.hasSuffix("\n") && curText.hasSuffix("\n") {
            belowText += "\n"
            curText    = String(curText.dropLast())
        }

        let fullRange = NSRange(location: curRange.location,
                                length: NSMaxRange(belowRange) - curRange.location)
        replaceText(in: fullRange, with: belowText + curText)

        let newStart = curRange.location
                     + (belowText as NSString).length
                     + (sel.location - curRange.location)
        textView.setSelectedRange(NSRange(location: newStart, length: sel.length))
    }
}

// MARK: - Cmd+Shift+K — delete current line

extension EditorViewController {

    fileprivate func deleteCurrentLine() {
        let ns = textView.string as NSString
        guard ns.length > 0 else { return }

        let sel = textView.selectedRange()
        var lineRange = ns.lineRange(for: sel)

        if NSMaxRange(lineRange) == ns.length && lineRange.location > 0 {
            lineRange = NSRange(location: lineRange.location - 1,
                                length: lineRange.length + 1)
        }

        replaceText(in: lineRange, with: "")

        let newPos = min(lineRange.location, (textView.string as NSString).length)
        textView.setSelectedRange(NSRange(location: newPos, length: 0))
    }
}

// MARK: - Cmd+Shift+L — select all occurrences & enter multi-edit

extension EditorViewController {

    func selectAllOccurrences() {
        let sel = textView.selectedRange()
        guard sel.length > 0 else { return }

        let ns     = textView.string as NSString
        let needle = ns.substring(with: sel)

        var ranges: [NSValue] = []
        var pos = 0
        while pos < ns.length {
            let r = ns.range(of: needle,
                             range: NSRange(location: pos, length: ns.length - pos))
            if r.location == NSNotFound { break }
            ranges.append(NSValue(range: r))
            pos = NSMaxRange(r)
        }

        guard !ranges.isEmpty else { return }
        selectionHistory.append(selectionSet.ranges)
        setSelections(ranges.map(\.rangeValue), primaryRange: sel)

        if ranges.count > 1 {
            isMultiEditActive = true
        }
    }
}

// MARK: - Multi-edit key routing

extension EditorViewController {

    fileprivate func handleMultiEditKey(_ event: NSEvent) -> Bool {
        if textView.hasMarkedText() || hasMarkedTextComposition { return false }
        let mods = event.modifierFlags.intersection([.command, .shift, .option, .control])
        guard let gesture = KeyGesture(event: event) else { return false }
        let key = gesture.key

        if key == "escape" { exitMultiEdit(); return true }

        if ["left", "right", "down", "up", "enter", "tab"].contains(key) {
            exitMultiEdit(); return false
        }

        if mods == .command, event.charactersIgnoringModifiers == "v",
           let text = NSPasteboard.general.string(forType: .string) {
            multiEditPaste(text)
            return true
        }
        if mods == .command, event.charactersIgnoringModifiers == "c",
           let text = copiedColumnText() {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            return true
        }

        if mods.contains(.command) { exitMultiEdit(); return false }

        if key == "backspace" { multiEditBackspace(); return true }
        if key == "delete" { multiEditForwardDelete(); return true }

        // Printable text, including the keystrokes that begin an IME
        // composition, must flow through NSTextInputClient. MaruTextView
        // broadcasts only the final `insertText` commit.
        return false
    }

    func exitMultiEdit() {
        isMultiEditActive = false
        selectionHistory.removeAll()
        setSelections([selectionSet.primaryRange], primaryRange: selectionSet.primaryRange)
    }
}

// MARK: - Multi-edit operations

extension EditorViewController {

    func multiEditInsert(_ text: String) {
        if columnSelectionRows != nil {
            insertIntoColumnSelection([text])
            return
        }
        let cursors = multiEditCursorRanges.map { replacementRangeForInput(text, selection: $0) }
        guard !cursors.isEmpty else { exitMultiEdit(); return }
        batchReplace(cursors, with: text)
    }

    func multiEditBackspace() {
        let wasColumnSelection = columnSelectionRows != nil
        let cursors = multiEditCursorRanges
        guard !cursors.isEmpty else { exitMultiEdit(); return }

        if cursors.contains(where: { $0.length > 0 }) {
            batchReplace(cursors, with: "")
        } else {
            let expanded = cursors.compactMap { r -> NSRange? in
                guard r.location > 0 else { return nil }
                return NSRange(location: r.location - 1, length: 1)
            }
            guard !expanded.isEmpty else { return }
            batchReplace(expanded, with: "")
        }
        if wasColumnSelection { columnSelectionRows = nil }
    }

    func multiEditForwardDelete() {
        let wasColumnSelection = columnSelectionRows != nil
        let cursors = multiEditCursorRanges
        guard !cursors.isEmpty else { exitMultiEdit(); return }
        let len = (textView.string as NSString).length

        if cursors.contains(where: { $0.length > 0 }) {
            batchReplace(cursors, with: "")
        } else {
            let expanded = cursors.compactMap { r -> NSRange? in
                guard r.location < len else { return nil }
                return NSRange(location: r.location, length: 1)
            }
            guard !expanded.isEmpty else { return }
            batchReplace(expanded, with: "")
        }
        if wasColumnSelection { columnSelectionRows = nil }
    }

    /// If the clipboard has exactly one line per selection, each line is
    /// pasted into its corresponding normalized selection. Otherwise the
    /// complete clipboard text is inserted at every selection.
    func multiEditPaste(_ text: String) {
        if columnSelectionRows != nil {
            insertIntoColumnSelection(text.components(separatedBy: "\n"))
            return
        }
        let ranges = selectionSet.ranges
        let fragments = text.components(separatedBy: "\n")
        if ranges.count > 1, fragments.count == ranges.count {
            batchReplace(ranges, with: fragments)
        } else {
            batchReplace(ranges, with: text)
        }
    }
}

// MARK: - Batch replacement engine (multi-cursor aware)

extension EditorViewController {

    /// Replaces every range with `text`, merges overlaps, repositions all cursors,
    /// and auto-exits multi-edit when only one cursor remains.
    ///
    /// We deliberately bypass `didChangeText()` here because the delegate's
    /// `textDidChange` handler runs rehighlighting via `ts.beginEditing/endEditing`,
    /// which collapses multi-selection back to a single cursor.  Instead we update
    /// the document state and undo stack manually.
    func batchReplace(_ targetRanges: [NSRange], with text: String) {
        batchReplace(targetRanges, with: Array(repeating: text, count: targetRanges.count))
    }

    /// Lenient adapter over the strict transaction primitive.
    ///
    /// Multi-cursor editing has always dropped ranges that no longer exist and
    /// merged overlapping ones by letting the earliest supply the replacement
    /// for the union. That behavior is load-bearing for a human dragging
    /// cursors around, and macros depend on it, so it is preserved here — in
    /// the adapter — rather than by weakening the primitive that automation
    /// needs to be strict.
    func batchReplace(_ targetRanges: [NSRange], with replacements: [String]) {
        batchReplace(targetRanges, with: replacements, actionName: "Multiple Selection Edit")
    }

    func batchReplace(
        _ targetRanges: [NSRange],
        with replacements: [String],
        actionName: String
    ) {
        guard let storage = textView.textStorage else { return }
        guard targetRanges.count == replacements.count else { return }

        var operations: [(range: NSRange, replacement: String)] = []
        for index in targetRanges.indices {
            let range = targetRanges[index]
            guard range.location != NSNotFound, NSMaxRange(range) <= storage.length else { continue }
            operations.append((range, replacements[index]))
        }
        operations.sort {
            $0.range.location == $1.range.location
                ? $0.range.length < $1.range.length : $0.range.location < $1.range.location
        }
        var merged: [(range: NSRange, replacement: String)] = []
        for operation in operations {
            if let last = merged.last,
               (operation.range.location < NSMaxRange(last.range)
                || (operation.range.length == 0 && NSLocationInRange(operation.range.location, last.range))) {
                let end = max(NSMaxRange(last.range), NSMaxRange(operation.range))
                // Deterministic overlap rule: the earliest normalized
                // selection supplies the replacement for the union.
                merged[merged.count - 1].range = NSRange(
                    location: last.range.location, length: end - last.range.location)
            } else {
                merged.append(operation)
            }
        }
        guard !merged.isEmpty else { return }

        _ = commitValidatedTransaction(
            merged.map { AutomationEdit(range: $0.range, replacement: $0.replacement) },
            actionName: actionName)
    }

}

// MARK: - Tab / Shift+Tab — indent / unindent selected lines

extension EditorViewController {

    /// Indents all selected lines when the selection spans multiple lines.
    /// Returns `false` (pass-through to default Tab behavior) for single-line or empty selections.
    fileprivate func indentSelectedLines() -> Bool {
        let sel = textView.selectedRange()
        guard sel.length > 0 else { return false }

        let ns = textView.string as NSString
        guard ns.substring(with: sel).contains("\n") else { return false }

        let lineRange = ns.lineRange(for: sel)
        let text = ns.substring(with: lineRange)

        var indented = "\t" + text.replacingOccurrences(of: "\n", with: "\n\t")
        if text.hasSuffix("\n") { indented = String(indented.dropLast()) }

        replaceText(in: lineRange, with: indented)
        textView.setSelectedRange(NSRange(location: lineRange.location,
                                          length: (indented as NSString).length))
        return true
    }

    /// Removes one level of indentation (one tab or up to 4 leading spaces) from
    /// each selected line, or the current line when nothing is selected.
    fileprivate func unindentSelectedLines() {
        let sel = textView.selectedRange()
        let ns = textView.string as NSString
        let lineRange = ns.lineRange(for: sel)
        let text = ns.substring(with: lineRange)

        let lines = text.components(separatedBy: "\n")
        let result = lines.enumerated().map { i, line -> String in
            if i == lines.count - 1 && line.isEmpty { return line }
            if line.hasPrefix("\t") { return String(line.dropFirst()) }
            var s = line[...]
            var n = 0
            while s.hasPrefix(" ") && n < 4 { s = s.dropFirst(); n += 1 }
            return String(s)
        }.joined(separator: "\n")

        guard result != text else { return }
        replaceText(in: lineRange, with: result)
        textView.setSelectedRange(NSRange(location: lineRange.location,
                                          length: (result as NSString).length))
    }
}

// MARK: - Single-range text replacement (used by move / delete line)

extension EditorViewController {

    fileprivate func replaceText(in range: NSRange, with replacement: String) {
        guard textView.shouldChangeText(in: range, replacementString: replacement) else { return }
        textView.textStorage?.replaceCharacters(in: range, with: replacement)
        textView.didChangeText()
    }
}
