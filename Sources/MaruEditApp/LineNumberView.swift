import AppKit
import MaruEditCore

/// Line number gutter implemented as a plain NSView (not NSRulerView) because
/// overriding drawHashMarksAndLabels on NSRulerView subclasses breaks
/// NSTextView rendering on macOS 15+.
final class LineNumberView: NSView {
    private weak var textView: NSTextView?
    private var gutterWidth: NSLayoutConstraint!
    var bookmarkOffsets: Set<Int> = [] { didSet { needsDisplay = true } }
    var foldRegions: [FoldRegion] = [] { didSet { needsDisplay = true } }
    var collapsedFoldIDs: Set<String> = [] { didSet { needsDisplay = true } }
    var onToggleFold: ((String) -> Void)?
    override var isFlipped: Bool { true }

    init(textView: NSTextView) {
        self.textView = textView
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        gutterWidth = widthAnchor.constraint(equalToConstant: 48)
        gutterWidth.isActive = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func setVisible(_ visible: Bool) {
        isHidden = !visible
        gutterWidth.constant = visible ? 48 : 0
    }

    override func draw(_ dirtyRect: NSRect) {
        Theme.gutterBg.setFill()
        dirtyRect.fill()

        Theme.border.setFill()
        NSRect(x: bounds.width - 1, y: dirtyRect.origin.y, width: 1, height: dirtyRect.height).fill()

        guard let tv = textView,
              let lm = tv.layoutManager,
              let tc = tv.textContainer else {
            drawNumber(1, y: 8, active: true)
            return
        }

        let string = tv.string as NSString
        let containerOrigin = tv.textContainerOrigin

        if string.length == 0 {
            drawNumber(1, y: containerOrigin.y - scrollOffset, active: true)
            return
        }

        let selectedRange = tv.selectedRange()
        guard let sv = tv.enclosingScrollView else { return }
        let visibleRect = sv.contentView.bounds
        let glyphRange = lm.glyphRange(forBoundingRect: visibleRect, in: tc)
        let charRange = lm.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)

        var lineNum = 1
        var idx = 0
        while idx < charRange.location {
            let lr = string.lineRange(for: NSRange(location: idx, length: 0))
            lineNum += 1
            idx = NSMaxRange(lr)
        }

        let yOffset = scrollOffset
        var gi = glyphRange.location
        while gi < NSMaxRange(glyphRange) {
            var effectiveRange = NSRange()
            let fragRect = lm.lineFragmentRect(forGlyphAt: gi, effectiveRange: &effectiveRange)
            let cr = lm.characterRange(forGlyphRange: effectiveRange, actualGlyphRange: nil)
            let lr = string.lineRange(for: NSRange(location: cr.location, length: 0))

            if cr.location == lr.location {
                let y = fragRect.origin.y + containerOrigin.y - yOffset
                let active = NSLocationInRange(selectedRange.location, lr)
                let fold = foldRegions.first { $0.startLine == lineNum - 1 }
                drawNumber(lineNum, y: y, active: active,
                           bookmarked: bookmarkOffsets.contains(lr.location), fold: fold)
                lineNum += 1
            }
            gi = NSMaxRange(effectiveRange)
        }
    }

    private var scrollOffset: CGFloat {
        textView?.enclosingScrollView?.contentView.bounds.origin.y ?? 0
    }

    private func drawNumber(
        _ num: Int, y: CGFloat, active: Bool, bookmarked: Bool = false,
        fold: FoldRegion? = nil
    ) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: Theme.lineNumFont,
            .foregroundColor: active ? Theme.gutterActiveText : Theme.gutterText
        ]
        let str = "\(num)" as NSString
        let sz = str.size(withAttributes: attrs)
        let pt = NSPoint(x: bounds.width - sz.width - 10,
                         y: y + (Theme.editorFont.ascender - sz.height) / 2 + 2)
        str.draw(at: pt, withAttributes: attrs)
        if bookmarked {
            Theme.accent.setFill()
            NSBezierPath(ovalIn: NSRect(x: 5, y: y + 5, width: 7, height: 7)).fill()
        }
        if let fold {
            let collapsed = collapsedFoldIDs.contains(fold.id)
            let path = NSBezierPath()
            if collapsed {
                path.move(to: NSPoint(x: 16, y: y + 5))
                path.line(to: NSPoint(x: 16, y: y + 13))
                path.line(to: NSPoint(x: 22, y: y + 9))
            } else {
                path.move(to: NSPoint(x: 15, y: y + 6))
                path.line(to: NSPoint(x: 23, y: y + 6))
                path.line(to: NSPoint(x: 19, y: y + 12))
            }
            path.close()
            Theme.gutterText.setFill()
            path.fill()
        }
    }

    override func mouseDown(with event: NSEvent) {
        guard convert(event.locationInWindow, from: nil).x < 26,
              let tv = textView, let lm = tv.layoutManager, let tc = tv.textContainer else {
            super.mouseDown(with: event); return
        }
        let point = tv.convert(event.locationInWindow, from: nil)
        let containerPoint = NSPoint(
            x: point.x - tv.textContainerOrigin.x,
            y: point.y - tv.textContainerOrigin.y)
        let glyph = lm.glyphIndex(for: containerPoint, in: tc)
        let offset = lm.characterIndexForGlyph(at: glyph)
        let line = LineIndex(tv.string).line(atUTF16Offset: offset)
        guard let region = foldRegions.first(where: { $0.startLine == line }) else {
            super.mouseDown(with: event); return
        }
        onToggleFold?(region.id)
    }
}
