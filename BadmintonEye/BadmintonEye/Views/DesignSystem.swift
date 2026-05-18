import SwiftUI

/// Centralized design tokens for an Apple-quality look-and-feel.
///
/// All views read color, typography, spacing, and motion from here so the app
/// feels coherent across the live-scoring hot path, system-style lists,
/// and full-bleed celebratory moments.
enum BE {

    // MARK: - Palette

    /// Team A — calibrated indigo/blue gradient, evocative of Apple Sports.
    enum TeamA {
        static let top = Color(red: 0.21, green: 0.40, blue: 0.95)   // vivid indigo
        static let bottom = Color(red: 0.09, green: 0.18, blue: 0.55) // deep navy
        static let accent = Color(red: 0.55, green: 0.78, blue: 1.00)

        static var gradient: LinearGradient {
            LinearGradient(colors: [top, bottom], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }

    /// Team B — refined warm magenta-to-ruby, away-team coded.
    enum TeamB {
        static let top = Color(red: 0.98, green: 0.34, blue: 0.45)   // coral
        static let bottom = Color(red: 0.62, green: 0.10, blue: 0.30) // ruby
        static let accent = Color(red: 1.00, green: 0.80, blue: 0.55)

        static var gradient: LinearGradient {
            LinearGradient(colors: [top, bottom], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }

    /// Service indicator — warm honey, high-contrast on either team gradient.
    static let serveAccent = Color(red: 1.00, green: 0.82, blue: 0.25)

    // MARK: - Typography

    /// Massive score numeral — SF Rounded, set in a weight that reads as
    /// confident but not blocky. Designed for live scores.
    static func scoreNumeral(size: CGFloat = 132) -> Font {
        .system(size: size, weight: .heavy, design: .rounded)
    }

    /// Display title for hero moments (match-end winner banner).
    static let displayTitle = Font.system(.largeTitle, design: .rounded).weight(.bold)

    /// Section eyebrow — small all-caps tracking label.
    static let eyebrow = Font.system(.caption2, design: .rounded).weight(.semibold)

    // MARK: - Shape & spacing

    /// Continuous-corner card shape used throughout.
    static func card(_ radius: CGFloat = 20) -> RoundedRectangle {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
    }

    /// Standard spacing scale (8-pt grid).
    enum Space {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 16
        static let l: CGFloat = 24
        static let xl: CGFloat = 32
    }

    // MARK: - Motion

    /// Bouncy spring used for score updates and overlay reveals.
    static let pop = Animation.spring(response: 0.35, dampingFraction: 0.62)
    /// Gentle spring for layout shifts.
    static let ease = Animation.spring(response: 0.45, dampingFraction: 0.85)
}

// MARK: - Apple-style tinted icon tile (for Settings rows)

struct SettingsIconTile: View {
    let systemName: String
    let tint: Color
    var size: CGFloat = 30

    var body: some View {
        ZStack {
            BE.card(7)
                .fill(tint)
            Image(systemName: systemName)
                .font(.system(size: size * 0.55, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

// MARK: - Floating glass pill (for live-match top bar)

struct GlassPill<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(.horizontal, BE.Space.m)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial, in: Capsule(style: .continuous))
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.18), radius: 14, y: 6)
    }
}

// MARK: - Glass circular icon button

struct GlassIconButton: View {
    let systemName: String
    var disabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().strokeBorder(Color.white.opacity(0.15), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
        }
        .disabled(disabled)
        .opacity(disabled ? 0.45 : 1.0)
    }
}
