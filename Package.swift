// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "meta-wearables-dat-ios",
    platforms: [
        .iOS(.v15),
        .visionOS(.v1)
    ],
    products: [
        // Core SDK for Meta Wearables Device Access Toolkit
        .library(
            name: "MWDATCore",
            targets: ["MWDATCore"]),

        // Camera functionality for video streaming and photo capture
        .library(
            name: "MWDATCamera",
            targets: ["MWDATCamera"]),

        // Mock device support for development and testing
        .library(
            name: "MWDATMockDevice",
            targets: ["MWDATMockDevice"]),
    ],
    dependencies: [
        // No external dependencies
    ],
    targets: [
        // Binary frameworks
        .binaryTarget(
            name: "MWDATCore",
            path: "./MWDATCore.xcframework"),

        .binaryTarget(
            name: "MWDATCamera",
            path: "./MWDATCamera.xcframework"),

        .binaryTarget(
            name: "MWDATMockDevice",
            path: "./MWDATMockDevice.xcframework"),
    ]
)