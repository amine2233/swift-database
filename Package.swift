// swift-tools-version: 6.2

import PackageDescription

let swiftSettings: [SwiftSetting] = [
    .enableUpcomingFeature("ApproachableConcurrency"),
    .enableUpcomingFeature("ExistentialAny"),
]

let package = Package(
    name: "DatabaseKit",
    platforms: [
        .iOS(.v18),
        .macOS(.v15),
        .tvOS(.v18),
        .watchOS(.v11),
        .visionOS(.v2),
    ],
    products: [
        .library(name: "DatabaseKit", targets: ["DatabaseKit"]),
        .library(name: "DatabaseKitTesting", targets: ["DatabaseKitTesting"]),
    ],
    targets: [
        .target(
            name: "DatabaseKit",
            swiftSettings: swiftSettings
        ),
        .target(
            name: "DatabaseKitTesting",
            dependencies: ["DatabaseKit"],
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "DatabaseKitTests",
            dependencies: ["DatabaseKit", "DatabaseKitTesting"],
            swiftSettings: swiftSettings
        ),
    ]
)
