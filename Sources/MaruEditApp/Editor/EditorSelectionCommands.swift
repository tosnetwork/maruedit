import AppKit
import MaruEditCore

extension EditorViewController {
    func selectCurrentWord() {
        textView.selectWord(nil)
        let range = textView.selectedRange()
        setSelections([range], primaryRange: range)
    }

    func selectCurrentLine() {
        let text = textView.string as NSString
        let location = min(selectionSet.primaryRange.location, text.length)
        let range = text.lineRange(for: NSRange(location: location, length: 0))
        setSelections([range], primaryRange: range)
    }

    func selectCurrentParagraph() {
        let text = textView.string as NSString
        let location = min(selectionSet.primaryRange.location, text.length)
        let range = text.paragraphRange(for: NSRange(location: location, length: 0))
        setSelections([range], primaryRange: range)
    }

    func copyWithQuotePrefix(to pasteboard: NSPasteboard = .general) -> Bool {
        let text = textView.string as NSString
        let values = selectionSet.ranges.compactMap { range -> String? in
            guard range.length > 0, NSMaxRange(range) <= text.length else { return nil }
            return text.substring(with: range).split(separator: "\n", omittingEmptySubsequences: false)
                .map { "> \($0)" }.joined(separator: "\n")
        }
        guard !values.isEmpty else { return false }
        pasteboard.clearContents()
        return pasteboard.setString(values.joined(separator: "\n"), forType: .string)
    }

    func pasteRemovingQuotePrefix(from pasteboard: NSPasteboard = .general) -> Bool {
        guard let value = pasteboard.string(forType: .string) else { return false }
        let unquoted = value.split(separator: "\n", omittingEmptySubsequences: false).map { line -> String in
            if line.hasPrefix("> ") { return String(line.dropFirst(2)) }
            if line.hasPrefix(">") { return String(line.dropFirst()) }
            return String(line)
        }.joined(separator: "\n")
        batchReplace(selectionSet.ranges, with: unquoted)
        return true
    }

    @discardableResult
    func appendSelectionToClipboard(cut: Bool, pasteboard: NSPasteboard = .general) -> Bool {
        let source = textView.string as NSString
        let ranges = selectionSet.ranges.filter { $0.length > 0 && NSMaxRange($0) <= source.length }
        guard !ranges.isEmpty else { return false }
        let appended = (pasteboard.string(forType: .string) ?? "")
            + ranges.map { source.substring(with: $0) }.joined(separator: "\n")
        pasteboard.clearContents()
        guard pasteboard.setString(appended, forType: .string) else { return false }
        if cut { batchReplace(ranges, with: "") }
        return true
    }

    func deleteToLineStart() { deleteTowardLineBoundary(start: true) }
    func deleteToLineEnd() { deleteTowardLineBoundary(start: false) }

    private func deleteTowardLineBoundary(start: Bool) {
        let source = textView.string as NSString
        let ranges = selectionSet.ranges.compactMap { selection -> NSRange? in
            guard selection.location <= source.length else { return nil }
            if selection.length > 0 { return selection }
            let line = source.lineRange(for: NSRange(location: selection.location, length: 0))
            var contentEnd = NSMaxRange(line)
            while contentEnd > line.location,
                  let scalar = UnicodeScalar(source.character(at: contentEnd - 1)),
                  CharacterSet.newlines.contains(scalar) { contentEnd -= 1 }
            return start
                ? NSRange(location: line.location, length: selection.location - line.location)
                : NSRange(location: selection.location, length: contentEnd - selection.location)
        }.filter { $0.length > 0 }
        if !ranges.isEmpty { batchReplace(ranges, with: "") }
    }

    func invertSelections() {
        let length = (textView.string as NSString).length
        let selected = selectionSet.ranges.filter { $0.length > 0 }.sorted { $0.location < $1.location }
        var result: [NSRange] = []
        var cursor = 0
        for range in selected {
            if cursor < range.location { result.append(NSRange(location: cursor, length: range.location - cursor)) }
            cursor = max(cursor, min(length, NSMaxRange(range)))
        }
        if cursor < length { result.append(NSRange(location: cursor, length: length - cursor)) }
        if result.isEmpty { result = [NSRange(location: 0, length: 0)] }
        setSelections(result, primaryRange: result.first)
        isMultiEditActive = result.count > 1
    }

    func reserveSelections() {
        let ranges = selectionSet.ranges.filter { $0.length > 0 }
        guard !ranges.isEmpty else { return }
        reservedSelections = ranges
        let cursor = NSRange(location: NSMaxRange(selectionSet.primaryRange), length: 0)
        setSelections([cursor], primaryRange: cursor)
        isMultiEditActive = false
    }

    func restoreReservedSelections() {
        guard !reservedSelections.isEmpty else { return }
        let current = selectionSet.ranges
        let restored = reservedSelections + current
        reservedSelections = []
        setSelections(restored, primaryRange: current.first)
        isMultiEditActive = selectionSet.ranges.count > 1
    }

    @discardableResult
    func boxPaste(from pasteboard: NSPasteboard = .general) -> Bool {
        guard let value = pasteboard.string(forType: .string) else { return false }
        let fragments = value.components(separatedBy: "\n")
        let origin = BoxSelectionModel.coordinate(
            atUTF16Offset: selectionSet.primaryRange.location, in: textView.string,
            tabWidth: max(1, appliedPreferences.tabWidth))
        let end = TextCoordinate(line: origin.line + max(0, fragments.count - 1), visualColumn: origin.visualColumn)
        let rows = BoxSelectionModel.rows(
            in: textView.string, anchor: origin, current: end,
            tabWidth: max(1, appliedPreferences.tabWidth))
        guard !rows.isEmpty else { return false }
        let replacements = zip(rows, fragments).map { row, fragment in
            String(repeating: " ", count: row.leadingVirtualSpaces) + fragment
        }
        batchReplace(rows.map(\.range), with: replacements)
        return true
    }

    func applyConversionPipeline(
        _ steps: [TextConversionStep], registry: TextConversionRegistry = TextConversionRegistry()
    ) throws {
        let source = textView.string as NSString
        guard source.length > 0 else { return }
        let selected = selectionSet.ranges.filter { $0.length > 0 }
        let ranges = selected.isEmpty
            ? SelectionSet.normalize(selectionSet.ranges.map { source.lineRange(for: $0) })
            : SelectionSet.normalize(selected)
        let replacements = try ranges.map { try registry.apply(steps, to: source.substring(with: $0)) }
        batchReplace(ranges, with: replacements)
    }

    @discardableResult
    func correctCapsLockMistake() -> Bool {
        if selectionSet.ranges.allSatisfy({ $0.length == 0 }) {
            selectCurrentWord()
        }
        let source = textView.string as NSString
        let ranges = selectionSet.ranges.filter {
            $0.length > 0 && NSMaxRange($0) <= source.length
        }
        guard !ranges.isEmpty else { return false }
        let replacements = ranges.map { range in
            let value = source.substring(with: range)
            return value.rangeOfCharacter(from: .lowercaseLetters) == nil
                ? value.lowercased() : value.uppercased()
        }
        batchReplace(ranges, with: replacements)
        return true
    }

    @discardableResult
    func reconvertWithCurrentInputMethod() -> Bool {
        NSApp.sendAction(Selector(("reconvert:")), to: nil, from: textView)
    }

    func addCursorAbove() { addCursorVertically(delta: -1) }
    func addCursorBelow() { addCursorVertically(delta: 1) }

    private func addCursorVertically(delta: Int) {
        let text = textView.string as NSString
        let primary = selectionSet.primaryRange
        let currentLine = text.lineRange(for: NSRange(location: min(primary.location, text.length), length: 0))
        let currentContentEnd = currentLine.length > 0 && text.substring(with: currentLine).hasSuffix("\n")
            ? NSMaxRange(currentLine) - 1 : NSMaxRange(currentLine)
        let column = min(primary.location - currentLine.location, currentContentEnd - currentLine.location)

        let targetLine: NSRange
        if delta < 0 {
            guard currentLine.location > 0 else { return }
            targetLine = text.lineRange(for: NSRange(location: currentLine.location - 1, length: 0))
        } else {
            guard NSMaxRange(currentLine) < text.length else { return }
            targetLine = text.lineRange(for: NSRange(location: NSMaxRange(currentLine), length: 0))
        }
        let targetHasNewline = targetLine.length > 0 && text.substring(with: targetLine).hasSuffix("\n")
        let targetEnd = NSMaxRange(targetLine) - (targetHasNewline ? 1 : 0)
        let cursor = NSRange(location: min(targetLine.location + column, targetEnd), length: 0)
        guard !selectionSet.ranges.contains(cursor) else { return }

        selectionHistory.append(selectionSet.ranges)
        let primaryRange = selectionSet.primaryRange
        setSelections(selectionSet.ranges + [cursor], primaryRange: primaryRange)
        isMultiEditActive = selectionSet.ranges.count > 1
    }

    func selectNextOccurrence() {
        let text = textView.string as NSString
        let primary = selectionSet.primaryRange
        guard primary.length > 0, NSMaxRange(primary) <= text.length else { return }
        let needle = text.substring(with: primary)
        let query = SearchQuery(pattern: needle, mode: .literal, isCaseSensitive: true, wraps: true)
        guard let matches = try? SearchEngine.matches(for: query, in: text as String), matches.count > 1 else { return }

        let existing = Set(selectionSet.ranges.map { "\($0.location):\($0.length)" })
        let ordered = matches.filter { $0.range.location > primary.location } + matches.filter { $0.range.location <= primary.location }
        guard let next = ordered.first(where: { !existing.contains("\($0.range.location):\($0.range.length)") }) else { return }
        selectionHistory.append(selectionSet.ranges)
        let primaryRange = selectionSet.primaryRange
        setSelections(selectionSet.ranges + [next.range], primaryRange: primaryRange)
        isMultiEditActive = selectionSet.ranges.count > 1
    }

    func undoLastAddedCursor() {
        guard let previous = selectionHistory.popLast() else { return }
        let primary = previous.first ?? NSRange(location: 0, length: 0)
        setSelections(previous, primaryRange: primary)
        isMultiEditActive = selectionSet.ranges.count > 1
    }
}
