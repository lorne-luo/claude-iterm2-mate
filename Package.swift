// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ClaudeItermMate",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "ClaudeItermMate",
            path: "Sources/ClaudeItermMate",
            resources: [.copy("Resources/mate-notify.js")]
        ),
        .testTarget(
            name: "ClaudeItermMateTests",
            dependencies: ["ClaudeItermMate"],
            path: "Tests/ClaudeItermMateTests"
        ),
    ]
)
