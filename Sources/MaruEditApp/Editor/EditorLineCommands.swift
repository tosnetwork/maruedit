import AppKit
import MaruEditCore

enum LineEditCommand {
    case delete, duplicate, moveUp, moveDown, join
    case trimTrailingWhitespace, uppercase, lowercase, titlecase, sort, reverse
    case indent, outdent, toggleComment
}

extension EditorViewController {
    func performLineCommand(_ command: LineEditCommand) {
        let ns = textView.string as NSString
        guard ns.length > 0 else { return }
        var ranges = commandRanges(for: command, in: ns)
        guard !ranges.isEmpty else { return }

        if command == .moveUp { ranges = ranges.filter { $0.location > 0 } }
        if command == .moveDown { ranges = ranges.filter { NSMaxRange($0) < ns.length } }
        guard !ranges.isEmpty else { return }

        var editRanges: [NSRange] = []
        var replacements: [String] = []
        for range in ranges {
            let edit = lineEdit(command, range: range, text: ns)
            guard edit.replacement != edit.original || edit.range != range else { continue }
            editRanges.append(edit.range)
            replacements.append(edit.replacement)
        }
        guard !editRanges.isEmpty else { return }
        var offset = 0
        let resultRanges = zip(editRanges, replacements).map { range, replacement in
            let replacementLength = (replacement as NSString).length
            defer { offset += replacementLength - range.length }
            return NSRange(location: range.location + offset, length: replacementLength)
        }
        batchReplace(editRanges, with: replacements)
        setSelections(resultRanges, primaryRange: resultRanges.first)
    }

    private func commandRanges(for command: LineEditCommand, in text: NSString) -> [NSRange] {
        let hasSelection = selectionSet.ranges.contains { $0.length > 0 }
        if [.uppercase, .lowercase, .titlecase].contains(command), hasSelection {
            return SelectionSet.normalize(selectionSet.ranges.filter { $0.length > 0 })
        }
        if !hasSelection && [.trimTrailingWhitespace, .sort, .reverse].contains(command) {
            return [NSRange(location: 0, length: text.length)]
        }
        var blocks = selectionSet.ranges.map { text.lineRange(for: $0) }
        blocks.sort { $0.location < $1.location }
        var merged: [NSRange] = []
        for range in blocks {
            if let last = merged.last, range.location <= NSMaxRange(last) {
                let end = max(NSMaxRange(last), NSMaxRange(range))
                merged[merged.count - 1] = NSRange(location: last.location, length: end - last.location)
            } else { merged.append(range) }
        }
        return merged
    }

    private func lineEdit(
        _ command: LineEditCommand,
        range: NSRange,
        text: NSString
    ) -> (range: NSRange, original: String, replacement: String) {
        let original = text.substring(with: range)
        switch command {
        case .delete:
            var deletion = range
            if NSMaxRange(range) == text.length, range.location > 0, !original.hasSuffix("\n") {
                deletion = NSRange(location: range.location - 1, length: range.length + 1)
            }
            return (deletion, text.substring(with: deletion), "")
        case .duplicate:
            let replacement = original.hasSuffix("\n") ? original + original : original + "\n" + original
            return (range, original, replacement)
        case .moveUp:
            let above = text.lineRange(for: NSRange(location: range.location - 1, length: 0))
            let full = NSRange(location: above.location, length: NSMaxRange(range) - above.location)
            var blockText = original
            var aboveText = text.substring(with: above)
            if !blockText.hasSuffix("\n"), aboveText.hasSuffix("\n") {
                blockText += "\n"; aboveText.removeLast()
            }
            return (full, text.substring(with: full), blockText + aboveText)
        case .moveDown:
            let below = text.lineRange(for: NSRange(location: NSMaxRange(range), length: 0))
            let full = NSRange(location: range.location, length: NSMaxRange(below) - range.location)
            var blockText = original
            var belowText = text.substring(with: below)
            if !belowText.hasSuffix("\n"), blockText.hasSuffix("\n") {
                belowText += "\n"; blockText.removeLast()
            }
            return (full, text.substring(with: full), belowText + blockText)
        case .join:
            var span = range
            if !original.contains("\n") || (original.filter { $0 == "\n" }.count == 1 && original.hasSuffix("\n")) {
                if NSMaxRange(range) < text.length {
                    let below = text.lineRange(for: NSRange(location: NSMaxRange(range), length: 0))
                    span.length = NSMaxRange(below) - span.location
                }
            }
            let source = text.substring(with: span)
            let trailing = source.hasSuffix("\n")
            var lines = source.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            if trailing, lines.last == "" { lines.removeLast() }
            let joined = lines.map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: " ")
                + (trailing ? "\n" : "")
            return (span, source, joined)
        case .trimTrailingWhitespace:
            return (range, original, transformLines(original) { $0.replacingOccurrences(
                of: #"[ \t]+$"#, with: "", options: .regularExpression) })
        case .uppercase: return (range, original, original.uppercased())
        case .lowercase: return (range, original, original.lowercased())
        case .titlecase: return (range, original, original.capitalized)
        case .sort: return (range, original, reorderLines(original) { $0.sorted() })
        case .reverse: return (range, original, reorderLines(original) { Array($0.reversed()) })
        case .indent:
            let settings = document?.fileTypeProfile?.settings
            let unit: String
            if let settings {
                unit = settings.indentStyle == .tabs
                    ? "\t" : String(repeating: " ", count: max(1, settings.indentWidth))
            } else {
                unit = "\t"
            }
            return (range, original, transformLines(original) { unit + $0 })
        case .outdent:
            let width = max(1, document?.fileTypeProfile?.settings.indentWidth ?? 4)
            return (range, original, transformLines(original) { line in
                if line.hasPrefix("\t") { return String(line.dropFirst()) }
                return String(line.dropFirst(min(width, line.prefix { $0 == " " }.count)))
            })
        case .toggleComment:
            guard let delimiter = document?.fileTypeProfile?.settings.lineComment
                    ?? document?.language.lineCommentDelimiter else { return (range, original, original) }
            let lines = logicalLines(original)
            let meaningful = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            let remove = !meaningful.isEmpty && meaningful.allSatisfy {
                $0.drop(while: { $0 == " " || $0 == "\t" }).hasPrefix(delimiter)
            }
            return (range, original, transformLines(original) { line in
                guard !line.trimmingCharacters(in: .whitespaces).isEmpty else { return line }
                let indent = line.prefix { $0 == " " || $0 == "\t" }
                var body = line.dropFirst(indent.count)
                if remove, body.hasPrefix(delimiter) {
                    body = body.dropFirst(delimiter.count)
                    if body.hasPrefix(" ") { body = body.dropFirst() }
                    return String(indent) + body
                }
                return String(indent) + delimiter + " " + body
            })
        }
    }

    private func logicalLines(_ text: String) -> [String] {
        var lines = text.components(separatedBy: "\n")
        if text.hasSuffix("\n") { lines.removeLast() }
        return lines
    }

    private func transformLines(_ text: String, transform: (String) -> String) -> String {
        let trailing = text.hasSuffix("\n")
        let result = logicalLines(text).map(transform).joined(separator: "\n")
        return result + (trailing ? "\n" : "")
    }

    private func reorderLines(_ text: String, reorder: ([String]) -> [String]) -> String {
        let trailing = text.hasSuffix("\n")
        return reorder(logicalLines(text)).joined(separator: "\n") + (trailing ? "\n" : "")
    }

    func goTo(line: Int, column: Int) {
        let ns = textView.string as NSString
        guard line > 0, column > 0 else { return }
        var currentLine = 1
        var index = 0
        while currentLine < line, index < ns.length {
            if ns.character(at: index) == 10 { currentLine += 1 }
            index += 1
        }
        guard currentLine == line else { return }
        let lineRange = ns.lineRange(for: NSRange(location: index, length: 0))
        let contentEnd = lineRange.length > 0 && ns.substring(with: lineRange).hasSuffix("\n")
            ? NSMaxRange(lineRange) - 1 : NSMaxRange(lineRange)
        let position = min(lineRange.location + column - 1, contentEnd)
        setSelections([NSRange(location: position, length: 0)])
        textView.scrollRangeToVisible(NSRange(location: position, length: 0))
    }
}
