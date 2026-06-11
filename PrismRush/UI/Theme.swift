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
