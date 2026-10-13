import Foundation
import os

/// Unified logging (`log stream --predicate 'subsystem == "<bundle-id>"'`). Rule
/// (ROADMAP M8): never log clipboard content – only kinds, counts, sizes, reasons
/// and type identifiers.
enum Log {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "CopyPal"

    static let capture = Logger(subsystem: subsystem, category: "capture")
    static let paste = Logger(subsystem: subsystem, category: "paste")
    static let input = Logger(subsystem: subsystem, category: "input")
    static let storage = Logger(subsystem: subsystem, category: "storage")
    static let app = Logger(subsystem: subsystem, category: "app")

    /// Intervals for Instruments (Points of Interest): "Halten bis sichtbar" and
    /// "Kopieren bis gespeichert".
    static let signposter = OSSignposter(subsystem: subsystem, category: .pointsOfInterest)
}
