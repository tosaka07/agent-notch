// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AgentNotch",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "AgentNotch", targets: ["AgentNotch"]),
        .executable(name: "agent-notch", targets: ["AgentNotchCLI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/sindresorhus/Defaults.git", from: "9.0.0"),
        .package(url: "https://github.com/sindresorhus/LaunchAtLogin-Modern.git", from: "1.1.0"),
    ],
    targets: [
        // Shared library — models, services, utilities (no UI dependency)
        .target(
            name: "AgentNotchCore",
            path: "AgentNotchCore"
        ),
        // GUI app
        .executableTarget(
            name: "AgentNotch",
            dependencies: [
                "AgentNotchCore",
                "Defaults",
                .product(name: "LaunchAtLogin", package: "LaunchAtLogin-Modern"),
            ],
            path: "AgentNotch",
            exclude: ["Info.plist"],
            resources: [
                .process("Resources"),
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
