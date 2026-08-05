import AppKit
import XCTest
@preconcurrency @testable import MaruEditApp

@MainActor
final class LocalizationArchitectureTests: XCTestCase {
    private func catalog(_ language: String) throws -> [String: String] {
        let tests = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let url = tests.deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/MaruEditApp/Resources/\(language).lproj/Localizable.strings")
        let data = try Data(contentsOf: url)
        return try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String]
        )
    }

    func testSelectableCatalogsHaveExactlyTheSameSemanticKeys() throws {
        let english = try catalog("en")
        let japanese = try catalog("ja")
        XCTAssertEqual(Set(english.keys), Set(japanese.keys))
        XCTAssertFalse(english.values.contains(where: { $0.isEmpty }))
        XCTAssertFalse(japanese.values.contains(where: { $0.isEmpty }))
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: AppLocalization.defaultsKey)
        super.tearDown()
    }

    func testEveryTypedKeyExistsInEverySelectableLanguageCatalog() {
        let keys: [L10nKey] = [
            .languageJapanese, .languageEnglish, .languageSimplifiedChinese,
            .languageMenu, .languageChanged,
            .commonOK, .commonCancel, .commonOpen, .commonSave, .commonDontSave,
            .commonReload, .commonSelect, .commonInsert, .commonApply,
            .commonRemove, .commonReset, .commonRestore, .commonClear,
            .commonRun, .commonAllow, .commonDeny, .commonGo, .commonJump,
            .inputInsert, .inputOverwrite,
        ]
        for language in AppLanguage.selectable {
            for key in keys {
                XCTAssertTrue(
                    AppLocalization.hasTranslation(key.rawValue, language: language),
                    "missing \(language.rawValue) localization for \(key.rawValue)"
                )
            }
        }
    }

    func testEveryStaticCommandHasSemanticResourcesInEverySelectableLanguage() {
        let registry = CommandRegistry()
        AppCommands.registerAll(in: registry)
        for definition in registry.allDefinitions {
            let key = "command.\(definition.id.rawValue)"
            for language in AppLanguage.selectable {
                XCTAssertTrue(
                    AppLocalization.hasTranslation(key, language: language),
                    "missing \(language.rawValue) localization for \(key) (\(definition.title))"
                )
            }
        }
    }

    func testChineseCanBeAddedByCatalogWithoutChangingFeatureCode() {
        XCTAssertTrue(AppLanguage.allCases.contains(.simplifiedChinese))
        XCTAssertFalse(AppLanguage.selectable.contains(.simplifiedChinese))
        XCTAssertEqual(
            AppLocalization.localizedFormat("common.save", language: .simplifiedChinese),
            "Save",
            "an incomplete future catalog must fall back to English"
        )
    }

    func testLegacyLanguagePreferenceValuesMigrateWithoutChangingUserChoice() {
        UserDefaults.standard.set("english", forKey: AppLocalization.defaultsKey)
        XCTAssertEqual(AppLocalization.language, .english)
        UserDefaults.standard.set("japanese", forKey: AppLocalization.defaultsKey)
        XCTAssertEqual(AppLocalization.language, .japanese)
    }

    func testEncodingAndInputMenusContainNoJapaneseInEnglishMode() {
        AppLocalization.language = .english
        let controller = MainWindowController()
        let titles = controller.buildEncodingMenu().items.flatMap { item in
            [item.title] + (item.submenu?.items.map(\.title) ?? [])
        } + controller.buildInputModeMenu().items.map(\.title)
        XCTAssertFalse(titles.contains { $0.range(of: "[ぁ-んァ-ヶ一-龯]", options: .regularExpression) != nil })
        XCTAssertTrue(titles.contains("Insert Mode"))
        XCTAssertTrue(titles.contains("Reload with Automatic Detection"))
    }

    func testImperativeAppKitUIContainsNoBareUserFacingStrings() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/MaruEditApp")
        let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)!
            .compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
        let pattern = #"(?:messageText|informativeText|placeholderString|toolTip|title|prompt|message)\s*=\s*\"|setAccessibility(?:Label|Help)\(\"|addButton\(withTitle:\s*\"|NS(?:Button|Menu|MenuItem)\([^\n]*title:\s*\""#
        let regex = try NSRegularExpression(pattern: pattern)
        var violations: [String] = []
        for file in files {
            let source = try String(contentsOf: file)
            if regex.firstMatch(in: source, range: NSRange(source.startIndex..., in: source)) != nil {
                violations.append(file.path.replacingOccurrences(of: root.path + "/", with: ""))
            }
        }
        XCTAssertEqual(violations, [], "bare user-facing strings must use semantic localization keys")
    }

    func testJapaneseUITextLivesInResourcesNotSwiftSource() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/MaruEditApp")
        let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)!
            .compactMap { $0 as? URL }.filter {
                $0.pathExtension == "swift" && $0.lastPathComponent != "VerticalLayoutFeasibility.swift"
            }
        let regex = try NSRegularExpression(pattern: "[ぁ-んァ-ヶ一-龯]")
        let violations = try files.filter {
            let source = try String(contentsOf: $0)
            return regex.firstMatch(in: source, range: NSRange(source.startIndex..., in: source)) != nil
        }
        XCTAssertEqual(violations.map(\.lastPathComponent), [])
    }
}
