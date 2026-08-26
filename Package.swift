// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "AgentNotch",
    defaultLocalization: "en",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "AgentNotch", targets: ["AgentNotch"]),
        .executable(name: "agent-notch", targets: ["AgentNotchCLI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/sindresorhus/Defaults.git", from: "9.0.0"),
        .package(url: "https://github.com/sindresorhus/LaunchAtLogin-Modern.git", from: "1.1.0"),
        .package(url: "https://github.com/gonzalezreal/swift-markdown-ui.git", from: "2.4.0"),
        .package(url: "https://github.com/smittytone/HighlighterSwift.git", from: "3.1.0"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.6.0"),
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts.git", from: "2.2.0"),
    ],
    targets: [
        // Shared library — models, services, utilities (no UI dependency)
        .target(
            name: "AgentNotchCore",
            dependencies: [
                .product(name: "Logging", package: "swift-log")
            ],
            path: "AgentNotchCore",
            resources: [
                .process("Resources")
            ]
        ),
        // GUI app
        .executableTarget(
            name: "AgentNotch",
            dependencies: [
                "AgentNotchCore",
                "Defaults",
                .product(name: "LaunchAtLogin", package: "LaunchAtLogin-Modern"),
                .product(name: "MarkdownUI", package: "swift-markdown-ui"),
                .product(name: "Highlighter", package: "HighlighterSwift"),
                "KeyboardShortcuts",
            ],
            path: "AgentNotch",
            exclude: [
                "AgentNotch.entitlements",
                "Info.plist",
            ],
            resources: [
                .process("Resources")
            ]
        ),
        // CLI tool
        .executableTarget(
            name: "AgentNotchCLI",
            dependencies: ["AgentNotchCore"],
            path: "AgentNotchCLI"
        ),
        // Tests
        .testTarget(
            name: "AgentNotchTests",
            dependencies: ["AgentNotchCore", "AgentNotch"],
            path: "AgentNotchTests"
        ),
    ]
)
