import XCTest
@testable import ClaudeTokenUsage

final class AuthManagerTests: XCTestCase {

    func testSessionCookieHeaders() {
        let auth = AuthManager()
        auth.authMethod = .sessionCookie
        auth.sessionCookie = "sk-ant-abc123"

        let headers = auth.buildHeaders()

        XCTAssertEqual(headers["Cookie"], "sessionKey=sk-ant-abc123")
        XCTAssertNil(headers["Authorization"])
    }

    func testOAuthHeaders() {
        let auth = AuthManager()
        auth.authMethod = .oauth
        auth.oauthToken = "oauth-token-xyz"

        let headers = auth.buildHeaders()

        XCTAssertEqual(headers["Authorization"], "Bearer oauth-token-xyz")
        XCTAssertEqual(headers["anthropic-beta"], "oauth-2025-04-20")
        XCTAssertNil(headers["Cookie"])
    }

    func testNoCredentials() {
        let auth = AuthManager()
        auth.authMethod = .sessionCookie
        auth.sessionCookie = ""

        let headers = auth.buildHeaders()

        XCTAssertTrue(headers.isEmpty)
    }

    func testIsConfigured_sessionCookie() {
        let auth = AuthManager()
        auth.authMethod = .sessionCookie
        auth.sessionCookie = ""
        XCTAssertFalse(auth.isConfigured)

        auth.sessionCookie = "sk-ant-abc123"
        XCTAssertTrue(auth.isConfigured)
    }

    func testIsConfigured_oauth() {
        let auth = AuthManager()
        auth.authMethod = .oauth
        auth.oauthToken = ""
        XCTAssertFalse(auth.isConfigured)

        auth.oauthToken = "token"
        XCTAssertTrue(auth.isConfigured)
    }
}
