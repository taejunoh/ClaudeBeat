import SwiftUI

enum SettingsTab: String, CaseIterable {
    case auth = "Auth"
    case display = "Display"
    case alerts = "Alerts"
    case general = "General"

    var icon: String {
        switch self {
        case .auth: return "key"
        case .display: return "display"
        case .alerts: return "bell"
        case .general: return "gear"
        }
    }
}

struct SettingsView: View {
    let authManager: AuthManager
    let notificationManager: NotificationManager

    @State private var selectedTab: SettingsTab = .auth

    var body: some View {
        HSplitView {
            // Left sidebar
            VStack(alignment: .leading, spacing: 2) {
                ForEach(SettingsTab.allCases, id: \.self) { tab in
                    Button {
                        selectedTab = tab
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: tab.icon)
                                .frame(width: 16)
                            Text(tab.rawValue)
                            Spacer()
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(selectedTab == tab ? Color.accentColor.opacity(0.2) : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            .padding(10)
            .frame(width: 130)

            // Right content
            Group {
                switch selectedTab {
                case .auth:
                    AuthSettingsView(authManager: authManager)
                case .display:
                    DisplaySettingsView()
                case .alerts:
                    AlertSettingsView(notificationManager: notificationManager)
                case .general:
                    GeneralSettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(width: 520, height: 380)
    }
}
