import Foundation

/// How a pattern is interpreted (ROADMAP.md section 9.4).
public enum SearchMode: String, Codable, Sendable, Equatable, CaseIterable {
    case literal
    case regularExpression
}

/// Where a search applies. `.selection` carries the range explicitly so
/// `SearchEngine` stays a pure function of (text, query) — it never needs
/// to ask a text view what is selected.
public enum SearchScope: Sendable, Equatable {
    case document
    case selection(NSRange)
}

/// One search request. Find, Select All Matches, Replace, Replace All, and
/// Grep all describe their work with this same type so their option
/// semantics cannot drift apart (ROADMAP.md section 11.1).
public struct SearchQuery: Sendable, Equatable {
    public var pattern: String
    public var replacement: String?
    public var mode: SearchMode
    public var isCaseSensitive: Bool
    public var wholeWord: Bool
    public var wraps: Bool
    public var scope: SearchScope

    public init(
        pattern: String,
        replacement: String? = nil,
        mode: SearchMode = .literal,
        isCaseSensitive: Bool = false,
        wholeWord: Bool = false,
        wraps: Bool = true,
        scope: SearchScope = .document
    ) {
        self.pattern = pattern
        self.replacement = replacement
        self.mode = mode
        self.isCaseSensitive = isCaseSensitive
        self.wholeWord = wholeWord
        self.wraps = wraps
        self.scope = scope
    }
}

/// One match, with its capture groups. `captureGroups[0]` is always the
/// whole match, mirroring `NSTextCheckingResult`'s numbering so `$1` in a
/// replacement template means `captureGroups[1]`.
public struct SearchMatch: Sendable, Equatable {
    public let range: NSRange
    public let captureGroups: [NSRange]

    public init(range: NSRange, captureGroups: [NSRange]) {
        self.range = range
        self.captureGroups = captureGroups
    }
}

public enum SearchError: Error, Sendable, Equatable {
    /// The pattern is not valid in the requested mode. `reason` is the
    /// underlying ICU diagnostic, shown to the user as-is so an invalid
    /// regex explains itself rather than silently finding nothing.
    case invalidPattern(pattern: String, reason: String)
}

extension SearchError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidPattern(_, let reason):
            return reason
        }
    }
}

/// The outcome of a Replace All (ROADMAP.md M3-03). Carries the finished
/// text plus enough detail for the caller to report a count and place a
/// sensible selection afterwards.
public struct SearchReplaceResult: Sendable, Equatable {
    public let text: String
    public let replacementCount: Int
    /// The ranges the replacements occupy *in `text`*, in document order.
    public let replacedRanges: [NSRange]

    public init(text: String, replacementCount: Int, replacedRanges: [NSRange]) {
        self.text = text
        self.replacementCount = replacementCount
        self.replacedRanges = replacedRanges
    }
}
