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
    private let text: Text
    let style: Theme.Tag

    init(text: LocalizedStringKey, style: Theme.Tag) {
        self.text = Text(text)
        self.style = style
    }

    /// Already localized or not to be translated.
    init(verbatim: String, style: Theme.Tag) {
        text = Text(verbatim: verbatim)
        self.style = style
    }

    var body: some View {
        text
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

/// The switch of a `SettingRow`. The row's title names it (also for VoiceOver), so
/// it has no own label – and no empty string that would land in the String Catalog.
struct RowSwitch: View {
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) { EmptyView() }
            .labelsHidden()
            .toggleStyle(.switch)
    }
}

/// One setting: title and optional explanation on the left, the control on the right.
struct SettingRow<Control: View>: View {
    let title: LocalizedStringKey
    var detail: LocalizedStringKey?
    @ViewBuilder let control: Control

    var body: some View {
        HStack(alignment: .center, spacing: Theme.Spacing.l) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textPrimary)
                if let detail {
                    Text(detail)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            control
        }
        .padding(.vertical, Theme.Spacing.s)
        .accessibilityElement(children: .combine)
    }
}

/// A page title with icon and subtitle, as used by every window.
struct PageHeader: View {
    let systemImage: String
    let title: LocalizedStringKey
    var subtitle: LocalizedStringKey?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Image(systemName: systemImage)
                .font(.system(size: 28))
                .foregroundStyle(Theme.Colors.textSecondary)
                .padding(.bottom, Theme.Spacing.xs)
                .accessibilityHidden(true)
            Text(title)
                .font(Theme.Typography.title)
                .foregroundStyle(Theme.Colors.textPrimary)
                .accessibilityAddTraits(.isHeader)
            if let subtitle {
                Text(subtitle)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
