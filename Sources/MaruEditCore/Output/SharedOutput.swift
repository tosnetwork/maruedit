import Foundation

public enum OutputChannel: String, Sendable, Codable {
    case grep, macro, standardOutput, standardError, system
}

public enum OutputSeverity: String, Sendable, Codable {
    case info, warning, error
}

public struct OutputLocation: Equatable, Sendable {
    public let url: URL
    public let line: Int
    public let column: Int
    public init(url: URL, line: Int, column: Int = 1) {
        self.url = url; self.line = max(1, line); self.column = max(1, column)
    }
}

public struct OutputEntry: Equatable, Sendable {
    public let sequence: UInt64
    public let timestamp: Date
    public let channel: OutputChannel
    public let severity: OutputSeverity
    public let message: String
    public let location: OutputLocation?
}

/// Bounded, value-only storage shared by Grep, macros, and processes.
/// Oldest records are discarded first and a warning record makes the loss visible.
public struct SharedOutputBuffer: Sendable {
    public let maximumEntries: Int
    public let maximumUTF8Bytes: Int
    public private(set) var entries: [OutputEntry] = []
    public private(set) var didTruncate = false
    public var currentUTF8Bytes: Int { byteCount }
    private var nextSequence: UInt64 = 1
    private var byteCount = 0

    public init(maximumEntries: Int = 10_000, maximumUTF8Bytes: Int = 4 * 1_024 * 1_024) {
        self.maximumEntries = max(2, maximumEntries)
        self.maximumUTF8Bytes = max(256, maximumUTF8Bytes)
    }

    @discardableResult
    public mutating func append(
        _ message: String, channel: OutputChannel, severity: OutputSeverity = .info,
        timestamp: Date = Date(), location: OutputLocation? = nil
    ) -> OutputEntry {
        let entry = OutputEntry(sequence: nextSequence, timestamp: timestamp, channel: channel,
                                severity: severity, message: bounded(message), location: location)
        nextSequence &+= 1; entries.append(entry); byteCount += entry.message.utf8.count
        enforceLimits(timestamp: timestamp)
        return entry
    }

    public mutating func clear() {
        entries.removeAll(keepingCapacity: true); byteCount = 0; didTruncate = false
    }

    private func bounded(_ message: String) -> String {
        guard message.utf8.count > maximumUTF8Bytes else { return message }
        var result = ""
        var used = 0
        for character in message {
            let bytes = String(character).utf8.count
            guard used + bytes <= maximumUTF8Bytes / 2 else { break }
            result.append(character); used += bytes
        }
        return result + "…"
    }

    private mutating func enforceLimits(timestamp: Date) {
        var removed = false
        while entries.count > maximumEntries || byteCount > maximumUTF8Bytes {
            byteCount -= entries.removeFirst().message.utf8.count; removed = true
        }
        guard removed else { return }
        didTruncate = true
        if entries.first?.channel != .system {
            let warning = OutputEntry(
                sequence: nextSequence, timestamp: timestamp, channel: .system, severity: .warning,
                message: "Earlier output was discarded because the output limit was reached.", location: nil)
            nextSequence &+= 1; entries.insert(warning, at: 0); byteCount += warning.message.utf8.count
            while entries.count > maximumEntries || byteCount > maximumUTF8Bytes {
                guard entries.count > 1 else { break }
                byteCount -= entries.remove(at: 1).message.utf8.count
            }
        }
    }
}

public enum OutputLocationParser {
    /// Recognizes `path:line`, `path:line:column`, and optional message text.
    public static func parse(_ text: String, relativeTo baseURL: URL? = nil) -> OutputLocation? {
        let pattern = #"^(.+?):([1-9][0-9]*)(?::([1-9][0-9]*))?(?::(?:\s|$).*)?$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let pathRange = Range(match.range(at: 1), in: text),
              let lineRange = Range(match.range(at: 2), in: text),
              let line = Int(text[lineRange]) else { return nil }
        let path = String(text[pathRange])
        let url = path.hasPrefix("/") ? URL(fileURLWithPath: path)
            : baseURL?.appendingPathComponent(path) ?? URL(fileURLWithPath: path)
        var column = 1
        if match.range(at: 3).location != NSNotFound,
           let range = Range(match.range(at: 3), in: text) { column = Int(text[range]) ?? 1 }
        return OutputLocation(url: url, line: line, column: column)
    }
}
