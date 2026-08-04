import Foundation

/// One match found by Grep. Carries enough to display a result row and to
/// reopen the file at exactly the right place (ROADMAP.md 11.3).
///
/// Offsets are into the file's *normalized* text (CRLF and CR collapsed to
/// LF), which is what the editor shows once the file is opened — so
/// jumping to a result lands on the match even in a CRLF file.
public struct GrepMatch: Sendable, Equatable {
    public let url: URL
    /// Path relative to the search root, for display.
    public let relativePath: String
    /// 1-based.
    public let line: Int
    /// 1-based, counted in UTF-16 units from the start of the line.
    public let column: Int
    /// The match, in the whole normalized text.
    public let range: NSRange
    /// The line the match starts on, without its line break.
    public let preview: String
    /// The match's range within `preview`.
    public let previewRange: NSRange
    public let encoding: TextEncoding

    public init(
        url: URL, relativePath: String, line: Int, column: Int,
        range: NSRange, preview: String, previewRange: NSRange, encoding: TextEncoding
    ) {
        self.url = url
        self.relativePath = relativePath
        self.line = line
        self.column = column
        self.range = range
        self.preview = preview
        self.previewRange = previewRange
        self.encoding = encoding
    }
}

public struct GrepSummary: Sendable, Equatable {
    public var scannedFiles: Int
    public var matchedFiles: Int
    public var matchCount: Int
    public var skippedFiles: Int
    public var wasCancelled: Bool
    /// Set when the pattern itself was invalid; no files were scanned.
    public var errorMessage: String?

    public init(
        scannedFiles: Int = 0, matchedFiles: Int = 0, matchCount: Int = 0,
        skippedFiles: Int = 0, wasCancelled: Bool = false, errorMessage: String? = nil
    ) {
        self.scannedFiles = scannedFiles
        self.matchedFiles = matchedFiles
        self.matchCount = matchCount
        self.skippedFiles = skippedFiles
        self.wasCancelled = wasCancelled
        self.errorMessage = errorMessage
    }
}

public enum GrepEvent: Sendable {
    case started
    case match(GrepMatch)
    case skippedFile(URL, SkipReason)
    case progress(scannedFiles: Int)
    case finished(GrepSummary)
}

/// Searches a directory tree, streaming results as they are found.
///
/// Callbacks rather than `AsyncThrowingStream` (which ROADMAP.md 11.3
/// sketches): every I/O path in this codebase is synchronous and
/// queue-dispatched, and a callback keeps `GrepService` usable from the
/// same background queue that already owns `TextFileLoader`. The
/// observable contract 11.3 asks for is unchanged — streaming, progress,
/// skip reporting, prompt cancellation — so swapping in a stream later is
/// a local change. See ADR-009.
///
/// Never call this on the main thread: it reads and decodes every file.
public enum GrepService {

    public static func run(
        _ request: GrepRequest,
        isCancelled: () -> Bool = { false },
        onEvent: (GrepEvent) -> Void
    ) {
        onEvent(.started)

        // An empty pattern is an ordinary "nothing asked for" state, not a
        // user error — checked before compiling, since an empty regex is
        // itself invalid.
        guard !request.query.pattern.isEmpty else {
            onEvent(.finished(GrepSummary()))
            return
        }

        // Compiled once for the whole run rather than per file — the
        // difference is measurable across thousands of files, and it also
        // means an invalid pattern fails before any file is touched.
        let regex: NSRegularExpression
        do {
            regex = try SearchEngine.compile(request.query)
        } catch {
            onEvent(.finished(GrepSummary(errorMessage: error.localizedDescription)))
            return
        }

        var summary = GrepSummary()
        // Roots are what relative paths are shown against; a file named
        // directly as a root is shown relative to its own directory.
        let rootsForDisplay = request.roots.map { root -> URL in
            var isDirectory: ObjCBool = false
            FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory)
            return isDirectory.boolValue ? root : root.deletingLastPathComponent()
        }

        DirectoryTraversal.traverse(
            request,
            isCancelled: isCancelled,
            onFile: { url in
                guard !isCancelled() else { return }
                summary.scannedFiles += 1

                guard let loaded = try? TextFileLoader.load(contentsOf: url) else {
                    summary.skippedFiles += 1
                    onEvent(.skippedFile(url, .unreadable("Could not decode the file's text")))
                    return
                }
                let text = LineEndingDetector.normalize(loaded.content)
                let matches = SearchEngine.matches(for: request.query, in: text, using: regex)
                guard !matches.isEmpty else {
                    onEvent(.progress(scannedFiles: summary.scannedFiles))
                    return
                }

                summary.matchedFiles += 1
                summary.matchCount += matches.count
                let relative = displayPath(for: url, roots: rootsForDisplay)
                for grep in grepMatches(
                    for: matches, in: text, url: url,
                    relativePath: relative, encoding: loaded.encoding
                ) {
                    guard !isCancelled() else { return }
                    onEvent(.match(grep))
                }
                onEvent(.progress(scannedFiles: summary.scannedFiles))
            },
            onSkip: { url, reason in
                summary.skippedFiles += 1
                onEvent(.skippedFile(url, reason))
            }
        )

        summary.wasCancelled = isCancelled()
        onEvent(.finished(summary))
    }

    // MARK: - Helpers

    private static func displayPath(for url: URL, roots: [URL]) -> String {
        let path = url.standardizedFileURL.path
        // The deepest matching root wins, so nested roots don't produce a
        // path relative to an ancestor the user didn't pick.
        let best = roots
            .map { $0.standardizedFileURL.path }
            .filter { path.hasPrefix($0) }
            .max(by: { $0.count < $1.count })
        guard let rootPath = best else { return path }
        let trimmed = path.dropFirst(rootPath.count)
        return trimmed.hasPrefix("/") ? String(trimmed.dropFirst()) : String(trimmed)
    }

    /// Converts a file's matches to result rows in one pass. Line numbers
    /// are counted incrementally across the sorted match list rather than
    /// rescanning from the top of the file for each one, which for a file
    /// with many matches is the difference between linear and quadratic.
    private static func grepMatches(
        for matches: [SearchMatch],
        in text: String,
        url: URL,
        relativePath: String,
        encoding: TextEncoding
    ) -> [GrepMatch] {
        let ns = text as NSString
        var results: [GrepMatch] = []
        results.reserveCapacity(matches.count)

        let lineIndex = LineIndex(text)

        for match in matches {
            let location = min(match.range.location, ns.length)
            let line = lineIndex.line(atUTF16Offset: location)
            let previewRange = lineIndex.contentRange(forLine: line)!

            let column = location - previewRange.location
            results.append(GrepMatch(
                url: url,
                relativePath: relativePath,
                line: line + 1,
                column: column + 1,
                range: match.range,
                preview: ns.substring(with: previewRange),
                previewRange: NSRange(
                    location: column,
                    length: min(match.range.length, max(0, previewRange.length - column))
                ),
                encoding: encoding
            ))
        }
        return results
    }
}
