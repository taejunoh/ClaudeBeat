import Foundation
import UserNotifications

@Observable
final class NotificationManager {
    var sessionThreshold: Double = 80
    var weeklyThreshold: Double = 80
    var extraUsageThreshold: Double = 40
    var sessionAlertsEnabled: Bool = true
    var weeklyAlertsEnabled: Bool = true
    var extraUsageAlertsEnabled: Bool = true

    private var sessionAlerted: Bool = false
    private var weeklyAlerted: Bool = false

    func requestPermission() {
        guard Bundle.main.bundleIdentifier != nil else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func shouldAlertForSession(utilization: Double) -> Bool {
        guard sessionAlertsEnabled, !sessionAlerted else { return false }
        return utilization >= sessionThreshold
    }

    func shouldAlertForWeekly(utilization: Double) -> Bool {
        guard weeklyAlertsEnabled, !weeklyAlerted else { return false }
        return utilization >= weeklyThreshold
    }

    func markSessionAlerted() {
        sessionAlerted = true
    }

    func markWeeklyAlerted() {
        weeklyAlerted = true
    }

    func resetSessionAlertIfNeeded(utilization: Double) {
        if utilization < sessionThreshold {
            sessionAlerted = false
        }
    }

    func resetWeeklyAlertIfNeeded(utilization: Double) {
        if utilization < weeklyThreshold {
            weeklyAlerted = false
        }
    }

    func checkAndNotify(response: UsageResponse) {
        let sessionUtil = response.fiveHour.utilization
        resetSessionAlertIfNeeded(utilization: sessionUtil)
        if shouldAlertForSession(utilization: sessionUtil) {
            sendNotification(
                title: "Claude Session Usage",
                body: "5-hour usage at \(Int(sessionUtil))%"
            )
            markSessionAlerted()
        }

        let weeklyUtil = response.sevenDay.utilization
        resetWeeklyAlertIfNeeded(utilization: weeklyUtil)
        if shouldAlertForWeekly(utilization: weeklyUtil) {
            sendNotification(
                title: "Claude Weekly Usage",
                body: "7-day usage at \(Int(weeklyUtil))%"
            )
            markWeeklyAlerted()
        }
    }

    private func sendNotification(title: String, body: String) {
        guard Bundle.main.bundleIdentifier != nil else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}
