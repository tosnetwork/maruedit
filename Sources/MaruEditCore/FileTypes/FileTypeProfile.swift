import Foundation

public enum IndentStyle: String, Codable, Sendable { case spaces, tabs }

public enum CompletionRanking: String, Codable, Sendable { case frequency, alphabetical }
public enum CompletionPresentation: String, Codable, Sendable { case list, tooltip, status }

public struct CompletionSettings: Codable, Equatable, Sendable {
    public var includesCurrentDocument: Bool
    public var dictionaryPaths: [String]
    public var ranking: CompletionRanking
    public var automatic: Bool
    public var presentation: CompletionPresentation

    public init(
        includesCurrentDocument: Bool = true, dictionaryPaths: [String] = [],
        ranking: CompletionRanking = .frequency, automatic: Bool = false,
        presentation: CompletionPresentation = .list
    ) {
        self.includesCurrentDocument = includesCurrentDocument
        self.dictionaryPaths = dictionaryPaths
        self.ranking = ranking
        self.automatic = automatic
        self.presentation = presentation
    }
}

public struct SpellingSettings: Codable, Equatable, Sendable {
    public var enabled: Bool
    public var automaticCorrection: Bool
    public init(enabled: Bool = false, automaticCorrection: Bool = false) {
        self.enabled = enabled; self.automaticCorrection = automaticCorrection
    }
}

public struct FileTypeSettings: Codable, Equatable, Sendable {
    public var tabWidth: Int
    public var indentWidth: Int
    public var indentStyle: IndentStyle
    public var wrapLines: Bool
    public var encoding: TextEncoding?
    public var syntax: Language
    public var lineComment: String?
    public var blockCommentStart: String?
    public var blockCommentEnd: String?
    /// Optional so profiles written before schema v2 decode without a custom
    /// migration pass. An empty/nil list uses only the built-in language rules.
    public var outlineRules: [OutlineRule]?
    public var completion: CompletionSettings?
    public var spelling: SpellingSettings?

    public init(
        tabWidth: Int = 4, indentWidth: Int = 4, indentStyle: IndentStyle = .spaces,
        wrapLines: Bool = false, encoding: TextEncoding? = nil, syntax: Language = .plainText,
        lineComment: String? = nil, blockCommentStart: String? = nil, blockCommentEnd: String? = nil,
        outlineRules: [OutlineRule]? = nil, completion: CompletionSettings? = nil,
        spelling: SpellingSettings? = nil
    ) {
        self.tabWidth = tabWidth; self.indentWidth = indentWidth; self.indentStyle = indentStyle
        self.wrapLines = wrapLines; self.encoding = encoding; self.syntax = syntax
        self.lineComment = lineComment; self.blockCommentStart = blockCommentStart
        self.blockCommentEnd = blockCommentEnd
        self.outlineRules = outlineRules
        self.completion = completion
        self.spelling = spelling
    }
}

public struct FileTypeProfile: Codable, Equatable, Identifiable, Sendable {
    public static let currentSchemaVersion = 3
    public var schemaVersion: Int
    public var id: String
    public var name: String
    public var filenamePatterns: [String]
    public var extensions: [String]
    public var priority: Int
    public var settings: FileTypeSettings

    public init(
        id: String, name: String, filenamePatterns: [String] = [], extensions: [String] = [],
        priority: Int = 0, settings: FileTypeSettings, schemaVersion: Int = currentSchemaVersion
    ) {
        self.schemaVersion = schemaVersion; self.id = id; self.name = name
        self.filenamePatterns = filenamePatterns; self.extensions = extensions
        self.priority = priority; self.settings = settings
    }
}

public enum FileTypeProfileSource: Int, Sendable { case builtIn = 0, user = 1 }

public struct SourcedFileTypeProfile: Equatable, Sendable {
    public var profile: FileTypeProfile
    public var source: FileTypeProfileSource
    public init(_ profile: FileTypeProfile, source: FileTypeProfileSource) {
        self.profile = profile; self.source = source
    }
}
