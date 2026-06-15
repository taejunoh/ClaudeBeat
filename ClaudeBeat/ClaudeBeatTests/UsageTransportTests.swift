import XCTest
@testable import ClaudeBeat

final class UsageTransportTests: XCTestCase {

    func testClassify_ok() {
        XCTAssertEqual(
            TransportClassifier.classify(status: 200, finalPath: "/api/organizations", cfMitigated: false),
            .ok
        )
    }

    func testClassify_cloudflareChallenge() {
        XCTAssertEqual(
            TransportClassifier.classify(status: 403, finalPath: "/api/organizations", cfMitigated: true),
            .challenge
        )
        // 403 alone (no marker) is still treated as a challenge to retry.
        XCTAssertEqual(
            TransportClassifier.classify(status: 403, finalPath: "/api/organizations", cfMitigated: false),
            .challenge
        )
    }

    func testClassify_unauthorized() {
        XCTAssertEqual(
            TransportClassifier.classify(status: 401, finalPath: "/api/organizations", cfMitigated: false),
            .needsLogin
        )
    }

    func testClassify_redirectToLogin() {
        XCTAssertEqual(
            TransportClassifier.classify(status: 200, finalPath: "/login", cfMitigated: false),
            .needsLogin
        )
    }

    func testClassify_serverError() {
        XCTAssertEqual(
            TransportClassifier.classify(status: 503, finalPath: "/api/organizations", cfMitigated: false),
            .networkError(503)
        )
    }
}
