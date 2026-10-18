import SwiftUI
import CopyPalCore

/// The popup (ROADMAP M7): the notch itself grows and drops down into a black panel.
/// Always dark, so the camera housing and the popup are one shape (Docs/Design.md,
/// variant A). Only the shape animates; the content is laid out once, revealed by the
/// growing shape and fades in row by row.
struct PopupRootView: View {
    let model: PopupModel
    let visuals: ClipVisuals
    let onSelect: @MainActor (Int) -> Void
    let onHover: @MainActor (Int) -> Void
    let onShowList: @MainActor (PopupList) -> Void

    private var layout: PopupLayout { model.layout }

    var body: some View {
        let silhouette = layout.silhouette(expanded: model.expanded)
        ZStack(alignment: .top) {
            silhouette
                .fill(Theme.Notch.fill)
                .shadow(color: .black.opacity(model.expanded ? 0.28 : 0), radius: 14, y: 6)
            PopupContent(model: model, visuals: visuals, onSelect: onSelect, onHover: onHover, onShowList: onShowList)
                .frame(width: layout.bodySize.width, height: layout.bodySize.height, alignment: .top)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .mask { silhouette }
        }
        .frame(width: layout.panelSize.width, height: layout.panelSize.height, alignment: .top)
        .environment(\.colorScheme, .dark)
    }
}

/// How the popup moves (ROADMAP M7: "falls" out of the notch).
enum PopupMotion {
    /// The shape drops down with a slight bounce. Kept as a `Spring` too, so a close
    /// during the opening can start from the size that is on screen.
    static let openSpring = Spring(duration: 0.42, bounce: 0.2)
    static let open = Animation.spring(openSpring)
    /// Back into the notch, without bounce.
    static let close = Animation.spring(duration: 0.26, bounce: 0)
    /// Fewer or more rows while searching.
    static let resize = Animation.spring(duration: 0.24, bounce: 0)
    /// Search and list switch beside the notch, footer.
    static let chrome = Animation.easeOut(duration: 0.2).delay(0.08)
    /// Delay before an animation starts, so its start state has been drawn once.
    static let firstFrame: TimeInterval = 0.02

    /// Rows follow the falling edge one after the other.
    static func row(_ index: Int) -> Animation {
        .spring(duration: 0.32, bounce: 0.12).delay(0.05 + Double(index) * 0.018)
    }
}

private struct PopupContent: View {
    let model: PopupModel
    let visuals: ClipVisuals
    let onSelect: @MainActor (Int) -> Void
    let onHover: @MainActor (Int) -> Void
    let onShowList: @MainActor (PopupList) -> Void

    var body: some View {
        let items = model.visibleItems
        VStack(spacing: 0) {
            band
                .frame(height: model.layout.bandHeight)
                .opacity(model.contentVisible ? 1 : 0)
                .animation(PopupMotion.chrome, value: model.contentVisible)
            if model.previewing, let item = model.selectedItem {
                PopupPreview(number: model.selectedIndex + 1, item: item, content: model.previews[item.id], visuals: visuals)
                    .frame(height: PopupMetrics.listHeight(rows: PopupMetrics.maxRows))
                    .opacity(model.contentVisible ? 1 : 0)
            } else if items.isEmpty {
                emptyState
                    .opacity(model.contentVisible ? 1 : 0)
                    .animation(PopupMotion.chrome, value: model.contentVisible)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        PopupRow(
                            number: index + 1,
                            item: item,
                            visuals: visuals,
                            isSelected: index == model.selectedIndex,
                            concealed: model.concealsContent
                        )
                            .onTapGesture { onSelect(index) }
                            .onHover { inside in
                                if inside { onHover(index) }
                            }
                            .opacity(model.contentVisible ? 1 : 0)
                            .offset(y: model.contentVisible ? 0 : -8)
                            .animation(PopupMotion.row(index), value: model.contentVisible)
                    }
                }
                .padding(.horizontal, PopupMetrics.listHorizontalPadding)
                .padding(.vertical, PopupMetrics.listVerticalPadding)
            }
            Spacer(minLength: 0)
            footer
                .opacity(model.contentVisible ? 1 : 0)
                .animation(PopupMotion.chrome, value: model.contentVisible)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("CopyPal"))
    }

    // MARK: Beside the notch

    /// Search on the left of the notch, list switch on the right; the middle stays
    /// free for the camera housing.
    private var band: some View {
        HStack(spacing: 0) {
            search
                .frame(width: model.layout.wingWidth, alignment: .leading)
            Spacer(minLength: model.layout.notchGap)
            listSwitch
                .frame(width: model.layout.wingWidth, alignment: .trailing)
        }
        .padding(.horizontal, PopupMetrics.wingPadding)
    }

    private var search: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.Notch.textSecondary)
                .accessibilityHidden(true)
            if model.query.isEmpty {
                Text("Tippen zum Suchen")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.Notch.textTertiary)
                    .lineLimit(1)
            } else {
                HStack(spacing: 1) {
                    Text(verbatim: model.query)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.Notch.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.head)
                    Rectangle()
                        .fill(Theme.Colors.accent)
                        .frame(width: 1.5, height: 14)
                        .accessibilityHidden(true)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("Suche: \(model.query)"))
            }
        }
    }

    /// Click or ⇥ switches between history and favorites.
    private var listSwitch: some View {
        HStack(spacing: 2) {
            switchLabel("Verlauf", list: .history)
            switchLabel("Favoriten", list: .favorites)
        }
        .padding(2)
        .background(Theme.Notch.control, in: Capsule())
    }

    private func switchLabel(_ title: LocalizedStringKey, list: PopupList) -> some View {
        let active = model.list == list
        return Button {
            onShowList(list)
        } label: {
            Text(title)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(active ? Theme.Notch.textPrimary : Theme.Notch.textSecondary)
                .lineLimit(1)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(active ? Theme.Notch.selection : .clear, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(active ? .isSelected : [])
    }

    // MARK: List and footer

    private var emptyState: some View {
        VStack(spacing: 2) {
            Text(emptyTitle)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.Notch.textPrimary)
            Text(emptyHint)
                .font(.system(size: 11))
                .foregroundStyle(Theme.Notch.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: PopupMetrics.emptyHeight)
    }

    private var emptyTitle: LocalizedStringKey {
        if !model.query.isEmpty { return "Keine Treffer" }
        return model.list == .history ? "Noch nichts kopiert" : "Noch keine Favoriten"
    }

    private var emptyHint: LocalizedStringKey {
        if !model.query.isEmpty { return "esc leert die Suche" }
        return model.list == .history ? "Kopiere etwas mit ⌘C – es erscheint hier." : "⌘P im Verlauf macht einen Eintrag zum Favoriten."
    }

    private var footer: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Theme.Notch.divider)
                .frame(height: 1)
                .padding(.horizontal, PopupMetrics.wingPadding)
            Group {
                if let notice = model.notice {
                    noticeLabel(notice)
                } else if model.concealsContent {
                    Label {
                        Text("Präsentationsmodus – Inhalte verborgen · 1–8 einfügen")
                    } icon: {
                        Image(systemName: "eye.slash")
                    }
                    .foregroundStyle(Theme.Notch.textSecondary)
                } else {
                    Text(footerText)
                        .foregroundStyle(Theme.Notch.textSecondary)
                }
            }
            .font(.system(size: 11))
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            .frame(maxWidth: .infinity)
            .frame(height: PopupMetrics.footerHeight - 1)
        }
    }

    private func noticeLabel(_ notice: PopupNotice) -> some View {
        HStack(spacing: 5) {
            switch notice {
            case .favoriteAdded:
                Image(systemName: "pin.fill").accessibilityHidden(true)
                Text("Zu Favoriten hinzugefügt")
            case .favoriteRemoved:
                Image(systemName: "pin.slash").accessibilityHidden(true)
                Text("Aus Favoriten entfernt")
            }
        }
        .foregroundStyle(Theme.Notch.textPrimary)
    }

    /// ⌘P toggles: "add" for a normal entry, "remove" for a favorite (always in the
    /// favorites list).
    private var footerText: LocalizedStringKey {
        if model.previewing {
            return "↩ einfügen · ⇧ ohne Formatierung · ↑↓ blättern · ← zurück"
        }
        if !model.query.isEmpty {
            return "↩ einfügen · ⌘1–8 Eintrag · ⇧↩ ohne Formatierung · esc Suche leeren"
        }
        if model.list == .favorites {
            return "1–8 einfügen · ⇧ ohne Formatierung · ⇥ Verlauf · ⌘P Favorit entfernen · → Vorschau"
        }
        if let selected = model.selectedItem, selected.isSensitive, !selected.isPinned {
            // A sensitive entry is deleted soon; a favorite stays.
            return "1–8 einfügen · ⇧ ohne Formatierung · ⇥ Favoriten · ⌘P behalten · → Vorschau"
        }
        return model.selectedItem?.isPinned == true
            ? "1–8 einfügen · ⇧ ohne Formatierung · ⇥ Favoriten · ⌘P Favorit entfernen · → Vorschau"
            : "1–8 einfügen · ⇧ ohne Formatierung · ⇥ Favoriten · ⌘P Favorit hinzufügen · → Vorschau"
    }
}

/// → : the selected entry in full – up to 4,000 characters of text, the whole link,
/// the picture, the color or the file names – in the room of the list.
private struct PopupPreview: View {
    let number: Int
    let item: ClipItem
    let content: PopupPreviewContent?
    let visuals: ClipVisuals

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            HStack(spacing: Theme.Spacing.s) {
                Text(verbatim: "\(number)")
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(Theme.Notch.textPrimary)
                    .frame(width: 16, height: 16)
                    .background(Theme.Notch.control, in: RoundedRectangle(cornerRadius: 4))
                    .accessibilityHidden(true)
                if let name = visuals.favoriteName(for: item) {
                    Text(verbatim: name)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.Notch.textPrimary)
                        .lineLimit(1)
                }
                Text(verbatim: visuals.kindLabel(for: item))
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.Notch.textSecondary)
                    .lineLimit(1)
                Spacer(minLength: Theme.Spacing.s)
                ClipTrailingDetails(item: item, visuals: visuals)
            }
            detail
        }
        .padding(.horizontal, PopupMetrics.listHorizontalPadding + Theme.Spacing.s)
        .padding(.vertical, Theme.Spacing.s)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var detail: some View {
        if item.isSensitive {
            Text(verbatim: visuals.title(for: item))
                .font(.system(size: 14, design: .monospaced))
                .foregroundStyle(Theme.Notch.textPrimary)
            Text("Sensibler Eintrag – der Inhalt bleibt verdeckt.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.Notch.textSecondary)
        } else if item.isRemotePlaceholder {
            Text("Vom iPhone kopiert – der Inhalt wird erst beim Einfügen geladen.")
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.Notch.textSecondary)
        } else {
            switch item.kind {
            case .color:
                colorDetail
            case .files:
                filesDetail
            case .image:
                imageDetail
            case .text, .richText, .link, .other:
                textDetail
            }
        }
    }

    @ViewBuilder
    private var textDetail: some View {
        switch content {
        case let .text(text):
            Text(verbatim: text)
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.Notch.textPrimary)
                .lineLimit(item.kind == .link ? 6 : 11)
                .truncationMode(item.kind == .link ? .middle : .tail)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .loading, nil:
            Text(verbatim: visuals.title(for: item))
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.Notch.textSecondary)
                .lineLimit(1)
        case .image, .unavailable:
            Text(verbatim: visuals.title(for: item))
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.Notch.textPrimary)
                .lineLimit(3)
        }
    }

    @ViewBuilder
    private var imageDetail: some View {
        if case let .image(image) = content {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: 158, alignment: .leading)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .accessibilityHidden(true)
        } else {
            RoundedRectangle(cornerRadius: 6)
                .fill(Theme.Notch.control)
                .frame(height: 158)
                .overlay {
                    if case .loading = content {
                        ProgressView().controlSize(.small)
                    }
                }
        }
        if let size = item.preview.imageSize {
            Text(verbatim: "\(size.width) × \(size.height) px")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Theme.Notch.textSecondary)
        }
    }

    private var colorDetail: some View {
        HStack(spacing: Theme.Spacing.m) {
            if let color = item.preview.color {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(.sRGB, red: color.red, green: color.green, blue: color.blue, opacity: color.alpha))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.Notch.divider))
                    .frame(width: 72, height: 72)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text(verbatim: color.hex)
                        .font(.system(size: 14, weight: .medium, design: .monospaced))
                        .foregroundStyle(Theme.Notch.textPrimary)
                    Text(verbatim: "R \(Int((color.red * 255).rounded())) · G \(Int((color.green * 255).rounded())) · B \(Int((color.blue * 255).rounded()))")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Theme.Notch.textSecondary)
                }
            } else {
                Text(verbatim: visuals.title(for: item))
                    .foregroundStyle(Theme.Notch.textPrimary)
            }
        }
    }

    private var filesDetail: some View {
        let names = item.preview.fileNames
        let moreCount = max(names.count - 9, 0)
        return VStack(alignment: .leading, spacing: 3) {
            ForEach(Array(names.prefix(9).enumerated()), id: \.offset) { _, name in
                Label {
                    Text(verbatim: name).lineLimit(1).truncationMode(.middle)
                } icon: {
                    Image(systemName: "doc")
                }
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.Notch.textPrimary)
            }
            if moreCount > 0 {
                Text("+\(moreCount) weitere")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.Notch.textSecondary)
            }
        }
    }
}

private struct PopupRow: View {
    let number: Int
    let item: ClipItem
    let visuals: ClipVisuals
    let isSelected: Bool
    /// Presentation mode: the kind instead of the content, no thumbnail.
    var concealed = false

    var body: some View {
        HStack(spacing: Theme.Spacing.s) {
            Text(verbatim: "\(number)")
                .font(.system(size: 11, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(isSelected ? Theme.Notch.textPrimary : Theme.Notch.textSecondary)
                .frame(width: 16, height: 16)
                .background(Theme.Notch.control, in: RoundedRectangle(cornerRadius: 4))
                .accessibilityHidden(true)
            ClipLeadingVisual(item: item, visuals: visuals, size: 18, showsContent: !concealed)
            if concealed {
                Text(verbatim: visuals.kindLabel(for: item))
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.Notch.textSecondary)
                    .lineLimit(1)
            } else if let name = visuals.favoriteName(for: item) {
                // Favorites that start alike are told apart by their names.
                Text(verbatim: name)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.Notch.textPrimary)
                    .lineLimit(1)
                    .layoutPriority(1)
                Text(verbatim: visuals.title(for: item))
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.Notch.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            } else {
                Text(verbatim: visuals.title(for: item))
                    .font(.system(size: 13))
                    .foregroundStyle(item.isRemotePlaceholder ? Theme.Notch.textSecondary : Theme.Notch.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            if !concealed, item.preview.lineCount > 1, item.kind == .text || item.kind == .richText, item.sensitivity == nil {
                Text(verbatim: "+\(item.preview.lineCount - 1)")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.Notch.textSecondary)
                    .accessibilityHidden(true)
            }
            if !concealed {
                ClipTags(item: item, visuals: visuals)
            }
            Spacer(minLength: Theme.Spacing.s)
            ClipTrailingDetails(item: item, visuals: visuals)
        }
        .padding(.horizontal, Theme.Spacing.s)
        .frame(height: PopupMetrics.rowHeight)
        .background(isSelected ? Theme.Notch.selection : .clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(verbatim: accessibilityTitle))
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }

    private var accessibilityTitle: String {
        if concealed {
            return "\(number): \(visuals.kindLabel(for: item))"
        }
        let title = visuals.title(for: item)
        if let name = visuals.favoriteName(for: item) {
            return "\(number): \(name), \(title)"
        }
        return "\(number): \(title)"
    }
}
