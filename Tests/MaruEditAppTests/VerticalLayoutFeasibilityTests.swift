@testable import MaruEditApp
import XCTest

@MainActor
final class VerticalLayoutFeasibilityTests: XCTestCase {
    func testAppKitLaysOutMixedJapaneseTextVertically() {
        let report = VerticalLayoutFeasibility.run()
        XCTAssertTrue(report.isViable)
        XCTAssertGreaterThanOrEqual(report.glyphCount, 10)
    }
}
