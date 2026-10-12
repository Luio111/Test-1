import SwiftUI

/// A page section: small gray label above its content, like Notion's sidebar groups.
struct SectionBlock<Content: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(title)
                .font(Theme.Typography.label)
                .foregroundStyle(Theme.Colors.textSecondary)
                .padding(.bottom, Theme.Spacing.xs)
            content
        }
    }
}

/// Label/value row in the style of Notion page properties.
struct PropertyRow<Value: View>: View {
    let label: LocalizedStringKey
    var systemImage: String?
    @ViewBuilder let value: Value

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.m) {
            HStack(spacing: Theme.Spacing.s) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 13))
                        .frame(width: 16)
                        .accessibilityHidden(true)
                }
                Text(label)
            }
            .font(Theme.Typography.body)
            .foregroundStyle(Theme.Colors.textSecondary)
            .frame(width: Theme.Layout.labelColumnWidth, alignment: .leading)

            value
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .padding(.vertical, Theme.Layout.rowVerticalPadding)
    }
}

/// Small colored tag for states (granted, missing, …).
struct StatusTag: View {
    let text: LocalizedStringKey
    let style: Theme.Tag

    var body: some View {
        Text(text)
            .font(Theme.Typography.caption)
            .foregroundStyle(style.foreground)
            .padding(.horizontal, Theme.Spacing.s - Theme.Spacing.xxs)
            .padding(.vertical, Theme.Spacing.xxs)
            .background(style.background, in: RoundedRectangle(cornerRadius: Theme.Radius.tag))
    }
}

struct Hairline: View {
    var body: some View {
        Rectangle()
            .fill(Theme.Colors.divider)
            .frame(height: 1)
    }
}

/// Quiet bordered button with hover background (secondary actions).
struct SubtleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        HoverableLabel(configuration: configuration, prominent: false)
    }
}

/// Filled accent button (one primary action per view).
struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        HoverableLabel(configuration: configuration, prominent: true)
    }
}

private struct HoverableLabel: View {
    let configuration: ButtonStyleConfiguration
    let prominent: Bool
    @State private var isHovering = false

    var body: some View {
        configuration.label
            .font(Theme.Typography.bodyMedium)
            .foregroundStyle(prominent ? Color.white : Theme.Colors.textPrimary)
            .padding(.horizontal, Theme.Spacing.m)
            .frame(height: 28)
            .background(background, in: RoundedRectangle(cornerRadius: Theme.Radius.control))
            .overlay {
                if !prominent {
                    RoundedRectangle(cornerRadius: Theme.Radius.control)
                        .strokeBorder(Theme.Colors.divider)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.control))
            .onHover { isHovering = $0 }
            .animation(Theme.Motion.quick, value: isHovering)
    }

    private var background: Color {
        if prominent {
            if configuration.isPressed { return Theme.Colors.accentFillPressed }
            return isHovering ? Theme.Colors.accentFillHover : Theme.Colors.accentFill
        }
        if configuration.isPressed { return Theme.Colors.pressed }
        return isHovering ? Theme.Colors.hover : .clear
    }
}
