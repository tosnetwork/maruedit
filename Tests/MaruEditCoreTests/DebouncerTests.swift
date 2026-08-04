import XCTest
@testable import MaruEditCore

final class DebouncerTests: XCTestCase {

    func testRapidScheduleCallsOnlyRunTheLastOne() {
        let debouncer = Debouncer(delay: 0.05)
        let expectation = expectation(description: "debounced action ran")
        var runs: [Int] = []

        for i in 1...5 {
            debouncer.schedule {
                runs.append(i)
                if i == 5 { expectation.fulfill() }
            }
        }

        wait(for: [expectation], timeout: 1.0)
        XCTAssertEqual(runs, [5], "only the last scheduled action within the delay window should run")
    }

    func testCancelPreventsScheduledActionFromRunning() {
        let debouncer = Debouncer(delay: 0.05)
        var ran = false
        debouncer.schedule { ran = true }
        debouncer.cancel()

        let notRunExpectation = expectation(description: "give the cancelled action a chance to (not) run")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            notRunExpectation.fulfill()
        }
        wait(for: [notRunExpectation], timeout: 1.0)

        XCTAssertFalse(ran)
    }
}
