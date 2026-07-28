import Foundation

/// High-level game lifecycle state.
enum GameMode: Sendable, Equatable {
    case menu, play, over
}

/// Collectible power-up kinds.
enum PickupKind: Sendable, Equatable {
    case shield, magnet, doubler, chrono, superSneakers
}

/// Every renderable spawned thing. Pure data — the renderer maps these onto pooled entities.
enum EntityKind: Sendable, Equatable {
    case low        // low block: hop or it clips your feet
    case tall       // full-height block: must change lane
    case movingTall // oscillating tall wall (high difficulty), tinted as danger
    case bar        // full-span overhead bar: slide or precise jump
    case splitBar   // overhead bar covering 2 of 3 lanes: steer to the gap (entity lane) or slide
    case gem        // octahedron collectible
    case shield     // icosahedron pickup
    case magnet     // torus pickup
    case doubler    // ×2 coin pickup (gems pay double currency while active)
    case chrono     // slow-mo pickup (world scroll slows; player reflexes run at full rate)
    case superSneakers // winged-boot pickup: jumps launch higher for a few seconds — never lethal
    case ring       // prism ring at jump-apex height: thread it for score/coins — never lethal
    case boostPad   // floor chevron strip: grounded contact triggers the overdrive boost
    case chasm      // full-width gap in the deck: be AIRBORNE across its whole span or fall (v1.8)
}

/// One pooled entity's render state for a single frame.
/// `z` is distance-relative to the player: negative = ahead of the player, positive = behind.
/// `lane` is -1 for full-span entities (bars, chasms); for a `splitBar` it is the OPEN (safe) lane.
/// `y` is authoritative for every obstacle kind (bar centre 1.3, low 0.425, tall 1.6, chasm 0 — the
/// deck plane it replaces) — renderers must place from `y`, never hardcode heights.
/// `z` is the CENTRE for every kind, including the `chasm`, whose mesh is `2 × Tuning.chasmHalfLength`
/// long: collision anchor and render anchor are the same point on purpose.
struct EntityState: Sendable, Identifiable, Equatable {
    var id: Int
    var kind: EntityKind
    var x: Double
    var y: Double
    var z: Double
    var lane: Int
    var spin: Double        // accumulated phase for spinning/bobbing collectibles
    var fading: Bool        // entity is being magneted / absorbed: renderer may fade it

    init(id: Int, kind: EntityKind, x: Double = 0, y: Double = 0, z: Double = 0,
         lane: Int = -1, spin: Double = 0, fading: Bool = false) {
        self.id = id; self.kind = kind; self.x = x; self.y = y; self.z = z
        self.lane = lane; self.spin = spin; self.fading = fading
    }
}

/// Immutable per-frame view of the world handed to the renderer. Value type, `Sendable`.
struct GameSnapshot: Sendable {
    var mode: GameMode
    var distance: Double            // ABSOLUTE position (matches world labels; the HUD meters readout)
    var traveledDistance: Double    // meters run THIS attempt (distance − checkpoint offset); XP / fair score
    var speed: Double               // EFFECTIVE world speed (chrono-slowed) — drives FOV/scroll/trails
    var rampSpeed: Double           // raw difficulty-ramp speed (un-slowed); HUD/debug only
    var playerX: Double
    var playerY: Double
    var playerScaleY: Double
    var bankZ: Double
    var worldFrom: Int
    var worldTo: Int
    var worldBlend: Double          // 0 → fully `worldFrom`, 1 → fully `worldTo`
    var worldOrdinal: Int           // ABSOLUTE world index (core.maxWorld) — worldFrom/To are the
                                    // 0–2 palette family; the sky's per-world identity + cycle
                                    // richening (WorldSky) need the real ordinal
    var shieldActive: Bool
    var magnetRemaining: Double
    var doublerRemaining: Double    // > 0 → gems pay double coins (HUD shows the timer)
    var chronoRemaining: Double     // > 0 → slow-mo active (HUD timer; renderer may tint)
    var boostRemaining: Double      // > 0 → overdrive boost active (mirrors boostT; HUD ring, FOV punch)
    var sneakersRemaining: Double   // > 0 → Super Sneakers active (jumps launch higher; HUD ring + rig glow)
    var flowStreak: Int             // near-miss count toward flow surges (HUD pips show % flowPerSurge)
    var sliding: Bool
    var grounded: Bool
    var usedCheckpoint: Bool        // run began mid-track — meta layer must skip Game Center submit
    var entities: [EntityState]
    var score: Int
    var gems: Int
    var mult: Int
    var best: Int

    /// The menu/attract state shown before the first run.
    static let initial = GameSnapshot(
        mode: .menu,
        distance: 0,
        traveledDistance: 0,
        speed: Tuning.menuSpeed,
        rampSpeed: Tuning.menuSpeed,
        playerX: 0,
        playerY: 0,
        playerScaleY: 1,
        bankZ: 0,
        worldFrom: 0,
        worldTo: 0,
        worldBlend: 1,
        worldOrdinal: 0,
        shieldActive: false,
        magnetRemaining: 0,
        doublerRemaining: 0,
        chronoRemaining: 0,
        boostRemaining: 0,
        sneakersRemaining: 0,
        flowStreak: 0,
        sliding: false,
        grounded: true,
        usedCheckpoint: false,
        entities: [],
        score: 0,
        gems: 0,
        mult: 1,
        best: 0
    )
}

/// Near-miss flavours: `close` = squeezed past a tall, `slick` = slid under a bar.
enum NearMissKind: Sendable, Equatable {
    case close, slick
}

/// One-shot effects the core emits each tick for the renderer / audio / haptics to react to.
/// The core never performs side effects itself — it only describes what happened.
enum FXEvent: Sendable, Equatable {
    case laneChanged(x: Double)
    case jumped(x: Double)
    case landed(x: Double)
    case slid(x: Double)
    case gemCollected(x: Double, y: Double, streak: Int)
    case nearMiss(kind: NearMissKind, x: Double)
    case pickup(kind: PickupKind, x: Double, y: Double)
    case worldChanged(index: Int, ordinal: Int)
    case shieldAbsorbed(x: Double)
    case chronoEnded                 // slow-mo timer crossed 0 (audio needs the edge)
    case sneakersEnded               // Super Sneakers timer crossed 0 (renderer/audio restore the rig)
    case ringPassed(x: Double, y: Double, perfect: Bool)   // threaded a prism ring (once per ring)
    case boostStarted(x: Double)     // overdrive pad triggered (edge)
    case boostEnded                  // boost timer crossed 0 (edge, like chronoEnded)
    case flowSurge(level: Int, x: Double)   // every flowPerSurge-th near-miss; level = surges this run (1-based)
    case died(x: Double)
}
