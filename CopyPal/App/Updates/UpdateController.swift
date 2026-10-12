import Foundation
import Sparkle

/// Updates through Sparkle 2 (ROADMAP M9). Starts only in builds that carry an
/// appcast URL and the EdDSA public key (Release builds after `Docs/Release.md`);
/// otherwise CopyPal never contacts an update server. Sparkle asks the user before
/// checking automatically and never sends a system profile.
@MainActor
final class UpdateController {
    private let controller: SPUStandardUpdaterController?
    private let delegate = UpdaterDelegate()

    init() {
        if Self.isConfigured {
            controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: delegate, userDriverDelegate: nil)
        } else {
            controller = nil
        }
    }

    var isAvailable: Bool {
        controller != nil
    }

    func checkForUpdates() {
        controller?.checkForUpdates(nil)
    }

    private static var isConfigured: Bool {
        #if DEBUG
        return false
        #else
        let info = Bundle.main.infoDictionary ?? [:]
        let feed = (info["SUFeedURL"] as? String) ?? ""
        let key = (info["SUPublicEDKey"] as? String) ?? ""
        return !feed.isEmpty && !key.isEmpty
        #endif
    }
}

/// Offers beta builds (appcast channel "beta") when the user opted in.
@MainActor
private final class UpdaterDelegate: NSObject, SPUUpdaterDelegate {
    nonisolated func allowedChannels(for updater: SPUUpdater) -> Set<String> {
        UserDefaults.standard.bool(forKey: AppSettings.betaUpdatesKey) ? ["beta"] : []
    }
}
