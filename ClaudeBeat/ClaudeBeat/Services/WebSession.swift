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

    private let webView: WKWebView
    private var readyContinuations: [CheckedContinuation<Void, Never>] = []
    private var didFinishFirstLoad = false

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

    /// Suspends until the WebView has finished its first navigation (challenge resolved).
    private func waitUntilReady() async {
        if didFinishFirstLoad { return }
        await withCheckedContinuation { continuation in
            readyContinuations.append(continuation)
        }
    }

    // MARK: UsageTransport

    func fetchJSON(path: String) async throws -> Data {
        await waitUntilReady()

        let js = """
        const r = await fetch(path, { headers: { Accept: 'application/json' }, credentials: 'include' });
        const body = await r.text();
        return { status: r.status, url: r.url, body: body };
        """

        let raw: Any?
        do {
            raw = try await webView.callAsyncJavaScript(
                js, arguments: ["path": path], in: nil, contentWorld: .page
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
        let cookie = HTTPCookie(properties: [
            .domain: ".claude.ai",
            .path: "/",
            .name: "sessionKey",
            .value: value,
            .secure: true,
        ])
        guard let cookie else { return }
        await WebSession.dataStore.httpCookieStore.setCookie(cookie)
        // Reload so the new cookie is used by subsequent in-page fetches.
        webView.load(URLRequest(url: WebSession.baseURL))
        didFinishFirstLoad = false
    }

    /// Clears all website data (cookies/cf_clearance) — used by Log out.
    func clearData() async {
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        await WebSession.dataStore.removeData(ofTypes: types, modifiedSince: .distantPast)
        webView.load(URLRequest(url: WebSession.baseURL))
        didFinishFirstLoad = false
    }
}

extension WebSession: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        didFinishFirstLoad = true
        let continuations = readyContinuations
        readyContinuations.removeAll()
        for continuation in continuations { continuation.resume() }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        // Treat a hard navigation failure as "ready" so callers don't hang; the fetch will
        // then surface the real error.
        didFinishFirstLoad = true
        let continuations = readyContinuations
        readyContinuations.removeAll()
        for continuation in continuations { continuation.resume() }
    }
}
