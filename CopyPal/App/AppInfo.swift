import Foundation
import CopyPalCore

/// Values from the generated Info.plist.
enum AppInfo {
    static var version: String {
        string(for: "CFBundleShortVersionString") ?? "–"
    }

    static var build: String {
        string(for: "CFBundleVersion") ?? "–"
    }

    static var bundleIdentifier: String {
        Bundle.main.bundleIdentifier ?? "–"
    }

    /// Xcode and SDK used for this build (Xcode adds `DTXcode` and `DTSDKName`).
    static var buildEnvironment: String {
        BuildEnvironment.describe(xcode: string(for: "DTXcode"), sdk: string(for: "DTSDKName"))
    }

    static var osVersion: String {
        ProcessInfo.processInfo.operatingSystemVersionString
    }

    private static func string(for key: String) -> String? {
        Bundle.main.object(forInfoDictionaryKey: key) as? String
    }
}
