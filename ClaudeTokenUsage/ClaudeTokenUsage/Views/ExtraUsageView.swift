import SwiftUI

struct ExtraUsageView: View {
    let usedCredits: Int
    let monthlyLimit: Int

    private var progress: Double {
        guard monthlyLimit > 0 else { return 0 }
        return Double(usedCredits) / Double(monthlyLimit)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Extra Usage")
                .font(.headline)
                .foregroundStyle(.secondary)

            ProgressView(value: progress) {
                HStack {
                    Text("$\(usedCredits) / $\(monthlyLimit)")
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

#Preview {
    ExtraUsageView(usedCredits: 1200, monthlyLimit: 5000)
        .frame(width: 280)
        .background(.black)
        .preferredColorScheme(.dark)
}
