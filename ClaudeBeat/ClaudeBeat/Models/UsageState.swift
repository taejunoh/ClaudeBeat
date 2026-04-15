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

    var menuBarPercentage: String {
        guard let utilization = response?.fiveHour.utilization else { return "--%"}
        return "\(Int(normalizeUtilization(utilization)))%"
    }

    var menuBarResetTime: String {
        guard let resetsAt = response?.fiveHour.resetsAt else { return "--" }
        return TimeFormatting.popoverString(until: resetsAt)
    }

    var weeklyPercentage: String {
        guard let utilization = response?.sevenDay.utilization else { return "--%"}
        return "\(Int(normalizeUtilization(utilization)))%"
    }

    var weeklyResetTime: String {
        guard let resetsAt = response?.sevenDay.resetsAt else { return "--" }
        return TimeFormatting.popoverString(until: resetsAt)
    }

    var colorLevel: ColorLevel {
        guard let utilization = response?.fiveHour.utilization else { return .gray }
        let norm = normalizeUtilization(utilization)
        switch norm {
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
    }

    func setError(_ message: String) {
        self.isError = true
        self.errorMessage = message
    }

    /// Normalize utilization: if value is 0-1, convert to 0-100
    private func normalizeUtilization(_ value: Double) -> Double {
        if value > 0 && value <= 1.0 {
            return value * 100
        }
        return value
    }
}
