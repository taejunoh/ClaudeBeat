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
            sevenDayOpus: nil,
            sevenDaySonnet: nil,
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
            sevenDayOpus: nil, sevenDaySonnet: nil, extraUsage: nil
        ))
        XCTAssertEqual(state.colorLevel, .green)
    }

    func testColorLevel_yellow() {
        let state = UsageState()
        state.update(with: UsageResponse(
            fiveHour: UsageBucket(utilization: 65.0, resetsAt: Date().addingTimeInterval(3600)),
            sevenDay: UsageBucket(utilization: 10.0, resetsAt: Date().addingTimeInterval(7 * 24 * 3600)),
            sevenDayOpus: nil, sevenDaySonnet: nil, extraUsage: nil
        ))
        XCTAssertEqual(state.colorLevel, .yellow)
    }

    func testColorLevel_red() {
        let state = UsageState()
        state.update(with: UsageResponse(
            fiveHour: UsageBucket(utilization: 90.0, resetsAt: Date().addingTimeInterval(3600)),
            sevenDay: UsageBucket(utilization: 10.0, resetsAt: Date().addingTimeInterval(7 * 24 * 3600)),
            sevenDayOpus: nil, sevenDaySonnet: nil, extraUsage: nil
        ))
        XCTAssertEqual(state.colorLevel, .red)
    }

    func testLastUpdated() {
        let state = UsageState()
        XCTAssertNil(state.lastUpdated)

        state.update(with: UsageResponse(
            fiveHour: UsageBucket(utilization: 50.0, resetsAt: Date().addingTimeInterval(3600)),
            sevenDay: UsageBucket(utilization: 10.0, resetsAt: Date().addingTimeInterval(7 * 24 * 3600)),
            sevenDayOpus: nil, sevenDaySonnet: nil, extraUsage: nil
        ))
        XCTAssertNotNil(state.lastUpdated)
    }
}
