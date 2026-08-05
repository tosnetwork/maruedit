import Foundation

enum SettingsLanguage { case english, japanese, simplifiedChinese }

enum SettingsLocalization {
    static var language: SettingsLanguage {
        switch AppLocalization.language {
        case .japanese: .japanese
        case .english: .english
        case .simplifiedChinese: .simplifiedChinese
        }
    }

    static func text(_ key: String, language: SettingsLanguage = language) -> String {
        let appLanguage: AppLanguage = switch language {
        case .english: .english
        case .japanese: .japanese
        case .simplifiedChinese: .simplifiedChinese
        }
        return AppLocalization.localizedFormat("settings.\(key)", language: appLanguage)
    }
}
