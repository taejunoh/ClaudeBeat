# Claude Token Usage

A native macOS menu bar app that monitors your Claude AI token usage in real-time.

![macOS](https://img.shields.io/badge/macOS-14%2B-blue)
![Swift](https://img.shields.io/badge/Swift-5.10-orange)
![License](https://img.shields.io/badge/license-MIT-green)

## Features

- **Menu bar display** — See your current usage at a glance: `5h: 82% · 2h 54m`
- **Three display modes** — Current Session (5h), Weekly Limit (7d), or Both
- **Popover dashboard** — Click to see detailed usage with circular gauges
  - Session (5h) utilization with reset countdown
  - Weekly (7d) breakdown: All models + Sonnet only
  - Extra usage credits ($used / $limit)
- **Configurable alerts** — macOS notifications when usage hits your threshold (default 80%)
- **Auto-refresh** — Polls every 60 seconds (configurable 15s–5min)
- **Launch at login** — Optional auto-start

## Screenshots

### Menu Bar
```
5h: 82% · 2h 54m
```

### Both Mode
```
5h: 82% · 2h 54m
7d: 7%  · Apr 14
```

## Installation

### Prerequisites
- macOS 14 (Sonoma) or later
- [Xcode](https://developer.apple.com/xcode/) (for building)
- [xcodegen](https://github.com/yonaskolb/XcodeGen) (optional, for regenerating the project)

### Build & Run

```bash
# Clone the repo
git clone https://github.com/taejunoh/claude-token-usage.git
cd claude-token-usage/ClaudeTokenUsage

# Option 1: Build with Xcode (recommended — enables notifications)
open ClaudeTokenUsage.xcodeproj
# Press Cmd+R to build and run

# Option 2: Build with Swift Package Manager
swift build
swift run
```

## Setup

On first launch, an onboarding window will appear:

1. Open [claude.ai](https://claude.ai) in your browser and log in
2. Open DevTools (Cmd+Opt+I) → Application tab
3. Sidebar → Cookies → `https://a.claude.ai`
4. Find `sessionKey` and copy its value
5. Click **Paste** in the app, then **Connect**

Your session key is saved locally and persists across app restarts.

## Settings

Access settings via the gear icon in the popover:

| Tab | Options |
|---|---|
| **Auth** | Switch between OAuth (Claude Code) and Session Cookie |
| **Display** | Choose what to show: Session / Weekly / Both, toggle reset time |
| **Alerts** | Enable/disable notifications, set thresholds per metric |
| **General** | Polling interval, launch at login |

## Architecture

```
ClaudeTokenUsage/
├── ClaudeTokenUsageApp.swift      # AppDelegate + NSStatusItem
├── Models/
│   ├── UsageResponse.swift        # API response models
│   └── UsageState.swift           # Observable app state
├── Services/
│   ├── AuthManager.swift          # OAuth + session cookie auth
│   ├── UsageService.swift         # API polling
│   └── NotificationManager.swift  # Alert thresholds
├── Views/
│   ├── PopoverView.swift          # Main popover
│   ├── UsageGaugeView.swift       # Circular gauge
│   ├── WeeklyUsageView.swift      # Weekly breakdown
│   ├── ExtraUsageView.swift       # Extra usage bar
│   ├── StatusBarView.swift        # Top/bottom bars
│   ├── OnboardingView.swift       # First-launch setup
│   └── Settings/                  # Settings tabs
└── Utilities/
    └── TimeFormatting.swift       # Reset time formatting
```

## API

The app reads usage data from Claude's internal API:

```
GET https://claude.ai/api/organizations/{org_id}/usage
```

Returns 5-hour session utilization, 7-day weekly limits (all models + Sonnet), and extra usage credits.

## Tech Stack

- **Swift + SwiftUI** — Native macOS app
- **AppKit** — `NSStatusItem` for reliable menu bar updates
- **NSPopover** — Click-to-open dashboard
- **UserNotifications** — Alert notifications
- **Swift Concurrency** — async/await for API polling
- **No third-party dependencies**

## License

MIT
