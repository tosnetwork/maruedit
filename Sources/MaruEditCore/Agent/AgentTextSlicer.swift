import Foundation

/// Pure text work for the agent tools: ranged reads, literal search, and
/// coordinate mapping.
///
/// It is deliberately a free-standing value API with no reference to the
/// editor. That is what lets it run off the main actor against an immutable
/// snapshot, which is the whole reason typing does not stall while an agent
/// searches ten megabytes.
public enum AgentTextSlicer {

    public struct Slice: Equatable, Sendable {
        public let text: String
        /// One-based, inclusive.
        public let startLine: Int
        /// One-based, exclusive — the half-open convention the protocol uses.
        public let endLine: Int
        public let totalLines: Int
        public let startOffset: Int
        public let endOffset: Int
        public let truncated: Bool
    }

    public struct Position: Equatable, Sendable {
        /// One-based.
        public let line: Int
        /// One-based, in UTF-16 code units.
        public let column: Int
    }

    public static let maximumSelectionCharacters = 4_000

    /// Bounds a piece of text for display in a result, marking it when cut.
    public static func bounded(_ text: String, limit: Int = maximumSelectionCharacters) -> String {
        guard text.count > limit else { return text }
        return String(text.prefix(limit)) + "…"
    }

    /// UTF-16 offsets at which each line starts.
    ///
    /// A line opens after every LF, including a trailing one — so "a\n" is two
    /// lines, the second empty. That is what `LineIndex` does and therefore
    /// what the gutter shows, and a protocol whose line numbers disagreed with
    /// the numbers on screen would be worse than useless.
    static func lineStarts(_ text: NSString) -> [Int] {
        var starts = [0]
        for offset in 0..<text.length where text.character(at: offset) == 0x0A {
            starts.append(offset + 1)
        }
        return starts
    }

    public static func position(ofOffset offset: Int, in text: NSString) -> Position {
        let starts = lineStarts(text)
        var low = 0, high = starts.count - 1, line = 0
        while low <= high {
            let mid = (low + high) / 2
            if starts[mid] <= offset { line = mid; low = mid + 1 } else { high = mid - 1 }
        }
        return Position(line: line + 1, column: offset - starts[line] + 1)
    }

    /// Extracts a half-open line range, bounded by bytes.
    ///
    /// Truncation moves back to a character boundary so a multi-byte scalar is
    /// never split, and the result reports the range it actually covers rather
    /// than the one that was asked for.
    public static func slice(
        text: String, startLine: Int?, endLine: Int?, maxBytes: Int
    ) -> Slice {
        let ns = text as NSString
        let starts = lineStarts(ns)
        let totalLines = starts.count

        let firstLine = max(1, startLine ?? 1)
        let lastLineExclusive = min(totalLines + 1, endLine ?? (totalLines + 1))
        guard firstLine <= totalLines, firstLine < lastLineExclusive else {
            return Slice(
                text: "", startLine: firstLine, endLine: firstLine, totalLines: totalLines,
                startOffset: ns.length, endOffset: ns.length, truncated: false)
        }

        let startOffset = starts[firstLine - 1]
        let endOffset = lastLineExclusive - 1 < starts.count ? starts[lastLineExclusive - 1] : ns.length
        var body = ns.substring(with: NSRange(location: startOffset, length: endOffset - startOffset))

        var truncated = false
        if body.utf8.count > maxBytes {
            truncated = true
            var cut = body.startIndex
            var used = 0
            for index in body.indices {
                let size = String(body[index]).utf8.count
                if used + size > maxBytes { break }
                used += size
                cut = body.index(after: index)
            }
            body = String(body[body.startIndex..<cut])
        }

        let actualEndOffset = startOffset + (body as NSString).length
        let actualEndLine = truncated
            ? position(ofOffset: max(startOffset, actualEndOffset - 1), in: ns).line + 1
            : lastLineExclusive
        return Slice(
            text: body,
            startLine: firstLine,
            endLine: actualEndLine,
            totalLines: totalLines,
            startOffset: startOffset,
            endOffset: actualEndOffset,
            truncated: truncated)
    }

    public struct SearchResults: Sendable {
        public let matches: [JSONValue]
        public let truncated: Bool
    }

    /// Literal search only.
    ///
    /// Regular expressions wait for a phase that can bound them: the existing
    /// engine makes one synchronous `NSRegularExpression` call with no
    /// cancellation point, so a catastrophically backtracking pattern cannot be
    /// stopped by any timer this process owns, and a client that repeats it has
    /// a denial-of-service primitive.
    public static func searchLiteral(
        in documents: [(id: String, revision: UInt64, metadataRevision: UInt64, text: String)],
        query: String,
        ignoreCase: Bool,
        limit: Int,
        contextCharacters: Int = 80
    ) -> SearchResults {
        var matches: [JSONValue] = []
        var truncated = false

        for document in documents {
            let ns = document.text as NSString
            let starts = lineStarts(ns)
            var searchRange = NSRange(location: 0, length: ns.length)
            let options: NSString.CompareOptions = ignoreCase ? [.caseInsensitive, .literal] : [.literal]

            while searchRange.length > 0 {
                let found = ns.range(of: query, options: options, range: searchRange)
                guard found.location != NSNotFound else { break }
                if matches.count >= limit {
                    truncated = true
                    break
                }

                var line = 0
                var low = 0, high = starts.count - 1
                while low <= high {
                    let mid = (low + high) / 2
                    if starts[mid] <= found.location { line = mid; low = mid + 1 } else { high = mid - 1 }
                }
                let lineStart = starts[line]
                let lineEnd = line + 1 < starts.count ? starts[line + 1] : ns.length
                let lineText = ns.substring(with: NSRange(location: lineStart, length: lineEnd - lineStart))

                let beforeStart = max(0, found.location - contextCharacters)
                let afterEnd = min(ns.length, NSMaxRange(found) + contextCharacters)

                matches.append(.object([
                    "documentId": .string(document.id),
                    "revision": .int(Int(document.revision)),
                    "metadataRevision": .int(Int(document.metadataRevision)),
                    "line": .int(line + 1),
                    "column": .int(found.location - lineStart + 1),
                    "offset": .int(found.location),
                    "length": .int(found.length),
                    "lineText": .string(bounded(lineText.trimmingCharacters(in: .newlines), limit: 400)),
                    "contextBefore": .string(ns.substring(
                        with: NSRange(location: beforeStart, length: found.location - beforeStart))),
                    "contextAfter": .string(ns.substring(
                        with: NSRange(location: NSMaxRange(found), length: afterEnd - NSMaxRange(found)))),
                ]))

                let next = NSMaxRange(found)
                searchRange = NSRange(location: next, length: ns.length - next)
            }
            if truncated { break }
        }

        return SearchResults(matches: matches, truncated: truncated)
    }
}
