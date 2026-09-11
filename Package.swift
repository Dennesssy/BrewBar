// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "BrewBar",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .library(
            name: "BrewBarKit",
            targets: ["BrewBarKit"]
        ),
        .executable(
            name: "BrewBar",
            targets: ["BrewBarApp"]
        )
    ],
    targets: [
        .target(
            name: "BrewBarKit",
            dependencies: [],
            path: "Sources/BrewBarKit",
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        ),
        .executableTarget(
            name: "BrewBarApp",
            dependencies: ["BrewBarKit"],
            path: "Sources/BrewBarApp",
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "BrewBarTests",
            dependencies: ["BrewBarKit"],
            path: "Tests/BrewBarTests"
        )
    ]
)
