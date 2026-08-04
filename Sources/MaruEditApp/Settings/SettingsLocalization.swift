import Foundation

enum SettingsLanguage { case english, japanese, simplifiedChinese }

enum SettingsLocalization {
    static var language: SettingsLanguage {
        let code = Locale.preferredLanguages.first?.lowercased() ?? "en"
        if code.hasPrefix("ja") { return .japanese }
        if code.hasPrefix("zh-hans") || code.hasPrefix("zh-cn") { return .simplifiedChinese }
        return .english
    }

    static func text(_ key: String, language: SettingsLanguage = language) -> String {
        let values: [String: [SettingsLanguage: String]] = [
            "settings": [.english: "Settings", .japanese: "設定", .simplifiedChinese: "设置"],
            "search": [.english: "Search Settings", .japanese: "設定を検索", .simplifiedChinese: "搜索设置"],
            "general": [.english: "General", .japanese: "一般", .simplifiedChinese: "通用"],
            "editor": [.english: "Editor", .japanese: "エディタ", .simplifiedChinese: "编辑器"],
            "appearance": [.english: "Appearance", .japanese: "外観", .simplifiedChinese: "外观"],
            "files": [.english: "Files", .japanese: "ファイル", .simplifiedChinese: "文件"],
            "searchGroup": [.english: "Search", .japanese: "検索", .simplifiedChinese: "搜索"],
            "keyBindings": [.english: "Key Bindings", .japanese: "キーバインド", .simplifiedChinese: "快捷键"],
            "macros": [.english: "Macros", .japanese: "マクロ", .simplifiedChinese: "宏"],
            "advanced": [.english: "Advanced", .japanese: "詳細", .simplifiedChinese: "高级"],
            "fontName": [.english: "Font name", .japanese: "フォント名", .simplifiedChinese: "字体名称"],
            "fontSize": [.english: "Font size", .japanese: "フォントサイズ", .simplifiedChinese: "字体大小"],
            "tabWidth": [.english: "Tab width", .japanese: "タブ幅", .simplifiedChinese: "制表符宽度"],
            "lineNumbers": [.english: "Show line numbers", .japanese: "行番号を表示", .simplifiedChinese: "显示行号"],
            "wrapLines": [.english: "Wrap long lines", .japanese: "長い行を折り返す", .simplifiedChinese: "长行自动换行"],
            "restore": [.english: "Restore Group Defaults", .japanese: "グループを初期設定に戻す", .simplifiedChinese: "恢复此组默认值"],
            "immediate": [.english: "Changes apply immediately to open and new documents.", .japanese: "変更は開いている書類と新規書類にすぐ適用されます。", .simplifiedChinese: "更改会立即应用于已打开和新建的文档。"],
            "comingSoon": [.english: "Options for this group are provided by later M5 tasks.", .japanese: "このグループの項目は後続の M5 タスクで追加されます。", .simplifiedChinese: "此组的选项将在后续 M5 任务中提供。"],
        ]
        return values[key]?[language] ?? key
    }
}
