import AppKit
import SwiftUI

/// CopyPal design tokens: calm, reduced, Notion-like. Warm grays instead of pure
/// black, hierarchy through size, weight and gray levels, one accent color, hairline
/// dividers instead of boxes, no heavy shadows. See Docs/Design.md.
enum Theme {
    enum Colors {
        static let background = Color.dynamic(light: 0xFFFFFF, dark: 0x191919)
        static let surface = Color.dynamic(light: 0xF7F7F5, dark: 0x202020)
        static let textPrimary = Color.dynamic(light: 0x37352F, dark: 0xFFFFFF, darkAlpha: 0.81)
        // Slightly darker than Notion's #787774 to reach WCAG AA (4.8:1 on white).
        static let textSecondary = Color.dynamic(light: 0x73726E, dark: 0x9B9B9B)
        /// Decorative only (placeholders, disabled); too little contrast for information.
        static let textTertiary = Color.dynamic(light: 0xA5A29C, dark: 0x6F6F6F)
        static let divider = Color.dynamic(light: 0x37352F, lightAlpha: 0.09, dark: 0xFFFFFF, darkAlpha: 0.094)
        static let hover = Color.dynamic(light: 0x37352F, lightAlpha: 0.06, dark: 0xFFFFFF, darkAlpha: 0.055)
        static let pressed = Color.dynamic(light: 0x37352F, lightAlpha: 0.12, dark: 0xFFFFFF, darkAlpha: 0.1)
        static let accent = Color.dynamic(light: 0x2383E2, dark: 0x2383E2)
        /// Fills for the primary button: darker than `accent` so white text reaches WCAG AA.
        static let accentFill = Color.dynamic(light: 0x1C6FC2, dark: 0x1C6FC2)
        static let accentFillHover = Color.dynamic(light: 0x1A6AB8, dark: 0x1A6AB8)
        static let accentFillPressed = Color.dynamic(light: 0x165FA6, dark: 0x165FA6)

        static let windowBackground = NSColor.dynamic(light: 0xFFFFFF, dark: 0x191919)
    }

    /// Notion-style tag colors: tinted background, dark text in light mode.
    enum Tag {
        case gray, green, orange, red, blue

        var background: Color {
            switch self {
            case .gray: Color.dynamic(light: 0xE3E2E0, dark: 0x373737)
            case .green: Color.dynamic(light: 0xDBEDDB, dark: 0x2B593F)
            case .orange: Color.dynamic(light: 0xFADEC9, dark: 0x854C1D)
            case .red: Color.dynamic(light: 0xFFE2DD, dark: 0x6E3630)
            case .blue: Color.dynamic(light: 0xD3E5EF, dark: 0x28456C)
            }
        }

        var foreground: Color {
            switch self {
            case .gray: Color.dynamic(light: 0x32302C, dark: 0xFFFFFF, darkAlpha: 0.81)
            case .green: Color.dynamic(light: 0x1C3829, dark: 0xFFFFFF, darkAlpha: 0.81)
            case .orange: Color.dynamic(light: 0x49290E, dark: 0xFFFFFF, darkAlpha: 0.81)
            case .red: Color.dynamic(light: 0x5D1715, dark: 0xFFFFFF, darkAlpha: 0.81)
            case .blue: Color.dynamic(light: 0x183347, dark: 0xFFFFFF, darkAlpha: 0.81)
            }
        }
    }

    enum Typography {
        static let title = Font.system(size: 24, weight: .bold)
        static let body = Font.system(size: 14)
        static let bodyMedium = Font.system(size: 14, weight: .medium)
        static let label = Font.system(size: 12, weight: .medium)
        static let caption = Font.system(size: 12)
        static let mono = Font.system(size: 12, design: .monospaced)
    }

    enum Spacing {
        static let xxs: CGFloat = 2
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
    }

    /// Fixed layout metrics outside the spacing scale.
    enum Layout {
        static let pageHorizontalPadding: CGFloat = 40
        /// Room for the transparent title bar.
        static let pageTopPadding: CGFloat = 44
        static let rowVerticalPadding: CGFloat = 6
        static let labelColumnWidth: CGFloat = 168
        static let windowSize = CGSize(width: 620, height: 680)
    }

    enum Radius {
        static let control: CGFloat = 6
        static let tag: CGFloat = 4
        static let panel: CGFloat = 12
    }

    enum Motion {
        static let quick = Animation.easeOut(duration: 0.15)
    }

    /// The popup and status capsule at the notch are always black like the camera
    /// housing (Docs/Design.md, variant A), so they use fixed light-on-black colors.
    enum Notch {
        static let fill = Color.black
        static let textPrimary = Color.white.opacity(0.92)
        /// Information on black: white at 60 % reaches 6.3:1.
        static let textSecondary = Color.white.opacity(0.6)
        /// Decorative only (placeholder).
        static let textTertiary = Color.white.opacity(0.4)
        static let selection = Color.white.opacity(0.14)
        static let control = Color.white.opacity(0.1)
        static let divider = Color.white.opacity(0.08)
    }
}

extension NSColor {
    /// Light/dark color from hex values. Only plain values are captured, so the
    /// provider stays `Sendable`.
    static func dynamic(light: UInt32, lightAlpha: CGFloat = 1, dark: UInt32, darkAlpha: CGFloat = 1) -> NSColor {
        NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return isDark ? NSColor(hex: dark, alpha: darkAlpha) : NSColor(hex: light, alpha: lightAlpha)
        }
    }

    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}

extension Color {
    static func dynamic(light: UInt32, lightAlpha: CGFloat = 1, dark: UInt32, darkAlpha: CGFloat = 1) -> Color {
        Color(nsColor: .dynamic(light: light, lightAlpha: lightAlpha, dark: dark, darkAlpha: darkAlpha))
    }
}
