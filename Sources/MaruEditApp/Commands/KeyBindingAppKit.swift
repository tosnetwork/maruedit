import AppKit
import MaruEditCore

extension KeyGesture {
    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
        var modifiers = Set<KeyModifier>()
        if flags.contains(.command) { modifiers.insert(.command) }
        if flags.contains(.shift) { modifiers.insert(.shift) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.control) { modifiers.insert(.control) }

        guard let characters = event.charactersIgnoringModifiers, let scalar = characters.unicodeScalars.first else { return nil }
        let key: String
        switch Int(scalar.value) {
        case NSUpArrowFunctionKey: key = "up"
        case NSDownArrowFunctionKey: key = "down"
        case NSLeftArrowFunctionKey: key = "left"
        case NSRightArrowFunctionKey: key = "right"
        case NSF1FunctionKey...NSF35FunctionKey: key = "f\(Int(scalar.value) - NSF1FunctionKey + 1)"
        case 0x08, 0x7f: key = "backspace"
        case 0x09: key = "tab"
        case 0x0d, 0x03: key = "enter"
        case 0x1b: key = "escape"
        case NSDeleteFunctionKey: key = "delete"
        default: key = String(scalar).lowercased()
        }
        self.init(key: key, modifiers: modifiers)
    }

    var menuKeyEquivalent: String? {
        switch key {
        case "up": return String(UnicodeScalar(NSUpArrowFunctionKey)!)
        case "down": return String(UnicodeScalar(NSDownArrowFunctionKey)!)
        case "left": return String(UnicodeScalar(NSLeftArrowFunctionKey)!)
        case "right": return String(UnicodeScalar(NSRightArrowFunctionKey)!)
        default:
            if key.count == 1 { return key }
            if key.hasPrefix("f"), let number = Int(key.dropFirst()), (1...35).contains(number) {
                return String(UnicodeScalar(NSF1FunctionKey + number - 1)!)
            }
            return nil
        }
    }

    var menuModifierFlags: NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if modifiers.contains(.command) { flags.insert(.command) }
        if modifiers.contains(.shift) { flags.insert(.shift) }
        if modifiers.contains(.option) { flags.insert(.option) }
        if modifiers.contains(.control) { flags.insert(.control) }
        return flags
    }
}
