import Foundation

/// A concrete, applicable line-ending style — as opposed to
/// `LineEndingState`, which also has to represent "mixed" and "no line
/// breaks at all" states that aren't a single style you can apply.
public enum LineEndingKind: String, Codable, Sendable, Equatable, CaseIterable {
    case lf
    case crlf
    case cr

    public var displayName: String {
        switch self {
        case .lf:   return "LF (Unix)"
        case .crlf: return "CRLF (Windows)"
        case .cr:   return "CR (Classic Mac)"
        }
    }

    var separator: String {
        switch self {
        case .lf:   return "\n"
        case .crlf: return "\r\n"
        case .cr:   return "\r"
        }
    }
}

public struct LineEndingSummary: Sendable, Equatable {
    public let lfCount: Int
    public let crlfCount: Int
    public let crCount: Int
}

/// What `LineEndingDetector` found in a piece of text. Unlike
/// `LineEndingKind`, this can represent "the file has no line breaks at
/// all" (`.none`) and "the file mixes styles" (`.mixed`) — states a
/// single applicable style can't express, per ROADMAP.md section 9.1.
public enum LineEndingState: Sendable, Equatable {
    case lf
    case crlf
    case cr
    case mixed(summary: LineEndingSummary)
    case none

    public var displayName: String {
        switch self {
        case .lf:   return "LF"
        case .crlf: return "CRLF"
        case .cr:   return "CR"
        case .mixed: return "Mixed"
        case .none: return "—"
        }
    }
}

/// Detects, normalizes, and re-applies line-ending styles, per
/// ROADMAP.md section 10.3: the in-memory editing buffer always uses
/// `\n` only, while `LineEndingState` metadata preserves what the file
/// on disk actually used, so a save can restore it — instead of
/// silently normalizing every file to LF the moment it's opened.
public enum LineEndingDetector {
    /// Detects the line-ending style(s) present in `text`, scanning for
    /// `\r\n`, lone `\n`, and lone `\r` (checking the two-character
    /// sequence first so a `\r\n` pair is never double-counted as a
    /// separate `\r` and `\n`).
    public static func detect(_ text: String) -> LineEndingState {
        var lf = 0, crlf = 0, cr = 0
        let scalars = Array(text.unicodeScalars)
        var i = 0
        while i < scalars.count {
            let c = scalars[i]
            if c == "\r" {
                if i + 1 < scalars.count, scalars[i + 1] == "\n" {
                    crlf += 1
                    i += 2
                    continue
                }
                cr += 1
            } else if c == "\n" {
                lf += 1
            }
            i += 1
        }

        let kindsPresent = [lf > 0, crlf > 0, cr > 0].filter { $0 }.count
        switch kindsPresent {
        case 0: return .none
        case 1:
            if lf > 0 { return .lf }
            if crlf > 0 { return .crlf }
            return .cr
        default:
            return .mixed(summary: LineEndingSummary(lfCount: lf, crlfCount: crlf, crCount: cr))
        }
    }

    /// Normalizes any mix of `\r\n`, `\r`, and `\n` to `\n` only, for the
    /// in-memory editing buffer. `\r\n` is replaced first so it isn't
    /// left as a dangling lone `\r` + `\n` pair.
    public static func normalize(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }

    /// Converts `\n`-normalized `text` to use `kind`'s separator
    /// throughout, for writing back to disk.
    public static func applying(_ kind: LineEndingKind, to text: String) -> String {
        guard kind != .lf else { return text }
        return text.replacingOccurrences(of: "\n", with: kind.separator)
    }
}
