import Foundation

public struct InMemorySearchDocument: Sendable, Equatable {
    public let url: URL
    public let displayName: String
    public let text: String
    public let encoding: TextEncoding

    public init(url: URL, displayName: String, text: String, encoding: TextEncoding = .utf8) {
        self.url = url; self.displayName = displayName; self.text = text; self.encoding = encoding
    }
}

/// Grep for buffers whose in-memory contents may differ from disk or have no file yet.
public enum InMemoryGrepService {
    public static func search(
        _ documents: [InMemorySearchDocument], query: SearchQuery
    ) throws -> [GrepMatch] {
        let regex = try SearchEngine.compile(query)
        var result: [GrepMatch] = []
        for document in documents.prefix(1_000) {
            let text = String(document.text.prefix(10_000_000))
            let ns = text as NSString
            let index = LineIndex(text)
            for match in SearchEngine.matches(for: query, in: text, using: regex) {
                let location = min(match.range.location, ns.length)
                let line = index.line(atUTF16Offset: location)
                guard let lineRange = index.contentRange(forLine: line) else { continue }
                let column = location - lineRange.location
                result.append(GrepMatch(
                    url: document.url, relativePath: document.displayName,
                    line: line + 1, column: column + 1, range: match.range,
                    preview: ns.substring(with: lineRange),
                    previewRange: NSRange(location: column, length: min(
                        match.range.length, max(0, lineRange.length - column))),
                    encoding: document.encoding))
                if result.count == 100_000 { return result }
            }
        }
        return result
    }

    /// Grep-over-results: keeps rows whose displayed line matches a new query.
    public static func refine(_ matches: [GrepMatch], query: SearchQuery) throws -> [GrepMatch] {
        let regex = try SearchEngine.compile(query)
        return matches.filter {
            !SearchEngine.matches(for: query, in: $0.preview, using: regex).isEmpty
        }
    }
}
