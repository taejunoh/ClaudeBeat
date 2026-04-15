// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "ClaudeBeat",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "ClaudeBeat",
            path: "ClaudeBeat",
            exclude: ["Info.plist", "ClaudeBeat.entitlements"]
        ),
        .testTarget(
            name: "ClaudeBeatTests",
            dependencies: ["ClaudeBeat"],
            path: "ClaudeBeatTests"
        ),
    ]
)
