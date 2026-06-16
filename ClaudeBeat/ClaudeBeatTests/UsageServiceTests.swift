import XCTest
@testable import ClaudeBeat

/// In-memory transport keyed by path.
final class FakeTransport: UsageTransport, @unchecked Sendable {
    var responses: [String: Result<Data, Error>] = [:]
    func fetchJSON(path: String) async throws -> Data {
        guard let result = responses[path] else { throw TransportError.network(404) }
        return try result.get()
    }
}

@MainActor
final class UsageServiceTests: XCTestCase {

    private let orgsJSON = #"[{"uuid":"org-123","name":"Acme"}]"#
    private let usageJSON = #"""
    {"five_hour":{"utilization":42,"resets_at":"2026-06-15T20:00:00Z"},
     "seven_day":{"utilization":12,"resets_at":"2026-06-20T00:00:00Z"}}
    """#

    func testFetchUsage_success_updatesState() async {
        let fake = FakeTransport()
        fake.responses["/api/organizations"] = .success(Data(orgsJSON.utf8))
        fake.responses["/api/organizations/org-123/usage"] = .success(Data(usageJSON.utf8))

        let state = UsageState()
        let service = UsageService(transport: fake, usageState: state)

        await service.fetchUsage()

        XCTAssertEqual(state.menuBarPercentage, "42%")
        XCTAssertFalse(state.isError)
        XCTAssertFalse(state.needsLogin)
    }

    func testFetchUsage_needsLogin_setsFlag() async {
        let fake = FakeTransport()
        fake.responses["/api/organizations"] = .failure(TransportError.needsLogin)

        let state = UsageState()
        let service = UsageService(transport: fake, usageState: state)

        await service.fetchUsage()

        XCTAssertTrue(state.needsLogin)
    }

    func testFetchUsage_challenge_setsConnectingError() async {
        let fake = FakeTransport()
        fake.responses["/api/organizations"] = .failure(TransportError.challenge)

        let state = UsageState()
        let service = UsageService(transport: fake, usageState: state)

        await service.fetchUsage()

        XCTAssertTrue(state.isError)
        XCTAssertFalse(state.needsLogin)
        XCTAssertEqual(state.errorMessage, "Connecting…")
    }

    func testFetchUsage_malformedJSON_setsError() async {
        let fake = FakeTransport()
        fake.responses["/api/organizations"] = .success(Data(orgsJSON.utf8))
        fake.responses["/api/organizations/org-123/usage"] = .success(Data("not json".utf8))

        let state = UsageState()
        let service = UsageService(transport: fake, usageState: state)

        await service.fetchUsage()

        XCTAssertTrue(state.isError)
        XCTAssertFalse(state.needsLogin)
    }
}
