import Foundation

/// Typed failures surfaced by a `UsageTransport`.
enum TransportError: Error, Equatable {
    case challenge          // Cloudflare challenge not passed yet — transient, retry
    case needsLogin         // 401 or redirected to a login page
    case network(Int)       // other non-200 HTTP status
    case decode             // body present but unparseable
    case webView(String)    // WKWebView navigation / JS failure
}

/// Performs an authenticated, same-origin GET against claude.ai and returns the raw JSON body.
/// `path` is an absolute path such as "/api/organizations/{id}/usage".
protocol UsageTransport: Sendable {
    func fetchJSON(path: String) async throws -> Data
}

/// Output of `TransportClassifier.classify`; the transport layer maps these to `TransportError` cases.
enum LoginState: Equatable {
    case ok
    case needsLogin
    case challenge
    case networkError(Int)
}

/// Pure mapping from an HTTP outcome to a `LoginState`. Testable without a network.
enum TransportClassifier {
    static func classify(status: Int, finalPath: String, cfMitigated: Bool) -> LoginState {
        // On claude.ai, a 403 is reliably a Cloudflare challenge (the API uses 401, not 403,
        // for auth failures), so treat any 403 as a transient challenge to retry.
        if cfMitigated || status == 403 { return .challenge }
        if status == 401 { return .needsLogin }
        if finalPath.hasPrefix("/login") || finalPath.hasPrefix("/auth") { return .needsLogin }
        if status == 200 { return .ok }
        return .networkError(status)
    }
}
