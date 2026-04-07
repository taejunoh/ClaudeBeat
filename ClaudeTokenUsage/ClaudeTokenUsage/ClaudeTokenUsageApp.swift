import SwiftUI

@main
struct ClaudeTokenUsageApp: App {
    @State private var usageState = UsageState()
    @State private var authManager = AuthManager()
    @State private var notificationManager = NotificationManager()
    @State private var usageService: UsageService?

    @AppStorage("showResetTime") private var showResetTime = true
    @AppStorage("showSessionLabel") private var showSessionLabel = true
    @AppStorage("pollingInterval") private var pollingInterval: Double = 60

    var body: some Scene {
        MenuBarExtra {
            PopoverView(
                usageState: usageState,
                onRefresh: { Task { await usageService?.fetchUsage() } },
                onSettings: { openSettings() }
            )
        } label: {
            menuBarLabel
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(
                authManager: authManager,
                notificationManager: notificationManager
            )
        }
    }

    private var menuBarLabel: some View {
        HStack(spacing: 4) {
            Image(systemName: "circle.fill")
                .font(.system(size: 6))
                .foregroundStyle(usageState.statusColor)

            if showSessionLabel {
                Text("Session:")
            }

            Text(usageState.menuBarPercentage)

            if showResetTime {
                Text("·")
                Text(usageState.menuBarResetTime)
            }
        }
        .onAppear {
            setupServices()
        }
        .onChange(of: pollingInterval) { _, newValue in
            usageService?.pollingInterval = newValue
            usageService?.startPolling()
        }
    }

    private func setupServices() {
        authManager.loadOAuthTokenFromKeychain()
        notificationManager.requestPermission()

        let service = UsageService(
            authManager: authManager,
            usageState: usageState,
            notificationManager: notificationManager
        )
        service.pollingInterval = pollingInterval
        usageService = service

        Task {
            try? await authManager.fetchOrganizationId()
            service.startPolling()
        }
    }

    private func openSettings() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
