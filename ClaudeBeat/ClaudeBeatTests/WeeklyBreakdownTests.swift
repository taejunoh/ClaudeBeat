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

    /// `scope.surface` isn't decoded yet; the moment the server populates it, the same
    /// model on two surfaces (e.g. Fable on Claude Code and Fable on web) arrives as two
    /// `weekly_scoped` entries sharing a `display_name`. Their ids must stay distinct so
    /// SwiftUI's `ForEach` over `WeeklyItem.id` doesn't collapse them.
    func testScopedEntriesWithSameLabelGetDistinctIds() {
        let items = WeeklyBreakdown.items(from: response(limits: [
            UsageLimit(kind: "weekly_all", percent: 46),
            scoped("Fable", 82),
            scoped("Fable", 91)
        ]))

        let fableItems = items.filter { $0.label == "Fable" }
        XCTAssertEqual(fableItems.count, 2)
        XCTAssertEqual(Set(fableItems.map(\.id)).count, 2)
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

    /// End-to-end seam test: decodes real captured JSON (copied from `capturedJSON` in
    /// UsageLimitTests.swift) all the way through to `WeeklyBreakdown.items(from:)`,
    /// rather than starting from hand-built `UsageLimit` values. A wrong `kind` string
    /// literal or a wrong CodingKey in the decode path would leave every other test in
    /// this suite passing while the app silently fell back to `seven_day`.
    ///
    /// The payload's two weekly entries differ by microseconds (…983485 vs …983652) —
    /// real drift, not a synthetic offset — so this also exercises `sharedResetDate`
    /// against the data that motivated its tolerance.
    func testEndToEndDecodedPayloadProducesWeeklyItems() throws {
        let capturedJSON = """
        {
            "five_hour": { "utilization": 4.0, "resets_at": "2026-08-15T16:49:59.983468+00:00" },
            "seven_day": { "utilization": 46.0, "resets_at": "2026-08-20T09:59:59.983485+00:00" },
            "seven_day_opus": null,
            "seven_day_sonnet": null,
            "nimbus_quill": { "utilization": 0.0, "resets_at": null },
            "amber_ladder": null,
            "limits": [
                { "kind": "session", "group": "session", "percent": 4, "severity": "normal",
                  "resets_at": "2026-08-15T16:49:59.983468+00:00", "scope": null, "is_active": false },
                { "kind": "weekly_all", "group": "weekly", "percent": 46, "severity": "normal",
                  "resets_at": "2026-08-20T09:59:59.983485+00:00", "scope": null, "is_active": false },
                { "kind": "weekly_scoped", "group": "weekly", "percent": 82, "severity": "warning",
                  "resets_at": "2026-08-20T09:59:59.983652+00:00",
                  "scope": { "model": { "id": "abc", "display_name": "Fable" }, "surface": null },
                  "is_active": true }
            ]
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder.makeAPIDecoder().decode(UsageResponse.self, from: capturedJSON)
        let items = WeeklyBreakdown.items(from: response)

        XCTAssertEqual(items.map(\.label), ["All models", "Fable"])
        XCTAssertEqual(items.map(\.utilization), [46, 82])
        XCTAssertNotNil(WeeklyBreakdown.sharedResetDate(for: items))

        let binding = WeeklyBreakdown.bindingItem(in: items)
        XCTAssertEqual(binding?.label, "Fable")
        XCTAssertEqual(binding?.utilization, 82)
    }

    /// Two `weekly_scoped` entries with the same label but different percents must maintain
    /// consistent ordering and ids regardless of the order the server sends them. If sort
    /// has no tie-breaker, the order depends on the input, causing the entries to swap their
    /// positions (and thus their ids) between polls.
    func testScopedEntriesWithSameLabelAreStableAcrossInputOrder() {
        let entries = [
            scoped("Fable", 82),
            scoped("Fable", 91)
        ]
        let entriesReversed = [
            scoped("Fable", 91),
            scoped("Fable", 82)
        ]

        let items1 = WeeklyBreakdown.items(from: response(limits: [
            UsageLimit(kind: "weekly_all", percent: 46)
        ] + entries))

        let items2 = WeeklyBreakdown.items(from: response(limits: [
            UsageLimit(kind: "weekly_all", percent: 46)
        ] + entriesReversed))

        let fableItems1 = items1.filter { $0.label == "Fable" }.sorted { $0.utilization < $1.utilization }
        let fableItems2 = items2.filter { $0.label == "Fable" }.sorted { $0.utilization < $1.utilization }

        XCTAssertEqual(fableItems1.count, 2)
        XCTAssertEqual(fableItems2.count, 2)

        for (item1, item2) in zip(fableItems1, fableItems2) {
            XCTAssertEqual(item1.label, item2.label)
            XCTAssertEqual(item1.utilization, item2.utilization)
            XCTAssertEqual(item1.id, item2.id)
        }
    }

    func testBindingItemIsTheHighestUtilization() {
        let items = [
            WeeklyItem(id: "weekly_all", label: "All models", utilization: 48, resetsAt: nil),
            WeeklyItem(id: "weekly_scoped:0:Fable", label: "Fable", utilization: 86, resetsAt: nil)
        ]

        XCTAssertEqual(WeeklyBreakdown.bindingItem(in: items)?.label, "Fable")
        XCTAssertEqual(WeeklyBreakdown.bindingItem(in: items)?.utilization, 86)
    }

    func testBindingItemKeepsTheEarlierItemOnATie() {
        // Pins the tie-break rule itself: on equal utilization, the earlier item in the list
        // wins. "All models" is first in the list, so this is what keeps it — rather than
        // some model it happens to tie with — as the binding item on a tie.
        let items = [
            WeeklyItem(id: "weekly_all", label: "All models", utilization: 80, resetsAt: nil),
            WeeklyItem(id: "weekly_scoped:0:Fable", label: "Fable", utilization: 80, resetsAt: nil)
        ]

        XCTAssertEqual(WeeklyBreakdown.bindingItem(in: items)?.label, "All models")
    }

    func testBindingItemIsNilForAnEmptyList() {
        XCTAssertNil(WeeklyBreakdown.bindingItem(in: []))
    }
}
