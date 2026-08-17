# All-models fallback per limit, and logging off the main actor

Date: 2026-08-17

Two follow-ups left over from the v1.1.0 reviews. They are unrelated to each other but
both small, both in code the same branch already touched.

## 1. The all-models gauge disappears when only `weekly_all` is missing

`WeeklyBreakdown.items(from:)` falls back to the flat `seven_day` bucket only when the
weekly list comes out **completely** empty:

```swift
let items = [allModels].compactMap { $0 } + scoped
guard items.isEmpty else { return items }
return [WeeklyItem(id: "seven_day", label: allModelsLabel, …)]
```

So a response carrying `weekly_scoped` but no `weekly_all` — an ordinary shape for an
endpoint that has already dropped fields twice — renders Fable alone and no all-models
figure at all, even though `seven_day` still carries it. The same gap reaches the menu bar
and the alerts, which read the same list.

### Design

Synthesize the all-models item from `seven_day` whenever `weekly_all` is absent, rather
than only when everything is absent:

```swift
let allModels = weeklyAllItem ?? WeeklyItem(
    id: "weekly_all",
    label: allModelsLabel,
    utilization: response.sevenDay.utilization,
    resetsAt: response.sevenDay.resetsAt
)
return [allModels] + scoped
```

`sevenDay` is non-optional on `UsageResponse`, so the all-models row always exists and the
`items.isEmpty` guard disappears. The old fallback case is subsumed: a response with no
`limits` at all still produces exactly one "All models" item with `seven_day`'s values,
which is what ships today.

**The id becomes `weekly_all` in both cases**, rather than `seven_day` for the synthesized
one. The row means the same thing to the viewer either way, and a stable id keeps SwiftUI
from treating it as a new view when a poll flips between the two sources.

This also changes alerts: an all-models limit that only `seven_day` reports can now cross
the threshold and notify. That is the intent — it is the same number the popover shows.

## 2. Raw-response logging blocks the main actor every poll

`UsageService` is `@MainActor`, and `logRawResponse` performs a synchronous atomic file
write on every successful fetch — by default every 60 seconds, in release builds. Before
v1.1.0 only rare decode failures wrote to disk.

### Design

Keep the log — it is what made the `limits` migration diagnosable from a real payload, and
removing it from release builds would blind exactly the case it exists for. Move the write
off the main actor instead:

```swift
nonisolated private static func logRawResponse(endpoint: String, body: Data) {
    Task.detached(priority: .utility) { write(…, to: "last-response.log") }
}
```

`logDecodeFailure` gets the same treatment, for consistency and because a decode failure
is the moment the app is least able to afford a stall.

Two consequences worth stating:

- **Writes are no longer ordered against the fetch that produced them.** Both files are
  written atomically and hold only the most recent entry, so concurrent writers race to
  last-writer-wins. For a "last response" log that is the correct semantic anyway.
- **A test cannot observe the write synchronously.** No test covers these functions today
  (they are `private static` file I/O with all errors swallowed), and this change does not
  make that worse.

## Non-goals

- Writing only when the body changed. Utilization numbers move on nearly every poll, so
  the skip would almost never trigger — the check would cost more than it saves.
- Removing the log from release builds. That was considered and rejected: field diagnosis
  is the point.
- Any change to how often the app polls.

## Testing

`WeeklyBreakdownTests`:
- `weekly_scoped` present, `weekly_all` absent → two items, "All models" first carrying
  `seven_day`'s utilization and reset, then the model
- no `limits` at all → exactly one "All models" item from `seven_day` (today's behavior,
  now reached by the general rule)
- `weekly_all` present → it wins; `seven_day` is not consulted
- the all-models item's id is `weekly_all` whichever source produced it

`NotificationManagerTests`:
- with `weekly_all` absent and `seven_day` above the threshold, the all-models limit alerts

No tests for the logging change, for the reason given above.

## Risks

- **Alert volume**: a response missing `weekly_all` now produces an all-models alert it
  previously could not. This is the intended fix, and the existing per-label latch still
  limits it to one notification per threshold crossing.
