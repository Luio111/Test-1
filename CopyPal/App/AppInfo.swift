import Foundation

/// Values from the generated Info.plist.
enum AppInfo {
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–"
    }

    static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "–"
    }

    static var bundleIdentifier: String {
        Bundle.main.bundleIdentifier ?? "–"
    }

    static var osVersion: String {
        ProcessInfo.processInfo.operatingSystemVersionString
    }
}
