import SwiftUI
import simd

/// Per-world palette (from the design spec). Colors are stored as linear 0…1 RGB triples so both
/// RealityKit (`UIColor`) and SwiftUI (`Color`) can consume them, and so Phase 4 can crossfade them.
struct WorldPalette: Sendable {
    let name: String
    let bg: SIMD3<Float>
    let grid: SIMD3<Float>
    let accent: SIMD3<Float>
    let accent2: SIMD3<Float>
}

enum Theme {
    static let worlds: [WorldPalette] = [
        WorldPalette(name: "Neon Metropolis", bg: rgb(0x07021A), grid: rgb(0xFF2BD6), accent: rgb(0x00F5FF), accent2: rgb(0xFF2BD6)),
        WorldPalette(name: "Crystal Caverns", bg: rgb(0x02141A), grid: rgb(0x00FFC8), accent: rgb(0xB26BFF), accent2: rgb(0x00FFC8)),
        WorldPalette(name: "Solar Sands",     bg: rgb(0x1C0A02), grid: rgb(0xFFB13D), accent: rgb(0xFF5E3A), accent2: rgb(0xFFD23D)),
    ]

    static func rgb(_ hex: UInt32) -> SIMD3<Float> {
        SIMD3(Float((hex >> 16) & 0xFF) / 255, Float((hex >> 8) & 0xFF) / 255, Float(hex & 0xFF) / 255)
    }

    static func mix(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ t: Float) -> SIMD3<Float> { a + (b - a) * t }

    static func color(_ v: SIMD3<Float>) -> Color { Color(red: Double(v.x), green: Double(v.y), blue: Double(v.z)) }
    static func color(_ hex: UInt32) -> Color { color(rgb(hex)) }

    /// The shared gold "claim/continue" gradient (daily button, CONTINUE, mission CLAIM).
    static let goldGradient = LinearGradient(colors: [color(0xFFD23D), color(0xFF9F1C)],
                                             startPoint: .leading, endPoint: .trailing)
    /// The shared cyan→magenta "action" gradient (PLAY-adjacent buttons, buy pills).
    static let actionGradient = LinearGradient(colors: [color(0x00F5FF), color(0xFF2BD6)],
                                               startPoint: .leading, endPoint: .trailing)
}

// MARK: - v1.3 visual system tokens (uiux §2 — names binding per V13_SPEC §C.4)

extension Theme {
    /// Role-based palette: meta chrome is neutral white-alpha on near-black; cyan is THE tap
    /// accent, gold means money/claim ONLY. World palettes stay inside the game + previews.
    enum Role {
        static let bg            = Theme.color(0x05010E)            // app background
        static let surface       = Color.white.opacity(0.06)        // cards, cells
        static let surfaceHi     = Color.white.opacity(0.10)        // raised/selected
        static let hairline      = Color.white.opacity(0.12)        // all strokes
        static let textPrimary   = Color.white
        static let textSecondary = Color.white.opacity(0.70)
        static let textTertiary  = Color.white.opacity(0.50)
        static let interactive   = Theme.color(0x00F5FF)            // THE tap accent (cyan)
        static let reward        = Theme.color(0xFFD23D)            // claim/coins/gold ONLY
        static let danger        = Color(red: 1, green: 0.37, blue: 0.37) // destructive/denied
        static let lock          = Color.white.opacity(0.35)        // locked states
    }

    /// Typography scale (R12: `TypeScale`, not the illegal `Type`). All `.rounded`; apply via
    /// `.typeScale(_:)` so every token is @ScaledMetric-backed and tracking collapses to 0 at
    /// accessibility sizes (uiux §2.3).
    enum TypeScale {
        case display, title, heading, body, caption, micro

        var size: CGFloat {
            switch self {
            case .display: 34; case .title: 22; case .heading: 17
            case .body: 13; case .caption: 11; case .micro: 9
            }
        }
        var weight: Font.Weight {
            switch self {
            case .display, .title: .heavy
            case .heading: .bold
            case .body: .medium
            case .caption, .micro: .semibold
            }
        }
        var tracking: CGFloat {
            switch self {
            case .caption: 1.5; case .micro: 2; default: 0
            }
        }
        var relativeTo: Font.TextStyle {
            switch self {
            case .display: .largeTitle; case .title: .title2; case .heading: .body
            case .body: .footnote; case .caption: .caption; case .micro: .caption2
            }
        }
    }

    /// Spacing tokens — replaces the 7/9/10/11/12/14/18/20/22 zoo (uiux §2.4).
    enum Space {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 16
        static let l: CGFloat = 24
        static let xl: CGFloat = 32
    }

    /// Corner radii: s = pills/chips, m = cells/rows, l = cards/primary buttons.
    enum Radius {
        static let s: CGFloat = 12
        static let m: CGFloat = 16
        static let l: CGFloat = 20
    }
}

/// Dynamic Type-aware application of a `Theme.TypeScale` token: the point size scales with the
/// user's text size (@ScaledMetric) and tracking zeroes out at accessibility sizes.
private struct TypeScaleModifier: ViewModifier {
    let token: Theme.TypeScale
    @ScaledMetric private var size: CGFloat
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(token: Theme.TypeScale) {
        self.token = token
        _size = ScaledMetric(wrappedValue: token.size, relativeTo: token.relativeTo)
    }

    func body(content: Content) -> some View {
        content
            .font(.system(size: size, weight: token.weight, design: .rounded))
            .tracking(dynamicTypeSize.isAccessibilitySize ? 0 : token.tracking)
    }
}

/// The ONE card treatment (uiux §2.4): `Role.surface` fill + token radius + hairline stroke,
/// no shadow — depth comes from the two surface levels. Every card/cell/row adopts it.
struct NeonCard: ViewModifier {
    var radius: CGFloat = Theme.Radius.m
    var raised = false

    func body(content: Content) -> some View {
        content
            .background(raised ? Theme.Role.surfaceHi : Theme.Role.surface,
                        in: RoundedRectangle(cornerRadius: radius))
            .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(Theme.Role.hairline))
    }
}

extension View {
    /// Apply a `Theme.TypeScale` token (font + tracking, Dynamic Type-backed).
    func typeScale(_ token: Theme.TypeScale) -> some View { modifier(TypeScaleModifier(token: token)) }
    /// Apply the shared `NeonCard` surface treatment.
    func neonCard(radius: CGFloat = Theme.Radius.m, raised: Bool = false) -> some View {
        modifier(NeonCard(radius: radius, raised: raised))
    }
}

/// Press feedback for every tappable neon surface: a quick squeeze + dim, so taps feel physical.
/// Replaces the inert `.plain` style on PLAY / hub / shop / skin / game-over buttons.
struct NeonButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .brightness(configuration.isPressed ? -0.06 : 0)
            .animation(.spring(duration: 0.18, bounce: 0.4), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == NeonButtonStyle {
    static var neon: NeonButtonStyle { NeonButtonStyle() }
}

/// Horizontal shake driven by an incrementing trigger — used for "can't afford" feedback on
/// skin cards / shop rows. One unit of `trigger` = three quick oscillations.
struct ShakeEffect: GeometryEffect {
    var travel: CGFloat = 7
    var trigger: CGFloat   // animate this from N to N+1 to shake once

    var animatableData: CGFloat {
        get { trigger }
        set { trigger = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: travel * sin(trigger * .pi * 6), y: 0))
    }
}
