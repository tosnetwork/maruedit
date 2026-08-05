import Foundation

/// MaruEdit's single, versioned user-preferences schema (ROADMAP.md
/// M1-04). All preference-backed settings live as typed fields on this
/// struct instead of scattered `UserDefaults` string keys.
///
/// Consumed live by Settings, View commands, and `EditorViewController`.
/// Defaults preserve the original editor appearance, and decoding supplies
/// defaults for fields introduced by later schema versions.
public struct Preferences: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 4

    public var schemaVersion: Int
    public var fontName: String
    public var fontSize: Double
    public var theme: ThemeName
    public var showLineNumbers: Bool
    public var wrapLines: Bool
    public var tabWidth: Int
    public var invisibleCharacters: InvisibleCharacterOptions
    public var workspaceStyle: WorkspaceStyle
    public var classicChrome: ClassicChromeOptions

    public init(
        schemaVersion: Int = Preferences.currentSchemaVersion,
        fontName: String,
        fontSize: Double,
        theme: ThemeName,
        showLineNumbers: Bool,
        wrapLines: Bool,
        tabWidth: Int,
        invisibleCharacters: InvisibleCharacterOptions = .none,
        workspaceStyle: WorkspaceStyle = .classic,
        classicChrome: ClassicChromeOptions = .allVisible
    ) {
        self.schemaVersion = schemaVersion
        self.fontName = fontName
        self.fontSize = fontSize
        self.theme = theme
        self.showLineNumbers = showLineNumbers
        self.wrapLines = wrapLines
        self.tabWidth = tabWidth
        self.invisibleCharacters = invisibleCharacters
        self.workspaceStyle = workspaceStyle
        self.classicChrome = classicChrome
    }

    /// Matches the values currently hardcoded in `Theme.swift` and
    /// `EditorViewController`, so adopting `PreferencesStore` later is a
    /// no-behavior-change migration by construction.
    public static let defaults = Preferences(
        fontName: "SF Mono", // resolved specially as NSFont.monospacedSystemFont, the current hardcoded font
        fontSize: 13,
        theme: .classicLight,
        showLineNumbers: true,
        wrapLines: false,
        tabWidth: 4,
        workspaceStyle: .classic
    )

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, fontName, fontSize, theme, showLineNumbers, wrapLines, tabWidth
        case invisibleCharacters, workspaceStyle, classicChrome
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try values.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        fontName = try values.decodeIfPresent(String.self, forKey: .fontName) ?? Self.defaults.fontName
        fontSize = try values.decodeIfPresent(Double.self, forKey: .fontSize) ?? Self.defaults.fontSize
        theme = try values.decodeIfPresent(ThemeName.self, forKey: .theme) ?? Self.defaults.theme
        showLineNumbers = try values.decodeIfPresent(Bool.self, forKey: .showLineNumbers)
            ?? Self.defaults.showLineNumbers
        wrapLines = try values.decodeIfPresent(Bool.self, forKey: .wrapLines) ?? Self.defaults.wrapLines
        tabWidth = try values.decodeIfPresent(Int.self, forKey: .tabWidth) ?? Self.defaults.tabWidth
        invisibleCharacters = try values.decodeIfPresent(
            InvisibleCharacterOptions.self, forKey: .invisibleCharacters) ?? .none
        workspaceStyle = try values.decodeIfPresent(
            WorkspaceStyle.self, forKey: .workspaceStyle) ?? .modern
        classicChrome = try values.decodeIfPresent(
            ClassicChromeOptions.self, forKey: .classicChrome) ?? .allVisible
    }
}

public struct ClassicChromeOptions: Codable, Equatable, Sendable {
    public var showHeading: Bool
    public var showRuler: Bool
    public var showCommandStrip: Bool

    public init(showHeading: Bool = true, showRuler: Bool = true, showCommandStrip: Bool = true) {
        self.showHeading = showHeading
        self.showRuler = showRuler
        self.showCommandStrip = showCommandStrip
    }

    public static let allVisible = ClassicChromeOptions()
}

/// Selects the window information architecture without changing document
/// contents or file-format behavior. Classic is the migration-oriented,
/// high-density editor workspace; Modern preserves the original project-editor
/// layout for existing users who prefer it.
public enum WorkspaceStyle: String, Codable, Sendable, CaseIterable {
    case classic
    case modern
}

public struct InvisibleCharacterOptions: Codable, Equatable, Sendable {
    public var spaces: Bool
    public var tabs: Bool
    public var lineEndings: Bool
    public var fullWidthSpaces: Bool

    public init(
        spaces: Bool = false, tabs: Bool = false,
        lineEndings: Bool = false, fullWidthSpaces: Bool = false
    ) {
        self.spaces = spaces
        self.tabs = tabs
        self.lineEndings = lineEndings
        self.fullWidthSpaces = fullWidthSpaces
    }

    public static let none = InvisibleCharacterOptions()
}

/// The set of built-in themes. Only one exists today (the hardcoded
/// Monokai-inspired palette in `Theme.swift`); this exists now so the
/// schema doesn't need a breaking change when a second theme arrives.
public enum ThemeName: String, Codable, Sendable, CaseIterable {
    case classicLight
    case monokai
}
