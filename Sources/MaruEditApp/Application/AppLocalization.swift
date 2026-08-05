import AppKit

enum AppLanguage: String, CaseIterable {
    case japanese = "ja"
    case english = "en"
    case simplifiedChinese = "zh-Hans"

    /// Chinese is catalog-ready but is exposed only after its catalog reaches
    /// parity. Adding a language never requires changing feature code.
    static let selectable: [AppLanguage] = [.japanese, .english]

    var displayNameKey: String {
        switch self {
        case .japanese: "language.japanese"
        case .english: "language.english"
        case .simplifiedChinese: "language.simplifiedChinese"
        }
    }
}

enum L10nKey: String {
    case languageJapanese = "language.japanese"
    case languageEnglish = "language.english"
    case languageSimplifiedChinese = "language.simplifiedChinese"
    case languageMenu = "menu.language"
    case languageChanged = "message.languageChanged"
    case commonOK = "common.ok"
    case commonCancel = "common.cancel"
    case commonOpen = "common.open"
    case commonSave = "common.save"
    case commonDontSave = "common.dontSave"
    case commonReload = "common.reload"
    case commonSelect = "common.select"
    case commonInsert = "common.insert"
    case commonApply = "common.apply"
    case commonRemove = "common.remove"
    case commonReset = "common.reset"
    case commonRestore = "common.restore"
    case commonClear = "common.clear"
    case commonRun = "common.run"
    case commonAllow = "common.allow"
    case commonDeny = "common.deny"
    case commonGo = "common.go"
    case commonJump = "common.jump"
    case inputInsert = "status.input.insert"
    case inputOverwrite = "status.input.overwrite"
}

enum AppLocalization {
    static let defaultsKey = "MaruEditApplicationLanguage"
    static let didChange = Notification.Name("MaruEditApplicationLanguageDidChange")

    static var language: AppLanguage {
        get {
            guard let raw = UserDefaults.standard.string(forKey: defaultsKey) else { return .japanese }
            if let value = AppLanguage(rawValue: raw) { return value }
            if raw == "japanese" { return .japanese }
            if raw == "english" { return .english }
            return .japanese
        }
        set {
            guard newValue != language else { return }
            UserDefaults.standard.set(newValue.rawValue, forKey: defaultsKey)
            NotificationCenter.default.post(name: didChange, object: newValue)
        }
    }

    static var isJapanese: Bool { language == .japanese }

    static func string(_ key: L10nKey, _ arguments: CVarArg...) -> String {
        string(key.rawValue, arguments)
    }

    static func string(_ key: String, _ arguments: [CVarArg] = []) -> String {
        let format = localizedFormat(key, language: language)
        guard !arguments.isEmpty else { return format }
        return String(format: format, locale: Locale(identifier: language.rawValue), arguments: arguments)
    }

    static func localizedFormat(_ key: String, language: AppLanguage) -> String {
        let selected = bundle(for: language)?.localizedString(forKey: key, value: nil, table: nil)
        if let selected, selected != key { return selected }
        let english = bundle(for: .english)?.localizedString(forKey: key, value: nil, table: nil)
        return english == key ? "⟦\(key)⟧" : (english ?? "⟦\(key)⟧")
    }

    static func hasTranslation(_ key: String, language: AppLanguage) -> Bool {
        guard let value = bundle(for: language)?.localizedString(forKey: key, value: nil, table: nil) else {
            return false
        }
        return value != key
    }

    private static func bundle(for language: AppLanguage) -> Bundle? {
        guard let path = Bundle.module.path(forResource: language.rawValue, ofType: "lproj") else {
            return nil
        }
        return Bundle(path: path)
    }

    static func commandTitle(id: String, english: String) -> String {
        let key = "command.\(id)"
        if hasTranslation(key, language: language) { return string(key) }
        return english
    }

    static func classicCommandTitle(id: String, english: String) -> String {
        if let bundle = bundle(for: language) {
            let key = "command.\(id)"
            let value = bundle.localizedString(forKey: key, value: key, table: "ClassicMenu")
            if value != key { return value }
        }
        return commandTitle(id: id, english: english)
    }

}
