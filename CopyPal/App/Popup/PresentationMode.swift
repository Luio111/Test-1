import Foundation
import Observation

/// Presentation mode: while on, the popup shows what kind each entry is, its app and
/// its age – never its content. For screen sharing, where keeping the window out of
/// the shared picture is not reliable. Ends by itself after two hours, also across a
/// relaunch.
@MainActor
@Observable
final class PresentationMode {
    static let duration: TimeInterval = 2 * 3_600

    private(set) var until: Date?
    /// Switched on or off (the menu bar icon shows it).
    @ObservationIgnored var onChange: (() -> Void)?
    /// Ended by itself after `duration`.
    @ObservationIgnored var onExpire: (() -> Void)?
    @ObservationIgnored private var endTask: Task<Void, Never>?

    init() {
        until = AppSettings.presentationUntil
        scheduleEnd()
    }

    var isActive: Bool {
        until.map { $0 > Date() } ?? false
    }

    func start() {
        set(Date().addingTimeInterval(Self.duration))
    }

    func stop() {
        set(nil)
    }

    private func set(_ date: Date?) {
        until = date
        AppSettings.presentationUntil = date
        scheduleEnd()
        onChange?()
    }

    private func scheduleEnd() {
        endTask?.cancel()
        endTask = nil
        guard let until else { return }
        let delay = until.timeIntervalSinceNow
        guard delay > 0 else {
            // Ran out while CopyPal was not running.
            self.until = nil
            AppSettings.presentationUntil = nil
            return
        }
        endTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self else { return }
            self.set(nil)
            self.onExpire?()
        }
    }
}
