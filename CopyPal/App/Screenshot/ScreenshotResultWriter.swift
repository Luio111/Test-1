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

    /// `sourceBundleID` is the app whose window the selection covers (ignore list,
    /// history icon); `capturedFrom` names app and window for the row and the search.
    static func publish(_ image: ImageBox, scale: CGFloat, sourceBundleID: String?, capturedFrom: String, app: AppController) async -> Outcome {
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

        // An ignored app (a password manager) in the picture: this Mac only, marked
        // concealed for other clipboard tools, never in the history.
        let fromIgnoredApp = sourceBundleID.map { AppSettings.ignoredBundleIDs.contains($0) } ?? false
        let representations = [
            ClipRepresentation(type: PasteboardTypeID.png, data: fitted.data),
            ClipRepresentation(type: PasteboardTypeID.tiff, data: tiff),
        ]
        let options = PasteboardWriter.Options(localOnly: fromIgnoredApp, concealed: fromIgnoredApp)
        let changeCount = PasteboardWriter.write(representations, to: app.capture.monitor.pasteboard, options: options)
        app.capture.registerOwnWrite(changeCount: changeCount)
        Log.app.info("Bildschirmfoto: \(fitted.image.width, privacy: .public) × \(fitted.image.height, privacy: .public) px, PNG \(fitted.data.count, privacy: .public) B\(fitted.downscaled ? ", verkleinert" : "", privacy: .public)")

        if app.capture.isPaused {
            return .pasteboardOnly(.paused)
        }
        if fromIgnoredApp {
            return .pasteboardOnly(.ignoredApp)
        }
        if fitted.data.count > maxBytes {
            return .pasteboardOnly(.tooLarge)
        }

        let content = CapturedContent(
            representations: [ClipRepresentation(type: PasteboardTypeID.png, data: fitted.data)],
            // The captured app, so the history shows its icon (CopyPal when unknown).
            sourceBundleID: sourceBundleID ?? Bundle.main.bundleIdentifier,
            hints: ContentHints(capturedFrom: capturedFrom)
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
