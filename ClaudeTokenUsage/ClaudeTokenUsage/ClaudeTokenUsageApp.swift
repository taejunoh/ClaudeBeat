import SwiftUI

@main
struct ClaudeTokenUsageApp: App {
    @State private var usageState = UsageState()
    @State private var authManager = AuthManager()
    @State private var notificationManager = NotificationManager()
    @State private var usageService: UsageService?
    @State private var showOnboarding = false

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

        Window("Setup", id: "onboarding") {
            OnboardingView(authManager: authManager) {
                showOnboarding = false
                startPolling()
            }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultPosition(.center)
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

        if authManager.isConfigured {
            Task {
                try? await authManager.fetchOrganizationId()
                service.startPolling()
            }
        } else {
            showOnboarding = true
            openOnboarding()
        }
    }

    private func startPolling() {
        guard let usageService else { return }
        Task {
            try? await authManager.fetchOrganizationId()
            usageService.startPolling()
        }
    }

    private func openOnboarding() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { $0.identifier?.rawValue.contains("onboarding") == true }) {
            window.makeKeyAndOrderFront(nil)
        }
    }

    private func openSettings() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
