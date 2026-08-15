import XCTest
@testable import ClaudeBeat

final class UsageLimitTests: XCTestCase {

    /// Trimmed from a real response captured 2026-08-15. Includes the unrecognized
    /// codename keys the API ships alongside the real ones.
    private let capturedJSON = """
    {
        "five_hour": { "utilization": 4.0, "resets_at": "2026-08-15T16:49:59.983468+00:00" },
        "seven_day": { "utilization": 46.0, "resets_at": "2026-08-20T09:59:59.983485+00:00" },
        "seven_day_opus": null,
        "seven_day_sonnet": null,
        "nimbus_quill": { "utilization": 0.0, "resets_at": null },
        "amber_ladder": null,
        "limits": [
            { "kind": "session", "group": "session", "percent": 4, "severity": "normal",
              "resets_at": "2026-08-15T16:49:59.983468+00:00", "scope": null, "is_active": false },
            { "kind": "weekly_all", "group": "weekly", "percent": 46, "severity": "normal",
              "resets_at": "2026-08-20T09:59:59.983485+00:00", "scope": null, "is_active": false },
            { "kind": "weekly_scoped", "group": "weekly", "percent": 82, "severity": "warning",
              "resets_at": "2026-08-20T09:59:59.983652+00:00",
              "scope": { "model": { "id": "abc", "display_name": "Fable" }, "surface": null },
              "is_active": true }
        ]
    }
    """.data(using: .utf8)!

    func testDecodeCapturedPayload() throws {
        let response = try JSONDecoder.makeAPIDecoder().decode(UsageResponse.self, from: capturedJSON)

        XCTAssertEqual(response.limits.count, 3)
        XCTAssertEqual(response.limits.map(\.kind), ["session", "weekly_all", "weekly_scoped"])

        let scoped = try XCTUnwrap(response.limits.first { $0.kind == "weekly_scoped" })
        XCTAssertEqual(scoped.percent, 82)
        XCTAssertEqual(scoped.severity, "warning")
        XCTAssertTrue(scoped.isActive)
        XCTAssertEqual(scoped.scope?.model?.displayName, "Fable")
        XCTAssertNotNil(scoped.resetsAt)
    }

    func testLimitsAbsentDecodesToEmpty() throws {
        let json = """
        {
            "five_hour": { "utilization": 1.0, "resets_at": "2026-08-15T16:49:59.983468+00:00" },
            "seven_day": { "utilization": 2.0, "resets_at": "2026-08-20T09:59:59.983485+00:00" }
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder.makeAPIDecoder().decode(UsageResponse.self, from: json)

        XCTAssertTrue(response.limits.isEmpty)
    }

    func testLimitsNullDecodesToEmpty() throws {
        let json = """
        {
            "five_hour": { "utilization": 1.0, "resets_at": "2026-08-15T16:49:59.983468+00:00" },
            "seven_day": { "utilization": 2.0, "resets_at": "2026-08-20T09:59:59.983485+00:00" },
            "limits": null
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder.makeAPIDecoder().decode(UsageResponse.self, from: json)

        XCTAssertTrue(response.limits.isEmpty)
    }

    func testMalformedElementIsDroppedAndSiblingsSurvive() throws {
        let json = """
        {
            "five_hour": { "utilization": 1.0, "resets_at": "2026-08-15T16:49:59.983468+00:00" },
            "seven_day": { "utilization": 2.0, "resets_at": "2026-08-20T09:59:59.983485+00:00" },
            "limits": [
                { "group": "weekly", "percent": 50 },
                { "kind": "weekly_all", "percent": 46 }
            ]
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder.makeAPIDecoder().decode(UsageResponse.self, from: json)

        XCTAssertEqual(response.limits.count, 1)
        XCTAssertEqual(response.limits.first?.kind, "weekly_all")
    }

    func testMissingPercentDecodesToZero() throws {
        let json = """
        {
            "five_hour": { "utilization": 1.0, "resets_at": "2026-08-15T16:49:59.983468+00:00" },
            "seven_day": { "utilization": 2.0, "resets_at": "2026-08-20T09:59:59.983485+00:00" },
            "limits": [
                { "kind": "weekly_all", "percent": null },
                { "kind": "weekly_scoped", "scope": { "model": { "display_name": "Fable" } } }
            ]
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder.makeAPIDecoder().decode(UsageResponse.self, from: json)

        XCTAssertEqual(response.limits.map(\.percent), [0, 0])
        XCTAssertFalse(response.limits[0].isActive)
    }

    func testUnknownScopeSurfaceShapeDoesNotFailDecode() throws {
        let json = """
        {
            "five_hour": { "utilization": 1.0, "resets_at": "2026-08-15T16:49:59.983468+00:00" },
            "seven_day": { "utilization": 2.0, "resets_at": "2026-08-20T09:59:59.983485+00:00" },
            "limits": [
                { "kind": "weekly_scoped", "percent": 82,
                  "scope": { "model": { "display_name": "Fable" },
                             "surface": { "id": "claude_code", "display_name": "Claude Code" } } }
            ]
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder.makeAPIDecoder().decode(UsageResponse.self, from: json)

        XCTAssertEqual(response.limits.first?.scope?.model?.displayName, "Fable")
    }
}
