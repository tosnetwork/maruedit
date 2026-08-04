import Foundation

/// The state a command needs to run against. MaruEdit is single-window
/// for now, so this just wraps the app's one `AppCoordinator`, which
/// resolves the (currently singular) window controller. When multi-window
/// support lands, this is where "the frontmost window" resolution would
/// go — command implementations should not need to change.
///
/// Not marked `@MainActor`: nothing else in this codebase uses Swift
/// concurrency yet, and every command currently only ever runs
/// synchronously on the main thread already (menu actions, key events).
/// Revisit if/when async commands (e.g. macros in M6) need real isolation.
struct CommandContext {
    let coordinator: AppCoordinator
}
