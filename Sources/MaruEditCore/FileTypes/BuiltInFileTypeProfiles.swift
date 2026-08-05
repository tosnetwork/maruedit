import Foundation

public enum BuiltInFileTypeProfiles {
    public static let all: [FileTypeProfile] = [
        profile("plainText", "Plain Text", [], .plainText, nil),
        profile("swift", "Swift", ["swift"], .swift, "//", block: ("/*", "*/")),
        profile("cpp", "C/C++", ["c", "h", "cpp", "hpp", "cc", "cxx", "hxx"], .cpp, "//", block: ("/*", "*/")),
        profile("go", "Go", ["go"], .go, "//", tabs: true),
        profile("rust", "Rust", ["rs"], .rust, "//", block: ("/*", "*/")),
        profile("javascript", "JavaScript", ["js", "jsx", "mjs", "cjs", "ts", "tsx"], .javascript, "//", block: ("/*", "*/")),
        profile("json", "JSON", ["json"], .json, nil),
        profile("markdown", "Markdown", ["md", "markdown"], .markdown, nil, wrap: true),
        FileTypeProfile(
            id: "builtin.shell", name: "Shell", filenamePatterns: ["Makefile"],
            extensions: ["sh", "bash", "zsh", "fish"], settings: FileTypeSettings(
                wrapLines: true, wrapMode: .fixed, wrapColumn: 160,
                syntax: .shell, lineComment: "#")),
    ]

    private static func profile(
        _ id: String, _ name: String, _ extensions: [String], _ syntax: Language,
        _ lineComment: String?, block: (String, String)? = nil,
        tabs: Bool = false, wrap: Bool = true
    ) -> FileTypeProfile {
        FileTypeProfile(
            id: "builtin.\(id)", name: name, extensions: extensions,
            settings: FileTypeSettings(
                indentStyle: tabs ? .tabs : .spaces, wrapLines: wrap,
                wrapMode: wrap ? WrapMode.fixed : WrapMode.none, wrapColumn: 160,
                syntax: syntax, lineComment: lineComment,
                blockCommentStart: block?.0, blockCommentEnd: block?.1))
    }
}
