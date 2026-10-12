import AppKit

/// Stand-in entries until the real history arrives (M4). Entry 1 is rich text so
/// "1" vs. "⇧1" can be checked in TextEdit.
struct PlaceholderClip: Identifiable {
    let id: Int
    let systemImage: String
    let plainText: String
    let isBold: Bool

    var preview: String {
        plainText.split(separator: "\n", omittingEmptySubsequences: true).first.map(String.init) ?? plainText
    }

    var isMultiline: Bool {
        plainText.contains("\n")
    }

    /// Writes the entry to `pasteboard`; with `plainText` only as unformatted text.
    func write(to pasteboard: NSPasteboard, plainText asPlainText: Bool) {
        pasteboard.clearContents()
        if isBold, !asPlainText, let rtf = boldRTF() {
            pasteboard.setData(rtf, forType: .rtf)
        }
        pasteboard.setString(plainText, forType: .string)
    }

    private func boldRTF() -> Data? {
        let text = NSAttributedString(string: plainText, attributes: [.font: NSFont.boldSystemFont(ofSize: 13)])
        return try? text.data(
            from: NSRange(location: 0, length: text.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )
    }

    static let all: [PlaceholderClip] = [
        PlaceholderClip(id: 1, systemImage: "bold", plainText: "Fett formatierter Text", isBold: true),
        PlaceholderClip(id: 2, systemImage: "text.alignleft", plainText: "Hallo! Das ist ein Platzhalter aus CopyPal.", isBold: false),
        PlaceholderClip(id: 3, systemImage: "link", plainText: "https://github.com/Luio111/Test-1", isBold: false),
        PlaceholderClip(id: 4, systemImage: "paintpalette", plainText: "#FF8800", isBold: false),
        PlaceholderClip(id: 5, systemImage: "text.alignleft", plainText: "Mehrzeiliger Text\nZweite Zeile\nDritte Zeile", isBold: false),
        PlaceholderClip(id: 6, systemImage: "envelope", plainText: "hallo@example.com", isBold: false),
        PlaceholderClip(id: 7, systemImage: "text.alignleft", plainText: "Lorem ipsum dolor sit amet, consectetur adipiscing elit.", isBold: false),
        PlaceholderClip(id: 8, systemImage: "text.alignleft", plainText: "Eintrag 8", isBold: false),
    ]
}
