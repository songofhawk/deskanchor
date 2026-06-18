// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "Winstore",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "Winstore", targets: ["WinstoreApp"]),
        .library(name: "WinstoreCore", targets: ["WinstoreCore"])
    ],
    targets: [
        .target(
            name: "WinstoreCore"
        ),
        .executableTarget(
            name: "WinstoreApp",
            dependencies: ["WinstoreCore"]
        ),
        .testTarget(
            name: "WinstoreCoreTests",
            dependencies: ["WinstoreCore"]
        )
    ]
)
