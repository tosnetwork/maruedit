import Foundation

/// A compact index of logical line starts in UTF-16 storage coordinates.
///
/// MaruEdit normalizes document line endings to LF while loading. Edits can
/// therefore update this index from the edited range and replacement alone;
/// the document text is only needed for display-column calculations.
public struct LineIndex: Sendable, Equatable {
    private var starts: [Int]
    public private(set) var utf16Length: Int

    public init(_ text: String = "") {
        let units = Array(text.utf16)
        utf16Length = units.count
        starts = [0]
        starts.reserveCapacity(max(1, units.count / 40))
        for (offset, unit) in units.enumerated() where unit == 0x0A {
            starts.append(offset + 1)
        }
    }

    public var lineCount: Int { starts.count }

    /// Applies an edit expressed in coordinates from before the edit.
    public mutating func applyEdit(range: NSRange, replacement: String) {
        precondition(range.location >= 0 && range.length >= 0 && NSMaxRange(range) <= utf16Length)
        let replacementUnits = Array(replacement.utf16)
        let oldEnd = NSMaxRange(range)
        let delta = replacementUnits.count - range.length

        // A start at range.location belongs to the preceding, untouched LF.
        // Starts after it and through oldEnd were created by removed text.
        starts.removeAll { $0 > range.location && $0 <= oldEnd }
        for index in starts.indices where starts[index] > oldEnd {
            starts[index] += delta
        }

        var inserted: [Int] = []
        for (offset, unit) in replacementUnits.enumerated() where unit == 0x0A {
            inserted.append(range.location + offset + 1)
        }
        if !inserted.isEmpty {
            let position = starts.partitioningIndex { $0 > range.location }
            starts.insert(contentsOf: inserted, at: position)
        }
        utf16Length += delta
    }

    /// Zero-based logical line containing the offset. EOF belongs to the
    /// final line (including the empty line after a trailing newline).
    public func line(atUTF16Offset offset: Int) -> Int {
        let safe = min(max(0, offset), utf16Length)
        return max(0, starts.partitioningIndex { $0 > safe } - 1)
    }

    public func utf16Offset(forLine line: Int) -> Int? {
        guard starts.indices.contains(line) else { return nil }
        return starts[line]
    }

    /// Range excluding the LF terminator.
    public func contentRange(forLine line: Int) -> NSRange? {
        guard let start = utf16Offset(forLine: line) else { return nil }
        let next = line + 1 < starts.count ? starts[line + 1] : utf16Length
        let end = line + 1 < starts.count ? max(start, next - 1) : next
        return NSRange(location: start, length: end - start)
    }

    public func displayColumn(
        atUTF16Offset offset: Int, in text: String, tabWidth: Int = 4
    ) -> Int {
        let safe = min(max(0, offset), utf16Length)
        let line = line(atUTF16Offset: safe)
        let start = starts[line]
        let ns = text as NSString
        let prefix = ns.substring(with: NSRange(location: start, length: min(safe, ns.length) - start))
        return Self.displayWidth(of: prefix, tabWidth: tabWidth)
    }

    public func utf16Offset(
        forLine line: Int, displayColumn target: Int, in text: String, tabWidth: Int = 4
    ) -> Int? {
        guard let range = contentRange(forLine: line) else { return nil }
        let value = (text as NSString).substring(with: range)
        var column = 0
        var offset = 0
        for character in value {
            let width = Self.displayWidth(of: String(character), startingAt: column, tabWidth: tabWidth)
            if target <= column { break }
            if target < column + width { break }
            column += width
            offset += String(character).utf16.count
        }
        return range.location + offset
    }

    public static func displayWidth(of text: String, tabWidth: Int = 4) -> Int {
        displayWidth(of: text, startingAt: 0, tabWidth: tabWidth)
    }

    private static func displayWidth(of text: String, startingAt initial: Int, tabWidth: Int) -> Int {
        var column = initial
        let width = max(1, tabWidth)
        for character in text {
            if character == "\t" {
                column += width - column % width
            } else if let base = character.unicodeScalars.first(where: {
                !CharacterSet.nonBaseCharacters.contains($0)
            }) {
                let value = base.value
                let wide = (0x1100...0x115F).contains(value)
                    || (0x2E80...0xA4CF).contains(value)
                    || (0xAC00...0xD7A3).contains(value)
                    || (0xF900...0xFAFF).contains(value)
                    || (0xFE10...0xFE6F).contains(value)
                    || (0xFF01...0xFF60).contains(value)
                    || (0xFFE0...0xFFE6).contains(value)
                    || (0x1F300...0x1FAFF).contains(value)
                column += wide ? 2 : 1
            }
        }
        return column - initial
    }
}

private extension Array {
    func partitioningIndex(where predicate: (Element) -> Bool) -> Int {
        var low = 0, high = count
        while low < high {
            let middle = low + (high - low) / 2
            if predicate(self[middle]) { high = middle } else { low = middle + 1 }
        }
        return low
    }
}
