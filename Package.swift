// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "DeskAnchor",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "DeskAnchor", targets: ["DeskAnchorApp"]),
        .library(name: "DeskAnchorCore", targets: ["DeskAnchorCore"])
    ],
    targets: [
        .target(
            name: "DeskAnchorCore"
        ),
        .executableTarget(
            name: "DeskAnchorApp",
            dependencies: ["DeskAnchorCore"]
        ),
        .testTarget(
            name: "DeskAnchorCoreTests",
            dependencies: ["DeskAnchorCore"]
        )
    ]
)
