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
    /// The 12 distinct worlds (v1.5). Each is its own theme, palette and (worlds 4–12) bespoke sky
    /// motif — no longer three families on a loop. Worlds 0–2 keep the original three families'
    /// identities (renamed); worlds 3–11 are new. `evolvedPalette` returns these unchanged for
    /// cycle 0 (ordinal 0–11) and only starts hue-rotating at ordinal 12 (the infinite-run tail).
    /// Every bg stays dark enough for dark-on-glow obstacles (decree 6) — including Singularity,
    /// whose "white endgame" reads through a radiant white motif on a deep-violet field, not a
    /// white background (which would break the dark-bg-only obstacle/ground/gem/FX materials).
    static let worlds: [WorldPalette] = [
        WorldPalette(name: "Pulse City",    bg: rgb(0x06021C), grid: rgb(0xFF2BD6), accent: rgb(0x18F0FF), accent2: rgb(0xFF49DE)),
        WorldPalette(name: "Geode Deep",    bg: rgb(0x02131A), grid: rgb(0x00FFC8), accent: rgb(0xB26BFF), accent2: rgb(0x35FFD8)),
        WorldPalette(name: "Solar Sands",   bg: rgb(0x1C0A02), grid: rgb(0xFFB13D), accent: rgb(0xFF5E3A), accent2: rgb(0xFFD23D)),
        WorldPalette(name: "Orbital Drift", bg: rgb(0x01030E), grid: rgb(0x2E5BFF), accent: rgb(0x6FE8FF), accent2: rgb(0xE9F4FF)),
        WorldPalette(name: "Tidal Glow",    bg: rgb(0x010F12), grid: rgb(0x0AE0D2), accent: rgb(0x33FFE0), accent2: rgb(0xB17BFF)),
        WorldPalette(name: "Ashfall",       bg: rgb(0x140402), grid: rgb(0xFF7A1A), accent: rgb(0xFF3D1A), accent2: rgb(0xFFC23D)),
        WorldPalette(name: "Borealis",      bg: rgb(0x040A14), grid: rgb(0x4FFFB0), accent: rgb(0x6FD8FF), accent2: rgb(0xC8A8FF)),
        WorldPalette(name: "Datastream",    bg: rgb(0x000308), grid: rgb(0x00E5FF), accent: rgb(0x18FFE0), accent2: rgb(0xFFFFFF)),
        WorldPalette(name: "Bloomfall",     bg: rgb(0x0E0414), grid: rgb(0xFF8FC8), accent: rgb(0xFFB3D9), accent2: rgb(0xFFE08A)),
        WorldPalette(name: "Eventide",      bg: rgb(0x040108), grid: rgb(0x9B3DFF), accent: rgb(0xFF6FD8), accent2: rgb(0xFFC04D)),
        WorldPalette(name: "Tempest",       bg: rgb(0x06061A), grid: rgb(0x6A5BFF), accent: rgb(0xBFA8FF), accent2: rgb(0xFFFFFF)),
        WorldPalette(name: "Singularity",   bg: rgb(0x140A2E), grid: rgb(0xFF4DA6), accent: rgb(0x4DC8FF), accent2: rgb(0xFFD24D)),
    ]

    static func rgb(_ hex: UInt32) -> SIMD3<Float> {
        SIMD3(Float((hex >> 16) & 0xFF) / 255, Float((hex >> 8) & 0xFF) / 255, Float(hex & 0xFF) / 255)
    }

    static func mix(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ t: Float) -> SIMD3<Float> { a + (b - a) * t }

    // MARK: - Distance-driven world evolution (v1.4.3, CODE_REVIEW.md §20.1)
    //
    // v1.5: there are 12 DISTINCT worlds (`worlds[ordinal % worlds.count]`), so cycle 0 is already
    // twelve different themes — no more "same art reshuffled". Beyond the authored set (ordinal ≥
    // 12) the infinite run keeps diverging: `evolvedPalette` keeps each world's base identity but
    // makes every CYCLE (`ordinal / worlds.count`) a visible transformation — the hue rotates a step
    // (wraps, so it's safe for unbounded infinite runs), saturation/contrast intensify up to a
    // cap (deep runs stay vivid, never muddy), and the background deepens for atmosphere. It is a
    // PURE function of the ABSOLUTE ordinal — no RNG, no sim state — so the deterministic core is
    // untouched (rule 2/3) and the same ordinal always looks identical. Cycle 0 (worlds 0/1/2) is
    // the identity, so the established first-cycle look and its screenshots/previews are preserved.

    /// Cap on the cycles over which density/saturation/contrast keep ramping. Hue still rotates
    /// past this (it wraps), so deeper worlds keep diverging without degenerating to black/grey.
    static let evolutionRampCycles = 4

    /// The palette for an absolute world `ordinal`, with per-cycle hue rotation + intensification
    /// layered onto the base family. Cycle 0 returns the base family unchanged.
    static func evolvedPalette(ordinal: Int) -> WorldPalette {
        let o = max(0, ordinal)
        // BOTH divisors are worlds.count (v1.5): the family index AND the cycle move together, so
        // ordinals 0–11 are cycle 0 (strict identity to the authored palettes) and evolution only
        // begins at ordinal 12 ("Pulse City II"…). Using /3 here would give world 3 cycle 1 and a
        // spurious roman suffix + hue rotation on first sight.
        let base = worlds[o % worlds.count]
        let cycle = o / worlds.count
        guard cycle > 0 else { return base }

        let hueShift = Float(cycle) * 0.137                      // ≈ 49° per cycle, wraps
        let intens = Float(min(cycle, evolutionRampCycles))
        let satBoost = intens * 0.05
        func shift(_ v: SIMD3<Float>, satAdd: Float, valScale: Float) -> SIMD3<Float> {
            var hsb = rgbToHSB(v)
            hsb.x += hueShift
            hsb.y = min(1, hsb.y + satAdd)
            hsb.z = min(1, max(0, hsb.z * valScale))
            return hsbToRGB(hsb)
        }
        return WorldPalette(
            name: base.name + " " + roman(cycle + 1),
            bg: shift(base.bg, satAdd: 0.02 * intens, valScale: 1 - 0.05 * intens),   // deepen
            grid: shift(base.grid, satAdd: satBoost, valScale: 1),
            accent: shift(base.accent, satAdd: satBoost, valScale: 1),
            accent2: shift(base.accent2, satAdd: satBoost, valScale: 1))
    }

    /// RGB (0…1) → HSB (h in turns 0…1, s, b). Pure; used only by `evolvedPalette`.
    static func rgbToHSB(_ c: SIMD3<Float>) -> SIMD3<Float> {
        let r = c.x, g = c.y, b = c.z
        let mx = max(r, max(g, b)), mn = min(r, min(g, b))
        let d = mx - mn
        var h: Float = 0
        if d > 0 {
            if mx == r { h = (g - b) / d; if h < 0 { h += 6 } }
            else if mx == g { h = (b - r) / d + 2 }
            else { h = (r - g) / d + 4 }
            h /= 6
        }
        return SIMD3(h, mx == 0 ? 0 : d / mx, mx)
    }

    /// HSB (h in turns) → RGB (0…1). Pure inverse of `rgbToHSB`.
    static func hsbToRGB(_ c: SIMD3<Float>) -> SIMD3<Float> {
        let h = (c.x - floor(c.x)) * 6, s = c.y, v = c.z
        let i = Int(h)
        let f = h - Float(i)
        let p = v * (1 - s), q = v * (1 - s * f), t = v * (1 - s * (1 - f))
        switch i % 6 {
        case 0: return SIMD3(v, t, p)
        case 1: return SIMD3(q, v, p)
        case 2: return SIMD3(p, v, t)
        case 3: return SIMD3(p, q, v)
        case 4: return SIMD3(t, p, v)
        default: return SIMD3(v, p, q)
        }
    }

    /// Compact Roman numeral for the world name suffix (cycle tier). Falls back to Arabic past
    /// the table — a 30th cycle is theoretical, but the name must never break.
    static func roman(_ n: Int) -> String {
        let table: [(Int, String)] = [(10, "X"), (9, "IX"), (5, "V"), (4, "IV"), (1, "I")]
        guard n > 0, n < 40 else { return "\(n)" }
        var v = n, s = ""
        for (value, sym) in table { while v >= value { s += sym; v -= value } }
        return s
    }

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

/// Dynamic-Type-aware system font that preserves an explicit weight/design (unlike `typeScale`,
/// which bundles a token's weight). The point size scales with the user's text size via
/// `@ScaledMetric`, so screens that need a bespoke size/weight — the tutorial, pause menu, profile
/// — still respect accessibility text sizes instead of hardcoding `.system(size:)` (v1.4.3, M3).
private struct ScaledFontModifier: ViewModifier {
    @ScaledMetric private var size: CGFloat
    let weight: Font.Weight
    let design: Font.Design

    init(size: CGFloat, weight: Font.Weight, design: Font.Design, relativeTo: Font.TextStyle) {
        _size = ScaledMetric(wrappedValue: size, relativeTo: relativeTo)
        self.weight = weight
        self.design = design
    }

    func body(content: Content) -> some View {
        content.font(.system(size: size, weight: weight, design: design))
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
    /// Dynamic-Type-aware `.system` font with an explicit weight/design (see `ScaledFontModifier`).
    /// Use when a surface needs a bespoke size/weight outside the six `TypeScale` tokens.
    func scaledFont(_ size: CGFloat, weight: Font.Weight = .regular,
                    design: Font.Design = .rounded, relativeTo: Font.TextStyle = .body) -> some View {
        modifier(ScaledFontModifier(size: size, weight: weight, design: design, relativeTo: relativeTo))
    }
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
