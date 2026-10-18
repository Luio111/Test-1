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

    /// ⌘S: the picture as a PNG in full resolution, where macOS puts its own
    /// screenshots (set in the Screenshot app, `com.apple.screencapture location`),
    /// else on the desktop. "Bildschirmfoto 2026-10-18 um 15.30.12.png"; never
    /// overwrites a file.
    static func saveFile(_ image: ImageBox, scale: CGFloat) async -> URL? {
        let url = uniqueURL(in: screenshotFolder(), name: fileName(for: Date()))
        let written = await Task.detached(priority: .userInitiated) { () -> Bool in
            guard let data = ImageConversion.png(image.image, scale: scale) else { return false }
            return (try? data.write(to: url, options: .withoutOverwriting)) != nil
        }.value
        return written ? url : nil
    }

    static func screenshotFolder() -> URL {
        if let path = UserDefaults(suiteName: "com.apple.screencapture")?.string(forKey: "location") {
            let expanded = (path as NSString).expandingTildeInPath
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: expanded, isDirectory: &isDirectory), isDirectory.boolValue {
                return URL(fileURLWithPath: expanded, isDirectory: true)
            }
        }
        return FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0]
    }

    private static func fileName(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let day = formatter.string(from: date)
        formatter.dateFormat = "HH.mm.ss"
        let time = formatter.string(from: date)
        return String(localized: "Bildschirmfoto \(day) um \(time)")
    }

    private static func uniqueURL(in folder: URL, name: String) -> URL {
        var url = folder.appendingPathComponent(name).appendingPathExtension("png")
        var number = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = folder.appendingPathComponent("\(name) (\(number))").appendingPathExtension("png")
            number += 1
        }
        return url
    }

    enum TextOutcome {
        case copied(lineCount: Int)
        case noText
        case failed(String)
    }

    /// ⇧⏎ in the overlay: the text in the picture, recognized on this Mac, goes to the
    /// pasteboard and through the normal capture into the history – masking, expiry
    /// and "this Mac only" apply as for any copy. Pause and the ignore list keep it
    /// out of the history.
    static func publishText(_ image: ImageBox, sourceBundleID: String?, app: AppController) async -> TextOutcome {
        let recognized = await Task.detached(priority: .userInitiated) {
            TextRecognizer.text(in: image.image)
        }.value
        guard let text = recognized, !text.isEmpty else {
            return .noText
        }
        let fromIgnoredApp = sourceBundleID.map { AppSettings.ignoredBundleIDs.contains($0) } ?? false
        let detection = await app.engine.currentPolicy.detection
        let sensitive = SensitiveContentDetector.detect(text, options: detection) != nil
        let keepLocal = fromIgnoredApp || sensitive
        let representations = [ClipRepresentation(type: PasteboardTypeID.plainText, data: Data(text.utf8))]
        let changeCount = PasteboardWriter.write(
            representations,
            to: app.capture.monitor.pasteboard,
            options: PasteboardWriter.Options(localOnly: keepLocal, concealed: keepLocal)
        )
        app.capture.registerOwnWrite(changeCount: changeCount)
        let lineCount = TextFolding.lineCount(of: text)
        guard !app.capture.isPaused, !fromIgnoredApp else {
            return .copied(lineCount: lineCount)
        }
        let content = CapturedContent(representations: representations, sourceBundleID: sourceBundleID ?? Bundle.main.bundleIdentifier)
        do {
            if case .stored = try await app.engine.capture(content) {
                await app.history.reload()
            }
            return .copied(lineCount: lineCount)
        } catch {
            return .failed(String(describing: error))
        }
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
                app.textIndexer.enqueue(result.item.id)
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
