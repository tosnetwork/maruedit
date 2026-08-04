import Foundation

/// A file's detected source language. Pure Foundation — no AppKit — so it
/// can be shared between MaruEditCore and MaruEditApp, and unit-tested
/// without launching an AppKit application.
public enum Language: String, Codable, CaseIterable, Sendable {
    case swift, python, javascript, typescript, html, css, json, markdown
    case rust, go, c, cpp, java, ruby, shell, xml, yaml, sql, toml, plainText

    public var displayName: String {
        switch self {
        case .swift:      return "Swift"
        case .python:     return "Python"
        case .javascript: return "JavaScript"
        case .typescript: return "TypeScript"
        case .html:       return "HTML"
        case .css:        return "CSS"
        case .json:       return "JSON"
        case .markdown:   return "Markdown"
        case .rust:       return "Rust"
        case .go:         return "Go"
        case .c:          return "C"
        case .cpp:        return "C++"
        case .java:       return "Java"
        case .ruby:       return "Ruby"
        case .shell:      return "Shell"
        case .xml:        return "XML"
        case .yaml:       return "YAML"
        case .sql:        return "SQL"
        case .toml:       return "TOML"
        case .plainText:  return "Plain Text"
        }
    }

    public static func detect(for url: URL) -> Language {
        switch url.pathExtension.lowercased() {
        case "swift":                          return .swift
        case "py", "pyw":                      return .python
        case "js", "jsx", "mjs", "cjs":       return .javascript
        case "ts", "tsx":                      return .typescript
        case "html", "htm":                    return .html
        case "css", "scss", "less":            return .css
        case "json":                           return .json
        case "md", "markdown":                 return .markdown
        case "rs":                             return .rust
        case "go":                             return .go
        case "c", "h":                         return .c
        case "cpp", "hpp", "cc", "cxx", "hxx": return .cpp
        case "java":                           return .java
        case "rb":                             return .ruby
        case "sh", "bash", "zsh", "fish":      return .shell
        case "xml", "plist":                   return .xml
        case "yml", "yaml":                    return .yaml
        case "sql":                            return .sql
        case "toml":                           return .toml
        default:                               return .plainText
        }
    }

    /// Temporary built-in profile value used by M4 line commands. M5-04
    /// moves this setting into versioned FileType Profiles.
    public var lineCommentDelimiter: String? {
        switch self {
        case .swift, .javascript, .typescript, .rust, .go, .c, .cpp, .java: return "//"
        case .python, .ruby, .shell, .yaml, .toml: return "#"
        case .sql: return "--"
        default: return nil
        }
    }
}
