import SwiftUI

struct UsageGaugeView: View {
    let title: String
    let utilization: Double
    let resetsAt: Date?

    private var percentage: Int { Int(utilization) }

    private var gaugeColor: Color {
        switch utilization {
        case 0..<50: return .green
        case 50..<80: return .yellow
        default: return .red
        }
    }

    var body: some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.3), lineWidth: 5)

                Circle()
                    .trim(from: 0, to: utilization / 100)
                    .stroke(gaugeColor, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.5), value: utilization)

                Text("\(percentage)%")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
            }
            .frame(width: 48, height: 48)

            if let resetsAt {
                Text("Resets in \(TimeFormatting.popoverString(until: resetsAt))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
}
