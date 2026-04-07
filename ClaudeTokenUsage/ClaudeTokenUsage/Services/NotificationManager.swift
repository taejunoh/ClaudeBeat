import Foundation
import UserNotifications

@Observable
final class NotificationManager {
    var alertsEnabled: Bool = true
    var sessionThreshold: Double = 80
    var weeklyThreshold: Double = 80
    var extraUsageThreshold: Double = 40
    var sessionAlertsEnabled: Bool = true
    var weeklyAlertsEnabled: Bool = true
    var extraUsageAlertsEnabled: Bool = true

    private var sessionAlerted: Bool = false
    private var weeklyAlerted: Bool = false
    private var permissionGranted: Bool = false
    private var previousSessionUtil: Double?
    var sessionResetAlertEnabled: Bool = true

    func requestPermission() {
        guard Bundle.main.bundleIdentifier != nil else {
            NSLog("[Notifications] No bundle identifier — skipping permission request")
            return
        }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            NSLog("[Notifications] Permission granted: \(granted), error: \(error?.localizedDescription ?? "none")")
            self.permissionGranted = granted
        }
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
        guard alertsEnabled else { return }

        let sessionUtil = response.fiveHour.utilization

        // Detect session reset (usage drops significantly = new 5h window)
        if sessionResetAlertEnabled, let prev = previousSessionUtil, prev >= 50, sessionUtil < 10 {
            NSLog("[Notifications] Session reset detected: \(Int(prev))% → \(Int(sessionUtil))%")
            sendNotification(
                title: "Claude Session Reset",
                body: "Your 5-hour session has reset. You're good to go!"
            )
            sessionAlerted = false
        }
        previousSessionUtil = sessionUtil

        resetSessionAlertIfNeeded(utilization: sessionUtil)
        if shouldAlertForSession(utilization: sessionUtil) {
            NSLog("[Notifications] Session threshold hit: \(Int(sessionUtil))% >= \(Int(sessionThreshold))%")
            sendNotification(
                title: "Claude Session Usage",
                body: "5-hour usage at \(Int(sessionUtil))%"
            )
            markSessionAlerted()
        }

        let weeklyUtil = response.sevenDay.utilization
        resetWeeklyAlertIfNeeded(utilization: weeklyUtil)
        if shouldAlertForWeekly(utilization: weeklyUtil) {
            NSLog("[Notifications] Weekly threshold hit: \(Int(weeklyUtil))% >= \(Int(weeklyThreshold))%")
            sendNotification(
                title: "Claude Weekly Usage",
                body: "7-day usage at \(Int(weeklyUtil))%"
            )
            markWeeklyAlerted()
        }
    }

    private func sendNotification(title: String, body: String) {
        guard Bundle.main.bundleIdentifier != nil else {
            NSLog("[Notifications] No bundle identifier — cannot send notification")
            return
        }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                NSLog("[Notifications] Failed to deliver: \(error.localizedDescription)")
            } else {
                NSLog("[Notifications] Delivered: \(title) — \(body)")
            }
        }
    }
}
