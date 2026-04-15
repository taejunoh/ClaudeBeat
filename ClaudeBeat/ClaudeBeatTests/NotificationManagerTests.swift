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

    func testShouldAlertWeekly() {
        let manager = NotificationManager()
        manager.weeklyThreshold = 80
        manager.weeklyAlertsEnabled = true

        XCTAssertTrue(manager.shouldAlertForWeekly(utilization: 85))
        XCTAssertFalse(manager.shouldAlertForWeekly(utilization: 70))
    }
}
