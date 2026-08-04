import Foundation

/// MaruEdit's single, versioned user-preferences schema (ROADMAP.md
/// M1-04). All preference-backed settings live as typed fields on this
/// struct instead of scattered `UserDefaults` string keys.
///
/// Not yet consumed by the editor UI: M1's goal is to establish this
/// boundary without changing current behavior (every field's default
/// below matches what is currently hardcoded in `Theme.swift` /
/// `EditorViewController`). Wiring the editor to actually read live
/// preferences — and building a Preferences UI to change them — is M5
/// ("Key bindings, settings, file profiles, display, and themes").
public struct Preferences: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var fontName: String
    public var fontSize: Double
    public var theme: ThemeName
    public var showLineNumbers: Bool
    public var wrapLines: Bool
    public var tabWidth: Int

    public init(
        schemaVersion: Int = Preferences.currentSchemaVersion,
        fontName: String,
        fontSize: Double,
        theme: ThemeName,
        showLineNumbers: Bool,
        wrapLines: Bool,
        tabWidth: Int
    ) {
        self.schemaVersion = schemaVersion
        self.fontName = fontName
        self.fontSize = fontSize
        self.theme = theme
        self.showLineNumbers = showLineNumbers
        self.wrapLines = wrapLines
        self.tabWidth = tabWidth
    }

    /// Matches the values currently hardcoded in `Theme.swift` and
    /// `EditorViewController`, so adopting `PreferencesStore` later is a
    /// no-behavior-change migration by construction.
    public static let defaults = Preferences(
        fontName: "SF Mono", // resolved specially as NSFont.monospacedSystemFont, the current hardcoded font
        fontSize: 13,
        theme: .monokai,
        showLineNumbers: true,
        wrapLines: false,
        tabWidth: 4
    )
}

/// The set of built-in themes. Only one exists today (the hardcoded
/// Monokai-inspired palette in `Theme.swift`); this exists now so the
/// schema doesn't need a breaking change when a second theme arrives.
public enum ThemeName: String, Codable, Sendable, CaseIterable {
    case monokai
}
