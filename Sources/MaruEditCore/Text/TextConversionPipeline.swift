import Foundation

public struct TextConversionStep: Codable, Equatable, Sendable {
    public var moduleID: String
    public var parameters: [String: String]

    public init(moduleID: String, parameters: [String: String] = [:]) {
        self.moduleID = moduleID
        self.parameters = parameters
    }
}

public struct TextConversionPreset: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var steps: [TextConversionStep]

    public init(id: UUID = UUID(), name: String, steps: [TextConversionStep]) {
        self.id = id
        self.name = name
        self.steps = steps
    }
}

public struct TextConversionModule: Sendable {
    public let id: String
    public let title: String
    private let operation: @Sendable (String, [String: String]) throws -> String

    public init(
        id: String, title: String,
        operation: @escaping @Sendable (String, [String: String]) throws -> String
    ) {
        self.id = id
        self.title = title
        self.operation = operation
    }

    public func convert(_ text: String, parameters: [String: String] = [:]) throws -> String {
        try operation(text, parameters)
    }
}

public enum TextConversionError: LocalizedError, Equatable {
    case unknownModule(String)
    case invalidRegularExpression(String)
    case emptySearchText

    public var errorDescription: String? {
        switch self {
        case .unknownModule(let id): return "Unknown text conversion module: \(id)"
        case .invalidRegularExpression(let pattern): return "Invalid regular expression: \(pattern)"
        case .emptySearchText: return "Literal replacement requires non-empty search text."
        }
    }
}

/// Ordered conversion registry used by both built-in commands and the
/// OldMaru-compatible conversion-dialog preset chain.
public struct TextConversionRegistry: Sendable {
    private var modules: [String: TextConversionModule]

    public init(includeBuiltIns: Bool = true) {
        modules = [:]
        if includeBuiltIns { Self.builtIns.forEach { modules[$0.id] = $0 } }
    }

    public mutating func register(_ module: TextConversionModule) { modules[module.id] = module }
    public var availableModules: [TextConversionModule] { modules.values.sorted { $0.title < $1.title } }

    public func apply(_ steps: [TextConversionStep], to text: String) throws -> String {
        try steps.reduce(text) { value, step in
            guard let module = modules[step.moduleID] else { throw TextConversionError.unknownModule(step.moduleID) }
            return try module.convert(value, parameters: step.parameters)
        }
    }

    public static let defaultPresets: [TextConversionPreset] = [
        .init(name: "Normalize Japanese", steps: [
            .init(moduleID: "width.full.katakana"), .init(moduleID: "kana.hiragana"),
        ]),
        .init(name: "Normalize Source Indentation", steps: [
            .init(moduleID: "whitespace.tabsToSpaces", parameters: ["width": "4"]),
            .init(moduleID: "whitespace.trimTrailing"),
        ]),
        .init(name: "Full-Width Alphanumerics", steps: [.init(moduleID: "width.full.alphanumeric")]),
    ]

    private static let builtIns: [TextConversionModule] = [
        .init(id: "case.uppercase", title: "Uppercase") { text, _ in text.uppercased() },
        .init(id: "case.lowercase", title: "Lowercase") { text, _ in text.lowercased() },
        .init(id: "case.title", title: "Title Case") { text, _ in text.capitalized },
        .init(id: "width.half", title: "Half-Width") { text, _ in text.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? text },
        .init(id: "width.full", title: "Full-Width") { text, _ in text.applyingTransform(.fullwidthToHalfwidth, reverse: true) ?? text },
        .init(id: "width.half.alphanumeric", title: "Alphanumerics to Half-Width") { text, _ in selectiveAlphanumericWidth(text, full: false) },
        .init(id: "width.full.alphanumeric", title: "Alphanumerics to Full-Width") { text, _ in selectiveAlphanumericWidth(text, full: true) },
        .init(id: "width.half.katakana", title: "Katakana to Half-Width") { text, _ in selectiveKatakanaWidth(text, full: false) },
        .init(id: "width.full.katakana", title: "Katakana to Full-Width") { text, _ in selectiveKatakanaWidth(text, full: true) },
        .init(id: "kana.hiragana", title: "Hiragana") { text, _ in text.applyingTransform(.hiraganaToKatakana, reverse: true) ?? text },
        .init(id: "kana.katakana", title: "Katakana") { text, _ in text.applyingTransform(.hiraganaToKatakana, reverse: false) ?? text },
        .init(id: "whitespace.tabsToSpaces", title: "Tabs to Spaces") { text, parameters in
            expandTabs(text, width: max(1, Int(parameters["width"] ?? "4") ?? 4))
        },
        .init(id: "whitespace.leadingSpacesToTabs", title: "Leading Spaces to Tabs") { text, parameters in
            leadingSpacesToTabs(text, width: max(1, Int(parameters["width"] ?? "4") ?? 4))
        },
        .init(id: "whitespace.trimTrailing", title: "Trim Trailing Whitespace") { text, _ in
            text.replacingOccurrences(of: #"[ \t]+(?=\r?$)"#, with: "", options: .regularExpression)
        },
        .init(id: "replace.literal", title: "Literal Replacement") { text, parameters in
            guard let search = parameters["search"], !search.isEmpty else { throw TextConversionError.emptySearchText }
            return text.replacingOccurrences(of: search, with: parameters["replacement"] ?? "")
        },
        .init(id: "replace.regex", title: "Regular Expression Replacement") { text, parameters in
            let pattern = parameters["pattern"] ?? ""
            guard let regex = try? NSRegularExpression(pattern: pattern) else {
                throw TextConversionError.invalidRegularExpression(pattern)
            }
            return regex.stringByReplacingMatches(
                in: text, range: NSRange(text.startIndex..., in: text),
                withTemplate: parameters["replacement"] ?? "")
        },
    ]
}

public final class TextConversionPresetStore: @unchecked Sendable {
    private let defaults: UserDefaults
    private let key: String
    private let lock = NSLock()

    public init(defaults: UserDefaults = .standard, key: String = "MaruEditTextConversionPresets") {
        self.defaults = defaults; self.key = key
    }

    public func load() -> [TextConversionPreset] {
        lock.lock(); defer { lock.unlock() }
        guard let data = defaults.data(forKey: key),
              let values = try? JSONDecoder().decode([TextConversionPreset].self, from: data) else { return [] }
        return values.filter { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !$0.steps.isEmpty }
    }

    public func save(_ presets: [TextConversionPreset]) {
        lock.lock(); defer { lock.unlock() }
        let normalized = presets.filter { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !$0.steps.isEmpty }
        if let data = try? JSONEncoder().encode(normalized) { defaults.set(data, forKey: key) }
    }
}

private func selectiveAlphanumericWidth(_ text: String, full: Bool) -> String {
    var output = ""
    for scalar in text.unicodeScalars {
        let value = scalar.value
        if full, (0x21...0x7E).contains(value), let mapped = UnicodeScalar(value + 0xFEE0) { output.unicodeScalars.append(mapped) }
        else if full, value == 0x20 { output.unicodeScalars.append("　") }
        else if !full, (0xFF01...0xFF5E).contains(value), let mapped = UnicodeScalar(value - 0xFEE0) { output.unicodeScalars.append(mapped) }
        else if !full, value == 0x3000 { output.unicodeScalars.append(" ") }
        else { output.unicodeScalars.append(scalar) }
    }
    return output
}

private func selectiveKatakanaWidth(_ text: String, full: Bool) -> String {
    var output = ""
    var buffer = ""
    func flush() {
        guard !buffer.isEmpty else { return }
        output += buffer.applyingTransform(.fullwidthToHalfwidth, reverse: full) ?? buffer
        buffer = ""
    }
    for character in text {
        let isKatakana = character.unicodeScalars.allSatisfy {
            (0x30A0...0x30FF).contains($0.value) || (0xFF65...0xFF9F).contains($0.value) || (0x3099...0x309C).contains($0.value)
        }
        if isKatakana { buffer.append(character) } else { flush(); output.append(character) }
    }
    flush(); return output
}

private func expandTabs(_ text: String, width: Int) -> String {
    text.components(separatedBy: "\n").map { line in
        var result = "", column = 0
        for character in line {
            if character == "\t" {
                let count = width - column % width
                result += String(repeating: " ", count: count); column += count
            } else { result.append(character); column += 1 }
        }
        return result
    }.joined(separator: "\n")
}

private func leadingSpacesToTabs(_ text: String, width: Int) -> String {
    text.components(separatedBy: "\n").map { line in
        let count = line.prefix { $0 == " " }.count
        return String(repeating: "\t", count: count / width)
            + String(repeating: " ", count: count % width) + line.dropFirst(count)
    }.joined(separator: "\n")
}
