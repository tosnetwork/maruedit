import Foundation

/// Renders Grep results as plain text for Copy and Save (ROADMAP.md
/// M3-06). Kept out of the view so the exact output is testable and so
/// "what gets copied" and "what gets saved" cannot drift apart.
///
/// The line format is the conventional `path:line:column: text`, which
/// other tools — including MaruEdit's own Output Pane navigation in
/// M6-06 — already know how to parse.
public enum GrepResultFormatter {

    public static func line(for match: GrepMatch) -> String {
        "\(match.relativePath):\(match.line):\(match.column): \(match.preview)"
    }

    public static func plainText(matches: [GrepMatch], summary: GrepSummary, pattern: String) -> String {
        var lines: [String] = ["Search for: \(pattern)"]
        lines.append(contentsOf: matches.map(line(for:)))
        lines.append("")
        lines.append(describe(summary))
        return lines.joined(separator: "\n") + "\n"
    }

    public static func describe(_ summary: GrepSummary) -> String {
        if let error = summary.errorMessage { return error }
        var text = "\(summary.matchCount) "
            + (summary.matchCount == 1 ? "match" : "matches")
            + " in \(summary.matchedFiles) of \(summary.scannedFiles) "
            + (summary.scannedFiles == 1 ? "file" : "files")
        if summary.skippedFiles > 0 {
            text += ", \(summary.skippedFiles) skipped"
        }
        if summary.wasCancelled {
            text += " (cancelled)"
        }
        return text
    }
}
