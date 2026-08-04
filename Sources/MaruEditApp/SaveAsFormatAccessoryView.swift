import AppKit
import MaruEditCore

/// `NSSavePanel` accessory view letting the user choose the target
/// encoding and byte-order-mark for "Save As…" (ROADMAP.md M2-04,
/// "Allow Save As to choose encoding and line ending" — the line-ending
/// half of that is handled separately by `MainWindowController`'s mixed-
/// line-ending save prompt, since it's a save-time correctness question
/// for *any* save, not just Save As).
final class SaveAsFormatAccessoryView: NSView {
    private let encodingPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let bomCheckbox: NSButton
    private let encodings = TextEncoding.userSelectable

    var selectedEncoding: TextEncoding {
        let index = encodingPopup.indexOfSelectedItem
        guard index >= 0, index < encodings.count else { return .utf8 }
        return encodings[index]
    }

    var includesByteOrderMark: Bool { bomCheckbox.state == .on }

    init(initialEncoding: TextEncoding, initialHasByteOrderMark: Bool) {
        bomCheckbox = NSButton(checkboxWithTitle: "Include Byte Order Mark", target: nil, action: nil)
        super.init(frame: NSRect(x: 0, y: 0, width: 340, height: 62))

        let encodingLabel = NSTextField(labelWithString: "Encoding:")
        encodingLabel.frame = NSRect(x: 0, y: 36, width: 70, height: 20)
        addSubview(encodingLabel)

        encodingPopup.frame = NSRect(x: 74, y: 32, width: 250, height: 26)
        for encoding in encodings {
            encodingPopup.addItem(withTitle: encoding.displayName)
        }
        if let index = encodings.firstIndex(of: initialEncoding) {
            encodingPopup.selectItem(at: index)
        }
        encodingPopup.target = self
        encodingPopup.action = #selector(encodingChanged)
        addSubview(encodingPopup)

        bomCheckbox.frame = NSRect(x: 74, y: 4, width: 250, height: 20)
        bomCheckbox.state = initialHasByteOrderMark ? .on : .off
        addSubview(bomCheckbox)

        updateBOMCheckboxAvailability()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    @objc private func encodingChanged() {
        updateBOMCheckboxAvailability()
    }

    private func updateBOMCheckboxAvailability() {
        let supportsBOM = selectedEncoding.byteOrderMark != nil
        bomCheckbox.isEnabled = supportsBOM
        if !supportsBOM { bomCheckbox.state = .off }
    }
}
