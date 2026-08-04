import AppKit
import MaruEditCore

protocol StatusBarViewDelegate: AnyObject {
    /// The user clicked the encoding label. `menu` should be popped up
    /// at `point` (already in the status bar's own coordinate space).
    func statusBar(_ statusBar: StatusBarView, didClickEncodingAt point: NSPoint)
}

final class StatusBarView: NSView {
    weak var delegate: StatusBarViewDelegate?

    private let lineColLabel     = NSTextField(labelWithString: "Ln 1, Col 1")
    private let langLabel        = NSTextField(labelWithString: "Plain Text")
    private let encLabel         = NSTextField(labelWithString: "UTF-8")
    private let lineEndingLabel  = NSTextField(labelWithString: "LF")
    private let indentLabel      = NSTextField(labelWithString: "Spaces: 4")
    /// ROADMAP.md M2-08: "Show an explicit read-only state." Hidden
    /// unless the current document's file is not writable.
    private let readOnlyLabel    = NSTextField(labelWithString: "Read-Only")
    private var cursorText = "Ln 1, Col 1"
    private var messageWorkItem: DispatchWorkItem?
    var displayedLeadingText: String { lineColLabel.stringValue }

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
        lineColLabel.frame = NSRect(x: 14, y: midY, width: messageWorkItem == nil ? 100 : 280, height: 16)
        indentLabel.frame = NSRect(x: 120, y: midY, width: 80, height: 16)
        langLabel.sizeToFit()
        langLabel.frame.origin = NSPoint(x: bounds.width - 14 - langLabel.frame.width, y: midY)
        encLabel.sizeToFit()
        encLabel.frame.origin = NSPoint(x: langLabel.frame.minX - 20 - encLabel.frame.width, y: midY)
        lineEndingLabel.sizeToFit()
        lineEndingLabel.frame.origin = NSPoint(x: encLabel.frame.minX - 16 - lineEndingLabel.frame.width, y: midY)
        readOnlyLabel.sizeToFit()
        readOnlyLabel.frame.origin = NSPoint(x: lineEndingLabel.frame.minX - 16 - readOnlyLabel.frame.width, y: midY)
        window?.invalidateCursorRects(for: self)
    }

    private func setup() {
        let labels = [lineColLabel, langLabel, encLabel, lineEndingLabel, indentLabel, readOnlyLabel]
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
        readOnlyLabel.textColor = .systemOrange
        readOnlyLabel.toolTip = "This file is read-only on disk; use Save As to save changes"
        readOnlyLabel.isHidden = true
    }

    func updateCursor(line: Int, col: Int) {
        cursorText = "Ln \(line), Col \(col)"
        if messageWorkItem == nil { lineColLabel.stringValue = cursorText }
        needsLayout = true
    }

    func showTransientMessage(_ message: String, duration: TimeInterval = 1.5) {
        messageWorkItem?.cancel()
        if message.isEmpty {
            messageWorkItem = nil
            lineColLabel.stringValue = cursorText
            needsLayout = true
            return
        }
        lineColLabel.stringValue = message
        let item = DispatchWorkItem { [weak self] in
            self?.messageWorkItem = nil
            self?.lineColLabel.stringValue = self?.cursorText ?? ""
            self?.needsLayout = true
        }
        messageWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: item)
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

    func updateLineEnding(_ state: LineEndingState) {
        lineEndingLabel.stringValue = state.displayName
        needsLayout = true
    }

    func updateReadOnly(_ isReadOnly: Bool) {
        guard readOnlyLabel.isHidden == isReadOnly else { return }
        readOnlyLabel.isHidden = !isReadOnly
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
