import SwiftUI

struct WeeklyUsageView: View {
    let items: [WeeklyItem]

    /// Three gauges is what fits across a 280pt popover; more wrap to another row.
    private static let itemsPerRow = 3

    private var rows: [[WeeklyItem]] {
        stride(from: 0, to: items.count, by: Self.itemsPerRow).map { start in
            Array(items[start..<min(start + Self.itemsPerRow, items.count)])
        }
    }

    private var sharedReset: Date? {
        WeeklyBreakdown.sharedResetDate(for: items)
    }

    var body: some View {
        VStack(spacing: 6) {
            Text("Weekly (7d)")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(alignment: .top, spacing: 8) {
                    ForEach(row) { item in
                        gauge(item, showsOwnReset: sharedReset == nil)
                    }
                }
            }

            // "Resets Thu 5:59 AM" needs ~90pt and a three-up column is ~82pt, so the
            // reset time lives under the section whenever the items agree on it.
            if let sharedReset {
                Text("Resets \(Self.resetFormatter.string(from: sharedReset))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private func gauge(_ item: WeeklyItem, showsOwnReset: Bool) -> some View {
        VStack(spacing: 4) {
            Text(item.label)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.tail)

            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.3), lineWidth: 4)
                Circle()
                    .trim(from: 0, to: item.utilization / 100)
                    .stroke(gaugeColor(item.utilization), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.5), value: item.utilization)
                Text("\(Int(item.utilization))%")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
            }
            .frame(width: 36, height: 36)

            if showsOwnReset, let resetsAt = item.resetsAt {
                Text(Self.resetFormatter.string(from: resetsAt))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func gaugeColor(_ utilization: Double) -> Color {
        switch utilization {
        case 0..<50: return .green
        case 50..<80: return .yellow
        default: return .red
        }
    }

    private static let resetFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE h:mm a"
        return f
    }()
}
