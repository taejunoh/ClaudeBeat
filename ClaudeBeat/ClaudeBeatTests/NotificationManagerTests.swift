import XCTest
@testable import ClaudeBeat

@MainActor
final class NotificationManagerTests: XCTestCase {

    func testShouldAlert_belowThreshold() {
        let manager = NotificationManager()
        manager.sessionThreshold = 80
        manager.sessionAlertsEnabled = true

        let result = manager.shouldAlertForSession(utilization: 70)
        XCTAssertFalse(result)
    }

    func testShouldAlert_atThreshold() {
        let manager = NotificationManager()
        manager.sessionThreshold = 80
        manager.sessionAlertsEnabled = true

        let result = manager.shouldAlertForSession(utilization: 80)
        XCTAssertTrue(result)
    }

    func testShouldAlert_aboveThreshold() {
        let manager = NotificationManager()
        manager.sessionThreshold = 80
        manager.sessionAlertsEnabled = true

        let result = manager.shouldAlertForSession(utilization: 90)
        XCTAssertTrue(result)
    }

    func testShouldAlert_disabled() {
        let manager = NotificationManager()
        manager.sessionThreshold = 80
        manager.sessionAlertsEnabled = false

        let result = manager.shouldAlertForSession(utilization: 90)
        XCTAssertFalse(result)
    }

    func testShouldAlert_noRepeatUntilReset() {
        let manager = NotificationManager()
        manager.sessionThreshold = 80
        manager.sessionAlertsEnabled = true

        // First time crossing threshold → alert
        XCTAssertTrue(manager.shouldAlertForSession(utilization: 85))
        manager.markSessionAlerted()

        // Still above → no repeat
        XCTAssertFalse(manager.shouldAlertForSession(utilization: 90))

        // Drops below → reset
        manager.resetSessionAlertIfNeeded(utilization: 50)
        XCTAssertTrue(manager.shouldAlertForSession(utilization: 85))
    }

    private func item(_ label: String, _ utilization: Double) -> WeeklyItem {
        WeeklyItem(id: "id:\(label)", label: label, utilization: utilization, resetsAt: nil)
    }

    func testShouldAlertWeekly() {
        let manager = NotificationManager()
        manager.weeklyThreshold = 80
        manager.weeklyAlertsEnabled = true

        XCTAssertTrue(manager.shouldAlertForWeekly(utilization: 85, label: "All models"))
        XCTAssertFalse(manager.shouldAlertForWeekly(utilization: 70, label: "All models"))
    }

    func testWeeklyAlertFiresOnceForAModelThenStaysQuiet() {
        let manager = NotificationManager()
        manager.weeklyThreshold = 80
        manager.weeklyAlertsEnabled = true

        let first = manager.weeklyAlertsToSend(for: [item("All models", 48), item("Fable", 86)])
        XCTAssertEqual(first.map(\.label), ["Fable"])

        let second = manager.weeklyAlertsToSend(for: [item("All models", 48), item("Fable", 87)])
        XCTAssertTrue(second.isEmpty)
    }

    func testWeeklyAlertRearmsAfterDroppingBelowThreshold() {
        let manager = NotificationManager()
        manager.weeklyThreshold = 80
        manager.weeklyAlertsEnabled = true

        _ = manager.weeklyAlertsToSend(for: [item("Fable", 86)])
        _ = manager.weeklyAlertsToSend(for: [item("Fable", 10)])

        let again = manager.weeklyAlertsToSend(for: [item("Fable", 86)])
        XCTAssertEqual(again.map(\.label), ["Fable"])
    }

    func testEachWeeklyLimitLatchesIndependently() {
        // Independence is across distinct labels; see testItemsSharingALabelCollapseIntoOneAlert for same-label behavior.
        let manager = NotificationManager()
        manager.weeklyThreshold = 80
        manager.weeklyAlertsEnabled = true

        let sent = manager.weeklyAlertsToSend(for: [item("All models", 91), item("Fable", 86)])
        XCTAssertEqual(sent.map(\.label), ["All models", "Fable"])
    }

    func testItemsSharingALabelCollapseIntoOneAlert() {
        // When multiple limits share the same label and both are above the threshold, only one
        // alert fires per poll. Same-label limits produce near-identical text (e.g., "Fable at 86%..."
        // and "Fable at 90%..."), and users cannot act on them differently. Collapsing them prevents
        // alert fatigue. The latch is keyed by label by design.
        let manager = NotificationManager()
        manager.weeklyThreshold = 80
        manager.weeklyAlertsEnabled = true

        let sent = manager.weeklyAlertsToSend(for: [item("Fable", 86), item("Fable", 90)])
        XCTAssertEqual(sent.count, 1)
        XCTAssertEqual(sent.map(\.label), ["Fable"])
    }

    func testANewModelDoesNotRefireExistingAlerts() {
        let manager = NotificationManager()
        manager.weeklyThreshold = 80
        manager.weeklyAlertsEnabled = true

        _ = manager.weeklyAlertsToSend(for: [item("All models", 91), item("Fable", 86)])

        // A model appearing shifts every WeeklyItem.id after it. Latching by label is what
        // keeps the already-alerted limits quiet through that.
        let sent = manager.weeklyAlertsToSend(for: [
            item("All models", 91), item("Aurora", 88), item("Fable", 86)
        ])
        XCTAssertEqual(sent.map(\.label), ["Aurora"])
    }

    func testWeeklyAlertRefiresAfterDisappearingThenReturningStillHot() {
        let manager = NotificationManager()
        manager.weeklyThreshold = 80
        manager.weeklyAlertsEnabled = true

        _ = manager.weeklyAlertsToSend(for: [item("Fable", 86)])

        // Fable drops out of the items entirely for a poll (model missing from the API
        // response), then comes back still above the threshold. The stale latch must not
        // suppress it.
        _ = manager.weeklyAlertsToSend(for: [item("All models", 48)])

        let again = manager.weeklyAlertsToSend(for: [item("All models", 48), item("Fable", 86)])
        XCTAssertEqual(again.map(\.label), ["Fable"])
    }

    func testWeeklyAlertStaysQuietWhilePresentAndHotAcrossPolls() {
        let manager = NotificationManager()
        manager.weeklyThreshold = 80
        manager.weeklyAlertsEnabled = true

        let first = manager.weeklyAlertsToSend(for: [item("Fable", 86)])
        XCTAssertEqual(first.map(\.label), ["Fable"])

        let second = manager.weeklyAlertsToSend(for: [item("Fable", 87)])
        XCTAssertTrue(second.isEmpty)

        let third = manager.weeklyAlertsToSend(for: [item("Fable", 88)])
        XCTAssertTrue(third.isEmpty)
    }

    func testWeeklyAlertsRespectTheEnableToggle() {
        let manager = NotificationManager()
        manager.weeklyThreshold = 80
        manager.weeklyAlertsEnabled = false

        XCTAssertTrue(manager.weeklyAlertsToSend(for: [item("Fable", 86)]).isEmpty)
    }

    func testWeeklyAlertBodyNamesTheLimit() {
        XCTAssertEqual(
            NotificationManager.weeklyAlertBody(for: item("Fable", 86)),
            "Fable at 86% of the 7-day limit"
        )
    }

    func testResponseWithoutLimitsStillAlertsOnTheSevenDayTotal() throws {
        let manager = NotificationManager()
        manager.weeklyThreshold = 80
        manager.weeklyAlertsEnabled = true

        // Covers the whole seam — response → items → alerts — for the case where the API
        // reports no `limits` at all, which must behave exactly as it did before.
        let response = UsageResponse(
            fiveHour: UsageBucket(utilization: 4, resetsAt: nil),
            sevenDay: UsageBucket(utilization: 91, resetsAt: nil)
        )

        let sent = manager.weeklyAlertsToSend(for: WeeklyBreakdown.items(from: response))

        XCTAssertEqual(sent.map(\.label), ["All models"])
        XCTAssertEqual(
            NotificationManager.weeklyAlertBody(for: try XCTUnwrap(sent.first)),
            "All models at 91% of the 7-day limit"
        )
    }
}
