import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// A piece of text found in an image, with its box in normalized image coordinates
/// (0…1, origin bottom left, as Vision reports it).
public struct RecognizedLine: Sendable, Equatable {
    public var text: String
    public var box: CGRect

    public init(text: String, box: CGRect) {
        self.text = text
        self.box = box
    }
}

public enum RecognizedText {
    /// The pieces in reading order: top to bottom; pieces on one line (their centres
    /// closer than half the smaller height) left to right, joined by a space. Nil
    /// when there is no text.
    public static func join(_ lines: [RecognizedLine]) -> String? {
        let pieces = lines
            .map { RecognizedLine(text: $0.text.trimmingCharacters(in: .whitespacesAndNewlines), box: $0.box) }
            .filter { !$0.text.isEmpty }
            .sorted { $0.box.midY > $1.box.midY }
        var rows: [[RecognizedLine]] = []
        for piece in pieces {
            if let first = rows.last?.first,
               abs(first.box.midY - piece.box.midY) < min(first.box.height, piece.box.height) / 2 {
                rows[rows.count - 1].append(piece)
            } else {
                rows.append([piece])
            }
        }
        let text = rows
            .map { row in row.sorted { $0.box.minX < $1.box.minX }.map(\.text).joined(separator: " ") }
            .joined(separator: "\n")
        return text.isEmpty ? nil : text
    }
}
