import Foundation

/// The state a command needs to run against. MaruEdit is single-window
/// for now, so this just wraps the app's one `AppCoordinator`, which
/// resolves the (currently singular) window controller. When multi-window
/// support lands, this is where "the frontmost window" resolution would
/// go — command implementations should not need to change.
///
/// Commands resolve AppKit state and therefore remain main-actor isolated.
@MainActor
struct CommandContext {
    let coordinator: AppCoordinator
}
