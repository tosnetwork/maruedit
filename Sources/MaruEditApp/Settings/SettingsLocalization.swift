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
            "exportSettings": [.english: "Export Settings…", .japanese: "設定を書き出す…", .simplifiedChinese: "导出设置…"],
            "importSettings": [.english: "Import Settings…", .japanese: "設定を読み込む…", .simplifiedChinese: "导入设置…"],
            "restoreAll": [.english: "Restore All Settings", .japanese: "すべての設定を初期化", .simplifiedChinese: "恢复所有默认设置"],
            "settingsTransfer": [.english: "Export, import, or restore the versioned settings file.", .japanese: "バージョン付き設定ファイルの書き出し、読み込み、初期化を行います。", .simplifiedChinese: "导出、导入或恢复带版本的设置文件。"],
            "reducedFeatures": [.english: "Reduced Features", .japanese: "機能制限モード", .simplifiedChinese: "精简功能"],
            "largeReadOnly": [.english: "Large File · Read-Only", .japanese: "大容量ファイル・読み取り専用", .simplifiedChinese: "大文件 · 只读"],
            "largeFileMode": [.english: "Large-file feature mode", .japanese: "大容量ファイル機能モード", .simplifiedChinese: "大文件功能模式"],
            "largeFileTooltip": [.english: "Reduced Features Mode is active; click to enable all features", .japanese: "機能制限モードが有効です。クリックして全機能を有効にできます", .simplifiedChinese: "精简功能模式已启用；点按可启用全部功能"],
            "openLargeFile": [.english: "Open large file?", .japanese: "大容量ファイルを開きますか？", .simplifiedChinese: "打开大文件？"],
            "largeFileExplanation": [.english: "Reduced Features Mode disables syntax highlighting, wrapping, invisible characters, and limits Undo.", .japanese: "機能制限モードでは、構文強調、折り返し、不可視文字を無効にし、取り消し回数を制限します。", .simplifiedChinese: "精简功能模式会禁用语法高亮、自动换行和不可见字符，并限制撤销次数。"],
            "continueReduced": [.english: "Continue in Reduced Mode", .japanese: "機能制限モードで続ける", .simplifiedChinese: "以精简模式继续"],
            "openReadOnly": [.english: "Open Read-Only", .japanese: "読み取り専用で開く", .simplifiedChinese: "以只读方式打开"],
            "cancel": [.english: "Cancel", .japanese: "キャンセル", .simplifiedChinese: "取消"],
            "enableAllLargeTitle": [.english: "Enable all features for this large file?", .japanese: "この大容量ファイルですべての機能を有効にしますか？", .simplifiedChinese: "为此大文件启用全部功能？"],
            "enableAllLargeExplanation": [.english: "Syntax highlighting, wrapping, invisible characters, and unlimited Undo can increase latency and memory use.", .japanese: "構文強調、折り返し、不可視文字、無制限の取り消しは、遅延とメモリ使用量を増やす可能性があります。", .simplifiedChinese: "语法高亮、自动换行、不可见字符和无限撤销可能增加延迟与内存占用。"],
            "enableAllFeatures": [.english: "Enable All Features", .japanese: "すべての機能を有効にする", .simplifiedChinese: "启用全部功能"],
            "keepReduced": [.english: "Keep Reduced", .japanese: "機能制限を維持", .simplifiedChinese: "保持精简模式"],
        ]
        return values[key]?[language] ?? key
    }
}
