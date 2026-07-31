import Foundation

/// Which stage of a Warden encounter the run is in.
///
/// The order is the order they happen in; there is no path that skips backwards.
enum WardenPhase: Sendable, Equatable {
    case arriving   // the craft drops into view ahead — nothing is on the deck yet
    case shielded   // it throws; every answered hazard chips the armour
    case exposed    // armour gone, core open; every answered hazard damages it
    case dying      // killed — the detonation beat before it clears the sky
    case leaving    // broke off (it ran out of time), or finished dying
}

/// The shape a throw takes, and therefore the verb that answers it.
///
/// **v2.2 kept the trichotomy and threw away the drawing.** S-009's insight was right and survives
/// intact: a boss that tests one axis leaves three of the player's verbs inert, so a strike must come
/// in one of three shapes with genuinely disjoint answers. What was wrong was that all three were
/// abstract red bands painted on the player's own plane after a 0.70–0.80 s wind-up. The S-011 render
/// audit measured the result — a full-width opaque red band on screen for 92–95% of the exposed
/// phase, a 100 ms dark gap between shapes, and a curtain that erased every pixel of track beyond
/// 5.3 m.
///
/// Each band is now the name of a REAL OBSTACLE the Warden launches down the track
/// (`Tuning.wardenThrowKind`), and the wind-up is the time it takes to arrive.
enum WardenBand: Sendable, Equatable, CaseIterable {
    case lance    // two tall walls, one lane open → change lane
    case floor    // a chasm blown in the deck     → jump
    case curtain  // a hanging bar                 → slide

    /// Whether this shape closes lanes individually. Only a lance does; the other two span the deck,
    /// which is exactly why they cannot be answered laterally.
    var isLateral: Bool { self == .lance }
}

/// Immutable per-frame view of an encounter, carried inside `GameSnapshot`.
///
/// `z` follows the same convention as `EntityState`: negative is AHEAD of the player. The Warden
/// hangs at a stand-off and never reaches the player plane — it is a set piece, not an obstacle,
/// which is exactly why it is modelled here and not as an `EntityKind` (see the note on
/// `WardenEncounter`).
struct WardenState: Sendable, Equatable {
    var phase: WardenPhase
    var world: Int                 // the world ordinal this Warden belongs to (3, 6, 9, …)
    var rank: Int                  // 1…wardenRankCap — how hard this one fights
    var z: Double                  // stand-off ahead of the player (negative = ahead) — ANIMATED
    var x: Double                  // lateral lean toward the lane the player is in
    var y: Double                  // hover height above the deck
    var shieldFraction: Double     // 1 → 0 across the armour phase; 0 once exposed
    var coreHits: Int              // 0 ..< coreHitsNeeded
    var coreHitsNeeded: Int        // rank-dependent, so the HUD must read THIS, never the constant
    var charge: Double             // the player's blast bank, 0…1
    var band: WardenBand           // the shape of the last thing it threw
    /// 1 → 0 over the beat after a throw. The craft's muzzle flash: the ONE moment the player should
    /// look up, because something just left it.
    var throwFlash: Double
    /// Seconds until it gives up and leaves with the bounty. This is the fight's whole clock now —
    /// there is no separate shield window — so the HUD can show one honest countdown.
    var secondsRemaining: Double
}

/// What one encounter tick did, handed back to `GameCore` to apply.
///
/// The encounter decides *what happened*; the core owns every consequence (spawning the hazard,
/// payout, FX). Same split as `Collisions`: the rule is testable without a running simulation.
struct WardenTick: Equatable {
    var justArmed = false      // the craft finished arriving and the fight began
    var threw = false          // it launched a hazard this tick
    var throwBand: WardenBand = .lance   // …of this shape
    var throwLead: Double = 0            // …this many metres ahead of the player
    var throwOpenLane: Int = 1           // …leaving this lane open (a lance only)
    var brokeOff = false       // the clock ran out with it alive — it leaves, you lose the reward
    var finished = false       // the encounter is over; the core may clear it
}

/// What answering a hazard did to the Warden.
enum WardenDamage: Sendable, Equatable {
    case armourChipped   // the shield took it
    case armourBroke     // …and that was the last of the shield: the core is open
    case coreHit         // the open core took it
    case killed          // …and that was the last one
}

/// A Warden encounter: the per-world antagonist that punctuates the run every third world.
///
/// **It can never kill you (v2.2, D-028).** This is the owner's instruction, and it matches every
/// shipped runner boss the S-011 research pass examined — Sonic Dash, Minion Rush, Crash On the Run
/// all model the boss as an OPPORTUNITY layer: the boss itself has no kill move, the lethal thing is
/// the obstacle it places, and failure means the boss escapes with the reward rather than ending the
/// run. v1.9–v2.1 inverted that: two landed beams 1.20 s apart ended a run outright.
///
/// So the Warden has no attack of its own at all. It throws real obstacles down the real track, and
/// inside the arena those obstacles STAGGER rather than kill (`GameCore.stepObstacles`). What a
/// landed hazard costs is the multiplier, a blast round, and — the one that actually decides the
/// fight — the answer it would have been worth. Miss enough and the clock runs out with the Warden
/// alive, and it leaves with your bounty.
///
/// **Why this is not an `EntityKind`.** Every other spawned thing in the game is an obstacle on the
/// deck, and `Core/` has several switches over `EntityKind` that carry a `default:` arm. A new case
/// added there is silently accepted by all of them and becomes a decorative, non-lethal prop that the
/// solvability bot cannot see. A Warden is a set piece with its own state machine and its own
/// lifetime, so it lives here as a first-class field of the snapshot instead.
///
/// **Determinism.** The encounter draws from its OWN `SplitMix64`, derived from the run seed and the
/// world ordinal. It never touches the run's spawn stream, so arming a Warden costs zero draws and
/// cannot shift a single pattern (iron rule 2). The hazards it throws are placed through a dedicated
/// path that consumes no rng either.
struct WardenEncounter {
    private(set) var phase: WardenPhase = .arriving
    private(set) var world: Int
    private(set) var rank: Int
    private(set) var armourHits: Int = 0
    private(set) var coreHits: Int = 0
    /// The shape of the last thing thrown. Meaningless before the first throw.
    private(set) var band: WardenBand = .lance

    private var phaseT: Double = 0     // seconds inside the current phase
    private var totalT: Double = 0     // seconds since arrival — checked against `wardenMaxSeconds`
    private var throwT: Double = 0     // seconds since the last throw
    private var throwIndex = 0         // how many throws have happened — indexes the script
    private var flash: Double = 0      // muzzle-flash decay after a throw
    /// Whether this encounter ended in a KILL rather than a withdrawal — the two must not look alike.
    private var wasKilled = false
    private var rng: SplitMix64

    /// `runSeed` and `world` fully determine the throw order — no `Date()`, no `Double.random`.
    init(world: Int, runSeed: UInt64) {
        self.world = world
        self.rank = Tuning.wardenRank(world: world)
        // Mix the ordinal in rather than adding it, so consecutive worlds get unrelated streams.
        rng = SplitMix64(seed: runSeed ^ (UInt64(bitPattern: Int64(world)) &* 0x9E37_79B9_7F4A_7C15))
    }

    /// Clean answers still needed on the open core. Rank-dependent, so nothing may read the constant.
    var coreHitsNeeded: Int { Tuning.wardenCoreHits(rank: rank) }

    /// Fraction of the armour still standing, 1 → 0.
    var shieldFraction: Double {
        max(0, 1 - Double(armourHits) / Double(Tuning.wardenShieldHits))
    }

    /// Whether the fight is live — i.e. whether a hazard on the deck belongs to this encounter and
    /// should be treated as its throw rather than as ordinary track.
    var isFighting: Bool { phase == .shielded || phase == .exposed }

    /// How far ahead the next hazard is launched.
    ///
    /// **It closes as the Warden takes damage**, 46 m → 26 m, and that single lerp buys three things
    /// at once. The fight escalates without any timer getting shorter. The craft grows as it closes,
    /// so the climax is the moment it has the most presence on screen — the opposite of v2.1, where
    /// it was largest at the start and its own attacks then covered the frame. And the boss's health
    /// becomes SPATIAL: a player can see they are winning because the thing is in their face.
    var throwLead: Double {
        let total = Double(Tuning.wardenAnswersToKill(rank: rank))
        let done = min(1, Double(armourHits + coreHits) / max(1, total))
        return Tuning.wardenThrowLeadFar
            + (Tuning.wardenThrowLeadNear - Tuning.wardenThrowLeadFar) * done
    }

    /// Advance one fixed step.
    ///
    /// Note what this no longer takes: the player's lane, x, body extent, jump height, velocity or
    /// grounded flag. v2.1 needed all six because a strike resolved against the body on the tick it
    /// fired. A thrown hazard resolves the way every other obstacle in the game does — in
    /// `GameCore.stepObstacles`, against `Collisions` — so the encounter's whole job is the clock,
    /// the health and the throw script. `playerLane` survives only to pick which lane a lance leaves
    /// open, which is chosen at LAUNCH and never revised.
    mutating func step(_ dt: Double, playerLane: Int) -> WardenTick {
        var out = WardenTick()
        phaseT += dt
        totalT += dt
        if flash > 0 { flash = max(0, flash - dt / Tuning.wardenThrowFlashTime) }

        // The hard ceiling, and the whole of the failure state: run out of time with it alive and it
        // leaves with the bounty. The player keeps the run — that is the point of the rebuild.
        if totalT >= Tuning.wardenMaxSeconds, phase != .dying, phase != .leaving {
            phase = .leaving; phaseT = 0
            out.brokeOff = true
            return out
        }

        switch phase {
        case .arriving:
            if phaseT >= Tuning.wardenArriveTime {
                phase = .shielded; phaseT = 0
                // Throw immediately: the arrival IS the wind-up for the first hazard, and a Warden
                // that hangs there doing nothing was the single stretch of v2.1 with nothing to do
                // in it.
                throwT = Tuning.wardenThrowInterval(rank: rank)
                out.justArmed = true
            }

        case .shielded, .exposed:
            throwT += dt
            guard throwT >= Tuning.wardenThrowInterval(rank: rank) else { break }
            // Never launch something that cannot arrive before the clock stops. A hazard still in
            // flight when the encounter ends would be swept off the deck by `GameCore`, which reads
            // as the boss's attack simply evaporating.
            let lead = throwLead
            guard totalT + lead / Tuning.speedCap < Tuning.wardenMaxSeconds else { break }
            throwT = 0
            band = Self.script(rank: rank)[throwIndex % Self.script(rank: rank).count]
            throwIndex += 1
            flash = 1
            out.threw = true
            out.throwBand = band
            out.throwLead = lead
            out.throwOpenLane = band.isLateral ? pickOpenLane(playerLane: playerLane) : 1

        case .dying:
            if phaseT >= Tuning.wardenDieTime { phase = .leaving; phaseT = 0 }

        case .leaving:
            if phaseT >= Tuning.wardenLeaveTime { out.finished = true }
        }

        return out
    }

    /// The player answered a hazard — dodged it clean, or blasted it out of the air. Both are worth
    /// exactly one hit, and that equivalence is the design: dodging is free and blasting costs a
    /// round, so dodging is always the better answer and the blast is insurance, never a shortcut.
    ///
    /// Returns `nil` when the encounter is not in a damageable phase (a hazard that outlives the
    /// fight must not damage a corpse).
    mutating func registerAnswer() -> WardenDamage? {
        guard isFighting else { return nil }
        if phase == .shielded {
            armourHits += 1
            if armourHits >= Tuning.wardenShieldHits {
                phase = .exposed; phaseT = 0
                return .armourBroke
            }
            return .armourChipped
        }
        coreHits += 1
        if coreHits >= coreHitsNeeded {
            wasKilled = true
            phase = .dying; phaseT = 0
            return .killed
        }
        return .coreHit
    }

    /// The lane a lance leaves open.
    ///
    /// **Never the lane the player is standing in when it launches**, so standing still is always
    /// punished and the Warden can never be beaten by ignoring it. That invariant is inherited
    /// verbatim from v1.9's beam, where it was load-bearing for the same reason: an earlier build
    /// that merely *usually* stalked let a player who never moved win outright whenever three
    /// consecutive attacks happened to pick an empty lane, because "wasn't in the beam" was being
    /// scored as a dodge. It isn't one.
    ///
    /// One rng draw, from the encounter's own stream. Exactly one lane is ever open, so the answer
    /// is unambiguous and the hazard always resolves in one pass — the fight stays bounded and can
    /// never outrun its arena.
    private mutating func pickOpenLane(playerLane: Int) -> Int {
        let others = (0..<3).filter { $0 != playerLane }
        return others[rng.int(0, others.count - 1)]
    }

    /// The fixed shape order per rank, consuming zero RNG.
    ///
    /// Scripted rather than rolled for two reasons, both deliberate: every player's first Warden is
    /// then the same designed introduction (a lance to establish that it throws real things, then
    /// the two new demands, then a lance again), and a fight's difficulty stops being a dice roll —
    /// nobody draws three chasms in a row and nobody draws none. Every rank alternates channels so
    /// no two consecutive throws are answered by the same verb.
    static func script(rank: Int) -> [WardenBand] {
        switch rank {
        case 1:  return [.lance, .floor, .curtain, .lance]
        case 2:  return [.lance, .floor, .curtain, .lance, .floor]
        default: return [.floor, .curtain, .lance, .floor, .curtain, .lance]
        }
    }

    /// The renderable view of this encounter.
    ///
    /// `playerX` lets the craft lean toward the lane the player is in. It is presentation only —
    /// nothing here feeds a collision or a draw — so it cannot affect determinism.
    func state(charge: Double, playerX: Double = 0) -> WardenState {
        // The craft closes in as it arrives and climbs away as it leaves, so entrance and exit read
        // as movement rather than a pop. `z` is negative = ahead, matching `EntityState`.
        let arrive = phase == .arriving ? min(1, phaseT / Tuning.wardenArriveTime) : 1
        // **A KILLED Warden does not fly away.** `.dying` falls through to `.leaving`, so applying
        // the departure rise/retreat unconditionally meant the corpse serenely climbed away
        // immediately after detonating — a killed Warden left exactly like one that had given up,
        // which erased the difference between winning and being ignored. A kill sinks instead.
        let leave = (phase == .leaving && !wasKilled) ? min(1, phaseT / Tuning.wardenLeaveTime) : 0
        let fall = (wasKilled && (phase == .dying || phase == .leaving))
            ? min(1, phaseT / Tuning.wardenDieTime) : 0
        // The recoil rides the muzzle flash: the craft rocks back on the throw, which is the beat
        // that says the thing now on the track came from up there.
        let recoil = flash * Tuning.wardenHitRecoil
        return WardenState(
            phase: phase,
            world: world,
            rank: rank,
            // **The stand-off IS the throw lead** (v2.2). It has to be: a hazard that appears further
            // away than the craft supposedly throwing it is a lie the player can see, and decree 2
            // is that previews never lie. So the craft sits exactly where its next hazard will
            // materialise, and closes in with it as the fight turns.
            z: -(throwLead + (1 - arrive) * Tuning.wardenArriveDepth
                           + leave * Tuning.wardenLeaveDepth + recoil),
            // Leans toward the player's lane while it is still deciding. Zero once it has thrown and
            // while dying or leaving: a craft that has committed — or is finished — stops pointing.
            x: (phase == .shielded || phase == .exposed) && flash <= 0
                ? (playerX / max(0.001, Tuning.laneX.last ?? 1)) * Tuning.wardenLeanX : 0,
            y: Tuning.wardenHoverY + (1 - arrive) * Tuning.wardenArriveRise
                                   + leave * Tuning.wardenLeaveRise
                                   - fall * Tuning.wardenDeathSink,
            shieldFraction: shieldFraction,
            coreHits: coreHits,
            coreHitsNeeded: coreHitsNeeded,
            charge: charge,
            band: band,
            throwFlash: flash,
            secondsRemaining: isFighting ? max(0, Tuning.wardenMaxSeconds - totalT) : 0
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

    /// Whether `d` falls inside a Warden arena — the stretch of deck kept clear of PROCEDURAL
    /// obstacles so the only things on it are the ones the Warden put there (decree 6).
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
    /// gem field on purpose. Gems are the blast bank, so the fight is fought with ammunition earned
    /// inside it, and a player who runs dry can still farm their way back into the fight.
    ///
    /// Pads are dropped with the obstacles because a boost inside the arena would carry the player
    /// past the encounter's distance budget.
    ///
    /// **This is only about the SPAWNER.** The Warden's own thrown hazards are placed through
    /// `GameCore.applyThrown`, which deliberately bypasses this gate — they are the reason the deck
    /// is being kept clear, not something to be cleared off it.
    static func suppresses(_ cmd: SpawnCmd) -> Bool {
        switch cmd {
        case let .low(d, _), let .tall(d, _), let .bar(d), let .splitBar(d, _),
             let .movingTall(d, _), let .chasm(d), let .boostPad(d, _), let .hangingBar(d):
            return isArena(d)
        case .gem, .shield, .magnet, .doubler, .chrono, .superSneakers, .ring:
            return false
        }
    }
}
