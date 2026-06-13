import Foundation

/// A procedural character skin (no asset files): colors + rig geometry + idle personality, one
/// recipe shared by the RealityKit rig rebuild and the SwiftUI Canvas previews. Every skin owns
/// real authored hexes — no skin EVER follows the world palette (owner decree 1). Prism's
/// `isPrismatic` shimmer is fixed and time-based (`SkinCatalog.prismaticColor`), identical in
/// every world; its `trailHex == nil` means "ride the shimmer hue", never "follow the world".
/// Not Codable, never persisted: only ids are stored, so catalog evolution can't corrupt saves.
struct Skin: Identifiable, Sendable {
    enum BodyShape: Sendable { case sphere, cube, crystal }
    enum PupilStyle: Sendable { case dot, wide, slit, glint }
    /// Cosmetic head adornment (v1.6) — the visible rarity ladder (owner C2): common runners wear
    /// `.none` (basic shape + colour), rares gain a light creature feature (ears/fin/floppy), epics
    /// a bold crest (horns/crown), legendaries a signature crest PLUS an orbiting aura ring. Drawn
    /// identically by the Canvas swatch and the RealityKit rig (decree 2 — previews never lie) and
    /// in the skin's authored `antennaHex`, so it reads as part of the character. Purely visual:
    /// never the hitbox, never an advantage (decree — characters stay cosmetic).
    enum Crest: Sendable, Equatable {
        case none          // common — plain head, antenna only
        case ears          // upright triangular "cat" ears flanking the antenna
        case floppy        // rounded drooping "dog/bunny" ears at the sides
        case fin           // a sawtooth dorsal mohawk along the crown
        case horns         // two angled horns sweeping up-and-out
        case crown         // a ring of points around the crown (royalty)
        case halo          // a glowing ring floating above the head
    }
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
    let bodyHex, antennaHex: UInt32          // authored identity colors — never world-driven
    var trailHex: UInt32? = nil              // nil = ride the prismatic shimmer (Prism only)
    /// Fixed, time-based iridescence (Prism only): the body + trail cycle the shared 8 s
    /// shimmer (`SkinCatalog.prismaticColor`), identical in every world — NEVER the world
    /// palette. Reduce Motion holds the shimmer's phase-0 color (= `bodyHex`, 0x00F5FF).
    var isPrismatic = false
    var bodyShape: BodyShape = .sphere
    var scale: Float = 1                     // visual only, 0.85...1.12 — never the hitbox
    var eyeRadius: Float = 0.13
    var eyeTintHex: UInt32 = 0xFFFFFF
    var pupilStyle: PupilStyle = .dot
    var antennaHeightScale: Float = 1
    var antennaTipScale: Float = 1
    /// Cosmetic crest (v1.6) — default `.none` keeps every legacy skin's silhouette unchanged
    /// until explicitly themed below; assigned to express the rarity ladder.
    var crest: Crest = .none
    /// Legendary signature aura (v1.6): a slow orbiting glow ring in the trail hue. Only the
    /// four legendaries set it — the unmistakable "this one is special" tell. Cosmetic only.
    var hasAura: Bool = false
    var idle: Idle = Idle()
    let rarity: Rarity
    let unlock: Unlock

    var premium: Bool { unlock == .iap }                                // back-compat
    var cost: Int { if case .coins(let c) = unlock { c } else { 0 } }   // back-compat

    /// Crest colour (v1.6): the authored antenna hue — the character's accent — UNLESS it is too
    /// dark to read as an adornment against the dark UI (Mono's 0x0A0A14, Fang's 0x14141E near-black
    /// antennas), in which case the body hue carries it. The crest is the rarity *tell*; it must
    /// always be visible, but still belong to the character. Pure of state — both render layers read
    /// it, so swatch and rig agree (decree 2).
    var crestHex: UInt32 {
        let r = Double((antennaHex >> 16) & 0xFF)
        let g = Double((antennaHex >> 8) & 0xFF)
        let b = Double(antennaHex & 0xFF)
        let luminance = 0.299 * r + 0.587 * g + 0.114 * b
        return luminance < 40 ? bodyHex : antennaHex
    }
}

enum SkinCatalog {
    /// The 24-character roster (DESIGN_characters §2 + the v1.4 eight), ordered rarity → unlock
    /// difficulty — the select grid renders catalog order inside each rarity section. The legacy
    /// 16 keep their ids, hexes, and costs exactly (pinned by tests); Fang is 2,500 — the week-1
    /// savings goal (R4). The v1.4 eight take the parking-lot rungs (2,000/3,500/5,000/7,500),
    /// the new level beats (8/18), `ach.gems` tier 2, and the 14-day challenge pull.
    /// Rarity census: Common 4 · Rare 9 · Epic 7 · Legendary 4.
    private static let roster: [Skin] = [
        // COMMON ──────────────────────────────────────────────────────────────────────────────
        Skin(id: "default", name: "Prism", flavor: "The first runner. Every world remembers it.",
             bodyHex: 0x00F5FF, antennaHex: 0xFF2BD6, isPrismatic: true,
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
        Skin(id: "circuit", name: "Circuit", flavor: "Runs on logic. Mostly.",
             bodyHex: 0xC97A3D, antennaHex: 0x00B3FF, trailHex: 0xE8A05C,
             bodyShape: .cube, scale: 0.95, eyeRadius: 0.12,
             antennaHeightScale: 1.0, antennaTipScale: 0.8,
             // Servo idle: quick precise ticks, the snappiest blink cadence after Bolt.
             idle: .init(bobSpeed: 2.4, bobAmp: 0.04, blinkMin: 1.8, blinkMax: 2.8, sway: 0.16),
             rarity: .rare, unlock: .level(8)),
        Skin(id: "tide", name: "Tide", flavor: "Comes in. Takes everything.",
             bodyHex: 0x00E08A, antennaHex: 0x0091FF, trailHex: 0x55F0B0,
             scale: 1.02, pupilStyle: .wide,
             antennaHeightScale: 0.9, antennaTipScale: 1.1,
             // Rolling-swell idle: slow bob with the deepest amplitude in the rare tier.
             idle: .init(bobSpeed: 1.0, bobAmp: 0.07, blinkMin: 2.6, blinkMax: 4.4, sway: 0.14),
             rarity: .rare, unlock: .coins(2_000)),
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
        Skin(id: "facet", name: "Facet", flavor: "Counts gems in its sleep.",
             bodyHex: 0xFF2BD6, antennaHex: 0xFFD23D, trailHex: 0xFF7BE9,   // the only magenta body
             bodyShape: .crystal, scale: 0.92, eyeRadius: 0.12, pupilStyle: .glint,
             antennaHeightScale: 0.9, antennaTipScale: 1.2,
             idle: .init(bobSpeed: 1.5, bobAmp: 0.05, blinkMin: 2.2, blinkMax: 4.0, sway: 0.12),
             rarity: .rare, unlock: .achievement(id: "ach.gems", tier: 2)),
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
        Skin(id: "nebula", name: "Nebula", flavor: "Stars have to start somewhere.",
             bodyHex: 0x7B2FE0, antennaHex: 0xFFD23D, trailHex: 0x9B5BFF,   // deep purple, gold star tip
             scale: 1.05, eyeRadius: 0.14, pupilStyle: .glint,
             antennaHeightScale: 1.3, antennaTipScale: 1.3,
             idle: .init(bobSpeed: 0.9, bobAmp: 0.06, blinkMin: 3.4, blinkMax: 5.6, sway: 0.18),
             rarity: .epic, unlock: .level(18)),
        Skin(id: "thorn", name: "Thorn", flavor: "Touch. Regret. Repeat.",
             bodyHex: 0xC41E5C, antennaHex: 0xB4FF5C, trailHex: 0xE84A8A,   // wine body, leaf-green spike
             pupilStyle: .slit,
             antennaHeightScale: 1.3, antennaTipScale: 0.7,   // tall and pointy — the thorn
             idle: .init(bobSpeed: 1.3, bobAmp: 0.04, blinkMin: 3.2, blinkMax: 5.2, sway: 0.08),
             rarity: .epic, unlock: .coins(3_500)),
        Skin(id: "golem", name: "Golem", flavor: "Pebble's older brother. Much older.",
             bodyHex: 0x55657A, antennaHex: 0xFFB13D, trailHex: 0x8FA3BD,   // the sibling cue is the antenna
             bodyShape: .cube, scale: 1.12, eyeRadius: 0.11, pupilStyle: .wide,
             antennaHeightScale: 0.7, antennaTipScale: 1.0,
             // Slowest bob in the roster — out-stills even Pebble. Mass has manners.
             idle: .init(bobSpeed: 0.6, bobAmp: 0.02, blinkMin: 5.0, blinkMax: 8.0, sway: 0.04),
             rarity: .epic, unlock: .coins(5_000)),
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
             // Body lightened 0x1A1A2E → 0x2A2A4A (AUDIT D3-4): the original was ~1.2:1 against
             // the world backgrounds — near-invisible in-run and a black halo in the swatch.
             // Still the roster's only dark body; gold eyes/indigo trail carry the menace.
             bodyHex: 0x2A2A4A, antennaHex: 0xFF2BD6, trailHex: 0x6B5BFF,
             scale: 1.08, eyeRadius: 0.14, eyeTintHex: 0xFFD23D,   // only non-white sclera
             pupilStyle: .slit, antennaTipScale: 1.2,
             idle: .init(bobSpeed: 1.0, bobAmp: 0.03, blinkMin: 4.0, blinkMax: 6.0, sway: 0.06),
             rarity: .legendary, unlock: .level(25)),
        Skin(id: "monarch", name: "Monarch", flavor: "It does not chase. It is awaited.",
             bodyHex: 0x2956FF, antennaHex: 0xFFD23D, trailHex: 0x5C82FF,   // royal blue, gold crown orb
             scale: 1.10, pupilStyle: .glint,
             antennaHeightScale: 1.2, antennaTipScale: 1.5,   // biggest tip in the roster — the crown jewel
             idle: .init(bobSpeed: 1.2, bobAmp: 0.05, blinkMin: 3.0, blinkMax: 5.0, sway: 0.10),
             rarity: .legendary, unlock: .coins(7_500)),
        Skin(id: "vigil", name: "Vigil", flavor: "Fourteen dawns. Saw them all.",
             bodyHex: 0xBFC9FF, antennaHex: 0xFF2BD6, trailHex: 0xD4DAFF,   // moonlit periwinkle
             bodyShape: .crystal, scale: 0.98, eyeRadius: 0.14, pupilStyle: .wide,
             antennaHeightScale: 1.1, antennaTipScale: 1.0,
             // Statue-still watcher: the longest stare in the roster — it out-blinks even Fang.
             idle: .init(bobSpeed: 0.7, bobAmp: 0.02, blinkMin: 6.0, blinkMax: 9.0, sway: 0.05),
             rarity: .legendary, unlock: .challengeDays(14)),
    ]

    /// The crest/aura theming layer (v1.6, owner C2) applied over the authored roster so the
    /// rarity ladder is VISIBLE: common runners stay plain, rares gain a light creature feature,
    /// epics a bold crest, legendaries a signature crest plus an orbiting aura. Kept as an id-keyed
    /// overlay (not inlined into 20 declarations) so the look stays auditable in one place and the
    /// legacy colour/cost/shape pins stay provably untouched. Catalog order + count are preserved.
    static let all: [Skin] = roster.map { skin in
        var s = skin
        s.crest = crestByID[skin.id] ?? .none
        s.hasAura = auraIDs.contains(skin.id)
        return s
    }

    /// Crest assignment — the rarity ladder, by id (commons omitted = `.none`, basic shape/colour):
    /// rare → light creature feature (ears/floppy/fin); epic → bold crest (horns/crown);
    /// legendary → signature crest (crown/halo/horns), paired with an aura below.
    private static let crestByID: [String: Skin.Crest] = [
        // RARE — light creature features
        "void": .ears, "blossom": .ears, "fang": .ears,
        "mono": .floppy, "drift": .floppy,
        "toxic": .fin, "circuit": .fin, "tide": .fin, "facet": .fin,
        // EPIC — bold crests
        "midas": .crown, "nebula": .crown, "tempo": .crown,
        "shard": .horns, "thorn": .horns, "golem": .horns, "wisp": .horns,
        // LEGENDARY — signature crests (each also wears an aura)
        "monarch": .crown, "aurora": .halo, "vigil": .halo, "eclipse": .horns,
    ]

    /// The four legendaries — the only skins with an orbiting aura ring (the "this one is special"
    /// tell). Purely cosmetic; never an in-run advantage (characters stay cosmetic by decree).
    private static let auraIDs: Set<String> = ["aurora", "eclipse", "monarch", "vigil"]

    static func skin(_ id: String) -> Skin { all.first { $0.id == id } ?? all[0] }

    // MARK: the Prism shimmer (decree 1: fixed + time-based, identical in every world)

    /// Shimmer loop length in seconds — matches the menu hero disc's historical 8 s hue drift.
    static let prismaticPeriod: Double = 8
    /// The authored identity stops the shimmer cycles through (the old menu-rainbow palette,
    /// now truthful): cyan → magenta → amber → back to cyan. Phase 0 is exactly Prism's
    /// `bodyHex` 0x00F5FF, which doubles as the static Reduce Motion look.
    static let prismaticStops: [UInt32] = [0x00F5FF, 0xFF2BD6, 0xFFB13D, 0x00F5FF]

    /// ONE pure clock→color function shared by the RealityKit body material, every character
    /// FX burst, and the SwiftUI previews — so the menu hero and the in-run body show the same
    /// hue at the same instant (decree 2 by construction; both layers feed it the same
    /// reference-date wall clock). Deterministic for a given `t`, no hidden state, and the
    /// signature takes ONLY time: the world palette structurally cannot influence it.
    static func prismaticColor(at t: Double) -> (r: Double, g: Double, b: Double) {
        func rgb(_ hex: UInt32) -> (Double, Double, Double) {
            (Double((hex >> 16) & 0xFF) / 255, Double((hex >> 8) & 0xFF) / 255,
             Double(hex & 0xFF) / 255)
        }
        let cycle = (t / prismaticPeriod).truncatingRemainder(dividingBy: 1)
        let phase = cycle < 0 ? cycle + 1 : cycle                  // negative t stays periodic
        let seg = phase * Double(prismaticStops.count - 1)         // 3 lerp segments, 4 stops
        let i = min(Int(seg), prismaticStops.count - 2)
        let f = seg - Double(i)
        let a = rgb(prismaticStops[i]), b = rgb(prismaticStops[i + 1])
        return (a.0 + (b.0 - a.0) * f, a.1 + (b.1 - a.1) * f, a.2 + (b.2 - a.2) * f)
    }
}
