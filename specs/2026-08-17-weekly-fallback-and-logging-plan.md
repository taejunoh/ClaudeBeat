# Weekly Fallback and Off-Main Logging Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Keep the all-models gauge whenever the API omits `weekly_all`, and stop the raw-response log from blocking the main actor on every poll.

**Architecture:** Two independent changes. `WeeklyBreakdown.items(from:)` synthesizes the all-models item from `seven_day` whenever no `weekly_all` limit is present, which subsumes the existing all-or-nothing fallback and removes its guard. `UsageService`'s two log helpers become `nonisolated` and perform their file write inside a detached background task.

**Tech Stack:** Swift 5.10, SwiftUI, XCTest, SwiftPM (`swift test`) with an xcodegen-generated Xcode project for app builds.

**Spec:** `specs/2026-08-17-weekly-fallback-and-logging-design.md`

## Global Constraints

- Swift 5.10, macOS 14.0 deployment target. `UsageService` and `UsageState` are `@MainActor`; model types stay `Sendable`.
- The all-models row's id is `weekly_all` regardless of which source produced it, so SwiftUI does not treat a source flip as a new view.
- The raw-response log stays in release builds — field diagnosis is its purpose. It must not be wrapped in `#if DEBUG`.
- Both log files are overwritten (never appended) so they stay bounded.
- Logging is best-effort: a logging failure must never surface to the caller or mask the original error.
- Run tests with `swift test` from the `ClaudeBeat/` directory (the one containing `Package.swift`). Baseline before this plan: 92 tests, 0 failures.
- Commit after every task. Work happens on branch `feat/weekly-fallback-and-logging`.

## File Structure

| File | Responsibility |
|---|---|
| `ClaudeBeat/ClaudeBeat/Models/WeeklyBreakdown.swift` | **Modify.** Synthesize the all-models item when `weekly_all` is absent; drop the empty-list guard. |
| `ClaudeBeat/ClaudeBeat/Services/UsageService.swift` | **Modify.** Make both log helpers `nonisolated` and write off the main actor. |
| `ClaudeBeat/ClaudeBeatTests/WeeklyBreakdownTests.swift` | **Modify.** Tests for the per-limit fallback. |
| `ClaudeBeat/ClaudeBeatTests/NotificationManagerTests.swift` | **Modify.** Test that a synthesized all-models limit can alert. |

---

### Task 1: All-models falls back per limit, not all-or-nothing

**Files:**
- Modify: `ClaudeBeat/ClaudeBeat/Models/WeeklyBreakdown.swift`
- Test: `ClaudeBeat/ClaudeBeatTests/WeeklyBreakdownTests.swift`
- Test: `ClaudeBeat/ClaudeBeatTests/NotificationManagerTests.swift`

**Interfaces:**
- Consumes: `UsageResponse` (its `limits: [UsageLimit]` and non-optional `sevenDay: UsageBucket`), `UsageLimit`, `LimitScope`, `LimitModel`, `WeeklyItem`, `WeeklyBreakdown.allModelsLabel` — all already exist.
- Produces: no new API. `WeeklyBreakdown.items(from:)` keeps its signature and now always returns at least one item.

- [ ] **Step 1: Write the failing tests**

Append these to the existing `WeeklyBreakdownTests` class in `ClaudeBeat/ClaudeBeatTests/WeeklyBreakdownTests.swift`. The class already has a `weeklyReset` property and `response(limits:sevenDay:)` / `scoped(_:_:resetsAt:)` helpers — use them as the existing tests do:

```swift
    func testAllModelsIsSynthesizedFromSevenDayWhenWeeklyAllIsMissing() {
        // A response can carry scoped limits without the all-models one. The old rule only
        // fell back when the whole list was empty, so this dropped the all-models gauge
        // even though seven_day still had the number.
        let items = WeeklyBreakdown.items(from: response(limits: [scoped("Fable", 100)], sevenDay: 66))

        XCTAssertEqual(items.map(\.label), ["All models", "Fable"])
        XCTAssertEqual(items.first?.utilization, 66)
        XCTAssertEqual(items.first?.resetsAt, weeklyReset)
    }

    func testSynthesizedAllModelsUsesTheWeeklyAllId() {
        let items = WeeklyBreakdown.items(from: response(limits: [scoped("Fable", 100)], sevenDay: 66))

        // Same id whichever source produced the row, so a poll that flips between them
        // does not read as a different view to SwiftUI.
        XCTAssertEqual(items.first?.id, "weekly_all")
    }

    func testWeeklyAllWinsOverSevenDayWhenPresent() {
        let items = WeeklyBreakdown.items(from: response(
            limits: [UsageLimit(kind: "weekly_all", percent: 48, resetsAt: weeklyReset), scoped("Fable", 100)],
            sevenDay: 66
        ))

        XCTAssertEqual(items.first?.label, "All models")
        XCTAssertEqual(items.first?.utilization, 48)
        XCTAssertEqual(items.first?.id, "weekly_all")
    }

    func testNoLimitsStillProducesASingleAllModelsItem() {
        let items = WeeklyBreakdown.items(from: response(limits: [], sevenDay: 46))

        XCTAssertEqual(items.map(\.label), ["All models"])
        XCTAssertEqual(items.first?.utilization, 46)
        XCTAssertEqual(items.first?.id, "weekly_all")
    }
```

Then append this to the existing `NotificationManagerTests` class in `ClaudeBeat/ClaudeBeatTests/NotificationManagerTests.swift`, which already has a private `item(_:_:)` helper:

```swift
    func testSynthesizedAllModelsLimitCanAlert() throws {
        let manager = NotificationManager()
        manager.weeklyThreshold = 80
        manager.weeklyAlertsEnabled = true

        // No weekly_all in the response — the all-models figure comes from seven_day, and
        // it must still be able to cross the threshold.
        let response = UsageResponse(
            fiveHour: UsageBucket(utilization: 4, resetsAt: nil),
            sevenDay: UsageBucket(utilization: 91, resetsAt: nil),
            extraUsage: nil,
            limits: [
                UsageLimit(
                    kind: "weekly_scoped",
                    percent: 20,
                    scope: LimitScope(model: LimitModel(displayName: "Fable"))
                )
            ]
        )

        let sent = manager.weeklyAlertsToSend(for: WeeklyBreakdown.items(from: response))

        XCTAssertEqual(sent.map(\.label), ["All models"])
        XCTAssertEqual(
            NotificationManager.weeklyAlertBody(for: try XCTUnwrap(sent.first)),
            "All models at 91% of the 7-day limit"
        )
    }
```

Note that this last test is declared `throws` for the `XCTUnwrap`.

The `WeeklyBreakdownTests` helper is `response(limits: [UsageLimit], sevenDay: Double = 46.0)`, and it builds `sevenDay`'s bucket with `resetsAt: weeklyReset` — which is why the first test can assert `items.first?.resetsAt == weeklyReset`.

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd ClaudeBeat && swift test --filter "WeeklyBreakdownTests|NotificationManagerTests" 2>&1 | tail -25`
Expected: `testAllModelsIsSynthesizedFromSevenDayWhenWeeklyAllIsMissing` fails — the result is `["Fable"]` with no all-models row. `testSynthesizedAllModelsUsesTheWeeklyAllId` and `testNoLimitsStillProducesASingleAllModelsItem` fail on the id (`"seven_day"`). `testSynthesizedAllModelsLimitCanAlert` fails because no all-models item exists to alert on.

- [ ] **Step 3: Write the implementation**

In `ClaudeBeat/ClaudeBeat/Models/WeeklyBreakdown.swift`, replace the tail of `items(from:)` — the block that currently reads:

```swift
        let items = [allModels].compactMap { $0 } + scoped
        guard items.isEmpty else { return items }

        return [WeeklyItem(
            id: "seven_day",
            label: allModelsLabel,
            utilization: response.sevenDay.utilization,
            resetsAt: response.sevenDay.resetsAt
        )]
    }
```

with:

```swift
        // `weekly_all` can be missing while scoped limits are present. Synthesizing the
        // row from `seven_day` whenever it is absent — rather than only when the whole
        // list is empty — keeps the all-models gauge, the menu bar figure, and its alert
        // alive in that case. `sevenDay` is non-optional, so this row always exists.
        let allModelsItem = allModels ?? WeeklyItem(
            id: "weekly_all",
            label: allModelsLabel,
            utilization: response.sevenDay.utilization,
            resetsAt: response.sevenDay.resetsAt
        )

        return [allModelsItem] + scoped
    }
```

Leave the loop, the sort, and the scoped-id construction above it untouched.

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd ClaudeBeat && swift test 2>&1 | grep -E "Executed [0-9]+ tests" | tail -1`
Expected: `Executed 97 tests, with 0 failures` (92 baseline + 5 new).

No existing test asserts the synthesized row's id, so nothing else should need editing — `grep -rn '"seven_day"' ClaudeBeat/ClaudeBeatTests/` matches only a JSON literal inside a decoding fixture. Do not weaken any assertion to make a test pass.

- [ ] **Step 5: Commit**

```bash
git add ClaudeBeat/ClaudeBeat/Models/WeeklyBreakdown.swift \
        ClaudeBeat/ClaudeBeatTests/WeeklyBreakdownTests.swift \
        ClaudeBeat/ClaudeBeatTests/NotificationManagerTests.swift
git commit -F - <<'EOF'
fix: keep the all-models gauge when weekly_all is missing

The fallback only fired when the weekly list came out completely empty, so
a response carrying scoped limits but no weekly_all dropped the all-models
figure from the popover, the menu bar, and its alert — while seven_day
still carried it.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
```

---

### Task 2: Log off the main actor

**Files:**
- Modify: `ClaudeBeat/ClaudeBeat/Services/UsageService.swift`

**Interfaces:**
- Consumes: nothing from Task 1.
- Produces: nothing other code calls. `logRawResponse(endpoint:body:)`, `logDecodeFailure(endpoint:error:body:)` and `write(_:to:)` all stay `private static`; their call sites inside `fetchUsage()` are unchanged.

There are no unit tests for this task. All three functions are `private static` file I/O with every error swallowed by design, and after this change the write completes asynchronously, so a test could only observe it by polling the filesystem. No test covers them today and this does not make that worse. Verification is a build plus a run of the app confirming the log still updates.

- [ ] **Step 1: Make the two log helpers nonisolated and write off the main actor**

In `ClaudeBeat/ClaudeBeat/Services/UsageService.swift`, change the declaration line of `logRawResponse` from:

```swift
    private static func logRawResponse(endpoint: String, body: Data) {
```

to:

```swift
    nonisolated private static func logRawResponse(endpoint: String, body: Data) {
```

and wrap its `write(...)` call so the body becomes:

```swift
        let bodyString = String(data: body, encoding: .utf8) ?? "<non-UTF8 body>"
        let contents = """
        timestamp: \(Date())
        endpoint: \(endpoint)
        body: \(bodyString)
        """
        // UsageService is @MainActor and this runs on every poll (60s by default), so the
        // write is moved off the main actor. Both log files hold only the most recent
        // entry and are written atomically, so a race between writers is last-writer-wins,
        // which is the semantic these files already have.
        Task.detached(priority: .utility) { write(contents, to: "last-response.log") }
```

Apply the same two changes to `logDecodeFailure`: add `nonisolated` to its declaration, and replace its `write(...)` call with

```swift
        let bodyString = String(data: body, encoding: .utf8) ?? "<non-UTF8 body>"
        let contents = """
        timestamp: \(Date())
        endpoint: \(endpoint)
        error: \(String(describing: error))
        body: \(bodyString)
        """
        Task.detached(priority: .utility) { write(contents, to: "decode-failures.log") }
```

Finally, mark the shared writer `nonisolated` so it can be called from the detached task:

```swift
    nonisolated private static func write(_ contents: String, to fileName: String) {
```

Its body — the `logsDir` lookup, `createDirectory`, atomic `contents.write`, and the empty `catch` with its comment — stays exactly as it is.

- [ ] **Step 2: Build and run the tests**

Run: `cd ClaudeBeat && swift test 2>&1 | grep -E "Executed [0-9]+ tests" | tail -1`
Expected: `Executed 97 tests, with 0 failures`

If the compiler reports that `error` is not `Sendable` when captured by the detached task in `logDecodeFailure`, note that the closure captures only `contents` — a `String` — because the interpolation happens before the `Task.detached`. If you hit a capture error, it means the interpolation was left inside the closure; move it out as shown above rather than adding `@unchecked Sendable` anywhere.

- [ ] **Step 3: Build the app target**

Run: `cd ClaudeBeat && xcodebuild -project ClaudeBeat.xcodeproj -scheme ClaudeBeat -configuration Debug -derivedDataPath /tmp/claudebeat-dd build 2>&1 | tail -3`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Confirm the log still gets written**

The app writes `last-response.log` on every successful fetch, immediately on launch. Launch the freshly built copy, wait for its first poll, and confirm the file is fresh:

```bash
open -n /tmp/claudebeat-dd/Build/Products/Debug/ClaudeBeat.app
sleep 12
L=~/Library/Containers/com.claudebeat.macos/Data/Library/Logs/last-response.log
echo "age: $(( $(date +%s) - $(stat -f %m "$L") ))s"
pkill -f "claudebeat-dd.*ClaudeBeat"
```

Expected: an age under 20 seconds, proving the detached write still lands. If the installed copy of ClaudeBeat is running, quit it first with `osascript -e 'quit app "ClaudeBeat"'` so only the debug build writes the file, and relaunch it from `/Applications` when done.

- [ ] **Step 5: Commit**

```bash
git add ClaudeBeat/ClaudeBeat/Services/UsageService.swift
git commit -F - <<'EOF'
perf: write diagnostic logs off the main actor

UsageService is @MainActor and logs the raw response on every poll, so a
synchronous atomic file write sat on the main actor every 60 seconds in
release builds. The log stays — it is what makes API drift diagnosable in
the field — but the write now happens in a detached task.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
```

---

## Verification

After Task 2:

- [ ] `cd ClaudeBeat && swift test 2>&1 | grep -E "Executed [0-9]+ tests" | tail -1` → `Executed 97 tests, with 0 failures`
- [ ] `grep -n "#if DEBUG" ClaudeBeat/ClaudeBeat/Services/UsageService.swift` → no matches (the log must remain in release builds)
- [ ] `git log --oneline master..HEAD` → 3 commits (spec + 2 tasks)
- [ ] `git status --short` → clean
