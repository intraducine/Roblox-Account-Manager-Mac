// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "RobloxAccountManagerMac",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "RAMacCore", targets: ["RAMacCore"]),
        .executable(name: "RobloxAccountManager", targets: ["RAMacApp"])
    ],
    targets: [
        .target(
            name: "RAMacCore",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Security")
            ]
        ),
        .executableTarget(
            name: "RAMacApp",
            dependencies: ["RAMacCore"],
            linkerSettings: [.linkedFramework("WebKit")]
        ),
        .testTarget(name: "RAMacCoreTests", dependencies: ["RAMacCore"])
    ]
)
