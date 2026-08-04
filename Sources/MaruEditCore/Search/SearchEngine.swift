import Foundation

/// The single matching implementation behind Find, Find Previous, Select
/// All Matches, Replace, Replace All, and Grep (ROADMAP.md section 11.1).
///
/// Everything ultimately funnels through `matches(for:in:)`, so "the next
/// match" and "the set Replace All will touch" can never disagree — the
/// inconsistency M3-01's acceptance criterion is written against.
///
/// Both modes compile to `NSRegularExpression` (ADR: ROADMAP.md 11.2 fixes
/// ICU/Apple regex syntax for 1.0); literal patterns are escaped first.
/// Using one engine for both is what keeps option semantics identical
/// across modes rather than one path using `NSString.range(of:)` and the
/// other using regex.
///
/// Pure and thread-safe: it holds no state and touches no UI, so Grep can
/// call it from a background task while the Find Bar calls it on the main
/// thread.
public enum SearchEngine {

    // MARK: - Compilation

    /// Builds the regex for `query`. Exposed so callers that run many
    /// searches with one query (Grep across thousands of files) can
    /// compile once instead of per file.
    public static func compile(_ query: SearchQuery) throws -> NSRegularExpression {
        let pattern: String
        switch query.mode {
        case .literal:
            pattern = NSRegularExpression.escapedPattern(for: query.pattern)
        case .regularExpression:
            pattern = query.pattern
        }

        var options: NSRegularExpression.Options = []
        if !query.isCaseSensitive { options.insert(.caseInsensitive) }
        // `^`/`$` match line boundaries, not just the whole-string
        // boundaries NSRegularExpression defaults to. That is what users
        // of a line-oriented text editor mean by those anchors, and it
        // makes a per-document regex behave the same as the same regex run
        // per line by Grep.
        if query.mode == .regularExpression { options.insert(.anchorsMatchLines) }

        do {
            return try NSRegularExpression(pattern: pattern, options: options)
        } catch {
            throw SearchError.invalidPattern(
                pattern: query.pattern,
                reason: (error as NSError).localizedDescription
            )
        }
    }

    /// Throws if `query` cannot be compiled. The Find Bar calls this to
    /// show an invalid-regex diagnostic without discarding what the user
    /// typed (ROADMAP.md 11.2 item 4).
    public static func validate(_ query: SearchQuery) throws {
        guard !query.pattern.isEmpty else { return }
        _ = try compile(query)
    }

    // MARK: - Matching

    /// Every match of `query` in `text`, in document order.
    ///
    /// An empty pattern yields no matches rather than an error: the Find
    /// Bar searches on every keystroke, and an empty field is a normal
    /// state, not a user mistake.
    public static func matches(for query: SearchQuery, in text: String) throws -> [SearchMatch] {
        guard !query.pattern.isEmpty else { return [] }
        let regex = try compile(query)
        return matches(for: query, in: text, using: regex)
    }

    /// Match with a pre-compiled regex, for callers reusing one query
    /// across many strings.
    public static func matches(
        for query: SearchQuery,
        in text: String,
        using regex: NSRegularExpression
    ) -> [SearchMatch] {
        guard !query.pattern.isEmpty else { return [] }
        let ns = text as NSString
        let scope = resolvedScope(query.scope, in: ns)

        // One `matches(in:)` sweep rather than a hand-rolled
        // firstMatch-and-advance loop: ICU already guarantees progress past
        // zero-length matches (ROADMAP.md 11.2 item 5), and re-searching a
        // shrinking sub-range would silently change what `^` and `$` mean,
        // since NSRegularExpression treats a search range's edges as
        // anchoring bounds.
        let results = regex.matches(in: text, options: [], range: scope)
        return results.compactMap { result in
            guard !query.wholeWord || isWholeWord(result.range, in: ns) else { return nil }
            return SearchMatch(range: result.range, captureGroups: captureGroups(of: result))
        }
    }

    /// The first match at or after `location`, wrapping to the start of
    /// the scope when `query.wraps` is set and nothing follows.
    ///
    /// Callers looking for "the match after the current selection" pass
    /// `NSMaxRange(selection)`, so the currently-selected match is not
    /// returned again.
    public static func nextMatch(
        for query: SearchQuery,
        in text: String,
        from location: Int
    ) throws -> SearchMatch? {
        let all = try matches(for: query, in: text)
        guard !all.isEmpty else { return nil }
        if let following = all.first(where: { $0.range.location >= location }) { return following }
        return query.wraps ? all.first : nil
    }

    /// The last match ending at or before `location`, wrapping to the end
    /// of the scope when `query.wraps` is set and nothing precedes it.
    ///
    /// Callers looking for "the match before the current selection" pass
    /// `selection.location`.
    public static func previousMatch(
        for query: SearchQuery,
        in text: String,
        from location: Int
    ) throws -> SearchMatch? {
        let all = try matches(for: query, in: text)
        guard !all.isEmpty else { return nil }
        if let preceding = all.last(where: { NSMaxRange($0.range) <= location }) { return preceding }
        return query.wraps ? all.last : nil
    }

    // MARK: - Replacement

    /// The text `match` should be replaced with.
    ///
    /// In regex mode this expands `$1`-style references against the
    /// match's capture groups (`\$` escapes a literal dollar sign, per
    /// `NSRegularExpression` template rules). In literal mode the
    /// replacement is inserted verbatim — a user replacing with `$1` in a
    /// literal search means those two characters.
    public static func replacement(
        for match: SearchMatch,
        in text: String,
        query: SearchQuery
    ) -> String {
        let template = query.replacement ?? ""
        guard query.mode == .regularExpression else { return template }
        return expand(template: template, groups: match.captureGroups, in: text as NSString)
    }

    /// Replaces every match of `query` in `text`.
    ///
    /// Returns the whole resulting string rather than mutating in place so
    /// this stays pure and testable without AppKit; the caller decides how
    /// to apply it to a text storage and how to group Undo.
    public static func replacingAllMatches(
        of query: SearchQuery,
        in text: String
    ) throws -> SearchReplaceResult {
        let found = try matches(for: query, in: text)
        guard !found.isEmpty else {
            return SearchReplaceResult(text: text, replacementCount: 0, replacedRanges: [])
        }

        let result = NSMutableString(string: text)
        var replacedRanges: [NSRange] = []
        var delta = 0

        // Applied lowest-to-highest with a running offset (rather than
        // highest-to-lowest) because the reported ranges must describe the
        // *new* text, which is what a caller re-selects afterwards.
        for match in found {
            let replacementText = replacement(for: match, in: text, query: query)
            let adjusted = NSRange(location: match.range.location + delta, length: match.range.length)
            result.replaceCharacters(in: adjusted, with: replacementText)
            let replacementLength = (replacementText as NSString).length
            replacedRanges.append(NSRange(location: adjusted.location, length: replacementLength))
            delta += replacementLength - match.range.length
        }

        return SearchReplaceResult(
            text: result as String,
            replacementCount: found.count,
            replacedRanges: replacedRanges
        )
    }

    // MARK: - Helpers

    private static func resolvedScope(_ scope: SearchScope, in ns: NSString) -> NSRange {
        switch scope {
        case .document:
            return NSRange(location: 0, length: ns.length)
        case .selection(let range):
            let location = max(0, min(range.location, ns.length))
            let length = max(0, min(range.length, ns.length - location))
            return NSRange(location: location, length: length)
        }
    }

    private static func captureGroups(of result: NSTextCheckingResult) -> [NSRange] {
        (0..<result.numberOfRanges).map { result.range(at: $0) }
    }

    /// Word characters for whole-word matching: Unicode alphanumerics plus
    /// `_`, the same set `\w` covers.
    private static let wordCharacters: CharacterSet = {
        var set = CharacterSet.alphanumerics
        set.insert(charactersIn: "_")
        return set
    }()

    /// Implemented as a boundary check around the match instead of
    /// wrapping the pattern in `\b…\b`, because `\b` silently never matches
    /// when the pattern itself starts or ends with a non-word character —
    /// a whole-word search for `(x)` would find nothing at all. Each edge
    /// is only constrained when the matched text's own character there is
    /// a word character, so a match's punctuation edges impose no
    /// requirement on their neighbors.
    private static func isWholeWord(_ range: NSRange, in ns: NSString) -> Bool {
        guard range.length > 0 else { return true }
        let end = NSMaxRange(range)
        if isWordCharacter(ns.character(at: range.location)),
           range.location > 0,
           isWordCharacter(ns.character(at: range.location - 1)) {
            return false
        }
        if isWordCharacter(ns.character(at: end - 1)),
           end < ns.length,
           isWordCharacter(ns.character(at: end)) {
            return false
        }
        return true
    }

    private static func isWordCharacter(_ unit: unichar) -> Bool {
        guard let scalar = Unicode.Scalar(UInt32(unit)) else { return false }
        return wordCharacters.contains(scalar)
    }

    /// Expands `$0`…`$n` and `${n}` references, honoring `\$` and `\\`
    /// escapes. Done by hand rather than via
    /// `NSRegularExpression.replacementString(for:)` so replacement works
    /// off a `SearchMatch` value — Grep Replace (M6-07) builds previews
    /// from stored matches, long after the original
    /// `NSTextCheckingResult` is gone.
    private static func expand(template: String, groups: [NSRange], in ns: NSString) -> String {
        var output = ""
        var index = template.startIndex

        while index < template.endIndex {
            let character = template[index]

            if character == "\\" {
                let next = template.index(after: index)
                if next < template.endIndex {
                    // `\$`, `\\`, `\n`, `\t` are the escapes users expect;
                    // anything else keeps both characters so an accidental
                    // backslash is not silently eaten.
                    switch template[next] {
                    case "$": output.append("$")
                    case "\\": output.append("\\")
                    case "n": output.append("\n")
                    case "t": output.append("\t")
                    default: output.append(character); output.append(template[next])
                    }
                    index = template.index(after: next)
                } else {
                    output.append(character)
                    index = next
                }
                continue
            }

            if character == "$" {
                var cursor = template.index(after: index)
                var braced = false
                if cursor < template.endIndex, template[cursor] == "{" {
                    braced = true
                    cursor = template.index(after: cursor)
                }
                var digits = ""
                while cursor < template.endIndex, template[cursor].isNumber {
                    digits.append(template[cursor])
                    cursor = template.index(after: cursor)
                }
                if braced {
                    guard cursor < template.endIndex, template[cursor] == "}" else {
                        output.append(character)
                        index = template.index(after: index)
                        continue
                    }
                    cursor = template.index(after: cursor)
                }
                if let groupNumber = Int(digits) {
                    if groupNumber < groups.count, groups[groupNumber].location != NSNotFound {
                        output.append(ns.substring(with: groups[groupNumber]))
                    }
                    // A reference to a group that did not participate
                    // expands to nothing, matching ICU behavior.
                    index = cursor
                    continue
                }
                output.append(character)
                index = template.index(after: index)
                continue
            }

            output.append(character)
            index = template.index(after: index)
        }
        return output
    }
}
