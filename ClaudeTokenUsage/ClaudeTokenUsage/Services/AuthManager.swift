import Foundation
import Security

enum AuthMethod: String, CaseIterable, Sendable {
    case oauth = "OAuth (Claude Code)"
    case sessionCookie = "Session Cookie"
}

@Observable
final class AuthManager {
    private static let defaults = UserDefaults(suiteName: "com.claudetokenusage.app") ?? .standard

    var authMethod: AuthMethod {
        didSet { Self.defaults.set(authMethod.rawValue, forKey: "authMethod") }
    }
    var sessionCookie: String {
        didSet { Self.defaults.set(sessionCookie, forKey: "sessionCookie") }
    }
    var oauthToken: String = ""
    var organizationId: String {
        didSet { Self.defaults.set(organizationId, forKey: "organizationId") }
    }
    var connectionStatus: ConnectionStatus = .unknown

    enum ConnectionStatus: Equatable {
        case unknown, connected, error(String)
    }

    init() {
        let d = Self.defaults
        let saved = d.string(forKey: "authMethod") ?? ""
        self.authMethod = AuthMethod(rawValue: saved) ?? .oauth
        self.sessionCookie = d.string(forKey: "sessionCookie") ?? ""
        self.organizationId = d.string(forKey: "organizationId") ?? ""
    }

    var isConfigured: Bool {
        switch authMethod {
        case .oauth:
            return !oauthToken.isEmpty
        case .sessionCookie:
            return !sessionCookie.isEmpty
        }
    }

    func buildHeaders() -> [String: String] {
        switch authMethod {
        case .oauth:
            guard !oauthToken.isEmpty else { return [:] }
            return [
                "Authorization": "Bearer \(oauthToken)",
                "anthropic-beta": "oauth-2025-04-20"
            ]
        case .sessionCookie:
            guard !sessionCookie.isEmpty else { return [:] }
            return [
                "Cookie": "sessionKey=\(sessionCookie)"
            ]
        }
    }

    func loadOAuthTokenFromKeychain() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.anthropic.claude-code",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecSuccess, let data = result as? Data,
           let token = String(data: data, encoding: .utf8) {
            oauthToken = token
        }
    }

    func fetchOrganizationId() async throws {
        guard isConfigured else { return }

        var request = URLRequest(url: URL(string: "https://claude.ai/api/organizations")!)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        for (key, value) in buildHeaders() {
            request.setValue(value, forHTTPHeaderField: key)
        }

        print("[AuthManager] Fetching organizations...")
        let (data, response) = try await URLSession.shared.data(for: request)
        print("[AuthManager] Got response: \(String(data: data, encoding: .utf8) ?? "nil")")

        guard let httpResponse = response as? HTTPURLResponse else {
            connectionStatus = .error("No HTTP response")
            throw URLError(.badServerResponse)
        }

        guard httpResponse.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            print("API error: HTTP \(httpResponse.statusCode) — \(body)")
            connectionStatus = .error("HTTP \(httpResponse.statusCode)")
            throw URLError(.badServerResponse)
        }

        let orgs = try JSONDecoder.apiDecoder.decode([Organization].self, from: data)
        if let firstOrg = orgs.first {
            organizationId = firstOrg.uuid
            connectionStatus = .connected
        } else {
            connectionStatus = .error("No organizations found")
        }
    }
}
