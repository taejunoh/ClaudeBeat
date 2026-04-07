import SwiftUI

enum ColorLevel: Sendable {
    case green, yellow, red, gray
}

@Observable
final class UsageState {
    private(set) var response: UsageResponse?
    private(set) var lastUpdated: Date?
    private(set) var isError: Bool = false
    private(set) var errorMessage: String?

    var menuBarPercentage: String {
        guard let utilization = response?.fiveHour.utilization else { return "--%"}
        return "\(Int(utilization))%"
    }

    var menuBarResetTime: String {
        guard let resetsAt = response?.fiveHour.resetsAt else { return "--" }
        return TimeFormatting.menuBarString(until: resetsAt)
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
    }

    func setError(_ message: String) {
        self.isError = true
        self.errorMessage = message
    }
}
