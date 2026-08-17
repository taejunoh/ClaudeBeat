# Alerts and menu bar follow the binding weekly limit

Date: 2026-08-16

## Problem

The popover now shows a gauge per weekly limit the API reports, but the other two
surfaces still read the flat `seven_day` bucket. In a captured response that means the
menu bar displays `7d: 48%` and every threshold alert evaluates 48%, while Fable sits at
86% and is the limit that will actually stop work.

Both surfaces are reassuring at exactly the moment they should not be.

## Goals

- Threshold alerts fire on whichever weekly limit crosses, naming it.
- The menu bar's Weekly display shows the limit that binds, labeled when it is a model.
- Neither surface changes behavior when the API reports no per-model limits.

## Non-goals

- Per-model thresholds or per-model toggles in settings. One weekly threshold governs
  every weekly limit. Model names arrive from the server and change over time; keying
  settings and `UserDefaults` to them would leave dead keys behind and give newly
  appearing models no configured value.
- The popover's Weekly section. It already renders every limit.

## Design

### The binding limit

Both surfaces need the same thing — the highest weekly limit — so it is derived once,
next to the list it comes from:

```swift
extension WeeklyBreakdown {
    static func bindingItem(in items: [WeeklyItem]) -> WeeklyItem?
}
```

Highest `utilization` wins. Ties go to whichever comes first in `items`, which puts
"All models" ahead of any model. This is implemented as a `reduce` that keeps the
incumbent on ties rather than `max(by:)`, whose choice among equal elements is not
specified. Empty list returns nil.

When `limits` is absent the list holds only the `seven_day` fallback item, so the binding
item is that item and both surfaces behave exactly as they do today.

### Menu bar

`UsageState.weeklyPercentage` and `weeklyResetTime` keep their names but change source:
they now read the binding item rather than `response.sevenDay`. The names still describe
what they are — the weekly figure the menu bar shows — and renaming them would churn call
sites and tests without making anything clearer. **This is a deliberate semantic change
and is the fix, not a side effect.**

A new `UsageState.weeklyModelLabel: String?` returns nil when the binding item is
"All models" and the model's label otherwise. `ClaudeBeatApp` interpolates it in the
`.weekly` and `.both` display modes:

- binding is a model → `7d: 86% Fable · Thu 6:00 AM`
- binding is all-models → `7d: 48% · Thu 6:00 AM`, byte-identical to today

Width only grows in the case where the extra word is the information the user needs.

### Alerts

`checkAndNotify(response:)` keeps its signature and calls `WeeklyBreakdown.items(from:)`
internally, so `UsageService` is untouched.

The latch changes from `weeklyAlerted: Bool` to `weeklyAlerted: Set<String>`. Each weekly
limit must latch independently, or the first one to cross suppresses the alert for every
other one.

**The latch key is the item's label, not its `id`.** `WeeklyItem.id` embeds the item's
sorted position, so the appearance of one new model shifts the ids of the items after it,
which would silently re-arm their latches and fire duplicate alerts. Labels are stable
across that change and are what the notification names anyway.

Per weekly item, on each poll:

- at or above the threshold and not in the set → notify, insert the label
- below the threshold → remove the label, re-arming it

Notification body is uniform across limits: `"Fable at 86% of the 7-day limit"`, so the
alert always says which limit crossed. This replaces the current `"7-day usage at 46%"`,
which could only ever have meant one thing.

`shouldAlertForWeekly(utilization:)`, `markWeeklyAlerted()`, and
`resetWeeklyAlertIfNeeded(utilization:)` gain a label parameter.

Session, session-reset, and extra-usage alerts are untouched.

### Settings

No new toggle or threshold. The Weekly (7d) group gains one line of explanatory copy
stating that the threshold applies to every weekly limit, including per-model ones.

## Testing

`WeeklyBreakdownTests`:
- `bindingItem` picks the highest utilization
- ties resolve to "All models"
- empty list returns nil

`UsageStateTests`:
- `weeklyModelLabel` is nil when all-models binds, the label when a model binds
- `weeklyPercentage` and `weeklyResetTime` read the binding item
- with no `limits`, both fall back to `seven_day` and produce today's values

`NotificationManagerTests`:
- a model crossing the threshold produces one alert naming it
- a repeat poll at the same level produces none
- dropping below the threshold re-arms it
- two limits above the threshold produce two alerts
- an all-models-only response behaves as before
- the label-keyed latch survives a new model appearing in the list without re-firing
  existing alerts

## Risks

- **The menu bar number changes meaning for existing users.** Someone used to reading
  `7d:` as the all-models total will see a higher number once a model binds. The label is
  what disambiguates it, which is why the label is not optional in that case.
- **Notification volume rises with the number of weekly limits**, since each can alert
  once per threshold crossing. With today's two limits the ceiling is two per reset
  window.
