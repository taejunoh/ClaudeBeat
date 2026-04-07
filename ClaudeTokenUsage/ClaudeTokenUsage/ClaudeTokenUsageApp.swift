import AppKit
import SwiftUI

@main
struct ClaudeTokenUsageApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            SettingsView(
                authManager: appDelegate.authManager,
                notificationManager: appDelegate.notificationManager
            )
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    let usageState = UsageState()
    let authManager = AuthManager()
    let notificationManager = NotificationManager()
    var usageService: UsageService?

    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var refreshTimer: Timer?
    private var onboardingWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private var eventMonitor: Any?

    private var topLabel: NSTextField!
    private var bottomLabel: NSTextField!

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Create status item with custom two-line view
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 80, height: 22))

        topLabel = makeLabel(fontSize: 10, alignment: .center)
        topLabel.stringValue = "Session:"
        topLabel.frame = NSRect(x: 0, y: 10, width: 80, height: 12)

        bottomLabel = makeLabel(fontSize: 10, alignment: .center)
        bottomLabel.stringValue = "--% · --"
        bottomLabel.frame = NSRect(x: 0, y: -1, width: 80, height: 12)

        container.addSubview(topLabel)
        container.addSubview(bottomLabel)

        statusItem.button?.addSubview(container)
        statusItem.button?.frame = container.frame
        statusItem.length = 80
        statusItem.button?.action = #selector(togglePopover)
        statusItem.button?.target = self

        // Create popover
        popover = NSPopover()
        popover.contentSize = NSSize(width: 300, height: 400)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: PopoverView(
                usageState: usageState,
                onRefresh: { [weak self] in
                    guard let self else { return }
                    Task {
                        await self.usageService?.fetchUsage()
                        await MainActor.run { self.updateMenuBarText() }
                    }
                },
                onSettings: { [weak self] in
                    self?.closePopover()
                    self?.openSettings()
                }
            )
        )

        // Start refresh timer
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            self?.updateMenuBarText()
        }

        // Setup services
        setupServices()
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            closePopover()
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
            eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                self?.closePopover()
            }
        }
    }

    private func closePopover() {
        popover.close()
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
        }
        eventMonitor = nil
    }

    private func makeLabel(fontSize: CGFloat, alignment: NSTextAlignment) -> NSTextField {
        let label = NSTextField(labelWithString: "")
        label.font = NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .medium)
        label.alignment = alignment
        label.textColor = .headerTextColor
        label.backgroundColor = .clear
        label.isBezeled = false
        label.isEditable = false
        return label
    }

    private func updateMenuBarText() {
        let displayMode = UserDefaults.standard.string(forKey: "menuBarDisplay") ?? MenuBarDisplay.session.rawValue
        let showResetTime = UserDefaults.standard.bool(forKey: "showResetTime") || !UserDefaults.standard.dictionaryRepresentation().keys.contains("showResetTime")

        let mode = MenuBarDisplay(rawValue: displayMode) ?? .session

        switch mode {
        case .session:
            // Single line: 5h: 56% · 4h 11m
            topLabel?.stringValue = ""
            topLabel?.font = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .medium)
            var line = ["5h: \(usageState.menuBarPercentage)"]
            if showResetTime { line.append("· \(usageState.menuBarResetTime)") }
            bottomLabel?.stringValue = line.joined(separator: " ")
            bottomLabel?.font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium)
            bottomLabel?.alignment = .center
            bottomLabel?.frame = NSRect(x: 0, y: 2, width: statusItem.length, height: 18)
            topLabel?.frame = NSRect(x: 0, y: 22, width: 0, height: 0)

        case .weekly:
            // Single line: 7d: 7% · Apr 14
            topLabel?.stringValue = ""
            topLabel?.font = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .medium)
            var line = ["7d: \(usageState.weeklyPercentage)"]
            if showResetTime { line.append("· \(usageState.weeklyResetTime)") }
            bottomLabel?.stringValue = line.joined(separator: " ")
            bottomLabel?.font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium)
            bottomLabel?.alignment = .center
            bottomLabel?.frame = NSRect(x: 0, y: 2, width: statusItem.length, height: 18)
            topLabel?.frame = NSRect(x: 0, y: 22, width: 0, height: 0)

        case .both:
            // Two lines — restore smaller font
            topLabel?.font = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .medium)
            bottomLabel?.font = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .medium)
            topLabel?.frame.origin.y = 10
            bottomLabel?.frame.origin.y = -1

            var top = ["5h: \(usageState.menuBarPercentage)"]
            if showResetTime { top.append("· \(usageState.menuBarResetTime)") }
            topLabel?.stringValue = top.joined(separator: " ")

            var bottom = ["7d: \(usageState.weeklyPercentage)"]
            if showResetTime { bottom.append("· \(usageState.weeklyResetTime)") }
            bottomLabel?.stringValue = bottom.joined(separator: " ")
        }

        // Auto-size width
        let topWidth = topLabel?.attributedStringValue.size().width ?? 0
        let bottomWidth = bottomLabel?.attributedStringValue.size().width ?? 0
        let width = max(topWidth, bottomWidth) + 14
        statusItem.length = max(width, 50)
        let len = statusItem.length
        topLabel?.frame.size.width = len
        bottomLabel?.frame.size.width = len
        statusItem.button?.subviews.first?.frame = NSRect(x: 0, y: 0, width: len, height: 22)
    }

    private func setupServices() {
        authManager.loadOAuthTokenFromKeychain()
        notificationManager.requestPermission()

        let service = UsageService(
            authManager: authManager,
            usageState: usageState,
            notificationManager: notificationManager
        )
        let interval = UserDefaults.standard.double(forKey: "pollingInterval")
        service.pollingInterval = interval > 0 ? interval : 60
        usageService = service

        if authManager.isConfigured {
            Task {
                try? await authManager.fetchOrganizationId()
                await service.fetchUsage()
                await MainActor.run { updateMenuBarText() }
                service.startPolling()
            }
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.openOnboarding()
            }
        }
    }

    private func openOnboarding() {
        let onboardingView = OnboardingView(authManager: authManager) { [weak self] in
            guard let self else { return }
            self.onboardingWindow?.close()
            self.onboardingWindow = nil
            Task {
                if self.authManager.organizationId.isEmpty {
                    try? await self.authManager.fetchOrganizationId()
                }
                await self.usageService?.fetchUsage()
                await MainActor.run { self.updateMenuBarText() }
                self.usageService?.startPolling()
            }
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
        if let existing = settingsWindow, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let settingsView = SettingsView(
            authManager: authManager,
            notificationManager: notificationManager
        )

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 450, height: 300),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Claude Token Usage — Settings"
        window.contentView = NSHostingView(rootView: settingsView)
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow = window
    }
}
