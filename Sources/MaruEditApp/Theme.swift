@preconcurrency import AppKit
import MaruEditCore

enum Theme {
    nonisolated(unsafe) static var activeName: ThemeName = .classicLight
    private static var light: Bool { activeName == .classicLight }

    static var background: NSColor { light ? .textBackgroundColor : NSColor(srgbRed: 0.153, green: 0.157, blue: 0.133, alpha: 1) }
    static var foreground: NSColor { light ? .textColor : NSColor(srgbRed: 0.973, green: 0.973, blue: 0.949, alpha: 1) }
    static var comment: NSColor { light ? NSColor(srgbRed: 0.12, green: 0.45, blue: 0.18, alpha: 1) : NSColor(srgbRed: 0.459, green: 0.443, blue: 0.369, alpha: 1) }
    static var string: NSColor { light ? NSColor(srgbRed: 0.65, green: 0.16, blue: 0.12, alpha: 1) : NSColor(srgbRed: 0.902, green: 0.859, blue: 0.455, alpha: 1) }
    static var keyword: NSColor { light ? NSColor(srgbRed: 0.08, green: 0.22, blue: 0.72, alpha: 1) : NSColor(srgbRed: 0.976, green: 0.149, blue: 0.447, alpha: 1) }
    static var function: NSColor { light ? NSColor(srgbRed: 0.46, green: 0.12, blue: 0.58, alpha: 1) : NSColor(srgbRed: 0.651, green: 0.886, blue: 0.182, alpha: 1) }
    static var number: NSColor { light ? NSColor(srgbRed: 0.02, green: 0.42, blue: 0.48, alpha: 1) : NSColor(srgbRed: 0.682, green: 0.506, blue: 1.000, alpha: 1) }
    static var type: NSColor { light ? NSColor(srgbRed: 0.05, green: 0.38, blue: 0.52, alpha: 1) : NSColor(srgbRed: 0.400, green: 0.851, blue: 0.937, alpha: 1) }

    static var selection: NSColor { light ? .selectedTextBackgroundColor : NSColor(srgbRed: 0.286, green: 0.282, blue: 0.235, alpha: 1) }
    static var currentLineHighlight: NSColor { light ? NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.05) : NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.07) }
    static var cursor: NSColor { light ? .textColor : NSColor(srgbRed: 0.973, green: 0.973, blue: 0.949, alpha: 1) }
    static var gutterBg: NSColor { light ? .controlBackgroundColor : NSColor(srgbRed: 0.184, green: 0.184, blue: 0.165, alpha: 1) }
    static var gutterText: NSColor { light ? .secondaryLabelColor : NSColor(srgbRed: 0.565, green: 0.565, blue: 0.541, alpha: 1) }
    static var gutterActiveText: NSColor { light ? .labelColor : NSColor(srgbRed: 0.800, green: 0.800, blue: 0.780, alpha: 1) }
    static var sidebarBg: NSColor { light ? .windowBackgroundColor : NSColor(srgbRed: 0.141, green: 0.145, blue: 0.122, alpha: 1) }
    static var sidebarText: NSColor { light ? .labelColor : NSColor(srgbRed: 0.800, green: 0.800, blue: 0.780, alpha: 1) }
    static var tabBarBg: NSColor { light ? .windowBackgroundColor : NSColor(srgbRed: 0.130, green: 0.133, blue: 0.114, alpha: 1) }
    /// The active tab shares the editor surface so it reads as the page in front.
    static var tabActive: NSColor { background }
    /// Inactive tabs sit recessed behind the bar instead of matching it.
    static var tabInactive: NSColor {
        light
            ? (NSColor.windowBackgroundColor.blended(withFraction: 0.13, of: .black) ?? .windowBackgroundColor)
            : NSColor(srgbRed: 0.098, green: 0.102, blue: 0.086, alpha: 1)
    }
    /// Hover sits between the recessed and the active face.
    static var tabHover: NSColor {
        light
            ? (NSColor.windowBackgroundColor.blended(withFraction: 0.05, of: .black) ?? .windowBackgroundColor)
            : NSColor(srgbRed: 0.169, green: 0.173, blue: 0.149, alpha: 1)
    }
    static var tabText: NSColor { light ? .secondaryLabelColor : NSColor(srgbRed: 0.550, green: 0.545, blue: 0.520, alpha: 1) }
    static var tabTextActive: NSColor { foreground }
    static var border: NSColor { light ? .separatorColor : NSColor(srgbRed: 0.180, green: 0.184, blue: 0.161, alpha: 1) }
    static var statusBg: NSColor { light ? .controlBackgroundColor : NSColor(srgbRed: 0.110, green: 0.114, blue: 0.098, alpha: 1) }
    static var statusText: NSColor { light ? .secondaryLabelColor : NSColor(srgbRed: 0.565, green: 0.565, blue: 0.541, alpha: 1) }
    static var accent: NSColor { light ? .controlAccentColor : NSColor(srgbRed: 0.976, green: 0.149, blue: 0.447, alpha: 1) }
    static var findBarBg: NSColor { light ? .controlBackgroundColor : NSColor(srgbRed: 0.180, green: 0.184, blue: 0.161, alpha: 1) }

    @MainActor static let editorFont = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
    @MainActor static let lineNumFont = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
    @MainActor static let uiFont = NSFont.systemFont(ofSize: 12, weight: .regular)
    @MainActor static let uiFontSmall = NSFont.systemFont(ofSize: 11, weight: .regular)
}
