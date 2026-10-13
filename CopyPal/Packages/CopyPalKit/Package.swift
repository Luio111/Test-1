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
    dependencies: [
        // Exact versions: the Xcode project is generated and its Package.resolved is not
        // checked in, so this keeps every build on the same code.
        .package(url: "https://github.com/groue/GRDB.swift.git", exact: "7.9.0"),
        // CryptoKit's API for Linux (CI tests). On macOS the app uses CryptoKit itself.
        .package(url: "https://github.com/apple/swift-crypto.git", exact: "3.15.1"),
    ],
    targets: [
        .target(name: "CopyPalCore"),
        .target(
            name: "CopyPalStorage",
            dependencies: [
                "CopyPalCore",
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "Crypto", package: "swift-crypto", condition: .when(platforms: [.linux])),
            ]
        ),
        .target(name: "CopyPalSystem", dependencies: ["CopyPalCore"], swiftSettings: macOSOnlySettings),
        .target(name: "CopyPalServices", dependencies: ["CopyPalCore", "CopyPalStorage"]),

        .testTarget(name: "CopyPalCoreTests", dependencies: ["CopyPalCore"]),
        .testTarget(name: "CopyPalStorageTests", dependencies: ["CopyPalStorage"]),
        .testTarget(name: "CopyPalSystemTests", dependencies: ["CopyPalSystem"], swiftSettings: macOSOnlySettings),
        .testTarget(name: "CopyPalServicesTests", dependencies: ["CopyPalServices"]),
    ]
)
