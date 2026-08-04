import AppKit
import MaruEditCore

protocol StatusBarViewDelegate: AnyObject {
    /// The user clicked the encoding label. `menu` should be popped up
    /// at `point` (already in the status bar's own coordinate space).
    func statusBar(_ statusBar: StatusBarView, didClickEncodingAt point: NSPoint)
}

final class StatusBarView: NSView {
    weak var delegate: StatusBarViewDelegate?

    private let lineColLabel = NSTextField(labelWithString: "Ln 1, Col 1")
    private let langLabel    = NSTextField(labelWithString: "Plain Text")
    private let encLabel     = NSTextField(labelWithString: "UTF-8")
    private let indentLabel  = NSTextField(labelWithString: "Spaces: 4")

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = Theme.statusBg.cgColor
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        let h = bounds.height
        let midY = (h - 16) / 2
        lineColLabel.frame = NSRect(x: 14, y: midY, width: 100, height: 16)
        indentLabel.frame = NSRect(x: 120, y: midY, width: 80, height: 16)
        langLabel.sizeToFit()
        langLabel.frame.origin = NSPoint(x: bounds.width - 14 - langLabel.frame.width, y: midY)
        encLabel.sizeToFit()
        encLabel.frame.origin = NSPoint(x: langLabel.frame.minX - 20 - encLabel.frame.width, y: midY)
        window?.invalidateCursorRects(for: self)
    }

    private func setup() {
        let labels = [lineColLabel, langLabel, encLabel, indentLabel]
        for l in labels {
            l.font = Theme.uiFontSmall
            l.textColor = Theme.statusText
            l.isBordered = false
            l.isEditable = false
            l.drawsBackground = false
            addSubview(l)
        }
        encLabel.textColor = Theme.accent
        encLabel.toolTip = "Click to reopen this file with a different encoding"
    }

    func updateCursor(line: Int, col: Int) {
        lineColLabel.stringValue = "Ln \(line), Col \(col)"
        needsLayout = true
    }

    func updateLanguage(_ lang: Language) {
        langLabel.stringValue = lang.displayName
        needsLayout = true
    }

    func updateEncoding(_ encoding: TextEncoding) {
        encLabel.stringValue = encoding.displayName
        needsLayout = true
    }

    // MARK: - Clickable encoding control

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard encLabel.frame.contains(point) else {
            super.mouseDown(with: event)
            return
        }
        delegate?.statusBar(self, didClickEncodingAt: NSPoint(x: encLabel.frame.minX, y: encLabel.frame.maxY))
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(encLabel.frame, cursor: .pointingHand)
    }
}
