import XCTest
@testable import ClaudeTokenUsage

final class UsageResponseTests: XCTestCase {

    func testDecodeFull() throws {
        let json = """
        {
            "five_hour": {
                "utilization": 42.5,
                "resets_at": "2026-04-07T18:30:00.000Z"
            },
            "seven_day": {
                "utilization": 15.2,
                "resets_at": "2026-04-13T12:59:00.000Z"
            },
            "seven_day_opus": {
                "utilization": 8.0
            },
            "seven_day_sonnet": {
                "utilization": 12.3,
                "resets_at": "2026-04-13T12:59:00.000Z"
            },
            "extra_usage": {
                "is_enabled": true,
                "monthly_limit": 5000,
                "used_credits": 1200
            }
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder.makeAPIDecoder().decode(UsageResponse.self, from: json)

        XCTAssertEqual(response.fiveHour.utilization, 42.5)
        XCTAssertNotNil(response.fiveHour.resetsAt)
        XCTAssertEqual(response.sevenDay.utilization, 15.2)
        XCTAssertEqual(response.sevenDayOpus?.utilization, 8.0)
        XCTAssertEqual(response.sevenDaySonnet?.utilization, 12.3)
        XCTAssertEqual(response.extraUsage?.isEnabled, true)
        XCTAssertEqual(response.extraUsage?.monthlyLimit, 5000)
        XCTAssertEqual(response.extraUsage?.usedCredits, 1200)
    }

    func testDecodeMinimal() throws {
        let json = """
        {
            "five_hour": {
                "utilization": 0.0,
                "resets_at": "2026-04-07T18:30:00.000Z"
            },
            "seven_day": {
                "utilization": 0.0,
                "resets_at": "2026-04-13T12:59:00.000Z"
            }
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder.makeAPIDecoder().decode(UsageResponse.self, from: json)

        XCTAssertEqual(response.fiveHour.utilization, 0.0)
        XCTAssertNil(response.sevenDayOpus)
        XCTAssertNil(response.sevenDaySonnet)
        XCTAssertNil(response.extraUsage)
    }

    func testDecodeOrganizations() throws {
        let json = """
        [
            {
                "uuid": "d3bc1234-abcd-5678-ef90-000000000000",
                "name": "Personal"
            }
        ]
        """.data(using: .utf8)!

        let orgs = try JSONDecoder.makeAPIDecoder().decode([Organization].self, from: json)

        XCTAssertEqual(orgs.count, 1)
        XCTAssertEqual(orgs[0].uuid, "d3bc1234-abcd-5678-ef90-000000000000")
        XCTAssertEqual(orgs[0].name, "Personal")
    }
}
