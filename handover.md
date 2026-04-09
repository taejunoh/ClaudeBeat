# Claude Token Usage — Handover

## What This Is

A native macOS menu bar app (Swift + SwiftUI) that monitors Claude AI token usage in real-time by polling `claude.ai/api/organizations/{org_id}/usage`.

## Current State

**Working features:**
- Menu bar displays usage as single-line (`5h: 56% · 4h 11m`) or two-line (both session + weekly)
- Popover on click shows: Session (5h) gauge, Weekly (7d) with All Models + Sonnet breakdown, Extra Usage progress bar
- Settings window with left sidebar tabs: Auth, Display, Alerts, General
- Onboarding window on first launch for session key setup
- Configurable alert thresholds (session, weekly, extra usage) with master "Enable alerts on refresh" toggle
- Polling every 60s (configurable 15s–5min)
- Credentials persisted to `UserDefaults` suite `com.claudetokenusage.macos`
- Quit button in popover, app doesn't quit when closing Settings
- Popover closes on click outside

**Auth methods:**
- Session cookie (paste `sessionKey` from `a.claude.ai` browser cookies) — primary
- OAuth (Claude Code CLI Keychain) — secondary, not tested

## Architecture

- **AppDelegate-based** (not SwiftUI `MenuBarExtra`) — needed because `MenuBarExtra` has a known bug where label text doesn't update
- Uses `NSStatusItem` + `NSPopover` directly for reliable menu bar text updates
- SwiftUI views hosted inside `NSHostingController` for the popover and settings
- `@Observable` pattern for state management (`UsageState`, `AuthManager`, `NotificationManager`)
- 2-second timer refreshes menu bar text from `UsageState`

## Key Files

```
ClaudeTokenUsage/
├── ClaudeTokenUsageApp.swift          # App + AppDelegate, NSStatusItem, popover, onboarding
├── Models/
│   ├── UsageResponse.swift            # API response Codable models + JSONDecoder extension
│   └── UsageState.swift               # @Observable state with computed menu bar text
├── Services/
│   ├── AuthManager.swift              # OAuth + session cookie, UserDefaults persistence
│   ├── UsageService.swift             # API polling loop
│   └── NotificationManager.swift      # Threshold logic + UNUserNotification
├── Views/
│   ├── PopoverView.swift              # Main popover container
│   ├── UsageGaugeView.swift           # Circular gauge (48x48)
│   ├── WeeklyUsageView.swift          # Side-by-side All Models + Sonnet gauges
│   ├── ExtraUsageView.swift           # Credits progress bar (values in cents, displayed as dollars)
│   ├── StatusBarView.swift            # TopBarView (updated/refresh) + BottomBarView (settings/quit)
│   ├── OnboardingView.swift           # First-launch session key setup
│   └── Settings/
│       ├── SettingsView.swift         # Left sidebar tab navigation
│       ├── AuthSettingsView.swift
│       ├── DisplaySettingsView.swift  # Session/Weekly/Both picker
│       ├── AlertSettingsView.swift    # Master toggle + per-metric thresholds
│       └── GeneralSettingsView.swift  # Polling interval, launch at login
├── Utilities/
│   └── TimeFormatting.swift           # "2h 14m", "45m", "Apr 10" formatting
```

## Build & Run

**SPM (development):**
```bash
cd ClaudeTokenUsage && swift run
```
Note: Notifications won't work via `swift run` (no bundle identifier).

**Xcode (full .app bundle, ad-hoc):**
```bash
cd ClaudeTokenUsage && xcodebuild -scheme ClaudeTokenUsage -configuration Debug build CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO
```

**Release (notarized):**
```bash
cd ClaudeTokenUsage && xcodebuild -scheme ClaudeTokenUsage -configuration Release clean build \
  CODE_SIGN_IDENTITY="Developer ID Application: Taejun Oh (3BMF4LM6TM)" \
  DEVELOPMENT_TEAM="3BMF4LM6TM" ENABLE_HARDENED_RUNTIME=YES \
  OTHER_CODE_SIGN_FLAGS="--timestamp" CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO
# Then notarize:
ditto -c -k --keepParent build/Release/ClaudeTokenUsage.app ClaudeTokenUsage.zip
xcrun notarytool submit ClaudeTokenUsage.zip --keychain-profile "notary-profile" --wait
xcrun stapler staple build/Release/ClaudeTokenUsage.app
```

**Regenerate Xcode project (after adding/removing files):**
```bash
cd ClaudeTokenUsage && xcodegen generate
```

## API Details

- **Base URL:** `https://claude.ai/api` (NOT `a.claude.ai` — that returns Cloudflare challenge)
- **Cookie domain:** `sessionKey` is set on `a.claude.ai` in browser, but works when sent to `claude.ai`
- **Endpoints:**
  - `GET /organizations` — returns list of orgs with UUIDs
  - `GET /organizations/{org_id}/usage` — returns utilization percentages + reset times
- **Extra usage values** (`usedCredits`, `monthlyLimit`) are in **cents** — divide by 100 for dollar display

## Known Issues / Gotchas

- `MenuBarExtra` label doesn't update reliably in SwiftUI — that's why we use `NSStatusItem` directly
- `UNUserNotificationCenter.current()` crashes in SPM builds (no bundle identifier) — guarded with `Bundle.main.bundleIdentifier != nil` check
- `UserDefaults.standard` writes to unpredictable domain in SPM builds — using named suite `com.claudetokenusage.macos`
- Paste (⌘V) doesn't work in text fields in SPM builds — added explicit "Paste" buttons
- `a.claude.ai` API calls hit Cloudflare challenge — must use `claude.ai` with `Accept: application/json` header

## Code Signing & Notarization

- **Certificate:** `Developer ID Application: Taejun Oh (3BMF4LM6TM)`
- **Bundle ID:** `com.claudetokenusage.macos` (changed from `com.claudetokenusage.app` to fix notification icon cache issue)
- **Entitlements:** App Sandbox (`true`) + Outgoing Network (`true`)
- **Hardened Runtime:** Enabled + Secure Timestamp
- **notarytool profile:** `notary-profile` (stored in Keychain via `xcrun notarytool store-credentials`)
- **AppIcon.icns:** Manually generated via `iconutil` (10 sizes, 16–1024px) in `Resources/` — the asset catalog compiler only generates a partial icns, which caused notification icons not to display

## What's Next

- Sparkle framework for auto-updates
- Distribute via DMG or Homebrew cask
