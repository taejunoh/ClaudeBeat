# ClaudeBeat

<p align="center">A native macOS menu bar app that monitors your Claude AI token usage in real-time.</p>

<p align="center">
  <a href="https://claudebeat.com/">Website</a>
</p>

<p align="center">
  <a href="https://github.com/taejunoh/ClaudeBeat/releases/latest/download/ClaudeBeat.zip">
    <img src="https://img.shields.io/badge/%E2%AC%87%EF%B8%8F_Download-ClaudeBeat-E8845C?style=for-the-badge&logoColor=white" alt="Download" height="48">
  </a>
</p>
<p align="center">
  macOS 14+ &nbsp;·&nbsp; Verified by Apple &nbsp;·&nbsp; Just unzip and run
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-14%2B-blue" alt="macOS">
  <img src="https://img.shields.io/badge/Swift-5.10-orange" alt="Swift">
  <img src="https://img.shields.io/badge/Notarized-Apple-black?logo=apple" alt="Notarized">
  <img src="https://img.shields.io/badge/license-MIT-green" alt="License">
  <a href="https://github.com/taejunoh/ClaudeBeat/releases/latest"><img src="https://img.shields.io/github/v/release/taejunoh/ClaudeBeat" alt="Release"></a>
  <a href="https://github.com/taejunoh/ClaudeBeat/releases"><img src="https://img.shields.io/github/downloads/taejunoh/ClaudeBeat/total" alt="Downloads"></a>
</p>

## Screenshots

| Menu Bar | Popover Dashboard | Settings | Auth |
|---|---|---|---|
| ![Menu Bar](assets/menubar.png) | ![Popover](assets/popover.png) | ![Settings](assets/settings.png) | ![Auth](assets/auth.png) |

![Notification](assets/alert.png)

## Features

- **Menu bar display** — See your current usage at a glance: `5h: 82% · 2h 54m`
- **Three display modes** — Current Session (5h), Weekly Limit (7d), or Both
- **Popover dashboard** — Click to see detailed usage with circular gauges and last-updated timestamp
  - Session (5h) utilization with reset countdown
  - Weekly (7d) breakdown: All models + Sonnet only with individual reset times
  - Extra Usage credits as a horizontal bar ($used / $limit with %)
- **Session reset notification** — Get notified when your 5h session resets so you can get back to work
- **Threshold alerts** — macOS notifications when usage hits your configured threshold
  - Session (5h) and Weekly (7d): percentage slider (0–100%)
  - Extra Usage: dollar amount input ($)
- **In-app sign-in** — Log in to Claude in a built-in window; the session is stored in the macOS Keychain, never plaintext (session-key paste available as a Google sign-in fallback)
- **Auto-refresh** — Polls every 60 seconds (configurable 15s-5min)
- **Launch at login** — Optional auto-start

## Installation

### Homebrew (recommended)

```bash
brew install --cask taejunoh/tap/claudebeat
```

### Direct Download

Download from [GitHub Releases](https://github.com/taejunoh/ClaudeBeat/releases/latest), unzip, and drag to Applications.

## Getting Started

On first launch, an onboarding window appears with two ways to connect.

### Log in to Claude (recommended)

Click **Log in to Claude** and sign in to claude.ai in the window that opens. That's it — your session is stored securely and persists across restarts, with no cookie-copying.

> **Signing in with Google?** Google blocks its sign-in inside embedded windows, so use the session-key method below instead.

### Session key (Google sign-in fallback)

1. Open [claude.ai](https://claude.ai) in your browser and log in
2. Open DevTools (`Cmd+Opt+I`) → **Application** tab
3. Sidebar → **Cookies** → `https://a.claude.ai`
4. Find `sessionKey` and copy its value
5. In onboarding (or **Settings → Auth**), expand the session-key section, click **Paste**, then **Connect** / **Save**

Your session key is stored in the macOS Keychain and persists across app restarts.

## Menu Bar Display

| Mode | Example |
|---|---|
| Current Session | `5h: 82% · 2h 54m` |
| Weekly Limit | `7d: 7% · Apr 14` |
| Both | `5h: 82% · 2h 54m` (top) / `7d: 7% · Apr 14` (bottom) |

## Settings

Access settings via the gear icon in the popover. Uses a sidebar layout:

| Tab | Options |
|---|---|
| **Auth** | Connection status, **Log in** / **Log out**, and an optional session-key field for the Google sign-in fallback |
| **Display** | Menu bar mode (Session / Weekly / Both), toggle reset time visibility |
| **Alerts** | Session reset notification, threshold alerts — Session (5h) & Weekly (7d) as % slider (0–100%), Extra Usage as $ amount |
| **General** | Polling interval (15s-5min), launch at login, version info |

## What's New

### v1.0.5
- **Fixes "no numbers" on macOS 26 (Tahoe)** — menu bar text now renders via the button's title, compatible with the Liquid Glass menu bar
- **Works past claude.ai's Cloudflare check** — usage is fetched through a hidden WebKit view that passes the bot challenge (plain requests now get HTTP 403)
- **In-app "Log in to Claude"** — sign in directly, no more copying cookies (session-key paste kept as a Google sign-in fallback)
- Settings → Auth shows live connection status with Log in / Log out
- Removed the (non-functional) Claude Code OAuth option

### v1.0.0
- Real-time 5h session and 7d weekly usage display in menu bar
- Popover dashboard with circular gauges
- Weekly breakdown: All models + Sonnet only
- Extra usage tracking with dollar amounts
- Session reset notifications
- Configurable threshold alerts (session, weekly, extra usage)
- Secure Keychain credential storage
- Two auth methods: Session Cookie and Claude Code OAuth
- Three display modes: Session / Weekly / Both
- Customizable polling interval (15s-5min)
- Launch at login support

## Troubleshooting

### Menu bar shows "Log in" / usage stopped updating
Your claude.ai session expired or you were signed out. Click the **Log in** menu bar item (or **Settings → Auth → Log in to Claude**) and sign in again. If you use Google sign-in, paste a fresh `sessionKey` in Settings → Auth instead.

### Menu bar text not showing
If you only see a blank space in the menu bar:
- Wait a few seconds — on first launch the app loads claude.ai and the first data fetch takes a moment
- Click the menu bar item — if it says "Log in", sign in via the window that opens
- Make sure you're on the latest release (older builds don't render on macOS 26 Tahoe)

### Notifications not working
- Make sure you're running the `.app` bundle (not `swift run`) — notifications require a proper app bundle
- Check System Settings → Notifications → ClaudeBeat → ensure notifications are allowed
- Verify alert thresholds in Settings → Alerts

### App asks for Keychain password
This happens once when the app first accesses the Keychain. Click "Always Allow" to prevent future prompts.

### Extra Usage shows wrong amounts
The API returns values in cents. The app converts to dollars (e.g., 2629 cents → $26.29). If amounts look wrong, please [open an issue](https://github.com/taejunoh/ClaudeBeat/issues).


## Security

- Sign-in happens in a sandboxed WebKit view talking directly to claude.ai; cookies live in the app's own website data store
- The optional session key (Google fallback) is stored in the macOS Keychain, not plaintext
- No data is sent to any third-party server

## Tech Stack

- **Swift + SwiftUI** — Native macOS app, macOS 14+
- **AppKit** — `NSStatusItem` for reliable menu bar updates, `NSPopover` for dashboard
- **Security** — macOS Keychain for credential storage
- **UserNotifications** — Session reset and threshold alerts
- **Swift Concurrency** — async/await with `@MainActor` for thread safety
- **No third-party dependencies**

## License

MIT
