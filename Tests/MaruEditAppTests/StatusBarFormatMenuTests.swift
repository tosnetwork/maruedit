import AppKit
import MaruEditCore
import XCTest
@preconcurrency @testable import MaruEditApp


@preconcurrency @MainActor
final class StatusBarFormatMenuTests: XCTestCase {
    func testMenusExposeEncodingBOMLineEndingAndEveryLanguage() async {
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
