import Foundation
import Security

@Observable
final class AuthManager {
    private static let keychainService = "com.claudetokenusage.sessionkey"

    /// Pasted sessionKey (Google-SSO fallback). Persisted to the Keychain and re-injected
    /// into the WebSession on launch.
    var sessionCookie: String = "" {
        didSet { saveSessionCookieToKeychain(sessionCookie) }
    }

    var connectionStatus: ConnectionStatus = .unknown

    enum ConnectionStatus: Equatable {
        case unknown, connected, error(String)
    }

    init() {
        self.sessionCookie = Self.loadCookieFromKeychain() ?? ""
    }

    /// True if we have a credential to try (a pasted key). The authoritative check is
    /// `WebSession.probeLoggedIn()`; this only gates whether to re-inject on launch.
    var isConfigured: Bool { !sessionCookie.isEmpty }

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
        return nil
    }

    private func saveSessionCookieToKeychain(_ value: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: "sessionKey",
        ]
        SecItemDelete(query as CFDictionary)
        guard !value.isEmpty else { return }
        var add = query
        add[kSecValueData as String] = Data(value.utf8)
        SecItemAdd(add as CFDictionary, nil)
    }
}
