import SwiftUI
import AppKit
import PruneCore

/// Spacing, radii, colours and reusable modifiers shared by every screen.
///
/// Colours are dynamic: in dark mode they match the near-black look of the
/// sibling apps, in light mode they fall back to the system semantic colours,
/// so the app follows whichever appearance is active.
enum Theme {
    // MARK: Spacing

    enum Spacing {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 24
    }

    // MARK: Corner radii

    enum Radius {
        static let small: CGFloat = 6
        static let card: CGFloat = 10
    }

    // MARK: Surfaces

    /// Detail pane background.
    static let background = Color(nsColor: dynamic(
        dark: NSColor(white: 0.075, alpha: 1),
        light: .windowBackgroundColor))

    /// Card fill.
    static let card = Color(nsColor: dynamic(
        dark: NSColor(white: 1, alpha: 0.05),
        light: .controlBackgroundColor))

    /// Card hairline border.
    static let cardBorder = Color(nsColor: dynamic(
        dark: NSColor(white: 1, alpha: 0.09),
        light: .separatorColor))

    /// Row hover highlight.
    static let hover = Color(nsColor: dynamic(
        dark: NSColor(white: 1, alpha: 0.04),
        light: NSColor(white: 0, alpha: 0.04)))

    static let tertiary = Color(nsColor: .tertiaryLabelColor)

    // MARK: Severity

    static func color(for severity: SizeSeverity) -> Color {
        switch severity {
        case .large: return .red
        case .medium: return .orange
        case .small: return .green
        }
    }

    /// Severity colour for an entry's size; unknown sizes are neutral.
    static func sizeColor(bytes: Int64, unknown: Bool) -> Color {
        unknown ? .gray : color(for: Formatter.sizeSeverity(bytes))
    }

    private static func dynamic(dark: NSColor, light: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        }
    }
}

/// Maps the 12 palette tokens from artifacts.json to SwiftUI colours.
enum Palette {
    static let colors: [String: Color] = [
        "green": .green,
        "mint": .mint,
        "orange": .orange,
        "red": .red,
        "brown": .brown,
        "yellow": .yellow,
        "teal": .teal,
        "blue": .blue,
        "purple": .purple,
        "cyan": .cyan,
        "pink": .pink,
        "gray": .gray,
    ]

    static func color(_ token: String?) -> Color {
        token.flatMap { colors[$0] } ?? .gray
    }
}

/// App-wide appearance preference. Dark is the default; "System" follows macOS.
enum AppearancePreference: String, CaseIterable, Identifiable {
    case dark, light, system

    static let storageKey = "appearance"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .dark: return "Dark"
        case .light: return "Light"
        case .system: return "Use System Setting"
        }
    }

    var nsAppearance: NSAppearance? {
        switch self {
        case .dark: return NSAppearance(named: .darkAqua)
        case .light: return NSAppearance(named: .aqua)
        case .system: return nil
        }
    }

    static var current: AppearancePreference {
        UserDefaults.standard.string(forKey: storageKey).flatMap(AppearancePreference.init) ?? .dark
    }

    /// Setting NSApp.appearance (rather than preferredColorScheme) also themes
    /// alerts, open panels and confirmation dialogs, and reverts cleanly to the
    /// system setting when cleared.
    @MainActor
    func apply() {
        NSApplication.shared.appearance = nsAppearance
    }
}

// MARK: - Modifiers

struct CardStyle: ViewModifier {
    var padding: CGFloat = Theme.Spacing.l

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).fill(Theme.card))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .stroke(Theme.cardBorder, lineWidth: 1)
            )
    }
}

struct BadgeStyle: ViewModifier {
    let color: Color

    func body(content: Content) -> some View {
        content
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(color)
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(color.opacity(0.15)))
            .fixedSize()
    }
}

struct SectionHeaderStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(.secondary)
            .textCase(.uppercase)
    }
}

extension View {
    /// Rounded card with the shared fill and hairline border.
    func cardStyle(padding: CGFloat = Theme.Spacing.l) -> some View {
        modifier(CardStyle(padding: padding))
    }

    /// Small tinted label, used for type, size and warning tags.
    func badge(color: Color) -> some View {
        modifier(BadgeStyle(color: color))
    }

    /// Small uppercase caption used above cards and sidebar groups.
    func sectionHeaderStyle() -> some View {
        modifier(SectionHeaderStyle())
    }
}
