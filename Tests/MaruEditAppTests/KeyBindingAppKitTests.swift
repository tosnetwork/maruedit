import AppKit
import XCTest
@testable import MaruEditApp
import MaruEditCore

final class KeyBindingAppKitTests: XCTestCase {
    func testEventConversionUsesCharactersAndSemanticKeysNotHardwareCodes() throws {
        let letter = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [.command, .shift],
            timestamp: 0, windowNumber: 0, context: nil,
            characters: "F", charactersIgnoringModifiers: "f", isARepeat: false, keyCode: 999))
        XCTAssertEqual(KeyGesture(event: letter), KeyGesture("cmd+shift+f"))

        let upCharacter = String(UnicodeScalar(NSUpArrowFunctionKey)!)
        let arrow = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [.option],
            timestamp: 0, windowNumber: 0, context: nil,
            characters: upCharacter, charactersIgnoringModifiers: upCharacter,
            isARepeat: false, keyCode: 1234))
        XCTAssertEqual(KeyGesture(event: arrow), KeyGesture("opt+up"))
    }

    func testMenuPresentationComesFromPortableGesture() {
        let gesture = KeyGesture("cmd+opt+up")!
        XCTAssertEqual(gesture.menuKeyEquivalent, String(UnicodeScalar(NSUpArrowFunctionKey)!))
        XCTAssertEqual(gesture.menuModifierFlags, [.command, .option])
        XCTAssertEqual(KeyGesture("ctrl+k")!.menuKeyEquivalent, "k")
    }
}
