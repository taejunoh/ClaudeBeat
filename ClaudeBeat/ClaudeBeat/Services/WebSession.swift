import Foundation
import WebKit

/// A hidden WKWebView that issues same-origin requests to claude.ai. Because it is a real
/// WebKit engine it passes Cloudflare's managed challenge and naturally carries cf_clearance
/// and session cookies. A single persistent data store is shared with the login window so a
/// login there is visible here and survives relaunches.
@MainActor
final class WebSession: NSObject, UsageTransport {

    static let baseURL = URL(string: "https://claude.ai")!

    /// Shared persistent store: cookies/cf_clearance survive app relaunch and are shared
    /// with LoginWebView.
    static let dataStore: WKWebsiteDataStore = .default()

    /// The app's single hidden web session, also used by the login window's probe.
    @MainActor static let shared = WebSession()

    /// Holds one pending readiness continuation and guarantees it resumes exactly once.
    private final class ReadyBox {
        private var continuation: CheckedContinuation<Bool, Never>?
        init(_ continuation: CheckedContinuation<Bool, Never>) { self.continuation = continuation }
        func resume(_ value: Bool) {
            continuation?.resume(returning: value)
            continuation = nil
        }
    }

    private let webView: WKWebView
    private var readyBoxes: [ReadyBox] = []
    private var didFinishFirstLoad = false

    /// Max wait for the WebView to finish loading before the attempt is treated as a transient
    /// challenge (the poll loop retries next cycle) rather than hanging forever.
    private let readyTimeout: Duration = .seconds(20)
    /// Max time for a single in-page fetch.
    private let fetchTimeoutMillis = 15000

    override init() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = WebSession.dataStore
        webView = WKWebView(frame: .zero, configuration: config)
        super.init()
        webView.navigationDelegate = self
        // A desktop Safari-like UA reduces friction with Cloudflare's UA heuristics.
        webView.customUserAgent =
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 " +
            "(KHTML, like Gecko) Version/17.0 Safari/605.1.15"
        webView.load(URLRequest(url: WebSession.baseURL))
    }

    /// Suspends until the WebView finishes its first navigation, or `readyTimeout` elapses.
    /// Returns true if ready, false on timeout — callers must not block indefinitely.
    private func waitUntilReady() async -> Bool {
        if didFinishFirstLoad { return true }
        let timeout = readyTimeout
        return await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            let box = ReadyBox(continuation)
            readyBoxes.append(box)
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: timeout)
                guard let self else { return }
                if let index = self.readyBoxes.firstIndex(where: { $0 === box }) {
                    self.readyBoxes.remove(at: index)
                    box.resume(false)
                }
            }
        }
    }

    /// Marks the session ready and resumes every queued continuation exactly once.
    private func markReady() {
        didFinishFirstLoad = true
        let boxes = readyBoxes
        readyBoxes.removeAll()
        for box in boxes { box.resume(true) }
    }

    // MARK: UsageTransport

    func fetchJSON(path: String) async throws -> Data {
        guard await waitUntilReady() else { throw TransportError.challenge }

        let js = """
        const ctrl = new AbortController();
        const t = setTimeout(() => ctrl.abort(), timeoutMillis);
        try {
            const r = await fetch(path, { headers: { Accept: 'application/json' }, credentials: 'include', signal: ctrl.signal });
            const body = await r.text();
            return { status: r.status, url: r.url, body: body };
        } finally {
            clearTimeout(t);
        }
        """

        let raw: Any?
        do {
            raw = try await webView.callAsyncJavaScript(
                js,
                arguments: ["path": path, "timeoutMillis": fetchTimeoutMillis],
                in: nil,
                contentWorld: .page
            )
        } catch {
            throw TransportError.webView(error.localizedDescription)
        }

        guard let dict = raw as? [String: Any],
              let status = dict["status"] as? Int,
              let body = dict["body"] as? String else {
            throw TransportError.webView("Malformed JS result")
        }

        let finalPath = URLComponents(string: dict["url"] as? String ?? "")?.path ?? ""
        switch TransportClassifier.classify(status: status, finalPath: finalPath, cfMitigated: false) {
        case .ok:
            guard let data = body.data(using: .utf8), !data.isEmpty else { throw TransportError.decode }
            return data
        case .needsLogin:
            throw TransportError.needsLogin
        case .challenge:
            throw TransportError.challenge
        case .networkError(let code):
            throw TransportError.network(code)
        }
    }

    // MARK: Login support

    /// True if claude.ai currently answers /api/organizations with 200 (i.e. logged in).
    func probeLoggedIn() async -> Bool {
        do { _ = try await fetchJSON(path: "/api/organizations"); return true }
        catch { return false }
    }

    /// Injects a pasted sessionKey cookie into the shared store (Google-SSO fallback path).
    func injectSessionCookie(_ value: String) async {
        // httpOnly is intentionally omitted: the cookie just needs to be attached by the engine
        // to outgoing fetch() requests; the hidden WebView only ever loads claude.ai itself.
        let cookie = HTTPCookie(properties: [
            .domain: ".claude.ai",
            .path: "/",
            .name: "sessionKey",
            .value: value,
            .secure: true,
        ])
        guard let cookie else { return }
        await WebSession.dataStore.httpCookieStore.setCookie(cookie)
        // Reset readiness BEFORE reloading so a pending wait re-arms against the new navigation.
        didFinishFirstLoad = false
        webView.load(URLRequest(url: WebSession.baseURL))
    }

    /// Clears all website data (cookies/cf_clearance) — used by Log out.
    func clearData() async {
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        await WebSession.dataStore.removeData(ofTypes: types, modifiedSince: .distantPast)
        didFinishFirstLoad = false
        webView.load(URLRequest(url: WebSession.baseURL))
    }
}

extension WebSession: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        markReady()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        // A hard failure after the response still unblocks callers; the fetch then surfaces the real error.
        markReady()
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        // Pre-response failures (DNS, refused connection, timeout) must also unblock callers.
        markReady()
    }
}
