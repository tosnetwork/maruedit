import AppKit
import MaruEditCore

enum StatusBarControl: CaseIterable {
    case cursorPosition, characterCode, inputMode, layoutMode, fontSize
    case largeFileMode, encoding, byteOrderMark, lineEnding, languageProfile
}

enum StatusBarField: String, CaseIterable {
    case cursorPosition, selection, indentation, inputMode, layoutMode, totals, characterCode, fontSize
    case macroActivity, capsLock, readOnly, largeFileMode, lineEnding, byteOrderMark, encoding, languageProfile

    var title: String {
        switch self {
        case .cursorPosition: "Cursor Position"
        case .selection: "Selection"
        case .indentation: "Indentation"
        case .inputMode: "Insert/Overwrite"
        case .layoutMode: "Writing/Column Layout"
        case .totals: "Total Lines and Characters"
        case .characterCode: "Character Code"
        case .fontSize: "Font Size"
        case .macroActivity: "Macro Activity"
        case .capsLock: "Caps Lock"
        case .readOnly: "Read-Only State"
        case .largeFileMode: "Large File Mode"
        case .lineEnding: "Line Ending"
        case .byteOrderMark: "Byte Order Mark"
        case .encoding: "Encoding"
        case .languageProfile: "File-Type Profile"
        }
    }
}

@MainActor
protocol StatusBarViewDelegate: AnyObject {
    func statusBar(
        _ statusBar: StatusBarView, didClick control: StatusBarControl, at point: NSPoint)
}

final class StatusBarView: NSView {
    weak var delegate: StatusBarViewDelegate?

    private let lineColLabel = NSTextField(labelWithString: "Ln 1, Col 1")
    private let selectionLabel = NSTextField(labelWithString: "")
    private let indentLabel = NSTextField(labelWithString: "Spaces: 4")
    private let inputModeLabel = NSTextField(labelWithString: "INS")
    private let layoutModeLabel = NSTextField(labelWithString: "HORZ")
    private let totalsLabel = NSTextField(labelWithString: "1 lines · 0 chars")
    private let characterCodeLabel = NSTextField(labelWithString: "")
    private let fontSizeLabel = NSTextField(labelWithString: "13 pt")
    private let macroActivityLabel = NSTextField(labelWithString: "MACRO")
    private let capsLockLabel = NSTextField(labelWithString: "CAPS")
    private let langLabel = NSTextField(labelWithString: "Plain Text")
    private let encLabel = NSTextField(labelWithString: "UTF-8")
    private let bomLabel = NSTextField(labelWithString: "No BOM")
    private let lineEndingLabel = NSTextField(labelWithString: "LF")
    private let readOnlyLabel = NSTextField(labelWithString: "Read-Only")
    private let largeFileModeLabel = NSTextField(labelWithString: "Reduced Features")
    private var cursorText = "Ln 1, Col 1"
    private var documentText = ""
    private var messageWorkItem: DispatchWorkItem?
    private var configuredFields = Set(StatusBarField.allCases)
    private var isReadOnly = false
    private var isCapsLockEnabled = false
    private var isMacroRunning = false
    private var isMacroRecording = false
    private var largeFileMode: LargeFileMode = .normal
    private static let fieldsDefaultsKey = "MaruClassicStatusBarFields"

    var displayedLeadingText: String { lineColLabel.stringValue }
    var displayedSelectionText: String { selectionLabel.stringValue }
    var displayedEncodingText: String { encLabel.stringValue }
    var displayedBOMText: String { bomLabel.stringValue }
    var displayedLineEndingText: String { lineEndingLabel.stringValue }
    var displayedLanguageProfileText: String { langLabel.stringValue }
    var displayedInputModeText: String { inputModeLabel.stringValue }
    var displayedLayoutModeText: String { layoutModeLabel.stringValue }
    var displayedTotalsText: String { totalsLabel.stringValue }
    var displayedCharacterCodeText: String { characterCodeLabel.stringValue }
    var characterCodeDetail: String { characterCodeLabel.toolTip ?? characterCodeLabel.stringValue }
    var displayedFontSizeText: String { fontSizeLabel.stringValue }
    var displayedLargeFileModeText: String? {
        largeFileModeLabel.isHidden ? nil : largeFileModeLabel.stringValue
    }
    var configuredFieldIDs: Set<String> { Set(configuredFields.map(\.rawValue)) }
    var displayedCapsLockText: String? { capsLockLabel.isHidden ? nil : capsLockLabel.stringValue }
    var displayedMacroActivityText: String? {
        macroActivityLabel.isHidden ? nil : macroActivityLabel.stringValue
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = Theme.statusBg.cgColor
        if let values = UserDefaults.standard.stringArray(forKey: Self.fieldsDefaultsKey) {
            configuredFields = Set(values.compactMap(StatusBarField.init(rawValue:)))
            configuredFields.insert(.cursorPosition)
        }
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        applyConfiguredVisibility()
        let midY = (bounds.height - 16) / 2
        var right = bounds.width - 14
        for (field, label) in rightFields.reversed() where !label.isHidden {
            guard configuredFields.contains(field) else { continue }
            label.sizeToFit(); right -= label.frame.width
            label.frame.origin = NSPoint(x: right, y: midY); right -= 14
        }

        var x: CGFloat = 14
        for (field, label, width) in leftFields {
            guard !label.isHidden else { continue }
            let actualWidth = field == .cursorPosition && messageWorkItem != nil ? 280 : width
            if field != .cursorPosition && x + actualWidth > right - 8 {
                label.isHidden = true
            } else {
                label.frame = NSRect(x: x, y: midY, width: actualWidth, height: 16)
                x += actualWidth + 4
            }
        }
        window?.invalidateCursorRects(for: self)
    }

    private func setup() {
        let labels = [lineColLabel, selectionLabel, indentLabel, inputModeLabel, layoutModeLabel,
                      totalsLabel, characterCodeLabel, fontSizeLabel, langLabel, encLabel,
                      bomLabel, lineEndingLabel, macroActivityLabel, capsLockLabel,
                      readOnlyLabel, largeFileModeLabel]
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
        inputModeLabel.setAccessibilityLabel("Input mode: insert")
        inputModeLabel.toolTip = "Insert mode; overwrite mode is not enabled"
        layoutModeLabel.setAccessibilityLabel("Writing layout: horizontal")
        layoutModeLabel.toolTip = "Horizontal writing; click to choose writing or column layout"
        for label in [lineColLabel, inputModeLabel, layoutModeLabel, characterCodeLabel, fontSizeLabel] {
            label.textColor = Theme.accent
            label.setAccessibilityRole(.button)
        }
        readOnlyLabel.textColor = .systemOrange
        readOnlyLabel.toolTip = "This file is read-only on disk; use Save As to save changes"
        readOnlyLabel.isHidden = true
        capsLockLabel.textColor = .systemOrange
        capsLockLabel.setAccessibilityLabel("Caps Lock enabled")
        capsLockLabel.toolTip = "Caps Lock is enabled"
        capsLockLabel.isHidden = true
        macroActivityLabel.textColor = .systemRed
        macroActivityLabel.setAccessibilityLabel("Macro running")
        macroActivityLabel.toolTip = "A macro is currently running"
        macroActivityLabel.isHidden = true
        largeFileModeLabel.textColor = .systemOrange
        largeFileModeLabel.setAccessibilityRole(.button)
        largeFileModeLabel.setAccessibilityLabel(SettingsLocalization.text("largeFileMode"))
        largeFileModeLabel.toolTip = SettingsLocalization.text("largeFileTooltip")
        largeFileModeLabel.isHidden = true
    }

    func applyTheme() {
        layer?.backgroundColor = Theme.statusBg.cgColor
        for label in [lineColLabel, selectionLabel, indentLabel, inputModeLabel, layoutModeLabel,
                      totalsLabel, characterCodeLabel, fontSizeLabel,
                      langLabel, encLabel, bomLabel, lineEndingLabel] {
            label.textColor = Theme.statusText
        }
        for label in [encLabel, bomLabel, lineEndingLabel, langLabel] {
            label.textColor = Theme.accent
        }
        for label in [lineColLabel, inputModeLabel, layoutModeLabel, characterCodeLabel, fontSizeLabel] {
            label.textColor = Theme.accent
        }
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
        updateCharacterCode(at: state.utf16Offset)
        if state.selectedLineCount > 0 {
            selectionLabel.stringValue += " · \(state.selectedLineCount) lines"
        }
        if let width = state.boxWidth, let height = state.boxHeight {
            selectionLabel.stringValue += " · BOX \(width)×\(height)"
        }
        selectionLabel.toolTip = "Selected UTF-16 units: \(state.selectedUTF16Length)"
        needsLayout = true
    }

    func updateDocumentMetrics(text: String, fontSize: CGFloat) {
        documentText = text
        let lines = text.isEmpty ? 1 : text.reduce(1) { $1 == "\n" ? $0 + 1 : $0 }
        totalsLabel.stringValue = "\(lines) lines · \(text.count) chars"
        fontSizeLabel.stringValue = "\(Int(fontSize.rounded())) pt"
        needsLayout = true
    }

    private func updateCharacterCode(at utf16Offset: Int) {
        let ns = documentText as NSString
        guard utf16Offset >= 0, utf16Offset < ns.length else {
            characterCodeLabel.stringValue = ""; return
        }
        let value = ns.substring(with: ns.rangeOfComposedCharacterSequence(at: utf16Offset))
        let scalars = value.unicodeScalars.map { String(format: "U+%04X", $0.value) }
        characterCodeLabel.stringValue = scalars.count == 1 ? scalars[0] : "\(scalars.count) codes"
        characterCodeLabel.toolTip = scalars.joined(separator: " ")
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

    func updateInputMode(_ mode: EditorInputMode) {
        inputModeLabel.stringValue = mode == .insert ? "INS" : "OVR"
        let name = mode == .insert ? "insert" : "overwrite"
        inputModeLabel.setAccessibilityLabel("Input mode: \(name)")
        inputModeLabel.toolTip = "Current input mode: \(name)"
    }

    func updateLayoutMode(isVertical: Bool, isColumn: Bool, columnCount: Int) {
        let text: String
        let description: String
        if isColumn {
            text = "COL×\(max(2, columnCount))"; description = "continuous column"
        } else if isVertical {
            text = "VERT"; description = "vertical writing"
        } else {
            text = "HORZ"; description = "horizontal writing"
        }
        layoutModeLabel.stringValue = text
        layoutModeLabel.setAccessibilityLabel("Writing layout: \(description)")
        layoutModeLabel.toolTip = "Current layout: \(description); click to choose"
        needsLayout = true
    }

    func updateReadOnly(_ isReadOnly: Bool) {
        updateAccessMode(isReadOnly: isReadOnly, isViewMode: false)
    }

    func updateAccessMode(isReadOnly: Bool, isViewMode: Bool) {
        self.isReadOnly = isReadOnly || isViewMode
        readOnlyLabel.stringValue = isViewMode ? "View Mode" : "Read-Only"
        readOnlyLabel.toolTip = isViewMode
            ? "View Mode prevents editing without changing the file"
            : "This file is read-only on disk; use Save As to save changes"
        applyConfiguredVisibility()
        needsLayout = true
    }

    func updateCapsLock(_ isEnabled: Bool) {
        isCapsLockEnabled = isEnabled
        applyConfiguredVisibility(); needsLayout = true
    }

    func updateMacroActivity(isRunning: Bool) {
        self.isMacroRunning = isRunning
        macroActivityLabel.stringValue = isMacroRecording ? "REC" : "MACRO"
        applyConfiguredVisibility(); needsLayout = true
    }

    func updateMacroRecording(isRecording: Bool) {
        isMacroRecording = isRecording
        macroActivityLabel.stringValue = isRecording ? "REC" : "MACRO"
        macroActivityLabel.setAccessibilityLabel(isRecording ? "Macro recording" : "Macro running")
        macroActivityLabel.toolTip = isRecording ? "Commands are being recorded" : "A macro is currently running"
        applyConfiguredVisibility(); needsLayout = true
    }

    func updateLargeFileMode(_ mode: LargeFileMode) {
        largeFileMode = mode
        largeFileModeLabel.stringValue = SettingsLocalization.text(
            mode == .readOnly ? "largeReadOnly" : "reducedFeatures")
        applyConfiguredVisibility()
        needsLayout = true
    }

    override func rightMouseDown(with event: NSEvent) {
        let menu = NSMenu(title: "Customize Status Bar")
        for field in StatusBarField.allCases {
            let item = NSMenuItem(title: field.title, action: #selector(toggleStatusField(_:)), keyEquivalent: "")
            item.target = self; item.representedObject = field.rawValue
            item.state = configuredFields.contains(field) ? .on : .off
            item.isEnabled = field != .cursorPosition
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let restore = NSMenuItem(title: "Restore Default Status Bar", action: #selector(restoreStatusFields), keyEquivalent: "")
        restore.target = self; menu.addItem(restore)
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    @objc private func toggleStatusField(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let field = StatusBarField(rawValue: rawValue), field != .cursorPosition else { return }
        if configuredFields.contains(field) { configuredFields.remove(field) } else { configuredFields.insert(field) }
        persistConfiguredFields(); applyConfiguredVisibility(); needsLayout = true
    }

    @objc private func restoreStatusFields() {
        configuredFields = Set(StatusBarField.allCases)
        persistConfiguredFields(); applyConfiguredVisibility(); needsLayout = true
    }

    func setConfiguredFieldsForTesting(_ fields: Set<StatusBarField>) {
        configuredFields = fields.union([.cursorPosition])
        applyConfiguredVisibility(); needsLayout = true
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
        case .cursorPosition: return visibleFrame(lineColLabel)
        case .characterCode:
            return characterCodeLabel.stringValue.isEmpty ? nil : visibleFrame(characterCodeLabel)
        case .inputMode: return visibleFrame(inputModeLabel)
        case .layoutMode: return visibleFrame(layoutModeLabel)
        case .fontSize: return visibleFrame(fontSizeLabel)
        case .largeFileMode: return visibleFrame(largeFileModeLabel)
        case .encoding: return visibleFrame(encLabel)
        case .byteOrderMark: return visibleFrame(bomLabel)
        case .lineEnding: return visibleFrame(lineEndingLabel)
        case .languageProfile: return visibleFrame(langLabel)
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

    private var leftFields: [(StatusBarField, NSTextField, CGFloat)] {[
        (.cursorPosition, lineColLabel, 105), (.selection, selectionLabel, 130),
        (.indentation, indentLabel, 85), (.inputMode, inputModeLabel, 34),
        (.layoutMode, layoutModeLabel, 58),
        (.totals, totalsLabel, 125), (.characterCode, characterCodeLabel, 70),
        (.fontSize, fontSizeLabel, 45),
    ]}

    private var rightFields: [(StatusBarField, NSTextField)] {[
        (.macroActivity, macroActivityLabel), (.capsLock, capsLockLabel),
        (.readOnly, readOnlyLabel),
        (.largeFileMode, largeFileModeLabel),
        (.lineEnding, lineEndingLabel), (.byteOrderMark, bomLabel),
        (.encoding, encLabel), (.languageProfile, langLabel),
    ]}

    private func applyConfiguredVisibility() {
        for (field, label, _) in leftFields { label.isHidden = !configuredFields.contains(field) }
        for (field, label) in rightFields {
            let stateAllowsVisibility = field == .macroActivity ? (isMacroRunning || isMacroRecording)
                : field == .capsLock ? isCapsLockEnabled
                : field == .readOnly ? isReadOnly
                : field == .largeFileMode ? largeFileMode != .normal : true
            label.isHidden = !configuredFields.contains(field) || !stateAllowsVisibility
        }
    }

    private func persistConfiguredFields() {
        UserDefaults.standard.set(configuredFields.map(\.rawValue).sorted(), forKey: Self.fieldsDefaultsKey)
    }

    private func visibleFrame(_ label: NSTextField) -> NSRect? {
        label.isHidden ? nil : label.frame
    }
}
