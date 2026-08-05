import Foundation

public enum OutlineSymbolKind: String, Codable, Sendable {
    case type, function, method, property, heading, section
}

public struct OutlineSymbol: Equatable, Sendable, Identifiable {
    public let kind: OutlineSymbolKind
    public let title: String
    public let line: Int
    public let utf16Range: NSRange
    public let level: Int

    public var id: String { "\(line):\(utf16Range.location):\(kind.rawValue):\(title)" }
}

public struct OutlineRule: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var pattern: String
    public var kind: OutlineSymbolKind
    public var titleCaptureGroup: Int
    public var fixedLevel: Int?

    public init(
        id: String = UUID().uuidString, pattern: String,
        kind: OutlineSymbolKind = .section, titleCaptureGroup: Int = 1,
        fixedLevel: Int? = nil
    ) {
        self.id = id
        self.pattern = pattern
        self.kind = kind
        self.titleCaptureGroup = titleCaptureGroup
        self.fixedLevel = fixedLevel
    }
}

/// Foundation-only outline index. Edits preserve the unchanged prefix and
/// rescan from the first touched logical line, avoiding a full-document pass
/// for the common case of edits near the end of a document.
public struct OutlineModel: Sendable, Equatable {
    public private(set) var text: String
    public private(set) var language: Language
    public private(set) var symbols: [OutlineSymbol]
    public private(set) var customRules: [OutlineRule]

    public init(text: String, language: Language, customRules: [OutlineRule] = []) {
        self.text = text
        self.language = language
        self.customRules = Array(customRules.prefix(Self.maximumCustomRuleCount))
        symbols = Self.scan(
            text: text, language: language, customRules: self.customRules,
            startingAtLine: 0, baseOffset: 0)
    }

    public mutating func replaceText(
        _ text: String, language: Language, customRules: [OutlineRule]? = nil
    ) {
        self.text = text
        self.language = language
        if let customRules {
            self.customRules = Array(customRules.prefix(Self.maximumCustomRuleCount))
        }
        symbols = Self.scan(
            text: text, language: language, customRules: self.customRules,
            startingAtLine: 0, baseOffset: 0)
    }

    public mutating func applyEdit(range: NSRange, replacement: String) {
        let old = text as NSString
        guard range.location >= 0, range.length >= 0, NSMaxRange(range) <= old.length else { return }
        let oldIndex = LineIndex(text)
        let firstLine = oldIndex.line(atUTF16Offset: range.location)
        let prefixOffset = oldIndex.utf16Offset(forLine: firstLine) ?? 0
        text = old.replacingCharacters(in: range, with: replacement)
        let newNSString = text as NSString
        let suffix = newNSString.substring(from: min(prefixOffset, newNSString.length))
        symbols.removeAll { $0.line >= firstLine }
        symbols.append(contentsOf: Self.scan(
            text: suffix, language: language, customRules: customRules,
            startingAtLine: firstLine, baseOffset: prefixOffset))
    }

    private struct Rule {
        let kind: OutlineSymbolKind
        let pattern: String
        let titleGroup: Int
        let fixedLevel: Int?
    }

    private static func scan(
        text: String, language: Language, customRules: [OutlineRule],
        startingAtLine: Int, baseOffset: Int
    ) -> [OutlineSymbol] {
        let rules = customRules.prefix(maximumCustomRuleCount).map {
            Rule(kind: $0.kind, pattern: $0.pattern,
                 titleGroup: max(0, $0.titleCaptureGroup), fixedLevel: $0.fixedLevel)
        } + rules(for: language)
        guard !rules.isEmpty else { return [] }
        let compiled = rules.compactMap { rule in
            try? (rule, NSRegularExpression(pattern: rule.pattern))
        }
        var output: [OutlineSymbol] = []
        var offset = 0
        let ns = text as NSString
        var lineNumber = startingAtLine
        while offset <= ns.length {
            let remaining = NSRange(location: offset, length: ns.length - offset)
            let newline = ns.range(of: "\n", options: [], range: remaining)
            let end = newline.location == NSNotFound ? ns.length : newline.location
            let lineRange = NSRange(location: offset, length: end - offset)
            let line = ns.substring(with: lineRange)
            let lineNS = line as NSString
            if lineNS.length <= maximumScannedLineLength {
              for (rule, regex) in compiled {
                let full = NSRange(location: 0, length: lineNS.length)
                guard let match = regex.firstMatch(in: line, range: full),
                      rule.titleGroup < match.numberOfRanges else { continue }
                let capture = match.range(at: rule.titleGroup)
                guard capture.location != NSNotFound else { continue }
                let title = lineNS.substring(with: capture)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !title.isEmpty else { continue }
                let indentation = line.prefix { $0 == " " || $0 == "\t" }.count
                output.append(OutlineSymbol(
                    kind: rule.kind, title: title, line: lineNumber,
                    utf16Range: NSRange(
                        location: baseOffset + offset + capture.location,
                        length: capture.length),
                    level: rule.fixedLevel ?? indentation / 4))
                break
              }
            }
            if newline.location == NSNotFound { break }
            offset = end + 1
            lineNumber += 1
        }
        return output
    }

    public static let maximumCustomRuleCount = 64
    public static let maximumScannedLineLength = 16_384

    private static func rules(for language: Language) -> [Rule] {
        let name = #"([\p{L}_][\p{L}\p{N}_]*)"#
        switch language {
        case .swift:
            return [
                Rule(kind: .type, pattern: #"^\s*(?:public\s+|private\s+|internal\s+|open\s+|final\s+)*(?:class|struct|enum|protocol|actor|extension)\s+"# + name, titleGroup: 1, fixedLevel: nil),
                Rule(kind: .function, pattern: #"^\s*(?:[\w@]+\s+)*func\s+"# + name, titleGroup: 1, fixedLevel: nil),
                Rule(kind: .property, pattern: #"^\s*(?:[\w@]+\s+)*(?:let|var)\s+"# + name, titleGroup: 1, fixedLevel: nil),
            ]
        case .python:
            return [
                Rule(kind: .type, pattern: #"^\s*class\s+"# + name, titleGroup: 1, fixedLevel: nil),
                Rule(kind: .function, pattern: #"^\s*(?:async\s+)?def\s+"# + name, titleGroup: 1, fixedLevel: nil),
            ]
        case .javascript, .typescript:
            return [
                Rule(kind: .type, pattern: #"^\s*(?:export\s+)?(?:default\s+)?(?:class|interface|type|enum)\s+"# + name, titleGroup: 1, fixedLevel: nil),
                Rule(kind: .function, pattern: #"^\s*(?:export\s+)?(?:async\s+)?function\s+"# + name, titleGroup: 1, fixedLevel: nil),
                Rule(kind: .function, pattern: #"^\s*(?:export\s+)?(?:const|let|var)\s+"# + name + #"\s*=\s*(?:async\s*)?(?:\([^)]*\)|[\p{L}_][\p{L}\p{N}_]*)\s*=>"#, titleGroup: 1, fixedLevel: nil),
            ]
        case .markdown:
            return [1, 2, 3, 4, 5, 6].map { level in
                Rule(kind: .heading, pattern: "^\\s*#{\(level)}\\s+(.+?)\\s*#*\\s*$", titleGroup: 1, fixedLevel: level - 1)
            }
        case .html, .xml:
            return (1...6).map { level in
                Rule(kind: .heading, pattern: "(?i)^\\s*<h\(level)[^>]*>(.*?)</h\(level)>", titleGroup: 1, fixedLevel: level - 1)
            }
        case .rust:
            return cLikeRules(typeKeywords: "struct|enum|trait|impl", functionKeyword: "fn")
        case .go:
            return [
                Rule(kind: .type, pattern: #"^\s*type\s+"# + name, titleGroup: 1, fixedLevel: nil),
                Rule(kind: .function, pattern: #"^\s*func\s+(?:\([^)]*\)\s*)?"# + name, titleGroup: 1, fixedLevel: nil),
            ]
        case .c, .cpp, .java:
            return cLikeRules(typeKeywords: "class|struct|enum|interface", functionKeyword: nil)
        case .ruby:
            return [
                Rule(kind: .type, pattern: #"^\s*(?:class|module)\s+"# + name, titleGroup: 1, fixedLevel: nil),
                Rule(kind: .function, pattern: #"^\s*def\s+"# + name, titleGroup: 1, fixedLevel: nil),
            ]
        case .shell:
            return [Rule(kind: .function, pattern: #"^\s*(?:function\s+)?"# + name + #"\s*\(\)"#, titleGroup: 1, fixedLevel: nil)]
        case .css:
            return [Rule(kind: .section, pattern: #"^\s*([^@/][^{]+)\s*\{"#, titleGroup: 1, fixedLevel: nil)]
        case .sql:
            return [Rule(kind: .section, pattern: #"(?i)^\s*create\s+(?:or\s+replace\s+)?(?:table|view|procedure|function)\s+([\w.]+)"#, titleGroup: 1, fixedLevel: nil)]
        case .yaml, .toml:
            return [Rule(kind: .section, pattern: #"^\s*(?:\[+)?([\p{L}_][\p{L}\p{N}_.-]*)(?:\]+)?\s*[:=]"#, titleGroup: 1, fixedLevel: nil)]
        case .json, .plainText:
            return []
        }
    }

    private static func cLikeRules(typeKeywords: String, functionKeyword: String?) -> [Rule] {
        let name = #"([\p{L}_][\p{L}\p{N}_]*)"#
        var result = [Rule(kind: .type, pattern: "^\\s*(?:\(typeKeywords))\\s+" + name, titleGroup: 1, fixedLevel: nil)]
        if let functionKeyword {
            result.append(Rule(kind: .function, pattern: "^\\s*(?:pub(?:\\([^)]*\\))?\\s+)?(?:async\\s+)?\(functionKeyword)\\s+" + name, titleGroup: 1, fixedLevel: nil))
        } else {
            result.append(Rule(kind: .function, pattern: #"^\s*(?:[\w:<>,*&\[\]]+\s+)+"# + name + #"\s*\([^;]*\)\s*(?:\{|throws\b)"#, titleGroup: 1, fixedLevel: nil))
        }
        return result
    }
}
