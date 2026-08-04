import AppKit
import MaruEditCore

enum StatusBarControl: CaseIterable {
    case largeFileMode, encoding, byteOrderMark, lineEnding, languageProfile
}

protocol StatusBarViewDelegate: AnyObject {
    func statusBar(
        _ statusBar: StatusBarView, didClick control: StatusBarControl, at point: NSPoint)
}

final class StatusBarView: NSView {
    weak var delegate: StatusBarViewDelegate?

    private let lineColLabel = NSTextField(labelWithString: "Ln 1, Col 1")
    private let selectionLabel = NSTextField(labelWithString: "")
    private let indentLabel = NSTextField(labelWithString: "Spaces: 4")
    private let langLabel = NSTextField(labelWithString: "Plain Text")
    private let encLabel = NSTextField(labelWithString: "UTF-8")
    private let bomLabel = NSTextField(labelWithString: "No BOM")
    private let lineEndingLabel = NSTextField(labelWithString: "LF")
    private let readOnlyLabel = NSTextField(labelWithString: "Read-Only")
    private let largeFileModeLabel = NSTextField(labelWithString: "Reduced Features")
    private var cursorText = "Ln 1, Col 1"
    private var messageWorkItem: DispatchWorkItem?

    var displayedLeadingText: String { lineColLabel.stringValue }
    var displayedSelectionText: String { selectionLabel.stringValue }
    var displayedEncodingText: String { encLabel.stringValue }
    var displayedBOMText: String { bomLabel.stringValue }
    var displayedLineEndingText: String { lineEndingLabel.stringValue }
    var displayedLanguageProfileText: String { langLabel.stringValue }
    var displayedLargeFileModeText: String? {
        largeFileModeLabel.isHidden ? nil : largeFileModeLabel.stringValue
    }

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
        let midY = (bounds.height - 16) / 2
        lineColLabel.frame = NSRect(
            x: 14, y: midY, width: messageWorkItem == nil ? 105 : 280, height: 16)
        selectionLabel.frame = NSRect(x: 122, y: midY, width: 130, height: 16)
        indentLabel.frame = NSRect(x: 255, y: midY, width: 85, height: 16)

        var right = bounds.width - 14
        for label in [langLabel, encLabel, bomLabel, lineEndingLabel, largeFileModeLabel] {
            label.sizeToFit()
            right -= label.frame.width
            label.frame.origin = NSPoint(x: right, y: midY)
            right -= 18
        }
        readOnlyLabel.sizeToFit()
        right -= readOnlyLabel.frame.width
        readOnlyLabel.frame.origin = NSPoint(x: right, y: midY)
        window?.invalidateCursorRects(for: self)
    }

    private func setup() {
        let labels = [lineColLabel, selectionLabel, indentLabel, langLabel, encLabel,
                      bomLabel, lineEndingLabel, readOnlyLabel, largeFileModeLabel]
        for label in labels {
            label.font = Theme.uiFontSmall
            label.textColor = Theme.statusText
            label.isBordered = false
            label.isEditable = false
            label.drawsBackground = false
            addSubview(label)
        }
        let controls: [(NSTextField, String, String)] = [
            (encLabel, "Encoding", "Choose or reopen with a text encoding"),
            (bomLabel, "Byte order mark", "Choose whether to save a byte order mark"),
            (lineEndingLabel, "Line ending", "Choose the saved line-ending style"),
            (langLabel, "Language and file-type profile", "Choose syntax language or inspect the active profile"),
        ]
        for (label, accessibilityLabel, toolTip) in controls {
            label.textColor = Theme.accent
            label.setAccessibilityRole(.button)
            label.setAccessibilityLabel(accessibilityLabel)
            label.toolTip = toolTip
        }
        lineColLabel.setAccessibilityLabel("Cursor line and display column")
        selectionLabel.setAccessibilityLabel("Selection count")
        readOnlyLabel.textColor = .systemOrange
        readOnlyLabel.toolTip = "This file is read-only on disk; use Save As to save changes"
        readOnlyLabel.isHidden = true
        largeFileModeLabel.textColor = .systemOrange
        largeFileModeLabel.setAccessibilityRole(.button)
        largeFileModeLabel.setAccessibilityLabel(SettingsLocalization.text("largeFileMode"))
        largeFileModeLabel.toolTip = SettingsLocalization.text("largeFileTooltip")
        largeFileModeLabel.isHidden = true
    }

    func updateCursor(_ state: EditorCursorState) {
        cursorText = "Ln \(state.lineNumber), Col \(state.displayColumn)"
        if messageWorkItem == nil { lineColLabel.stringValue = cursorText }
        if state.selectedCharacterCount == 0 {
            selectionLabel.stringValue = state.selectionRangeCount > 1
                ? "\(state.selectionRangeCount) carets" : ""
        } else if state.selectionRangeCount > 1 {
            selectionLabel.stringValue = "Sel \(state.selectedCharacterCount) (\(state.selectionRangeCount) ranges)"
        } else {
            selectionLabel.stringValue = "Sel \(state.selectedCharacterCount)"
        }
        lineColLabel.toolTip = "UTF-16 offset: \(state.utf16Offset)"
        selectionLabel.toolTip = "Selected UTF-16 units: \(state.selectedUTF16Length)"
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

    func updateLanguage(_ language: Language, profileName: String?) {
        langLabel.stringValue = profileName.map { "\(language.displayName) · \($0)" }
            ?? language.displayName
        needsLayout = true
    }

    func updateEncoding(_ encoding: TextEncoding) {
        encLabel.stringValue = encoding.displayName
        needsLayout = true
    }

    func updateByteOrderMark(_ hasByteOrderMark: Bool) {
        bomLabel.stringValue = hasByteOrderMark ? "BOM" : "No BOM"
        needsLayout = true
    }

    func updateLineEnding(_ state: LineEndingState) {
        lineEndingLabel.stringValue = state.displayName
        needsLayout = true
    }

    func updateIndentation(style: IndentStyle, width: Int) {
        indentLabel.stringValue = style == .tabs ? "Tabs: \(width)" : "Spaces: \(width)"
        needsLayout = true
    }

    func updateReadOnly(_ isReadOnly: Bool) {
        guard readOnlyLabel.isHidden == isReadOnly else { return }
        readOnlyLabel.isHidden = !isReadOnly
        needsLayout = true
    }

    func updateLargeFileMode(_ mode: LargeFileMode) {
        largeFileModeLabel.stringValue = SettingsLocalization.text(
            mode == .readOnly ? "largeReadOnly" : "reducedFeatures")
        largeFileModeLabel.isHidden = mode == .normal
        needsLayout = true
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard let control = control(at: point), let frame = frame(for: control) else {
            super.mouseDown(with: event)
            return
        }
        activate(control, at: NSPoint(x: frame.minX, y: frame.maxY))
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        for control in StatusBarControl.allCases {
            if let frame = frame(for: control) { addCursorRect(frame, cursor: .pointingHand) }
        }
    }

    func frame(for control: StatusBarControl) -> NSRect? {
        switch control {
        case .largeFileMode:
            return largeFileModeLabel.isHidden ? nil : largeFileModeLabel.frame
        case .encoding: return encLabel.frame
        case .byteOrderMark: return bomLabel.frame
        case .lineEnding: return lineEndingLabel.frame
        case .languageProfile: return langLabel.frame
        }
    }

    func activate(_ control: StatusBarControl, at point: NSPoint? = nil) {
        guard let frame = frame(for: control) else { return }
        delegate?.statusBar(
            self, didClick: control,
            at: point ?? NSPoint(x: frame.minX, y: frame.maxY))
    }

    private func control(at point: NSPoint) -> StatusBarControl? {
        StatusBarControl.allCases.first { frame(for: $0)?.contains(point) == true }
    }
}
