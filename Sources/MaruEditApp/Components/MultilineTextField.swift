import AppKit

/// An AppKit field configured for embedded newlines and a caller-controlled
/// number of visible rows. Return remains available to the owning workflow;
/// Option-Return inserts a newline through the standard field editor.
final class MultilineTextField: NSTextField {
    var visibleLines: Int = 2 { didSet { invalidateIntrinsicContentSize() } }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        usesSingleLineMode = false
        maximumNumberOfLines = 0
        cell?.wraps = true
        cell?.isScrollable = true
        lineBreakMode = .byWordWrapping
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: NSSize {
        let base = super.intrinsicContentSize
        return NSSize(width: base.width, height: max(base.height, CGFloat(visibleLines * 18 + 8)))
    }
}
