import AppKit
import WebKit

/// A visible window that loads claude.ai's login page in a WKWebView sharing WebSession's
/// persistent store. When the user becomes logged in, `onLoggedIn` fires once and the window closes.
@MainActor
final class LoginWindowController: NSObject, NSWindowDelegate {

    private var window: NSWindow?
    private var webView: WKWebView?
    private let onLoggedIn: () -> Void
    private var probeTask: Task<Void, Never>?
    /// Once-flag: ensures `onLoggedIn` fires at most once and suppresses any in-flight probe
    /// completion after the window has closed.
    private var loginDidSucceed = false

    init(onLoggedIn: @escaping () -> Void) {
        self.onLoggedIn = onLoggedIn
        super.init()
    }

    func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        // Fresh login session: clear the once-flag that windowWillClose latched on a prior close.
        loginDidSucceed = false

        let config = WKWebViewConfiguration()
        config.websiteDataStore = WebSession.dataStore   // shared store
        let webView = WKWebView(
            frame: NSRect(x: 0, y: 0, width: 460, height: 640),
            configuration: config
        )
        webView.navigationDelegate = self
        webView.load(URLRequest(url: URL(string: "https://claude.ai/login")!))
        self.webView = webView

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 640),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Log in to Claude"
        window.contentView = webView
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
    }

    func windowWillClose(_ notification: Notification) {
        // Suppress any in-flight probe completion: a manual close cancels the flow.
        loginDidSucceed = true
        probeTask?.cancel()
        probeTask = nil
        window = nil
        webView = nil
    }

    private func close() {
        window?.close()
    }
}

extension LoginWindowController: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // After each navigation, probe whether the user is now logged in.
        probeTask?.cancel()
        probeTask = Task { @MainActor [weak self] in
            guard let self else { return }
            if await WebSession.shared.probeLoggedIn() {
                guard !self.loginDidSucceed else { return }
                self.loginDidSucceed = true
                self.onLoggedIn()
                self.close()
            }
        }
    }
}
