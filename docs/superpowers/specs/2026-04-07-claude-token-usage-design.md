# Claude Token Usage — Mac Menu Bar App Design Spec

## Overview

A native macOS menu bar app (Swift + SwiftUI) that displays Claude token usage from claude.ai in real-time. Inspired by [iStat Menus](https://bjango.com/mac/istatmenus/) for its clean, data-dense UI style.

## Data Source

**Primary endpoint:** `GET https://claude.ai/api/organizations/{org_id}/usage`

Returns JSON with:
- `five_hour.utilization` — percentage (0-100), `five_hour.resets_at` — ISO 8601
- `seven_day.utilization` — percentage, `seven_day.resets_at`
- `seven_day_opus.utilization` — Max subscribers only
- `seven_day_sonnet.utilization` — Max subscribers only
- `extra_usage.is_enabled`, `extra_usage.monthly_limit`, `extra_usage.used_credits`

**Supporting endpoints:**
- `GET /api/organizations` — list orgs, get `org_id`

**Authentication (two options, user chooses):**
1. **Claude Code OAuth** (preferred) — read access token from macOS Keychain (service: `com.anthropic.claude-code`, stored by Claude Code CLI on login), sent as `Authorization: Bearer <token>` with `anthropic-beta: oauth-2025-04-20` header
2. **Session cookie** — user pastes `sessionKey` value from browser cookies for `claude.ai`, sent as `Cookie: sessionKey=<value>`

## Menu Bar

**Format:** `◉ Session: 69% · 2h`

- `◉` — small Claude/app icon
- `Session:` — label indicating this is 5-hour session usage
- `69%` — current 5-hour utilization percentage
- `2h` — time until 5-hour reset (shows `2h`, `45m`, `12m`, etc.)
- Color shifts: green (0-50%) → yellow (50-80%) → red (80-100%)
- Auth error / disconnected state: `◉ Session: -- · --`

## Popover (click menu bar to open)

Dark-themed panel (iStat Menus style) with three sections:

### 1. Current Session (5h)
- Circular or semi-circular gauge showing utilization percentage
- "Resets in 2h 14m" text
- Per-model breakdown: Opus %, Sonnet %

### 2. Weekly Limit (7d)
- Same gauge style showing 7-day utilization
- "Resets Apr 13" text
- Per-model breakdown

### 3. Extra Usage
- Credits used / monthly limit (e.g., $12 / $50)
- Progress bar
- Only shown if `extra_usage.is_enabled` is true

### Bottom Bar
- Settings gear icon
- "Last updated: 30s ago"
- Manual refresh button

## Settings Window

Separate preferences window with tabs:

### Authentication
- Toggle between OAuth (auto-detect from Keychain) and Session Cookie (paste field)
- Connection status indicator (green dot = connected, red = error)
- "Test Connection" button

### Display
- Menu bar format options (show/hide reset time, show/hide "Session:" label)
- Popover theme: auto / dark / light

### Alerts
- Configurable thresholds per metric:
  - 5h session: warn at ___% (default 80%)
  - 7d weekly: warn at ___% (default 80%)
  - Extra usage: warn at $___
- Toggle notifications on/off per metric
- Alert style: macOS system notification (`UNUserNotification`)

### General
- Polling interval: default 60 seconds, range 15s–5min
- Launch at login toggle
- About / version info

## Architecture

**Single-process SwiftUI menu bar app** (no main window, `LSUIElement`).

### Components

| Component | Responsibility |
|---|---|
| **MenuBarManager** | Renders `◉ Session: 69% · 2h` in menu bar, owns popover |
| **UsageService** | Async polling loop (default 60s), calls claude.ai API, publishes usage data via `@Observable` |
| **AuthManager** | Handles OAuth (Keychain read) + session cookie auth, token refresh |
| **NotificationManager** | Watches usage against thresholds, fires macOS notifications |
| **SettingsManager** | Persists preferences via `UserDefaults` / `@AppStorage` |

### Data Flow

```
AuthManager → UsageService (polls API every 60s) → @Observable state
                                                       ↓
                                               MenuBarManager (updates text)
                                               PopoverView (charts/gauges)
                                               NotificationManager (checks thresholds)
```

### Technical Details

- **Framework:** SwiftUI + Swift Charts
- **Menu bar:** `MenuBarExtra` with custom popover
- **Minimum target:** macOS 14 (Sonoma)
- **Concurrency:** Swift async/await for networking
- **Storage:** `UserDefaults` / `@AppStorage` for settings, Keychain for auth tokens
- **Notifications:** `UserNotifications` framework
- **No third-party dependencies** — all Apple frameworks
