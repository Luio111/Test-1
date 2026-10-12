import Observation
import SwiftUI

@MainActor
@Observable
final class PopupModel {
    var items: [PlaceholderClip] = PlaceholderClip.all
    var selectedIndex = 0
}

/// The history popup: a calm card below the notch. Numbers 1–8 paste, ⇧ pastes
/// without formatting, esc closes.
struct PopupView: View {
    static let width: CGFloat = 380

    let model: PopupModel
    let onSelect: @MainActor (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            VStack(spacing: Theme.Spacing.xxs) {
                ForEach(Array(model.items.enumerated()), id: \.element.id) { index, clip in
                    PopupRow(number: index + 1, clip: clip, isSelected: index == model.selectedIndex)
                        .onTapGesture { onSelect(index) }
                }
            }
            .padding(.horizontal, Theme.Spacing.s - Theme.Spacing.xxs)
            .padding(.bottom, Theme.Spacing.s - Theme.Spacing.xxs)
            Hairline()
            footer
        }
        .frame(width: Self.width)
        .background(Theme.Colors.background, in: RoundedRectangle(cornerRadius: Theme.Radius.panel))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.panel)
                .strokeBorder(Theme.Colors.divider)
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.panel))
    }

    private var header: some View {
        HStack {
            Text("Zuletzt kopiert")
                .font(Theme.Typography.label)
                .foregroundStyle(Theme.Colors.textSecondary)
            Spacer()
            StatusTag(text: "Platzhalter", style: .gray)
        }
        .padding(.horizontal, Theme.Spacing.m)
        .padding(.top, Theme.Spacing.m)
        .padding(.bottom, Theme.Spacing.s)
    }

    private var footer: some View {
        Text("1–8 einfügen · ⇧ ohne Formatierung · esc schließen")
            .font(Theme.Typography.caption)
            .foregroundStyle(Theme.Colors.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Theme.Spacing.m)
            .padding(.vertical, Theme.Spacing.s)
    }
}

private struct PopupRow: View {
    let number: Int
    let clip: PlaceholderClip
    let isSelected: Bool
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: Theme.Spacing.s) {
            Text(verbatim: "\(number)")
                .font(Theme.Typography.mono)
                .foregroundStyle(Theme.Colors.textSecondary)
                .frame(width: 18, height: 18)
                .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.tag))
            Image(systemName: clip.systemImage)
                .font(.system(size: 12))
                .foregroundStyle(Theme.Colors.textSecondary)
                .frame(width: 16)
                .accessibilityHidden(true)
            Text(verbatim: clip.preview)
                .font(clip.isBold ? Theme.Typography.bodyMedium.bold() : Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textPrimary)
                .lineLimit(1)
                .truncationMode(.tail)
            if clip.isMultiline {
                Text(verbatim: "…")
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.Spacing.s)
        .frame(height: 30)
        .background(
            (isSelected || isHovering) ? Theme.Colors.hover : .clear,
            in: RoundedRectangle(cornerRadius: Theme.Radius.control)
        )
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(verbatim: "\(number): \(clip.preview)"))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
