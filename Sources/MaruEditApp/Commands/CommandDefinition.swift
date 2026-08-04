import MaruEditCore

/// Describes one registrable command. This is a deliberately simplified
/// version of the shape sketched in ROADMAP.md section 9.5 — no
/// `async throws` and no `titleKey`/`defaultKeyBindings` yet, since
/// nothing in the codebase needs asynchronous commands or a real
/// localization/key-binding backing store yet (section 9's preamble
/// explicitly allows this: "direction, not byte-for-byte requirements").
/// Revisit when macros (M6) or key-binding profiles (M5) need more.
struct CommandDefinition {
    let id: CommandID
    let title: String
    let isEnabled: (CommandContext) -> Bool
    let execute: (CommandContext) -> Void

    init(
        id: CommandID,
        title: String,
        isEnabled: @escaping (CommandContext) -> Bool = { _ in true },
        execute: @escaping (CommandContext) -> Void
    ) {
        self.id = id
        self.title = title
        self.isEnabled = isEnabled
        self.execute = execute
    }
}
