import MaruEditCore

/// The single entry point for invoking a command by its stable
/// `CommandID`. Per ROADMAP.md ADR-006, menus, key bindings, the future
/// command palette, and macros must all execute commands through here —
/// never by calling a controller method directly — so there is exactly
/// one place that decides whether a command can run right now.
@MainActor
final class CommandRegistry {
    private var definitionsByID: [CommandID: CommandDefinition] = [:]

    /// Registers `definition`. Traps on a duplicate ID — that's a
    /// programmer error (two commands claiming the same stable ID), not a
    /// runtime condition to recover from.
    func register(_ definition: CommandDefinition) {
        precondition(
            definitionsByID[definition.id] == nil,
            "Duplicate command id: \(definition.id.rawValue)"
        )
        definitionsByID[definition.id] = definition
    }

    @discardableResult
    func unregister(_ id: CommandID) -> Bool {
        definitionsByID.removeValue(forKey: id) != nil
    }

    func definition(for id: CommandID) -> CommandDefinition? {
        definitionsByID[id]
    }

    func isEnabled(_ id: CommandID, context: CommandContext) -> Bool {
        guard let definition = definitionsByID[id] else { return false }
        return definition.isEnabled(context)
    }

    /// Runs the command if it's registered and currently enabled. Returns
    /// whether it actually ran, so callers (e.g. menu validation callers
    /// double-checking before acting) can tell a no-op from a real run.
    @discardableResult
    func execute(_ id: CommandID, context: CommandContext) -> Bool {
        guard let definition = definitionsByID[id], definition.isEnabled(context) else {
            return false
        }
        definition.execute(context)
        return true
    }

    var allDefinitions: [CommandDefinition] {
        Array(definitionsByID.values)
    }
}
