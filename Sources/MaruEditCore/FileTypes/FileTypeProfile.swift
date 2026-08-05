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

public struct ProfileAppearanceSettings: Codable, Equatable, Sendable {
    public var fontName: String?
    public var fontSize: Double?
    public var foregroundHex: String?
    public var backgroundHex: String?
    public var selectionHex: String?

    public init(
        fontName: String? = nil, fontSize: Double? = nil,
        foregroundHex: String? = nil, backgroundHex: String? = nil,
        selectionHex: String? = nil
    ) {
        self.fontName = fontName; self.fontSize = fontSize
        self.foregroundHex = foregroundHex; self.backgroundHex = backgroundHex
        self.selectionHex = selectionHex
    }
}

public enum BackupDestination: String, Codable, Sendable { case sibling, directory }

public struct BackupSettings: Codable, Equatable, Sendable {
    public var enabled: Bool
    public var destination: BackupDestination
    public var directoryPath: String?
    public var suffix: String
    public var maximumCopies: Int
    public init(
        enabled: Bool = false, destination: BackupDestination = .sibling,
        directoryPath: String? = nil, suffix: String = "~", maximumCopies: Int = 5
    ) {
        self.enabled = enabled; self.destination = destination
        self.directoryPath = directoryPath; self.suffix = suffix
        self.maximumCopies = maximumCopies
    }
}

public struct ProfileLoadPolicy: Codable, Equatable, Sendable {
    public var opensReadOnly: Bool
    public var encodingCandidateOrder: [TextEncoding]
    public init(opensReadOnly: Bool = false, encodingCandidateOrder: [TextEncoding] = []) {
        self.opensReadOnly = opensReadOnly; self.encodingCandidateOrder = encodingCandidateOrder
    }
}

public struct ProfileSavePolicy: Codable, Equatable, Sendable {
    public var backup: BackupSettings
    public var ensuresFinalNewline: Bool
    public var trimsTrailingWhitespace: Bool
    public init(
        backup: BackupSettings = BackupSettings(), ensuresFinalNewline: Bool = false,
        trimsTrailingWhitespace: Bool = false
    ) {
        self.backup = backup; self.ensuresFinalNewline = ensuresFinalNewline
        self.trimsTrailingWhitespace = trimsTrailingWhitespace
    }
}

public struct FileTypeSettings: Codable, Equatable, Sendable {
    public var tabWidth: Int
    public var indentWidth: Int
    public var indentStyle: IndentStyle
    public var wrapLines: Bool
    public var wrapMode: WrapMode?
    public var wrapColumn: Int?
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
    public var appearance: ProfileAppearanceSettings?
    public var foldingEnabled: Bool?
    public var templatePath: String?
    public var loadPolicy: ProfileLoadPolicy?
    public var savePolicy: ProfileSavePolicy?

    public init(
        tabWidth: Int = 4, indentWidth: Int = 4, indentStyle: IndentStyle = .spaces,
        wrapLines: Bool = false, wrapMode: WrapMode? = nil, wrapColumn: Int? = nil,
        encoding: TextEncoding? = nil, syntax: Language = .plainText,
        lineComment: String? = nil, blockCommentStart: String? = nil, blockCommentEnd: String? = nil,
        outlineRules: [OutlineRule]? = nil, completion: CompletionSettings? = nil,
        spelling: SpellingSettings? = nil, appearance: ProfileAppearanceSettings? = nil,
        foldingEnabled: Bool? = nil, templatePath: String? = nil,
        loadPolicy: ProfileLoadPolicy? = nil, savePolicy: ProfileSavePolicy? = nil
    ) {
        self.tabWidth = tabWidth; self.indentWidth = indentWidth; self.indentStyle = indentStyle
        self.wrapLines = wrapLines; self.wrapMode = wrapMode
        self.wrapColumn = wrapColumn.map { max(20, min(8_000, $0)) }
        self.encoding = encoding; self.syntax = syntax
        self.lineComment = lineComment; self.blockCommentStart = blockCommentStart
        self.blockCommentEnd = blockCommentEnd
        self.outlineRules = outlineRules
        self.completion = completion
        self.spelling = spelling
        self.appearance = appearance
        self.foldingEnabled = foldingEnabled
        self.templatePath = templatePath
        self.loadPolicy = loadPolicy
        self.savePolicy = savePolicy
    }
}

public struct FileTypeProfile: Codable, Equatable, Identifiable, Sendable {
    public static let currentSchemaVersion = 5
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
