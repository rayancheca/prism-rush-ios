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
}
