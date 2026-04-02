// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AgentNotch",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/sindresorhus/Defaults.git", from: "9.0.0"),
        .package(url: "https://github.com/sindresorhus/LaunchAtLogin-Modern.git", from: "1.1.0"),
    ],
    targets: [
        .executableTarget(
            name: "AgentNotch",
            dependencies: [
                "Defaults",
                .product(name: "LaunchAtLogin", package: "LaunchAtLogin-Modern"),
            ],
            path: "AgentNotch",
            exclude: ["Info.plist"],
            resources: [
                .process("Resources"),
            ]
        ),
        .testTarget(
            name: "AgentNotchTests",
            dependencies: ["AgentNotch"],
            path: "AgentNotchTests"
        ),
    ]
)
