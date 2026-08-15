import XCTest
@testable import ClaudeBeat

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

    /// Real payload captured while the API was A/B-testing several unmodeled fields
    /// (seven_day_oauth_apps, tangelo, extra_usage.daily, etc.) as null. Unknown keys
    /// are ignored by Codable; this only exercises the fields we model.
    func testDecodeRealFixtureWithABTestFields() throws {
        let json = """
        {
            "five_hour": {
                "utilization": 11.0,
                "resets_at": "2026-07-30T05:09:59.772974+00:00",
                "limit_dollars": null,
                "used_dollars": null,
                "remaining_dollars": null
            },
            "seven_day": {
                "utilization": 96.0,
                "resets_at": "2026-07-30T10:00:00.772994+00:00",
                "limit_dollars": null,
                "used_dollars": null,
                "remaining_dollars": null
            },
            "seven_day_oauth_apps": null,
            "seven_day_cowork": null,
            "seven_day_omelette": null,
            "tangelo": null,
            "iguana_necktie": null,
            "omelette_promotional": null,
            "nimbus_quill": null,
            "cinder_cove": null,
            "amber_ladder": null,
            "extra_usage": {
                "is_enabled": false,
                "monthly_limit": null,
                "used_credits": null,
                "utilization": null,
                "currency": null,
                "decimal_places": null,
                "disabled_reason": null,
                "user_disabled": true,
                "spend_limit_reached": false,
                "credits_ever_enabled": true,
                "daily": null,
                "weekly": null
            },
            "member_dashboard_available": false
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder.makeAPIDecoder().decode(UsageResponse.self, from: json)

        XCTAssertEqual(response.fiveHour.utilization, 11.0)
        XCTAssertEqual(response.extraUsage?.isEnabled, false)
    }

    func testDecodeUsageBucket_nullUtilization_defaultsToZero() throws {
        let json = """
        {"utilization": null, "resets_at": "2026-04-07T18:30:00.000Z"}
        """.data(using: .utf8)!

        let bucket = try JSONDecoder.makeAPIDecoder().decode(UsageBucket.self, from: json)

        XCTAssertEqual(bucket.utilization, 0.0)
        XCTAssertNotNil(bucket.resetsAt)
    }

    func testDecodeUsageBucket_missingUtilization_defaultsToZero() throws {
        let json = """
        {"resets_at": "2026-04-07T18:30:00.000Z"}
        """.data(using: .utf8)!

        let bucket = try JSONDecoder.makeAPIDecoder().decode(UsageBucket.self, from: json)

        XCTAssertEqual(bucket.utilization, 0.0)
        XCTAssertNotNil(bucket.resetsAt)
    }

    func testDecodeExtraUsage_missingIsEnabled_defaultsToFalse() throws {
        let json = """
        {"monthly_limit": 5000}
        """.data(using: .utf8)!

        let extraUsage = try JSONDecoder.makeAPIDecoder().decode(ExtraUsage.self, from: json)

        XCTAssertEqual(extraUsage.isEnabled, false)
    }

    func testDecodeExtraUsage_nullIsEnabled_defaultsToFalse() throws {
        let json = """
        {"is_enabled": null, "monthly_limit": 5000}
        """.data(using: .utf8)!

        let extraUsage = try JSONDecoder.makeAPIDecoder().decode(ExtraUsage.self, from: json)

        XCTAssertEqual(extraUsage.isEnabled, false)
    }

    func testDecodeOrganizations_skipsBadElement() throws {
        let json = """
        [
            {"name": "No UUID"},
            {"uuid": "d3bc1234-abcd-5678-ef90-000000000000", "name": "Personal"}
        ]
        """.data(using: .utf8)!

        let orgs = try JSONDecoder.makeAPIDecoder().decode(LossyArray<Organization>.self, from: json).elements

        XCTAssertEqual(orgs.count, 1)
        XCTAssertEqual(orgs[0].uuid, "d3bc1234-abcd-5678-ef90-000000000000")
    }
}
