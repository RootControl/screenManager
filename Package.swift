// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ScreenManager",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "ScreenManager",
            path: "Sources/ScreenManager",
            swiftSettings: [
                .unsafeFlags([
                    "-import-objc-header",
                    "Sources/ScreenManager/include/BridgingHeader.h"
                ])
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Carbon"),
                .linkedFramework("ApplicationServices"),
            ]
        )
    ]
)
