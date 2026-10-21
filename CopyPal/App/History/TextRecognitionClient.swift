import CopyPalSystem
import Foundation

/// Reads the text in images through CopyPal's helper process (an XPC service, ADR
/// 0005), so Vision's models never stay in CopyPal's memory (ROADMAP R32). The
/// connection stays open while there is work and closes `idleTimeout` after the last
/// answer; the helper then ends. The caller's priority carries over to the helper:
/// the background indexer reads at utility, ⇧⏎ at user-initiated.
///
/// A helper that ends during a request (it was closing, or an odd picture crashed it)
/// gets one more try; after that the picture counts as without text. A helper that
/// cannot start at all is replaced by reading in this process, so the feature never
/// just stops working.
actor TextRecognitionClient {
    static let idleTimeout: Duration = .seconds(5)
    static let requestTimeout: Duration = .seconds(60)

    private let serviceName: String?
    private var connection: NSXPCConnection?
    private var openRequests = 0
    private var closeTask: Task<Void, Never>?
    private var reportedFallback = false
    /// The helper's process for the last answered request (self-test: it has to end).
    private(set) var lastHelperPID: pid_t?

    init(bundle: Bundle = .main) {
        let url = bundle.bundleURL
            .appendingPathComponent("Contents/XPCServices", isDirectory: true)
            .appendingPathComponent(TextRecognitionHelper.bundleName)
        serviceName = Bundle(url: url)?.bundleIdentifier
    }

    nonisolated var hasHelper: Bool {
        serviceName != nil
    }

    /// A picture from the history (PNG, TIFF …); larger ones are read scaled down.
    func text(inImageData data: Data, maxPixels: Int = TextRecognizer.defaultMaxPixels) async -> String? {
        guard let serviceName else {
            return await readHere(data, maxPixels: maxPixels)
        }
        openRequests += 1
        closeTask?.cancel()
        defer {
            openRequests -= 1
            if openRequests == 0 {
                scheduleClose()
            }
        }
        var outcome = await request(data, maxPixels: maxPixels, serviceName: serviceName)
        switch outcome {
        case .interrupted, .unavailable:
            outcome = await request(data, maxPixels: maxPixels, serviceName: serviceName)
        case .answered, .timedOut:
            break
        }
        switch outcome {
        case let .answered(text):
            return text
        case .unavailable:
            return await readHere(data, maxPixels: maxPixels)
        case .interrupted:
            Log.app.error("Texterkennung: Hilfsprozess zweimal beendet – Bild ohne Text")
            return nil
        case .timedOut:
            Log.app.error("Texterkennung: keine Antwort nach 60 s – Hilfsprozess beendet")
            return nil
        }
    }

    /// A captured selection (⇧⏎ in the screenshot overlay), sent as TIFF – quicker to
    /// write than PNG – and read at full size, as before the helper existed.
    func text(in image: ImageBox) async -> String? {
        guard let data = ImageConversion.tiff(image.image, scale: 1) else { return nil }
        return await text(inImageData: data, maxPixels: .max)
    }

    // MARK: Connection

    private enum Outcome: Sendable {
        case answered(String?)
        /// The helper ended with the request open.
        case interrupted
        /// No helper to talk to: it would not start, or the connection was closed.
        case unavailable
        case timedOut
    }

    /// The first of answer, error and timeout wins; later ones are ignored.
    private final class Reply: @unchecked Sendable {
        private let lock = NSLock()
        private var result: Outcome?
        private var waiting: CheckedContinuation<Outcome, Never>?

        func finish(_ outcome: Outcome) {
            let continuation: CheckedContinuation<Outcome, Never>? = lock.withLock {
                guard result == nil else { return nil }
                result = outcome
                defer { waiting = nil }
                return waiting
            }
            continuation?.resume(returning: outcome)
        }

        var outcome: Outcome {
            get async {
                await withCheckedContinuation { continuation in
                    let ready: Outcome? = lock.withLock {
                        if let result { return result }
                        waiting = continuation
                        return nil
                    }
                    if let ready {
                        continuation.resume(returning: ready)
                    }
                }
            }
        }
    }

    private func request(_ data: Data, maxPixels: Int, serviceName: String) async -> Outcome {
        let connection = openConnection(serviceName)
        let reply = Reply()
        let proxy = connection.remoteObjectProxyWithErrorHandler { error in
            reply.finish((error as? CocoaError)?.code == .xpcConnectionInterrupted ? .interrupted : .unavailable)
        } as? TextRecognitionXPC
        guard let proxy else { return .unavailable }
        proxy.recognizeText(in: data, maxPixels: maxPixels) { text in
            reply.finish(.answered(text))
        }
        let timeout = Task {
            do {
                try await Task.sleep(for: Self.requestTimeout)
                reply.finish(.timedOut)
            } catch {}
        }
        let outcome = await reply.outcome
        timeout.cancel()
        switch outcome {
        case .answered:
            lastHelperPID = connection.processIdentifier
        case .interrupted:
            // The connection stays usable: the next message starts a new helper.
            break
        case .unavailable:
            drop(connection)
        case .timedOut:
            // Stuck in Vision: end the helper, and its memory with it.
            drop(connection, killing: true)
        }
        return outcome
    }

    private func openConnection(_ serviceName: String) -> NSXPCConnection {
        if let connection {
            return connection
        }
        let connection = NSXPCConnection(serviceName: serviceName)
        connection.remoteObjectInterface = TextRecognitionHelper.makeInterface()
        connection.resume()
        self.connection = connection
        return connection
    }

    private func drop(_ connection: NSXPCConnection, killing: Bool = false) {
        let pid = connection.processIdentifier
        if killing, pid > 0 {
            kill(pid, SIGKILL)
        }
        connection.invalidate()
        if self.connection === connection {
            self.connection = nil
        }
    }

    /// Closing the connection ends the helper (XPCServices/TextRecognition/main.swift).
    private func scheduleClose() {
        closeTask?.cancel()
        closeTask = Task {
            do {
                try await Task.sleep(for: Self.idleTimeout)
            } catch {
                return
            }
            self.closeIfIdle()
        }
    }

    private func closeIfIdle() {
        guard openRequests == 0, let connection else { return }
        drop(connection)
    }

    private func readHere(_ data: Data, maxPixels: Int) async -> String? {
        if !reportedFallback {
            reportedFallback = true
            Log.app.error("Texterkennung: Hilfsprozess nicht verfügbar – lese im App-Prozess")
        }
        return await Task.detached(priority: Task.currentPriority) {
            TextRecognizer.text(inImageData: data, maxPixels: maxPixels)
        }.value
    }
}
