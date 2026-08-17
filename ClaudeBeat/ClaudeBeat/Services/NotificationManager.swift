import AppKit
import Foundation
import UserNotifications

@MainActor
@Observable
final class NotificationManager {
    private static let defaults = UserDefaults(suiteName: "com.claudebeat.macos") ?? .standard

    var alertsEnabled: Bool {
        didSet { Self.defaults.set(alertsEnabled, forKey: "alertsEnabled") }
    }
    var sessionThreshold: Double {
        didSet { Self.defaults.set(sessionThreshold, forKey: "sessionThreshold") }
    }
    var weeklyThreshold: Double {
        didSet { Self.defaults.set(weeklyThreshold, forKey: "weeklyThreshold") }
    }
    var extraUsageThreshold: Double {
        didSet { Self.defaults.set(extraUsageThreshold, forKey: "extraUsageThreshold") }
    }
    var sessionAlertsEnabled: Bool {
        didSet { Self.defaults.set(sessionAlertsEnabled, forKey: "sessionAlertsEnabled") }
    }
    var weeklyAlertsEnabled: Bool {
        didSet { Self.defaults.set(weeklyAlertsEnabled, forKey: "weeklyAlertsEnabled") }
    }
    var extraUsageAlertsEnabled: Bool {
        didSet { Self.defaults.set(extraUsageAlertsEnabled, forKey: "extraUsageAlertsEnabled") }
    }
    var sessionResetAlertEnabled: Bool {
        didSet { Self.defaults.set(sessionResetAlertEnabled, forKey: "sessionResetAlertEnabled") }
    }

    private var sessionAlerted: Bool = false
    // Keyed by label, not by WeeklyItem.id: ids embed the item's sorted position, so one
    // new model shifts the ids after it and would silently re-arm those latches.
    private var weeklyAlerted: Set<String> = []
    private var extraUsageAlerted: Bool = false
    private var previousSessionUtil: Double?

    init() {
        let d = Self.defaults
        self.alertsEnabled = d.object(forKey: "alertsEnabled") as? Bool ?? true
        self.sessionThreshold = d.object(forKey: "sessionThreshold") as? Double ?? 80
        self.weeklyThreshold = d.object(forKey: "weeklyThreshold") as? Double ?? 80
        self.extraUsageThreshold = d.object(forKey: "extraUsageThreshold") as? Double ?? 40
        self.sessionAlertsEnabled = d.object(forKey: "sessionAlertsEnabled") as? Bool ?? true
        self.weeklyAlertsEnabled = d.object(forKey: "weeklyAlertsEnabled") as? Bool ?? true
        self.extraUsageAlertsEnabled = d.object(forKey: "extraUsageAlertsEnabled") as? Bool ?? true
        self.sessionResetAlertEnabled = d.object(forKey: "sessionResetAlertEnabled") as? Bool ?? true
    }

    func requestPermission() {
        guard Bundle.main.bundleIdentifier != nil else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    func shouldAlertForSession(utilization: Double) -> Bool {
        guard sessionAlertsEnabled, !sessionAlerted else { return false }
        return utilization >= sessionThreshold
    }

    func shouldAlertForWeekly(utilization: Double, label: String) -> Bool {
        guard weeklyAlertsEnabled, !weeklyAlerted.contains(label) else { return false }
        return utilization >= weeklyThreshold
    }

    func markSessionAlerted() { sessionAlerted = true }
    func markWeeklyAlerted(label: String) { weeklyAlerted.insert(label) }

    func resetSessionAlertIfNeeded(utilization: Double) {
        if utilization < sessionThreshold { sessionAlerted = false }
    }

    func resetWeeklyAlertIfNeeded(utilization: Double, label: String) {
        if utilization < weeklyThreshold { weeklyAlerted.remove(label) }
    }

    /// The weekly limits to notify about on this poll, in list order, advancing the latch.
    ///
    /// Every weekly limit is watched, not just the all-models total: a per-model limit
    /// routinely binds first — Fable at 86% against 48% for all models — and watching the
    /// total alone stays silent straight through it.
    func weeklyAlertsToSend(for items: [WeeklyItem]) -> [WeeklyItem] {
        var toSend: [WeeklyItem] = []
        for item in items {
            resetWeeklyAlertIfNeeded(utilization: item.utilization, label: item.label)
            if shouldAlertForWeekly(utilization: item.utilization, label: item.label) {
                toSend.append(item)
                markWeeklyAlerted(label: item.label)
            }
        }

        // A latched label that stops appearing in items (its model dropped out of the API
        // response, or the server transiently omitted it) would otherwise never get pruned,
        // since resetWeeklyAlertIfNeeded above only runs for labels still present. Left alone,
        // that stale latch would silently swallow the next alert if the limit came back already
        // over threshold. Drop it here instead: a label the API isn't reporting has no limit to
        // be latched against, so re-arming it is correct.
        let currentLabels = Set(items.map(\.label))
        weeklyAlerted.formIntersection(currentLabels)

        return toSend
    }

    static func weeklyAlertBody(for item: WeeklyItem) -> String {
        "\(item.label) at \(Int(item.utilization))% of the 7-day limit"
    }

    func checkAndNotify(response: UsageResponse) {
        guard alertsEnabled else { return }

        let sessionUtil = response.fiveHour.utilization

        // Session reset detection
        if sessionResetAlertEnabled, let prev = previousSessionUtil, prev >= 50, sessionUtil < 10 {
            sendNotification(
                title: "Claude Session Reset",
                body: "Your 5-hour session has reset. You're good to go!"
            )
            sessionAlerted = false
        }
        previousSessionUtil = sessionUtil

        // Session threshold
        resetSessionAlertIfNeeded(utilization: sessionUtil)
        if shouldAlertForSession(utilization: sessionUtil) {
            sendNotification(
                title: "Claude Session Usage",
                body: "5-hour usage at \(Int(sessionUtil))%"
            )
            markSessionAlerted()
        }

        // Weekly thresholds, one per reported limit
        for item in weeklyAlertsToSend(for: WeeklyBreakdown.items(from: response)) {
            sendNotification(
                title: "Claude Weekly Usage",
                body: Self.weeklyAlertBody(for: item)
            )
        }

        // Extra usage threshold
        if extraUsageAlertsEnabled, !extraUsageAlerted,
           let extra = response.extraUsage, extra.isEnabled,
           let usedCredits = extra.usedCredits {
            let spent = Double(usedCredits) / 100.0
            if spent >= extraUsageThreshold {
                sendNotification(
                    title: "Claude Extra Usage",
                    body: "Extra usage at $\(String(format: "%.2f", spent))"
                )
                extraUsageAlerted = true
            }
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
