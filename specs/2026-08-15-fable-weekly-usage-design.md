# Fable weekly usage in the popover

Date: 2026-08-15

## Problem

The popover's Weekly (7d) section shows only "All models". The "Sonnet only" gauge it
used to show has silently disappeared, and there is no Fable figure at all — even though
Fable is the limit that actually binds: a captured response has All models at 46% while
Fable sits at 82% with `severity: "warning"` and `is_active: true`.

The cause is that the API stopped populating the fields the app reads.

## Evidence

Captured from `GET /api/organizations/{id}/usage` on 2026-08-15 (ids redacted):

```json
{
  "five_hour": { "utilization": 4.0, "resets_at": "2026-08-15T16:49:59.983468+00:00" },
  "seven_day": { "utilization": 46.0, "resets_at": "2026-08-20T09:59:59.983485+00:00" },

  "seven_day_oauth_apps": null,
  "seven_day_opus": null,
  "seven_day_sonnet": null,
  "seven_day_cowork": null,
  "seven_day_omelette": null,
  "tangelo": null,
  "iguana_necktie": null,
  "omelette_promotional": null,
  "nimbus_quill": { "utilization": 0.0, "resets_at": null },
  "cinder_cove": null,
  "amber_ladder": null,

  "limits": [
    { "kind": "session", "group": "session", "percent": 4, "severity": "normal",
      "resets_at": "2026-08-15T16:49:59.983468+00:00", "scope": null, "is_active": false },
    { "kind": "weekly_all", "group": "weekly", "percent": 46, "severity": "normal",
      "resets_at": "2026-08-20T09:59:59.983485+00:00", "scope": null, "is_active": false },
    { "kind": "weekly_scoped", "group": "weekly", "percent": 82, "severity": "warning",
      "resets_at": "2026-08-20T09:59:59.983652+00:00",
      "scope": { "model": { "id": "<redacted>", "display_name": "Fable" }, "surface": null },
      "is_active": true }
  ]
}
```

Three conclusions:

1. **Every `seven_day_*` field is null.** Decoding those keys — statically or dynamically —
   yields nothing. There is no `seven_day_fable` key to add.
2. **Per-model usage now lives in `limits[]`**, keyed by `kind`, with the display label
   supplied by the server at `scope.model.display_name`.
3. **The response carries unrecognized codename keys** (`tangelo`, `iguana_necktie`,
   `nimbus_quill`, `cinder_cove`, `amber_ladder`, `omelette_promotional`). They are
   presumed unreleased features. The app ignores them.

## Goals

- Show Fable's weekly utilization in the Weekly (7d) section.
- Generalize: render whatever scoped weekly limits the API returns, so the next model
  appears without an app update — and so a model going away degrades quietly.
- Survive the reverse drift: if `limits` disappears the way `seven_day_*` did, the popover
  keeps working.

## Non-goals

- Per-model alert thresholds. `NotificationManager` continues to watch `seven_day` only.
  Worth revisiting — Fable at 82% vs All models at 46% means alerts currently fire on the
  wrong signal — but it is a separate change with its own settings UI.
- Using the server's `severity` for gauge color. It is decoded but unused; mixing it with
  the app's own 50/80 thresholds would make the same number two colors in two places.
- The `session` entry in `limits[]`. Session and menu bar keep reading `five_hour`, which
  is still populated and agrees with it (4.0 vs 4). Narrower blast radius.

## Design

### Data model

`limits[]` decodes into a new type, reusing the existing `LossyArray` so one malformed
element drops itself instead of failing the whole response:

```swift
struct UsageLimit: Decodable, Sendable {
    let kind: String
    let percent: Double
    let severity: String?
    let resetsAt: Date?
    let scope: LimitScope?
    let isActive: Bool
}

struct LimitScope: Decodable, Sendable {
    let model: LimitModel?
}

struct LimitModel: Decodable, Sendable {
    let displayName: String?
}
```

`UsageResponse` gains `limits: [UsageLimit]`, decoded with `decodeIfPresent` and defaulting
to `[]`. The existing `fiveHour`, `sevenDay`, and `extraUsage` fields stay as they are.
`sevenDayOpus` and `sevenDaySonnet` are removed — they are dead.

Two decoding decisions the captured payload forces:

- **`scope.surface` is not declared.** It was null in the capture, so its real type is
  unknown; declaring it `String?` would fail the decode if it turns out to be an object.
  Nothing needs it, so it is left out.
- **`percent` decodes as `Double` via `decodeIfPresent ?? 0`.** It arrived as an integer,
  but `UsageBucket.utilization` was already burned once by a null, and the same tolerance
  costs nothing here.

### Selection and fallback

`UsageState` exposes the presentation list:

```swift
struct WeeklyItem: Identifiable {
    let id: String
    let label: String
    let utilization: Double
    let resetsAt: Date?
}
```

Built as:

1. `weekly_all` → label "All models"; every `weekly_scoped` → label from
   `scope.model.displayName`.
2. A `weekly_scoped` entry with no display name is dropped — an unlabeled gauge is noise.
3. Any other `kind` is ignored, so a new one cannot break the view.
4. **If step 1 produces nothing** (no `limits`, empty `limits`, or no weekly entries), fall
   back to a single item built from `sevenDay`. This is the current behavior, so a
   disappearing `limits` array returns the popover to exactly what it shows today.

### Ordering

Array order from the server is not treated as stable. "All models" is pinned first, and
scoped items follow sorted by label. Without this the gauges can reorder between refreshes.

### Layout

The Weekly section becomes a grid of at most 3 items per row, wrapping beyond that, inside
the fixed 280pt popover. At 3 columns each item gets roughly 82pt.

That width does not fit a reset string: `Resets Thu 5:59 AM` needs about 90pt at caption2.
So the reset time moves out of the item. **If every item's `resetsAt` matches when rounded
to the minute, one shared line is rendered under the section**; otherwise each item shows
its own, abbreviated.

Rounding to the minute is required, not cosmetic: in the capture, `weekly_all` and
`weekly_scoped` differ at the microsecond (`...983485` vs `...983652`) while being the
same reset. Exact comparison would always take the per-item branch.

### Cleanup

The Opus/Sonnet chip row in `UsageGaugeView` is removed. It renders only when both
utilizations are non-nil, which no longer happens, and the Weekly section now presents the
same information properly.

### Diagnostics

`UsageService` writes the raw body of every usage response to
`Library/Logs/last-response.log` (overwritten each time, so it stays bounded), alongside
the existing decode-failure log. This is what made the present diagnosis possible without
guessing at key names, and this endpoint has now drifted twice.

## Testing

`UsageResponseTests`:

- the captured payload decodes to weekly items `[All models 46, Fable 82]`
- `limits` absent → falls back to `seven_day`
- `limits` present but empty → falls back to `seven_day`
- unknown `kind` is dropped
- a malformed element is dropped while its siblings survive
- `weekly_scoped` without `scope.model.display_name` is dropped
- missing/null `percent` decodes as 0

`UsageStateTests`:

- scoped entries supplied in shuffled order produce identical output
- reset times differing only in microseconds collapse to a shared line
- reset times differing by minutes do not

Existing tests are updated for the removal of `sevenDayOpus` / `sevenDaySonnet`.

## Risks

- **`limits` is itself likely under A/B testing**, given the decoy keys sharing the
  response. The fallback path is the mitigation, and it is tested rather than assumed.
- **`scope.model.display_name` is a server-controlled string** rendered directly. It sets
  the gauge label, so a long name truncates rather than breaking layout.
- **The label says "Fable", not "Fable 5".** That is what the server sends; the app does not
  invent a version suffix that could go stale.
