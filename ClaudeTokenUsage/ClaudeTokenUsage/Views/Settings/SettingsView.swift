import SwiftUI

struct SettingsView: View {
    let authManager: AuthManager
    let notificationManager: NotificationManager

    var body: some View {
        TabView {
            AuthSettingsView(authManager: authManager)
                .tabItem {
                    Label("Authentication", systemImage: "key")
                }

            DisplaySettingsView()
                .tabItem {
                    Label("Display", systemImage: "display")
                }

            AlertSettingsView(notificationManager: notificationManager)
                .tabItem {
                    Label("Alerts", systemImage: "bell")
                }

            GeneralSettingsView()
                .tabItem {
                    Label("General", systemImage: "gear")
                }
        }
        .frame(width: 450, height: 300)
    }
}
