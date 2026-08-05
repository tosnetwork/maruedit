import AppKit
import MaruEditCore
import XCTest
@preconcurrency @testable import MaruEditApp


@preconcurrency @MainActor
final class StatusBarFormatMenuTests: XCTestCase {
    func testMenusExposeEncodingBOMLineEndingAndEveryLanguage() async {
        AppLocalization.language = .english
        defer { UserDefaults.standard.removeObject(forKey: AppLocalization.defaultsKey) }
        let controller = MainWindowController()

        XCTAssertFalse(controller.buildEncodingMenu().items.isEmpty)
        XCTAssertEqual(controller.buildByteOrderMarkMenu().items.map(\.title),
                       ["With BOM", "Without BOM"])
        XCTAssertEqual(controller.buildLineEndingMenu().items.map(\.title), ["LF", "CRLF", "CR"])
        let profileMenu = controller.buildLanguageProfileMenu()
        let syntaxIndex = try! XCTUnwrap(profileMenu.items.firstIndex { $0.title == "Syntax Only" })
        let languages = Array(profileMenu.items.suffix(from: syntaxIndex + 1)).filter { !$0.isSeparatorItem }
        XCTAssertEqual(languages.count, Language.allCases.count)
        XCTAssertTrue(languages.allSatisfy { $0.action != nil && $0.target === controller })
        XCTAssertTrue(profileMenu.items.contains { $0.title == "Built-in Profiles" })
        XCTAssertTrue(profileMenu.items.contains { $0.title == "Swift" && $0.action != nil })
    }

    func testInputModeMenuOffersExplicitChoicesAndUpdatesTheDocument() throws {
        let controller = MainWindowController()
        var menu = controller.buildInputModeMenu()
        XCTAssertEqual(menu.items.map(\.title), ["上書きモード", "挿入モード"])
        XCTAssertEqual(menu.items.first { $0.title == "挿入モード" }?.state, .on)

        let overwrite = try XCTUnwrap(menu.items.first { $0.title == "上書きモード" })
        _ = overwrite.target?.perform(overwrite.action, with: overwrite)
        menu = controller.buildInputModeMenu()
        XCTAssertEqual(menu.items.first { $0.title == "上書きモード" }?.state, .on)
        XCTAssertEqual(controller.macroEditor.document?.inputMode, .overwrite)
    }

    func testEncodingMenuIsRichAndCanSetAnUntitledDocumentEncoding() throws {
        let controller = MainWindowController()
        let menu = controller.buildEncodingMenu()
        let encodingItems = menu.items + menu.items.compactMap(\.submenu).flatMap(\.items)
        for encoding in TextEncoding.userSelectable {
            XCTAssertTrue(encodingItems.contains { $0.representedObject as? TextEncoding == encoding })
        }
        let targetEncoding = try XCTUnwrap(TextEncoding.userSelectable.first {
            $0 != controller.macroEditor.document?.encoding
        })
        let item = try XCTUnwrap(encodingItems.first {
            $0.representedObject as? TextEncoding == targetEncoding
        })
        _ = item.target?.perform(item.action, with: item)
        XCTAssertEqual(controller.macroEditor.document?.encoding, targetEncoding)
        let refreshed = controller.buildEncodingMenu()
        let refreshedItems = refreshed.items + refreshed.items.compactMap(\.submenu).flatMap(\.items)
        XCTAssertEqual(refreshedItems.first { $0.representedObject as? TextEncoding == targetEncoding }?.state, .on)
    }

    func testProfileMenuAppliesTheCompleteProfileRatherThanOnlySyntax() throws {
        let controller = MainWindowController()
        let swift = try XCTUnwrap(controller.buildLanguageProfileMenu().items.first {
            $0.representedObject as? String == "builtin.swift"
        })
        _ = swift.target?.perform(swift.action, with: swift)
        XCTAssertEqual(controller.macroEditor.document?.fileTypeProfile?.id, "builtin.swift")
        XCTAssertEqual(controller.macroEditor.document?.language, .swift)
        XCTAssertEqual(controller.macroEditor.effectiveWrapColumn, 160)
    }

    func testFormatMenuActionsUpdateCheckedState() async throws {
        let controller = MainWindowController()
        let bom = try XCTUnwrap(controller.buildByteOrderMarkMenu().items.first)
        _ = bom.target?.perform(bom.action, with: bom)
        XCTAssertEqual(controller.buildByteOrderMarkMenu().items.first?.state, .on)

        let crlf = try XCTUnwrap(controller.buildLineEndingMenu().items.first { $0.title == "CRLF" })
        _ = crlf.target?.perform(crlf.action, with: crlf)
        XCTAssertEqual(controller.buildLineEndingMenu().items.first { $0.title == "CRLF" }?.state, .on)

        let shell = try XCTUnwrap(controller.buildLanguageProfileMenu().items.first { $0.title == "Shell" })
        _ = shell.target?.perform(shell.action, with: shell)
        XCTAssertEqual(controller.buildLanguageProfileMenu().items.first { $0.title == "Shell" }?.state, .on)
    }
}
