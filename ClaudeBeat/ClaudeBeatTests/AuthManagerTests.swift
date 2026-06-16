import XCTest
@testable import ClaudeBeat

final class AuthManagerTests: XCTestCase {

    override func tearDown() {
        // Clear the shared Keychain item so tests don't pollute each other or the real app.
        AuthManager().sessionCookie = ""
        super.tearDown()
    }

    func testSessionCookiePersistsToKeychain() {
        AuthManager().sessionCookie = "sk-ant-abc123"
        // A fresh instance must load the persisted value back from the Keychain.
        let reloaded = AuthManager()
        XCTAssertEqual(reloaded.sessionCookie, "sk-ant-abc123")
    }

    func testIsConfigured_followsSessionCookie() {
        let auth = AuthManager()
        auth.sessionCookie = ""
        XCTAssertFalse(auth.isConfigured)

        auth.sessionCookie = "sk-ant-abc123"
        XCTAssertTrue(auth.isConfigured)
    }
}
