import Foundation

/// One open file's restorable state within a session. Replaces the prior
/// implementation's two parallel structures (a plain array of paths, plus
/// a separate `[path: cursorPosition]` dictionary) with one typed record
/// per file — and adds scroll position, which the prior implementation
/// tracked only in memory during a session, never across a relaunch.
public struct OpenFileState: Codable, Equatable, Sendable {
    public var path: String
    public var cursorPosition: Int
    public var scrollOffsetX: Double
    public var scrollOffsetY: Double

    public init(path: String, cursorPosition: Int, scrollOffsetX: Double, scrollOffsetY: Double) {
        self.path = path
        self.cursorPosition = cursorPosition
        self.scrollOffsetX = scrollOffsetX
        self.scrollOffsetY = scrollOffsetY
    }
}

/// MaruEdit's versioned, restorable window session (ROADMAP.md M1-05).
///
/// Window frame is deliberately **not** part of this schema: AppKit's own
/// `NSWindow.setFrameAutosaveName` already persists and restores it, and
/// duplicating that here would just be two sources of truth for the same
/// thing. Recovering *unsaved edits* after a crash is a separate, larger
/// concern (`RecoveryStore`, ROADMAP.md M2) — this schema only restores
/// which already-saved files were open and where the caret/scroll was.
public struct SessionState: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var rootFolderPath: String?
    public var openFiles: [OpenFileState]
    public var activeIndex: Int
    public var windowZoomed: Bool
    public var sidebarCollapsed: Bool

    public init(
        schemaVersion: Int = SessionState.currentSchemaVersion,
        rootFolderPath: String?,
        openFiles: [OpenFileState],
        activeIndex: Int,
        windowZoomed: Bool,
        sidebarCollapsed: Bool
    ) {
        self.schemaVersion = schemaVersion
        self.rootFolderPath = rootFolderPath
        self.openFiles = openFiles
        self.activeIndex = activeIndex
        self.windowZoomed = windowZoomed
        self.sidebarCollapsed = sidebarCollapsed
    }

    /// The state of a brand-new window with nothing restored.
    public static let empty = SessionState(
        rootFolderPath: nil,
        openFiles: [],
        activeIndex: -1,
        windowZoomed: false,
        sidebarCollapsed: false
    )
}
