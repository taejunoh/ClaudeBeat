import Foundation

/// One gauge in the popover's Weekly (7d) section.
struct WeeklyItem: Identifiable, Equatable, Sendable {
    let id: String
    let label: String
    let utilization: Double
    let resetsAt: Date?
}

enum WeeklyBreakdown {
    static let allModelsLabel = "All models"

    /// Builds the Weekly section's gauges from a usage response.
    ///
    /// Prefers `limits`, which is where per-model utilization lives now. When it carries
    /// no weekly entries — this endpoint has emptied fields without notice before — falls
    /// back to the flat `seven_day` bucket, which is exactly what the popover showed
    /// before `limits` existed.
    static func items(from response: UsageResponse) -> [WeeklyItem] {
        var allModels: WeeklyItem?
        var scoped: [WeeklyItem] = []

        for limit in response.limits {
            switch limit.kind {
            case "weekly_all":
                allModels = WeeklyItem(
                    id: "weekly_all",
                    label: allModelsLabel,
                    utilization: limit.percent,
                    resetsAt: limit.resetsAt
                )
            case "weekly_scoped":
                // An unlabeled gauge is noise — the server owns the label.
                guard let label = limit.scope?.model?.displayName, !label.isEmpty else { continue }
                scoped.append(WeeklyItem(
                    id: "weekly_scoped:\(label)",
                    label: label,
                    utilization: limit.percent,
                    resetsAt: limit.resetsAt
                ))
            default:
                continue
            }
        }

        // Server array order is not contractual; sort so gauges don't swap places between
        // refreshes.
        scoped.sort { $0.label.localizedStandardCompare($1.label) == .orderedAscending }

        let items = [allModels].compactMap { $0 } + scoped
        guard items.isEmpty else { return items }

        return [WeeklyItem(
            id: "seven_day",
            label: allModelsLabel,
            utilization: response.sevenDay.utilization,
            resetsAt: response.sevenDay.resetsAt
        )]
    }

    /// The one reset time to show for the whole section, or nil when the items disagree
    /// and each must show its own.
    ///
    /// Compared with a minute of tolerance: observed responses differ by microseconds
    /// (…983485 vs …983652) for what is plainly the same reset, so exact equality would
    /// never find a shared time.
    static func sharedResetDate(for items: [WeeklyItem]) -> Date? {
        let dates = items.compactMap(\.resetsAt)
        guard dates.count == items.count, let first = dates.first else { return nil }
        guard dates.allSatisfy({ abs($0.timeIntervalSince(first)) < 60 }) else { return nil }
        return first
    }
}
