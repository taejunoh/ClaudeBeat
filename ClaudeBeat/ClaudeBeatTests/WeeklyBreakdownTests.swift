import XCTest
@testable import ClaudeBeat

final class WeeklyBreakdownTests: XCTestCase {

    private let weeklyReset = Date(timeIntervalSince1970: 1_755_684_000)

    private func response(limits: [UsageLimit], sevenDay: Double = 46.0) -> UsageResponse {
        UsageResponse(
            fiveHour: UsageBucket(utilization: 4.0, resetsAt: nil),
            sevenDay: UsageBucket(utilization: sevenDay, resetsAt: weeklyReset),
            extraUsage: nil,
            limits: limits
        )
    }

    private func scoped(_ name: String, _ percent: Double, resetsAt: Date? = nil) -> UsageLimit {
        UsageLimit(
            kind: "weekly_scoped",
            percent: percent,
            resetsAt: resetsAt,
            scope: LimitScope(model: LimitModel(displayName: name))
        )
    }

    func testAllModelsAndScopedModels() {
        let items = WeeklyBreakdown.items(from: response(limits: [
            UsageLimit(kind: "session", percent: 4),
            UsageLimit(kind: "weekly_all", percent: 46, resetsAt: weeklyReset),
            scoped("Fable", 82, resetsAt: weeklyReset)
        ]))

        XCTAssertEqual(items.map(\.label), ["All models", "Fable"])
        XCTAssertEqual(items.map(\.utilization), [46, 82])
    }

    func testAllModelsIsAlwaysFirstAndScopedAreSortedByLabel() {
        let items = WeeklyBreakdown.items(from: response(limits: [
            scoped("Sonnet", 12),
            scoped("Fable", 82),
            UsageLimit(kind: "weekly_all", percent: 46),
            scoped("Opus", 8)
        ]))

        XCTAssertEqual(items.map(\.label), ["All models", "Fable", "Opus", "Sonnet"])
    }

    func testUnknownKindIsIgnored() {
        let items = WeeklyBreakdown.items(from: response(limits: [
            UsageLimit(kind: "weekly_all", percent: 46),
            UsageLimit(kind: "monthly_something_new", percent: 99)
        ]))

        XCTAssertEqual(items.map(\.label), ["All models"])
    }

    func testScopedWithoutDisplayNameIsDropped() {
        let items = WeeklyBreakdown.items(from: response(limits: [
            UsageLimit(kind: "weekly_all", percent: 46),
            UsageLimit(kind: "weekly_scoped", percent: 82, scope: nil),
            UsageLimit(kind: "weekly_scoped", percent: 71, scope: LimitScope(model: LimitModel(displayName: ""))),
            scoped("Fable", 82)
        ]))

        XCTAssertEqual(items.map(\.label), ["All models", "Fable"])
    }

    func testFallsBackToSevenDayWhenLimitsIsEmpty() {
        let items = WeeklyBreakdown.items(from: response(limits: []))

        XCTAssertEqual(items.map(\.label), ["All models"])
        XCTAssertEqual(items.first?.utilization, 46)
        XCTAssertEqual(items.first?.resetsAt, weeklyReset)
    }

    func testFallsBackToSevenDayWhenLimitsHasNoWeeklyEntries() {
        let items = WeeklyBreakdown.items(from: response(limits: [
            UsageLimit(kind: "session", percent: 4)
        ]))

        XCTAssertEqual(items.map(\.label), ["All models"])
        XCTAssertEqual(items.first?.utilization, 46)
    }

    func testSharedResetIgnoresSubMinuteDrift() {
        // Observed: weekly_all …983485 vs weekly_scoped …983652, the same reset.
        let items = [
            WeeklyItem(id: "a", label: "All models", utilization: 46, resetsAt: weeklyReset),
            WeeklyItem(id: "b", label: "Fable", utilization: 82, resetsAt: weeklyReset.addingTimeInterval(0.000167))
        ]

        XCTAssertEqual(WeeklyBreakdown.sharedResetDate(for: items), weeklyReset)
    }

    func testNoSharedResetWhenTimesDifferByMinutes() {
        let items = [
            WeeklyItem(id: "a", label: "All models", utilization: 46, resetsAt: weeklyReset),
            WeeklyItem(id: "b", label: "Fable", utilization: 82, resetsAt: weeklyReset.addingTimeInterval(600))
        ]

        XCTAssertNil(WeeklyBreakdown.sharedResetDate(for: items))
    }

    func testNoSharedResetWhenPairwiseWithinToleranceButSpreadIsNot() {
        // T, T-59s, T+59s: each is within 60s of the pivot `T`, but the outer two differ by
        // 118s. Agreement must be judged by the whole set's spread, not distance from one
        // arbitrarily chosen element.
        let items = [
            WeeklyItem(id: "b", label: "Fable", utilization: 82, resetsAt: weeklyReset),
            WeeklyItem(id: "a", label: "All models", utilization: 46, resetsAt: weeklyReset.addingTimeInterval(-59)),
            WeeklyItem(id: "c", label: "Opus", utilization: 12, resetsAt: weeklyReset.addingTimeInterval(59))
        ]

        XCTAssertNil(WeeklyBreakdown.sharedResetDate(for: items))
    }

    func testSharedResetToleranceBoundaryIsOneMinute() {
        let items = [
            WeeklyItem(id: "a", label: "All models", utilization: 46, resetsAt: weeklyReset),
            WeeklyItem(id: "b", label: "Fable", utilization: 82, resetsAt: weeklyReset.addingTimeInterval(59.9))
        ]
        XCTAssertEqual(WeeklyBreakdown.sharedResetDate(for: items), weeklyReset)

        let itemsOverBoundary = [
            WeeklyItem(id: "a", label: "All models", utilization: 46, resetsAt: weeklyReset),
            WeeklyItem(id: "b", label: "Fable", utilization: 82, resetsAt: weeklyReset.addingTimeInterval(60.1))
        ]
        XCTAssertNil(WeeklyBreakdown.sharedResetDate(for: itemsOverBoundary))
    }

    func testNoSharedResetWhenAnyItemLacksOne() {
        let items = [
            WeeklyItem(id: "a", label: "All models", utilization: 46, resetsAt: weeklyReset),
            WeeklyItem(id: "b", label: "Fable", utilization: 82, resetsAt: nil)
        ]

        XCTAssertNil(WeeklyBreakdown.sharedResetDate(for: items))
    }

    func testNoSharedResetForEmptyList() {
        XCTAssertNil(WeeklyBreakdown.sharedResetDate(for: []))
    }
}
