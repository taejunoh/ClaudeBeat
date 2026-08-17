import SwiftUI

enum ColorLevel: Sendable {
    case green, yellow, red, gray
}

@MainActor
@Observable
final class UsageState {
    private(set) var response: UsageResponse?
    private(set) var lastUpdated: Date?
    private(set) var isError: Bool = false
    private(set) var errorMessage: String?
    private(set) var needsLogin: Bool = false

    var menuBarPercentage: String {
        guard let utilization = response?.fiveHour.utilization else { return "--%"}
        return "\(Int(utilization))%"
    }

    var menuBarResetTime: String {
        guard let resetsAt = response?.fiveHour.resetsAt else { return "--" }
        return TimeFormatting.popoverString(until: resetsAt)
    }

    // These read the binding limit rather than the flat seven_day bucket: a per-model
    // limit routinely binds first, and showing the total alone reassures the user at
    // exactly the wrong moment. With no `limits` in the response the list holds only the
    // seven_day fallback item, so these produce today's values unchanged.
    var weeklyPercentage: String {
        guard let utilization = weeklyBindingItem?.utilization else { return "--%"}
        return "\(Int(utilization))%"
    }

    var weeklyResetTime: String {
        guard let resetsAt = weeklyBindingItem?.resetsAt else { return "--" }
        return TimeFormatting.popoverString(until: resetsAt)
    }

    /// The model whose weekly limit binds, or nil when the all-models limit does. The menu
    /// bar appends it so a higher-than-expected percentage is attributable.
    var weeklyModelLabel: String? {
        guard let item = weeklyBindingItem, item.label != WeeklyBreakdown.allModelsLabel else {
            return nil
        }
        return item.label
    }

    private var weeklyBindingItem: WeeklyItem? {
        WeeklyBreakdown.bindingItem(in: weeklyItems)
    }

    var weeklyItems: [WeeklyItem] {
        guard let response else { return [] }
        return WeeklyBreakdown.items(from: response)
    }

    var colorLevel: ColorLevel {
        guard let utilization = response?.fiveHour.utilization else { return .gray }
        switch utilization {
        case 0..<50: return .green
        case 50..<80: return .yellow
        default: return .red
        }
    }

    var statusColor: Color {
        switch colorLevel {
        case .green: return .green
        case .yellow: return .yellow
        case .red: return .red
        case .gray: return .gray
        }
    }

    func update(with response: UsageResponse) {
        self.response = response
        self.lastUpdated = Date()
        self.isError = false
        self.errorMessage = nil
        self.needsLogin = false
    }

    func setError(_ message: String) {
        self.isError = true
        self.errorMessage = message
        self.needsLogin = false
    }

    func setNeedsLogin() {
        self.needsLogin = true
        self.isError = true
        self.errorMessage = "Login required"
    }
}
