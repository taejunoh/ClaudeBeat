import SwiftUI

struct WeeklyUsageView: View {
    let allModels: UsageBucket
    let sonnetOnly: UsageBucket?

    var body: some View {
        VStack(spacing: 4) {
            Text("Weekly (7d)")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 16) {
                weeklyItem(
                    label: "All models",
                    utilization: allModels.utilization,
                    resetsAt: allModels.resetsAt
                )

                if let sonnet = sonnetOnly {
                    Divider()
                        .frame(height: 60)

                    weeklyItem(
                        label: "Sonnet only",
                        utilization: sonnet.utilization,
                        resetsAt: sonnet.resetsAt
                    )
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private func weeklyItem(label: String, utilization: Double, resetsAt: Date?) -> some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.tertiary)

            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.3), lineWidth: 4)
                Circle()
                    .trim(from: 0, to: utilization / 100)
                    .stroke(gaugeColor(utilization), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.5), value: utilization)
                Text("\(Int(utilization))%")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
            }
            .frame(width: 36, height: 36)

            if let resetsAt {
                Text("Resets \(resetString(resetsAt))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
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

    private func resetString(_ date: Date) -> String {
        Self.resetFormatter.string(from: date)
    }
}
