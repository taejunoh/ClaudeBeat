import Foundation

enum TimeFormatting {
    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f
    }()
    /// Compact format for menu bar: "2h", "45m", "<1m", "now"
    static func menuBarString(until date: Date) -> String {
        let seconds = date.timeIntervalSinceNow
        guard seconds > 0 else { return "now" }

        let totalMinutes = Int(seconds / 60)
        let hours = totalMinutes / 60

        if hours >= 1 {
            return "\(hours)h"
        } else if totalMinutes >= 1 {
            return "\(totalMinutes)m"
        } else {
            return "<1m"
        }
    }

    /// Detailed format for popover: "2h 14m", "45m", or "Apr 10"
    static func popoverString(until date: Date) -> String {
        let seconds = date.timeIntervalSinceNow
        guard seconds > 0 else { return "now" }

        let totalMinutes = Int(seconds / 60)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60

        // More than 24h: show date
        if hours >= 24 {
            return Self.dateFormatter.string(from: date)
        }

        if hours >= 1 {
            return minutes > 0 ? "\(hours)h \(minutes)m" : "\(hours)h"
        } else {
            return "\(totalMinutes)m"
        }
    }
}
