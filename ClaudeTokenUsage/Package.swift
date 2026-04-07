// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "ClaudeTokenUsage",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "ClaudeTokenUsage",
            path: "ClaudeTokenUsage",
            exclude: ["Info.plist", "ClaudeTokenUsage.entitlements"]
        ),
        .testTarget(
            name: "ClaudeTokenUsageTests",
            dependencies: ["ClaudeTokenUsage"],
            path: "ClaudeTokenUsageTests"
        ),
    ]
)
