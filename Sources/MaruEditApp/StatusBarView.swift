import AppKit
import MaruEditCore

enum StatusBarControl: CaseIterable {
    case cursorPosition, totals, characterCode, inputMode, layoutMode, fontSize
    case macroActivity, largeFileMode, encoding, byteOrderMark, lineEnding, languageProfile
}

struct CharacterCountConfiguration: Codable, Equatable {
    var fullWidth = 1.0
    var halfWidth = 1.0
    var fullWidthSpace = 1.0
    var halfWidthSpace = 1.0
    var tab = 1.0
    var lineBreak = 1.0

    static let standard = CharacterCountConfiguration()
}

enum StatusBarField: String, CaseIterable {
    case cursorPosition, selection, indentation, inputMode, layoutMode, totals, characterCode, fontSize
    case macroActivity, capsLock, readOnly, viewMode, largeFileMode, lineEnding, byteOrderMark, encoding, languageProfile

    var title: String {
        AppLocalization.string("status.field.\(rawValue)")
    }
}

@MainActor
protocol StatusBarViewDelegate: AnyObject {
    func statusBar(
        _ statusBar: StatusBarView, didClick control: StatusBarControl, at point: NSPoint)
}

private final class ActionableStatusLabel: NSTextField {
    var onAccessibilityPress: (() -> Bool)?

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 || event.keyCode == 76 || event.charactersIgnoringModifiers == " " {
            _ = accessibilityPerformPress()
        } else {
            super.keyDown(with: event)
        }
    }

    override func accessibilityPerformPress() -> Bool {
        onAccessibilityPress?() ?? false
    }
}

final class StatusBarView: NSView {
    weak var delegate: StatusBarViewDelegate?
    var onPreferredWidthChange: (() -> Void)?

    private let lineColLabel = ActionableStatusLabel(labelWithString: "Ln 1, Col 1")
    private let messageLabel = NSTextField(labelWithString: "")
    private let selectionLabel = NSTextField(labelWithString: "")
    private let indentLabel = NSTextField(labelWithString: "Spaces: 4")
    private let inputModeLabel = ActionableStatusLabel(labelWithString: "INS")
    private let layoutModeLabel = ActionableStatusLabel(labelWithString: "HORZ")
    private let totalsLabel = ActionableStatusLabel(labelWithString: "1 lines · 0 chars")
    private let characterCodeLabel = ActionableStatusLabel(labelWithString: "")
    private let fontSizeLabel = ActionableStatusLabel(labelWithString: "13 pt")
    private let macroActivityLabel = ActionableStatusLabel(labelWithString: "MACRO")
    private let capsLockLabel = NSTextField(labelWithString: "CAPS")
    private let langLabel = ActionableStatusLabel(labelWithString: "Plain Text")
    private let encLabel = ActionableStatusLabel(labelWithString: "UTF-8")
    private let bomLabel = ActionableStatusLabel(labelWithString: "No BOM")
    private let lineEndingLabel = ActionableStatusLabel(labelWithString: "LF")
    private let readOnlyLabel = NSTextField(labelWithString: AppLocalization.string("status.readOnly"))
    private let viewModeLabel = NSTextField(labelWithString: AppLocalization.string("status.viewMode"))
    private let largeFileModeLabel = ActionableStatusLabel(labelWithString: "Reduced Features")
    private var cursorText = "Ln 1, Col 1"
    private var documentText = ""
    private var cursorUTF16Offset = 0
    private var documentEncoding: TextEncoding = .utf8
    private var messageWorkItem: DispatchWorkItem?
    private var configuredFields = Set(StatusBarField.allCases)
    private var isReadOnly = false
    private var isViewMode = false
    private var isCapsLockEnabled = false
    private var isMacroRunning = false
    private var isMacroRecording = false
    private var currentInputMode: EditorInputMode = .insert
    private var largeFileMode: LargeFileMode = .normal
    private var showsCursorPosition = true
    private static let fieldsDefaultsKey = "MaruClassicStatusBarFields"
    private static let normalFieldsDefaultsKey = "MaruClassicStatusBarNormalFields"
    private static let mergedFieldsDefaultsKey = "MaruClassicStatusBarMergedFields"
    private static let mergedFieldsVersionKey = "MaruClassicStatusBarMergedFieldsVersion"
    private static let currentMergedFieldsVersion = 1
    private static let clicksDefaultsKey = "MaruClassicStatusBarClicksEnabled"
    private static let countDefaultsKey = "MaruClassicCharacterCountConfiguration"
    private static let defaultMergedFields: Set<StatusBarField> = [
        .encoding, .inputMode,
    ]
    private static let formerDefaultMergedFields: Set<StatusBarField> = [
        .inputMode, .totals, .lineEnding, .byteOrderMark, .encoding,
    ]
    private(set) var areClicksEnabled = true
    private(set) var isMergedMode = false
    private var usesClassicAppearance = true
    private(set) var characterCountConfiguration = CharacterCountConfiguration.standard

    var displayedLeadingText: String {
        messageLabel.stringValue.isEmpty ? lineColLabel.stringValue : messageLabel.stringValue
    }
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
    var preferredMergedWidth: CGFloat {
        applyConfiguredVisibility()
        let visibleRight = rightFields.filter { !$0.1.isHidden }
        let rightWidth = visibleRight.reduce(CGFloat.zero) { result, item in
            item.1.sizeToFit()
            return result + max(0, item.1.frame.width)
        } + CGFloat(visibleRight.count * 14)
        let visibleLeft = leftFields.filter { !$0.1.isHidden }
        let leftWidth = visibleLeft.reduce(CGFloat.zero) { $0 + $1.2 }
            + CGFloat(max(0, visibleLeft.count - 1) * 4)
        return ceil(max(80, rightWidth + leftWidth))
    }
    var isMessageAreaVisible: Bool { !messageLabel.isHidden }
    var displayedCapsLockText: String? { capsLockLabel.isHidden ? nil : capsLockLabel.stringValue }
    var displayedMacroActivityText: String? {
        macroActivityLabel.isHidden ? nil : macroActivityLabel.stringValue
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = Theme.statusBg.cgColor
        if let values = UserDefaults.standard.stringArray(forKey: Self.normalFieldsDefaultsKey)
            ?? UserDefaults.standard.stringArray(forKey: Self.fieldsDefaultsKey) {
            configuredFields = Set(values.compactMap(StatusBarField.init(rawValue:)))
            configuredFields.insert(.cursorPosition)
        }
        if UserDefaults.standard.object(forKey: Self.clicksDefaultsKey) != nil {
            areClicksEnabled = UserDefaults.standard.bool(forKey: Self.clicksDefaultsKey)
        }
        if let data = UserDefaults.standard.data(forKey: Self.countDefaultsKey),
           let decoded = try? JSONDecoder().decode(CharacterCountConfiguration.self, from: data) {
            characterCountConfiguration = decoded
        }
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        applyConfiguredVisibility()
        let midY = (bounds.height - 16) / 2
        if isMergedMode {
            layoutMergedFields(midY: midY)
            window?.invalidateCursorRects(for: self)
            return
        }
        var right = bounds.width - 14
        for (field, label) in rightFields.reversed() where !label.isHidden {
            guard configuredFields.contains(field) else { continue }
            label.sizeToFit()
            if right - label.frame.width < (isMergedMode ? 0 : 4) {
                label.isHidden = true
            } else {
                right -= label.frame.width
                label.frame.origin = NSPoint(x: right, y: midY); right -= 14
            }
        }

        if isMergedMode {
            messageLabel.isHidden = true
        } else {
            messageLabel.isHidden = false
            messageLabel.frame = NSRect(x: 6, y: midY, width: min(110, max(0, right - 14)), height: 16)
        }
        var x: CGFloat = isMergedMode ? 6 : 120
        for (_, label, width) in leftFields {
            guard !label.isHidden else { continue }
            let actualWidth = width
            if x + actualWidth > right - 8 {
                label.isHidden = true
            } else {
                label.frame = NSRect(x: x, y: midY, width: actualWidth, height: 16)
                x += actualWidth + 4
            }
        }
        window?.invalidateCursorRects(for: self)
    }

    private func layoutMergedFields(midY: CGFloat) {
        messageLabel.isHidden = true
        var x = CGFloat.zero
        for (_, label, width) in leftFields where !label.isHidden {
            guard x + width <= bounds.width else { label.isHidden = true; continue }
            label.frame = NSRect(x: x, y: midY, width: width, height: 16)
            x += width + 4
        }
        for (_, label) in rightFields where !label.isHidden {
            label.sizeToFit()
            let width = ceil(label.frame.width)
            guard x + width <= bounds.width else { label.isHidden = true; continue }
            label.frame = NSRect(x: x, y: midY, width: width, height: 16)
            x += width + 14
        }
    }

    private func setup() {
        let labels = [messageLabel, lineColLabel, selectionLabel, indentLabel, inputModeLabel, layoutModeLabel,
                      totalsLabel, characterCodeLabel, fontSizeLabel, langLabel, encLabel,
                      bomLabel, lineEndingLabel, macroActivityLabel, capsLockLabel,
                      readOnlyLabel, viewModeLabel, largeFileModeLabel]
        for label in labels {
            label.font = Theme.uiFontSmall
            label.textColor = Theme.statusText
            label.isBordered = false
            label.isEditable = false
            label.drawsBackground = false
            addSubview(label)
        }
        let controls: [(NSTextField, String, String)] = [
            (encLabel, AppLocalization.string("status.accessibility.encoding"), AppLocalization.string("status.tooltip.encoding")),
            (bomLabel, AppLocalization.string("status.accessibility.bom"), AppLocalization.string("status.tooltip.bom")),
            (lineEndingLabel, AppLocalization.string("status.accessibility.lineEnding"), AppLocalization.string("status.tooltip.lineEnding")),
            (langLabel, AppLocalization.string("status.accessibility.language"), AppLocalization.string("status.tooltip.language")),
        ]
        for (label, accessibilityLabel, toolTip) in controls {
            label.textColor = Theme.accent
            label.setAccessibilityRole(.button)
            label.setAccessibilityLabel(accessibilityLabel)
            label.toolTip = toolTip
        }
        lineColLabel.setAccessibilityLabel(AppLocalization.string("status.accessibility.cursor"))
        totalsLabel.setAccessibilityLabel(AppLocalization.string("status.accessibility.totals"))
        totalsLabel.toolTip = AppLocalization.string("status.tooltip.totals")
        characterCodeLabel.setAccessibilityLabel(AppLocalization.string("status.accessibility.characterCode"))
        characterCodeLabel.toolTip = AppLocalization.string("status.tooltip.characterCode")
        fontSizeLabel.setAccessibilityLabel(AppLocalization.string("status.accessibility.fontSize"))
        fontSizeLabel.toolTip = AppLocalization.string("status.tooltip.fontSize")
        selectionLabel.setAccessibilityLabel(AppLocalization.string("status.accessibility.selection"))
        inputModeLabel.setAccessibilityLabel(AppLocalization.string("status.accessibility.inputInsert"))
        inputModeLabel.toolTip = AppLocalization.string("status.tooltip.inputInsert")
        layoutModeLabel.setAccessibilityLabel(AppLocalization.string("status.accessibility.layoutHorizontal"))
        layoutModeLabel.toolTip = AppLocalization.string("status.tooltip.layoutHorizontal")
        for label in [lineColLabel, totalsLabel, inputModeLabel, layoutModeLabel, characterCodeLabel, fontSizeLabel] {
            label.textColor = Theme.accent
            label.setAccessibilityRole(.button)
        }
        readOnlyLabel.textColor = .systemOrange
        readOnlyLabel.toolTip = AppLocalization.string("status.tooltip.readOnly")
        readOnlyLabel.isHidden = true
        viewModeLabel.textColor = .systemOrange
        viewModeLabel.toolTip = AppLocalization.string("status.tooltip.viewMode")
        viewModeLabel.isHidden = true
        capsLockLabel.textColor = .systemOrange
        capsLockLabel.setAccessibilityLabel(AppLocalization.string("status.accessibility.capsLock"))
        capsLockLabel.toolTip = AppLocalization.string("status.tooltip.capsLock")
        capsLockLabel.isHidden = true
        macroActivityLabel.textColor = .systemRed
        macroActivityLabel.setAccessibilityRole(.button)
        macroActivityLabel.setAccessibilityLabel(AppLocalization.string("status.accessibility.macroRunning"))
        macroActivityLabel.toolTip = AppLocalization.string("status.tooltip.macroRunning")
        macroActivityLabel.isHidden = true
        largeFileModeLabel.textColor = .systemOrange
        largeFileModeLabel.setAccessibilityRole(.button)
        largeFileModeLabel.setAccessibilityLabel(SettingsLocalization.text("largeFileMode"))
        largeFileModeLabel.toolTip = SettingsLocalization.text("largeFileTooltip")
        largeFileModeLabel.isHidden = true

        let actionable: [(ActionableStatusLabel, StatusBarControl)] = [
            (lineColLabel, .cursorPosition), (totalsLabel, .totals),
            (characterCodeLabel, .characterCode), (inputModeLabel, .inputMode),
            (layoutModeLabel, .layoutMode), (fontSizeLabel, .fontSize),
            (macroActivityLabel, .macroActivity), (largeFileModeLabel, .largeFileMode),
            (encLabel, .encoding), (bomLabel, .byteOrderMark),
            (lineEndingLabel, .lineEnding), (langLabel, .languageProfile),
        ]
        for (label, control) in actionable {
            label.onAccessibilityPress = { [weak self, weak label] in
                guard let self, let label, self.areClicksEnabled, !label.isHidden,
                      self.frame(for: control) != nil else { return false }
                self.activate(control)
                return true
            }
        }
    }

    func applyTheme() {
        layer?.backgroundColor = Theme.statusBg.cgColor
        for label in [messageLabel, lineColLabel, selectionLabel, indentLabel, inputModeLabel, layoutModeLabel,
                      totalsLabel, characterCodeLabel, fontSizeLabel,
                      langLabel, encLabel, bomLabel, lineEndingLabel] {
            label.textColor = Theme.statusText
        }
        for label in [encLabel, bomLabel, lineEndingLabel, langLabel] {
            label.textColor = Theme.accent
        }
        for label in [lineColLabel, totalsLabel, inputModeLabel, layoutModeLabel, characterCodeLabel, fontSizeLabel] {
            label.textColor = Theme.accent
        }
        applyAppearance()
    }

    func setClassicAppearance(_ enabled: Bool) {
        usesClassicAppearance = enabled
        refreshClassicFieldText()
        applyAppearance()
    }

    func refreshLocalization() {
        readOnlyLabel.stringValue = AppLocalization.string("status.readOnly")
        viewModeLabel.stringValue = AppLocalization.string("status.viewMode")
        largeFileModeLabel.stringValue = SettingsLocalization.text(
            largeFileMode == .readOnly ? "largeReadOnly" : "reducedFeatures")
        refreshClassicFieldText()
        needsLayout = true
        if isMergedMode { onPreferredWidthChange?() }
    }

    private func refreshClassicFieldText() {
        encLabel.stringValue = usesClassicAppearance && isMergedMode && documentEncoding == .utf8
            ? "Unicode (UTF-8)" : documentEncoding.displayName
        let isOverwrite = currentInputMode == .overwrite
        if usesClassicAppearance && isMergedMode {
            inputModeLabel.stringValue = isOverwrite
                ? AppLocalization.string(.inputOverwrite)
                : AppLocalization.string(.inputInsert)
        } else {
            inputModeLabel.stringValue = isOverwrite ? "OVR" : "INS"
        }
    }

    private func applyAppearance() {
        let labels = [messageLabel, lineColLabel, selectionLabel, indentLabel, inputModeLabel,
                      layoutModeLabel, totalsLabel, characterCodeLabel, fontSizeLabel,
                      macroActivityLabel, capsLockLabel, readOnlyLabel, viewModeLabel,
                      largeFileModeLabel, lineEndingLabel, bomLabel, encLabel, langLabel]
        layer?.backgroundColor = (usesClassicAppearance
            ? NSColor(calibratedWhite: 0.91, alpha: 1) : Theme.statusBg).cgColor
        for label in labels {
            label.wantsLayer = true
            label.layer?.borderWidth = usesClassicAppearance ? 0.5 : 0
            label.layer?.borderColor = NSColor(calibratedWhite: 0.68, alpha: 1).cgColor
            label.layer?.backgroundColor = usesClassicAppearance
                ? NSColor(calibratedWhite: 0.94, alpha: 1).cgColor : NSColor.clear.cgColor
            if usesClassicAppearance && ![macroActivityLabel, capsLockLabel, readOnlyLabel,
                                          viewModeLabel, largeFileModeLabel].contains(where: { $0 === label }) {
                label.textColor = NSColor(calibratedWhite: 0.12, alpha: 1)
            }
        }
    }

    func updateCursor(_ state: EditorCursorState) {
        cursorUTF16Offset = state.utf16Offset
        cursorText = "Ln \(state.lineNumber), Col \(state.displayColumn)"
        lineColLabel.stringValue = cursorText
        if state.selectedCharacterCount == 0 {
            selectionLabel.stringValue = state.selectionRangeCount > 1
                ? "\(state.selectionRangeCount) carets" : ""
        } else if state.selectionRangeCount > 1 {
            selectionLabel.stringValue = "Sel \(state.selectedCharacterCount) (\(state.selectionRangeCount) ranges)"
        } else {
            selectionLabel.stringValue = "Sel \(state.selectedCharacterCount)"
        }
        lineColLabel.toolTip = AppLocalization.string("status.tooltip.utf16Offset", [state.utf16Offset])
        updateCharacterCode(at: state.utf16Offset)
        if state.selectedLineCount > 0 {
            selectionLabel.stringValue += " · \(state.selectedLineCount) lines"
        }
        if let width = state.boxWidth, let height = state.boxHeight {
            let displayWidth = state.boxWidthIsPixels ? "\(width)px" : "\(width)"
            selectionLabel.stringValue += " · BOX \(displayWidth)×\(height)"
        }
        selectionLabel.toolTip = AppLocalization.string("status.tooltip.selectedUTF16", [state.selectedUTF16Length])
        needsLayout = true
    }

    func setCursorPositionVisible(_ visible: Bool) {
        showsCursorPosition = visible
        applyConfiguredVisibility()
        needsLayout = true
    }

    func updateDocumentMetrics(text: String, fontSize: CGFloat) {
        documentText = text
        let lines = text.isEmpty ? 1 : text.reduce(1) { $1 == "\n" ? $0 + 1 : $0 }
        totalsLabel.stringValue = "\(lines) lines · \(configuredCharacterCount(text)) chars"
        fontSizeLabel.stringValue = "\(Int(fontSize.rounded())) pt"
        needsLayout = true
    }

    func setCharacterCountConfiguration(_ configuration: CharacterCountConfiguration) {
        characterCountConfiguration = configuration
        if let data = try? JSONEncoder().encode(configuration) {
            UserDefaults.standard.set(data, forKey: Self.countDefaultsKey)
        }
        updateDocumentMetrics(text: documentText, fontSize: CGFloat(
            Int(fontSizeLabel.stringValue.split(separator: " ").first ?? "13") ?? 13))
    }

    private func configuredCharacterCount(_ text: String) -> Int {
        var total = 0.0
        for character in text {
            if character == "\n" || character == "\r" { total += characterCountConfiguration.lineBreak }
            else if character == "\t" { total += characterCountConfiguration.tab }
            else if character == " " { total += characterCountConfiguration.halfWidthSpace }
            else if character == "　" { total += characterCountConfiguration.fullWidthSpace }
            else if character.unicodeScalars.allSatisfy({ $0.value < 0x80 }) {
                total += characterCountConfiguration.halfWidth
            } else {
                total += characterCountConfiguration.fullWidth
            }
        }
        return Int(ceil(total))
    }

    private func updateCharacterCode(at utf16Offset: Int) {
        let ns = documentText as NSString
        guard utf16Offset >= 0, utf16Offset < ns.length else {
            characterCodeLabel.stringValue = ""; return
        }
        let value = ns.substring(with: ns.rangeOfComposedCharacterSequence(at: utf16Offset))
        let scalars = value.unicodeScalars.map { String(format: "U+%04X", $0.value) }
        let unicode = scalars.joined(separator: " ")
        let currentBytes = encodedBytes(value, as: documentEncoding)
        if documentEncoding == .utf8 || documentEncoding == .utf16LittleEndian
            || documentEncoding == .utf16BigEndian {
            characterCodeLabel.stringValue = scalars.count == 1 ? scalars[0] : "\(scalars.count) codes"
        } else if let currentBytes {
            characterCodeLabel.stringValue = currentBytes
        } else {
            characterCodeLabel.stringValue = scalars.count == 1 ? scalars[0] : "\(scalars.count) codes"
        }
        var details = ["Unicode: \(unicode)"]
        if let utf8 = encodedBytes(value, as: .utf8) { details.append("UTF-8: \(utf8)") }
        if let shiftJIS = encodedBytes(value, as: .windows31J) {
            details.append("Windows-31J (Shift-JIS): \(shiftJIS)")
        }
        if documentEncoding != .utf8, documentEncoding != .windows31J,
           let currentBytes {
            details.append("\(documentEncoding.displayName): \(currentBytes)")
        }
        if scalars.count > 1 { details.append("Composed character: \(scalars.count) code points") }
        characterCodeLabel.toolTip = details.joined(separator: "\n")
    }

    private func encodedBytes(_ value: String, as encoding: TextEncoding) -> String? {
        guard let foundation = encoding.foundationEncoding,
              let data = value.data(using: foundation, allowLossyConversion: false) else { return nil }
        return data.map { String(format: "%02X", $0) }.joined(separator: " ")
    }

    func showTransientMessage(_ message: String, duration: TimeInterval = 1.5) {
        messageWorkItem?.cancel()
        if message.isEmpty {
            messageWorkItem = nil
            messageLabel.stringValue = ""
            needsLayout = true
            return
        }
        messageLabel.stringValue = message
        let item = DispatchWorkItem { [weak self] in
            self?.messageWorkItem = nil
            self?.messageLabel.stringValue = ""
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
        documentEncoding = encoding
        encLabel.stringValue = usesClassicAppearance && isMergedMode && encoding == .utf8
            ? "Unicode (UTF-8)" : encoding.displayName
        updateCharacterCode(at: cursorUTF16Offset)
        needsLayout = true
        if isMergedMode { onPreferredWidthChange?() }
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
        currentInputMode = mode
        inputModeLabel.stringValue = usesClassicAppearance && isMergedMode
            ? (mode == .insert
                ? AppLocalization.string(.inputInsert)
                : AppLocalization.string(.inputOverwrite))
            : (mode == .insert ? "INS" : "OVR")
        inputModeLabel.setAccessibilityLabel(AppLocalization.string(
            mode == .insert ? "status.accessibility.inputInsert" : "status.accessibility.inputOverwrite"))
        inputModeLabel.toolTip = AppLocalization.string(
            mode == .insert ? "status.tooltip.currentInputInsert" : "status.tooltip.currentInputOverwrite")
        needsLayout = true
        if isMergedMode { onPreferredWidthChange?() }
    }

    func updateLayoutMode(isVertical: Bool, isColumn: Bool, columnCount: Int) {
        let text: String
        let descriptionKey: String
        if isColumn {
            text = "COL×\(max(2, columnCount))"; descriptionKey = "status.layout.column"
        } else if isVertical {
            text = "VERT"; descriptionKey = "status.layout.vertical"
        } else {
            text = "HORZ"; descriptionKey = "status.layout.horizontal"
        }
        let description = AppLocalization.string(descriptionKey)
        layoutModeLabel.stringValue = text
        layoutModeLabel.setAccessibilityLabel(AppLocalization.string("status.accessibility.layout", [description]))
        layoutModeLabel.toolTip = AppLocalization.string("status.tooltip.currentLayout", [description])
        needsLayout = true
    }

    func updateReadOnly(_ isReadOnly: Bool) {
        updateAccessMode(isReadOnly: isReadOnly, isViewMode: false)
    }

    func updateAccessMode(isReadOnly: Bool, isViewMode: Bool) {
        self.isReadOnly = isReadOnly
        self.isViewMode = isViewMode
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
        macroActivityLabel.setAccessibilityLabel(AppLocalization.string(
            isRecording ? "status.accessibility.macroRecording" : "status.accessibility.macroRunning"))
        macroActivityLabel.toolTip = AppLocalization.string(
            isRecording ? "status.tooltip.macroRecording" : "status.tooltip.macroRunning")
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
        let menu = NSMenu(title: AppLocalization.string("status.customize"))
        for field in StatusBarField.allCases {
            let item = NSMenuItem(title: field.title, action: #selector(toggleStatusField(_:)), keyEquivalent: "")
            item.target = self; item.representedObject = field.rawValue
            item.state = configuredFields.contains(field) ? .on : .off
            item.isEnabled = field != .cursorPosition
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let clicks = NSMenuItem(
            title: AppLocalization.string("status.enableClicks"), action: #selector(toggleClickActions),
            keyEquivalent: "")
        clicks.target = self; clicks.state = areClicksEnabled ? .on : .off
        menu.addItem(clicks)
        let restore = NSMenuItem(title: AppLocalization.string("status.restore"), action: #selector(restoreStatusFields), keyEquivalent: "")
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

    @objc private func toggleClickActions() {
        setClickActionsEnabled(!areClicksEnabled)
        UserDefaults.standard.set(areClicksEnabled, forKey: Self.clicksDefaultsKey)
    }

    func setClickActionsEnabled(_ enabled: Bool) {
        areClicksEnabled = enabled
        window?.invalidateCursorRects(for: self)
    }

    func setConfiguredFieldsForTesting(_ fields: Set<StatusBarField>) {
        configuredFields = fields.union([.cursorPosition])
        applyConfiguredVisibility(); needsLayout = true
    }

    func setMergedMode(_ merged: Bool) {
        guard isMergedMode != merged else { return }
        persistConfiguredFields()
        isMergedMode = merged
        refreshClassicFieldText()
        let key = merged ? Self.mergedFieldsDefaultsKey : Self.normalFieldsDefaultsKey
        let savedFields = UserDefaults.standard.stringArray(forKey: key)
            .map { Set($0.compactMap(StatusBarField.init(rawValue:))) }
        if merged, UserDefaults.standard.integer(forKey: Self.mergedFieldsVersionKey)
            < Self.currentMergedFieldsVersion {
            configuredFields = savedFields == nil || savedFields == Self.formerDefaultMergedFields
                ? Self.defaultMergedFields : savedFields!
            UserDefaults.standard.set(configuredFields.map(\.rawValue), forKey: key)
            UserDefaults.standard.set(Self.currentMergedFieldsVersion, forKey: Self.mergedFieldsVersionKey)
        } else {
            configuredFields = savedFields ?? (merged ? Self.defaultMergedFields : Set(StatusBarField.allCases))
        }
        configuredFields.insert(.cursorPosition)
        applyConfiguredVisibility(); needsLayout = true
    }

    func accessibilityElement(for control: StatusBarControl) -> NSView? {
        switch control {
        case .cursorPosition: lineColLabel
        case .totals: totalsLabel
        case .characterCode: characterCodeLabel
        case .inputMode: inputModeLabel
        case .layoutMode: layoutModeLabel
        case .fontSize: fontSizeLabel
        case .macroActivity: macroActivityLabel
        case .largeFileMode: largeFileModeLabel
        case .encoding: encLabel
        case .byteOrderMark: bomLabel
        case .lineEnding: lineEndingLabel
        case .languageProfile: langLabel
        }
    }

    var keyboardFocusableViews: [NSView] {
        StatusBarControl.allCases.compactMap { control in
            guard let view = accessibilityElement(for: control), !view.isHidden,
                  frame(for: control) != nil else { return nil }
            return view
        }
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
        guard areClicksEnabled else { return }
        for control in StatusBarControl.allCases {
            if let frame = frame(for: control) { addCursorRect(frame, cursor: .pointingHand) }
        }
    }

    func frame(for control: StatusBarControl) -> NSRect? {
        switch control {
        case .cursorPosition: return visibleFrame(lineColLabel)
        case .totals: return visibleFrame(totalsLabel)
        case .characterCode:
            return characterCodeLabel.stringValue.isEmpty ? nil : visibleFrame(characterCodeLabel)
        case .inputMode: return visibleFrame(inputModeLabel)
        case .layoutMode: return visibleFrame(layoutModeLabel)
        case .fontSize: return visibleFrame(fontSizeLabel)
        case .macroActivity: return visibleFrame(macroActivityLabel)
        case .largeFileMode: return visibleFrame(largeFileModeLabel)
        case .encoding: return visibleFrame(encLabel)
        case .byteOrderMark: return visibleFrame(bomLabel)
        case .lineEnding: return visibleFrame(lineEndingLabel)
        case .languageProfile: return visibleFrame(langLabel)
        }
    }

    func activate(_ control: StatusBarControl, at point: NSPoint? = nil) {
        guard areClicksEnabled, let frame = frame(for: control) else { return }
        delegate?.statusBar(
            self, didClick: control,
            at: point ?? NSPoint(x: frame.minX, y: frame.maxY))
    }

    private func control(at point: NSPoint) -> StatusBarControl? {
        StatusBarControl.allCases.first { frame(for: $0)?.contains(point) == true }
    }

    private var leftFields: [(StatusBarField, NSTextField, CGFloat)] {[
        (.cursorPosition, lineColLabel, 105), (.selection, selectionLabel, 130),
        (.indentation, indentLabel, 85),
        (.layoutMode, layoutModeLabel, 58),
        (.totals, totalsLabel, 125), (.characterCode, characterCodeLabel, 70),
        (.fontSize, fontSizeLabel, 45),
    ]}

    private var rightFields: [(StatusBarField, NSTextField)] {[
        (.macroActivity, macroActivityLabel), (.capsLock, capsLockLabel),
        (.readOnly, readOnlyLabel), (.viewMode, viewModeLabel),
        (.largeFileMode, largeFileModeLabel),
        (.lineEnding, lineEndingLabel), (.byteOrderMark, bomLabel),
        (.encoding, encLabel), (.inputMode, inputModeLabel), (.languageProfile, langLabel),
    ]}

    private func applyConfiguredVisibility() {
        for (field, label, _) in leftFields {
            label.isHidden = !configuredFields.contains(field)
                || (field == .cursorPosition && !showsCursorPosition)
        }
        for (field, label) in rightFields {
            let stateAllowsVisibility = field == .macroActivity ? (isMacroRunning || isMacroRecording)
                : field == .capsLock ? isCapsLockEnabled
                : field == .readOnly ? isReadOnly
                : field == .viewMode ? isViewMode
                : field == .largeFileMode ? largeFileMode != .normal : true
            label.isHidden = !configuredFields.contains(field) || !stateAllowsVisibility
        }
    }

    private func persistConfiguredFields() {
        let key = isMergedMode ? Self.mergedFieldsDefaultsKey : Self.normalFieldsDefaultsKey
        UserDefaults.standard.set(configuredFields.map(\.rawValue).sorted(), forKey: key)
    }

    private func visibleFrame(_ label: NSTextField) -> NSRect? {
        label.isHidden ? nil : label.frame
    }
}
