import AppKit
import Observation
import SwiftUI
import CopyPalCore
import CopyPalServices
import CopyPalSystem

/// Icons, thumbnails and texts for history rows, shared by the popup and the history
/// window. Everything is cached in memory; thumbnails are also kept encrypted on
/// disk by the store (ROADMAP M6).
@MainActor
@Observable
final class ClipVisuals {
    private(set) var thumbnails: [UUID: NSImage] = [:]
    private(set) var favicons: [String: NSImage] = [:]

    @ObservationIgnored private let engine: HistoryEngine
    @ObservationIgnored private var appIcons: [String: NSImage] = [:]
    @ObservationIgnored private var appNames: [String: String] = [:]
    @ObservationIgnored private var pendingThumbnails: Set<UUID> = []
    @ObservationIgnored private var pendingFavicons: Set<String> = []
    @ObservationIgnored private let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        formatter.dateTimeStyle = .named
        return formatter
    }()

    init(engine: HistoryEngine) {
        self.engine = engine
    }

    // MARK: Text

    func title(for item: ClipItem) -> String {
        if item.isRemotePlaceholder {
            return String(localized: "Vom iPhone kopiert – Auswahl lädt den Inhalt")
        }
        if let masked = item.preview.masked {
            return masked
        }
        switch item.kind {
        case .image:
            if let source = item.preview.capturedFrom {
                // A screenshot: where it was taken is what tells two of them apart.
                return source.isEmpty ? String(localized: "Bildschirmfoto") : String(localized: "Bildschirmfoto · \(source)")
            }
            if let size = item.preview.imageSize {
                return String(localized: "Bild \(size.width) × \(size.height)")
            }
            return String(localized: "Bild")
        case .files:
            let names = item.preview.fileNames
            if names.count > 1 {
                return String(localized: "\(names.count) Dateien: \(names.joined(separator: ", "))")
            }
            return names.first ?? item.preview.title
        case .link:
            if let link = item.preview.link {
                return link.host + link.path
            }
            return item.preview.title
        case .text, .richText, .color, .other:
            return item.preview.title
        }
    }

    /// What an entry is, without its content (presentation mode): "Link", "Bild" …
    func kindLabel(for item: ClipItem) -> String {
        if item.isRemotePlaceholder {
            return String(localized: "Vom iPhone")
        }
        if let sensitivity = item.sensitivity {
            return sensitivityLabel(sensitivity)
        }
        switch item.kind {
        case .text: return String(localized: "Text")
        case .richText: return String(localized: "Formatierter Text")
        case .link: return String(localized: "Link")
        case .color: return String(localized: "Farbe")
        case .image: return item.preview.capturedFrom != nil ? String(localized: "Bildschirmfoto") : String(localized: "Bild")
        case .files:
            let fileCount = item.preview.fileNames.count
            return fileCount > 1 ? String(localized: "\(fileCount) Dateien") : String(localized: "Datei")
        case .other: return String(localized: "Eintrag")
        }
    }

    func systemImage(for item: ClipItem) -> String {
        if item.isRemotePlaceholder { return "iphone" }
        if let sensitivity = item.sensitivity {
            switch sensitivity {
            case .iban: return "building.columns"
            case .card: return "creditcard"
            case .secret: return "key"
            case .oneTimeCode: return "number"
            }
        }
        switch item.kind {
        case .text: return item.preview.lineCount > 1 ? "text.alignleft" : "text.justify.left"
        case .richText: return "textformat"
        case .link: return "link"
        case .color: return "paintpalette"
        case .image: return "photo"
        case .files: return item.preview.fileNames.count > 1 ? "doc.on.doc" : "doc"
        case .other: return "square.dashed"
        }
    }

    func sensitivityLabel(_ sensitivity: Sensitivity) -> String {
        switch sensitivity {
        case .iban: String(localized: "IBAN")
        case .card: String(localized: "Karte")
        case .secret: String(localized: "Schlüssel")
        case .oneTimeCode: String(localized: "Code")
        }
    }

    /// A favorite's own name, shown instead of its first line where room is short.
    func favoriteName(for item: ClipItem) -> String? {
        guard item.isPinned, let label = item.pinLabel?.trimmingCharacters(in: .whitespacesAndNewlines), !label.isEmpty else {
            return nil
        }
        return label
    }

    /// "noch 42 s" while a sensitive entry counts down to its deletion; nil otherwise.
    func remainingTime(for item: ClipItem, now: Date = Date()) -> String? {
        guard !item.isPinned, let expiresAt = item.expiresAt else { return nil }
        let seconds = max(Int(expiresAt.timeIntervalSince(now).rounded(.up)), 0)
        if seconds < 90 {
            return String(localized: "noch \(seconds) s")
        }
        let minuteCount = Int((Double(seconds) / 60).rounded())
        return String(localized: "noch \(minuteCount) min")
    }

    func relativeTime(for item: ClipItem, now: Date = Date()) -> String {
        if now.timeIntervalSince(item.lastUsedAt) < 60 {
            return String(localized: "gerade eben")
        }
        return relativeFormatter.localizedString(for: item.lastUsedAt, relativeTo: now)
    }

    // MARK: Source app

    func appIcon(for bundleID: String?) -> NSImage? {
        guard let bundleID else { return nil }
        if let cached = appIcons[bundleID] { return cached }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icon.size = NSSize(width: 32, height: 32)
        appIcons[bundleID] = icon
        return icon
    }

    /// Names of the source apps of `items`, for the search (bundle ID → name).
    func appNames(for items: [ClipItem]) -> [String: String] {
        var names: [String: String] = [:]
        for bundleID in Set(items.compactMap(\.sourceBundleID)) {
            names[bundleID] = appName(for: bundleID)
        }
        return names
    }

    func appName(for bundleID: String?) -> String? {
        guard let bundleID else { return nil }
        if let cached = appNames[bundleID] { return cached }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        let name = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        appNames[bundleID] = name
        return name
    }

    // MARK: Thumbnails

    /// The thumbnail if ready; otherwise starts making it (the view updates when done).
    func thumbnail(for item: ClipItem) -> NSImage? {
        guard item.kind == .image else { return nil }
        if let image = thumbnails[item.id] { return image }
        guard !pendingThumbnails.contains(item.id) else { return nil }
        pendingThumbnails.insert(item.id)
        let engine = engine
        let id = item.id
        Task {
            let data = await Self.makeThumbnail(id: id, engine: engine)
            self.pendingThumbnails.remove(id)
            if let data, let image = NSImage(data: data) {
                self.thumbnails[id] = image
            }
        }
        return nil
    }

    /// Cached encrypted thumbnail, or made from the stored PNG (off the main thread).
    nonisolated private static func makeThumbnail(id: UUID, engine: HistoryEngine) async -> Data? {
        if let cached = engine.store.thumbnail(for: id) {
            return cached
        }
        guard let png = try? await engine.representations(of: id).first(where: { $0.type == PasteboardTypeID.png })?.data,
              let thumbnail = ImageConversion.thumbnail(fromImageData: png, maxPixelSize: 256) else {
            return nil
        }
        engine.store.storeThumbnail(thumbnail, for: id)
        return thumbnail
    }

    // MARK: Website icons (ROADMAP D7: only when turned on)

    func favicon(for item: ClipItem) -> NSImage? {
        guard AppSettings.loadFavicons, let host = item.preview.link?.host else { return nil }
        if let image = favicons[host] { return image }
        guard !pendingFavicons.contains(host), let url = URL(string: "https://\(host)/favicon.ico") else { return nil }
        pendingFavicons.insert(host)
        Task {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 5
            configuration.httpCookieStorage = nil
            let session = URLSession(configuration: configuration)
            if let result = try? await session.data(from: url),
               (result.1 as? HTTPURLResponse)?.statusCode == 200,
               let image = NSImage(data: result.0) {
                self.favicons[host] = image
            }
        }
        return nil
    }
}

extension ClipItem {
    /// An iPhone copy recorded from its types only (`RemoteClipboardMode.onDemand`).
    var isRemotePlaceholder: Bool {
        origin == .remoteDevice && kind == .other && byteSize == 0
    }
}

/// The leading visual of a row: color swatch, thumbnail, website icon or symbol.
struct ClipLeadingVisual: View {
    let item: ClipItem
    let visuals: ClipVisuals
    var size: CGFloat = 20
    /// False in presentation mode: the symbol only, never a thumbnail or swatch.
    var showsContent = true

    var body: some View {
        Group {
            if !showsContent {
                Image(systemName: visuals.systemImage(for: item))
                    .font(.system(size: size * 0.62))
                    .foregroundStyle(Theme.Colors.textSecondary)
            } else if item.kind == .color, item.sensitivity == nil, let color = item.preview.color {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(.sRGB, red: color.red, green: color.green, blue: color.blue, opacity: color.alpha))
                    .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Theme.Colors.divider))
            } else if item.sensitivity == nil, let thumbnail = visuals.thumbnail(for: item) {
                // A picture found to hold an IBAN or a key shows its symbol only.
                // Square crop in the icon column: framed before clipping, so wide
                // screenshots do not spill over the number and the title.
                Image(nsImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Theme.Colors.divider))
            } else if let favicon = visuals.favicon(for: item) {
                Image(nsImage: favicon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding(2)
            } else {
                Image(systemName: visuals.systemImage(for: item))
                    .font(.system(size: size * 0.62))
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Trailing details: favorite pin, iPhone mark, relative time, source app icon.
struct ClipTrailingDetails: View {
    let item: ClipItem
    let visuals: ClipVisuals

    var body: some View {
        HStack(spacing: Theme.Spacing.xs + 2) {
            if item.isPinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .accessibilityLabel(Text("Favorit"))
            }
            if item.origin == .remoteDevice {
                Image(systemName: "iphone")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .accessibilityLabel(Text("Vom iPhone"))
            }
            if item.expiresAt != nil, !item.isPinned {
                // Counts down every second until the entry is deleted.
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(verbatim: visuals.remainingTime(for: item, now: context.date) ?? "")
                        .font(Theme.Typography.caption)
                        .monospacedDigit()
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .lineLimit(1)
                }
            } else {
                Text(verbatim: visuals.relativeTime(for: item))
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .lineLimit(1)
            }
            if let icon = visuals.appIcon(for: item.sourceBundleID) {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 14, height: 14)
                    .accessibilityLabel(Text(visuals.appName(for: item.sourceBundleID) ?? ""))
            }
        }
    }
}

/// Small tags after the title: "formatiert", sensitivity.
struct ClipTags: View {
    let item: ClipItem
    let visuals: ClipVisuals

    var body: some View {
        HStack(spacing: Theme.Spacing.xs) {
            if let sensitivity = item.sensitivity {
                StatusTag(verbatim: visuals.sensitivityLabel(sensitivity), style: .orange)
            } else if item.preview.isFormatted, item.kind == .richText {
                StatusTag(text: "formatiert", style: .gray)
            }
        }
    }
}
