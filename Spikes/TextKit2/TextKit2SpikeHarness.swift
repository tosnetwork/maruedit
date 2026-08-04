import AppKit
import Foundation

/// Isolated TextKit 2 probe. The production editor does not depend on this
/// target; it exists only to keep migration experiments compiling and measured.
@MainActor
public final class TextKit2SpikeHarness {
    public let contentStorage: NSTextContentStorage
    public let layoutManager: NSTextLayoutManager
    public let textContainer: NSTextContainer
    public let textView: NSTextView

    public init(text: String) {
        contentStorage = NSTextContentStorage()
        layoutManager = NSTextLayoutManager()
        textContainer = NSTextContainer(
            containerSize: NSSize(width: 800, height: CGFloat.greatestFiniteMagnitude))
        contentStorage.addTextLayoutManager(layoutManager)
        layoutManager.textContainer = textContainer
        textView = NSTextView(
            frame: NSRect(x: 0, y: 0, width: 800, height: 600),
            textContainer: textContainer)
        contentStorage.textStorage?.setAttributedString(NSAttributedString(string: text))
    }

    public var usesTextKit2: Bool { textView.textLayoutManager === layoutManager }

    public func acceptsMultipleSelections(_ ranges: [NSRange]) -> Bool {
        textView.setSelectedRanges(
            ranges.map(NSValue.init(range:)), affinity: .downstream, stillSelecting: false)
        return textView.selectedRanges.map(\.rangeValue) == ranges
    }

    public var exposesMarkedTextContract: Bool {
        textView.responds(to: #selector(NSTextInputClient.setMarkedText(
            _:selectedRange:replacementRange:)))
            && textView.responds(to: #selector(NSTextInputClient.unmarkText))
    }

    public func layoutDuration() -> TimeInterval {
        let started = CFAbsoluteTimeGetCurrent()
        layoutManager.ensureLayout(for: contentStorage.documentRange)
        return CFAbsoluteTimeGetCurrent() - started
    }

    public func enumerateLayoutFragmentCount() -> Int {
        var count = 0
        layoutManager.enumerateTextLayoutFragments(
            from: contentStorage.documentRange.location,
            options: [.ensuresLayout]
        ) { _ in
            count += 1
            return true
        }
        return count
    }
}
