// swift-tools-version: 5.9
import PackageDescription

let bridgingHeader: [SwiftSetting] = [
    .unsafeFlags([
        "-import-objc-header",
        "Sources/ScreenManagerCore/include/BridgingHeader.h"
    ])
]

let package = Package(
    name: "ScreenManager",
    platforms: [.macOS(.v13)],
    targets: [
        // All logic lives here so it can be exercised by tests; the executable
        // is a one-line shim.
        .target(
            name: "ScreenManagerCore",
            path: "Sources/ScreenManagerCore",
            exclude: ["include/BridgingHeader.h"],
            swiftSettings: bridgingHeader,
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Carbon"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("ServiceManagement"),
            ]
        ),
        .executableTarget(
            name: "ScreenManager",
            dependencies: ["ScreenManagerCore"],
            path: "Sources/ScreenManager"
        ),
        .testTarget(
            name: "ScreenManagerTests",
            dependencies: ["ScreenManagerCore"],
            path: "Tests/ScreenManagerTests",
            swiftSettings: bridgingHeader
        ),
    ]
)
