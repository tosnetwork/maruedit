import MaruEditCore

/// Describes one registrable command. This is a deliberately simplified
/// version of the shape sketched in ROADMAP.md section 9.5 — no
/// `async throws` and no `titleKey`/`defaultKeyBindings` yet, since
/// nothing in the codebase needs asynchronous commands or a real
/// localization/key-binding backing store yet (section 9's preamble
/// explicitly allows this: "direction, not byte-for-byte requirements").
/// Revisit when macros (M6) or key-binding profiles (M5) need more.
@MainActor
struct CommandDefinition {
    let id: CommandID
    let title: String
    let isEnabled: (CommandContext) -> Bool
    let execute: (CommandContext) -> Void

    /// Whether an AI agent may invoke this command.
    ///
    /// Default deny, and deliberately a property of the definition rather than
    /// a list somewhere else: registering a command must never be what makes it
    /// remotely invocable (ADR-011 §9.7).
    ///
    /// Commands are targetable now — `CommandContext` carries a window and
    /// resolution is pinned while the command runs — so what remains is
    /// whether *this* command acts synchronously. One that defers its work into
    /// a completion handler resolves the window again after the pin is gone,
    /// and would act on whatever is key by then, so it stays unexposed.
    let isAgentExposed: Bool

    init(
        id: CommandID,
        title: String,
        isEnabled: @escaping (CommandContext) -> Bool = { _ in true },
        isAgentExposed: Bool = false,
        execute: @escaping (CommandContext) -> Void
    ) {
        self.id = id
        self.title = title
        self.isEnabled = isEnabled
        self.isAgentExposed = isAgentExposed
        self.execute = execute
    }
}
