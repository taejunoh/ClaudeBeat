# Claude Token Usage

A native macOS menu bar app that monitors your Claude AI token usage in real-time.

![macOS](https://img.shields.io/badge/macOS-14%2B-blue)
![Swift](https://img.shields.io/badge/Swift-5.10-orange)

## Features

- **Menu bar display** — See your current usage at a glance: `5h: 82% · 2h 54m`
- **Three display modes** — Current Session (5h), Weekly Limit (7d), or Both
- **Popover dashboard** — Click to see detailed usage with circular gauges
  - Session (5h) utilization with reset countdown
  - Weekly (7d) breakdown: All models + Sonnet only with individual reset times
  - Extra usage credits ($used / $limit)
- **Session reset notification** — Get notified when your 5h session resets so you can get back to work
- **Threshold alerts** — macOS notifications when session, weekly, or extra usage hits your configured threshold
- **Secure credential storage** — Session cookie stored in macOS Keychain, not plaintext
- **Auto-refresh** — Polls every 60 seconds (configurable 15s–5min)
- **Launch at login** — Optional auto-start

## Download

[![Download](https://img.shields.io/badge/Download-v1.0.0-blue?style=for-the-badge)](https://github.com/taejunoh/claude-token-usage/releases/latest/download/ClaudeTokenUsage.zip)

1. Download the zip file
2. Unzip
3. Drag `ClaudeTokenUsage.app` to Applications
4. Open and follow the setup instructions

> Requires macOS 14 (Sonoma) or later.

## Build from Source

### Prerequisites

- [Xcode](https://developer.apple.com/xcode/)
- [xcodegen](https://github.com/yonaskolb/XcodeGen) (optional, for regenerating the project)

### Build & Run

```bash
# Clone the repo
git clone https://github.com/taejunoh/claude-token-usage.git
cd claude-token-usage/ClaudeTokenUsage

# Option 1: Build with Xcode (recommended — enables notifications)
open ClaudeTokenUsage.xcodeproj
# Press Cmd+R to build and run

# Option 2: Build with xcodebuild
xcodebuild -scheme ClaudeTokenUsage -configuration Debug build \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO

# Option 3: Build with Swift Package Manager (no notifications)
swift build && swift run
```

## Setup

On first launch, an onboarding window will appear:

1. Open [claude.ai](https://claude.ai) in your browser and log in
2. Open DevTools (Cmd+Opt+I) → Application tab
3. Sidebar → Cookies → `https://a.claude.ai`
4. Find `sessionKey` and copy its value
5. Click **Paste** in the app, then **Connect**

Your session key is securely stored in the macOS Keychain and persists across app restarts.

## Menu Bar Display

| Mode | Example |
|---|---|
| Current Session | `5h: 82% · 2h 54m` |
| Weekly Limit | `7d: 7% · Apr 14` |
| Both | `5h: 82% · 2h 54m` (top line) / `7d: 7% · Apr 14` (bottom line) |

## Settings

Access settings via the gear icon in the popover. Uses a sidebar layout:

| Tab | Options |
|---|---|
| **Auth** | Switch between OAuth (Claude Code) and Session Cookie, test connection |
| **Display** | Menu bar mode (Session / Weekly / Both), toggle reset time visibility |
| **Alerts** | Session reset notification, threshold alerts per metric (Session 5h, Weekly 7d, Extra Usage) |
| **General** | Polling interval (15s–5min), launch at login, version info |

## Architecture

```
ClaudeTokenUsage/
├── ClaudeTokenUsageApp.swift      # @MainActor AppDelegate + NSStatusItem + NSPopover
├── Models/
│   ├── UsageResponse.swift        # API response models (Codable)
│   └── UsageState.swift           # @MainActor @Observable app state
├── Services/
│   ├── AuthManager.swift          # OAuth + session cookie auth (Keychain storage)
│   ├── UsageService.swift         # API client + async polling loop
│   └── NotificationManager.swift  # @MainActor session reset + threshold alerts (persisted)
├── Views/
│   ├── PopoverView.swift          # Main popover container
│   ├── UsageGaugeView.swift       # Circular gauge component
│   ├── WeeklyUsageView.swift      # Weekly breakdown (All models + Sonnet)
│   ├── ExtraUsageView.swift       # Extra usage progress bar
│   ├── StatusBarView.swift        # Top bar (refresh) + bottom bar (settings, quit)
│   ├── OnboardingView.swift       # First-launch setup
│   └── Settings/
│       ├── SettingsView.swift     # Sidebar settings container
│       ├── AuthSettingsView.swift
│       ├── DisplaySettingsView.swift
│       ├── AlertSettingsView.swift
│       └── GeneralSettingsView.swift
└── Utilities/
    └── TimeFormatting.swift       # Reset time formatting (cached formatters)
```

## API

The app reads usage data from Claude's internal API:

```
GET https://claude.ai/api/organizations/{org_id}/usage
```

Returns 5-hour session utilization, 7-day weekly limits (all models + Sonnet), and extra usage credits.

## Security

- Session cookie is stored in macOS Keychain (not plaintext UserDefaults)
- Automatic migration from older plaintext storage on first launch
- OAuth tokens read from Claude Code's Keychain entry (read-only)

## Tech Stack

- **Swift + SwiftUI** — Native macOS app, macOS 14+
- **AppKit** — `NSStatusItem` for reliable menu bar updates, `NSPopover` for dashboard
- **Security** — macOS Keychain for credential storage
- **UserNotifications** — Session reset and threshold alerts
- **Swift Concurrency** — async/await with `@MainActor` for thread safety
- **No third-party dependencies**

## License

MIT
