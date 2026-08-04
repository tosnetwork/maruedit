import Foundation

/// A shell-style path filter for Grep's include/exclude lists.
///
/// Translated to `NSRegularExpression` rather than delegating to
/// `fnmatch(3)`, which has no `**` and whose `FNM_PATHNAME` behavior would
/// force a separate pass to make `*.swift` match at any depth.
///
/// Supported syntax:
/// - `*` — any run of characters except `/`
/// - `**` — any run of characters including `/`
/// - `?` — one character except `/`
/// - `[abc]`, `[a-z]`, `[!abc]` — character classes
///
/// A pattern containing no `/` is matched against the last path component
/// alone, which is what makes `*.swift` and `node_modules` behave the way
/// people expect. Patterns with a `/` are matched against the path
/// relative to the search root.
public struct GlobPattern: Sendable, Equatable {
    public let pattern: String
    private let regex: NSRegularExpression?
    private let matchesFullPath: Bool

    public init(_ pattern: String) {
        self.pattern = pattern
        self.matchesFullPath = pattern.contains("/")
        self.regex = try? NSRegularExpression(
            pattern: "^" + Self.regexBody(for: pattern) + "$",
            options: []
        )
    }

    /// Whether this pattern matches `path`, expressed relative to the
    /// search root. An unparseable pattern matches nothing rather than
    /// everything — a bad filter must not silently widen the search.
    public func matches(relativePath path: String) -> Bool {
        guard let regex = regex else { return false }
        let candidate = matchesFullPath ? path : (path as NSString).lastPathComponent
        let range = NSRange(location: 0, length: (candidate as NSString).length)
        return regex.firstMatch(in: candidate, options: [], range: range) != nil
    }

    private static func regexBody(for pattern: String) -> String {
        var output = ""
        let characters = Array(pattern)
        var index = 0

        while index < characters.count {
            let character = characters[index]
            switch character {
            case "*":
                if index + 1 < characters.count, characters[index + 1] == "*" {
                    output += ".*"
                    index += 2
                    // `**/` should also match zero directories, so `**/x`
                    // matches a plain `x` at the root.
                    if index < characters.count, characters[index] == "/" {
                        output += "(?:/)?"
                        index += 1
                    }
                    continue
                }
                output += "[^/]*"
            case "?":
                output += "[^/]"
            case "[":
                var classBody = "["
                var cursor = index + 1
                if cursor < characters.count, characters[cursor] == "!" {
                    classBody += "^"
                    cursor += 1
                }
                var closed = false
                while cursor < characters.count {
                    let inner = characters[cursor]
                    if inner == "]" { closed = true; break }
                    classBody += inner == "\\" ? "\\\\" : String(inner)
                    cursor += 1
                }
                if closed {
                    output += classBody + "]"
                    index = cursor + 1
                    continue
                }
                // An unterminated `[` is a literal bracket.
                output += "\\["
            default:
                output += NSRegularExpression.escapedPattern(for: String(character))
            }
            index += 1
        }
        return output
    }
}

extension Array where Element == GlobPattern {
    /// The first pattern in this list matching `path`, if any.
    public func firstMatch(relativePath path: String) -> GlobPattern? {
        first { $0.matches(relativePath: path) }
    }
}
