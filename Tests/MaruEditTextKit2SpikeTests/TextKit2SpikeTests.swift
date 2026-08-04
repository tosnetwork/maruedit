import AppKit
import XCTest
@testable import MaruEditTextKit2Spike

@MainActor
final class TextKit2SpikeTests: XCTestCase {
    func testIsolatedHarnessActuallyUsesTextKit2AndLaysOut() {
        let harness = TextKit2SpikeHarness(text: "one\ntwo\n日本語\n")
        XCTAssertTrue(harness.usesTextKit2)
        XCTAssertGreaterThan(harness.enumerateLayoutFragmentCount(), 0)
    }

    func testMultipleSelectionAndIMEContractsRemainAvailable() {
        let harness = TextKit2SpikeHarness(text: "alpha beta gamma")
        XCTAssertTrue(harness.acceptsMultipleSelections([
            NSRange(location: 0, length: 5),
            NSRange(location: 11, length: 5),
        ]))
        XCTAssertTrue(harness.exposesMarkedTextContract)
    }

    func testOneMegabyteLayoutProbe() {
        let text = String(repeating: "func value() -> Int { 42 }\n", count: 38_000)
        let harness = TextKit2SpikeHarness(text: text)
        let textKit2Duration = harness.layoutDuration()

        let storage = NSTextStorage(string: text)
        let textKit1Layout = NSLayoutManager()
        let container = NSTextContainer(
            containerSize: NSSize(width: 800, height: CGFloat.greatestFiniteMagnitude))
        storage.addLayoutManager(textKit1Layout)
        textKit1Layout.addTextContainer(container)
        let started = CFAbsoluteTimeGetCurrent()
        textKit1Layout.ensureLayout(
            forCharacterRange: NSRange(location: 0, length: storage.length))
        let textKit1Duration = CFAbsoluteTimeGetCurrent() - started

        print("M7_TEXTKIT_LAYOUT_1MB textkit1=\(textKit1Duration) textkit2=\(textKit2Duration) fragments=\(harness.enumerateLayoutFragmentCount())")
        XCTAssertLessThan(textKit2Duration, 5, "Spike guardrail, not a production performance promise")
        XCTAssertLessThan(textKit1Duration, 5, "Comparison guardrail, not a production performance promise")
    }
}
