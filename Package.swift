// swift-tools-version:5.9
//
// This package exists so the shared keyboard core can be tested on a plain
// macOS runner with `swift test` — no simulator, no signing, no Xcode project.
//
// It deliberately compiles ONLY Shared/*.swift. The SwiftUI files in
// Shared/Rendering are excluded here and are compiled by the two app targets in
// the Xcode project, which keeps this package Foundation-only (so it builds for
// macOS without UIKit) while the app still shares one copy of the code.
//
// Nothing in the iOS build consumes this package: it is a test harness for the
// same sources.

import PackageDescription

let package = Package(
    name: "KeyraShared",
    platforms: [
        .macOS(.v12)
    ],
    products: [
        .library(name: "KeyraShared", targets: ["KeyraShared"])
    ],
    targets: [
        .target(
            name: "KeyraShared",
            path: "Shared",
            exclude: ["Rendering"]
        ),
        .testTarget(
            name: "KeyraSharedTests",
            dependencies: ["KeyraShared"],
            path: "Tests/KeyraSharedTests"
        )
    ]
)
