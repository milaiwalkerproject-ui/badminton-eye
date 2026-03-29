// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "ScoringEngine",
    platforms: [
        .iOS(.v17),
        .watchOS(.v10),
    ],
    products: [
        .library(
            name: "ScoringEngine",
            targets: ["ScoringEngine"]
        ),
    ],
    targets: [
        .target(
            name: "ScoringEngine",
            path: "Sources/ScoringEngine"
        ),
        .testTarget(
            name: "ScoringEngineTests",
            dependencies: ["ScoringEngine"],
            path: "Tests/ScoringEngineTests"
        ),
    ]
)
