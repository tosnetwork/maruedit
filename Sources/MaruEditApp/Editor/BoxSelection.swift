import Foundation

struct BoxSelectionRow: Equatable {
    let line: Int
    let range: NSRange
    let leadingVirtualSpaces: Int
}

struct TextCoordinate: Equatable {
    let line: Int
    let visualColumn: Int
}

enum BoxSelectionModel {
    static func coordinate(atUTF16Offset offset: Int, in text: String, tabWidth: Int = 4) -> TextCoordinate {
        let ns = text as NSString
        let clamped = min(max(0, offset), ns.length)
        var line = 0
        var lineStart = 0
        var cursor = 0
        while cursor < clamped {
            if ns.character(at: cursor) == 10 { line += 1; lineStart = cursor + 1 }
            cursor += 1
        }
        let prefix = ns.substring(with: NSRange(location: lineStart, length: clamped - lineStart))
        return TextCoordinate(line: line, visualColumn: visualWidth(of: prefix, tabWidth: tabWidth))
    }

    static func rows(
        in text: String,
        anchor: TextCoordinate,
        current: TextCoordinate,
        tabWidth: Int = 4
    ) -> [BoxSelectionRow] {
        let ns = text as NSString
        let lineRanges = logicalLineRanges(ns)
        guard !lineRanges.isEmpty else { return [] }
        let firstLine = min(max(0, min(anchor.line, current.line)), lineRanges.count - 1)
        let lastLine = min(max(0, max(anchor.line, current.line)), lineRanges.count - 1)
        let startColumn = min(anchor.visualColumn, current.visualColumn)
        let endColumn = max(anchor.visualColumn, current.visualColumn)

        return (firstLine...lastLine).map { line in
            let lineRange = lineRanges[line]
            let lineText = ns.substring(with: lineRange)
            let width = visualWidth(of: lineText, tabWidth: tabWidth)
            let start = utf16Offset(forVisualColumn: startColumn, in: lineText, tabWidth: tabWidth, trailing: false)
            let end = utf16Offset(forVisualColumn: endColumn, in: lineText, tabWidth: tabWidth, trailing: true)
            return BoxSelectionRow(
                line: line,
                range: NSRange(location: lineRange.location + start, length: max(0, end - start)),
                leadingVirtualSpaces: max(0, startColumn - width)
            )
        }
    }

    static func visualWidth(of text: String, tabWidth: Int = 4) -> Int {
        var column = 0
        for character in text {
            if character == "\t" {
                column += max(1, tabWidth - column % max(1, tabWidth))
            } else {
                column += characterDisplayWidth(character)
            }
        }
        return column
    }

    private static func utf16Offset(
        forVisualColumn target: Int,
        in text: String,
        tabWidth: Int,
        trailing: Bool
    ) -> Int {
        var column = 0
        var utf16 = 0
        for character in text {
            let length = String(character).utf16.count
            let width = character == "\t"
                ? max(1, tabWidth - column % max(1, tabWidth))
                : characterDisplayWidth(character)
            if target <= column { return utf16 }
            if target < column + width { return trailing ? utf16 + length : utf16 }
            column += width
            utf16 += length
        }
        return utf16
    }

    private static func logicalLineRanges(_ text: NSString) -> [NSRange] {
        if text.length == 0 { return [NSRange(location: 0, length: 0)] }
        var result: [NSRange] = []
        var start = 0
        for index in 0..<text.length where text.character(at: index) == 10 {
            result.append(NSRange(location: start, length: index - start))
            start = index + 1
        }
        result.append(NSRange(location: start, length: text.length - start))
        return result
    }

    private static func characterDisplayWidth(_ character: Character) -> Int {
        let scalars = character.unicodeScalars
        guard let base = scalars.first(where: { !CharacterSet.nonBaseCharacters.contains($0) }) else { return 0 }
        let value = base.value
        let wide = (0x1100...0x115F).contains(value)
            || (0x2E80...0xA4CF).contains(value)
            || (0xAC00...0xD7A3).contains(value)
            || (0xF900...0xFAFF).contains(value)
            || (0xFE10...0xFE6F).contains(value)
            || (0xFF01...0xFF60).contains(value)
            || (0xFFE0...0xFFE6).contains(value)
            || (0x1F300...0x1FAFF).contains(value)
        return wide ? 2 : 1
    }
}
