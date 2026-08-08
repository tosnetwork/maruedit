import AppKit
import MaruEditCore
import XCTest
@preconcurrency @testable import MaruEditApp


@preconcurrency @MainActor
final class MenuCustomizationUITests: XCTestCase {
    private let settings = CommandDefinition(id: .appSettings, title: "Settings") { _ in }
    private let find = CommandDefinition(id: .searchFind, title: "Find") { _ in }
    private let partialOpen = CommandDefinition(id: .fileOpenPartial, title: "Open Part") { _ in }

    private func menu(named name: String, in root: NSMenu) -> NSMenu? {
        let localized: [String: String] = [
            "File": "ファイル(F)", "Edit": "編集(E)", "View": "表示(V)",
            "Search": "検索(S)", "Window": "ウィンドウ(W)",
            "Macro": "マクロ(M)", "Other": "その他(O)",
        ]
        return root.items.compactMap(\.submenu).first {
            $0.title == name || $0.title == localized[name]
        }
    }

    override func setUp() {
        super.setUp()
        UserDefaults.standard.set(AppLanguage.japanese.rawValue, forKey: AppLocalization.defaultsKey)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: AppLocalization.defaultsKey)
        super.tearDown()
    }

    func testOtherMenuLanguageChoicePersistsAndRebuildsAllVisibleMenusInEnglish() {
        _ = NSApplication.shared
        let delegate = AppDelegate()
        delegate.buildMenu()
        let root = try! XCTUnwrap(NSApp.mainMenu)
        let other = try! XCTUnwrap(menu(named: "Other", in: root))
        let language = try! XCTUnwrap(other.item(withTitle: "言語")?.submenu)
        XCTAssertEqual(language.items.map(\.title), ["Japanese", "English"])
        XCTAssertEqual(language.item(withTitle: "Japanese")?.state, .on)

        let english = try! XCTUnwrap(language.item(withTitle: "English"))
        XCTAssertTrue(NSApp.sendAction(english.action!, to: english.target, from: english))
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        XCTAssertEqual(AppLocalization.language, .english)
        XCTAssertEqual(
            NSApp.mainMenu?.items.filter { !$0.isHidden }.dropFirst().map(\.title),
            ["File", "Edit", "View", "Search", "Window", "Macro", "Other"]
        )
        let englishView = try! XCTUnwrap(menu(named: "View", in: NSApp.mainMenu!))
        for title in ["Line Wrapping", "Ruler Display", "Tab Stops", "Folding"] {
            XCTAssertNotNil(englishView.item(withTitle: title)?.submenu, "missing English View group \(title)")
        }
        XCTAssertFalse(englishView.items.map(\.title).contains { $0.range(of: "[ぁ-んァ-ヶ一-龯]", options: .regularExpression) != nil })
        let englishOther = try! XCTUnwrap(menu(named: "Other", in: NSApp.mainMenu!))
        XCTAssertEqual(englishOther.item(withTitle: "Language")?.submenu?.item(withTitle: "English")?.state, .on)
        XCTAssertEqual(SettingsLocalization.text("settings"), "Settings")
    }

    func testWindowHidesOptionalCommandsButProtectsRequiredCommandsAndRestores() async throws {
        var changes: [MenuCustomization] = []
        let controller = MenuCustomizationWindowController(
            definitions: [settings, find], protectedCommandIDs: [.appSettings],
            customization: .defaults, onChange: { changes.append($0) })

        controller.setVisibleForTesting(false, command: .appSettings)
        XCTAssertEqual(controller.checkboxForTesting(.appSettings)?.state, .on)
        XCTAssertEqual(controller.currentCustomization, .defaults)

        controller.setVisibleForTesting(false, command: .searchFind)
        XCTAssertEqual(controller.currentCustomization.hiddenCommandIDs, [.searchFind])
        XCTAssertEqual(changes.last?.hiddenCommandIDs, [.searchFind])

        controller.restoreForTesting()
        XCTAssertEqual(controller.currentCustomization, .defaults)
        XCTAssertEqual(controller.checkboxForTesting(.searchFind)?.state, .on)
    }

    func testDefaultSubmenusAreCompactAndHiddenCommandsCanBeAddedBack() async {
        _ = NSApplication.shared
        let delegate = AppDelegate()
        delegate.buildMenu()
        let main = try! XCTUnwrap(NSApp.mainMenu)

        func visibleIDs(in title: String) -> Set<CommandID> {
            let menu = self.menu(named: title, in: main)
            return Set(menu?.items.compactMap { item in
                guard !item.isHidden else { return nil }
                return item.representedObject as? CommandID
            } ?? [])
        }

        XCTAssertEqual(visibleIDs(in: "File"), Set([
            .fileNew, .fileOpen, .fileCloseAndOpen, .fileSave, .fileSaveAs,
            .insertFileContents, .filePrint, .fileSaveAndClose,
            .fileSaveAllAndClose, .fileDiscardAllAndClose,
        ]))
        XCTAssertEqual(visibleIDs(in: "Edit"), [
            .editAppendCut, .editAppendCopy, .editClipboardHistory,
            .editCompleteWord, .fileReload,
        ])
        XCTAssertEqual(visibleIDs(in: "Search"), Set([
            .searchFind, .searchReplace, .searchFindNext, .searchFindPrevious,
            .searchToggleHighlight, .searchReturnToStart, .searchGoToLine,
            .navigateDocumentStart, .navigateDocumentEnd, .navigateLastEdit,
            .searchNextEditMark, .searchPreviousEditMark, .navigatePreviousCursor,
            .highlightOutlineAnalysis, .searchListMarks, .searchListColorLayers,
            .searchGrep, .searchGrepReplace,
        ]))
        let fileMenu = try! XCTUnwrap(menu(named: "File", in: main))
        let encodingItem = try! XCTUnwrap(fileMenu.items.first {
            $0.identifier?.rawValue == "menu.dynamic.reopenEncoding"
        })
        XCTAssertEqual(encodingItem.title, "エンコードの種類(D)")
        XCTAssertFalse(encodingItem.isHidden)
        XCTAssertNotNil(encodingItem.submenu)
        let partialItem = try! XCTUnwrap(fileMenu.items.first {
            ($0.representedObject as? CommandID) == .fileOpenPartial
        })
        XCTAssertTrue(partialItem.isHidden)

        var expanded = MenuCustomization.defaults
        expanded.setVisible(true, command: .fileOpenPartial)
        AppDelegate.applyMenuCustomization(
            expanded, protectedCommandIDs: AppDelegate.protectedCommandIDs,
            defaultMenuPlacements: AppDelegate.classicDefaultMenuPlacements, to: main)
        XCTAssertFalse(partialItem.isHidden)
    }

    func testMenuEditorShowsCompactDefaultsAndCanEnableAnExtendedCommand() async {
        var changes: [MenuCustomization] = []
        let controller = MenuCustomizationWindowController(
            definitions: [settings, find, partialOpen],
            protectedCommandIDs: [.appSettings], customization: .defaults,
            onChange: { changes.append($0) })
        XCTAssertEqual(controller.checkboxForTesting(.searchFind)?.state, .on)
        XCTAssertEqual(controller.checkboxForTesting(.fileOpenPartial)?.state, .off)

        controller.setVisibleForTesting(true, command: .fileOpenPartial)
        XCTAssertEqual(changes.last?.visibleCommandIDs, [.fileOpenPartial])
        XCTAssertTrue(changes.last!.isCommandVisible(.fileOpenPartial, defaultVisible: false))
    }

    func testApplyingCustomizationUsesIDsAndNeverHidesSystemOrProtectedItems() async {
        let root = NSMenu()
        let menu = NSMenu(title: "Test")
        let top = NSMenuItem(); top.submenu = menu; root.addItem(top)
        menu.addItem(NSMenuItem(title: "About Localized However", action: nil, keyEquivalent: ""))
        menu.addItem(.separator())
        let protected = NSMenuItem(title: "Localized Settings", action: nil, keyEquivalent: "")
        protected.representedObject = CommandID.appSettings
        menu.addItem(protected)
        let group = NSMenuItem(title: "Localized Group", action: nil, keyEquivalent: "")
        group.identifier = NSUserInterfaceItemIdentifier("menu.group.test")
        let submenu = NSMenu()
        let optional = NSMenuItem(title: "Localized Find", action: nil, keyEquivalent: "")
        optional.representedObject = CommandID.searchFind
        submenu.addItem(optional)
        group.submenu = submenu
        menu.addItem(group)

        AppDelegate.applyMenuCustomization(
            MenuCustomization(hiddenCommandIDs: [.appSettings, .searchFind]),
            protectedCommandIDs: [.appSettings],
            defaultMenuPlacements: AppDelegate.classicDefaultMenuPlacements, to: root)

        XCTAssertFalse(menu.items[0].isHidden, "system item has no Command ID and is protected by construction")
        XCTAssertFalse(protected.isHidden)
        XCTAssertTrue(optional.isHidden)
        XCTAssertTrue(group.isHidden, "an empty optional command group should collapse")
    }

    func testBuiltApplicationMenuContainsRequiredMacOSItems() async {
        _ = NSApplication.shared
        let delegate = AppDelegate()
        delegate.buildMenu()
        let menus = NSApp.mainMenu?.items.compactMap(\.submenu) ?? []
        let allTitles = Set(menus.flatMap { $0.items.map(\.title) })
        for required in ["MaruEditについて", "サービス", "MaruEditを隠す", "ほかを隠す",
                         "すべてを表示", "MaruEditを終了", "やり直し(U)",
                         "やり直しのやり直し(R)"] {
            XCTAssertTrue(allTitles.contains(required), "missing required menu item \(required)")
        }
    }

    func testBusinessMenuOrderMatchesMaru() async {
        _ = NSApplication.shared
        let delegate = AppDelegate(); delegate.buildMenu()
        let titles = NSApp.mainMenu?.items.filter { !$0.isHidden }.compactMap { $0.submenu?.title } ?? []
        XCTAssertEqual(Array(titles.dropFirst()), [
            "ファイル(F)", "編集(E)", "表示(V)", "検索(S)",
            "ウィンドウ(W)", "マクロ(M)", "その他(O)",
        ])

        AppDelegate.applyMenuCustomization(
            MenuCustomization(hiddenTopLevelMenus: []),
            protectedCommandIDs: AppDelegate.protectedCommandIDs,
            defaultMenuPlacements: AppDelegate.classicDefaultMenuPlacements,
            to: NSApp.mainMenu!)
        let expanded = NSApp.mainMenu?.items.filter { !$0.isHidden }.compactMap { $0.submenu?.title } ?? []
        XCTAssertEqual(Array(expanded.dropFirst()), [
            "ファイル(F)", "編集(E)", "変換(V)", "表示(V)", "挿入", "検索(S)", "強調",
            "ブックマーク", "ツール", "ウィンドウ(W)", "マクロ(M)", "その他(O)", "ヘルプ",
        ])
    }

    func testDefaultSevenMenusMatchTheLocallyRecordedClassicStructure() {
        _ = NSApplication.shared
        let delegate = AppDelegate(); delegate.buildMenu()
        let root = try! XCTUnwrap(NSApp.mainMenu)
        XCTAssertEqual(
            root.items.filter { !$0.isHidden }.dropFirst().map(\.title),
            ["ファイル(F)", "編集(E)", "表示(V)", "検索(S)",
             "ウィンドウ(W)", "マクロ(M)", "その他(O)"]
        )
        func titles(_ menuTitle: String) -> [String] {
            let menu = self.menu(named: menuTitle, in: root)
            return menu?.items.filter { !$0.isHidden && !$0.isSeparatorItem }.map(\.title) ?? []
        }
        XCTAssertEqual(titles("File"), [
            "新規作成(N)", "開く(O)...", "閉じて開く(L)...", "上書き保存(S)",
            "名前を付けて保存(A)...", "カーソル位置への読み込み(I)...", "印刷(P)...",
            "エンコードの種類(D)", "保存して終了(E)", "終了(X)", "全保存終了(T)", "全終了(Q)",
        ])
        XCTAssertEqual(titles("Edit"), [
            "やり直し(U)", "やり直しのやり直し(R)", "切り抜き(T)", "コピー(C)",
            "追加切り抜き(W)", "追加コピー(A)", "貼り付け(P)", "削除(L)", "変換(V)",
            "整形(-)", "すべてを選択(S)", "クリップボード履歴(H)...", "単語補完(I)", "再読み込み(O)",
        ])
        XCTAssertEqual(titles("View"), [
            "ツールバー(T)", "タブモード(B)", "ファンクションキー表示(F)", "ステータスバー(S)",
            "ファイルマネージャ枠(X)", "アウトプット枠(P)", "ブラウザ枠(￥)",
            "アウトライン解析の枠(O)", "見出しバー(U)", "折りたたみ用の余白(M)",
            "行番号(L)", "現在行の強調表示(H)", "ルーラー(R)", "自動スペルチェック(K)", "個別ブラウザ枠(￥)",
            "折り返し(I)", "ルーラーの表示(D)", "タブストップ(A)", "縦書きモード(Q)",
            "段組モード(J)", "部分編集([)", "部分編集解除(])", "折りたたみ(V)", "全画面表示(Z)",
        ])
        XCTAssertEqual(titles("Search"), [
            "検索(F)...", "下候補(N)", "上候補(P)", "置換(R)...", "検索文字列の強調(O)",
            "検索開始位置へ戻る(S)", "指定行(J)...", "ファイルの先頭(T)", "ファイルの最後(B)",
            "最後に編集した所(L)", "下の編集マーク(D)", "上の編集マーク(U)",
            "前のカーソル位置(V)", "強調(H)", "マーカー一覧(M)...", "カラーマーカー(I)",
            "grepして置換(@)...", "grepの実行(G)...",
        ])
        XCTAssertEqual(Array(titles("Window").prefix(17)), [
            "縦に並べる(V)", "横に並べる(H)", "重ねて表示(C)", "並べて表示(T)",
            "全部最小化(N)", "ウィンドウ分割上下(D)",
            "他のMaruエディタと同時スクロール(L)...", "他のMaruエディタと内容比較(F)...",
            "デスクトップ保存(S)", "デスクトップ復元(R)", "常に手前に表示(A)",
            "アウトライン解析の枠(O)", "ファイルマネージャ枠(X)", "アウトプット枠(U)",
            "ブラウザ枠(￥)", "タブモード(B)", "このタブを分離/移動(I)",
        ])
        XCTAssertEqual(titles("Macro"), [
            "キー操作の記録開始/終了(R)", "キー操作の再生(P)", "キー操作の保存(S)...",
            "キー操作の読み込み(L)...", "マクロ実行(X)...", "マクロ登録(E)...", "マクロヘルプ(H)",
        ])
        XCTAssertEqual(titles("Other"), [
            "ファイルタイプ別の設定(C)...", "動作環境(E)...", "キー割り当て(K)...", "メニュー編集(M)...",
            "タグジャンプ(T)", "ダイレクトタグジャンプ(D)", "バックタグジャンプ(B)",
            "制御コード入力(I)...", "tagsファイルの作成(G)...", "プログラム実行(X)...",
            "スペルミスの修正(Z)...", "コマンド一覧(O)...", "閲覧モード(R)",
            "設定内容の保存/復元(U)...", "最新バージョンの確認(V)...", "MaruEditヘルプ(P)", "MaruEditについて(A)...", "言語",
        ])

        let search = try! XCTUnwrap(menu(named: "Search", in: root))
        let highlight = try! XCTUnwrap(search.item(withTitle: "強調(H)")?.submenu)
        XCTAssertEqual(highlight.items.compactMap { $0.representedObject as? CommandID }, [
            .highlightOutlineAnalysis, .highlightNextLine,
            .highlightPreviousLine, .highlightSelectLineArea,
        ])
        let colorMarker = try! XCTUnwrap(search.item(withTitle: "カラーマーカー(I)")?.submenu)
        XCTAssertEqual(colorMarker.items.compactMap { $0.representedObject as? CommandID }, [
            .searchListColorLayers, .highlightTemporaryConfigure,
            .highlightTemporaryApply, .highlightTemporaryRemove,
            .highlightTemporaryClear, .highlightTemporarySelect,
            .highlightTemporaryNext, .highlightTemporaryPrevious,
        ])
    }

    func testMenuEditorCanEnableEveryExtendedTopLevelMenu() async {
        var changes: [MenuCustomization] = []
        let controller = MenuCustomizationWindowController(
            definitions: [settings, find], protectedCommandIDs: [.appSettings],
            customization: .defaults, onChange: { changes.append($0) })
        for menu in MenuCustomization.optionalTopLevelMenus {
            XCTAssertEqual(controller.menuCheckboxForTesting(menu)?.state, .off)
            controller.setMenuVisibleForTesting(true, menu: menu)
            XCTAssertFalse(changes.last!.hiddenMenus.contains(menu))
        }
        XCTAssertEqual(changes.last?.hiddenTopLevelMenus, [])
        controller.restoreForTesting()
        XCTAssertEqual(controller.currentCustomization, .defaults)
    }

    func testToolsMenuGroupsCompareTagsExternalCommandsAndCommandList() async {
        _ = NSApplication.shared
        let app = AppDelegate()
        app.buildMenu()
        let tools = NSApp.mainMenu?.item(withTitle: AppLocalization.string("menu.other.tools"))?.submenu
        let titles = tools?.items.map(\.title) ?? []
        XCTAssertTrue(titles.contains("Compare with Next Document"))
        XCTAssertTrue(titles.contains("Generate Tags File…"))
        XCTAssertTrue(titles.contains("タグジャンプ"))
        XCTAssertTrue(titles.contains(AppLocalization.string("menu.other.externalCommands")))
        XCTAssertTrue(titles.contains("Command List…"))
        XCTAssertNotNil(tools?.item(withTitle: AppLocalization.string("menu.other.externalCommands"))?.submenu)
        for slot in 1...8 {
            XCTAssertNotNil(tools?.item(withTitle: AppLocalization.string("settings.userMenus.number", [slot]))?.submenu)
        }
        XCTAssertTrue(titles.contains("Configure User Menus…"))
        XCTAssertTrue(titles.contains("Show in Finder"))
        XCTAssertTrue(titles.contains("Open Macro Folder"))
    }

    func testHelpMenuContainsSixConfigurableExternalHelpSlots() async {
        let app = AppDelegate(); app.buildMenu()
        let helpMenu = NSApp.mainMenu?.items.compactMap(\.submenu).first {
            $0.title == AppLocalization.string("menu.group.help")
        }
        let titles = helpMenu?.items.map(\.title) ?? []
        for slot in 1...6 { XCTAssertTrue(titles.contains("External Help \(slot)")) }
        XCTAssertTrue(titles.contains("Configure External Help…"))
    }

    func testOtherMenuProvidesCategorizedHistoryClearing() async {
        let app = AppDelegate(); app.buildMenu()
        let other = NSApp.mainMenu.flatMap { menu(named: "Other", in: $0) }
        XCTAssertEqual(other?.item(withTitle: AppLocalization.string("menu.other.clearHistory"))?.isHidden, true,
                       "history maintenance is an extended, non-default group")
    }

    func testOtherMenuProvidesSettingsTransferCommands() async {
        let app = AppDelegate(); app.buildMenu()
        let other = NSApp.mainMenu.flatMap { menu(named: "Other", in: $0) }
        let transfer = other?.item(withTitle: "設定内容の保存/復元(U)...")?.submenu
        XCTAssertEqual(transfer?.items.filter { !$0.isSeparatorItem }.map(\.title), [
            "設定を書き出す...", "設定を読み込む...", "設定を初期状態に戻す...",
        ])
        XCTAssertNotNil(other?.item(withTitle: "Free Cursor"))
    }
}
