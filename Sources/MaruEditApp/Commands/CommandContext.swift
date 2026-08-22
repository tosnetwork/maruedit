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
    /// The window this command was asked to act on, when the caller named one.
    ///
    /// A human's command has no target: they are looking at the window they
    /// mean. Anything else — an agent, a script, a test — must say, because
    /// "whichever window is key when this happens to run" is not something the
    /// caller can predict or the authorization layer can check.
    let target: MainWindowController?

    init(coordinator: AppCoordinator, target: MainWindowController? = nil) {
        self.coordinator = coordinator
        self.target = target
    }

    /// Runs `body` with window resolution pinned to this context's target, if
    /// it has one.
    func resolvingTarget<T>(_ body: () -> T) -> T {
        guard let target else { return body() }
        return coordinator.withTargetedWindow(target, body)
    }
}
