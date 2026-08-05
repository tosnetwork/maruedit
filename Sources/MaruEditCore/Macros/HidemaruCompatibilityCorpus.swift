import Foundation

/// Clean-room behavior cases authored for MaruEdit from observable command
/// semantics. They contain no Hidemaru code, assets, help text, or binaries.
public struct HidemaruBehaviorCase: Sendable, Equatable {
    public let id: String
    public let category: String
    public let source: String
    public let expectedToTranslate: Bool
}

public enum HidemaruCompatibilityCorpus {
    public static let license = "CC0-1.0"
    public static let cases: [HidemaruBehaviorCase] = [
        .init(id: "edit-transform", category: "editor", source: "selectall; toupper;", expectedToTranslate: true),
        .init(id: "variables-loop-branch", category: "language", source: #"#i=0; while(#i<2){#i=#i+1;} if(#i==2){gofileend; insert "ok";}"#, expectedToTranslate: true),
        .init(id: "function-call", category: "language", source: #"function append { gofileend; insert "!"; } call append;"#, expectedToTranslate: true),
        .init(id: "search-navigation", category: "search", source: "findnext; findprevious;", expectedToTranslate: true),
        .init(id: "outline-window", category: "window-outline", source: "showoutline; nextwindow;", expectedToTranslate: true),
        .init(id: "unsafe-process", category: "diagnostic", source: #"run "tool";"#, expectedToTranslate: false),
        .init(id: "windows-registry", category: "diagnostic", source: "registry;", expectedToTranslate: false),
    ]

    public static func markdownReport() -> String {
        var lines = ["# Generated Hidemaru Compatibility Report", "", "Corpus license: \(license)", "", "| Case | Category | Result |", "|---|---|---|"]
        for item in cases {
            let translated = (try? HidemaruCompatibility.translate(item.source)) != nil
            let result = translated == item.expectedToTranslate ? "PASS" : "FAIL"
            lines.append("| \(item.id) | \(item.category) | \(result) |")
        }
        return lines.joined(separator: "\n") + "\n"
    }
}
