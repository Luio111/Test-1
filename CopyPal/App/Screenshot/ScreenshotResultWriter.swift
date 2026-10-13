import AppKit
import CopyPalCore
import CopyPalServices
import CopyPalSystem

/// Puts a finished screenshot on the pasteboard (PNG + TIFF, as CopyPal's own write)
/// and into the history (PNG), honouring the pause and the ignore list (ROADMAP M11).
@MainActor
enum ScreenshotResultWriter {
    enum Reason: Sendable {
        case paused
        case ignoredApp
        case tooLarge
    }

    enum Outcome {
        case stored(ClipItem, downscaled: Bool)
        /// On the pasteboard, but kept out of the history.
        case pasteboardOnly(Reason)
        case failed(String)
    }

    /// `sourceBundleID` is the app whose window the selection covers (ignore list).
    static func publish(_ image: ImageBox, scale: CGFloat, sourceBundleID: String?, app: AppController) async -> Outcome {
        let maxBytes = AppSettings.retentionPolicy.maxImageBytes
        let encoded = await Task.detached(priority: .userInitiated) { () -> (ImageConversion.FittedPNG, Data)? in
            guard let fitted = ImageConversion.pngFitting(image.image, scale: scale, maxBytes: maxBytes, maximumHalvings: 1),
                  let tiff = ImageConversion.tiff(fitted.image.image, scale: fitted.scale) else {
                return nil
            }
            return (fitted, tiff)
        }.value
        guard let encoded else {
            return .failed("PNG/TIFF konnten nicht erzeugt werden")
        }
        let (fitted, tiff) = encoded

        let representations = [
            ClipRepresentation(type: PasteboardTypeID.png, data: fitted.data),
            ClipRepresentation(type: PasteboardTypeID.tiff, data: tiff),
        ]
        let changeCount = PasteboardWriter.write(representations, to: app.capture.monitor.pasteboard)
        app.capture.registerOwnWrite(changeCount: changeCount)
        Log.app.info("Bildschirmfoto: \(fitted.image.width, privacy: .public) × \(fitted.image.height, privacy: .public) px, PNG \(fitted.data.count, privacy: .public) B\(fitted.downscaled ? ", verkleinert" : "", privacy: .public)")

        if app.capture.isPaused {
            return .pasteboardOnly(.paused)
        }
        if let sourceBundleID, AppSettings.ignoredBundleIDs.contains(sourceBundleID) {
            return .pasteboardOnly(.ignoredApp)
        }
        if fitted.data.count > maxBytes {
            return .pasteboardOnly(.tooLarge)
        }

        let content = CapturedContent(
            representations: [ClipRepresentation(type: PasteboardTypeID.png, data: fitted.data)],
            sourceBundleID: Bundle.main.bundleIdentifier
        )
        do {
            switch try await app.engine.capture(content) {
            case let .stored(result):
                await app.history.reload()
                return .stored(result.item, downscaled: fitted.downscaled)
            case .skipped(.tooLarge):
                return .pasteboardOnly(.tooLarge)
            case let .skipped(reason):
                return .failed("übersprungen: \(reason)")
            }
        } catch {
            return .failed(String(describing: error))
        }
    }
}
