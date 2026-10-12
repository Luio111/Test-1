import SwiftUI
import CopyPalCore

/// The popup: a calm card that grows out of the notch (ROADMAP M7). The black shape
/// starts at the notch and morphs into the card; the content fades in on top.
struct PopupRootView: View {
    let model: PopupModel
    let visuals: ClipVisuals
    let onSelect: @MainActor (Int) -> Void

    private var layout: PopupLayout { model.layout }

    var body: some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: model.expanded ? Theme.Radius.panel : layout.startRadius, style: .continuous)
                .fill(model.expanded ? Theme.Colors.background : Color.black)
                .overlay {
                    RoundedRectangle(cornerRadius: model.expanded ? Theme.Radius.panel : layout.startRadius, style: .continuous)
                        .strokeBorder(model.expanded ? Theme.Colors.divider : .clear)
                }
                .frame(
                    width: model.expanded ? layout.cardSize.width : layout.startSize.width,
                    height: model.expanded ? layout.cardSize.height : layout.startSize.height
                )
                .offset(y: model.expanded ? layout.cardTop : layout.startTop)
                .shadow(color: .black.opacity(model.expanded ? 0.12 : 0), radius: 12, y: 4)

            PopupCard(model: model, visuals: visuals, onSelect: onSelect)
                .frame(width: layout.cardSize.width, height: layout.cardSize.height)
                .offset(y: layout.cardTop)
                .opacity(model.contentVisible ? 1 : 0)
        }
        .frame(width: layout.panelSize.width, height: layout.panelSize.height, alignment: .top)
    }
}

private struct PopupCard: View {
    let model: PopupModel
    let visuals: ClipVisuals
    let onSelect: @MainActor (Int) -> Void

    var body: some View {
        let items = model.visibleItems
        VStack(alignment: .leading, spacing: 0) {
            header
            Hairline()
            if items.isEmpty {
                emptyState
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        PopupRow(number: index + 1, item: item, visuals: visuals, isSelected: index == model.selectedIndex)
                            .onTapGesture { onSelect(index) }
                    }
                }
                .padding(.horizontal, PopupMetrics.listPadding)
                .padding(.vertical, PopupMetrics.listPadding)
            }
            Spacer(minLength: 0)
            Hairline()
            footer
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("CopyPal"))
    }

    private var header: some View {
        HStack(spacing: Theme.Spacing.s) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13))
                .foregroundStyle(Theme.Colors.textSecondary)
                .accessibilityHidden(true)
            if model.query.isEmpty {
                Text("Tippen zum Suchen")
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textTertiary)
            } else {
                HStack(spacing: 1) {
                    Text(verbatim: model.query)
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.head)
                    Rectangle()
                        .fill(Theme.Colors.accent)
                        .frame(width: 1.5, height: 16)
                        .accessibilityHidden(true)
                }
                .accessibilityLabel(Text("Suche: \(model.query)"))
            }
            Spacer(minLength: Theme.Spacing.s)
            listSwitch
        }
        .padding(.horizontal, Theme.Spacing.m)
        .frame(height: PopupMetrics.headerHeight)
    }

    private var listSwitch: some View {
        HStack(spacing: 2) {
            switchLabel("Verlauf", active: model.list == .history)
            switchLabel("Favoriten", active: model.list == .favorites)
        }
        .padding(2)
        .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.control))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(model.list == .history ? Text("Verlauf, ⇥ wechselt zu Favoriten") : Text("Favoriten, ⇥ wechselt zum Verlauf"))
    }

    private func switchLabel(_ title: LocalizedStringKey, active: Bool) -> some View {
        Text(title)
            .font(Theme.Typography.label)
            .foregroundStyle(active ? Theme.Colors.textPrimary : Theme.Colors.textSecondary)
            .padding(.horizontal, Theme.Spacing.s)
            .padding(.vertical, 3)
            .background(active ? Theme.Colors.background : .clear, in: RoundedRectangle(cornerRadius: Theme.Radius.tag))
    }

    private var emptyState: some View {
        VStack(spacing: Theme.Spacing.xs) {
            Text(emptyTitle)
                .font(Theme.Typography.bodyMedium)
                .foregroundStyle(Theme.Colors.textPrimary)
            Text(emptyHint)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
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
        Text(footerText)
            .font(Theme.Typography.caption)
            .foregroundStyle(Theme.Colors.textSecondary)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Theme.Spacing.m)
            .frame(height: PopupMetrics.footerHeight)
    }

    private var footerText: LocalizedStringKey {
        if model.query.isEmpty {
            "1–8 einfügen · ⇧ ohne Formatierung · ⇥ Favoriten · ⌘P anpinnen · esc"
        } else {
            "↩ einfügen · ⌘1–8 Eintrag · ⇧↩ ohne Formatierung · esc Suche leeren"
        }
    }
}

private struct PopupRow: View {
    let number: Int
    let item: ClipItem
    let visuals: ClipVisuals
    let isSelected: Bool
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: Theme.Spacing.s) {
            Text(verbatim: "\(number)")
                .font(Theme.Typography.mono)
                .foregroundStyle(Theme.Colors.textSecondary)
                .frame(width: 18, height: 18)
                .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.tag))
                .accessibilityHidden(true)
            ClipLeadingVisual(item: item, visuals: visuals, size: 20)
            Text(verbatim: visuals.title(for: item))
                .font(Theme.Typography.body)
                .foregroundStyle(item.isRemotePlaceholder ? Theme.Colors.textSecondary : Theme.Colors.textPrimary)
                .lineLimit(1)
                .truncationMode(.tail)
            if item.preview.lineCount > 1, item.kind == .text || item.kind == .richText, item.sensitivity == nil {
                Text(verbatim: "+\(item.preview.lineCount - 1)")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .accessibilityHidden(true)
            }
            ClipTags(item: item, visuals: visuals)
            Spacer(minLength: Theme.Spacing.s)
            ClipTrailingDetails(item: item, visuals: visuals)
        }
        .padding(.horizontal, Theme.Spacing.s)
        .frame(height: PopupMetrics.rowHeight)
        .background(
            (isSelected || isHovering) ? Theme.Colors.hover : .clear,
            in: RoundedRectangle(cornerRadius: Theme.Radius.control)
        )
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(verbatim: "\(number): \(visuals.title(for: item))"))
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }
}
