import SwiftUI

struct StatusBarView: View {
    let lastUpdated: Date?
    let onRefresh: () -> Void
    let onSettings: () -> Void

    private var lastUpdatedText: String {
        guard let lastUpdated else { return "Never" }
        let seconds = Int(-lastUpdated.timeIntervalSinceNow)
        if seconds < 60 { return "\(seconds)s ago" }
        return "\(seconds / 60)m ago"
    }

    var body: some View {
        HStack {
            Button(action: onSettings) {
                Image(systemName: "gear")
            }
            .buttonStyle(.plain)

            Spacer()

            Text("Updated \(lastUpdatedText)")
                .font(.caption2)
                .foregroundStyle(.tertiary)

            Button(action: onRefresh) {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
    }
}
