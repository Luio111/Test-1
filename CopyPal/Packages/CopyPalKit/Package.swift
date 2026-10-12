// swift-tools-version: 6.0
import PackageDescription

// macOS-only modules (System) still compile on Linux: their sources are wrapped in
// `#if os(macOS)`, so `swift build` / `swift test` run everywhere and CI can test
// the platform-neutral parts cheaply.
let macOSOnlySettings: [SwiftSetting] = [
    // Swift 5 mode with complete concurrency checking (warnings, not errors) until the
    // AppKit/CoreGraphics adapters are verified on a real Mac — see Docs/ADR/0002.
    .swiftLanguageMode(.v5),
    .enableUpcomingFeature("StrictConcurrency"),
]

let package = Package(
    name: "CopyPalKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "CopyPalCore", targets: ["CopyPalCore"]),
        .library(name: "CopyPalStorage", targets: ["CopyPalStorage"]),
        .library(name: "CopyPalSystem", targets: ["CopyPalSystem"]),
        .library(name: "CopyPalServices", targets: ["CopyPalServices"]),
    ],
    targets: [
        .target(name: "CopyPalCore"),
        .target(name: "CopyPalStorage", dependencies: ["CopyPalCore"]),
        .target(name: "CopyPalSystem", dependencies: ["CopyPalCore"], swiftSettings: macOSOnlySettings),
        .target(name: "CopyPalServices", dependencies: ["CopyPalCore", "CopyPalStorage", "CopyPalSystem"]),

        .testTarget(name: "CopyPalCoreTests", dependencies: ["CopyPalCore"]),
        .testTarget(name: "CopyPalStorageTests", dependencies: ["CopyPalStorage"]),
        .testTarget(name: "CopyPalSystemTests", dependencies: ["CopyPalSystem"], swiftSettings: macOSOnlySettings),
        .testTarget(name: "CopyPalServicesTests", dependencies: ["CopyPalServices"]),
    ]
)
