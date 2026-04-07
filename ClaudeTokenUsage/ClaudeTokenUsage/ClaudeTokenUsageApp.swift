import AppKit
import SwiftUI

@main
struct ClaudeTokenUsageApp: App {
    @State private var usageState = UsageState()
    @State private var authManager = AuthManager()
    @State private var notificationManager = NotificationManager()
    @State private var usageService: UsageService?
    @State private var showOnboarding = false
    @State private var onboardingWindow: NSWindow?
    @State private var menuBarText = "Session: --% · --"
    @State private var refreshTimer: Timer?

    @AppStorage("showResetTime") private var showResetTime = true
    @AppStorage("showSessionLabel") private var showSessionLabel = true
    @AppStorage("pollingInterval") private var pollingInterval: Double = 60

    var body: some Scene {
        MenuBarExtra {
            PopoverView(
                usageState: usageState,
                onRefresh: {
                    Task {
                        await usageService?.fetchUsage()
                        updateMenuBarText()
                    }
                },
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
        Text(menuBarText)
        .onAppear {
            setupServices()
            startMenuBarRefresh()
        }
        .onChange(of: pollingInterval) { _, newValue in
            usageService?.pollingInterval = newValue
            usageService?.startPolling()
        }
    }

    private func startMenuBarRefresh() {
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
            Task { @MainActor in
                updateMenuBarText()
            }
        }
    }

    private func updateMenuBarText() {
        var parts: [String] = []
        if showSessionLabel {
            parts.append("Session:")
        }
        parts.append(usageState.menuBarPercentage)
        if showResetTime {
            parts.append("·")
            parts.append(usageState.menuBarResetTime)
        }
        menuBarText = parts.joined(separator: " ")
    }

    private func setupServices() {
        authManager.loadOAuthTokenFromKeychain()
        notificationManager.requestPermission()

        NSLog("[App] setupServices: isConfigured=\(authManager.isConfigured) cookie=\(authManager.sessionCookie.prefix(10))... orgId=\(authManager.organizationId)")

        let service = UsageService(
            authManager: authManager,
            usageState: usageState,
            notificationManager: notificationManager
        )
        service.pollingInterval = pollingInterval
        usageService = service

        if authManager.isConfigured {
            NSLog("[App] Auth configured, starting polling...")
            Task {
                try? await authManager.fetchOrganizationId()
                NSLog("[App] OrgId after fetch: \(authManager.organizationId)")
                service.startPolling()
            }
        } else {
            showOnboarding = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                openOnboarding()
            }
        }
    }

    private func startPolling() {
        guard let usageService else { return }
        Task {
            if authManager.organizationId.isEmpty {
                try? await authManager.fetchOrganizationId()
            }
            await usageService.fetchUsage()
            usageService.startPolling()
        }
    }

    private func openOnboarding() {
        let onboardingView = OnboardingView(authManager: authManager) { [self] in
            startPolling()
            onboardingWindow?.close()
            onboardingWindow = nil
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 400),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Claude Token Usage — Setup"
        window.contentView = NSHostingView(rootView: onboardingView)
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        onboardingWindow = window
    }

    private func openSettings() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
