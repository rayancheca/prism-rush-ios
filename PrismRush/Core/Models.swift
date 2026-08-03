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
    case hangingBar // full-span wall from the sky with NO top: slide, and ONLY slide (v2.2)
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
    /// A Warden's aimed shot (v2.3): a single-lane projectile fired at the lane the player is
    /// STANDING IN, closing far faster than anything the deck produces. Answered by moving, or by
    /// blasting it out of the air. Never spawned by the spawner — only a Warden fires one.
    ///
    /// **Why it is its own kind rather than a fast `tall`.** Mechanically it resolves through
    /// `tallHit` like a wall, and that is deliberate — the player already knows "full-height thing in
    /// my lane, move". What differs is everything the player uses to PREDICT it: a lance leaves a
    /// lane open by construction and can be read, while a shot follows you and must be reacted to.
    /// A different rule deserves a different silhouette, a different sound and a different speed, and
    /// none of those are expressible if it borrows another kind's identity.
    case bolt
}

extension EntityKind {
    /// Whether THE BLAST (v2.2) destroys this kind.
    ///
    /// The switch is deliberately exhaustive with no `default:` arm — this is one of the seven
    /// places in `Core/` that must be told about a new `EntityKind`, and the compiler is the only
    /// reliable way to be told. (See the note on `WardenEncounter` for the other six and for why a
    /// silently-defaulted case is worse than a compile error.)
    ///
    /// **The chasm is immune by rule.** You cannot knock down a hole, and more to the point the
    /// chasm is the catalogue's only two-sided timing window: giving it a second answer would undo
    /// the one thing it was added to teach. `Collisions.grazes` makes exactly the same carve-out for
    /// exactly the same reason. Collectibles are not "destroyed" either — a blast that ate the gems
    /// in front of you would spend ammo to destroy the ammo.
    var isBlastable: Bool {
        switch self {
        case .low, .tall, .movingTall, .bar, .splitBar, .hangingBar:
            return true
        // Shooting a shot down is the fantasy the blast exists for, and it is the one hazard where
        // spending a round can be strictly better than dodging: a shot tracks the lane you are in,
        // so it is the only throw you cannot answer by having already been somewhere else.
        case .bolt:
            return true
        case .chasm:
            return false
        case .gem, .shield, .magnet, .doubler, .chrono, .superSneakers, .ring, .boostPad:
            return false
        }
    }
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
    /// Thrown by a Warden rather than drawn by the spawner (v2.2). The renderer paints these in the
    /// Warden's hazard red instead of the world accent, and that is not decoration: inside an arena
    /// a thrown wall follows a DIFFERENT rule from every other wall in the game — it staggers and
    /// can never kill — so the player has to be able to tell whose wall it is at a glance (decree 6).
    var fromWarden: Bool

    init(id: Int, kind: EntityKind, x: Double = 0, y: Double = 0, z: Double = 0,
         lane: Int = -1, spin: Double = 0, fading: Bool = false, fromWarden: Bool = false) {
        self.id = id; self.kind = kind; self.x = x; self.y = y; self.z = z
        self.lane = lane; self.spin = spin; self.fading = fading; self.fromWarden = fromWarden
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
    /// Seconds left of the post-stumble recovery, 0 when clean (v2.0). While this is > 0 the NEXT
    /// contact is fatal, so it is the one piece of state the player must be able to see — the HUD
    /// tints its frame and the renderer keeps the body flashing for exactly this long.
    var stumbleRemaining: Double
    /// Whether the recovery `stumbleRemaining` is counting down came from a Warden (v2.4).
    ///
    /// The two sources mean different things and must not be drawn in the same colour. An ordinary
    /// stumble means *the next wall kills you*, which is what the red vignette has always said. A
    /// Warden strike means *the boss landed one* — and only says "the next one ends the run" when
    /// the strike budget is actually spent, which `WardenState.strikes` answers. Red is the scarcer
    /// and more valuable signal of the two, so it is reserved for the case that is literally fatal.
    var stumbleFromWarden: Bool
    var usedCheckpoint: Bool        // run began mid-track — meta layer must skip Game Center submit
    var entities: [EntityState]
    /// The live Warden encounter, or `nil` on open track. Deliberately its own field rather than an
    /// `EntityKind`: a Warden is a set piece with its own state machine and its own collision rule,
    /// and Core has six switches over `EntityKind` whose `default:` arms would have swallowed a new
    /// case silently. See `WardenEncounter`.
    var warden: WardenState?
    /// The player's Warden charge bank, 0…1 — earned from gems, spent breaking a shield. Lives in
    /// the snapshot (not just inside `warden`) because the HUD meter must be readable BEFORE an
    /// encounter, which is the whole reason collecting gems matters early.
    var wardenCharge: Double
    /// The live blast front's distance-relative `z` (negative = ahead), or `nil` when no shockwave
    /// is travelling. Same sign convention as `EntityState.z`, so the renderer places it with the
    /// same arithmetic it uses for every obstacle.
    var blastFrontZ: Double?
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
        stumbleRemaining: 0,
        stumbleFromWarden: false,
        usedCheckpoint: false,
        entities: [],
        warden: nil,
        wardenCharge: 0,
        blastFrontZ: nil,
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
    /// A contact the player SURVIVED (v2.0). `x` is where it happened; `fromWarden` separates the two
    /// sources because they sound and read differently — a wall clips you, a boss lands a shot on you
    /// — and because only one of them is a boss telling you the next one is fatal.
    case stumbled(x: Double, fromWarden: Bool)
    /// The run ended. `fromWarden` separates the two sources for the same reason `stumbled` does —
    /// and since v2.4 it is no longer always `false`: a Warden past the teaching rank can spend a
    /// player's whole strike budget and end the run (D-037/D-039). A death a boss caused must not
    /// look, sound or feel like clipping a wall.
    case died(x: Double, fromWarden: Bool)

    // MARK: THE BLAST (v2.2)
    /// A double tap spent `Tuning.blastCost` and launched a shockwave. `chargeLeft` is the bank
    /// AFTER the spend, so the HUD/audio can pitch the cue to how much ammo is left.
    case blastFired(x: Double, y: Double, chargeLeft: Double)
    /// The shockwave reached an obstacle and destroyed it. One per obstacle, in the order the front
    /// passed them, so the renderer's shatters read as a path opening rather than one explosion.
    case obstacleShattered(kind: EntityKind, x: Double, y: Double, z: Double)

    // MARK: Wardens (v1.9)
    case wardenArrived(world: Int)              // the craft drops in — the arena has begun
    case wardenShieldBroke                      // the armour is stripped: the core is open
    /// **It threw something (v2.2).** `band` is the shape, and therefore the verb that answers it —
    /// the renderer, the audio cue and the haptic all key off it, so adding a shape is a compile
    /// error everywhere it must be handled. `lead` is how many metres ahead the hazard materialised,
    /// which is also how long the player has: travel time IS the telegraph.
    ///
    /// This replaces `wardenTelegraph` + `wardenStruck`. There is no longer a moment when a strike
    /// "fires" — the hazard is a real obstacle from the instant it exists, and it resolves the way
    /// every obstacle in the game resolves, in `stepObstacles`.
    case wardenThrew(band: WardenBand, lead: Double)
    case wardenCoreHit(hits: Int)               // an answered hazard damaged it (1-based)
    case wardenDefeated(world: Int, bounty: Int)
    case wardenBrokeOff                         // the shield held out the window — it leaves, you live
}
