import SwiftUI

struct ExtraUsageView: View {
    let usedCredits: Int
    let monthlyLimit: Int

    private var progress: Double {
        guard monthlyLimit > 0 else { return 0 }
        return min(Double(usedCredits) / Double(monthlyLimit), 1.0)
    }

    private var usedDollars: String {
        String(format: "%.2f", Double(usedCredits) / 100.0)
    }

    private var limitDollars: String {
        String(format: "%.2f", Double(monthlyLimit) / 100.0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Extra Usage")
                .font(.headline)
                .foregroundStyle(.secondary)

            ProgressView(value: progress) {
                HStack {
                    Text("$\(usedDollars) / $\(limitDollars)")
                        .font(.caption)
                        .foregroundStyle(.primary)
                    Spacer()
                    Text("\(Int(progress * 100))%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .tint(progress < 0.8 ? .blue : .red)
        }
        .padding()
    }
}
