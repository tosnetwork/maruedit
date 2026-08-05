import Foundation

public enum WorkspaceFile {
    public static let pathExtension = "marudesk"

    public static func save(_ state: SessionState, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try AtomicFileWriter.write(try encoder.encode(state), to: url)
    }

    public static func load(from url: URL) throws -> SessionState {
        let state = try JSONDecoder().decode(SessionState.self, from: Data(contentsOf: url))
        return SessionStore.migrate(state)
    }
}
