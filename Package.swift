// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AIUsageBuddy",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "AIUsageBuddy",
            resources: [
                .copy("Resources/ja.lproj"),
                .copy("Resources/en.lproj")
            ]
        ),
        .testTarget(
            name: "AIUsageBuddyTests",
            dependencies: ["AIUsageBuddy"],
            resources: [
                .process("TestResources")
            ]
        )
    ]
)
