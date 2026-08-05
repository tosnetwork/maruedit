import AppKit

/// Compact, original macOS chrome inspired by high-density text-editor
/// workflows. It contains no copied product art or bitmap assets.
final class ClassicWorkspaceChrome: NSView {
    static let headingHeight: CGFloat = 22
    static let rulerHeight: CGFloat = 20
    static let commandStripHeight: CGFloat = 24
    static let topHeight = headingHeight + rulerHeight

    private let heading = NSTextField(labelWithString: "Untitled")
    private let ruler = CharacterRulerView()
    private let commandStrip = ClassicCommandStripView()

    var headingText: String { heading.stringValue }
    var topChromeHeight: CGFloat { Self.topHeight }
    var bottomChromeHeight: CGFloat { Self.commandStripHeight }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        heading.font = .systemFont(ofSize: 11, weight: .medium)
        heading.lineBreakMode = .byTruncatingMiddle
        heading.setAccessibilityLabel("Current document heading")
        addSubview(heading)
        addSubview(ruler)
        addSubview(commandStrip)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        heading.frame = NSRect(
            x: 8, y: bounds.height - Self.headingHeight + 3,
            width: max(0, bounds.width - 16), height: 16)
        ruler.frame = NSRect(
            x: 0, y: bounds.height - Self.topHeight,
            width: bounds.width, height: Self.rulerHeight)
        commandStrip.frame = NSRect(
            x: 0, y: 0, width: bounds.width, height: Self.commandStripHeight)
    }

    func updateHeading(_ value: String) { heading.stringValue = value }
}

private final class CharacterRulerView: NSView {
    override var isFlipped: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        setAccessibilityRole(.ruler)
        setAccessibilityLabel("Character column ruler")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSColor.separatorColor.setStroke()
        let baseline = NSBezierPath()
        baseline.move(to: NSPoint(x: 0, y: bounds.maxY - 0.5))
        baseline.line(to: NSPoint(x: bounds.maxX, y: bounds.maxY - 0.5))
        baseline.stroke()

        let cell: CGFloat = 8
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 8, weight: .regular),
            .foregroundColor: NSColor.secondaryLabelColor,
        ]
        var column = 0
        var x: CGFloat = 46
        while x < bounds.maxX {
            if column.isMultiple(of: 10) {
                String(column).draw(at: NSPoint(x: x + 1, y: 1), withAttributes: attributes)
            } else if column.isMultiple(of: 5) {
                let tick = NSBezierPath()
                tick.move(to: NSPoint(x: x, y: bounds.maxY - 5))
                tick.line(to: NSPoint(x: x, y: bounds.maxY))
                tick.stroke()
            }
            column += 1
            x += cell
        }
    }
}

private final class ClassicCommandStripView: NSView {
    private let titles = ["F1 Help", "F2 Save", "F3 Find", "F4 Next", "F5 Grep", "F6 Macro"]
    private var labels: [NSTextField] = []

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        for title in titles {
            let label = NSTextField(labelWithString: title)
            label.font = .systemFont(ofSize: 10)
            label.alignment = .center
            label.setAccessibilityLabel(title)
            labels.append(label)
            addSubview(label)
        }
        setAccessibilityRole(.group)
        setAccessibilityLabel("Favorite command strip")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        let width = labels.isEmpty ? 0 : bounds.width / CGFloat(labels.count)
        for (index, label) in labels.enumerated() {
            label.frame = NSRect(x: CGFloat(index) * width, y: 4, width: width, height: 16)
        }
    }
}
