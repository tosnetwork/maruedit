import Foundation

public struct TextDiffHunk: Equatable, Sendable, Identifiable {
    public let id: Int
    public let originalRange: NSRange
    public let replacement: String
    public let originalStartLine: Int
    public let replacementStartLine: Int
}

public enum TextDiffEngine {
    public static let detailedLineLimit = 1_000

    public static func compare(_ original: String, _ revised: String) -> [TextDiffHunk] {
        guard original != revised else { return [] }
        let old = lines(original), new = lines(revised)
        guard old.count <= detailedLineLimit, new.count <= detailedLineLimit else {
            return [TextDiffHunk(
                id: 0, originalRange: NSRange(location: 0, length: (original as NSString).length),
                replacement: revised, originalStartLine: 0, replacementStartLine: 0)]
        }
        let columns = new.count + 1
        var lcs = Array(repeating: 0, count: (old.count + 1) * columns)
        if !old.isEmpty, !new.isEmpty {
            for i in stride(from: old.count - 1, through: 0, by: -1) {
                for j in stride(from: new.count - 1, through: 0, by: -1) {
                    lcs[i * columns + j] = old[i].text == new[j].text
                        ? 1 + lcs[(i + 1) * columns + j + 1]
                        : max(lcs[(i + 1) * columns + j], lcs[i * columns + j + 1])
                }
            }
        }
        var hunks: [TextDiffHunk] = []
        var i = 0, j = 0
        while i < old.count || j < new.count {
            if i < old.count, j < new.count, old[i].text == new[j].text { i += 1; j += 1; continue }
            let oldStart = i, newStart = j
            while i < old.count || j < new.count {
                if i < old.count, j < new.count, old[i].text == new[j].text { break }
                if j == new.count || (i < old.count
                    && lcs[(i + 1) * columns + j] >= lcs[i * columns + min(j + 1, new.count)]) {
                    i += 1
                } else { j += 1 }
            }
            let location = oldStart < old.count
                ? old[oldStart].range.location : (original as NSString).length
            let end = i > oldStart ? NSMaxRange(old[i - 1].range) : location
            hunks.append(TextDiffHunk(
                id: hunks.count,
                originalRange: NSRange(location: location, length: end - location),
                replacement: new[newStart..<j].map(\.text).joined(),
                originalStartLine: oldStart, replacementStartLine: newStart))
        }
        return hunks
    }

    public static func applying(_ hunk: TextDiffHunk, to original: String) -> String? {
        let ns = original as NSString
        guard hunk.originalRange.location >= 0,
              NSMaxRange(hunk.originalRange) <= ns.length else { return nil }
        return ns.replacingCharacters(in: hunk.originalRange, with: hunk.replacement)
    }

    private struct Line { let text: String; let range: NSRange }
    private static func lines(_ text: String) -> [Line] {
        let ns = text as NSString
        guard ns.length > 0 else { return [] }
        var result: [Line] = [], offset = 0
        while offset < ns.length {
            let range = ns.lineRange(for: NSRange(location: offset, length: 0))
            result.append(Line(text: ns.substring(with: range), range: range))
            offset = NSMaxRange(range)
        }
        return result
    }
}
