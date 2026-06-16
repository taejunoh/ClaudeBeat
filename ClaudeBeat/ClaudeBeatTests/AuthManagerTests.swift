import XCTest
@testable import ClaudeBeat

final class AuthManagerTests: XCTestCase {

    func testSessionCookieRoundTrips() {
        let auth = AuthManager()
        auth.sessionCookie = "sk-ant-abc123"
        XCTAssertEqual(auth.sessionCookie, "sk-ant-abc123")
    }

    func testIsConfigured_followsSessionCookie() {
        let auth = AuthManager()
        auth.sessionCookie = ""
        XCTAssertFalse(auth.isConfigured)

        auth.sessionCookie = "sk-ant-abc123"
        XCTAssertTrue(auth.isConfigured)
    }
}
