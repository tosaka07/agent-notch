// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "AgentNotch",
    defaultLocalization: "en",
    platforms: [.macOS(.v26)],
    products: [
        // Debug builds only. The shipped .app is built by Xcode, which cannot link a SwiftPM
        // executable target — it links the AgentNotchUI library below and supplies its own
        // entry point from AgentNotchApp.
        .executable(name: "AgentNotch", targets: ["AgentNotchApp"]),
        .executable(name: "agent-notch", targets: ["AgentNotchCLI"]),
        // Everything the app does. Exposed as a product solely so the Xcode target can depend
        // on it; the module is still named AgentNotch.
        .library(name: "AgentNotchUI", targets: ["AgentNotch"]),
        // Likewise for the CLI's Xcode target. AgentNotchCore carries resources of its own, so
        // the CLI has to be built by Xcode too — see xcode/project.yml.
        .library(name: "AgentNotchCoreLib", targets: ["AgentNotchCore"]),
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
        // GUI app — a library so that both the SwiftPM executable and the Xcode application
        // target can link it.
        .target(
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
        // Entry point only. Shared verbatim with the Xcode target.
        .executableTarget(
            name: "AgentNotchApp",
            dependencies: ["AgentNotch"],
            path: "AgentNotchApp"
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
