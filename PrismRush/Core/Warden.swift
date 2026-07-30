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

/// The shape a strike takes, and therefore the verb that answers it (S-009).
///
/// v1.9 had exactly one shape, tested against the player's X alone, so jump and slide were inert
/// inside a fight and the encounter asked for one of the player's four verbs. Three shapes with
/// disjoint answers is the fix — see `Tuning.wardenCurtainKillBottom` for why the curtain has no
/// ceiling, which is the property that keeps a single jump from answering everything.
///
/// The renderer draws these as one binary the neon deck already answers — *is the red ON the grid
/// or hanging OVER it* — rather than as a height the player has to judge.
enum WardenBand: Sendable, Equatable, CaseIterable {
    case lance    // per-lane columns → change lane
    case floor    // full-width slab on the deck → jump
    case curtain  // full-width wall from the sky, stopping above the deck → slide

    /// Whether this shape closes lanes individually. Only a lance does; the other two span the deck,
    /// which is exactly why they cannot be answered laterally.
    var isLateral: Bool { self == .lance }
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
    var rank: Int                  // 1…wardenRankCap — how hard this one fights
    var z: Double                  // stand-off ahead of the player (negative = ahead) — ANIMATED
    var x: Double                  // lateral lean toward the lane the player is in
    var y: Double                  // hover height above the deck
    var shieldFraction: Double     // 1 → 0 across the shield phase; 0 once exposed
    var coreHits: Int              // 0 ..< coreHitsNeeded
    var coreHitsNeeded: Int        // rank-dependent, so the HUD must read THIS, never the constant
    var charge: Double             // the player's bank, 0…1 — drives fire rate, drains while firing
    var band: WardenBand           // the shape of the strike in flight — the renderer's whole read
    var beamMask: UInt8            // bit per closed lane; 0 when no attack is in flight (lance only)
    var telegraphProgress: Double  // 0 → 1 across the wind-up; 0 outside a telegraph
    var striking: Bool             // the beam is actually firing this tick
    var secondsRemaining: Double   // what is left of the shield window (`.shielded` only)

    /// Whether `lane` is closed by the beam currently in flight. A mask rather than an array so
    /// building this every frame allocates nothing. A floor or a curtain closes no *lane* — it spans
    /// them all — so this is meaningful only for `.lance`.
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
    var telegraphBand: WardenBand = .lance   // …and the shape it wound up as
    var struck = false         // the beam fired this tick
    var struckMask: UInt8 = 0  // the lanes it closed (lance only)
    var struckBand: WardenBand = .lance      // the shape that fired
    var caughtPlayer = false   // the player failed to answer it
    var coreHit = false        // the player answered it — the open core took a hit
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
    private(set) var rank: Int
    private(set) var shield: Double = Tuning.wardenShieldHP
    private(set) var coreHits: Int = 0
    private(set) var beamMask: UInt8 = 0
    /// The shape of the strike in flight. Meaningless outside a telegraph or its afterglow.
    private(set) var band: WardenBand = .lance

    private var phaseT: Double = 0     // seconds inside the current phase
    private var windowT: Double = 0    // seconds since the shield phase opened
    private var totalT: Double = 0     // seconds since arrival — checked against `wardenMaxSeconds`
    private var attacking = false      // inside a telegraph → strike → recover cycle
    private var strikeShow: Double = 0 // the beam stays lit this long AFTER it fires, so the hit is
                                       // something the player sees rather than infers
    private var attackIndex = 0        // how many telegraphs have begun — indexes the script
    /// 1 when the last strike was DODGED (the craft flinches), 0 when it landed (it does not).
    private var hitFlinch: Double = 0
    /// Whether this encounter ended in a KILL rather than a withdrawal — the two must not look alike.
    private var wasKilled = false
    private var rng: SplitMix64

    /// `runSeed` and `world` fully determine the attack order — no `Date()`, no `Double.random`.
    init(world: Int, runSeed: UInt64) {
        self.world = world
        self.rank = Tuning.wardenRank(world: world)
        // Mix the ordinal in rather than adding it, so consecutive worlds get unrelated streams.
        rng = SplitMix64(seed: runSeed ^ (UInt64(bitPattern: Int64(world)) &* 0x9E37_79B9_7F4A_7C15))
    }

    /// Clean answers still needed to kill it. Rank-dependent, so nothing may read the old constant.
    var coreHitsNeeded: Int { Tuning.wardenCoreHits(rank: rank) }

    /// Fraction of the shield still standing, 1 → 0.
    var shieldFraction: Double { max(0, shield / Tuning.wardenShieldHP) }

    /// A strike is winding up RIGHT NOW. `band` is its shape and, for a lance, `beamMask` is the set
    /// of lanes it will close.
    ///
    /// False during the `strikeShow` afterglow, when the shape is still lit but the shot is spent —
    /// so nothing (the Autopilot included) dodges a strike that has already fired.
    var isTelegraphing: Bool { phase == .exposed && attacking }

    /// The shape winding up right now, or `nil` if nothing is. The Autopilot's whole read.
    var pendingBand: WardenBand? { isTelegraphing ? band : nil }

    /// Seconds until the strike in flight resolves, or `.infinity` if none is. Lets the bot commit
    /// to a jump or a slide at a lead rather than guessing from phase state.
    var secondsToStrike: Double {
        isTelegraphing ? max(0, Tuning.wardenTelegraphTime(rank: rank) - phaseT) : .infinity
    }

    /// Whether the strike in flight closes `lane` (lance only — the other shapes span the deck).
    func closes(_ lane: Int) -> Bool { beamMask & (1 << UInt8(lane)) != 0 }

    /// Advance one fixed step.
    ///
    /// `charge` is the player's bank (0…1), drained in place while the gun is firing. `playerLane`
    /// is the lane the player has *committed* to and is read only when a telegraph locks on;
    /// `playerX` is where the body actually is and is what the strike tests against — the same
    /// split the rest of the game uses, so a lane change that has been input but not yet travelled
    /// does not teleport you out of a beam.
    ///
    /// The vertical terms are the S-009 addition. `top`/`bottom` are the player's body extent at the
    /// instant of the strike and are what a floor or a curtain tests; `jumpY`/`vy`/`grounded` are
    /// read at telegraph LOCK to decide whether a floor is answerable from where the player already
    /// is. All of them are final for the tick, because `GameCore.stepWarden` runs after
    /// `stepPlayer` — a strike always resolves against where the body actually ended up.
    mutating func step(_ dt: Double, playerLane: Int, playerX: Double,
                       playerTop: Double, playerBottom: Double,
                       jumpY: Double, vy: Double, grounded: Bool,
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
            // The fired strike lingers briefly. `wardenAttackRecover` is longer than this at every
            // rank, so the lit shape has always cleared before the next telegraph locks a new one.
            if strikeShow > 0 {
                strikeShow = max(0, strikeShow - dt)
                if strikeShow == 0 { beamMask = 0 }
            }
            if !attacking {
                if phaseT >= Tuning.wardenAttackRecover(rank: rank) {
                    attacking = true; phaseT = 0
                    band = pickBand(jumpY: jumpY, vy: vy, grounded: grounded)
                    beamMask = band.isLateral ? pickBeamMask(playerLane: playerLane) : 0b111
                    attackIndex += 1
                    out.telegraphBegan = true
                    out.telegraphBand = band
                }
            } else if phaseT >= Tuning.wardenTelegraphTime(rank: rank) {
                // The strike resolves on one tick: fail to answer its shape and it catches you,
                // answer it and the open core eats the shot.
                out.struck = true
                out.struckMask = beamMask
                out.struckBand = band
                if Collisions.wardenStrikeHit(playerX: playerX, playerTop: playerTop,
                                              playerBottom: playerBottom, mask: beamMask,
                                              band: band) {
                    out.caughtPlayer = true
                    hitFlinch = 0
                } else {
                    coreHits += 1
                    out.coreHit = true
                    hitFlinch = 1
                    if coreHits >= coreHitsNeeded {
                        out.killed = true
                        wasKilled = true
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

    /// The lanes the next lance closes.
    ///
    /// It ALWAYS closes the lane the player is standing in as the telegraph begins, so standing
    /// still is always fatal and the gun can never win a fight by itself. Increasingly often it also
    /// closes one other lane, leaving exactly one safe answer — which is what forces the wind-up to
    /// be *read* rather than answered with a reflex sidestep. The chance climbs with every landed
    /// core hit, so the last lance of a fight is a real read even though the first one forgives.
    ///
    /// Never more than two of three lanes, so a safe answer always exists and the attack always
    /// resolves in one cycle. One lane to move to, one input to give: decree 6 holds.
    private mutating func pickBeamMask(playerLane: Int) -> UInt8 {
        var mask: UInt8 = 1 << UInt8(playerLane)
        if rng.chance(Tuning.wardenDoubleBeamChance(rank: rank, coreHits: coreHits)) {
            let others = (0..<3).filter { $0 != playerLane }
            mask |= 1 << UInt8(others[rng.int(0, others.count - 1)])
        }
        return mask
    }

    /// The shape of the next strike.
    ///
    /// **The order is scripted, not rolled**, and consumes zero RNG. Two reasons, both deliberate:
    /// every player's first Warden is then the same designed introduction (lance to establish the
    /// grammar, then the two new shapes, then a lance again), and a fight's difficulty stops being
    /// a dice roll — nobody draws three curtains in a row and nobody draws none. The RNG is spent
    /// only on *which lanes* a lance closes, which is the one place variety is worth entropy.
    ///
    /// The reachability substitution is the fairness term. A floor demands a jump, and a player who
    /// is already airborne and descending may have no way to be high enough when it lands — an
    /// unanswerable frame, which would breach the owner's "not impossible" bar. So if the script
    /// says floor and a floor is not reachable from where the player already is, a CURTAIN fires
    /// instead: answerable from every vertical state, always, so the function is total.
    ///
    /// This cannot be farmed. Jumping to dodge a floor you were going to be given anyway buys you a
    /// curtain you must slam and slide under — a strictly *harder* demand, bought with an input you
    /// did not need. Pinned by `WardenTests.testDodgingIntoTheSubstitutionIsNeverAnEasierFight`.
    private func pickBand(jumpY: Double, vy: Double, grounded: Bool) -> WardenBand {
        let scripted = Self.script(rank: rank)[attackIndex % Self.script(rank: rank).count]
        guard scripted == .floor else { return scripted }
        return Self.floorIsReachable(jumpY: jumpY, vy: vy, grounded: grounded,
                                     secondsToStrike: Tuning.wardenTelegraphTime(rank: rank))
            ? .floor : .curtain
    }

    /// The fixed shape order per rank. Rank 1 opens with a lance — the shape v1.9 already taught —
    /// before asking for anything new, and every rank alternates channels so no two consecutive
    /// strikes are answered by the same verb.
    static func script(rank: Int) -> [WardenBand] {
        switch rank {
        case 1:  return [.lance, .floor, .curtain, .lance]
        case 2:  return [.lance, .floor, .curtain, .lance, .floor]
        default: return [.floor, .curtain, .lance, .floor, .curtain, .lance]
        }
    }

    /// Whether the player can be clear of a full-width floor `T` seconds from now.
    ///
    /// Pure function of the player's vertical state — no simulation state, no RNG, Foundation only,
    /// so the encounter, the bot and the tests all agree by construction.
    ///
    /// Clearing a floor means the body's underside is at or above `wardenFloorKillTop` (0.85), which
    /// standing needs `jumpY ≥ 0.75`. From the ground that is any launch inside [0.078, 0.737] s of
    /// the strike. Airborne there are two ways: the arc the player is already on is high enough when
    /// it lands, or they touch down early enough to launch a fresh one. The second branch uses the
    /// NATURAL landing time, never the air-slam — the rule must never depend on an input the player
    /// might not give.
    static func floorIsReachable(jumpY: Double, vy: Double, grounded: Bool,
                                 secondsToStrike T: Double) -> Bool {
        // Height the body must reach for its underside to clear the slab, standing.
        let need = Tuning.wardenFloorKillTop - (Tuning.groundedCenterY - Tuning.bodyRadius) - 0.06
        // Shortest time from a standing launch until the arc is above `need`.
        let disc = Tuning.jumpV0 * Tuning.jumpV0 - 2 * Tuning.gravity * need
        guard disc > 0 else { return false }   // unreachable even by a perfect jump — cannot happen
        let riseT = (Tuning.jumpV0 - disc.squareRoot()) / Tuning.gravity
        if grounded { return T >= riseT }

        // Already airborne: is this arc high enough at the moment of the strike?
        if jumpY + vy * T - 0.5 * Tuning.gravity * T * T >= need { return true }
        // Otherwise, does it land early enough to leave room for a fresh jump?
        let land = (vy + (vy * vy + 2 * Tuning.gravity * jumpY).squareRoot()) / Tuning.gravity
        return land <= T - riseT
    }

    /// The renderable view of this encounter.
    ///
    /// `playerX` lets the craft lean toward the lane the player is in. It is presentation only —
    /// nothing here feeds a collision or a draw — so it cannot affect determinism.
    func state(charge: Double, playerX: Double = 0) -> WardenState {
        let telegraph: Double = (phase == .exposed && attacking)
            ? min(1, phaseT / Tuning.wardenTelegraphTime(rank: rank)) : 0
        let firing = phase == .exposed && strikeShow > 0
        // The craft closes in as it arrives and climbs away as it leaves, so entrance and exit read
        // as movement rather than a pop. `z` is negative = ahead, matching `EntityState`.
        //
        // **Depth genuinely animates now (S-009).** For all of v1.9 `z` was the constant
        // `-wardenStandOff` while this comment claimed it closed in; only `y` ever moved. It now
        // approaches on arrival, recoils when the core is hit, and retreats as it leaves.
        let arrive = phase == .arriving ? min(1, phaseT / Tuning.wardenArriveTime) : 1
        // **A KILLED Warden does not fly away.** `.dying` falls through to `.leaving`, so applying
        // the departure rise/retreat unconditionally meant the corpse serenely climbed 14 units and
        // retreated 26 immediately after detonating — a killed Warden left exactly like one that had
        // given up, which erased the difference between winning and being ignored. A kill now sinks
        // instead: it drops and drifts toward the player as the wreck clears.
        let leave = (phase == .leaving && !wasKilled) ? min(1, phaseT / Tuning.wardenLeaveTime) : 0
        let fall = (wasKilled && (phase == .dying || phase == .leaving))
            ? min(1, phaseT / Tuning.wardenDieTime) : 0
        // The recoil decays over the same window the fired shape stays lit, so "I dodged" and "it
        // flinched" are the same beat.
        let recoil = strikeShow > 0 && phase != .dying
            ? (strikeShow / Tuning.wardenStrikeShowTime) * Tuning.wardenHitRecoil * hitFlinch
            : 0
        return WardenState(
            phase: phase,
            world: world,
            rank: rank,
            z: -(Tuning.wardenStandOff + (1 - arrive) * Tuning.wardenArriveDepth
                                       + leave * Tuning.wardenLeaveDepth + recoil),
            // Leans toward the player's lane, eased so it never snaps. Zero while dying or leaving:
            // a craft that is finished stops paying attention.
            //
            // **And zero once a strike is committed.** `pickBeamMask` locks the target lane at the
            // START of a telegraph, so a craft that kept tracking the player through the wind-up
            // visibly aimed AWAY from the beam it had already committed to — 1.6 units of lateral
            // motion telling the player the opposite of the truth, in the one window where reading
            // the attack is the whole game (decree 6). It is also meaningless for a floor or a
            // curtain, which close every lane and have no direction to point in.
            x: (phase == .shielded || (phase == .exposed && !attacking))
                ? (playerX / max(0.001, Tuning.laneX.last ?? 1)) * Tuning.wardenLeanX : 0,
            y: Tuning.wardenHoverY + (1 - arrive) * Tuning.wardenArriveRise
                                   + leave * Tuning.wardenLeaveRise
                                   - fall * Tuning.wardenDeathSink,
            shieldFraction: shieldFraction,
            coreHits: coreHits,
            coreHitsNeeded: coreHitsNeeded,
            charge: charge,
            band: band,
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
