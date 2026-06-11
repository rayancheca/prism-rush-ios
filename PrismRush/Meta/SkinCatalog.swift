import Foundation

/// A procedural character skin (no asset files): colors + rig geometry + idle personality, one
/// recipe shared by the RealityKit rig rebuild and the SwiftUI Canvas previews. `bodyHex == 0`
/// means "follow the live world accent" — Prism only — and `trailHex == nil` likewise.
/// Not Codable, never persisted: only ids are stored, so catalog evolution can't corrupt saves.
struct Skin: Identifiable, Sendable {
    enum BodyShape: Sendable { case sphere, cube, crystal }
    enum PupilStyle: Sendable { case dot, wide, slit, glint }
    enum Rarity: Int, Sendable, Comparable {
        case common = 0, rare, epic, legendary
        // Raw-typed enums do NOT synthesize Comparable — rawValue order IS the rarity ladder.
        static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
    }
    enum Unlock: Equatable, Sendable {
        case free, coins(Int), level(Int)
        case achievement(id: String, tier: Int), challengeDays(Int), iap
    }
    /// Idle personality — drives the Canvas preview bob/blink/sway AND the in-run antenna sway.
    struct Idle: Sendable {
        var bobSpeed: Double = 1.6               // Hz
        var bobAmp: Double = 0.05                // fraction of swatch size
        var blinkMin: Double = 2.2, blinkMax: Double = 4.2
        var sway: Double = 0.12                  // antenna sway amplitude, radians
    }

    let id, name, flavor: String
    let bodyHex, antennaHex: UInt32          // bodyHex 0 = followsWorld (Prism only)
    var trailHex: UInt32? = nil              // nil = follow world accent (Prism only)
    var bodyShape: BodyShape = .sphere
    var scale: Float = 1                     // visual only, 0.85...1.12 — never the hitbox
    var eyeRadius: Float = 0.13
    var eyeTintHex: UInt32 = 0xFFFFFF
    var pupilStyle: PupilStyle = .dot
    var antennaHeightScale: Float = 1
    var antennaTipScale: Float = 1
    var idle: Idle = Idle()
    let rarity: Rarity
    let unlock: Unlock

    var followsWorld: Bool { bodyHex == 0 }
    var premium: Bool { unlock == .iap }                                // back-compat
    var cost: Int { if case .coins(let c) = unlock { c } else { 0 } }   // back-compat
}

enum SkinCatalog {
    /// The 16-character roster (DESIGN_characters §2), ordered rarity → unlock difficulty — the
    /// select grid renders catalog order inside each rarity section. The legacy 7 keep their ids,
    /// hexes, and coin costs exactly (pinned by tests); Fang is 2,500 — the week-1 savings goal
    /// (R4). Rarity census: Common 4 · Rare 6 · Epic 4 · Legendary 2.
    static let all: [Skin] = [
        // COMMON ──────────────────────────────────────────────────────────────────────────────
        Skin(id: "default", name: "Prism", flavor: "Born of every world, loyal to none.",
             bodyHex: 0, antennaHex: 0,
             rarity: .common, unlock: .free),
        Skin(id: "ember", name: "Ember", flavor: "Runs hot. Cools never.",
             bodyHex: 0xFF5E3A, antennaHex: 0xFFD23D, trailHex: 0xFF7A3D,
             idle: .init(bobSpeed: 1.9, bobAmp: 0.06, blinkMin: 2.0, blinkMax: 3.6, sway: 0.15),
             rarity: .common, unlock: .coins(200)),
        Skin(id: "bolt", name: "Bolt", flavor: "First off the line. Every line.",
             bodyHex: 0x00B3FF, antennaHex: 0xFFFFFF, trailHex: 0x00B3FF, scale: 0.95,
             idle: .init(bobSpeed: 2.6, bobAmp: 0.07, blinkMin: 1.2, blinkMax: 2.4, sway: 0.20),
             rarity: .common, unlock: .coins(300)),
        Skin(id: "pebble", name: "Pebble", flavor: "Small. Round-ish. Unbothered.",
             bodyHex: 0x8E9BAE, antennaHex: 0xFFB13D, trailHex: 0xAFC2D9,
             bodyShape: .cube, scale: 0.85, eyeRadius: 0.11, pupilStyle: .wide,
             antennaHeightScale: 0.6, antennaTipScale: 0.9,
             idle: .init(bobSpeed: 0.8, bobAmp: 0.03, blinkMin: 3.5, blinkMax: 6.0, sway: 0.05),
             rarity: .common, unlock: .level(3)),
        // RARE ────────────────────────────────────────────────────────────────────────────────
        Skin(id: "void", name: "Void", flavor: "It stares back.",
             bodyHex: 0xB26BFF, antennaHex: 0x00FFC8, trailHex: 0xB26BFF,
             eyeRadius: 0.14, pupilStyle: .wide,
             idle: .init(bobSpeed: 1.2, bobAmp: 0.04, blinkMin: 3.0, blinkMax: 5.0, sway: 0.08),
             rarity: .rare, unlock: .coins(350)),
        Skin(id: "toxic", name: "Toxic", flavor: "Do not lick.",
             bodyHex: 0x39FF14, antennaHex: 0xFF2BD6, trailHex: 0x39FF14,
             pupilStyle: .slit,
             idle: .init(bobSpeed: 1.7, bobAmp: 0.05, blinkMin: 2.6, blinkMax: 4.6, sway: 0.18),
             rarity: .rare, unlock: .coins(500)),
        Skin(id: "mono", name: "Mono", flavor: "Allergic to color.",
             bodyHex: 0xF4F8FF, antennaHex: 0x0A0A14, trailHex: 0xE8EEFF,
             eyeRadius: 0.12,
             idle: .init(bobSpeed: 1.1, bobAmp: 0.03, blinkMin: 2.8, blinkMax: 4.8, sway: 0.05),
             rarity: .rare, unlock: .coins(750)),
        Skin(id: "blossom", name: "Blossom", flavor: "Runs on petals and spite.",
             bodyHex: 0xFF8AD4, antennaHex: 0xB4FF5C, trailHex: 0xFFB3E2,
             eyeRadius: 0.14, antennaHeightScale: 1.3, antennaTipScale: 1.4,
             idle: .init(bobSpeed: 1.5, bobAmp: 0.06, blinkMin: 2.4, blinkMax: 4.0, sway: 0.30),
             rarity: .rare, unlock: .level(6)),
        Skin(id: "fang", name: "Fang", flavor: "Bites first. Blinks never.",
             bodyHex: 0xFF3B30, antennaHex: 0x14141E, trailHex: 0xFF6B4A,
             pupilStyle: .slit,
             idle: .init(bobSpeed: 1.4, bobAmp: 0.04, blinkMin: 5.0, blinkMax: 8.0, sway: 0.10),
             rarity: .rare, unlock: .coins(2_500)),
        Skin(id: "drift", name: "Drift", flavor: "Found asleep in the Sands. Still asleep.",
             bodyHex: 0xE08A3C, antennaHex: 0x00FFC8, trailHex: 0xFFB36B,
             scale: 1.05, eyeRadius: 0.15, pupilStyle: .wide,
             antennaHeightScale: 0.8, antennaTipScale: 1.1,
             idle: .init(bobSpeed: 0.9, bobAmp: 0.06, blinkMin: 4.5, blinkMax: 7.0, sway: 0.08),
             rarity: .rare, unlock: .achievement(id: "ach.dist", tier: 1)),
        // EPIC ────────────────────────────────────────────────────────────────────────────────
        Skin(id: "midas", name: "Midas", flavor: "Everything it touches turns to score.",
             bodyHex: 0xFFD23D, antennaHex: 0xFFFFFF, trailHex: 0xFFD23D,
             pupilStyle: .glint, antennaTipScale: 1.3,
             idle: .init(bobSpeed: 1.4, bobAmp: 0.04, blinkMin: 2.4, blinkMax: 4.2, sway: 0.10),
             rarity: .epic, unlock: .coins(1_500)),
        Skin(id: "shard", name: "Shard", flavor: "A splinter of the first prism.",
             bodyHex: 0x7DF9FF, antennaHex: 0xFFFFFF, trailHex: 0x7DF9FF,
             bodyShape: .crystal, eyeRadius: 0.12, pupilStyle: .glint,
             antennaHeightScale: 1.1, antennaTipScale: 0.8,
             idle: .init(bobSpeed: 1.3, bobAmp: 0.04, blinkMin: 3.0, blinkMax: 5.0, sway: 0.10),
             rarity: .epic, unlock: .level(12)),
        Skin(id: "wisp", name: "Wisp", flavor: "Half here. All speed.",
             bodyHex: 0xDFF6FF, antennaHex: 0x9BF0FF, trailHex: 0xCFF8FF,
             scale: 0.90, eyeRadius: 0.12,
             antennaHeightScale: 1.4, antennaTipScale: 0.7,
             idle: .init(bobSpeed: 2.2, bobAmp: 0.09, blinkMin: 3.8, blinkMax: 6.0, sway: 0.25),
             rarity: .epic, unlock: .achievement(id: "ach.close", tier: 1)),
        Skin(id: "tempo", name: "Tempo", flavor: "Never misses a beat. Or a day.",
             bodyHex: 0xC6FF4D, antennaHex: 0xFF2BD6, trailHex: 0xC6FF4D,
             antennaHeightScale: 1.2, antennaTipScale: 1.2,
             // The metronome: blinks exactly on its 3 s beat, biggest antenna sway in the roster.
             idle: .init(bobSpeed: 2.0, bobAmp: 0.05, blinkMin: 3.0, blinkMax: 3.0, sway: 0.35),
             rarity: .epic, unlock: .challengeDays(7)),
        // LEGENDARY ───────────────────────────────────────────────────────────────────────────
        Skin(id: "aurora", name: "Aurora", flavor: "The sky wears it.",
             bodyHex: 0x00FFC8, antennaHex: 0xFF2BD6, trailHex: 0xFF2BD6,   // the two-tone money look
             pupilStyle: .glint, antennaHeightScale: 1.1, antennaTipScale: 1.2,
             idle: .init(bobSpeed: 1.8, bobAmp: 0.07, blinkMin: 2.2, blinkMax: 4.0, sway: 0.22),
             rarity: .legendary, unlock: .iap),
        Skin(id: "eclipse", name: "Eclipse", flavor: "The dark between worlds.",
             bodyHex: 0x1A1A2E, antennaHex: 0xFF2BD6, trailHex: 0x6B5BFF,
             scale: 1.08, eyeRadius: 0.14, eyeTintHex: 0xFFD23D,   // only non-white sclera
             pupilStyle: .slit, antennaTipScale: 1.2,
             idle: .init(bobSpeed: 1.0, bobAmp: 0.03, blinkMin: 4.0, blinkMax: 6.0, sway: 0.06),
             rarity: .legendary, unlock: .level(25)),
    ]

    static func skin(_ id: String) -> Skin { all.first { $0.id == id } ?? all[0] }
}
