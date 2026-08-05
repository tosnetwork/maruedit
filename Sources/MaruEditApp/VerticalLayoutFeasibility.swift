@preconcurrency import AppKit

struct VerticalLayoutFeasibilityReport: Equatable {
    let glyphCount: Int
    let usedWidth: CGFloat
    let usedHeight: CGFloat
    var isViable: Bool { glyphCount > 0 && usedWidth > 0 && usedHeight > 0 }
}

@MainActor
enum VerticalLayoutFeasibility {
    static func run(sample: String = "縦書きの日本語、ABC。\n第二列") -> VerticalLayoutFeasibilityReport {
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 240, height: 320))
        textView.string = sample
        textView.font = NSFont.systemFont(ofSize: 16)
        textView.setLayoutOrientation(.vertical)
        guard let layout = textView.layoutManager, let container = textView.textContainer else {
            return VerticalLayoutFeasibilityReport(glyphCount: 0, usedWidth: 0, usedHeight: 0)
        }
        layout.ensureLayout(for: container)
        return VerticalLayoutFeasibilityReport(
            glyphCount: layout.numberOfGlyphs,
            usedWidth: layout.usedRect(for: container).width,
            usedHeight: layout.usedRect(for: container).height)
    }
}
