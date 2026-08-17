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
        var scopedCandidates: [(label: String, percent: Double, resetsAt: Date?)] = []

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
                scopedCandidates.append((label: label, percent: limit.percent, resetsAt: limit.resetsAt))
            default:
                continue
            }
        }

        // Server array order is not contractual; sort so gauges don't swap places between
        // refreshes. When two entries share a label (before `scope.surface` is decoded),
        // break ties on percent to ensure a deterministic order independent of input.
        scopedCandidates.sort {
            let labelOrder = $0.label.localizedStandardCompare($1.label)
            if labelOrder == .orderedSame {
                return $0.percent < $1.percent
            }
            return labelOrder == .orderedAscending
        }

        // `scope.surface` isn't decoded yet, so two distinct surfaces for the same model
        // (e.g. "Fable" on Claude Code and on web) currently arrive with the same label.
        // Fold the post-sort position into the id so those entries don't collide — the
        // position is stable across refreshes as long as the server's set of labels is.
        let scoped = scopedCandidates.enumerated().map { index, candidate in
            WeeklyItem(
                id: "weekly_scoped:\(index):\(candidate.label)",
                label: candidate.label,
                utilization: candidate.percent,
                resetsAt: candidate.resetsAt
            )
        }

        let items = [allModels].compactMap { $0 } + scoped
        guard items.isEmpty else { return items }

        return [WeeklyItem(
            id: "seven_day",
            label: allModelsLabel,
            utilization: response.sevenDay.utilization,
            resetsAt: response.sevenDay.resetsAt
        )]
    }

    /// The weekly limit that binds — the highest one. A per-model limit routinely sits far
    /// above the all-models total (Fable at 86% against 48%), and it is the one that will
    /// actually stop work, so it is what the menu bar shows and what alerts watch.
    ///
    /// Ties keep the earlier item, which puts "All models" ahead of any model. `max(by:)`
    /// does not specify which of several equal elements it returns, so it is not used here.
    static func bindingItem(in items: [WeeklyItem]) -> WeeklyItem? {
        items.reduce(into: nil as WeeklyItem?) { binding, candidate in
            guard let incumbent = binding else {
                binding = candidate
                return
            }
            if candidate.utilization > incumbent.utilization {
                binding = candidate
            }
        }
    }

    /// The one reset time to show for the whole section, or nil when the items disagree
    /// and each must show its own.
    ///
    /// Compared with a minute of tolerance: observed responses differ by microseconds
    /// (…983485 vs …983652) for what is plainly the same reset, so exact equality would
    /// never find a shared time.
    ///
    /// Agreement is judged by the spread of the whole set (max − min), not by each date's
    /// distance from an arbitrary pivot — pairwise-to-one-element comparisons aren't
    /// transitive, so that approach could call a set "shared" even when its extremes were
    /// more than a minute apart.
    static func sharedResetDate(for items: [WeeklyItem]) -> Date? {
        let dates = items.compactMap(\.resetsAt)
        guard dates.count == items.count, let first = dates.first else { return nil }
        guard let min = dates.min(), let max = dates.max() else { return nil }
        guard max.timeIntervalSince(min) < 60 else { return nil }
        return first
    }
}
