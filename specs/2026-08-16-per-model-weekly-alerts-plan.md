# Per-Model Weekly Alerts Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make threshold alerts and the menu bar follow whichever weekly limit actually binds, naming the model when it is a per-model limit.

**Architecture:** One new derivation, `WeeklyBreakdown.bindingItem(in:)`, returns the highest item from the existing weekly gauge list. `UsageState` reads it for the menu bar and exposes the model's label separately. `NotificationManager` iterates every weekly item with a label-keyed latch so each limit alerts independently.

**Tech Stack:** Swift 5.10, SwiftUI, XCTest, SwiftPM (`swift test`) with an xcodegen-generated Xcode project for app builds.

**Spec:** `specs/2026-08-16-per-model-weekly-alerts-design.md`

## Global Constraints

- Swift 5.10, macOS 14.0 deployment target.
- Model types stay `Sendable`; `UsageState` and `NotificationManager` are `@MainActor @Observable`.
- One weekly threshold governs every weekly limit. No per-model thresholds, no per-model toggles, no new `UserDefaults` keys.
- The alert latch is keyed by the item's **label**, never by `WeeklyItem.id` — ids embed sorted position and shift when the server's set of models changes.
- Notification body format, exactly: `"<label> at <percent>% of the 7-day limit"` (e.g. `Fable at 86% of the 7-day limit`).
- Behavior with no `limits` in the response must be identical to today's.
- Run tests with `swift test` from the `ClaudeBeat/` directory (the one containing `Package.swift`). Baseline before this plan: 72 tests, 0 failures.
- Commit after every task. Work happens on branch `feat/per-model-weekly-alerts`.

## File Structure

| File | Responsibility |
|---|---|
| `ClaudeBeat/ClaudeBeat/Models/WeeklyBreakdown.swift` | **Modify.** Add `bindingItem(in:)` beside the list it selects from. |
| `ClaudeBeat/ClaudeBeat/Models/UsageState.swift` | **Modify.** Menu bar's weekly figures read the binding item; expose `weeklyModelLabel`. |
| `ClaudeBeat/ClaudeBeat/ClaudeBeatApp.swift` | **Modify.** Interpolate the model label into the `.weekly` and `.both` menu bar titles. |
| `ClaudeBeat/ClaudeBeat/Services/NotificationManager.swift` | **Modify.** Label-keyed latch; alert on every weekly limit. |
| `ClaudeBeat/ClaudeBeat/Views/Settings/AlertSettingsView.swift` | **Modify.** One line of copy stating the threshold covers per-model limits. |
| `ClaudeBeat/ClaudeBeatTests/WeeklyBreakdownTests.swift` | **Modify.** Tests for `bindingItem(in:)`. |
| `ClaudeBeat/ClaudeBeatTests/UsageStateTests.swift` | **Modify.** Tests for the menu bar figures and label. |
| `ClaudeBeat/ClaudeBeatTests/NotificationManagerTests.swift` | **Modify.** Tests for the per-limit latch and body copy. |

---

### Task 1: Select the binding weekly limit

**Files:**
- Modify: `ClaudeBeat/ClaudeBeat/Models/WeeklyBreakdown.swift`
- Test: `ClaudeBeat/ClaudeBeatTests/WeeklyBreakdownTests.swift`

**Interfaces:**
- Consumes: `WeeklyItem` (`id: String`, `label: String`, `utilization: Double`, `resetsAt: Date?`), `WeeklyBreakdown.items(from:)`, `WeeklyBreakdown.allModelsLabel` — all already exist.
- Produces: `WeeklyBreakdown.bindingItem(in items: [WeeklyItem]) -> WeeklyItem?`.

- [ ] **Step 1: Write the failing tests**

Append these to the existing `WeeklyBreakdownTests` class in `ClaudeBeat/ClaudeBeatTests/WeeklyBreakdownTests.swift`:

```swift
    func testBindingItemIsTheHighestUtilization() {
        let items = [
            WeeklyItem(id: "weekly_all", label: "All models", utilization: 48, resetsAt: nil),
            WeeklyItem(id: "weekly_scoped:0:Fable", label: "Fable", utilization: 86, resetsAt: nil)
        ]

        XCTAssertEqual(WeeklyBreakdown.bindingItem(in: items)?.label, "Fable")
        XCTAssertEqual(WeeklyBreakdown.bindingItem(in: items)?.utilization, 86)
    }

    func testBindingItemKeepsTheEarlierItemOnATie() {
        // "All models" is first in the list, so a tie must resolve to it rather than to
        // whichever element a nondeterministic max happens to return.
        let items = [
            WeeklyItem(id: "weekly_all", label: "All models", utilization: 80, resetsAt: nil),
            WeeklyItem(id: "weekly_scoped:0:Fable", label: "Fable", utilization: 80, resetsAt: nil)
        ]

        XCTAssertEqual(WeeklyBreakdown.bindingItem(in: items)?.label, "All models")
    }

    func testBindingItemIsNilForAnEmptyList() {
        XCTAssertNil(WeeklyBreakdown.bindingItem(in: []))
    }
```

Then extend the existing end-to-end test so the selection is covered against real decoded JSON too. `testEndToEndDecodedPayloadProducesWeeklyItems` already decodes the captured payload into a local `capturedJSON`; add these two assertions at the end of that test body, after its existing assertions:

```swift
        let binding = WeeklyBreakdown.bindingItem(in: items)
        XCTAssertEqual(binding?.label, "Fable")
        XCTAssertEqual(binding?.utilization, 82)
```

Use whatever local name that test already gives the derived list — it is `items` if the test follows the file's convention. Do **not** copy the payload into a new test: it already exists verbatim in two files, and a third copy is one more place to drift.

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd ClaudeBeat && swift test --filter WeeklyBreakdownTests 2>&1 | tail -20`
Expected: compile failure — `type 'WeeklyBreakdown' has no member 'bindingItem'`.

- [ ] **Step 3: Write the implementation**

Add to `ClaudeBeat/ClaudeBeat/Models/WeeklyBreakdown.swift`, inside `enum WeeklyBreakdown`, immediately after `items(from:)` and before `sharedResetDate(for:)`:

```swift
    /// The weekly limit that binds — the highest one. A per-model limit routinely sits far
    /// above the all-models total (Fable at 86% against 48%), and it is the one that will
    /// actually stop work, so it is what the menu bar shows and what alerts watch.
    ///
    /// Ties keep the earlier item, which puts "All models" ahead of any model. `max(by:)`
    /// does not specify which of several equal elements it returns, so it is not used here.
    static func bindingItem(in items: [WeeklyItem]) -> WeeklyItem? {
        items.reduce(into: nil as WeeklyItem?) { binding, candidate in
            guard let incumbent = binding else {
                binding = candidate
                return
            }
            if candidate.utilization > incumbent.utilization {
                binding = candidate
            }
        }
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd ClaudeBeat && swift test 2>&1 | grep -E "Executed [0-9]+ tests" | tail -1`
Expected: `Executed 75 tests, with 0 failures` (72 baseline + 3 new; the binding assertions added to the end-to-end test do not change the count).

- [ ] **Step 5: Commit**

```bash
git add ClaudeBeat/ClaudeBeat/Models/WeeklyBreakdown.swift \
        ClaudeBeat/ClaudeBeatTests/WeeklyBreakdownTests.swift
git commit -F - <<'EOF'
feat: select the binding weekly limit

The highest weekly limit is the one that stops work, and both the menu bar
and alerts need the same answer, so it is derived once next to the list it
selects from.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
```

---

### Task 2: Menu bar follows the binding limit

**Files:**
- Modify: `ClaudeBeat/ClaudeBeat/Models/UsageState.swift`
- Modify: `ClaudeBeat/ClaudeBeat/ClaudeBeatApp.swift`
- Test: `ClaudeBeat/ClaudeBeatTests/UsageStateTests.swift`

**Interfaces:**
- Consumes: `WeeklyBreakdown.bindingItem(in:)` from Task 1; `UsageState.weeklyItems` and `WeeklyBreakdown.allModelsLabel`, which already exist.
- Produces: `UsageState.weeklyModelLabel: String?` — nil when the all-models limit binds, the model's label otherwise. `weeklyPercentage` and `weeklyResetTime` keep their names and types (`String`) but now read the binding item.

- [ ] **Step 1: Write the failing tests**

Append these to the existing `UsageStateTests` class in `ClaudeBeat/ClaudeBeatTests/UsageStateTests.swift`:

```swift
    private func responseWithWeeklyLimits(
        sevenDay: Double,
        sevenDayResetsAt: Date,
        scoped: [(String, Double)]
    ) -> UsageResponse {
        var limits = [UsageLimit(kind: "weekly_all", percent: sevenDay, resetsAt: sevenDayResetsAt)]
        for (label, percent) in scoped {
            limits.append(UsageLimit(
                kind: "weekly_scoped",
                percent: percent,
                resetsAt: sevenDayResetsAt,
                scope: LimitScope(model: LimitModel(displayName: label))
            ))
        }
        return UsageResponse(
            fiveHour: UsageBucket(utilization: 4.0, resetsAt: Date().addingTimeInterval(3600)),
            sevenDay: UsageBucket(utilization: sevenDay, resetsAt: sevenDayResetsAt),
            extraUsage: nil,
            limits: limits
        )
    }

    func testWeeklyPercentageReadsTheBindingLimit() {
        let state = UsageState()
        state.update(with: responseWithWeeklyLimits(
            sevenDay: 48,
            sevenDayResetsAt: Date().addingTimeInterval(3 * 24 * 3600),
            scoped: [("Fable", 86)]
        ))

        XCTAssertEqual(state.weeklyPercentage, "86%")
    }

    func testWeeklyModelLabelNamesTheBindingModel() {
        let state = UsageState()
        state.update(with: responseWithWeeklyLimits(
            sevenDay: 48,
            sevenDayResetsAt: Date().addingTimeInterval(3 * 24 * 3600),
            scoped: [("Fable", 86)]
        ))

        XCTAssertEqual(state.weeklyModelLabel, "Fable")
    }

    func testWeeklyModelLabelIsNilWhenAllModelsBinds() {
        let state = UsageState()
        state.update(with: responseWithWeeklyLimits(
            sevenDay: 90,
            sevenDayResetsAt: Date().addingTimeInterval(3 * 24 * 3600),
            scoped: [("Fable", 20)]
        ))

        XCTAssertNil(state.weeklyModelLabel)
        XCTAssertEqual(state.weeklyPercentage, "90%")
    }

    func testWeeklyResetTimeReadsTheBindingLimit() {
        let state = UsageState()
        let allModelsReset = Date().addingTimeInterval(3 * 24 * 3600)
        let fableReset = Date().addingTimeInterval(2 * 3600 + 60)
        state.update(with: UsageResponse(
            fiveHour: UsageBucket(utilization: 4.0, resetsAt: Date().addingTimeInterval(3600)),
            sevenDay: UsageBucket(utilization: 48, resetsAt: allModelsReset),
            extraUsage: nil,
            limits: [
                UsageLimit(kind: "weekly_all", percent: 48, resetsAt: allModelsReset),
                UsageLimit(
                    kind: "weekly_scoped",
                    percent: 86,
                    resetsAt: fableReset,
                    scope: LimitScope(model: LimitModel(displayName: "Fable"))
                )
            ]
        ))

        // Fable binds, so its reset is the one shown — not the all-models reset.
        XCTAssertEqual(state.weeklyResetTime, "2h")
    }

    func testWeeklyFiguresFallBackToSevenDayWithoutLimits() {
        let state = UsageState()
        state.update(with: UsageResponse(
            fiveHour: UsageBucket(utilization: 4.0, resetsAt: Date().addingTimeInterval(3600)),
            sevenDay: UsageBucket(utilization: 44, resetsAt: Date().addingTimeInterval(2 * 3600 + 60)),
            extraUsage: nil
        ))

        XCTAssertEqual(state.weeklyPercentage, "44%")
        XCTAssertEqual(state.weeklyResetTime, "2h")
        XCTAssertNil(state.weeklyModelLabel)
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd ClaudeBeat && swift test --filter UsageStateTests 2>&1 | tail -20`
Expected: compile failure — `value of type 'UsageState' has no member 'weeklyModelLabel'`.

- [ ] **Step 3: Change the menu bar's weekly source**

In `ClaudeBeat/ClaudeBeat/Models/UsageState.swift`, replace the `weeklyPercentage` and `weeklyResetTime` properties:

```swift
    var weeklyPercentage: String {
        guard let utilization = response?.sevenDay.utilization else { return "--%"}
        return "\(Int(utilization))%"
    }

    var weeklyResetTime: String {
        guard let resetsAt = response?.sevenDay.resetsAt else { return "--" }
        return TimeFormatting.popoverString(until: resetsAt)
    }
```

with:

```swift
    // These read the binding limit rather than the flat seven_day bucket: a per-model
    // limit routinely binds first, and showing the total alone reassures the user at
    // exactly the wrong moment. With no `limits` in the response the list holds only the
    // seven_day fallback item, so these produce today's values unchanged.
    var weeklyPercentage: String {
        guard let utilization = weeklyBindingItem?.utilization else { return "--%"}
        return "\(Int(utilization))%"
    }

    var weeklyResetTime: String {
        guard let resetsAt = weeklyBindingItem?.resetsAt else { return "--" }
        return TimeFormatting.popoverString(until: resetsAt)
    }

    /// The model whose weekly limit binds, or nil when the all-models limit does. The menu
    /// bar appends it so a higher-than-expected percentage is attributable.
    var weeklyModelLabel: String? {
        guard let item = weeklyBindingItem, item.label != WeeklyBreakdown.allModelsLabel else {
            return nil
        }
        return item.label
    }

    private var weeklyBindingItem: WeeklyItem? {
        WeeklyBreakdown.bindingItem(in: weeklyItems)
    }
```

`weeklyBindingItem` must be declared after `weeklyItems` in the file, or simply anywhere in the same type — Swift does not require ordering. Place it directly below `weeklyModelLabel`.

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd ClaudeBeat && swift test 2>&1 | grep -E "Executed [0-9]+ tests" | tail -1`
Expected: `Executed 80 tests, with 0 failures` (75 + 5 new).

- [ ] **Step 5: Interpolate the label into the menu bar title**

In `ClaudeBeat/ClaudeBeat/ClaudeBeatApp.swift`, in the `.weekly` case, replace:

```swift
        case .weekly:
            var line = ["7d: \(usageState.weeklyPercentage)"]
            if showResetTime { line.append("· \(usageState.weeklyResetTime)") }
            button.attributedTitle = singleLineTitle(line.joined(separator: " "))
```

with:

```swift
        case .weekly:
            var line = ["7d: \(usageState.weeklyPercentage)"]
            if let model = usageState.weeklyModelLabel { line.append(model) }
            if showResetTime { line.append("· \(usageState.weeklyResetTime)") }
            button.attributedTitle = singleLineTitle(line.joined(separator: " "))
```

and in the `.both` case, replace:

```swift
            var bottom = ["7d: \(usageState.weeklyPercentage)"]
            if showResetTime { bottom.append("· \(usageState.weeklyResetTime)") }
```

with:

```swift
            var bottom = ["7d: \(usageState.weeklyPercentage)"]
            if let model = usageState.weeklyModelLabel { bottom.append(model) }
            if showResetTime { bottom.append("· \(usageState.weeklyResetTime)") }
```

Both produce `7d: 86% Fable · Aug 20` when a model binds, and are byte-identical to today's output when it does not.

- [ ] **Step 6: Build the app**

Run: `cd ClaudeBeat && xcodebuild -project ClaudeBeat.xcodeproj -scheme ClaudeBeat -configuration Debug -derivedDataPath /tmp/claudebeat-dd build 2>&1 | tail -3`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 7: Run the whole suite**

Run: `cd ClaudeBeat && swift test 2>&1 | grep -E "Executed [0-9]+ tests" | tail -1`
Expected: `Executed 80 tests, with 0 failures`

- [ ] **Step 8: Commit**

```bash
git add ClaudeBeat/ClaudeBeat/Models/UsageState.swift \
        ClaudeBeat/ClaudeBeat/ClaudeBeatApp.swift \
        ClaudeBeat/ClaudeBeatTests/UsageStateTests.swift
git commit -F - <<'EOF'
feat: menu bar shows the weekly limit that binds

It read the flat seven_day total, so it displayed 48% while Fable sat at
86%. The percentage now comes from the binding limit and carries the model
name when that limit is a model's, since a higher number with no label
would just look like a wrong total.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
```

---

### Task 3: Alerts watch every weekly limit

**Files:**
- Modify: `ClaudeBeat/ClaudeBeat/Services/NotificationManager.swift`
- Modify: `ClaudeBeat/ClaudeBeat/Views/Settings/AlertSettingsView.swift`
- Test: `ClaudeBeat/ClaudeBeatTests/NotificationManagerTests.swift`

**Interfaces:**
- Consumes: `WeeklyBreakdown.items(from:)`, `WeeklyItem` — both already exist.
- Produces:
  - `NotificationManager.shouldAlertForWeekly(utilization: Double, label: String) -> Bool`
  - `NotificationManager.markWeeklyAlerted(label: String)`
  - `NotificationManager.resetWeeklyAlertIfNeeded(utilization: Double, label: String)`
  - `NotificationManager.weeklyAlertsToSend(for items: [WeeklyItem]) -> [WeeklyItem]` — advances the latch and returns the items to notify about, in list order.
  - `NotificationManager.weeklyAlertBody(for item: WeeklyItem) -> String` (static).

`checkAndNotify(response:)` keeps its existing signature so `UsageService` is untouched.

- [ ] **Step 1: Write the failing tests**

In `ClaudeBeat/ClaudeBeatTests/NotificationManagerTests.swift`, replace the existing `testShouldAlertWeekly` — the three calls it makes all gain a label parameter — with the following, and append the rest to the same class:

```swift
    private func item(_ label: String, _ utilization: Double) -> WeeklyItem {
        WeeklyItem(id: "id:\(label)", label: label, utilization: utilization, resetsAt: nil)
    }

    func testShouldAlertWeekly() {
        let manager = NotificationManager()
        manager.weeklyThreshold = 80
        manager.weeklyAlertsEnabled = true

        XCTAssertTrue(manager.shouldAlertForWeekly(utilization: 85, label: "All models"))
        XCTAssertFalse(manager.shouldAlertForWeekly(utilization: 70, label: "All models"))
    }

    func testWeeklyAlertFiresOnceForAModelThenStaysQuiet() {
        let manager = NotificationManager()
        manager.weeklyThreshold = 80
        manager.weeklyAlertsEnabled = true

        let first = manager.weeklyAlertsToSend(for: [item("All models", 48), item("Fable", 86)])
        XCTAssertEqual(first.map(\.label), ["Fable"])

        let second = manager.weeklyAlertsToSend(for: [item("All models", 48), item("Fable", 87)])
        XCTAssertTrue(second.isEmpty)
    }

    func testWeeklyAlertRearmsAfterDroppingBelowThreshold() {
        let manager = NotificationManager()
        manager.weeklyThreshold = 80
        manager.weeklyAlertsEnabled = true

        _ = manager.weeklyAlertsToSend(for: [item("Fable", 86)])
        _ = manager.weeklyAlertsToSend(for: [item("Fable", 10)])

        let again = manager.weeklyAlertsToSend(for: [item("Fable", 86)])
        XCTAssertEqual(again.map(\.label), ["Fable"])
    }

    func testEachWeeklyLimitLatchesIndependently() {
        let manager = NotificationManager()
        manager.weeklyThreshold = 80
        manager.weeklyAlertsEnabled = true

        let sent = manager.weeklyAlertsToSend(for: [item("All models", 91), item("Fable", 86)])
        XCTAssertEqual(sent.map(\.label), ["All models", "Fable"])
    }

    func testANewModelDoesNotRefireExistingAlerts() {
        let manager = NotificationManager()
        manager.weeklyThreshold = 80
        manager.weeklyAlertsEnabled = true

        _ = manager.weeklyAlertsToSend(for: [item("All models", 91), item("Fable", 86)])

        // A model appearing shifts every WeeklyItem.id after it. Latching by label is what
        // keeps the already-alerted limits quiet through that.
        let sent = manager.weeklyAlertsToSend(for: [
            item("All models", 91), item("Aurora", 88), item("Fable", 86)
        ])
        XCTAssertEqual(sent.map(\.label), ["Aurora"])
    }

    func testWeeklyAlertsRespectTheEnableToggle() {
        let manager = NotificationManager()
        manager.weeklyThreshold = 80
        manager.weeklyAlertsEnabled = false

        XCTAssertTrue(manager.weeklyAlertsToSend(for: [item("Fable", 86)]).isEmpty)
    }

    func testWeeklyAlertBodyNamesTheLimit() {
        XCTAssertEqual(
            NotificationManager.weeklyAlertBody(for: item("Fable", 86)),
            "Fable at 86% of the 7-day limit"
        )
    }

    func testResponseWithoutLimitsStillAlertsOnTheSevenDayTotal() {
        let manager = NotificationManager()
        manager.weeklyThreshold = 80
        manager.weeklyAlertsEnabled = true

        // Covers the whole seam — response → items → alerts — for the case where the API
        // reports no `limits` at all, which must behave exactly as it did before.
        let response = UsageResponse(
            fiveHour: UsageBucket(utilization: 4, resetsAt: nil),
            sevenDay: UsageBucket(utilization: 91, resetsAt: nil)
        )

        let sent = manager.weeklyAlertsToSend(for: WeeklyBreakdown.items(from: response))

        XCTAssertEqual(sent.map(\.label), ["All models"])
        XCTAssertEqual(
            NotificationManager.weeklyAlertBody(for: try XCTUnwrap(sent.first)),
            "All models at 91% of the 7-day limit"
        )
    }
```

That last test must be declared `throws` for the `XCTUnwrap`: write its signature as `func testResponseWithoutLimitsStillAlertsOnTheSevenDayTotal() throws {`.

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd ClaudeBeat && swift test --filter NotificationManagerTests 2>&1 | tail -20`
Expected: compile failure — `extra argument 'label' in call` and `type 'NotificationManager' has no member 'weeklyAlertsToSend'`.

- [ ] **Step 3: Replace the weekly latch**

In `ClaudeBeat/ClaudeBeat/Services/NotificationManager.swift`, replace the stored property:

```swift
    private var weeklyAlerted: Bool = false
```

with:

```swift
    // Keyed by label, not by WeeklyItem.id: ids embed the item's sorted position, so one
    // new model shifts the ids after it and would silently re-arm those latches.
    private var weeklyAlerted: Set<String> = []
```

Then replace these three methods:

```swift
    func shouldAlertForWeekly(utilization: Double) -> Bool {
        guard weeklyAlertsEnabled, !weeklyAlerted else { return false }
        return utilization >= weeklyThreshold
    }
```

```swift
    func markWeeklyAlerted() { weeklyAlerted = true }
```

```swift
    func resetWeeklyAlertIfNeeded(utilization: Double) {
        if utilization < weeklyThreshold { weeklyAlerted = false }
    }
```

with:

```swift
    func shouldAlertForWeekly(utilization: Double, label: String) -> Bool {
        guard weeklyAlertsEnabled, !weeklyAlerted.contains(label) else { return false }
        return utilization >= weeklyThreshold
    }
```

```swift
    func markWeeklyAlerted(label: String) { weeklyAlerted.insert(label) }
```

```swift
    func resetWeeklyAlertIfNeeded(utilization: Double, label: String) {
        if utilization < weeklyThreshold { weeklyAlerted.remove(label) }
    }
```

Note that `markSessionAlerted()` and `resetSessionAlertIfNeeded(utilization:)` are separate methods on the same type and must be left exactly as they are.

- [ ] **Step 4: Add the per-limit decision and its copy**

Still in `NotificationManager.swift`, add these two methods immediately after `resetWeeklyAlertIfNeeded(utilization:label:)`:

```swift
    /// The weekly limits to notify about on this poll, in list order, advancing the latch.
    ///
    /// Every weekly limit is watched, not just the all-models total: a per-model limit
    /// routinely binds first — Fable at 86% against 48% for all models — and watching the
    /// total alone stays silent straight through it.
    func weeklyAlertsToSend(for items: [WeeklyItem]) -> [WeeklyItem] {
        var toSend: [WeeklyItem] = []
        for item in items {
            resetWeeklyAlertIfNeeded(utilization: item.utilization, label: item.label)
            if shouldAlertForWeekly(utilization: item.utilization, label: item.label) {
                toSend.append(item)
                markWeeklyAlerted(label: item.label)
            }
        }
        return toSend
    }

    static func weeklyAlertBody(for item: WeeklyItem) -> String {
        "\(item.label) at \(Int(item.utilization))% of the 7-day limit"
    }
```

- [ ] **Step 5: Rewire `checkAndNotify`**

In the same file, in `checkAndNotify(response:)`, replace the whole weekly block:

```swift
        // Weekly threshold
        let weeklyUtil = response.sevenDay.utilization
        resetWeeklyAlertIfNeeded(utilization: weeklyUtil)
        if shouldAlertForWeekly(utilization: weeklyUtil) {
            sendNotification(
                title: "Claude Weekly Usage",
                body: "7-day usage at \(Int(weeklyUtil))%"
            )
            markWeeklyAlerted()
        }
```

with:

```swift
        // Weekly thresholds, one per reported limit
        for item in weeklyAlertsToSend(for: WeeklyBreakdown.items(from: response)) {
            sendNotification(
                title: "Claude Weekly Usage",
                body: Self.weeklyAlertBody(for: item)
            )
        }
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `cd ClaudeBeat && swift test 2>&1 | grep -E "Executed [0-9]+ tests" | tail -1`
Expected: `Executed 88 tests, with 0 failures` (80 + 8 new).

- [ ] **Step 7: Say so in the settings copy**

In `ClaudeBeat/ClaudeBeat/Views/Settings/AlertSettingsView.swift`, in the `GroupBox("Weekly (7d)")`, add the explanatory line after the `HStack` holding the slider — that is, between the closing brace of the `HStack`'s `.disabled(...)` modifier and the closing brace of the `VStack`:

```swift
                    Text("Applies to every weekly limit, including per-model ones.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
```

The resulting group reads:

```swift
            GroupBox("Weekly (7d)") {
                VStack(alignment: .leading, spacing: 6) {
                    Toggle("Enable", isOn: $notificationManager.weeklyAlertsEnabled)
                    HStack {
                        Text("Warn at")
                        Slider(value: $notificationManager.weeklyThreshold, in: 0...100, step: 5)
                        Text("\(Int(notificationManager.weeklyThreshold))%")
                            .monospacedDigit()
                            .frame(width: 35)
                    }
                    .disabled(!notificationManager.weeklyAlertsEnabled)
                    Text("Applies to every weekly limit, including per-model ones.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
```

- [ ] **Step 8: Build the app**

Run: `cd ClaudeBeat && xcodebuild -project ClaudeBeat.xcodeproj -scheme ClaudeBeat -configuration Debug -derivedDataPath /tmp/claudebeat-dd build 2>&1 | tail -3`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 9: Commit**

```bash
git add ClaudeBeat/ClaudeBeat/Services/NotificationManager.swift \
        ClaudeBeat/ClaudeBeat/Views/Settings/AlertSettingsView.swift \
        ClaudeBeat/ClaudeBeatTests/NotificationManagerTests.swift
git commit -F - <<'EOF'
feat: alert on every weekly limit, not just the total

Alerts watched seven_day alone, so they stayed quiet with Fable at 86%
while the total sat at 48% — silent on the limit that actually stops work.
Each limit now latches independently, keyed by label rather than by
WeeklyItem.id, whose sorted position shifts when a model appears.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
```

---

## Verification

After Task 3:

- [ ] `cd ClaudeBeat && swift test 2>&1 | grep -E "Executed [0-9]+ tests" | tail -1` → `Executed 88 tests, with 0 failures`
- [ ] `git log --oneline master..HEAD` → 4 commits (spec + 3 tasks)
- [ ] `git status --short` → clean
- [ ] `grep -rn "shouldAlertForWeekly\|markWeeklyAlerted\|resetWeeklyAlertIfNeeded" ClaudeBeat/` → every call passes a label
