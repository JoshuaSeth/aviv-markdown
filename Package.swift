// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "Aviv",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "Aviv", targets: ["Aviv"]),
        .library(name: "AvivCore", targets: ["AvivCore"])
    ],
    targets: [
        .target(
            name: "AvivCore",
            path: "Sources/AvivCore"
        ),
        .executableTarget(
            name: "Aviv",
            dependencies: ["AvivCore"],
            path: "Sources/AvivApp"
        ),
        .testTarget(
            name: "AvivCoreTests",
            dependencies: ["AvivCore"],
            path: "Tests/AvivCoreTests"
        )
    ]
)
