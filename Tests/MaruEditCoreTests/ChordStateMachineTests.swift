import XCTest
@testable import MaruEditCore

final class ChordStateMachineTests: XCTestCase {
    private let bindings = [
        KeyBinding(keys: [KeyGesture("cmd+s")!], command: "file.save"),
        KeyBinding(keys: [KeyGesture("ctrl+k")!, KeyGesture("ctrl+c")!], command: "edit.toggleComment"),
    ]

    func testSingleAndSuccessfulChordCommands() {
        let machine = ChordStateMachine(timeout: 1)
        XCTAssertEqual(machine.handle(KeyGesture("cmd+s")!, bindings: bindings, now: 0), .command("file.save"))
        XCTAssertEqual(machine.handle(KeyGesture("ctrl+k")!, bindings: bindings, now: 1), .waiting(prefix: KeyGesture("ctrl+k")!))
        XCTAssertEqual(machine.handle(KeyGesture("ctrl+c")!, bindings: bindings, now: 1.5), .command("edit.toggleComment"))
        XCTAssertNil(machine.pendingPrefix)
    }

    func testTimeoutClearsPendingChord() {
        let machine = ChordStateMachine(timeout: 1)
        _ = machine.handle(KeyGesture("ctrl+k")!, bindings: bindings, now: 2)
        XCTAssertFalse(machine.expire(now: 2.9))
        XCTAssertTrue(machine.expire(now: 3))
        XCTAssertNil(machine.pendingPrefix)
    }

    func testEscapeCancelsAndInvalidSecondKeyClears() {
        let machine = ChordStateMachine(timeout: 1)
        _ = machine.handle(KeyGesture("ctrl+k")!, bindings: bindings, now: 0)
        XCTAssertEqual(machine.handle(KeyGesture("escape")!, bindings: bindings, now: 0.1), .cancelled)
        _ = machine.handle(KeyGesture("ctrl+k")!, bindings: bindings, now: 1)
        XCTAssertEqual(machine.handle(KeyGesture("ctrl+x")!, bindings: bindings, now: 1.1), .invalid)
        XCTAssertNil(machine.pendingPrefix)
    }

    func testLateSecondKeyReturnsTimedOutRatherThanCommand() {
        let machine = ChordStateMachine(timeout: 1)
        _ = machine.handle(KeyGesture("ctrl+k")!, bindings: bindings, now: 0)
        XCTAssertEqual(machine.handle(KeyGesture("ctrl+c")!, bindings: bindings, now: 2), .timedOut)
    }

    func testPrefixConflictIsReported() {
        let manager = KeyBindingManager(profile: KeyBindingProfile(name: "Bad", bindings: bindings + [
            KeyBinding(keys: [KeyGesture("ctrl+k")!], command: "edit.deleteLine"),
        ]))
        XCTAssertEqual(manager.prefixConflicts.count, 1)
        XCTAssertEqual(manager.prefixConflicts[0].keys, [KeyGesture("ctrl+k")!])
    }
}
