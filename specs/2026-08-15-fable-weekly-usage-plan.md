# Fable Weekly Usage Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show Fable's weekly utilization in the popover's Weekly (7d) section, driven by the API's new `limits` array rather than the now-null `seven_day_*` fields.

**Architecture:** A new `UsageLimit` model decodes `limits[]`. A pure `WeeklyBreakdown` helper turns a `UsageResponse` into an ordered list of `WeeklyItem` gauges — `weekly_all` plus every labeled `weekly_scoped` entry — falling back to the flat `seven_day` bucket when `limits` carries no weekly entries. `WeeklyUsageView` renders that list as a wrapping grid with one shared reset line.

**Tech Stack:** Swift 5.10, SwiftUI, XCTest, SwiftPM (`swift test`) with an xcodegen-generated Xcode project for app builds.

**Spec:** `specs/2026-08-15-fable-weekly-usage-design.md`

## Global Constraints

- Swift 5.10, macOS 14.0 deployment target.
- All model types stay `Sendable`. `UsageService` and `UsageState` are `@MainActor`.
- Decode defensively: this endpoint has dropped fields and sent nulls without notice. A field the app does not use is not decoded at all.
- Never fail a whole response over one bad element — reuse the existing `LossyArray` for arrays.
- The popover is a fixed 280pt wide. Nothing may widen it.
- Run tests with `swift test` from the `ClaudeBeat/` directory (the one containing `Package.swift`). Baseline before this plan: 46 tests, 0 failures.
- Commit after every task. Work happens on branch `feat/fable-weekly-usage`.

## File Structure

| File | Responsibility |
|---|---|
| `ClaudeBeat/ClaudeBeat/Models/UsageLimit.swift` | **Create.** Decodes one `limits[]` entry plus its `scope.model`. |
| `ClaudeBeat/ClaudeBeat/Models/WeeklyBreakdown.swift` | **Create.** `WeeklyItem` presentation model and the pure derivation + shared-reset logic. |
| `ClaudeBeat/ClaudeBeat/Models/UsageResponse.swift` | **Modify.** Add `limits` (Task 2); delete the dead `sevenDayOpus` / `sevenDaySonnet` (Task 5, with their last call sites). |
| `ClaudeBeat/ClaudeBeat/Models/UsageState.swift` | **Modify.** Expose `weeklyItems`. |
| `ClaudeBeat/ClaudeBeat/Views/WeeklyUsageView.swift` | **Modify.** Render a list of items as a wrapping grid with a shared reset line. |
| `ClaudeBeat/ClaudeBeat/Views/UsageGaugeView.swift` | **Modify.** Delete the dead Opus/Sonnet chip row. |
| `ClaudeBeat/ClaudeBeat/Views/PopoverView.swift` | **Modify.** Wire the new inputs. |
| `ClaudeBeat/ClaudeBeat/Services/UsageService.swift` | **Modify.** Log every raw response body (already applied in the working tree — Task 1 only commits it). |
| `ClaudeBeat/ClaudeBeatTests/UsageLimitTests.swift` | **Create.** Decoding tests against the captured payload. |
| `ClaudeBeat/ClaudeBeatTests/WeeklyBreakdownTests.swift` | **Create.** Derivation, ordering, fallback, shared-reset tests. |
| `ClaudeBeat/ClaudeBeatTests/UsageResponseTests.swift` | **Modify.** Drop assertions on removed fields. |
| `ClaudeBeat/ClaudeBeatTests/UsageStateTests.swift` | **Modify.** Update `UsageResponse` initializer calls. |
| `README.md` | **Modify.** Lines 41 and 122 describe "All models + Sonnet only". |

---

### Task 1: Commit the raw-response diagnostic

The change is already applied to the working tree — it is what produced the captured payload the rest of this plan depends on. This task verifies and commits it.

**Files:**
- Modify: `ClaudeBeat/ClaudeBeat/Services/UsageService.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: nothing other code calls. `logRawResponse(endpoint:body:)` and `write(_:to:)` are `private static`.

There is no unit test here. Both functions are `private static` file I/O with all errors swallowed by design, so a test would assert on the filesystem rather than on behavior anything depends on. It was verified by running the app and reading the log it produced.

- [ ] **Step 1: Confirm the working tree holds exactly this change**

Run: `git diff --stat`
Expected: one file changed, `ClaudeBeat/ClaudeBeat/Services/UsageService.swift`.

- [ ] **Step 2: Confirm the call site and helpers are present**

Run: `grep -n "logRawResponse\|private static func write" ClaudeBeat/ClaudeBeat/Services/UsageService.swift`
Expected: three lines — the call inside `fetchUsage()`, the `logRawResponse` definition, the `write` definition.

- [ ] **Step 3: Verify the suite still passes**

Run: `cd ClaudeBeat && swift test 2>&1 | tail -5`
Expected: `Executed 46 tests, with 0 failures`

- [ ] **Step 4: Commit**

```bash
git add ClaudeBeat/ClaudeBeat/Services/UsageService.swift
git commit -m "feat: log the raw usage response body

The usage endpoint drifts without notice — per-model fields have now gone
null twice — and a decode-failure-only log cannot diagnose drift that still
decodes. Keep the last raw body on disk, overwritten each fetch."
```

---

### Task 2: Decode the `limits` array

**Files:**
- Create: `ClaudeBeat/ClaudeBeat/Models/UsageLimit.swift`
- Modify: `ClaudeBeat/ClaudeBeat/Models/UsageResponse.swift`
- Test: `ClaudeBeat/ClaudeBeatTests/UsageLimitTests.swift`

This task is additive on purpose. `sevenDayOpus` and `sevenDaySonnet` are dead, but `PopoverView` still reads them; deleting them here would break the build mid-task. They go in Task 5 together with their last call sites.

**Interfaces:**
- Consumes: `LossyArray<Element>` and `JSONDecoder.makeAPIDecoder()` from `UsageResponse.swift`.
- Produces:
  - `struct UsageLimit: Decodable, Sendable` with `kind: String`, `percent: Double`, `severity: String?`, `resetsAt: Date?`, `scope: LimitScope?`, `isActive: Bool`, and memberwise init `UsageLimit(kind:percent:severity:resetsAt:scope:isActive:)` where every parameter after `percent` defaults.
  - `struct LimitScope: Decodable, Sendable` with `model: LimitModel?` and init `LimitScope(model:)`.
  - `struct LimitModel: Decodable, Sendable` with `displayName: String?` and init `LimitModel(displayName:)`.
  - `UsageResponse.limits: [UsageLimit]`, never nil, `[]` when absent.
  - `UsageResponse` memberwise init becomes `UsageResponse(fiveHour:sevenDay:sevenDayOpus:sevenDaySonnet:extraUsage:limits:)` with every parameter after `sevenDay` defaulted to `nil` / `[]`, so existing call sites keep compiling and new ones can write `UsageResponse(fiveHour:sevenDay:extraUsage:limits:)`.

- [ ] **Step 1: Write the failing tests**

Create `ClaudeBeat/ClaudeBeatTests/UsageLimitTests.swift`:

```swift
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
```

That last test is the point of not declaring `surface`: it was null in every capture, so its real type is a guess. If the app declared it as `String?` and it arrives as an object, `LossyArray` would silently drop the entry and Fable's gauge would vanish with no error anywhere.

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd ClaudeBeat && swift test --filter UsageLimitTests 2>&1 | tail -20`
Expected: compile failure — `cannot find type 'UsageLimit' in scope` / `value of type 'UsageResponse' has no member 'limits'`.

- [ ] **Step 3: Create the model**

Create `ClaudeBeat/ClaudeBeat/Models/UsageLimit.swift`:

```swift
import Foundation

/// One entry of the usage endpoint's `limits` array.
///
/// This array superseded the per-model `seven_day_*` fields, which the API now sends as
/// null. `scope.surface` is deliberately not decoded: it has only ever been observed as
/// null, so its real type is unknown, and declaring the wrong one would drop the entry.
struct UsageLimit: Decodable, Sendable {
    let kind: String
    let percent: Double
    let severity: String?
    let resetsAt: Date?
    let scope: LimitScope?
    let isActive: Bool

    enum CodingKeys: String, CodingKey {
        case kind
        case percent
        case severity
        case resetsAt = "resets_at"
        case scope
        case isActive = "is_active"
    }

    init(
        kind: String,
        percent: Double,
        severity: String? = nil,
        resetsAt: Date? = nil,
        scope: LimitScope? = nil,
        isActive: Bool = false
    ) {
        self.kind = kind
        self.percent = percent
        self.severity = severity
        self.resetsAt = resetsAt
        self.scope = scope
        self.isActive = isActive
    }

    // `kind` is the one required field: an entry without it cannot be routed, so letting
    // the decode throw lets LossyArray drop just that element.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decode(String.self, forKey: .kind)
        percent = try container.decodeIfPresent(Double.self, forKey: .percent) ?? 0
        severity = try container.decodeIfPresent(String.self, forKey: .severity)
        resetsAt = try container.decodeIfPresent(Date.self, forKey: .resetsAt)
        scope = try container.decodeIfPresent(LimitScope.self, forKey: .scope)
        isActive = try container.decodeIfPresent(Bool.self, forKey: .isActive) ?? false
    }
}

struct LimitScope: Decodable, Sendable {
    let model: LimitModel?

    init(model: LimitModel?) {
        self.model = model
    }
}

struct LimitModel: Decodable, Sendable {
    let displayName: String?

    enum CodingKeys: String, CodingKey {
        case displayName = "display_name"
    }

    init(displayName: String?) {
        self.displayName = displayName
    }
}
```

- [ ] **Step 4: Wire `limits` into `UsageResponse`**

In `ClaudeBeat/ClaudeBeat/Models/UsageResponse.swift`, replace the whole `UsageResponse` struct (lines 3-17) with:

```swift
struct UsageResponse: Decodable, Sendable {
    let fiveHour: UsageBucket
    let sevenDay: UsageBucket
    let sevenDayOpus: UsageBucket?
    let sevenDaySonnet: UsageBucket?
    let extraUsage: ExtraUsage?
    let limits: [UsageLimit]

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
        case sevenDayOpus = "seven_day_opus"
        case sevenDaySonnet = "seven_day_sonnet"
        case extraUsage = "extra_usage"
        case limits
    }

    init(
        fiveHour: UsageBucket,
        sevenDay: UsageBucket,
        sevenDayOpus: UsageBucket? = nil,
        sevenDaySonnet: UsageBucket? = nil,
        extraUsage: ExtraUsage? = nil,
        limits: [UsageLimit] = []
    ) {
        self.fiveHour = fiveHour
        self.sevenDay = sevenDay
        self.sevenDayOpus = sevenDayOpus
        self.sevenDaySonnet = sevenDaySonnet
        self.extraUsage = extraUsage
        self.limits = limits
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        fiveHour = try container.decode(UsageBucket.self, forKey: .fiveHour)
        sevenDay = try container.decode(UsageBucket.self, forKey: .sevenDay)
        sevenDayOpus = try container.decodeIfPresent(UsageBucket.self, forKey: .sevenDayOpus)
        sevenDaySonnet = try container.decodeIfPresent(UsageBucket.self, forKey: .sevenDaySonnet)
        extraUsage = try container.decodeIfPresent(ExtraUsage.self, forKey: .extraUsage)
        limits = try container.decodeIfPresent(LossyArray<UsageLimit>.self, forKey: .limits)?.elements ?? []
    }
}
```

Two things about this struct that are not obvious:

- `Codable` becomes `Decodable` because `UsageLimit` is decode-only and nothing in the app encodes a response — `grep -rn "JSONEncoder" ClaudeBeat/ClaudeBeat` returns nothing.
- The memberwise init has to be written out by hand now. Adding `limits` with a default is what lets every existing call site keep compiling untouched, and the synthesized init gives no defaults.

- [ ] **Step 5: Run tests to verify they pass**

Run: `cd ClaudeBeat && swift test 2>&1 | tail -5`
Expected: `Executed 52 tests, with 0 failures` (46 baseline + 6 new). No existing test needed editing.

- [ ] **Step 6: Commit**

```bash
git add ClaudeBeat/ClaudeBeat/Models/UsageLimit.swift \
        ClaudeBeat/ClaudeBeat/Models/UsageResponse.swift \
        ClaudeBeat/ClaudeBeatTests/UsageLimitTests.swift
git commit -m "feat: decode the usage endpoint's limits array

Per-model utilization moved here; every seven_day_* field is now null.
scope.surface is left undecoded — it has only been seen as null and
guessing its type would drop the entry that carries Fable."
```

---

### Task 3: Derive the weekly gauge list

**Files:**
- Create: `ClaudeBeat/ClaudeBeat/Models/WeeklyBreakdown.swift`
- Test: `ClaudeBeat/ClaudeBeatTests/WeeklyBreakdownTests.swift`

**Interfaces:**
- Consumes: `UsageResponse`, `UsageLimit`, `LimitScope`, `LimitModel`, `UsageBucket` from Task 2.
- Produces:
  - `struct WeeklyItem: Identifiable, Equatable, Sendable` with `id: String`, `label: String`, `utilization: Double`, `resetsAt: Date?`, and memberwise init `WeeklyItem(id:label:utilization:resetsAt:)`.
  - `enum WeeklyBreakdown` with `static let allModelsLabel = "All models"`, `static func items(from: UsageResponse) -> [WeeklyItem]`, and `static func sharedResetDate(for: [WeeklyItem]) -> Date?`.

- [ ] **Step 1: Write the failing tests**

Create `ClaudeBeat/ClaudeBeatTests/WeeklyBreakdownTests.swift`:

```swift
import XCTest
@testable import ClaudeBeat

final class WeeklyBreakdownTests: XCTestCase {

    private let weeklyReset = Date(timeIntervalSince1970: 1_755_684_000)

    private func response(limits: [UsageLimit], sevenDay: Double = 46.0) -> UsageResponse {
        UsageResponse(
            fiveHour: UsageBucket(utilization: 4.0, resetsAt: nil),
            sevenDay: UsageBucket(utilization: sevenDay, resetsAt: weeklyReset),
            extraUsage: nil,
            limits: limits
        )
    }

    private func scoped(_ name: String, _ percent: Double, resetsAt: Date? = nil) -> UsageLimit {
        UsageLimit(
            kind: "weekly_scoped",
            percent: percent,
            resetsAt: resetsAt,
            scope: LimitScope(model: LimitModel(displayName: name))
        )
    }

    func testAllModelsAndScopedModels() {
        let items = WeeklyBreakdown.items(from: response(limits: [
            UsageLimit(kind: "session", percent: 4),
            UsageLimit(kind: "weekly_all", percent: 46, resetsAt: weeklyReset),
            scoped("Fable", 82, resetsAt: weeklyReset)
        ]))

        XCTAssertEqual(items.map(\.label), ["All models", "Fable"])
        XCTAssertEqual(items.map(\.utilization), [46, 82])
    }

    func testAllModelsIsAlwaysFirstAndScopedAreSortedByLabel() {
        let items = WeeklyBreakdown.items(from: response(limits: [
            scoped("Sonnet", 12),
            scoped("Fable", 82),
            UsageLimit(kind: "weekly_all", percent: 46),
            scoped("Opus", 8)
        ]))

        XCTAssertEqual(items.map(\.label), ["All models", "Fable", "Opus", "Sonnet"])
    }

    func testUnknownKindIsIgnored() {
        let items = WeeklyBreakdown.items(from: response(limits: [
            UsageLimit(kind: "weekly_all", percent: 46),
            UsageLimit(kind: "monthly_something_new", percent: 99)
        ]))

        XCTAssertEqual(items.map(\.label), ["All models"])
    }

    func testScopedWithoutDisplayNameIsDropped() {
        let items = WeeklyBreakdown.items(from: response(limits: [
            UsageLimit(kind: "weekly_all", percent: 46),
            UsageLimit(kind: "weekly_scoped", percent: 82, scope: nil),
            UsageLimit(kind: "weekly_scoped", percent: 71, scope: LimitScope(model: LimitModel(displayName: ""))),
            scoped("Fable", 82)
        ]))

        XCTAssertEqual(items.map(\.label), ["All models", "Fable"])
    }

    func testFallsBackToSevenDayWhenLimitsIsEmpty() {
        let items = WeeklyBreakdown.items(from: response(limits: []))

        XCTAssertEqual(items.map(\.label), ["All models"])
        XCTAssertEqual(items.first?.utilization, 46)
        XCTAssertEqual(items.first?.resetsAt, weeklyReset)
    }

    func testFallsBackToSevenDayWhenLimitsHasNoWeeklyEntries() {
        let items = WeeklyBreakdown.items(from: response(limits: [
            UsageLimit(kind: "session", percent: 4)
        ]))

        XCTAssertEqual(items.map(\.label), ["All models"])
        XCTAssertEqual(items.first?.utilization, 46)
    }

    func testSharedResetIgnoresSubMinuteDrift() {
        // Observed: weekly_all …983485 vs weekly_scoped …983652, the same reset.
        let items = [
            WeeklyItem(id: "a", label: "All models", utilization: 46, resetsAt: weeklyReset),
            WeeklyItem(id: "b", label: "Fable", utilization: 82, resetsAt: weeklyReset.addingTimeInterval(0.000167))
        ]

        XCTAssertEqual(WeeklyBreakdown.sharedResetDate(for: items), weeklyReset)
    }

    func testNoSharedResetWhenTimesDifferByMinutes() {
        let items = [
            WeeklyItem(id: "a", label: "All models", utilization: 46, resetsAt: weeklyReset),
            WeeklyItem(id: "b", label: "Fable", utilization: 82, resetsAt: weeklyReset.addingTimeInterval(600))
        ]

        XCTAssertNil(WeeklyBreakdown.sharedResetDate(for: items))
    }

    func testNoSharedResetWhenAnyItemLacksOne() {
        let items = [
            WeeklyItem(id: "a", label: "All models", utilization: 46, resetsAt: weeklyReset),
            WeeklyItem(id: "b", label: "Fable", utilization: 82, resetsAt: nil)
        ]

        XCTAssertNil(WeeklyBreakdown.sharedResetDate(for: items))
    }

    func testNoSharedResetForEmptyList() {
        XCTAssertNil(WeeklyBreakdown.sharedResetDate(for: []))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd ClaudeBeat && swift test --filter WeeklyBreakdownTests 2>&1 | tail -20`
Expected: compile failure — `cannot find 'WeeklyBreakdown' in scope`.

- [ ] **Step 3: Write the implementation**

Create `ClaudeBeat/ClaudeBeat/Models/WeeklyBreakdown.swift`:

```swift
import Foundation

/// One gauge in the popover's Weekly (7d) section.
struct WeeklyItem: Identifiable, Equatable, Sendable {
    let id: String
    let label: String
    let utilization: Double
    let resetsAt: Date?
}

enum WeeklyBreakdown {
    static let allModelsLabel = "All models"

    /// Builds the Weekly section's gauges from a usage response.
    ///
    /// Prefers `limits`, which is where per-model utilization lives now. When it carries
    /// no weekly entries — this endpoint has emptied fields without notice before — falls
    /// back to the flat `seven_day` bucket, which is exactly what the popover showed
    /// before `limits` existed.
    static func items(from response: UsageResponse) -> [WeeklyItem] {
        var allModels: WeeklyItem?
        var scoped: [WeeklyItem] = []

        for limit in response.limits {
            switch limit.kind {
            case "weekly_all":
                allModels = WeeklyItem(
                    id: "weekly_all",
                    label: allModelsLabel,
                    utilization: limit.percent,
                    resetsAt: limit.resetsAt
                )
            case "weekly_scoped":
                // An unlabeled gauge is noise — the server owns the label.
                guard let label = limit.scope?.model?.displayName, !label.isEmpty else { continue }
                scoped.append(WeeklyItem(
                    id: "weekly_scoped:\(label)",
                    label: label,
                    utilization: limit.percent,
                    resetsAt: limit.resetsAt
                ))
            default:
                continue
            }
        }

        // Server array order is not contractual; sort so gauges don't swap places between
        // refreshes.
        scoped.sort { $0.label.localizedStandardCompare($1.label) == .orderedAscending }

        let items = [allModels].compactMap { $0 } + scoped
        guard items.isEmpty else { return items }

        return [WeeklyItem(
            id: "seven_day",
            label: allModelsLabel,
            utilization: response.sevenDay.utilization,
            resetsAt: response.sevenDay.resetsAt
        )]
    }

    /// The one reset time to show for the whole section, or nil when the items disagree
    /// and each must show its own.
    ///
    /// Compared with a minute of tolerance: observed responses differ by microseconds
    /// (…983485 vs …983652) for what is plainly the same reset, so exact equality would
    /// never find a shared time.
    static func sharedResetDate(for items: [WeeklyItem]) -> Date? {
        let dates = items.compactMap(\.resetsAt)
        guard dates.count == items.count, let first = dates.first else { return nil }
        guard dates.allSatisfy({ abs($0.timeIntervalSince(first)) < 60 }) else { return nil }
        return first
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd ClaudeBeat && swift test --filter WeeklyBreakdownTests 2>&1 | tail -5`
Expected: `Executed 10 tests, with 0 failures`

- [ ] **Step 5: Run the whole suite**

Run: `cd ClaudeBeat && swift test 2>&1 | tail -5`
Expected: `Executed 62 tests, with 0 failures`

- [ ] **Step 6: Commit**

```bash
git add ClaudeBeat/ClaudeBeat/Models/WeeklyBreakdown.swift \
        ClaudeBeat/ClaudeBeatTests/WeeklyBreakdownTests.swift
git commit -m "feat: derive the weekly gauge list from limits

All models pinned first, scoped models sorted by label so they keep their
places across refreshes, and a seven_day fallback for when limits empties
out the way seven_day_* did."
```

---

### Task 4: Expose the list on `UsageState`

**Files:**
- Modify: `ClaudeBeat/ClaudeBeat/Models/UsageState.swift`
- Test: `ClaudeBeat/ClaudeBeatTests/UsageStateTests.swift`

**Interfaces:**
- Consumes: `WeeklyBreakdown.items(from:)` and `WeeklyItem` from Task 3.
- Produces: `UsageState.weeklyItems: [WeeklyItem]`, empty before the first response arrives.

- [ ] **Step 1: Write the failing tests**

Append to `ClaudeBeat/ClaudeBeatTests/UsageStateTests.swift`, inside the existing `UsageStateTests` class:

```swift
    func testWeeklyItems_noData() {
        let state = UsageState()
        XCTAssertTrue(state.weeklyItems.isEmpty)
    }

    func testWeeklyItems_fromLimits() {
        let state = UsageState()
        let reset = Date().addingTimeInterval(5 * 24 * 3600)
        state.update(with: UsageResponse(
            fiveHour: UsageBucket(utilization: 4.0, resetsAt: Date().addingTimeInterval(3600)),
            sevenDay: UsageBucket(utilization: 46.0, resetsAt: reset),
            extraUsage: nil,
            limits: [
                UsageLimit(kind: "weekly_all", percent: 46, resetsAt: reset),
                UsageLimit(
                    kind: "weekly_scoped",
                    percent: 82,
                    resetsAt: reset,
                    scope: LimitScope(model: LimitModel(displayName: "Fable"))
                )
            ]
        ))

        XCTAssertEqual(state.weeklyItems.map(\.label), ["All models", "Fable"])
        XCTAssertEqual(state.weeklyItems.map(\.utilization), [46, 82])
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd ClaudeBeat && swift test --filter UsageStateTests 2>&1 | tail -20`
Expected: compile failure — `value of type 'UsageState' has no member 'weeklyItems'`.

- [ ] **Step 3: Write the implementation**

In `ClaudeBeat/ClaudeBeat/Models/UsageState.swift`, add after the `weeklyResetTime` computed property (line 34):

```swift
    var weeklyItems: [WeeklyItem] {
        guard let response else { return [] }
        return WeeklyBreakdown.items(from: response)
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd ClaudeBeat && swift test 2>&1 | tail -5`
Expected: `Executed 64 tests, with 0 failures`

- [ ] **Step 5: Commit**

```bash
git add ClaudeBeat/ClaudeBeat/Models/UsageState.swift ClaudeBeat/ClaudeBeatTests/UsageStateTests.swift
git commit -m "feat: expose weeklyItems on UsageState"
```

---

### Task 5: Render the gauges

**Files:**
- Modify: `ClaudeBeat/ClaudeBeat/Views/WeeklyUsageView.swift`
- Modify: `ClaudeBeat/ClaudeBeat/Views/UsageGaugeView.swift`
- Modify: `ClaudeBeat/ClaudeBeat/Views/PopoverView.swift`
- Modify: `ClaudeBeat/ClaudeBeat/Models/UsageResponse.swift`
- Modify: `ClaudeBeat/ClaudeBeatTests/UsageResponseTests.swift`
- Modify: `ClaudeBeat/ClaudeBeatTests/UsageStateTests.swift`
- Modify: `README.md`

**Interfaces:**
- Consumes: `UsageState.weeklyItems` (Task 4), `WeeklyBreakdown.sharedResetDate(for:)` (Task 3).
- Produces: `WeeklyUsageView(items:)`; `UsageGaugeView(title:utilization:resetsAt:)` with the two chip parameters gone; `UsageResponse` without `sevenDayOpus` / `sevenDaySonnet`.

This task removes the last readers of `sevenDayOpus` / `sevenDaySonnet` and the fields themselves in one go — that is the only ordering in which the tree compiles at every commit.

There are no unit tests for the view changes — the project has no snapshot or view-test infrastructure, and adding it for one view is out of scope. Verification is a build plus a look at the running popover, in Steps 7-9.

- [ ] **Step 1: Replace `WeeklyUsageView`**

Replace the entire contents of `ClaudeBeat/ClaudeBeat/Views/WeeklyUsageView.swift`:

```swift
import SwiftUI

struct WeeklyUsageView: View {
    let items: [WeeklyItem]

    /// Three gauges is what fits across a 280pt popover; more wrap to another row.
    private static let itemsPerRow = 3

    private var rows: [[WeeklyItem]] {
        stride(from: 0, to: items.count, by: Self.itemsPerRow).map { start in
            Array(items[start..<min(start + Self.itemsPerRow, items.count)])
        }
    }

    private var sharedReset: Date? {
        WeeklyBreakdown.sharedResetDate(for: items)
    }

    var body: some View {
        VStack(spacing: 6) {
            Text("Weekly (7d)")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(alignment: .top, spacing: 8) {
                    ForEach(row) { item in
                        gauge(item, showsOwnReset: sharedReset == nil)
                    }
                }
            }

            // "Resets Thu 5:59 AM" needs ~90pt and a three-up column is ~82pt, so the
            // reset time lives under the section whenever the items agree on it.
            if let sharedReset {
                Text("Resets \(Self.resetFormatter.string(from: sharedReset))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private func gauge(_ item: WeeklyItem, showsOwnReset: Bool) -> some View {
        VStack(spacing: 4) {
            Text(item.label)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.tail)

            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.3), lineWidth: 4)
                Circle()
                    .trim(from: 0, to: item.utilization / 100)
                    .stroke(gaugeColor(item.utilization), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.5), value: item.utilization)
                Text("\(Int(item.utilization))%")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
            }
            .frame(width: 36, height: 36)

            if showsOwnReset, let resetsAt = item.resetsAt {
                Text(Self.resetFormatter.string(from: resetsAt))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func gaugeColor(_ utilization: Double) -> Color {
        switch utilization {
        case 0..<50: return .green
        case 50..<80: return .yellow
        default: return .red
        }
    }

    private static let resetFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE h:mm a"
        return f
    }()
}
```

The `Divider` that used to sit between the two gauges is gone: with a variable number of items spread by `maxWidth: .infinity`, the columns already read as separate, and a divider that appears only at certain counts looks like a bug.

- [ ] **Step 2: Delete the dead chip row from `UsageGaugeView`**

In `ClaudeBeat/ClaudeBeat/Views/UsageGaugeView.swift`, delete these two properties (lines 7-8):

```swift
    let opusUtilization: Double?
    let sonnetUtilization: Double?
```

and delete this block (lines 48-57):

```swift
            if let opus = opusUtilization, let sonnet = sonnetUtilization {
                HStack(spacing: 12) {
                    Label("Opus \(Int(opus))%", systemImage: "circle.fill")
                        .font(.caption2)
                        .foregroundStyle(.purple)
                    Label("Sonnet \(Int(sonnet))%", systemImage: "circle.fill")
                        .font(.caption2)
                        .foregroundStyle(.blue)
                }
            }
```

It required both values to be non-nil, which stopped happening when the API nulled those fields, and the Weekly section now shows the same numbers properly.

- [ ] **Step 3: Rewire `PopoverView`**

In `ClaudeBeat/ClaudeBeat/Views/PopoverView.swift`, replace `usageSections(_:)` (lines 37-61) with:

```swift
    @ViewBuilder
    private func usageSections(_ response: UsageResponse) -> some View {
        UsageGaugeView(
            title: "Session (5h)",
            utilization: response.fiveHour.utilization,
            resetsAt: response.fiveHour.resetsAt
        )

        Divider()

        WeeklyUsageView(items: usageState.weeklyItems)

        if let extra = response.extraUsage, extra.isEnabled {
            Divider()
            ExtraUsageView(
                usedCredits: extra.usedCredits ?? 0,
                monthlyLimit: extra.monthlyLimit ?? 0
            )
        }
    }
```

- [ ] **Step 4: Delete the dead fields from `UsageResponse`**

In `ClaudeBeat/ClaudeBeat/Models/UsageResponse.swift`, delete these two properties:

```swift
    let sevenDayOpus: UsageBucket?
    let sevenDaySonnet: UsageBucket?
```

these two `CodingKeys` cases:

```swift
        case sevenDayOpus = "seven_day_opus"
        case sevenDaySonnet = "seven_day_sonnet"
```

these two memberwise-init parameters and their assignments:

```swift
        sevenDayOpus: UsageBucket? = nil,
        sevenDaySonnet: UsageBucket? = nil,
```

```swift
        self.sevenDayOpus = sevenDayOpus
        self.sevenDaySonnet = sevenDaySonnet
```

and these two lines from `init(from:)`:

```swift
        sevenDayOpus = try container.decodeIfPresent(UsageBucket.self, forKey: .sevenDayOpus)
        sevenDaySonnet = try container.decodeIfPresent(UsageBucket.self, forKey: .sevenDaySonnet)
```

- [ ] **Step 5: Clean the removed fields out of the tests**

Run: `grep -rn "sevenDayOpus\|sevenDaySonnet" ClaudeBeat/ClaudeBeatTests/`

Every hit is either an assertion or an initializer argument. Delete these two assertions from `testDecodeFull` in `UsageResponseTests.swift`:

```swift
        XCTAssertEqual(response.sevenDayOpus?.utilization, 8.0)
        XCTAssertEqual(response.sevenDaySonnet?.utilization, 12.3)
```

and these two from `testDecodeMinimal`:

```swift
        XCTAssertNil(response.sevenDayOpus)
        XCTAssertNil(response.sevenDaySonnet)
```

In `UsageStateTests.swift`, drop the arguments. The multi-line form:

```swift
        state.update(with: UsageResponse(
            fiveHour: UsageBucket(utilization: 69.0, resetsAt: resetDate),
            sevenDay: UsageBucket(utilization: 15.0, resetsAt: Date().addingTimeInterval(7 * 24 * 3600)),
            sevenDayOpus: nil,
            sevenDaySonnet: nil,
            extraUsage: nil
        ))
```

becomes:

```swift
        state.update(with: UsageResponse(
            fiveHour: UsageBucket(utilization: 69.0, resetsAt: resetDate),
            sevenDay: UsageBucket(utilization: 15.0, resetsAt: Date().addingTimeInterval(7 * 24 * 3600)),
            extraUsage: nil
        ))
```

and the single-line form:

```swift
            sevenDayOpus: nil, sevenDaySonnet: nil, extraUsage: nil
```

becomes:

```swift
            extraUsage: nil
```

Also delete the `"seven_day_opus"` and `"seven_day_sonnet"` keys from the JSON literals in `UsageResponseTests.swift` (in `testDecodeFull` and in the null-tolerance test). Leaving them implies the app still reads those keys. Keep them in `UsageLimitTests.swift`'s captured payload — there they are evidence that the real response sends them as null.

- [ ] **Step 6: Update the README**

In `README.md` line 41, replace:

```
  - Weekly (7d) breakdown: All models + Sonnet only with individual reset times
```

with:

```
  - Weekly (7d) breakdown: All models plus a gauge per model the API reports (e.g. Fable), with a shared reset time
```

and line 122, replace:

```
- Weekly breakdown: All models + Sonnet only
```

with:

```
- Weekly breakdown: All models + a gauge per model the API reports
```

- [ ] **Step 7: Build the app**

Run: `cd ClaudeBeat && xcodebuild -project ClaudeBeat.xcodeproj -scheme ClaudeBeat -configuration Debug -derivedDataPath /tmp/claudebeat-dd build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

If the build fails with `cannot find 'WeeklyBreakdown' in scope` while `swift test` passes, the committed `.xcodeproj` has gone stale and does not include the new files. Regenerate it: `cd ClaudeBeat && xcodegen generate`, then rebuild.

- [ ] **Step 8: Run the whole suite**

Run: `cd ClaudeBeat && swift test 2>&1 | tail -5`
Expected: `Executed 64 tests, with 0 failures`

- [ ] **Step 9: Verify in the running app**

```bash
open -n /tmp/claudebeat-dd/Build/Products/Debug/ClaudeBeat.app
```

Click the menu bar item and confirm the Weekly (7d) section shows two gauges — "All models" and "Fable" — side by side, with one "Resets …" line beneath them, and that neither label nor percentage is clipped at 280pt. The Session gauge should have no Opus/Sonnet chips under it.

Then quit that instance: `pkill -f "claudebeat-dd.*ClaudeBeat"`

- [ ] **Step 10: Commit**

```bash
git add ClaudeBeat/ClaudeBeat/Views/WeeklyUsageView.swift \
        ClaudeBeat/ClaudeBeat/Views/UsageGaugeView.swift \
        ClaudeBeat/ClaudeBeat/Views/PopoverView.swift \
        ClaudeBeat/ClaudeBeat/Models/UsageResponse.swift \
        ClaudeBeat/ClaudeBeatTests/UsageResponseTests.swift \
        ClaudeBeat/ClaudeBeatTests/UsageStateTests.swift \
        README.md
git commit -m "feat: show a weekly gauge per model the API reports

Fable's weekly cap is the one that actually binds — 82% against 46% for all
models — and it had no gauge at all. The section now renders whatever
weekly limits come back, wrapping at three across, with the reset time
hoisted out of the columns since it does not fit in 82pt."
```

---

## Verification

After Task 5, the whole change is in place. Final check before opening a PR:

- [ ] `cd ClaudeBeat && swift test 2>&1 | tail -5` → `Executed 64 tests, with 0 failures`
- [ ] `git log --oneline master..HEAD` → 6 commits (spec + 5 tasks)
- [ ] `git status --short` → clean
