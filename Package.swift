// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ClaudeItermMate",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "ClaudeItermMate",
            path: "Sources/ClaudeItermMate",
            exclude: [
                // Reference-only copy for source control; installed manually to
                // ~/.claude/scripts/ (like iterm-focus-pane.py), not loaded via
                // Bundle.module at runtime.
                "Resources/set-pane-bg.py",
            ],
            resources: [
                .copy("Resources/mate-notify.js"),
                .copy("Resources/mate-session-start.js"),
            ]
        ),
        .testTarget(
            name: "ClaudeItermMateTests",
            dependencies: ["ClaudeItermMate"],
            path: "Tests/ClaudeItermMateTests"
        ),
    ]
)
