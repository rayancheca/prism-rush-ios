import Foundation

/// Which stage of a Warden encounter the run is in.
///
/// The order is the order they happen in; there is no path that skips backwards.
enum WardenPhase: Sendable, Equatable {
    case arriving   // the craft drops into view ahead — nothing can hurt anyone yet
    case shielded   // auto-fire chips the shield; the player farms the arena's gems to fire faster
    case exposed    // telegraph → strike cycles; a clean dodge lands one hit on the open core
    case dying      // killed — the detonation beat before it clears the sky
    case leaving    // broke off (the shield never fell), or finished dying
}

/// Immutable per-frame view of an encounter, carried inside `GameSnapshot`.
///
/// `z` follows the same convention as `EntityState`: negative is AHEAD of the player. The Warden
/// hangs at a fixed stand-off and never reaches the player plane — it is a set piece, not an
/// obstacle, which is exactly why it is modelled here and not as an `EntityKind` (see the note on
/// `WardenEncounter`).
struct WardenState: Sendable, Equatable {
    var phase: WardenPhase
    var world: Int                 // the world ordinal this Warden belongs to (3, 6, 9, …)
    var z: Double                  // stand-off ahead of the player (negative = ahead)
    var y: Double                  // hover height above the deck
    var shieldFraction: Double     // 1 → 0 across the shield phase; 0 once exposed
    var coreHits: Int              // 0 ..< Tuning.wardenCoreHits
    var charge: Double             // the player's bank, 0…1 — drives fire rate, drains while firing
    var beamMask: UInt8            // bit per closed lane; 0 when no attack is in flight
    var telegraphProgress: Double  // 0 → 1 across the wind-up; 0 outside a telegraph
    var striking: Bool             // the beam is actually firing this tick
    var secondsRemaining: Double   // what is left of the shield window (`.shielded` only)

    /// Whether `lane` is closed by the beam currently in flight. A mask rather than an array so
    /// building this every frame allocates nothing.
    func closes(_ lane: Int) -> Bool { beamMask & (1 << UInt8(lane)) != 0 }
}

/// What one encounter tick did, handed back to `GameCore` to apply.
///
/// The encounter decides *what happened*; the core owns every consequence (death, shield absorb,
/// payout, FX). Same split as `Collisions`: the rule is testable without a running simulation.
struct WardenTick: Equatable {
    var justArmed = false      // the craft finished arriving and the shield phase began
    var shieldBroke = false    // the shield fell this tick — the core is open
    var telegraphBegan = false // a new attack wound up this tick (renderer/audio cue)
    var struck = false         // the beam fired this tick
    var struckMask: UInt8 = 0  // the lanes it closed
    var caughtPlayer = false   // the player was standing in one of them
    var coreHit = false        // the player was clear — the open core took a hit
    var killed = false         // that hit was the last one
    var brokeOff = false       // the shield window expired with the shield still up
    var finished = false       // the encounter is over; the core may clear it
}

/// A Warden encounter: the per-world antagonist that punctuates the run every third world.
///
/// **Why this is not an `EntityKind`.** Every other spawned thing in the game is an obstacle on the
/// deck, and `Core/` has six switches over `EntityKind` that carry a `default:` arm — `obstacleX`,
/// the collision dispatch, the near-miss scorer, `freeLaneNear`, `Autopilot.decide` and
/// `Spawner.isObstacle`. A new case added there is silently accepted by all six and becomes a
/// decorative, non-lethal prop that the solvability bot cannot see. A Warden is a set piece with its
/// own state machine, its own lifetime and its own collision rule, so it lives here as a first-class
/// field of the snapshot instead. The renderer gets a new field it is forced to handle rather than a
/// new enum case it can ignore.
///
/// **Determinism.** The encounter draws from its OWN `SplitMix64`, derived from the run seed and the
/// world ordinal. It never touches the run's spawn stream, so arming a Warden costs zero draws and
/// cannot shift a single pattern (iron rule 2). The arena it fights in is a pure function of
/// distance, so which stretch of deck falls quiet is fixed by the seed, not by how the fight goes.
struct WardenEncounter {
    private(set) var phase: WardenPhase = .arriving
    private(set) var world: Int
    private(set) var shield: Double = Tuning.wardenShieldHP
    private(set) var coreHits: Int = 0
    private(set) var beamMask: UInt8 = 0

    private var phaseT: Double = 0     // seconds inside the current phase
    private var windowT: Double = 0    // seconds since the shield phase opened
    private var totalT: Double = 0     // seconds since arrival — checked against `wardenMaxSeconds`
    private var attacking = false      // inside a telegraph → strike → recover cycle
    private var strikeShow: Double = 0 // the beam stays lit this long AFTER it fires, so the hit is
                                       // something the player sees rather than infers
    private var rng: SplitMix64

    /// `runSeed` and `world` fully determine the attack order — no `Date()`, no `Double.random`.
    init(world: Int, runSeed: UInt64) {
        self.world = world
        // Mix the ordinal in rather than adding it, so consecutive worlds get unrelated streams.
        rng = SplitMix64(seed: runSeed ^ (UInt64(bitPattern: Int64(world)) &* 0x9E37_79B9_7F4A_7C15))
    }

    /// Fraction of the shield still standing, 1 → 0.
    var shieldFraction: Double { max(0, shield / Tuning.wardenShieldHP) }

    /// A beam is winding up RIGHT NOW and `beamMask` is the set of lanes it will close.
    ///
    /// False during the `strikeShow` afterglow, when `beamMask` is still set but the shot is spent —
    /// so nothing (the Autopilot included) dodges a beam that has already fired.
    var isTelegraphing: Bool { phase == .exposed && attacking }

    /// Whether the beam in flight closes `lane`.
    func closes(_ lane: Int) -> Bool { beamMask & (1 << UInt8(lane)) != 0 }

    /// Advance one fixed step.
    ///
    /// `charge` is the player's bank (0…1), drained in place while the gun is firing. `playerLane`
    /// is the lane the player has *committed* to and is read only when a telegraph locks on;
    /// `playerX` is where the body actually is and is what the strike tests against — the same
    /// split the rest of the game uses, so a lane change that has been input but not yet travelled
    /// does not teleport you out of a beam.
    mutating func step(_ dt: Double, playerLane: Int, playerX: Double,
                       charge: inout Double) -> WardenTick {
        var out = WardenTick()
        phaseT += dt
        totalT += dt

        // The hard ceiling. Phase timings alone do not bound an encounter, because an absorbed beam
        // is spent without landing a core hit and shields remain collectable inside the arena. At
        // the cap it breaks off exactly as an unbroken shield would: the player keeps the run.
        if totalT >= Tuning.wardenMaxSeconds, phase != .dying, phase != .leaving {
            phase = .leaving; phaseT = 0; attacking = false; beamMask = 0
            out.brokeOff = true
            return out
        }

        switch phase {
        case .arriving:
            if phaseT >= Tuning.wardenArriveTime {
                phase = .shielded; phaseT = 0; windowT = 0
                out.justArmed = true
            }

        case .shielded:
            windowT += dt
            // Fire rate is the bank, spent as it is used: a full bank burns bright and fades, and
            // gems picked up inside the arena top it back up mid-fight. A player who banked nothing
            // fires at `wardenBaseDPS`, which cannot break the shield inside the window by design —
            // the gun is a timer the player earned, never a win button.
            let dps = Tuning.wardenBaseDPS + charge * Tuning.wardenChargeDPS
            shield -= dps * dt
            charge = max(0, charge - Tuning.wardenChargeDrain * dt)
            if shield <= 0 {
                shield = 0
                phase = .exposed; phaseT = 0
                attacking = false
                out.shieldBroke = true
            } else if windowT >= Tuning.wardenShieldWindow {
                // The safety valve, and the reason this can never cost a good run: failing to
                // DAMAGE is not failing to survive. It leaves; you lose the reward, not the run.
                phase = .leaving; phaseT = 0
                out.brokeOff = true
            }

        case .exposed:
            // The fired beam lingers briefly. `wardenAttackRecover` is longer than this, so the
            // lit lane has always cleared before the next telegraph locks a new one.
            if strikeShow > 0 {
                strikeShow = max(0, strikeShow - dt)
                if strikeShow == 0 { beamMask = 0 }
            }
            if !attacking {
                if phaseT >= Tuning.wardenAttackRecover {
                    attacking = true; phaseT = 0
                    beamMask = pickBeamMask(playerLane: playerLane)
                    out.telegraphBegan = true
                }
            } else if phaseT >= Tuning.wardenTelegraphTime {
                // The strike resolves on one tick: overlap a lit lane and it catches you, be clear
                // of them all and the open core eats the shot.
                out.struck = true
                out.struckMask = beamMask
                if Collisions.wardenBeamHit(playerX: playerX, mask: beamMask) {
                    out.caughtPlayer = true
                } else {
                    coreHits += 1
                    out.coreHit = true
                    if coreHits >= Tuning.wardenCoreHits {
                        out.killed = true
                        phase = .dying
                    }
                }
                attacking = false
                phaseT = 0
                strikeShow = Tuning.wardenStrikeShowTime
            }

        case .dying:
            if phaseT >= Tuning.wardenDieTime { phase = .leaving; phaseT = 0 }

        case .leaving:
            if phaseT >= Tuning.wardenLeaveTime { out.finished = true }
        }

        return out
    }

    /// The lanes the next beam closes.
    ///
    /// It ALWAYS closes the lane the player is standing in as the telegraph begins, so standing
    /// still is always fatal and the gun can never win a fight by itself. Some of the time it also
    /// closes one other lane, leaving exactly one safe answer — which is what forces the wind-up to
    /// be *read* rather than answered with a reflex sidestep.
    ///
    /// Never more than two of three lanes, so a safe answer always exists and the attack always
    /// resolves in one cycle. One lane to move to, one input to give: decree 6 holds.
    private mutating func pickBeamMask(playerLane: Int) -> UInt8 {
        var mask: UInt8 = 1 << UInt8(playerLane)
        if rng.chance(Tuning.wardenDoubleBeamChance) {
            let others = (0..<3).filter { $0 != playerLane }
            mask |= 1 << UInt8(others[rng.int(0, others.count - 1)])
        }
        return mask
    }

    /// The renderable view of this encounter.
    func state(charge: Double) -> WardenState {
        let telegraph: Double = (phase == .exposed && attacking)
            ? min(1, phaseT / Tuning.wardenTelegraphTime) : 0
        let firing = phase == .exposed && strikeShow > 0
        // The craft closes in as it arrives and climbs away as it leaves, so entrance and exit read
        // as movement rather than a pop. `z` is negative = ahead, matching `EntityState`.
        let arrive = phase == .arriving ? min(1, phaseT / Tuning.wardenArriveTime) : 1
        let leave = phase == .leaving ? min(1, phaseT / Tuning.wardenLeaveTime) : 0
        return WardenState(
            phase: phase,
            world: world,
            z: -Tuning.wardenStandOff,
            y: Tuning.wardenHoverY + (1 - arrive) * Tuning.wardenArriveRise
                                   + leave * Tuning.wardenLeaveRise,
            shieldFraction: shieldFraction,
            coreHits: coreHits,
            charge: charge,
            beamMask: beamMask,
            telegraphProgress: telegraph,
            striking: firing,
            secondsRemaining: phase == .shielded
                ? max(0, Tuning.wardenShieldWindow - windowT) : 0
        )
    }
}

/// Pure, distance-domain facts about where Wardens live. Consumes no RNG and holds no state, so the
/// spawner, the core and the tests all agree by construction.
enum Warden {
    /// The world ordinal whose arena contains `d`, or `nil` if `d` is on open track.
    ///
    /// Arenas sit at the START of every `wardenEveryWorlds`-th world and are shorter than a world,
    /// so one can never span two.
    static func arenaWorld(forDistance d: Double) -> Int? {
        guard d >= 0 else { return nil }
        let w = Int((d / Tuning.worldLength).rounded(.down))
        guard w > 0, w % Tuning.wardenEveryWorlds == 0 else { return nil }
        let into = d - Double(w) * Tuning.worldLength
        return into < Tuning.wardenArenaLength ? w : nil
    }

    /// Whether `d` falls inside a Warden arena — the stretch of deck that stays clear of obstacles
    /// so the encounter's telegraphs are the only thing to read (decree 6).
    static func isArena(_ d: Double) -> Bool { arenaWorld(forDistance: d) != nil }

    /// The world whose Warden may ARM at `d`. Stricter than `arenaWorld`: a Warden only appears in
    /// the first `wardenArmWindow` metres, so a checkpoint run that began near the far end of an
    /// arena runs it out as clear track instead of summoning a fight with no room to hold it.
    static func armableWorld(forDistance d: Double) -> Int? {
        guard let w = arenaWorld(forDistance: d) else { return nil }
        return d - Double(w) * Tuning.worldLength < Tuning.wardenArmWindow ? w : nil
    }

    /// Whether a spawn command must be dropped because it lands inside an arena.
    ///
    /// Obstacles and boost pads are suppressed; gems, rings and power-ups are NOT — the arena is a
    /// gem field on purpose. Gems are what charge the gun, so the shield phase is spent collecting
    /// with the verbs the player already owns, rather than waiting for a bar to empty.
    ///
    /// Pads are dropped with the obstacles because a boost inside the arena would carry the player
    /// past the encounter's distance budget.
    static func suppresses(_ cmd: SpawnCmd) -> Bool {
        switch cmd {
        case let .low(d, _), let .tall(d, _), let .bar(d), let .splitBar(d, _),
             let .movingTall(d, _), let .chasm(d), let .boostPad(d, _):
            return isArena(d)
        case .gem, .shield, .magnet, .doubler, .chrono, .superSneakers, .ring:
            return false
        }
    }
}
