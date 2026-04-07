# Claude Token Usage — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a native macOS menu bar app that displays Claude token usage (5h session, 7d weekly, extra usage) with configurable alerts.

**Architecture:** Single-process SwiftUI menu bar app using `MenuBarExtra`. Polls `claude.ai/api/organizations/{org_id}/usage` on a timer, displays percentage + reset time in the menu bar, shows detailed charts in a popover, and fires macOS notifications at configurable thresholds. Auth via OAuth token (Keychain) or session cookie.

**Tech Stack:** Swift, SwiftUI, Swift Charts, UserNotifications, Security (Keychain), async/await

---

## File Structure

```
ClaudeTokenUsage/
├── ClaudeTokenUsageApp.swift          # App entry point, MenuBarExtra
├── Models/
│   ├── UsageResponse.swift            # API response models (Codable)
│   └── UsageState.swift               # App-level observable state
├── Services/
│   ├── AuthManager.swift              # OAuth + session cookie auth
│   ├── UsageService.swift             # API client + polling loop
│   └── NotificationManager.swift      # Threshold checks + UNUserNotification
├── Views/
│   ├── PopoverView.swift              # Main popover container
│   ├── UsageGaugeView.swift           # Circular gauge component
│   ├── ExtraUsageView.swift           # Extra usage section
│   ├── StatusBarView.swift            # Bottom bar (last updated, refresh, settings)
│   └── Settings/
│       ├── SettingsView.swift         # Settings window with tabs
│       ├── AuthSettingsView.swift     # Auth tab
│       ├── DisplaySettingsView.swift  # Display tab
│       ├── AlertSettingsView.swift    # Alert thresholds tab
│       └── GeneralSettingsView.swift  # General tab
├── Utilities/
│   └── TimeFormatting.swift           # Reset time formatting helpers
ClaudeTokenUsageTests/
├── UsageResponseTests.swift           # JSON decoding tests
├── UsageStateTests.swift              # State logic tests
├── AuthManagerTests.swift             # Auth header building tests
├── NotificationManagerTests.swift     # Threshold logic tests
└── TimeFormattingTests.swift          # Time formatting tests
```

---

## Task 0: Initialize Git Repository

- [ ] **Step 1: Initialize git repo and create .gitignore**

```bash
cd /Users/taejunoh/Desktop/LFG/claude-token-usage
git init
cat > .gitignore << 'EOF'
.DS_Store
.build/
*.xcodeproj/xcuserdata/
DerivedData/
.swiftpm/
EOF
git add .gitignore
git commit -m "chore: initialize repository with .gitignore"
```

---

## Task 1: Xcode Project Setup

**Files:**
- Create: Xcode project `ClaudeTokenUsage` (macOS app, SwiftUI lifecycle)
- Create: `ClaudeTokenUsage/ClaudeTokenUsageApp.swift`

- [ ] **Step 1: Create the Xcode project**

```bash
cd /Users/taejunoh/Desktop/LFG/claude-token-usage
mkdir -p ClaudeTokenUsage/ClaudeTokenUsage
mkdir -p ClaudeTokenUsage/ClaudeTokenUsageTests
```

Create `ClaudeTokenUsage/ClaudeTokenUsage.xcodeproj` using a Swift Package-based approach. Create a `Package.swift` at the root of `ClaudeTokenUsage/`:

```swift
// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "ClaudeTokenUsage",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "ClaudeTokenUsage",
            path: "ClaudeTokenUsage"
        ),
        .testTarget(
            name: "ClaudeTokenUsageTests",
            dependencies: ["ClaudeTokenUsage"],
            path: "ClaudeTokenUsageTests"
        ),
    ]
)
```

- [ ] **Step 2: Create minimal app entry point**

Create `ClaudeTokenUsage/ClaudeTokenUsage/ClaudeTokenUsageApp.swift`:

```swift
import SwiftUI

@main
struct ClaudeTokenUsageApp: App {
    var body: some Scene {
        MenuBarExtra("Claude Usage", systemImage: "circle.fill") {
            Text("Claude Token Usage")
            Divider()
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
    }
}
```

- [ ] **Step 3: Create Info.plist to hide dock icon**

Create `ClaudeTokenUsage/ClaudeTokenUsage/Info.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>LSUIElement</key>
    <true/>
</dict>
</plist>
```

- [ ] **Step 4: Build and verify**

```bash
cd /Users/taejunoh/Desktop/LFG/claude-token-usage/ClaudeTokenUsage
swift build
```

Expected: Build succeeds. App shows a circle icon in menu bar with "Claude Token Usage" text and Quit button.

- [ ] **Step 5: Commit**

```bash
git add ClaudeTokenUsage/
git commit -m "feat: scaffold Xcode project with minimal MenuBarExtra app"
```

---

## Task 2: API Response Models + JSON Decoding

**Files:**
- Create: `ClaudeTokenUsage/ClaudeTokenUsage/Models/UsageResponse.swift`
- Create: `ClaudeTokenUsage/ClaudeTokenUsageTests/UsageResponseTests.swift`

- [ ] **Step 1: Write the failing tests for JSON decoding**

Create `ClaudeTokenUsage/ClaudeTokenUsageTests/UsageResponseTests.swift`:

```swift
import XCTest
@testable import ClaudeTokenUsage

final class UsageResponseTests: XCTestCase {

    func testDecodeFull() throws {
        let json = """
        {
            "five_hour": {
                "utilization": 42.5,
                "resets_at": "2026-04-07T18:30:00.000Z"
            },
            "seven_day": {
                "utilization": 15.2,
                "resets_at": "2026-04-13T12:59:00.000Z"
            },
            "seven_day_opus": {
                "utilization": 8.0
            },
            "seven_day_sonnet": {
                "utilization": 12.3,
                "resets_at": "2026-04-13T12:59:00.000Z"
            },
            "extra_usage": {
                "is_enabled": true,
                "monthly_limit": 5000,
                "used_credits": 1200
            }
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder.apiDecoder.decode(UsageResponse.self, from: json)

        XCTAssertEqual(response.fiveHour.utilization, 42.5)
        XCTAssertNotNil(response.fiveHour.resetsAt)
        XCTAssertEqual(response.sevenDay.utilization, 15.2)
        XCTAssertEqual(response.sevenDayOpus?.utilization, 8.0)
        XCTAssertEqual(response.sevenDaySonnet?.utilization, 12.3)
        XCTAssertEqual(response.extraUsage?.isEnabled, true)
        XCTAssertEqual(response.extraUsage?.monthlyLimit, 5000)
        XCTAssertEqual(response.extraUsage?.usedCredits, 1200)
    }

    func testDecodeMinimal() throws {
        let json = """
        {
            "five_hour": {
                "utilization": 0.0,
                "resets_at": "2026-04-07T18:30:00.000Z"
            },
            "seven_day": {
                "utilization": 0.0,
                "resets_at": "2026-04-13T12:59:00.000Z"
            }
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder.apiDecoder.decode(UsageResponse.self, from: json)

        XCTAssertEqual(response.fiveHour.utilization, 0.0)
        XCTAssertNil(response.sevenDayOpus)
        XCTAssertNil(response.sevenDaySonnet)
        XCTAssertNil(response.extraUsage)
    }

    func testDecodeOrganizations() throws {
        let json = """
        [
            {
                "uuid": "d3bc1234-abcd-5678-ef90-000000000000",
                "name": "Personal"
            }
        ]
        """.data(using: .utf8)!

        let orgs = try JSONDecoder.apiDecoder.decode([Organization].self, from: json)

        XCTAssertEqual(orgs.count, 1)
        XCTAssertEqual(orgs[0].uuid, "d3bc1234-abcd-5678-ef90-000000000000")
        XCTAssertEqual(orgs[0].name, "Personal")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd /Users/taejunoh/Desktop/LFG/claude-token-usage/ClaudeTokenUsage
swift test --filter UsageResponseTests
```

Expected: FAIL — `UsageResponse` type not found.

- [ ] **Step 3: Implement the models**

Create `ClaudeTokenUsage/ClaudeTokenUsage/Models/UsageResponse.swift`:

```swift
import Foundation

struct UsageResponse: Codable, Sendable {
    let fiveHour: UsageBucket
    let sevenDay: UsageBucket
    let sevenDayOpus: UsageBucket?
    let sevenDaySonnet: UsageBucket?
    let extraUsage: ExtraUsage?

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
        case sevenDayOpus = "seven_day_opus"
        case sevenDaySonnet = "seven_day_sonnet"
        case extraUsage = "extra_usage"
    }
}

struct UsageBucket: Codable, Sendable {
    let utilization: Double
    let resetsAt: Date?

    enum CodingKeys: String, CodingKey {
        case utilization
        case resetsAt = "resets_at"
    }
}

struct ExtraUsage: Codable, Sendable {
    let isEnabled: Bool
    let monthlyLimit: Int
    let usedCredits: Int

    enum CodingKeys: String, CodingKey {
        case isEnabled = "is_enabled"
        case monthlyLimit = "monthly_limit"
        case usedCredits = "used_credits"
    }
}

struct Organization: Codable, Sendable {
    let uuid: String
    let name: String
}

extension JSONDecoder {
    static let apiDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateString = try container.decode(String.self)
            if let date = formatter.date(from: dateString) {
                return date
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Cannot decode date: \(dateString)"
            )
        }
        return decoder
    }()
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
cd /Users/taejunoh/Desktop/LFG/claude-token-usage/ClaudeTokenUsage
swift test --filter UsageResponseTests
```

Expected: All 3 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add ClaudeTokenUsage/ClaudeTokenUsage/Models/UsageResponse.swift ClaudeTokenUsage/ClaudeTokenUsageTests/UsageResponseTests.swift
git commit -m "feat: add API response models with JSON decoding"
```

---

## Task 3: Time Formatting Utilities

**Files:**
- Create: `ClaudeTokenUsage/ClaudeTokenUsage/Utilities/TimeFormatting.swift`
- Create: `ClaudeTokenUsage/ClaudeTokenUsageTests/TimeFormattingTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `ClaudeTokenUsage/ClaudeTokenUsageTests/TimeFormattingTests.swift`:

```swift
import XCTest
@testable import ClaudeTokenUsage

final class TimeFormattingTests: XCTestCase {

    func testMenuBarFormat_hours() {
        let future = Date().addingTimeInterval(2 * 3600 + 14 * 60)
        let result = TimeFormatting.menuBarString(until: future)
        XCTAssertEqual(result, "2h")
    }

    func testMenuBarFormat_minutes() {
        let future = Date().addingTimeInterval(45 * 60)
        let result = TimeFormatting.menuBarString(until: future)
        XCTAssertEqual(result, "45m")
    }

    func testMenuBarFormat_lessThanOneMinute() {
        let future = Date().addingTimeInterval(30)
        let result = TimeFormatting.menuBarString(until: future)
        XCTAssertEqual(result, "<1m")
    }

    func testMenuBarFormat_past() {
        let past = Date().addingTimeInterval(-60)
        let result = TimeFormatting.menuBarString(until: past)
        XCTAssertEqual(result, "now")
    }

    func testPopoverFormat_hoursAndMinutes() {
        let future = Date().addingTimeInterval(2 * 3600 + 14 * 60)
        let result = TimeFormatting.popoverString(until: future)
        XCTAssertEqual(result, "2h 14m")
    }

    func testPopoverFormat_minutesOnly() {
        let future = Date().addingTimeInterval(45 * 60 + 30)
        let result = TimeFormatting.popoverString(until: future)
        XCTAssertEqual(result, "45m")
    }

    func testPopoverFormat_dateForFarFuture() {
        let future = Date().addingTimeInterval(3 * 24 * 3600)
        let result = TimeFormatting.popoverString(until: future)
        // Should show a date like "Apr 10" instead of hours
        XCTAssertFalse(result.contains("h"))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
swift test --filter TimeFormattingTests
```

Expected: FAIL — `TimeFormatting` not found.

- [ ] **Step 3: Implement TimeFormatting**

Create `ClaudeTokenUsage/ClaudeTokenUsage/Utilities/TimeFormatting.swift`:

```swift
import Foundation

enum TimeFormatting {
    /// Compact format for menu bar: "2h", "45m", "<1m", "now"
    static func menuBarString(until date: Date) -> String {
        let seconds = date.timeIntervalSinceNow
        guard seconds > 0 else { return "now" }

        let totalMinutes = Int(seconds / 60)
        let hours = totalMinutes / 60

        if hours >= 1 {
            return "\(hours)h"
        } else if totalMinutes >= 1 {
            return "\(totalMinutes)m"
        } else {
            return "<1m"
        }
    }

    /// Detailed format for popover: "2h 14m", "45m", or "Apr 10"
    static func popoverString(until date: Date) -> String {
        let seconds = date.timeIntervalSinceNow
        guard seconds > 0 else { return "now" }

        let totalMinutes = Int(seconds / 60)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60

        // More than 24h: show date
        if hours >= 24 {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d"
            return formatter.string(from: date)
        }

        if hours >= 1 {
            return minutes > 0 ? "\(hours)h \(minutes)m" : "\(hours)h"
        } else {
            return "\(totalMinutes)m"
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
swift test --filter TimeFormattingTests
```

Expected: All 7 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add ClaudeTokenUsage/ClaudeTokenUsage/Utilities/TimeFormatting.swift ClaudeTokenUsage/ClaudeTokenUsageTests/TimeFormattingTests.swift
git commit -m "feat: add time formatting utilities for menu bar and popover"
```

---

## Task 4: UsageState (Observable App State)

**Files:**
- Create: `ClaudeTokenUsage/ClaudeTokenUsage/Models/UsageState.swift`
- Create: `ClaudeTokenUsage/ClaudeTokenUsageTests/UsageStateTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `ClaudeTokenUsage/ClaudeTokenUsageTests/UsageStateTests.swift`:

```swift
import XCTest
@testable import ClaudeTokenUsage

final class UsageStateTests: XCTestCase {

    func testMenuBarText_withData() {
        let state = UsageState()
        let resetDate = Date().addingTimeInterval(2 * 3600)
        state.update(with: UsageResponse(
            fiveHour: UsageBucket(utilization: 69.0, resetsAt: resetDate),
            sevenDay: UsageBucket(utilization: 15.0, resetsAt: Date().addingTimeInterval(7 * 24 * 3600)),
            sevenDayOpus: nil,
            sevenDaySonnet: nil,
            extraUsage: nil
        ))

        XCTAssertEqual(state.menuBarPercentage, "69%")
        XCTAssertEqual(state.menuBarResetTime, "2h")
        XCTAssertFalse(state.isError)
    }

    func testMenuBarText_noData() {
        let state = UsageState()
        XCTAssertEqual(state.menuBarPercentage, "--%")
        XCTAssertEqual(state.menuBarResetTime, "--")
    }

    func testColorLevel_green() {
        let state = UsageState()
        state.update(with: UsageResponse(
            fiveHour: UsageBucket(utilization: 30.0, resetsAt: Date().addingTimeInterval(3600)),
            sevenDay: UsageBucket(utilization: 10.0, resetsAt: Date().addingTimeInterval(7 * 24 * 3600)),
            sevenDayOpus: nil, sevenDaySonnet: nil, extraUsage: nil
        ))
        XCTAssertEqual(state.colorLevel, .green)
    }

    func testColorLevel_yellow() {
        let state = UsageState()
        state.update(with: UsageResponse(
            fiveHour: UsageBucket(utilization: 65.0, resetsAt: Date().addingTimeInterval(3600)),
            sevenDay: UsageBucket(utilization: 10.0, resetsAt: Date().addingTimeInterval(7 * 24 * 3600)),
            sevenDayOpus: nil, sevenDaySonnet: nil, extraUsage: nil
        ))
        XCTAssertEqual(state.colorLevel, .yellow)
    }

    func testColorLevel_red() {
        let state = UsageState()
        state.update(with: UsageResponse(
            fiveHour: UsageBucket(utilization: 90.0, resetsAt: Date().addingTimeInterval(3600)),
            sevenDay: UsageBucket(utilization: 10.0, resetsAt: Date().addingTimeInterval(7 * 24 * 3600)),
            sevenDayOpus: nil, sevenDaySonnet: nil, extraUsage: nil
        ))
        XCTAssertEqual(state.colorLevel, .red)
    }

    func testLastUpdated() {
        let state = UsageState()
        XCTAssertNil(state.lastUpdated)

        state.update(with: UsageResponse(
            fiveHour: UsageBucket(utilization: 50.0, resetsAt: Date().addingTimeInterval(3600)),
            sevenDay: UsageBucket(utilization: 10.0, resetsAt: Date().addingTimeInterval(7 * 24 * 3600)),
            sevenDayOpus: nil, sevenDaySonnet: nil, extraUsage: nil
        ))
        XCTAssertNotNil(state.lastUpdated)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
swift test --filter UsageStateTests
```

Expected: FAIL — `UsageState` not found.

- [ ] **Step 3: Implement UsageState**

Create `ClaudeTokenUsage/ClaudeTokenUsage/Models/UsageState.swift`:

```swift
import SwiftUI

enum ColorLevel: Sendable {
    case green, yellow, red, gray
}

@Observable
final class UsageState {
    private(set) var response: UsageResponse?
    private(set) var lastUpdated: Date?
    private(set) var isError: Bool = false
    private(set) var errorMessage: String?

    var menuBarPercentage: String {
        guard let utilization = response?.fiveHour.utilization else { return "--%"}
        return "\(Int(utilization))%"
    }

    var menuBarResetTime: String {
        guard let resetsAt = response?.fiveHour.resetsAt else { return "--" }
        return TimeFormatting.menuBarString(until: resetsAt)
    }

    var colorLevel: ColorLevel {
        guard let utilization = response?.fiveHour.utilization else { return .gray }
        switch utilization {
        case 0..<50: return .green
        case 50..<80: return .yellow
        default: return .red
        }
    }

    var statusColor: Color {
        switch colorLevel {
        case .green: return .green
        case .yellow: return .yellow
        case .red: return .red
        case .gray: return .gray
        }
    }

    func update(with response: UsageResponse) {
        self.response = response
        self.lastUpdated = Date()
        self.isError = false
        self.errorMessage = nil
    }

    func setError(_ message: String) {
        self.isError = true
        self.errorMessage = message
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
swift test --filter UsageStateTests
```

Expected: All 6 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add ClaudeTokenUsage/ClaudeTokenUsage/Models/UsageState.swift ClaudeTokenUsage/ClaudeTokenUsageTests/UsageStateTests.swift
git commit -m "feat: add observable UsageState with color levels and menu bar text"
```

---

## Task 5: AuthManager

**Files:**
- Create: `ClaudeTokenUsage/ClaudeTokenUsage/Services/AuthManager.swift`
- Create: `ClaudeTokenUsage/ClaudeTokenUsageTests/AuthManagerTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `ClaudeTokenUsage/ClaudeTokenUsageTests/AuthManagerTests.swift`:

```swift
import XCTest
@testable import ClaudeTokenUsage

final class AuthManagerTests: XCTestCase {

    func testSessionCookieHeaders() {
        let auth = AuthManager()
        auth.authMethod = .sessionCookie
        auth.sessionCookie = "sk-ant-abc123"

        let headers = auth.buildHeaders()

        XCTAssertEqual(headers["Cookie"], "sessionKey=sk-ant-abc123")
        XCTAssertNil(headers["Authorization"])
    }

    func testOAuthHeaders() {
        let auth = AuthManager()
        auth.authMethod = .oauth
        auth.oauthToken = "oauth-token-xyz"

        let headers = auth.buildHeaders()

        XCTAssertEqual(headers["Authorization"], "Bearer oauth-token-xyz")
        XCTAssertEqual(headers["anthropic-beta"], "oauth-2025-04-20")
        XCTAssertNil(headers["Cookie"])
    }

    func testNoCredentials() {
        let auth = AuthManager()
        auth.authMethod = .sessionCookie
        auth.sessionCookie = ""

        let headers = auth.buildHeaders()

        XCTAssertTrue(headers.isEmpty)
    }

    func testIsConfigured_sessionCookie() {
        let auth = AuthManager()
        auth.authMethod = .sessionCookie
        auth.sessionCookie = ""
        XCTAssertFalse(auth.isConfigured)

        auth.sessionCookie = "sk-ant-abc123"
        XCTAssertTrue(auth.isConfigured)
    }

    func testIsConfigured_oauth() {
        let auth = AuthManager()
        auth.authMethod = .oauth
        auth.oauthToken = ""
        XCTAssertFalse(auth.isConfigured)

        auth.oauthToken = "token"
        XCTAssertTrue(auth.isConfigured)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
swift test --filter AuthManagerTests
```

Expected: FAIL — `AuthManager` not found.

- [ ] **Step 3: Implement AuthManager**

Create `ClaudeTokenUsage/ClaudeTokenUsage/Services/AuthManager.swift`:

```swift
import Foundation
import Security

enum AuthMethod: String, CaseIterable, Sendable {
    case oauth = "OAuth (Claude Code)"
    case sessionCookie = "Session Cookie"
}

@Observable
final class AuthManager {
    var authMethod: AuthMethod = .oauth
    var sessionCookie: String = ""
    var oauthToken: String = ""
    var organizationId: String = ""
    var connectionStatus: ConnectionStatus = .unknown

    enum ConnectionStatus: Equatable {
        case unknown, connected, error(String)
    }

    var isConfigured: Bool {
        switch authMethod {
        case .oauth:
            return !oauthToken.isEmpty
        case .sessionCookie:
            return !sessionCookie.isEmpty
        }
    }

    func buildHeaders() -> [String: String] {
        switch authMethod {
        case .oauth:
            guard !oauthToken.isEmpty else { return [:] }
            return [
                "Authorization": "Bearer \(oauthToken)",
                "anthropic-beta": "oauth-2025-04-20"
            ]
        case .sessionCookie:
            guard !sessionCookie.isEmpty else { return [:] }
            return [
                "Cookie": "sessionKey=\(sessionCookie)"
            ]
        }
    }

    func loadOAuthTokenFromKeychain() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.anthropic.claude-code",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecSuccess, let data = result as? Data,
           let token = String(data: data, encoding: .utf8) {
            oauthToken = token
        }
    }

    func fetchOrganizationId() async throws {
        guard isConfigured else { return }

        var request = URLRequest(url: URL(string: "https://claude.ai/api/organizations")!)
        for (key, value) in buildHeaders() {
            request.setValue(value, forHTTPHeaderField: key)
        }

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            connectionStatus = .error("Failed to fetch organizations")
            throw URLError(.badServerResponse)
        }

        let orgs = try JSONDecoder.apiDecoder.decode([Organization].self, from: data)
        if let firstOrg = orgs.first {
            organizationId = firstOrg.uuid
            connectionStatus = .connected
        } else {
            connectionStatus = .error("No organizations found")
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
swift test --filter AuthManagerTests
```

Expected: All 5 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add ClaudeTokenUsage/ClaudeTokenUsage/Services/AuthManager.swift ClaudeTokenUsage/ClaudeTokenUsageTests/AuthManagerTests.swift
git commit -m "feat: add AuthManager with OAuth and session cookie support"
```

---

## Task 6: UsageService (API Client + Polling)

**Files:**
- Create: `ClaudeTokenUsage/ClaudeTokenUsage/Services/UsageService.swift`

- [ ] **Step 1: Implement UsageService**

Create `ClaudeTokenUsage/ClaudeTokenUsage/Services/UsageService.swift`:

```swift
import Foundation

@Observable
final class UsageService {
    private let authManager: AuthManager
    private let usageState: UsageState
    private var pollingTask: Task<Void, Never>?

    var pollingInterval: TimeInterval = 60

    init(authManager: AuthManager, usageState: UsageState) {
        self.authManager = authManager
        self.usageState = usageState
    }

    func fetchUsage() async {
        guard authManager.isConfigured, !authManager.organizationId.isEmpty else {
            usageState.setError("Not authenticated")
            return
        }

        let urlString = "https://claude.ai/api/organizations/\(authManager.organizationId)/usage"
        guard let url = URL(string: urlString) else {
            usageState.setError("Invalid URL")
            return
        }

        var request = URLRequest(url: url)
        for (key, value) in authManager.buildHeaders() {
            request.setValue(value, forHTTPHeaderField: key)
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                usageState.setError("HTTP \(code)")
                return
            }

            let usageResponse = try JSONDecoder.apiDecoder.decode(UsageResponse.self, from: data)
            usageState.update(with: usageResponse)
        } catch {
            usageState.setError(error.localizedDescription)
        }
    }

    func startPolling() {
        stopPolling()
        pollingTask = Task {
            while !Task.isCancelled {
                await fetchUsage()
                try? await Task.sleep(for: .seconds(pollingInterval))
            }
        }
    }

    func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }
}
```

- [ ] **Step 2: Build to verify compilation**

```bash
swift build
```

Expected: Build succeeds.

- [ ] **Step 3: Commit**

```bash
git add ClaudeTokenUsage/ClaudeTokenUsage/Services/UsageService.swift
git commit -m "feat: add UsageService with API polling loop"
```

---

## Task 7: NotificationManager

**Files:**
- Create: `ClaudeTokenUsage/ClaudeTokenUsage/Services/NotificationManager.swift`
- Create: `ClaudeTokenUsage/ClaudeTokenUsageTests/NotificationManagerTests.swift`

- [ ] **Step 1: Write the failing tests for threshold logic**

Create `ClaudeTokenUsage/ClaudeTokenUsageTests/NotificationManagerTests.swift`:

```swift
import XCTest
@testable import ClaudeTokenUsage

final class NotificationManagerTests: XCTestCase {

    func testShouldAlert_belowThreshold() {
        let manager = NotificationManager()
        manager.sessionThreshold = 80
        manager.sessionAlertsEnabled = true

        let result = manager.shouldAlertForSession(utilization: 70)
        XCTAssertFalse(result)
    }

    func testShouldAlert_atThreshold() {
        let manager = NotificationManager()
        manager.sessionThreshold = 80
        manager.sessionAlertsEnabled = true

        let result = manager.shouldAlertForSession(utilization: 80)
        XCTAssertTrue(result)
    }

    func testShouldAlert_aboveThreshold() {
        let manager = NotificationManager()
        manager.sessionThreshold = 80
        manager.sessionAlertsEnabled = true

        let result = manager.shouldAlertForSession(utilization: 90)
        XCTAssertTrue(result)
    }

    func testShouldAlert_disabled() {
        let manager = NotificationManager()
        manager.sessionThreshold = 80
        manager.sessionAlertsEnabled = false

        let result = manager.shouldAlertForSession(utilization: 90)
        XCTAssertFalse(result)
    }

    func testShouldAlert_noRepeatUntilReset() {
        let manager = NotificationManager()
        manager.sessionThreshold = 80
        manager.sessionAlertsEnabled = true

        // First time crossing threshold → alert
        XCTAssertTrue(manager.shouldAlertForSession(utilization: 85))
        manager.markSessionAlerted()

        // Still above → no repeat
        XCTAssertFalse(manager.shouldAlertForSession(utilization: 90))

        // Drops below → reset
        manager.resetSessionAlertIfNeeded(utilization: 50)
        XCTAssertTrue(manager.shouldAlertForSession(utilization: 85))
    }

    func testShouldAlertWeekly() {
        let manager = NotificationManager()
        manager.weeklyThreshold = 80
        manager.weeklyAlertsEnabled = true

        XCTAssertTrue(manager.shouldAlertForWeekly(utilization: 85))
        XCTAssertFalse(manager.shouldAlertForWeekly(utilization: 70))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
swift test --filter NotificationManagerTests
```

Expected: FAIL — `NotificationManager` not found.

- [ ] **Step 3: Implement NotificationManager**

Create `ClaudeTokenUsage/ClaudeTokenUsage/Services/NotificationManager.swift`:

```swift
import Foundation
import UserNotifications

@Observable
final class NotificationManager {
    var sessionThreshold: Double = 80
    var weeklyThreshold: Double = 80
    var extraUsageThreshold: Double = 40
    var sessionAlertsEnabled: Bool = true
    var weeklyAlertsEnabled: Bool = true
    var extraUsageAlertsEnabled: Bool = true

    private var sessionAlerted: Bool = false
    private var weeklyAlerted: Bool = false

    func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func shouldAlertForSession(utilization: Double) -> Bool {
        guard sessionAlertsEnabled, !sessionAlerted else { return false }
        return utilization >= sessionThreshold
    }

    func shouldAlertForWeekly(utilization: Double) -> Bool {
        guard weeklyAlertsEnabled, !weeklyAlerted else { return false }
        return utilization >= weeklyThreshold
    }

    func markSessionAlerted() {
        sessionAlerted = true
    }

    func markWeeklyAlerted() {
        weeklyAlerted = true
    }

    func resetSessionAlertIfNeeded(utilization: Double) {
        if utilization < sessionThreshold {
            sessionAlerted = false
        }
    }

    func resetWeeklyAlertIfNeeded(utilization: Double) {
        if utilization < weeklyThreshold {
            weeklyAlerted = false
        }
    }

    func checkAndNotify(response: UsageResponse) {
        let sessionUtil = response.fiveHour.utilization
        resetSessionAlertIfNeeded(utilization: sessionUtil)
        if shouldAlertForSession(utilization: sessionUtil) {
            sendNotification(
                title: "Claude Session Usage",
                body: "5-hour usage at \(Int(sessionUtil))%"
            )
            markSessionAlerted()
        }

        let weeklyUtil = response.sevenDay.utilization
        resetWeeklyAlertIfNeeded(utilization: weeklyUtil)
        if shouldAlertForWeekly(utilization: weeklyUtil) {
            sendNotification(
                title: "Claude Weekly Usage",
                body: "7-day usage at \(Int(weeklyUtil))%"
            )
            markWeeklyAlerted()
        }
    }

    private func sendNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
swift test --filter NotificationManagerTests
```

Expected: All 6 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add ClaudeTokenUsage/ClaudeTokenUsage/Services/NotificationManager.swift ClaudeTokenUsage/ClaudeTokenUsageTests/NotificationManagerTests.swift
git commit -m "feat: add NotificationManager with configurable thresholds"
```

---

## Task 8: Popover UI — UsageGaugeView

**Files:**
- Create: `ClaudeTokenUsage/ClaudeTokenUsage/Views/UsageGaugeView.swift`

- [ ] **Step 1: Implement the circular gauge component**

Create `ClaudeTokenUsage/ClaudeTokenUsage/Views/UsageGaugeView.swift`:

```swift
import SwiftUI

struct UsageGaugeView: View {
    let title: String
    let utilization: Double
    let resetsAt: Date?
    let opusUtilization: Double?
    let sonnetUtilization: Double?

    private var percentage: Int { Int(utilization) }

    private var gaugeColor: Color {
        switch utilization {
        case 0..<50: return .green
        case 50..<80: return .yellow
        default: return .red
        }
    }

    var body: some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.secondary)

            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.3), lineWidth: 8)

                Circle()
                    .trim(from: 0, to: utilization / 100)
                    .stroke(gaugeColor, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.5), value: utilization)

                VStack(spacing: 2) {
                    Text("\(percentage)%")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                }
            }
            .frame(width: 80, height: 80)

            if let resetsAt {
                Text("Resets in \(TimeFormatting.popoverString(until: resetsAt))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let opus = opusUtilization, let sonnet = sonnetUtilization {
                HStack(spacing: 12) {
                    Label("Opus \(Int(opus))%", systemImage: "circle.fill")
                        .font(.caption2)
                        .foregroundStyle(.purple)
                    Label("Sonnet \(Int(sonnet))%", systemImage: "circle.fill")
                        .font(.caption2)
                        .foregroundStyle(.blue)
                }
            }
        }
        .padding()
    }
}

#Preview {
    UsageGaugeView(
        title: "Session (5h)",
        utilization: 69,
        resetsAt: Date().addingTimeInterval(2 * 3600 + 14 * 60),
        opusUtilization: 45,
        sonnetUtilization: 24
    )
    .frame(width: 200)
    .background(.black)
    .preferredColorScheme(.dark)
}
```

- [ ] **Step 2: Build to verify compilation**

```bash
swift build
```

Expected: Build succeeds.

- [ ] **Step 3: Commit**

```bash
git add ClaudeTokenUsage/ClaudeTokenUsage/Views/UsageGaugeView.swift
git commit -m "feat: add circular gauge view component"
```

---

## Task 9: Popover UI — ExtraUsageView + StatusBarView

**Files:**
- Create: `ClaudeTokenUsage/ClaudeTokenUsage/Views/ExtraUsageView.swift`
- Create: `ClaudeTokenUsage/ClaudeTokenUsage/Views/StatusBarView.swift`

- [ ] **Step 1: Implement ExtraUsageView**

Create `ClaudeTokenUsage/ClaudeTokenUsage/Views/ExtraUsageView.swift`:

```swift
import SwiftUI

struct ExtraUsageView: View {
    let usedCredits: Int
    let monthlyLimit: Int

    private var progress: Double {
        guard monthlyLimit > 0 else { return 0 }
        return Double(usedCredits) / Double(monthlyLimit)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Extra Usage")
                .font(.headline)
                .foregroundStyle(.secondary)

            ProgressView(value: progress) {
                HStack {
                    Text("$\(usedCredits) / $\(monthlyLimit)")
                        .font(.caption)
                        .foregroundStyle(.primary)
                    Spacer()
                    Text("\(Int(progress * 100))%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .tint(progress < 0.8 ? .blue : .red)
        }
        .padding()
    }
}

#Preview {
    ExtraUsageView(usedCredits: 1200, monthlyLimit: 5000)
        .frame(width: 280)
        .background(.black)
        .preferredColorScheme(.dark)
}
```

- [ ] **Step 2: Implement StatusBarView**

Create `ClaudeTokenUsage/ClaudeTokenUsage/Views/StatusBarView.swift`:

```swift
import SwiftUI

struct StatusBarView: View {
    let lastUpdated: Date?
    let onRefresh: () -> Void
    let onSettings: () -> Void

    private var lastUpdatedText: String {
        guard let lastUpdated else { return "Never" }
        let seconds = Int(-lastUpdated.timeIntervalSinceNow)
        if seconds < 60 { return "\(seconds)s ago" }
        return "\(seconds / 60)m ago"
    }

    var body: some View {
        HStack {
            Button(action: onSettings) {
                Image(systemName: "gear")
            }
            .buttonStyle(.plain)

            Spacer()

            Text("Updated \(lastUpdatedText)")
                .font(.caption2)
                .foregroundStyle(.tertiary)

            Button(action: onRefresh) {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
    }
}
```

- [ ] **Step 3: Build to verify compilation**

```bash
swift build
```

Expected: Build succeeds.

- [ ] **Step 4: Commit**

```bash
git add ClaudeTokenUsage/ClaudeTokenUsage/Views/ExtraUsageView.swift ClaudeTokenUsage/ClaudeTokenUsage/Views/StatusBarView.swift
git commit -m "feat: add extra usage and status bar views"
```

---

## Task 10: Popover UI — PopoverView (Container)

**Files:**
- Create: `ClaudeTokenUsage/ClaudeTokenUsage/Views/PopoverView.swift`

- [ ] **Step 1: Implement PopoverView**

Create `ClaudeTokenUsage/ClaudeTokenUsage/Views/PopoverView.swift`:

```swift
import SwiftUI

struct PopoverView: View {
    let usageState: UsageState
    let onRefresh: () -> Void
    let onSettings: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            if usageState.isError {
                errorSection
            } else if let response = usageState.response {
                usageSections(response)
            } else {
                Text("No data yet")
                    .foregroundStyle(.secondary)
                    .padding()
            }

            Divider()

            StatusBarView(
                lastUpdated: usageState.lastUpdated,
                onRefresh: onRefresh,
                onSettings: onSettings
            )
        }
        .frame(width: 300)
        .background(.ultraThinMaterial)
    }

    @ViewBuilder
    private func usageSections(_ response: UsageResponse) -> some View {
        // Session (5h)
        UsageGaugeView(
            title: "Session (5h)",
            utilization: response.fiveHour.utilization,
            resetsAt: response.fiveHour.resetsAt,
            opusUtilization: response.sevenDayOpus?.utilization,
            sonnetUtilization: response.sevenDaySonnet?.utilization
        )

        Divider()

        // Weekly (7d)
        UsageGaugeView(
            title: "Weekly (7d)",
            utilization: response.sevenDay.utilization,
            resetsAt: response.sevenDay.resetsAt,
            opusUtilization: nil,
            sonnetUtilization: nil
        )

        // Extra Usage (conditional)
        if let extra = response.extraUsage, extra.isEnabled {
            Divider()
            ExtraUsageView(
                usedCredits: extra.usedCredits,
                monthlyLimit: extra.monthlyLimit
            )
        }
    }

    private var errorSection: some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(.yellow)
            Text(usageState.errorMessage ?? "Unknown error")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}
```

- [ ] **Step 2: Build to verify compilation**

```bash
swift build
```

Expected: Build succeeds.

- [ ] **Step 3: Commit**

```bash
git add ClaudeTokenUsage/ClaudeTokenUsage/Views/PopoverView.swift
git commit -m "feat: add popover container view with all sections"
```

---

## Task 11: Settings Window

**Files:**
- Create: `ClaudeTokenUsage/ClaudeTokenUsage/Views/Settings/SettingsView.swift`
- Create: `ClaudeTokenUsage/ClaudeTokenUsage/Views/Settings/AuthSettingsView.swift`
- Create: `ClaudeTokenUsage/ClaudeTokenUsage/Views/Settings/DisplaySettingsView.swift`
- Create: `ClaudeTokenUsage/ClaudeTokenUsage/Views/Settings/AlertSettingsView.swift`
- Create: `ClaudeTokenUsage/ClaudeTokenUsage/Views/Settings/GeneralSettingsView.swift`

- [ ] **Step 1: Implement AuthSettingsView**

Create `ClaudeTokenUsage/ClaudeTokenUsage/Views/Settings/AuthSettingsView.swift`:

```swift
import SwiftUI

struct AuthSettingsView: View {
    @Bindable var authManager: AuthManager

    var body: some View {
        Form {
            Picker("Auth Method", selection: $authManager.authMethod) {
                ForEach(AuthMethod.allCases, id: \.self) { method in
                    Text(method.rawValue).tag(method)
                }
            }

            switch authManager.authMethod {
            case .oauth:
                HStack {
                    Text("OAuth Token")
                    Spacer()
                    if authManager.oauthToken.isEmpty {
                        Text("Not found in Keychain")
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Found")
                            .foregroundStyle(.green)
                    }
                }

                Button("Load from Keychain") {
                    authManager.loadOAuthTokenFromKeychain()
                }

            case .sessionCookie:
                SecureField("Session Key", text: $authManager.sessionCookie)
                    .textFieldStyle(.roundedBorder)
                Text("Paste sessionKey from claude.ai browser cookies")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                connectionStatusView
                Spacer()
                Button("Test Connection") {
                    Task {
                        try? await authManager.fetchOrganizationId()
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private var connectionStatusView: some View {
        switch authManager.connectionStatus {
        case .unknown:
            Label("Not tested", systemImage: "circle")
                .foregroundStyle(.secondary)
        case .connected:
            Label("Connected", systemImage: "circle.fill")
                .foregroundStyle(.green)
        case .error(let message):
            Label(message, systemImage: "circle.fill")
                .foregroundStyle(.red)
        }
    }
}
```

- [ ] **Step 2: Implement DisplaySettingsView**

Create `ClaudeTokenUsage/ClaudeTokenUsage/Views/Settings/DisplaySettingsView.swift`:

```swift
import SwiftUI

struct DisplaySettingsView: View {
    @AppStorage("showResetTime") var showResetTime = true
    @AppStorage("showSessionLabel") var showSessionLabel = true

    var body: some View {
        Form {
            Section("Menu Bar") {
                Toggle("Show reset time", isOn: $showResetTime)
                Toggle("Show \"Session:\" label", isOn: $showSessionLabel)
            }
        }
        .formStyle(.grouped)
    }
}
```

- [ ] **Step 3: Implement AlertSettingsView**

Create `ClaudeTokenUsage/ClaudeTokenUsage/Views/Settings/AlertSettingsView.swift`:

```swift
import SwiftUI

struct AlertSettingsView: View {
    @Bindable var notificationManager: NotificationManager

    var body: some View {
        Form {
            Section("Session (5h)") {
                Toggle("Enable alerts", isOn: $notificationManager.sessionAlertsEnabled)
                HStack {
                    Text("Warn at")
                    Slider(value: $notificationManager.sessionThreshold, in: 50...100, step: 5)
                    Text("\(Int(notificationManager.sessionThreshold))%")
                        .monospacedDigit()
                        .frame(width: 40)
                }
                .disabled(!notificationManager.sessionAlertsEnabled)
            }

            Section("Weekly (7d)") {
                Toggle("Enable alerts", isOn: $notificationManager.weeklyAlertsEnabled)
                HStack {
                    Text("Warn at")
                    Slider(value: $notificationManager.weeklyThreshold, in: 50...100, step: 5)
                    Text("\(Int(notificationManager.weeklyThreshold))%")
                        .monospacedDigit()
                        .frame(width: 40)
                }
                .disabled(!notificationManager.weeklyAlertsEnabled)
            }

            Section("Extra Usage") {
                Toggle("Enable alerts", isOn: $notificationManager.extraUsageAlertsEnabled)
                HStack {
                    Text("Warn at $")
                    TextField("Amount", value: $notificationManager.extraUsageThreshold, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                }
                .disabled(!notificationManager.extraUsageAlertsEnabled)
            }
        }
        .formStyle(.grouped)
    }
}
```

- [ ] **Step 4: Implement GeneralSettingsView**

Create `ClaudeTokenUsage/ClaudeTokenUsage/Views/Settings/GeneralSettingsView.swift`:

```swift
import SwiftUI
import ServiceManagement

struct GeneralSettingsView: View {
    @AppStorage("pollingInterval") var pollingInterval: Double = 60

    var body: some View {
        Form {
            Section("Polling") {
                HStack {
                    Text("Refresh every")
                    Slider(value: $pollingInterval, in: 15...300, step: 15)
                    Text("\(Int(pollingInterval))s")
                        .monospacedDigit()
                        .frame(width: 40)
                }
            }

            Section("System") {
                Toggle("Launch at login", isOn: Binding(
                    get: { SMAppService.mainApp.status == .enabled },
                    set: { newValue in
                        do {
                            if newValue {
                                try SMAppService.mainApp.register()
                            } else {
                                try SMAppService.mainApp.unregister()
                            }
                        } catch {
                            print("Launch at login error: \(error)")
                        }
                    }
                ))
            }

            Section("About") {
                LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0")
            }
        }
        .formStyle(.grouped)
    }
}
```

- [ ] **Step 5: Implement SettingsView (tab container)**

Create `ClaudeTokenUsage/ClaudeTokenUsage/Views/Settings/SettingsView.swift`:

```swift
import SwiftUI

struct SettingsView: View {
    let authManager: AuthManager
    let notificationManager: NotificationManager

    var body: some View {
        TabView {
            AuthSettingsView(authManager: authManager)
                .tabItem {
                    Label("Authentication", systemImage: "key")
                }

            DisplaySettingsView()
                .tabItem {
                    Label("Display", systemImage: "display")
                }

            AlertSettingsView(notificationManager: notificationManager)
                .tabItem {
                    Label("Alerts", systemImage: "bell")
                }

            GeneralSettingsView()
                .tabItem {
                    Label("General", systemImage: "gear")
                }
        }
        .frame(width: 450, height: 300)
    }
}
```

- [ ] **Step 6: Build to verify compilation**

```bash
swift build
```

Expected: Build succeeds.

- [ ] **Step 7: Commit**

```bash
git add ClaudeTokenUsage/ClaudeTokenUsage/Views/Settings/
git commit -m "feat: add settings window with auth, display, alerts, and general tabs"
```

---

## Task 12: Wire Everything Together in App Entry Point

**Files:**
- Modify: `ClaudeTokenUsage/ClaudeTokenUsage/ClaudeTokenUsageApp.swift`

- [ ] **Step 1: Update the app entry point**

Replace `ClaudeTokenUsage/ClaudeTokenUsage/ClaudeTokenUsageApp.swift` with:

```swift
import SwiftUI

@main
struct ClaudeTokenUsageApp: App {
    @State private var usageState = UsageState()
    @State private var authManager = AuthManager()
    @State private var notificationManager = NotificationManager()
    @State private var usageService: UsageService?

    @AppStorage("showResetTime") private var showResetTime = true
    @AppStorage("showSessionLabel") private var showSessionLabel = true
    @AppStorage("pollingInterval") private var pollingInterval: Double = 60

    var body: some Scene {
        MenuBarExtra {
            PopoverView(
                usageState: usageState,
                onRefresh: { Task { await usageService?.fetchUsage() } },
                onSettings: { openSettings() }
            )
        } label: {
            menuBarLabel
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(
                authManager: authManager,
                notificationManager: notificationManager
            )
        }
    }

    private var menuBarLabel: some View {
        HStack(spacing: 4) {
            Image(systemName: "circle.fill")
                .font(.system(size: 6))
                .foregroundStyle(usageState.statusColor)

            if showSessionLabel {
                Text("Session:")
            }

            Text(usageState.menuBarPercentage)

            if showResetTime {
                Text("·")
                Text(usageState.menuBarResetTime)
            }
        }
        .onAppear {
            setupServices()
        }
        .onChange(of: pollingInterval) { _, newValue in
            usageService?.pollingInterval = newValue
            usageService?.startPolling()
        }
    }

    private func setupServices() {
        authManager.loadOAuthTokenFromKeychain()
        notificationManager.requestPermission()

        let service = UsageService(authManager: authManager, usageState: usageState)
        service.pollingInterval = pollingInterval
        usageService = service

        Task {
            try? await authManager.fetchOrganizationId()
            service.startPolling()
        }
    }

    private func openSettings() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
```

- [ ] **Step 2: Build to verify compilation**

```bash
swift build
```

Expected: Build succeeds.

- [ ] **Step 3: Commit**

```bash
git add ClaudeTokenUsage/ClaudeTokenUsage/ClaudeTokenUsageApp.swift
git commit -m "feat: wire up app entry point with menu bar, popover, and settings"
```

---

## Task 13: Integration — Notification Triggering on Poll

**Files:**
- Modify: `ClaudeTokenUsage/ClaudeTokenUsage/Services/UsageService.swift`

- [ ] **Step 1: Add notification manager to UsageService**

Update `UsageService` to accept and call `NotificationManager` after each successful fetch:

```swift
// In UsageService.swift, update the class:

@Observable
final class UsageService {
    private let authManager: AuthManager
    private let usageState: UsageState
    private let notificationManager: NotificationManager?
    private var pollingTask: Task<Void, Never>?

    var pollingInterval: TimeInterval = 60

    init(authManager: AuthManager, usageState: UsageState, notificationManager: NotificationManager? = nil) {
        self.authManager = authManager
        self.usageState = usageState
        self.notificationManager = notificationManager
    }

    // In fetchUsage(), after usageState.update(with:), add:
    // notificationManager?.checkAndNotify(response: usageResponse)
```

The full updated `fetchUsage` method:

```swift
    func fetchUsage() async {
        guard authManager.isConfigured, !authManager.organizationId.isEmpty else {
            usageState.setError("Not authenticated")
            return
        }

        let urlString = "https://claude.ai/api/organizations/\(authManager.organizationId)/usage"
        guard let url = URL(string: urlString) else {
            usageState.setError("Invalid URL")
            return
        }

        var request = URLRequest(url: url)
        for (key, value) in authManager.buildHeaders() {
            request.setValue(value, forHTTPHeaderField: key)
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                usageState.setError("HTTP \(code)")
                return
            }

            let usageResponse = try JSONDecoder.apiDecoder.decode(UsageResponse.self, from: data)
            usageState.update(with: usageResponse)
            notificationManager?.checkAndNotify(response: usageResponse)
        } catch {
            usageState.setError(error.localizedDescription)
        }
    }
```

- [ ] **Step 2: Update app entry point to pass notificationManager**

In `ClaudeTokenUsageApp.swift`, update `setupServices()`:

```swift
    private func setupServices() {
        authManager.loadOAuthTokenFromKeychain()
        notificationManager.requestPermission()

        let service = UsageService(
            authManager: authManager,
            usageState: usageState,
            notificationManager: notificationManager
        )
        service.pollingInterval = pollingInterval
        usageService = service

        Task {
            try? await authManager.fetchOrganizationId()
            service.startPolling()
        }
    }
```

- [ ] **Step 3: Build to verify compilation**

```bash
swift build
```

Expected: Build succeeds.

- [ ] **Step 4: Commit**

```bash
git add ClaudeTokenUsage/ClaudeTokenUsage/Services/UsageService.swift ClaudeTokenUsage/ClaudeTokenUsage/ClaudeTokenUsageApp.swift
git commit -m "feat: integrate notification triggering into polling loop"
```

---

## Task 14: Run All Tests + Final Verification

- [ ] **Step 1: Run full test suite**

```bash
cd /Users/taejunoh/Desktop/LFG/claude-token-usage/ClaudeTokenUsage
swift test
```

Expected: All tests pass (UsageResponseTests, TimeFormattingTests, UsageStateTests, AuthManagerTests, NotificationManagerTests).

- [ ] **Step 2: Build release**

```bash
swift build -c release
```

Expected: Build succeeds.

- [ ] **Step 3: Run the app manually to verify**

```bash
swift run
```

Expected: App appears in menu bar showing `◉ Session: --% · --` (no auth configured yet). Clicking shows the popover. Settings window opens from gear icon.

- [ ] **Step 4: Commit any fixes**

If any issues were found, fix and commit:

```bash
git add -A
git commit -m "fix: address issues found during final verification"
```

