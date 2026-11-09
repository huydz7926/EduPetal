// swift-tools-version: 5.10
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "EduPetal",
    defaultLocalization: "vi",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "EduPetal",
            targets: ["EduPetal"]
        ),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "EduPetal",
            dependencies: [],
            path: "Sources/EduPetal",
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "EduPetalTests",
            dependencies: ["EduPetal"],
            path: "Tests/EduPetalTests"
        ),
    ]
)

