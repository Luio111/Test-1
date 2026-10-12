import Foundation

/// User-adjustable values (UserDefaults). The lab window edits them in M1; the
/// settings window takes over in M7.
enum AppSettings {
    private enum Key {
        static let holdThreshold = "holdThreshold"
        static let pasteDelayMilliseconds = "pasteDelayMilliseconds"
    }

    static let holdThresholdRange: ClosedRange<Double> = 0.15...0.6
    static let pasteDelayRange: ClosedRange<Double> = 0...150

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            Key.holdThreshold: 0.3,
            Key.pasteDelayMilliseconds: 30.0,
        ])
    }

    /// Seconds ⌘V must be held before the popup opens (ROADMAP D2).
    static var holdThreshold: Double {
        get { UserDefaults.standard.double(forKey: Key.holdThreshold) }
        set { UserDefaults.standard.set(newValue.clamped(to: holdThresholdRange), forKey: Key.holdThreshold) }
    }

    /// Wait between closing the popup and posting ⌘V, so focus is back in the target app.
    static var pasteDelayMilliseconds: Double {
        get { UserDefaults.standard.double(forKey: Key.pasteDelayMilliseconds) }
        set { UserDefaults.standard.set(newValue.clamped(to: pasteDelayRange), forKey: Key.pasteDelayMilliseconds) }
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
