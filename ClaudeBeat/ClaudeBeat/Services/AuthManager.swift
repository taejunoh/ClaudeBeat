import Foundation
import Security

enum AuthMethod: String, CaseIterable, Sendable {
    case oauth = "OAuth (Claude Code)"
    case sessionCookie = "Session Cookie"
}

@Observable
final class AuthManager {
    private static let defaults = UserDefaults(suiteName: "com.claudebeat.macos") ?? .standard
    private static let keychainService = "com.claudetokenusage.sessionkey"

    var authMethod: AuthMethod {
        didSet { Self.defaults.set(authMethod.rawValue, forKey: "authMethod") }
    }
    var sessionCookie: String = "" {
        didSet { saveSessionCookieToKeychain(sessionCookie) }
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
        self.organizationId = d.string(forKey: "organizationId") ?? ""
        self.sessionCookie = Self.loadCookieFromKeychain() ?? ""
    }

    private static func loadCookieFromKeychain() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: "sessionKey",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecSuccess, let data = result as? Data {
            return String(data: data, encoding: .utf8)
        }
        // Migration: check old UserDefaults storage
        if let old = defaults.string(forKey: "sessionCookie"), !old.isEmpty {
            let saveQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: keychainService,
                kSecValueData as String: Data(old.utf8)
            ]
            SecItemAdd(saveQuery as CFDictionary, nil)
            defaults.removeObject(forKey: "sessionCookie")
            return old
        }
        return nil
    }

    var isConfigured: Bool {
        switch authMethod {
        case .oauth: return !oauthToken.isEmpty
        case .sessionCookie: return !sessionCookie.isEmpty
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
            return ["Cookie": "sessionKey=\(sessionCookie)"]
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

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            connectionStatus = .error("No HTTP response")
            throw URLError(.badServerResponse)
        }

        guard httpResponse.statusCode == 200 else {
            connectionStatus = .error("HTTP \(httpResponse.statusCode)")
            throw URLError(.badServerResponse)
        }

        let orgs = try JSONDecoder.makeAPIDecoder().decode([Organization].self, from: data)
        if let firstOrg = orgs.first {
            organizationId = firstOrg.uuid
            connectionStatus = .connected
        } else {
            connectionStatus = .error("No organizations found")
        }
    }

    // MARK: - Keychain helpers

    private func saveSessionCookieToKeychain(_ value: String) {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: "sessionKey",
        ]
        SecItemDelete(query as CFDictionary)
        guard !value.isEmpty else { return }
        var add = query
        add[kSecValueData as String] = data
        SecItemAdd(add as CFDictionary, nil)
    }

}
