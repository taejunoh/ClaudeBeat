import SwiftUI

struct UsageGaugeView: View {
    let title: String
    let utilization: Double
    let resetsAt: Date?
    let opusUtilization: Double?
    let sonnetUtilization: Double?

    private var percentage: Int { Int(utilization) }

    private var gaugeColor: Color {
        switch utilization {
        case 0..<50: return .green
        case 50..<80: return .yellow
        default: return .red
        }
    }

    var body: some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.secondary)

            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.3), lineWidth: 8)

                Circle()
                    .trim(from: 0, to: utilization / 100)
                    .stroke(gaugeColor, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.5), value: utilization)

                VStack(spacing: 2) {
                    Text("\(percentage)%")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                }
            }
            .frame(width: 80, height: 80)

            if let resetsAt {
                Text("Resets in \(TimeFormatting.popoverString(until: resetsAt))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let opus = opusUtilization, let sonnet = sonnetUtilization {
                HStack(spacing: 12) {
                    Label("Opus \(Int(opus))%", systemImage: "circle.fill")
                        .font(.caption2)
                        .foregroundStyle(.purple)
                    Label("Sonnet \(Int(sonnet))%", systemImage: "circle.fill")
                        .font(.caption2)
                        .foregroundStyle(.blue)
                }
            }
        }
        .padding()
    }
}
