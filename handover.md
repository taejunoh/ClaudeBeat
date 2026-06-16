# ClaudeBeat — Handover

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
- Credentials persisted to `UserDefaults` suite `com.claudebeat.macos`
- Quit button in popover, app doesn't quit when closing Settings
- Popover closes on click outside

**Auth (hybrid — a single web-session model):**
- **Embedded login (primary):** "Log in to Claude" opens an in-app `WKWebView` login window (`LoginWindowController`) sharing `WebSession.dataStore`. Works for email + code login.
- **Session-key paste (fallback):** for Google-SSO accounts (Google blocks sign-in inside embedded WebViews). The pasted `sessionKey` is injected into the shared `WKHTTPCookieStore` and persisted to the Keychain for re-injection on launch.
- OAuth was **removed** — it hit the same Cloudflare-gated `claude.ai/api` endpoints and could never work.

## Architecture

- **AppDelegate-based** (not SwiftUI `MenuBarExtra`) — needed because `MenuBarExtra` has a known bug where label text doesn't update
- Uses `NSStatusItem` + `NSPopover` directly for reliable menu bar text updates
- SwiftUI views hosted inside `NSHostingController` for the popover and settings
- `@Observable` pattern for state management (`UsageState`, `AuthManager`, `NotificationManager`)
- 2-second timer refreshes menu bar text from `UsageState`
- **Data transport via a hidden `WKWebView`** (`WebSession`, conforms to `UsageTransport`) — `claude.ai/api` now sits behind a Cloudflare *managed challenge* that blocks plain `URLSession` (HTTP 403). A real WebKit engine passes the challenge and carries `cf_clearance` + session cookies; `WebSession` issues an in-page `fetch()` via `callAsyncJavaScript`. `UsageService` (now `@MainActor`) depends on the `UsageTransport` protocol — production = `WebSession.shared`, tests = `FakeTransport`.
- **Menu bar uses `statusItem.button.attributedTitle`** (NOT custom `NSView` subviews, which stopped rendering on macOS 26 Tahoe's Liquid Glass menu bar). `UsageState.needsLogin` drives a "Log in" menu-bar state whose click opens the login window.

## Key Files

```
ClaudeBeat/
├── ClaudeBeatApp.swift          # App + AppDelegate, NSStatusItem, popover, onboarding
├── Models/
│   ├── UsageResponse.swift            # API response Codable models + JSONDecoder extension
│   └── UsageState.swift               # @Observable state with computed menu bar text
├── Services/
│   ├── UsageTransport.swift           # Transport protocol + TransportError + response classifier
│   ├── WebSession.swift               # Hidden WKWebView transport (passes Cloudflare); cookie injection + login probe
│   ├── AuthManager.swift              # Thin sessionKey (Keychain) holder + connection status
│   ├── UsageService.swift             # @MainActor polling loop over UsageTransport
│   └── NotificationManager.swift      # Threshold logic + UNUserNotification
├── Views/
│   ├── PopoverView.swift              # Main popover container
│   ├── UsageGaugeView.swift           # Circular gauge (48x48)
│   ├── WeeklyUsageView.swift          # Side-by-side All Models + Sonnet gauges
│   ├── ExtraUsageView.swift           # Credits progress bar (values in cents, displayed as dollars)
│   ├── StatusBarView.swift            # TopBarView (updated/refresh) + BottomBarView (settings/quit)
│   ├── OnboardingView.swift           # First-launch hybrid auth (embedded login + sessionKey fallback)
│   ├── LoginWebView.swift             # Embedded claude.ai login window (LoginWindowController)
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
cd ClaudeBeat && swift run
```
Note: Notifications won't work via `swift run` (no bundle identifier).

**Xcode (full .app bundle, ad-hoc):**
```bash
cd ClaudeBeat && xcodebuild -scheme ClaudeBeat -configuration Debug build CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO
```

**Release (notarized):**
```bash
cd ClaudeBeat && xcodebuild -scheme ClaudeBeat -configuration Release clean build \
  CODE_SIGN_IDENTITY="Developer ID Application: Taejun Oh (3BMF4LM6TM)" \
  DEVELOPMENT_TEAM="3BMF4LM6TM" ENABLE_HARDENED_RUNTIME=YES \
  OTHER_CODE_SIGN_FLAGS="--timestamp" CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO
# Then notarize:
ditto -c -k --keepParent build/Release/ClaudeBeat.app ClaudeBeat.zip
xcrun notarytool submit ClaudeBeat.zip --keychain-profile "notary-profile" --wait
xcrun stapler staple build/Release/ClaudeBeat.app
```

**Regenerate Xcode project (after adding/removing files):**
```bash
cd ClaudeBeat && xcodegen generate
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
- `UserDefaults.standard` writes to unpredictable domain in SPM builds — using named suite `com.claudebeat.macos`
- Paste (⌘V) doesn't work in text fields in SPM builds — added explicit "Paste" buttons
- **`claude.ai/api` now returns a Cloudflare *managed challenge* (HTTP 403, `cf-mitigated: challenge`, "Just a moment…" HTML) to plain HTTP clients** — regardless of cookie validity or User-Agent. All data fetches go through `WebSession`'s hidden `WKWebView`. **Do NOT reintroduce `URLSession` requests to `claude.ai/api`** — they will 403.

## Code Signing & Notarization

- **Certificate:** `Developer ID Application: Taejun Oh (3BMF4LM6TM)`
- **Bundle ID:** `com.claudebeat.macos` (changed from `com.claudebeat.app` to fix notification icon cache issue)
- **Entitlements:** App Sandbox (`true`) + Outgoing Network (`true`)
- **Hardened Runtime:** Enabled + Secure Timestamp
- **notarytool profile:** `notary-profile` (stored in Keychain via `xcrun notarytool store-credentials`)
- **AppIcon.icns:** Manually generated via `iconutil` (10 sizes, 16–1024px) in `Resources/` — the asset catalog compiler only generates a partial icns, which caused notification icons not to display

## Manual QA — WKWebView fetch (not covered by unit tests)

The `WKWebView` transport, Cloudflare pass, and login can't be unit-tested (need a real engine + network + account). After building the `.app`, walk:

- [ ] Cold launch with no stored login → onboarding window appears.
- [ ] "Log in to Claude" opens the login window; after email+code login it closes and real percentages appear within ~60s.
- [ ] Google-SSO account: the login window is blocked by Google → use "Use a session key instead", paste `sessionKey`, Connect → percentages appear.
- [ ] Quit and relaunch → still logged in (persistent `WKWebsiteDataStore`), no re-login needed.
- [ ] Cold launch shows numbers within a few seconds (Cloudflare challenge passes on first load).
- [ ] Force logout (revoke the session in a browser) → menu bar shows "Log in"; clicking it opens the login window; logging back in restores numbers.
- [ ] Toggle network off briefly → last value retained, recovers on the next poll.

## Known follow-ups (deferred from the WKWebView milestone)

- **Cold-start double-fetch of `/api/organizations`** — `setupServices` probes login via `/api/organizations`, then `UsageService` resolves the org id with a second identical request. Minor extra round-trip; could be collapsed by having the probe seed the service.
- **`logOut()` does not `stopPolling()`** — after logout the poll loop keeps running and re-sets `needsLogin` each cycle (harmless/self-healing; intentionally left so a later Settings "Save" picks up the new key without needing to restart polling).

(Resolved in-milestone: the Settings → Auth tab is now fully wired — status is derived live from `UsageState` ("Connected"/"Login required"/"Connecting…"), and Log in / Log out / Save all route through `AppDelegate`. The vestigial `AuthManager.connectionStatus` was removed.)

## What's Next

- Sparkle framework for auto-updates
- Distribute via DMG or Homebrew cask
