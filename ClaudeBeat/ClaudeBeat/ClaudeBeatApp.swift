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

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    let usageState = UsageState()
    let authManager = AuthManager()
    let notificationManager = NotificationManager()
    var usageService: UsageService?

    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var refreshTimer: Timer?
    private var pollingObserver: NSObjectProtocol?
    private var onboardingWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private var loginWindowController: LoginWindowController?
    private var eventMonitor: Any?

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        // Render the menu bar text via the button's own title (supported API).
        // Custom NSView subviews added to statusItem.button no longer render on
        // macOS 26 (Tahoe)'s Liquid Glass menu bar, which is why the numbers
        // disappeared after the OS update. attributedTitle lets AppKit lay out
        // and color the text, adapting to light/dark and menu bar vibrancy.
        if let button = statusItem.button {
            button.imagePosition = .noImage
            (button.cell as? NSButtonCell)?.usesSingleLineMode = false
            button.action = #selector(togglePopover)
            button.target = self
        }
        updateMenuBarText()

        popover = NSPopover()
        popover.contentSize = NSSize(width: 300, height: 400)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: PopoverView(
                usageState: usageState,
                onRefresh: { [weak self] in
                    guard let self else { return }
                    Task { [weak self] in
                        await self?.usageService?.fetchUsage()
                        await MainActor.run { self?.updateMenuBarText() }
                    }
                },
                onSettings: { [weak self] in
                    self?.closePopover()
                    self?.openSettings()
                }
            )
        )

        refreshTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            // Fires on the main runloop, so we are already on the main actor.
            MainActor.assumeIsolated { self?.updateMenuBarText() }
        }

        // Watch for polling interval changes in UserDefaults
        pollingObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // Delivered on the .main queue, so assume main-actor isolation.
            MainActor.assumeIsolated {
                guard let self, let service = self.usageService else { return }
                let interval = UserDefaults.standard.double(forKey: "pollingInterval")
                let newInterval = interval > 0 ? interval : 60
                if service.pollingInterval != newInterval {
                    service.pollingInterval = newInterval
                    service.startPolling()
                }
            }
        }

        setupServices()
    }

    func applicationWillTerminate(_ notification: Notification) {
        refreshTimer?.invalidate()
        refreshTimer = nil
        usageService?.stopPolling()
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
        }
        eventMonitor = nil
        if let pollingObserver {
            NotificationCenter.default.removeObserver(pollingObserver)
        }
        pollingObserver = nil
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if usageState.needsLogin {
            openLogin()
            return
        }
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

    private func updateMenuBarText() {
        guard let button = statusItem.button else { return }

        if usageState.needsLogin {
            button.attributedTitle = singleLineTitle("Log in")
            return
        }

        let displayMode = UserDefaults.standard.string(forKey: "menuBarDisplay") ?? MenuBarDisplay.session.rawValue
        let showResetTime = UserDefaults.standard.object(forKey: "showResetTime") as? Bool ?? true
        let mode = MenuBarDisplay(rawValue: displayMode) ?? .session

        switch mode {
        case .session:
            var line = ["5h: \(usageState.menuBarPercentage)"]
            if showResetTime { line.append("· \(usageState.menuBarResetTime)") }
            button.attributedTitle = singleLineTitle(line.joined(separator: " "))

        case .weekly:
            var line = ["7d: \(usageState.weeklyPercentage)"]
            if showResetTime { line.append("· \(usageState.weeklyResetTime)") }
            button.attributedTitle = singleLineTitle(line.joined(separator: " "))

        case .both:
            var top = ["5h: \(usageState.menuBarPercentage)"]
            if showResetTime { top.append("· \(usageState.menuBarResetTime)") }
            var bottom = ["7d: \(usageState.weeklyPercentage)"]
            if showResetTime { bottom.append("· \(usageState.weeklyResetTime)") }
            button.attributedTitle = twoLineTitle(
                top.joined(separator: " "),
                bottom.joined(separator: " ")
            )
        }
    }

    private func singleLineTitle(_ string: String) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        return NSAttributedString(string: string, attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraph,
        ])
    }

    private func twoLineTitle(_ top: String, _ bottom: String) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.maximumLineHeight = 10
        paragraph.minimumLineHeight = 10
        return NSAttributedString(string: "\(top)\n\(bottom)", attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .medium),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraph,
        ])
    }

    private func setupServices() {
        notificationManager.requestPermission()

        let service = UsageService(
            transport: WebSession.shared,
            usageState: usageState,
            notificationManager: notificationManager
        )
        let interval = UserDefaults.standard.double(forKey: "pollingInterval")
        service.pollingInterval = interval > 0 ? interval : 60
        usageService = service

        Task { [weak self] in
            guard let self else { return }
            // Re-inject a previously pasted sessionKey (if any) before probing.
            if !self.authManager.sessionCookie.isEmpty {
                await WebSession.shared.injectSessionCookie(self.authManager.sessionCookie)
            }
            if await WebSession.shared.probeLoggedIn() {
                await self.usageService?.fetchUsage()
                await MainActor.run { self.updateMenuBarText() }
                self.usageService?.startPolling()
            } else {
                await MainActor.run { self.openOnboarding() }
            }
        }
    }

    /// Shared post-login sequence: dismiss onboarding (if open), refresh, and start polling.
    private func handleLoginSuccess() async {
        onboardingWindow?.close()
        onboardingWindow = nil
        await usageService?.fetchUsage()
        updateMenuBarText()
        usageService?.startPolling()
    }

    func openLogin() {
        let controller = loginWindowController ?? LoginWindowController(onLoggedIn: { [weak self] in
            // Close onboarding (if open) — nil-safe when openLogin was triggered from the menu bar directly.
            Task { @MainActor [weak self] in await self?.handleLoginSuccess() }
        })
        loginWindowController = controller
        controller.show()
    }

    private func openOnboarding() {
        let onboardingView = OnboardingView(
            authManager: authManager,
            onLogin: { [weak self] in self?.openLogin() },
            onPaste: { [weak self] key in
                guard let self else { return false }
                await WebSession.shared.injectSessionCookie(key)
                let ok = await WebSession.shared.probeLoggedIn()
                if ok { await self.handleLoginSuccess() }
                return ok
            }
        )

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 400),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "ClaudeBeat — Setup"
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
        window.title = "ClaudeBeat — Settings"
        window.contentView = NSHostingView(rootView: settingsView)
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow = window
    }
}
