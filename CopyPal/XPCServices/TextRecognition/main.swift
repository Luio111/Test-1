import CopyPalSystem
import Foundation
import os

// CopyPal's text recognition helper (ROADMAP R32, ADR 0005). Vision runs here instead
// of in the app: CopyPal keeps a connection open while it has images to read and
// closes it after a few idle seconds. With the last connection gone this process
// ends, and Vision's models leave memory with it. Never logs or keeps image content.

final class Recognizer: NSObject, TextRecognitionXPC, Sendable {
    func recognizeText(in imageData: Data, maxPixels: Int, reply: @escaping @Sendable (String?) -> Void) {
        reply(TextRecognizer.text(inImageData: imageData, maxPixels: maxPixels))
    }
}

final class ServiceDelegate: NSObject, NSXPCListenerDelegate, Sendable {
    private let openConnections = OSAllocatedUnfairLock(initialState: 0)

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        connection.exportedInterface = TextRecognitionHelper.makeInterface()
        connection.exportedObject = Recognizer()
        let openConnections = self.openConnections
        openConnections.withLock { $0 += 1 }
        connection.invalidationHandler = {
            // CopyPal closed the connection or quit: nothing left to do.
            let remaining = openConnections.withLock {
                $0 -= 1
                return $0
            }
            if remaining == 0 {
                exit(0)
            }
        }
        connection.resume()
        return true
    }
}

let delegate = ServiceDelegate()
let listener = NSXPCListener.service()
listener.delegate = delegate
listener.resume()
