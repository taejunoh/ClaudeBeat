import XCTest
@testable import ClaudeBeat

@MainActor
final class UsageStateTests: XCTestCase {

    func testMenuBarText_withData() {
        let state = UsageState()
        let resetDate = Date().addingTimeInterval(2 * 3600 + 60)
        state.update(with: UsageResponse(
            fiveHour: UsageBucket(utilization: 69.0, resetsAt: resetDate),
            sevenDay: UsageBucket(utilization: 15.0, resetsAt: Date().addingTimeInterval(7 * 24 * 3600)),
            extraUsage: nil
        ))

        XCTAssertEqual(state.menuBarPercentage, "69%")
        XCTAssertEqual(state.menuBarResetTime, "2h")
        XCTAssertFalse(state.isError)
    }

    func testMenuBarText_noData() {
        let state = UsageState()
        XCTAssertEqual(state.menuBarPercentage, "--%")
        XCTAssertEqual(state.menuBarResetTime, "--")
    }

    func testColorLevel_green() {
        let state = UsageState()
        state.update(with: UsageResponse(
            fiveHour: UsageBucket(utilization: 30.0, resetsAt: Date().addingTimeInterval(3600)),
            sevenDay: UsageBucket(utilization: 10.0, resetsAt: Date().addingTimeInterval(7 * 24 * 3600)),
            extraUsage: nil
        ))
        XCTAssertEqual(state.colorLevel, .green)
    }

    func testColorLevel_yellow() {
        let state = UsageState()
        state.update(with: UsageResponse(
            fiveHour: UsageBucket(utilization: 65.0, resetsAt: Date().addingTimeInterval(3600)),
            sevenDay: UsageBucket(utilization: 10.0, resetsAt: Date().addingTimeInterval(7 * 24 * 3600)),
            extraUsage: nil
        ))
        XCTAssertEqual(state.colorLevel, .yellow)
    }

    func testColorLevel_red() {
        let state = UsageState()
        state.update(with: UsageResponse(
            fiveHour: UsageBucket(utilization: 90.0, resetsAt: Date().addingTimeInterval(3600)),
            sevenDay: UsageBucket(utilization: 10.0, resetsAt: Date().addingTimeInterval(7 * 24 * 3600)),
            extraUsage: nil
        ))
        XCTAssertEqual(state.colorLevel, .red)
    }

    func testLastUpdated() {
        let state = UsageState()
        XCTAssertNil(state.lastUpdated)

        state.update(with: UsageResponse(
            fiveHour: UsageBucket(utilization: 50.0, resetsAt: Date().addingTimeInterval(3600)),
            sevenDay: UsageBucket(utilization: 10.0, resetsAt: Date().addingTimeInterval(7 * 24 * 3600)),
            extraUsage: nil
        ))
        XCTAssertNotNil(state.lastUpdated)
    }

    func testNeedsLogin_setAndClearedByUpdate() {
        let state = UsageState()
        XCTAssertFalse(state.needsLogin)

        state.setNeedsLogin()
        XCTAssertTrue(state.needsLogin)
        XCTAssertTrue(state.isError)

        state.update(with: UsageResponse(
            fiveHour: UsageBucket(utilization: 10.0, resetsAt: Date().addingTimeInterval(3600)),
            sevenDay: UsageBucket(utilization: 5.0, resetsAt: Date().addingTimeInterval(7 * 24 * 3600)),
            extraUsage: nil
        ))
        XCTAssertFalse(state.needsLogin)
        XCTAssertFalse(state.isError)
        XCTAssertNil(state.errorMessage)
    }

    func testSetError_doesNotSetNeedsLogin() {
        let state = UsageState()
        state.setError("HTTP 500")
        XCTAssertTrue(state.isError)
        XCTAssertFalse(state.needsLogin)
    }

    func testSetError_clearsPriorNeedsLogin() {
        let state = UsageState()
        state.setNeedsLogin()
        XCTAssertTrue(state.needsLogin)

        state.setError("Timeout")
        XCTAssertTrue(state.isError)
        XCTAssertFalse(state.needsLogin)
        XCTAssertEqual(state.errorMessage, "Timeout")
    }

    func testWeeklyItems_noData() {
        let state = UsageState()
        XCTAssertTrue(state.weeklyItems.isEmpty)
    }

    func testWeeklyItems_fromLimits() {
        let state = UsageState()
        let reset = Date().addingTimeInterval(5 * 24 * 3600)
        state.update(with: UsageResponse(
            fiveHour: UsageBucket(utilization: 4.0, resetsAt: Date().addingTimeInterval(3600)),
            sevenDay: UsageBucket(utilization: 46.0, resetsAt: reset),
            extraUsage: nil,
            limits: [
                UsageLimit(kind: "weekly_all", percent: 46, resetsAt: reset),
                UsageLimit(
                    kind: "weekly_scoped",
                    percent: 82,
                    resetsAt: reset,
                    scope: LimitScope(model: LimitModel(displayName: "Fable"))
                )
            ]
        ))

        XCTAssertEqual(state.weeklyItems.map(\.label), ["All models", "Fable"])
        XCTAssertEqual(state.weeklyItems.map(\.utilization), [46, 82])
    }
}
