import AppKit
import SwiftUI

struct TopBarView: View {
    let lastUpdated: Date?
    let onRefresh: () -> Void

    var body: some View {
        HStack {
            Spacer()

            TimelineView(.periodic(from: .now, by: 5)) { _ in
                Text("Updated \(lastUpdatedText)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Button(action: onRefresh) {
                Image(systemName: "arrow.clockwise")
                    .font(.caption2)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal)
        .padding(.vertical, 4)
    }

    private var lastUpdatedText: String {
        guard let lastUpdated else { return "Never" }
        let seconds = Int(-lastUpdated.timeIntervalSinceNow)
        if seconds < 60 { return "\(seconds)s ago" }
        return "\(seconds / 60)m ago"
    }
}

struct BottomBarView: View {
    let onSettings: () -> Void

    var body: some View {
        HStack {
            Button(action: onSettings) {
                Image(systemName: "gear")
            }
            .buttonStyle(.plain)

            Spacer()

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Image(systemName: "power")
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
    }
}
