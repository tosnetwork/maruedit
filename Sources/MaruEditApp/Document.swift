import AppKit
import MaruEditCore

final class Document {
    var fileURL: URL?
    var content: String
    var isModified: Bool = false
    var language: Language
    var cursorPosition: Int = 0
    var scrollOffset: NSPoint = .zero
    var cachedTextStorage: NSTextStorage?
    private var savedContent: String

    init(fileURL: URL? = nil, content: String = "", language: Language = .plainText) {
        self.fileURL = fileURL
        self.content = content
        self.language = language
        self.savedContent = content
    }

    var displayName: String { fileURL?.lastPathComponent ?? "Untitled" }
    var title: String { isModified ? "\(displayName) •" : displayName }

    func markModified() {
        isModified = content != savedContent
    }

    func markSaved() {
        savedContent = content
        isModified = false
    }

    static func open(url: URL) throws -> Document {
        let text = try String(contentsOf: url, encoding: .utf8)
        return Document(fileURL: url, content: text, language: Language.detect(for: url))
    }

    func save() throws {
        guard let url = fileURL else { return }
        try content.write(to: url, atomically: true, encoding: .utf8)
        markSaved()
    }

    func save(to url: URL) throws {
        fileURL = url
        language = Language.detect(for: url)
        try save()
    }
}
