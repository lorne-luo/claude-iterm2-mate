// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ClaudeItermMate",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "ClaudeItermMate",
            path: "Sources/ClaudeItermMate",
            resources: [
                .copy("Resources/mate-notify.js"),
                .copy("Resources/mate-session-start.js"),
                // Published to App Support by ScriptInstaller; run via the it2
                // venv python (PythonInterpreter), never via their shebang.
                .copy("Resources/iterm-focus-pane.py"),
                .copy("Resources/set-pane-bg.py"),
            ]
        ),
        .testTarget(
            name: "ClaudeItermMateTests",
            dependencies: ["ClaudeItermMate"],
            path: "Tests/ClaudeItermMateTests"
        ),
    ]
)
