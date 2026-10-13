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
            if items.isEmpty {
                emptyState
                    .opacity(model.contentVisible ? 1 : 0)
                    .animation(PopupMotion.chrome, value: model.contentVisible)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        PopupRow(number: index + 1, item: item, visuals: visuals, isSelected: index == model.selectedIndex)
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
        if !model.query.isEmpty {
            return "↩ einfügen · ⌘1–8 Eintrag · ⇧↩ ohne Formatierung · esc Suche leeren"
        }
        if model.list == .favorites {
            return "1–8 einfügen · ⇧ ohne Formatierung · ⇥ Verlauf · ⌘P Favorit entfernen"
        }
        return model.selectedItem?.isPinned == true
            ? "1–8 einfügen · ⇧ ohne Formatierung · ⇥ Favoriten · ⌘P Favorit entfernen"
            : "1–8 einfügen · ⇧ ohne Formatierung · ⇥ Favoriten · ⌘P Favorit hinzufügen"
    }
}

private struct PopupRow: View {
    let number: Int
    let item: ClipItem
    let visuals: ClipVisuals
    let isSelected: Bool

    var body: some View {
        HStack(spacing: Theme.Spacing.s) {
            Text(verbatim: "\(number)")
                .font(.system(size: 11, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(isSelected ? Theme.Notch.textPrimary : Theme.Notch.textSecondary)
                .frame(width: 16, height: 16)
                .background(Theme.Notch.control, in: RoundedRectangle(cornerRadius: 4))
                .accessibilityHidden(true)
            ClipLeadingVisual(item: item, visuals: visuals, size: 18)
            Text(verbatim: visuals.title(for: item))
                .font(.system(size: 13))
                .foregroundStyle(item.isRemotePlaceholder ? Theme.Notch.textSecondary : Theme.Notch.textPrimary)
                .lineLimit(1)
                .truncationMode(.tail)
            if item.preview.lineCount > 1, item.kind == .text || item.kind == .richText, item.sensitivity == nil {
                Text(verbatim: "+\(item.preview.lineCount - 1)")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.Notch.textSecondary)
                    .accessibilityHidden(true)
            }
            ClipTags(item: item, visuals: visuals)
            Spacer(minLength: Theme.Spacing.s)
            ClipTrailingDetails(item: item, visuals: visuals)
        }
        .padding(.horizontal, Theme.Spacing.s)
        .frame(height: PopupMetrics.rowHeight)
        .background(isSelected ? Theme.Notch.selection : .clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(verbatim: "\(number): \(visuals.title(for: item))"))
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }
}
