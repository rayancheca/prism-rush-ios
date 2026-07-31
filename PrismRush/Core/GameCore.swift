import Foundation
import Observation

/// A live blast shockwave (v2.2).
///
/// Pure geometry in the distance domain — no RNG, no entity references, no renderer. It starts on
/// the player's own plane and runs forward to `limitD`, shattering every destructible obstacle whose
/// spawn distance it passes. Modelled in ABSOLUTE distance rather than relative `z` for the same
/// reason every entity is: the world scrolls under the player, so an absolute anchor is the only one
/// that stays put while the front travels.
struct BlastWave: Sendable, Equatable {
    var startD: Double    // where the front was born (the player's plane at the instant of firing)
    var frontD: Double    // how far it has reached
    var limitD: Double    // where it dies — `startD + Tuning.blastRange`
}

/// One live spawned thing inside the simulation (pre-snapshot, mutable).
struct CoreEntity {
    var id: Int
    var kind: EntityKind
    var lane: Int          // -1 for bar
    var d: Double          // absolute spawn distance; relative z = distance - d
    var x: Double          // current world x (gems drift under magnet; moving wall is computed live)
    var baseY: Double      // gem / pickup base height (collision uses this, before cosmetic bob)
    var phase: Double      // moving-wall oscillation phase
    var passed: Bool
    var fading: Bool
    /// Thrown by a Warden rather than drawn by the spawner (v2.2). Three consequences, all of them
    /// the reason the flag exists rather than a lookup: inside an arena it can only ever STAGGER
    /// (the boss has no kill move), answering it damages the Warden, and the renderer tints it in
    /// the Warden's own hazard colour so the player can tell whose wall it is.
    var fromWarden: Bool = false
    /// Metres per second this entity travels TOWARD the player, on top of the track scroll (v2.3).
    ///
    /// **This is what "sending walls down the lane" means** (owner, S-013: *"its not sending walls
    /// down the lane like i asked … the walls he send come quicker like the trains from subway
    /// surfers"*). Until v2.2 every obstacle in the game — including a Warden's — was pinned to a
    /// fixed `d` and the player simply ran into it. Nothing was ever launched AT anybody, so the
    /// boss's "attack" was indistinguishable from ordinary track that happened to be red.
    ///
    /// A closing hazard is launched from further out and arrives sooner, which buys three things at
    /// once: it visibly rushes (the Subway Surfers train read), the reaction window becomes a TIME
    /// budget the rank ladder can tighten, and because it clears the deck faster the throw interval
    /// can shrink without ever putting two opposite verbs on the deck at once.
    ///
    /// **Zero by default, and every spawner-placed obstacle leaves it zero** — so the seeded stream,
    /// the 200-seed solvability proof and every daily-challenge golden are untouched by this field's
    /// existence. Only `applyThrown` ever sets it.
    var closeSpeed: Double = 0
}

/// The deterministic, renderer-agnostic game engine.
///
/// Fixed timestep of `Tuning.tickDt` (1/120 s) with an accumulator; rendering interpolates.
/// All randomness flows through `rng`, so a seed fully determines a run. No imports of any
/// renderer or UIKit — this is what makes the test suite possible.
@Observable @MainActor
final class GameCore {
    /// The only observed property: SwiftUI re-renders when this changes (once per rendered frame).
    private(set) var snapshot: GameSnapshot = .initial

    /// Sink for one-shot effects (audio / haptics / renderer bursts). Set by the host.
    @ObservationIgnored var onFX: ((FXEvent) -> Void)?

    // MARK: simulation state (ObservationIgnored — mutates every tick; only `snapshot` drives UI)

    @ObservationIgnored private(set) var mode: GameMode = .menu
    @ObservationIgnored private(set) var distance: Double = 0
    @ObservationIgnored private(set) var scoreOffset: Double = 0   // checkpoint head-start (not scored)
    @ObservationIgnored private(set) var speed: Double = Tuning.menuSpeed
    @ObservationIgnored private(set) var px: Double = 0
    @ObservationIgnored private(set) var laneIndex: Int = 1
    @ObservationIgnored private(set) var jumpY: Double = 0
    @ObservationIgnored private(set) var vy: Double = 0
    @ObservationIgnored private(set) var grounded: Bool = true
    @ObservationIgnored private(set) var slideT: Double = 0
    @ObservationIgnored private(set) var sy: Double = 1
    @ObservationIgnored private(set) var bankZ: Double = 0
    @ObservationIgnored private(set) var jumpBuf: Double = 0
    @ObservationIgnored private(set) var world: Int = 0
    @ObservationIgnored private(set) var maxWorld: Int = 0
    @ObservationIgnored private(set) var worldFrom: Int = 0
    @ObservationIgnored private(set) var worldTo: Int = 0
    @ObservationIgnored private(set) var worldBlend: Double = 1
    @ObservationIgnored private(set) var shield: Bool = false
    @ObservationIgnored private(set) var invulnT: Double = 0   // post-shield-absorb grace window
    /// Seconds left of the post-stumble recovery (v2.0). While > 0 the player is **fully vulnerable**
    /// and the next contact of any kind is fatal — the whole "1.5 lives" limit, held in one Double.
    @ObservationIgnored private(set) var stumbleT: Double = 0
    /// Contacts survived this run. Written for one reason that matters more than the stat: the
    /// solvability bot decides "unfair" by asking whether it DIED, and a survivable contact would
    /// silently turn an impossible pattern into a green stagger. `SolvabilityBotTests` asserts this
    /// stays zero, so the 200-seed proof keeps proving what it claims to.
    @ObservationIgnored private(set) var stumbles: Int = 0
    @ObservationIgnored private(set) var magnetT: Double = 0
    @ObservationIgnored private(set) var doublerT: Double = 0  // gems pay double currency while > 0
    @ObservationIgnored private(set) var chronoT: Double = 0   // slow-mo: distance integrates at × chronoFactor
    @ObservationIgnored private(set) var boostT: Double = 0    // overdrive: world speed × boostFactor (capped)
    @ObservationIgnored private(set) var superSneakersT: Double = 0  // > 0 → jumps launch at × superSneakersJumpMult
    @ObservationIgnored private(set) var flowStreak: Int = 0   // near-misses since last surge/reset (§C.1) — always < flowPerSurge
    @ObservationIgnored private(set) var flowSurges: Int = 0   // surges this run (FX escalation level, 1-based)
    @ObservationIgnored private(set) var bonus: Int = 0
    @ObservationIgnored private(set) var score: Int = 0
    @ObservationIgnored private(set) var gemCount: Int = 0
    @ObservationIgnored private(set) var streak: Int = 0
    @ObservationIgnored private(set) var bestStreak: Int = 0
    @ObservationIgnored private(set) var mult: Int = 1
    @ObservationIgnored var best: Int = 0
    @ObservationIgnored private(set) var revivesUsed = 0   // continues taken this run (escalating cost)
    @ObservationIgnored private var deathDistance: Double = 0   // where the run died (revive scrubs the decel drift)
    @ObservationIgnored private(set) var usedCheckpoint = false // run began mid-track (not leaderboard-eligible)

    /// The live Warden encounter, or `nil` on open track (v1.9).
    @ObservationIgnored private(set) var warden: WardenEncounter?
    /// The last world whose Warden is finished — stops an arena re-arming behind the player.
    @ObservationIgnored private(set) var wardenWorldDone: Int = -1
    /// Charge bank, 0…1: earned one gem at a time, spent one BLAST at a time (v2.2). Still named
    /// `wardenCharge` because it is still the Warden's ammunition — it is simply no longer *only*
    /// that, which is the whole point: the meter now means something from the first gem of the first
    /// run rather than from the first Warden 104 seconds later.
    @ObservationIgnored private(set) var wardenCharge: Double = 0
    /// The shockwave in flight, or `nil`. At most one at a time — a second blast while one is
    /// travelling simply replaces it, which is what the `guard` in `blast()` prevents anyway.
    @ObservationIgnored private(set) var blastWave: BlastWave?
    /// Blasts fired this run, and obstacles they destroyed. Run statistics only — nothing in the
    /// simulation reads them, but the missions layer and the session log both want them.
    @ObservationIgnored private(set) var blastsFired: Int = 0
    @ObservationIgnored private(set) var obstaclesShattered: Int = 0
    /// Wardens killed this run — the meta layer banks this once, in `applyRunSummary`.
    @ObservationIgnored private(set) var wardensDefeatedThisRun: Int = 0
    /// Wardens MET this run, won or lost (v2.3). Gates the first-time verb coaching.
    @ObservationIgnored private(set) var wardensMetThisRun: Int = 0
    /// Warden bounty coins earned this run. Kept OUT of `gemCount` so a kill never inflates the
    /// run's gem stat, its gem missions or its per-gem XP — see the payout site in `stepWarden`.
    @ObservationIgnored private(set) var bountyCoins: Int = 0
    /// The run's seed, kept so a Warden can derive its OWN stream from it without ever drawing from
    /// the spawn stream (iron rule 2 — arming a Warden costs zero `rng` calls).
    @ObservationIgnored private(set) var runSeed: UInt64

    @ObservationIgnored private(set) var activeObstacles: [CoreEntity] = []
    @ObservationIgnored private(set) var activeGems: [CoreEntity] = []
    @ObservationIgnored private(set) var activePickups: [CoreEntity] = []

    @ObservationIgnored private var rng: SplitMix64
    @ObservationIgnored private var spawner = Spawner()
    @ObservationIgnored private var accumulator: Double = 0
    @ObservationIgnored private var nextId: Int = 0
    @ObservationIgnored private var powerUpCursor: Double = Tuning.powerUpFirstAt  // next guaranteed power-up mark
    @ObservationIgnored private var powerUpIndex: Int = 0   // cycles the cadence through all kinds

    init(seed: UInt64 = .random(in: .min ... .max)) {
        rng = SplitMix64(seed: seed)
        runSeed = seed
        activeObstacles.reserveCapacity(Tuning.capLow + Tuning.capTall + Tuning.capBar)
        activeGems.reserveCapacity(Tuning.capGem)
        activePickups.reserveCapacity(Tuning.capShield + Tuning.capMagnet)
        rebuildSnapshot()
    }

    // MARK: - Lifecycle

    /// Begin a run. `best` is preserved; provide a `seed` for deterministic runs (tests / replay).
    /// Begin a run. `startDistance > 0` starts at a reached checkpoint (its world + difficulty), but
    /// score & coins still count from zero (`scoreOffset`). Checkpoint runs still ramp toward the
    /// end-game speed (66 pts/s) far sooner than a fresh run ever could, so they're strictly better
    /// for best-score chasing: `usedCheckpoint` flags them and the meta layer MUST skip Game Center
    /// submission for such runs (local best is fine).
    func startRun(seed: UInt64? = nil, startDistance: Double = 0) {
        let keepBest = best
        reset(seed: seed)
        best = keepBest
        mode = .play
        speed = Tuning.speedStart   // launch at the base play speed — no sluggish crawl off the line
        if startDistance > 0 {
            usedCheckpoint = true
            distance = startDistance
            scoreOffset = startDistance
            spawner.cursor = startDistance + 60
            powerUpCursor = startDistance + Tuning.powerUpFirstAt
            let wn = Int((startDistance / Tuning.worldLength).rounded(.down))
            let wi = ((wn % 3) + 3) % 3
            maxWorld = wn; world = wi; worldFrom = wi; worldTo = wi; worldBlend = 1
            // A checkpoint run starts with an EMPTY charge bank, which is below the threshold that
            // can break a Warden's shield — so buying a start at world 3, 6, 9 or 12 used to
            // GUARANTEE that the first Warden you ever saw arrived, hung there, and withdrew.
            // A paid feature whose first act is a boss giving up on you is decree 3 (no
            // broken-looking states for expected situations) and decree 5 (advertised bonuses are
            // always delivered), so a checkpoint start is granted the charge a player would have
            // banked reaching that distance under their own steam.
            wardenCharge = min(1, startDistance / Tuning.worldLength
                                  * Tuning.wardenCheckpointChargePerWorld)
        }
        rebuildSnapshot()
    }

    /// Distance actually travelled this run (excludes a checkpoint head-start).
    var traveledDistance: Double { distance - scoreOffset }

    /// World speed the player actually experiences: chrono slow-mo and the overdrive boost scale
    /// the raw ramp `speed` without touching it, so the difficulty curve resumes seamlessly when
    /// their timers end. Chrono applies first, then the boost (capped) — the single composition
    /// point. Everything distance-domain (obstacle arrival, autopilot leads, scroll) uses this.
    var effectiveSpeed: Double {
        var v = speed
        if chronoT > 0 { v *= Tuning.chronoFactor }
        if boostT > 0 { v = min(v * Tuning.boostFactor, Tuning.boostSpeedMax) }
        return v
    }

    /// The factor applied to a closing hazard's OWN motion (v2.3).
    ///
    /// Chrono and only chrono: slow-mo is the promise that the world slows while the player's
    /// reflexes do not, so a thrown hazard has to slow with it. A boost is the opposite — the player
    /// chose to close the gap faster and the hazard's ground speed is none of their business — so it
    /// is absent here and shows up in `effectiveSpeed` instead, where the two velocities simply add.
    ///
    /// **`advanceClosingHazards` and `Autopilot.closingRatio` must both read THIS.** They are two
    /// halves of one arithmetic: the bot converts a real gap into a time-to-arrival by dividing by
    /// the same total closing rate the simulation moves the hazard at. When they disagreed (the bot
    /// briefly compared a chrono-scaled `effectiveSpeed` against an unscaled `closeSpeed`) the
    /// factors stopped cancelling, the bot read a closing chasm as nearer than it was, launched
    /// early into the one obstacle with a two-sided window, and slammed itself into the hole.
    var hazardCloseScale: Double { chronoT > 0 ? Tuning.chronoFactor : 1 }

    /// Vertical launch velocity for a fresh/buffered jump — boosted while Super Sneakers is active.
    /// Read at the takeoff sites only; ballistic gem-arc/ring PLACEMENT (Patterns) deliberately
    /// never reads this, so the buff over-clears rather than perturbing the seeded track.
    private var launchVelocity: Double {
        superSneakersT > 0 ? Tuning.jumpV0 * Tuning.superSneakersJumpMult : Tuning.jumpV0
    }

    /// Reset to the fresh menu state. Reseeds if `seed` is given (else a new random stream).
    func reset(seed: UInt64?) {
        let s = seed ?? .random(in: .min ... .max)
        rng = SplitMix64(seed: s)
        runSeed = s
        warden = nil; wardenWorldDone = -1; wardenCharge = 0
        wardensDefeatedThisRun = 0; wardensMetThisRun = 0
        blastWave = nil; blastsFired = 0; obstaclesShattered = 0
        spawner = Spawner()
        mode = .menu; distance = 0; scoreOffset = 0; speed = Tuning.menuSpeed; revivesUsed = 0
        deathDistance = 0; usedCheckpoint = false
        px = 0; laneIndex = 1; jumpY = 0; vy = 0; grounded = true; slideT = 0; sy = 1
        bankZ = 0; jumpBuf = 0
        world = 0; maxWorld = 0; worldFrom = 0; worldTo = 0; worldBlend = 1
        shield = false; invulnT = 0; magnetT = 0; doublerT = 0; chronoT = 0
        stumbleT = 0; stumbles = 0
        boostT = 0; superSneakersT = 0; flowStreak = 0; flowSurges = 0
        bonus = 0; score = 0; gemCount = 0; streak = 0; bestStreak = 0; mult = 1; bountyCoins = 0
        activeObstacles.removeAll(keepingCapacity: true)
        activeGems.removeAll(keepingCapacity: true)
        activePickups.removeAll(keepingCapacity: true)
        accumulator = 0; nextId = 0
        powerUpCursor = Tuning.powerUpFirstAt; powerUpIndex = 0
    }

    // MARK: - Driving

    /// Real-time entry point for the renderer: consumes wall-clock dt in fixed steps.
    func advance(realDt: Double) {
        // A NaN/inf/negative dt (suspend hiccups, clock jumps) must never reach the accumulator:
        // `min(NaN, 0.1)` is NaN, which then sticks and bricks the run.
        guard realDt.isFinite, realDt > 0 else { return }
        accumulator += min(realDt, 0.1)
        while accumulator >= Tuning.tickDt {
            tick(Tuning.tickDt)
            accumulator -= Tuning.tickDt
        }
        rebuildSnapshot()
    }

    /// One fixed simulation step. Internal so tests can drive exact step counts deterministically.
    func tick(_ dt: Double) {
        stepSpeedAndDistance(dt)
        stepWorld(dt)
        if mode == .play { spawn() }
        stepPlayer(dt)
        stepWarden(dt)   // after the player has moved: a beam resolves against where the body IS
        // BEFORE `stepObstacles`, and that ordering is the whole reliability of the verb: a wall the
        // shockwave reaches on this tick must be gone before the collision pass looks for it, or a
        // blast fired in time would still kill you. At `blastFrontSpeed` the front covers 1.25 m per
        // tick, so anything inside the kill band when you fire is cleared on the very next step.
        stepBlast(dt)
        stepObstacles(dt)
        stepGems(dt)
        stepPickups(dt)
        if magnetT > 0 { magnetT = max(0, magnetT - dt) }
        if doublerT > 0 { doublerT = max(0, doublerT - dt) }
        if chronoT > 0 {
            chronoT = max(0, chronoT - dt)
            if chronoT == 0 { emit(.chronoEnded) }   // edge, not level — audio keys off it
        }
        if boostT > 0 {
            boostT = max(0, boostT - dt)
            if boostT == 0 { emit(.boostEnded) }     // edge — renderer/audio restore on it
        }
        if superSneakersT > 0 {
            superSneakersT = max(0, superSneakersT - dt)
            if superSneakersT == 0 { emit(.sneakersEnded) }   // edge — rig glow / jump height restore
        }
        if invulnT > 0 { invulnT = max(0, invulnT - dt) }
        if stumbleT > 0 { stumbleT = max(0, stumbleT - dt) }
        // Score freezes at death: the post-death decel keeps distance climbing, but the run's
        // score must not. `die()` captures the final value; here we only advance it while playing.
        if mode == .play { score = Int(((distance - scoreOffset) * 2).rounded(.down)) + bonus }
    }

    // MARK: - Input intents (called between ticks on the main actor)

    func changeLane(_ dir: Int) {
        guard mode == .play, dir != 0 else { return }
        let n = clampI(laneIndex + dir, 0, 2)
        if n != laneIndex { laneIndex = n; emit(.laneChanged(x: px)) }
    }

    func jump() {
        guard mode == .play else { return }
        if grounded {
            grounded = false; vy = launchVelocity; slideT = 0; sy = Tuning.airStretchY
            emit(.jumped(x: px))
        } else {
            jumpBuf = Tuning.jumpBuffer   // buffered: fires on landing
        }
    }

    /// **THE BLAST (v2.2)** — the game's first offensive verb, fired by a double tap.
    ///
    /// Spends `Tuning.blastCost` of the charge bank and launches a shockwave that destroys every
    /// destructible obstacle inside `Tuning.blastRange` ahead. Returns false (and costs nothing) when
    /// the bank is short, so the caller can fall through to a jump and the verb can never eat an
    /// input.
    ///
    /// **The chasm is immune, and that is a rule rather than an omission**: you cannot knock down a
    /// hole. It is the same carve-out the stumble already makes (`Collisions.grazes` returns false
    /// for `.chasm`) and for the same reason — the chasm's answer is timing, and neither of the
    /// game's two rescues is allowed to become "the chasm has a second answer".
    ///
    /// Consumes NO rng and touches no spawn state, exactly like `jump()` / `slide()` / the four
    /// deploy verbs, so the seeded stream stays byte-identical and no `layoutVersion` bump is owed.
    /// **A blast with nothing to hit is refused rather than wasted.** Without this, a reflexive
    /// double tap on empty track — or, worse, anywhere inside a Warden arena, which `Warden.suppresses`
    /// deliberately sweeps clear of obstacles — silently burns a third of the bank for no effect and
    /// gives the player no way to learn that it did. Refusing costs them nothing: `handleGesture`
    /// falls through to the jump, which is exactly what a single tap would have done.
    private var hasBlastTarget: Bool {
        let limit = distance + Tuning.blastRange
        let floor = distance - Tuning.obstacleZHalf
        for o in activeObstacles where o.kind.isBlastable && o.d > floor && o.d <= limit { return true }
        return false
    }

    @discardableResult
    func blast() -> Bool {
        guard mode == .play, wardenCharge >= Tuning.blastCost, hasBlastTarget else { return false }
        wardenCharge = max(0, wardenCharge - Tuning.blastCost)
        blastWave = BlastWave(startD: distance - Tuning.obstacleZHalf,
                              frontD: distance - Tuning.obstacleZHalf,
                              limitD: distance + Tuning.blastRange)
        blastsFired += 1
        emit(.blastFired(x: px, y: jumpY, chargeLeft: wardenCharge))
        return true
    }

    /// Manually deploy a banked slow-mo — the player-triggered power-up. Same effect as the chrono
    /// track pickup, fired on demand from the HUD button. Returns true only if it actually started
    /// (in play, and one isn't already running — no stack/refresh abuse). Consumes NO rng (it's
    /// input-driven like jump/slide), so the seeded sim and the solvability bot are untouched.
    @discardableResult
    func activateSlowMo() -> Bool {
        guard mode == .play, chronoT <= 0 else { return false }
        chronoT = Tuning.chronoDuration
        emit(.pickup(kind: .chrono, x: px, y: jumpY))
        return true
    }

    /// Pre-run "Head Start" consumable: launch the run with a multi-second Overdrive boost — a
    /// momentum head start, not a score grant. RNG-free (input-driven like activateSlowMo) and
    /// leaderboard-safe (it never sets `usedCheckpoint`), so the seeded sim and bot are untouched.
    /// Returns true only if it actually armed (in play).
    @discardableResult
    func activateHeadStart() -> Bool {
        guard mode == .play else { return false }
        boostT = Tuning.headStartBoostDuration
        emit(.boostStarted(x: px))
        return true
    }

    /// Manually deploy a banked SHIELD on demand (sibling of activateSlowMo). RNG-free; refuses if a
    /// shield is already held (no waste). Same one-hit shield the road pickup grants.
    @discardableResult
    func deployShield() -> Bool {
        guard mode == .play, !shield else { return false }
        shield = true
        emit(.pickup(kind: .shield, x: px, y: jumpY))
        return true
    }

    /// Manually deploy a banked "Speed Up" — a multi-second Overdrive burst on demand (sibling of
    /// activateSlowMo). RNG-free + input-driven, so the seeded sim and the bot are untouched. Returns
    /// true only if it started (in play, none already running — no stack/refresh abuse).
    @discardableResult
    func deployOverdrive() -> Bool {
        guard mode == .play, boostT <= 0 else { return false }
        boostT = Tuning.speedUpDeployDuration
        emit(.boostStarted(x: px))
        return true
    }

    func slide() {
        guard mode == .play else { return }
        // `.slid` is EDGE-triggered (v1.8). Re-arming is called every tick by the Autopilot, and
        // `.slid` drives both a one-shot SFX and the `slidesThisRun` mission counter — so emitting
        // per call meant 120 overlapping slide sounds a second, and a slide stat that counted ticks
        // rather than slides, in every autoplay/demo run. The re-arm itself is unchanged: holding a
        // slide still works exactly as before, it just stops re-announcing itself.
        let wasSliding = slideT > 0
        slideT = Tuning.slideDuration
        sy = Tuning.slideScaleY               // snap to the low slide profile immediately (responsive +
        if !grounded { vy = Tuning.slamVy }   // avoids the mid-lerp window where a bar still clips you)
        if !wasSliding { emit(.slid(x: px)) }
    }

    // MARK: - Steps

    private func stepSpeedAndDistance(_ dt: Double) {
        switch mode {
        case .over:
            speed = max(0, speed - dt * Tuning.overDecel)
        case .play:
            let target = min(Tuning.speedCap, Tuning.speedStart + distance * Tuning.speedRamp)
            speed = lerp(speed, target, dt * Tuning.speedLerp)
        case .menu:
            speed = lerp(speed, Tuning.menuSpeed, dt * Tuning.speedLerp)
        }
        distance += effectiveSpeed * dt   // chrono slows the world; the ramp above is untouched
    }

    private func stepWorld(_ dt: Double) {
        if worldBlend < 1 { worldBlend = min(1, worldBlend + dt * Tuning.worldBlendRate) }
        guard mode == .play else { return }
        let wn = Int((distance / Tuning.worldLength).rounded(.down))
        let fc = Tuning.worldFamilyCount
        let wi = ((wn % fc) + fc) % fc
        if wn > maxWorld {
            maxWorld = wn
            if wi != worldTo { worldFrom = worldTo; worldTo = wi; worldBlend = 0 }
            emit(.worldChanged(index: wi, ordinal: wn))
        }
        world = wi
    }

    private func spawn() {
        spawner.fill(to: distance + Tuning.spawnHorizon, dist: distance, rng: &rng) { [weak self] cmd in
            self?.apply(cmd)
        }
        // Guaranteed power-up cadence (v1.6) — runs AFTER fill, so the patterns up to the horizon are
        // already placed and `freeLaneNear` sees them (no overlap; both cursors advance past the
        // horizon together so a later pattern can't land on an emitted pickup). Zero RNG.
        let horizon = distance + Tuning.spawnHorizon
        while powerUpCursor < horizon {
            if let lane = freeLaneNear(powerUpCursor) {
                apply(cadenceCommand(powerUpIndex, d: powerUpCursor, lane: lane))
                powerUpIndex += 1
            }
            powerUpCursor += Tuning.powerUpCadence
        }
    }

    /// A lane with no obstacle within `cadenceClearance` of `d` (prefers centre). Full-span/sweeping
    /// obstacles (bar/splitBar/movingTall) near the mark block every lane → returns nil (skip). Pure
    /// of the obstacle set, which is deterministic from the seed — so the cadence stays deterministic.
    private func freeLaneNear(_ d: Double) -> Int? {
        for lane in [1, 0, 2] {
            var blocked = false
            for o in activeObstacles {
                // The chasm is the one obstacle with an extent, so its clearance is measured from
                // its rim rather than its centre — a cadence pickup dropped inside the void would
                // hang at y 1.0 over nothing and be uncollectable.
                let margin = Tuning.cadenceClearance + (o.kind == .chasm ? Tuning.chasmHalfLength : 0)
                guard abs(o.d - d) <= margin else { continue }
                switch o.kind {
                case .bar, .splitBar, .movingTall, .chasm, .hangingBar: blocked = true
                case .tall, .low: if o.lane == lane { blocked = true }
                default: break
                }
                if blocked { break }
            }
            if !blocked { return lane }
        }
        return nil
    }

    /// The cadence's power-up for `index`, cycling through all five kinds so the player meets each.
    private func cadenceCommand(_ index: Int, d: Double, lane: Int) -> SpawnCmd {
        switch ((index % 5) + 5) % 5 {
        case 0:  return .shield(d: d, lane: lane)
        case 1:  return .magnet(d: d, lane: lane)
        case 2:  return .doubler(d: d, lane: lane)
        case 3:  return .chrono(d: d, lane: lane)
        default: return .superSneakers(d: d, lane: lane)
        }
    }

    /// Drive the Warden encounter (v1.9).
    ///
    /// Arming is a pure function of distance, so a checkpoint run that starts mid-arena still meets
    /// its Warden instead of coasting through an empty one — and no encounter can re-arm behind the
    /// player. The encounter draws only from its own derived stream, so nothing here perturbs the
    /// seeded spawn stream (iron rule 2).
    private func stepWarden(_ dt: Double) {
        guard mode == .play else { return }
        if warden == nil, let w = Warden.armableWorld(forDistance: distance), w != wardenWorldDone {
            warden = WardenEncounter(world: w, runSeed: runSeed)
            wardensMetThisRun += 1
            emit(.wardenArrived(world: w))
        }
        guard var w = warden else { return }
        let ev = w.step(dt, playerLane: laneIndex)
        warden = w

        // **A throw is a spawn, not a strike.** The encounter names a shape and a lead; the core
        // turns that into real obstacles on the real deck through `applyThrown`, which is the same
        // `apply` path the spawner uses minus the arena filter and the pool caps. Nothing here
        // consumes rng from the run's stream (iron rule 2) — the only draw is the open lane, and
        // that comes from the encounter's own derived generator.
        if ev.threw {
            throwHazard(band: ev.throwBand, lead: ev.throwLead, lane: ev.throwLane)
            emit(.wardenThrew(band: ev.throwBand, lead: ev.throwLead))
        }

        if ev.brokeOff { emit(.wardenBrokeOff) }
        if ev.finished {
            wardenWorldDone = w.world
            warden = nil
            // The boss takes its toys. A thrown hazard that outlived the fight would sit on the deck
            // as a wall that cannot kill you — a free pass through a stretch of act-two track — and
            // it would look identical to one that can. `WardenEncounter.step` already refuses to
            // launch anything that cannot arrive in time, so this only ever sweeps up the tail.
            activeObstacles.removeAll { $0.fromWarden }
        }
    }

    /// Turn one throw into real obstacles on the real deck.
    ///
    /// The mapping is one shape to one demand, and it is the same trichotomy S-009 established —
    /// the shapes were never the problem, the way they were DRAWN was. Each of these is a mesh the
    /// player has been reading for 2,400 m, killed by a rule they already know:
    ///
    ///   `.lance`   → two `tall` walls with one lane open → change lane
    ///   `.floor`   → a `chasm` blown in the deck          → jump (with a two-sided window)
    ///   `.curtain` → a `hangingBar`                       → slide, and only slide
    private func throwHazard(band: WardenBand, lead: Double, lane openLane: Int) {
        let d = distance + lead
        // Every member of one throw closes at the SAME rate, which is what keeps a lance's two walls
        // bit-identical in `d` — `hasUnpassedThrownTwin` and the lance sweep both identify a pair by
        // exact `Double` equality (see `advanceClosingHazards`).
        let close = Tuning.wardenCloseSpeed(rank: warden?.rank ?? 1)
        switch band {
        case .lance:
            for lane in 0..<3 where lane != openLane { applyThrown(.tall(d: d, lane: lane), close: close) }
        case .floor:
            applyThrown(.chasm(d: d), close: close)
        case .curtain:
            applyThrown(.hangingBar(d: d), close: close)
        case .shot:
            // Fired FASTER than anything else the craft throws. A shot is the rank ladder's reaction
            // test, and the extra closing speed is where the pressure comes from — the lead is the
            // same, so the window is `wardenShotCloseBonus` shorter than the wall thrown beside it.
            applyThrown(.bolt(d: d, lane: openLane), close: close + Tuning.wardenShotCloseBonus)
        }
    }

    /// The player answered a thrown hazard — dodged it clean, or blasted it. Both are worth one hit.
    private func registerWardenAnswer() {
        guard var w = warden, let dmg = w.registerAnswer() else { return }
        warden = w
        switch dmg {
        case .armourChipped: emit(.wardenCoreHit(hits: w.coreHits))
        case .armourBroke:   emit(.wardenShieldBroke)
        case .coreHit:       emit(.wardenCoreHit(hits: w.coreHits))
        case .killed:
            wardensDefeatedThisRun += 1
            bonus += Tuning.wardenScoreBonus * mult
            // Currency only, like a ring — never streak (rule 9). Banked SEPARATELY from `gemCount`
            // because `gemCount` is also the run's GEM stat and feeds gem missions and per-gem XP.
            bountyCoins += Tuning.wardenCoinBounty
            emit(.wardenDefeated(world: w.world, bounty: Tuning.wardenCoinBounty))
        }
    }

    private func stepPlayer(_ dt: Double) {
        let tx = Tuning.laneX[laneIndex]
        px = lerp(px, tx, min(1, dt * Tuning.laneLerpRate))
        bankZ = lerp(bankZ, (tx - px) * Tuning.bankRate, min(1, dt * Tuning.bankLerp))

        if jumpBuf > 0 { jumpBuf -= dt }

        if !grounded {
            vy -= Tuning.gravity * dt
            jumpY += vy * dt
            if jumpY <= 0 {
                jumpY = 0; grounded = true; vy = 0; sy = Tuning.landSquashY
                emit(.landed(x: px))
                if jumpBuf > 0 {
                    jumpBuf = 0; grounded = false; vy = launchVelocity; sy = Tuning.airStretchY
                    emit(.jumped(x: px))
                }
            }
        }

        if slideT > 0 { slideT -= dt }
        let targetSy = slideT > 0 ? Tuning.slideScaleY : (grounded ? 1.0 : Tuning.airHoldY)
        sy = lerp(sy, targetSy, min(1, dt * Tuning.slideLerp))
    }

    private func obstacleX(_ e: CoreEntity) -> Double {
        switch e.kind {
        case .bar, .splitBar, .chasm, .hangingBar: return 0   // full-span: `lane` is -1, never index `laneX`
        case .movingTall: return sin((distance - e.d) * Tuning.movingWallFreq + e.phase) * Tuning.movingWallAmplitude
        default: return Tuning.laneX[e.lane]
        }
    }

    /// Advance the shockwave and shatter what it reaches.
    ///
    /// The front sweeps a half-open interval `(startD, frontD]` exactly once, so an obstacle can
    /// never be destroyed twice and one already behind the player when the trigger was pulled is
    /// never touched. The wave dies the tick it reaches `limitD`, whether or not it hit anything.
    private func stepBlast(_ dt: Double) {
        // `.over` keeps ticking for the death decel, and a wave left travelling through it would go
        // on demolishing the track behind a dead player — visible in the game-over camera drift.
        guard mode == .play else { blastWave = nil; return }
        guard var w = blastWave else { return }
        w.frontD = min(w.limitD, w.frontD + Tuning.blastFrontSpeed * dt)

        var i = 0
        while i < activeObstacles.count {
            let e = activeObstacles[i]
            guard e.kind.isBlastable, e.d > w.startD, e.d <= w.frontD else { i += 1; continue }
            activeObstacles.swapAt(i, activeObstacles.count - 1)
            activeObstacles.removeLast()
            obstaclesShattered += 1
            if mode == .play { bonus += Tuning.blastScorePerObstacle * mult }
            // Blasting a thrown hazard damages the Warden exactly as dodging it does. The
            // equivalence is the design: a dodge is free and a blast costs a round, so dodging is
            // always the better answer and the blast is insurance — never a shortcut.
            if e.fromWarden && (e.kind != .tall || !hasUnpassedThrownTwin(e)) { registerWardenAnswer() }
            emit(.obstacleShattered(kind: e.kind, x: obstacleX(e), y: e.baseY, z: distance - e.d))
        }

        blastWave = w.frontD >= w.limitD ? nil : w
    }

    /// Advance everything travelling toward the player under its own power (v2.3).
    ///
    /// One pass over the whole pool BEFORE the collision loop, deliberately, for two reasons.
    ///
    /// 1. **The exact-equality invariants survive.** `hasUnpassedThrownTwin` and the lance sweep in
    ///    `stepObstacles` both identify a throw's members by `o.d == e.d` on raw `Double`s. A lance's
    ///    two walls are launched at one `d` with one `closeSpeed`, and this loop subtracts the same
    ///    product from both in the same pass — bit-identical arithmetic, so they stay equal forever.
    ///    Advancing them inside the collision loop instead would interleave the decrement with
    ///    removals and make that far harder to see.
    /// 2. Every obstacle has moved before ANY of them is tested, so a tick never resolves one hazard
    ///    against a stale position and its twin against a fresh one.
    ///
    /// **Chrono scales it, boost does not, and that asymmetry is the point.** Slow-mo is the promise
    /// that the world slows while the player's reflexes do not, so a thrown hazard has to slow with
    /// the world or the power-up would quietly make the boss HARDER. A boost is the opposite: the
    /// player chose to close the gap faster, and a hazard's own ground speed is none of their
    /// business — the two velocities simply add.
    private func advanceClosingHazards(_ dt: Double) {
        let scale = hazardCloseScale
        for i in activeObstacles.indices where activeObstacles[i].closeSpeed > 0 {
            activeObstacles[i].d -= activeObstacles[i].closeSpeed * scale * dt
        }
    }

    private func stepObstacles(_ dt: Double) {
        advanceClosingHazards(dt)
        let pb = Collisions.playerBounds(jumpY: jumpY, scaleY: sy)
        var i = 0
        while i < activeObstacles.count {
            let e = activeObstacles[i]
            let z = distance - e.d
            if z > Tuning.recycleObstacleZ {
                activeObstacles.swapAt(i, activeObstacles.count - 1)
                activeObstacles.removeLast()
                continue
            }
            let ox = obstacleX(e)

            // Every obstacle but the chasm is a plane, lethal within `obstacleZHalf`. The chasm owns
            // a RANGE of track, so the outer gate widens for it — otherwise the gate would veto the
            // predicate and an 8 u hole would only be fatal in its middle 1.9 u.
            let zHalf = e.kind == .chasm ? Tuning.chasmHalfLength : Tuning.obstacleZHalf
            if mode == .play && invulnT <= 0 && abs(z) < zHalf {
                let hit: Bool
                switch e.kind {
                case .bar: hit = Collisions.barHit(playerTop: pb.top, playerBottom: pb.bottom, z: z)
                case .hangingBar: hit = Collisions.hangingBarHit(playerTop: pb.top, playerBottom: pb.bottom, z: z)
                case .chasm: hit = Collisions.chasmHit(playerY: jumpY, z: z)
                case .splitBar: hit = Collisions.splitBarHit(playerTop: pb.top, playerBottom: pb.bottom, playerX: px, openLane: e.lane, z: z)
                case .low: hit = Collisions.lowHit(playerBottom: pb.bottom, playerX: px, obstacleX: ox, z: z)
                case .tall, .movingTall: hit = Collisions.tallHit(playerX: px, obstacleX: ox, z: z,
                                                                   playerBottom: pb.bottom, canVault: superSneakersT > 0)
                // A shot resolves exactly like a wall in its lane, and deliberately so: the player
                // already knows that rule, and a boss is the wrong place to teach a new collision.
                // It is NOT vaultable — Super Sneakers is a jump buff, and a shot fired at your
                // chest is not answered by being slightly higher.
                case .bolt: hit = Collisions.tallHit(playerX: px, obstacleX: ox, z: z)
                default: hit = false
                }
                if hit {
                    // **The Warden branch is tested BEFORE the shield, and the order is the fix**
                    // (v2.3). A shield exists to absorb something that would otherwise END the run,
                    // and inside an arena nothing can (D-028) — so letting it fire here was wrong
                    // three separate ways at once. It spent the player's one rescue on a survivable
                    // stagger; it deleted the throw WITHOUT paying a Warden answer, so holding a
                    // shield made the fight strictly longer; and it opened `invulnDuration` (0.4 s)
                    // of invulnerability during which the next hazard crossed the player plane
                    // un-hit and collected a FREE answer from the `passed` branch below, which sits
                    // outside the `invulnT <= 0` gate. Shields are deliberately left in arenas as
                    // ammunition for what comes after the fight; they are not part of it.
                    if e.fromWarden {
                        // **A WARDEN CAN NEVER KILL YOU (v2.2, D-028).** Not "forgives once", not
                        // "stumbles then kills" — never. This is the owner's instruction and it is
                        // the model every shipped runner boss uses: the boss is an OPPORTUNITY
                        // layer, and failing it costs the reward, not the run.
                        //
                        // v2.1 was the inverse. Two landed beams 1.20 s apart ended the run, and
                        // branch 3 below could be skipped outright — it required `stumbleT <= 0`
                        // while `stumbleT` runs 0.90 s and `stumbleGrace` only 0.15 s, so any wall
                        // clip in the 60 m before the arena mouth made the FIRST Warden hit lethal.
                        //
                        // What it costs instead is everything the player can afford to lose: the
                        // multiplier and the tempo (the stumble), one blast round, and — the term
                        // that actually decides the fight — the answer this hazard would have been
                        // worth. Miss enough and the clock runs out with the Warden alive.
                        stumble(fromWarden: true)
                        wardenCharge = max(0, wardenCharge - Tuning.wardenHitChargeLoss)
                        // The WHOLE throw goes, not just the wall that touched you. A `.lance` is a
                        // pair at one `d`, and leaving the partner standing would let it cross the
                        // player plane un-hit a few ticks later and pay a Warden answer for the
                        // attack that just landed on you — credit for failing.
                        let throwD = e.d
                        activeObstacles.removeAll { $0.fromWarden && $0.d == throwD }
                        continue
                    } else if shield {
                        // The grace window outlives the kill band: patterns 3/7/9 pair talls at the
                        // same `d`, and the partner wall stays lethal for several more ticks.
                        shield = false; invulnT = Tuning.invulnDuration; streak = 0; mult = 1
                        flowStreak = 0   // taking a hit (even absorbed) breaks the flow
                        emit(.shieldAbsorbed(x: px))
                        activeObstacles.swapAt(i, activeObstacles.count - 1)
                        activeObstacles.removeLast()
                        continue
                    } else if stumbleT <= 0,
                              Collisions.grazes(kind: e.kind, playerX: px, obstacleX: ox,
                                                playerTop: pb.top, playerBottom: pb.bottom,
                                                openLane: e.lane) {
                        // Nearly made it, and not already recovering from the last one.
                        stumble(fromWarden: false)
                        // The wall MUST go. Left alive it would re-hit on the next tick, and — worse
                        // — its near-miss scorer fires at the exit plane, where `dx` has grown while
                        // the player kept escaping: the wall they crashed into would pay them CLOSE,
                        // +40 × mult, style coins and a flow pip, moments after staggering them.
                        activeObstacles.swapAt(i, activeObstacles.count - 1)
                        activeObstacles.removeLast()
                        continue
                    } else {
                        die()
                        // fall through: subsequent logic is mode-guarded; entity stays.
                    }
                }
            }

            // near-miss bonuses, scored exactly once as the obstacle crosses the player plane
            if !activeObstacles[i].passed && z >= Tuning.obstacleZHalf {
                activeObstacles[i].passed = true
                if mode == .play {
                    // A thrown hazard that reaches this line was ANSWERED — it got past without
                    // touching anyone, because every contact above removes it. That is one hit on
                    // the Warden. A `.lance` throws TWO walls, so only the pair's second wall
                    // scores; `registerWardenAnswer` is idempotent per pair because the first wall's
                    // partner is still on the deck when it fires. (See the lane guard below.)
                    if e.fromWarden && (e.kind != .tall || !hasUnpassedThrownTwin(e)) {
                        registerWardenAnswer()
                    }
                    switch e.kind {
                    case .tall, .movingTall:
                        let dx = abs(px - ox)
                        if Collisions.closeNearMiss(dx: dx) {
                            bonus += Tuning.nearMissBonus * mult
                            emit(.nearMiss(kind: .close, x: px))
                            registerFlowNearMiss()
                        }
                    case .bar, .hangingBar:
                        if slideT > 0 {
                            bonus += Tuning.nearMissBonus * mult
                            emit(.nearMiss(kind: .slick, x: px))
                            registerFlowNearMiss()
                        }
                    default: break
                    }
                }
            }
            i += 1
        }
    }

    /// Whether `e`'s lance partner is still on the deck and still unscored.
    ///
    /// A `.lance` throw places TWO walls at the same `d`, and both cross the player plane on the
    /// same tick — so without this the Warden would take two hits for one dodge and every fight
    /// would be half as long as its own arithmetic says. The pair is identified by distance rather
    /// than by an id: they are placed together at exactly the same `d` and nothing else the Warden
    /// throws is a `.tall`.
    private func hasUnpassedThrownTwin(_ e: CoreEntity) -> Bool {
        for o in activeObstacles
        where o.fromWarden && o.kind == .tall && o.id != e.id && !o.passed && o.d == e.d {
            return true
        }
        return false
    }

    /// Flow surge (v1.3): every `flowPerSurge`-th CLOSE/SLICK without a hit pays a score bonus and
    /// sprays a gem fountain into the player's lane. The fountain derives purely from current state
    /// (laneIndex + distance) — it consumes ZERO RNG, so the seeded spawn stream stays byte-identical
    /// whether or not surges fire (iron rule 2; pinned by `FlowTests`).
    private func registerFlowNearMiss() {
        flowStreak += 1
        guard flowStreak >= Tuning.flowPerSurge else { return }
        flowStreak = 0   // §C.1: "streak since last surge/reset" — the surge consumes the streak
        flowSurges += 1
        bonus += Tuning.flowSurgeScore * mult
        for i in 0..<Tuning.fountainGems {
            apply(.gem(d: distance + Tuning.fountainLead + Double(i) * Tuning.fountainSpacing,
                       lane: laneIndex, y: 0.8))
        }
        emit(.flowSurge(level: flowSurges, x: px))
    }

    private func stepGems(_ dt: Double) {
        let pcy = Collisions.playerCenterY(jumpY: jumpY, scaleY: sy)
        var i = 0
        while i < activeGems.count {
            var g = activeGems[i]
            let z = distance - g.d
            // Magnet only pulls during live play; `fading` is sticky once set so the renderer
            // never sees a grabbed gem pop back to full opacity when the pull window releases it.
            if mode == .play && magnetT > 0 && Collisions.magnetActive(z: z) {
                g.x = lerp(g.x, px, min(1, dt * Tuning.magnetGemXRate))
                g.baseY = lerp(g.baseY, pcy, min(1, dt * Tuning.magnetGemYRate))
                g.fading = true
            }
            if z > Tuning.recycleCollectibleZ {
                activeGems.swapAt(i, activeGems.count - 1)
                activeGems.removeLast()
                continue
            }
            if mode == .play && Collisions.gemPickup(playerCenterY: pcy, playerX: px, gemX: g.x, gemBaseY: g.baseY, z: z) {
                activeGems.swapAt(i, activeGems.count - 1)
                activeGems.removeLast()
                // Doubler doubles CURRENCY only (gemCount feeds the coin payout); streak/multiplier
                // remain skill stats and always count single. The overdrive boost adds a flat
                // +boostGemBonus coin per gem on top (stacks with the doubler: 2+1).
                gemCount += (doublerT > 0 ? 2 : 1) + (boostT > 0 ? Tuning.boostGemBonus : 0)
                // Charge counts GEMS, never currency: the doubler and the boost multiply the coin
                // payout, and letting them multiply Warden damage too would make a consumable the
                // way to win a fight the design says only dodging can win.
                wardenCharge = min(1, wardenCharge + Tuning.chargePerGem)
                streak += 1
                bestStreak = max(bestStreak, streak)
                mult = clampI(1 + streak / Tuning.streakPerMult, 1, Tuning.multCap)
                bonus += Tuning.gemBaseScore * mult
                emit(.gemCollected(x: g.x, y: g.baseY, streak: streak))
                continue
            }
            activeGems[i] = g
            i += 1
        }
    }

    private func stepPickups(_ dt: Double) {
        let pcy = Collisions.playerCenterY(jumpY: jumpY, scaleY: sy)
        var i = 0
        while i < activePickups.count {
            let p = activePickups[i]
            let z = distance - p.d
            if z > Tuning.recycleCollectibleZ {
                activePickups.swapAt(i, activePickups.count - 1)
                activePickups.removeLast()
                continue
            }
            let pxw = Tuning.laneX[p.lane]

            // Rings & pads (v1.3) have bespoke trigger geometry — branch BEFORE the generic window
            // so `pickupHit` can never consume them (a mid-jump body overlap with a ring at apex
            // height is a THREAD, not a touch-grab). Both are non-lethal by construction.
            switch p.kind {
            case .ring:
                if mode == .play {
                    let (pass, perfect) = Collisions.ringPass(playerCenterY: pcy, playerX: px,
                                                              ringX: pxw, ringY: p.baseY, z: z)
                    if pass {
                        activePickups.swapAt(i, activePickups.count - 1)
                        activePickups.removeLast()
                        // Ring payouts are score + CURRENCY only — streak/mult stay gem-pickup
                        // skill stats (iron rule 9; the doubler pays gemCount the same way).
                        bonus += Tuning.ringScore * mult
                        gemCount += perfect ? Tuning.ringPerfectCoins : Tuning.ringCoins
                        emit(.ringPassed(x: pxw, y: p.baseY, perfect: perfect))
                        continue
                    }
                }
                i += 1
                continue
            case .boostPad:
                if mode == .play && Collisions.boostPadHit(playerX: px, padX: pxw, z: z, grounded: grounded) {
                    activePickups.swapAt(i, activePickups.count - 1)
                    activePickups.removeLast()
                    boostT = Tuning.boostDuration   // a second pad simply refreshes the timer
                    bonus += Tuning.boostScoreBonus * mult
                    emit(.boostStarted(x: pxw))
                    continue
                }
                i += 1
                continue
            default:
                break
            }

            if mode == .play && Collisions.pickupHit(playerCenterY: pcy, playerX: px, pickupX: pxw, pickupY: p.baseY, z: z) {
                activePickups.swapAt(i, activePickups.count - 1)
                activePickups.removeLast()
                switch p.kind {
                case .shield:
                    shield = true
                    emit(.pickup(kind: .shield, x: pxw, y: p.baseY))
                case .magnet:
                    magnetT = Tuning.magnetDuration
                    emit(.pickup(kind: .magnet, x: pxw, y: p.baseY))
                case .doubler:
                    doublerT = Tuning.doublerDuration
                    emit(.pickup(kind: .doubler, x: pxw, y: p.baseY))
                case .chrono:
                    chronoT = Tuning.chronoDuration
                    emit(.pickup(kind: .chrono, x: pxw, y: p.baseY))
                case .superSneakers:
                    superSneakersT = Tuning.superSneakersDuration   // refresh, no stack — like the others
                    emit(.pickup(kind: .superSneakers, x: pxw, y: p.baseY))
                default:
                    break
                }
                continue
            }
            i += 1
        }
    }

    /// Survive a contact (v2.0).
    ///
    /// The costs are deliberately asymmetric. The **multiplier reset is the punishment** — it is the
    /// owner's own word, it is the one existing code path (the shield absorb runs these three lines),
    /// and until now `mult` could only ever rise in a clean run, so ×5 had no stakes at all. The
    /// speed dip is what makes it *read* as a stagger; it costs about 13 points.
    ///
    /// What it deliberately does NOT take: `wardenCharge` (520 gems of banking, confiscated for one
    /// wall clip, would punish twice and be nearly invisible), `boostT` and the earned consumable
    /// timers (decree 5 — advertised bonuses are always delivered), and `bestStreak`, which is a
    /// high-water mark and is what keeps `run.mult5` and every multiplier mission completable.
    private func stumble(fromWarden: Bool) {
        stumbleT = Tuning.stumbleRecover
        invulnT = max(invulnT, Tuning.stumbleGrace)
        streak = 0; mult = 1; flowStreak = 0
        speed *= Tuning.stumbleSpeedFactor
        stumbles += 1
        emit(.stumbled(x: px, fromWarden: fromWarden))
    }

    private func die() {
        score = Int(((distance - scoreOffset) * 2).rounded(.down)) + bonus   // final, frozen score
        deathDistance = distance
        mode = .over
        streak = 0; mult = 1; flowStreak = 0   // death breaks the flow (boostT decays naturally)
        if score > best { best = score }
        emit(.died(x: px))
    }

    /// Debug-only: force an immediate death (used by the `PR_DEMO` screenshot flow).
    func debugForceDie() { if mode == .play { die() } }

    /// Debug/QA hook (`PR_SNEAKERS`): arm Super Sneakers without a track pickup so the active rig
    /// glow + HUD ring can be screenshotted. Consumes no RNG; play-gated like the real activation.
    func debugActivateSuperSneakers() { if mode == .play { superSneakersT = Tuning.superSneakersDuration } }

    /// Debug/QA hook (`PR_WARDEN`): fill the charge bank without collecting ~520 gems first, so an
    /// encounter can be inspected on the simulator. Consumes no RNG; play-gated like every other
    /// debug activation, so it can never affect a seeded run or the solvability bot.
    func debugFillWardenCharge() { if mode == .play { wardenCharge = 1 } }

    /// Debug/QA hook (`PR_STUMBLE`): stagger the player on demand, so the vulnerability shell, the
    /// HUD's EXPOSED chip and the impact FX can be screenshotted without hand-flying a half-hit at
    /// 33 m/s. The Autopilot plays perfectly and never enters a graze band, so an autoplay capture
    /// can never produce one on its own. Consumes no RNG and is play-gated like every other debug
    /// activation, so it can never reach a seeded run or the solvability bot.
    func debugStumble() { if mode == .play { stumble(fromWarden: false) } }

    /// Test/diagnostic hook: wipe every live entity and park the spawner so hand-built scenarios
    /// (`debugSpawn`) run with zero procedural interference.
    func debugClearTrack() {
        activeObstacles.removeAll(keepingCapacity: true)
        activeGems.removeAll(keepingCapacity: true)
        activePickups.removeAll(keepingCapacity: true)
        blastWave = nil   // else a wave from the previous scenario shatters the next one's props
        spawner.cursor = .greatestFiniteMagnitude
    }

    /// Test/diagnostic hook: place a single spawn command directly (same path as the spawner).
    func debugSpawn(_ cmd: SpawnCmd) { apply(cmd) }

    /// Continue after death (the UI charges coins). Clears the field, re-centres the player, grants a
    /// one-hit shield, and respawns well ahead so the continue isn't an instant re-death.
    func revive() {
        guard mode == .over else { return }
        revivesUsed += 1
        mode = .play
        // Distance kept integrating during the death decel; fold that drift into the offset so the
        // score (and coin payout) resumes exactly where it froze — no free post-death points.
        scoreOffset += distance - deathDistance
        // Keep the player's LANE (don't snap to centre) so a continue reads as resuming where you
        // were, not a restart — the board is cleared below, so the held lane is safe (v1.6).
        jumpY = 0; vy = 0; grounded = true; slideT = 0; sy = 1
        shield = true
        // A continue resets only what could bank *free* momentum: the boost timer and the flow
        // streak. Earned consumable timers (magnet / doubler / chrono) deliberately carry over —
        // the player collected them and a paid revive should never confiscate them (decree 5:
        // advertised bonuses are always delivered). `magnetT`/`doublerT`/`chronoT` are intentionally
        // left running.
        boostT = 0; flowStreak = 0
        // A paid continue must never resume INSIDE the fatal recovery window — you would have bought
        // a run that the next wall ends for free. The counter (`stumbles`) is left standing: it is a
        // run statistic and the bot's contact detector, not a resource.
        stumbleT = 0
        // A Warden that put the player down has done its job: it breaks off rather than resuming
        // over a cleared board, and its world is marked finished so the arena can't re-arm as the
        // player runs the rest of it. The charge bank is deliberately NOT refunded — it was spent.
        if let w = warden { wardenWorldDone = w.world; warden = nil }
        speed = max(speed, Tuning.speedStart)   // paid continues resume instantly, not from the decel floor
        activeObstacles.removeAll()
        activeGems.removeAll()
        activePickups.removeAll()
        // A shockwave in flight has nothing left to travel through, and leaving it live would draw a
        // ring across a board that was cleared out from under it. The charge it cost is NOT refunded
        // — it was spent, exactly as the Warden bank is (see `wardenWorldDone` above).
        blastWave = nil
        spawner.cursor = distance + 70
        rebuildSnapshot()
    }

    // MARK: - Spawning

    private func takeId() -> Int { nextId += 1; return nextId }

    /// Closure predicate (not a `Set`) so per-spawn cap checks never allocate.
    private func obstacleCount(where matches: (EntityKind) -> Bool) -> Int {
        var n = 0
        for o in activeObstacles where matches(o.kind) { n += 1 }
        return n
    }

    private func pickupCount(_ kind: EntityKind) -> Int {
        var n = 0
        for p in activePickups where p.kind == kind { n += 1 }
        return n
    }

    /// Place a Warden's thrown hazard.
    ///
    /// Deliberately NOT `apply`, and the two differences are both load-bearing:
    ///
    /// 1. **It skips `Warden.suppresses`.** That gate exists to keep the arena clear of everything
    ///    the SPAWNER would have drawn, precisely so the Warden's own hazards are the only things on
    ///    it. Routing a throw through `apply` would have the arena filter delete the attack.
    /// 2. **It skips the pool caps.** A throw is not a procedural spawn competing for a budget; it is
    ///    the fight. Dropping one on a full pool would silently make the encounter unwinnable, and
    ///    the caps provably never bind anyway (`BlastTests.testNoObstacleCapEverBindsDuringRealPlay`).
    ///
    /// Consumes no rng and does not touch `spawner`, so a fight still cannot perturb the seeded
    /// stream (iron rule 2; pinned by `WardenTests.testAFightCanNeverPerturbTheSpawnStream`).
    private func applyThrown(_ cmd: SpawnCmd, close: Double) {
        let before = activeObstacles.count
        switch cmd {
        case let .tall(d, lane):
            activeObstacles.append(CoreEntity(id: takeId(), kind: .tall, lane: lane, d: d,
                                              x: Tuning.laneX[lane], baseY: 1.6, phase: 0,
                                              passed: false, fading: false, fromWarden: true,
                                              closeSpeed: close))
        case let .chasm(d):
            activeObstacles.append(CoreEntity(id: takeId(), kind: .chasm, lane: -1, d: d, x: 0,
                                              baseY: 0, phase: 0, passed: false, fading: false,
                                              fromWarden: true, closeSpeed: close))
        case let .hangingBar(d):
            activeObstacles.append(CoreEntity(id: takeId(), kind: .hangingBar, lane: -1, d: d, x: 0,
                                              baseY: (Tuning.hangingBarKillBottom + Tuning.hangingBarKillTop) / 2,
                                              phase: 0, passed: false, fading: false, fromWarden: true,
                                              closeSpeed: close))
        case let .bolt(d, lane):
            activeObstacles.append(CoreEntity(id: takeId(), kind: .bolt, lane: lane, d: d,
                                              x: Tuning.laneX[lane], baseY: 1.6, phase: 0,
                                              passed: false, fading: false, fromWarden: true,
                                              closeSpeed: close))
        default:
            // A Warden throws exactly three things. Anything else is a programming error, and
            // silently ignoring it would produce a fight with an attack that never arrives.
            assertionFailure("applyThrown got a command a Warden cannot throw: \(cmd)")
        }
        assert(activeObstacles.count > before || activeObstacles.count == before)
    }

    private func apply(_ cmd: SpawnCmd) {
        // A Warden arena is kept clear of obstacles so its telegraphs are the only thing to read
        // (decree 6). Filtering here rather than in the spawner is deliberate: `Spawner.fill` still
        // draws exactly the same patterns and consumes exactly the same `rng` values, so the seeded
        // stream is byte-identical to v1.8 and nothing about pattern SELECTION moves. What changes
        // is which of those spawns reach the deck — which is a layout change, hence layoutVersion 10.
        if Warden.suppresses(cmd) { return }
        switch cmd {
        case .bolt:
            // **The spawner may never place a shot.** A shot aims at the lane the player occupies
            // at the moment of launch, which no pattern can know — a "pattern-placed bolt" would be
            // a wall wearing a projectile's mesh, teaching the player that shots are readable in
            // advance. It reaches the deck only through `applyThrown`. Trapped rather than ignored,
            // for the same reason `applyThrown` traps the inverse case.
            assertionFailure("a bolt reached the spawner path; only a Warden may fire one")
        case let .low(d, lane):
            guard obstacleCount(where: { $0 == .low }) < Tuning.capLow else { return }
            activeObstacles.append(CoreEntity(id: takeId(), kind: .low, lane: lane, d: d, x: Tuning.laneX[lane], baseY: 0.425, phase: 0, passed: false, fading: false))
        case let .tall(d, lane):
            guard obstacleCount(where: { $0 == .tall || $0 == .movingTall }) < Tuning.capTall else { return }
            activeObstacles.append(CoreEntity(id: takeId(), kind: .tall, lane: lane, d: d, x: Tuning.laneX[lane], baseY: 1.6, phase: 0, passed: false, fading: false))
        case let .movingTall(d, phase):
            guard obstacleCount(where: { $0 == .tall || $0 == .movingTall }) < Tuning.capTall else { return }
            activeObstacles.append(CoreEntity(id: takeId(), kind: .movingTall, lane: 1, d: d, x: 0, baseY: 1.6, phase: phase, passed: false, fading: false))
        case let .bar(d):
            guard obstacleCount(where: { $0 == .bar }) < Tuning.capBar else { return }
            activeObstacles.append(CoreEntity(id: takeId(), kind: .bar, lane: -1, d: d, x: 0, baseY: 1.3, phase: 0, passed: false, fading: false))
        case let .splitBar(d, openLane):
            guard obstacleCount(where: { $0 == .splitBar }) < Tuning.capSplitBar else { return }
            activeObstacles.append(CoreEntity(id: takeId(), kind: .splitBar, lane: openLane, d: d, x: 0, baseY: 1.3, phase: 0, passed: false, fading: false))
        case let .gem(d, lane, y):
            guard activeGems.count < Tuning.capGem else { return }
            activeGems.append(CoreEntity(id: takeId(), kind: .gem, lane: lane, d: d, x: Tuning.laneX[lane], baseY: y, phase: 0, passed: false, fading: false))
        case let .shield(d, lane):
            guard pickupCount(.shield) < Tuning.capShield else { return }
            activePickups.append(CoreEntity(id: takeId(), kind: .shield, lane: lane, d: d, x: Tuning.laneX[lane], baseY: 1.0, phase: 0, passed: false, fading: false))
        case let .magnet(d, lane):
            guard pickupCount(.magnet) < Tuning.capMagnet else { return }
            activePickups.append(CoreEntity(id: takeId(), kind: .magnet, lane: lane, d: d, x: Tuning.laneX[lane], baseY: 1.0, phase: 0, passed: false, fading: false))
        case let .doubler(d, lane):
            guard pickupCount(.doubler) < Tuning.capDoubler else { return }
            activePickups.append(CoreEntity(id: takeId(), kind: .doubler, lane: lane, d: d, x: Tuning.laneX[lane], baseY: 1.0, phase: 0, passed: false, fading: false))
        case let .chrono(d, lane):
            guard pickupCount(.chrono) < Tuning.capChrono else { return }
            activePickups.append(CoreEntity(id: takeId(), kind: .chrono, lane: lane, d: d, x: Tuning.laneX[lane], baseY: 1.0, phase: 0, passed: false, fading: false))
        case let .superSneakers(d, lane):
            guard pickupCount(.superSneakers) < Tuning.capSuperSneakers else { return }
            activePickups.append(CoreEntity(id: takeId(), kind: .superSneakers, lane: lane, d: d, x: Tuning.laneX[lane], baseY: 1.0, phase: 0, passed: false, fading: false))
        case let .ring(d, lane, y):
            guard pickupCount(.ring) < Tuning.capRing else { return }
            activePickups.append(CoreEntity(id: takeId(), kind: .ring, lane: lane, d: d, x: Tuning.laneX[lane], baseY: y, phase: 0, passed: false, fading: false))
        case let .boostPad(d, lane):
            guard pickupCount(.boostPad) < Tuning.capBoostPad else { return }
            activePickups.append(CoreEntity(id: takeId(), kind: .boostPad, lane: lane, d: d, x: Tuning.laneX[lane], baseY: 0.05, phase: 0, passed: false, fading: false))
        case let .hangingBar(d):
            guard obstacleCount(where: { $0 == .hangingBar }) < Tuning.capHangingBar else { return }
            activeObstacles.append(CoreEntity(id: takeId(), kind: .hangingBar, lane: -1, d: d, x: 0,
                                              baseY: (Tuning.hangingBarKillBottom + Tuning.hangingBarKillTop) / 2,
                                              phase: 0, passed: false, fading: false))
        case let .chasm(d):
            // Full-span like a bar, so `lane: -1` and `x: 0` (see `obstacleX`). `baseY: 0` is the
            // deck plane it replaces — the renderer sinks the shaft below it from there.
            guard obstacleCount(where: { $0 == .chasm }) < Tuning.capChasm else { return }
            activeObstacles.append(CoreEntity(id: takeId(), kind: .chasm, lane: -1, d: d, x: 0, baseY: 0, phase: 0, passed: false, fading: false))
        }
    }

    // MARK: - Snapshot

    @ObservationIgnored private var entityScratch: [EntityState] = []

    private func rebuildSnapshot() {
        entityScratch.removeAll(keepingCapacity: true)
        entityScratch.reserveCapacity(activeObstacles.count + activeGems.count + activePickups.count)

        for e in activeObstacles {
            let z = distance - e.d
            let x = obstacleX(e)
            // `baseY` (set at spawn) is the authoritative render height for EVERY obstacle kind —
            // bar/splitBar centre 1.3, low 0.425, tall 1.6. Renderers must never hardcode these.
            entityScratch.append(EntityState(id: e.id, kind: e.kind, x: x, y: e.baseY, z: z,
                                             lane: e.lane, spin: 0, fading: false,
                                             fromWarden: e.fromWarden))
        }
        for g in activeGems {
            let z = distance - g.d
            let bob = sin((distance + g.d) * 0.6) * 0.07
            entityScratch.append(EntityState(id: g.id, kind: .gem, x: g.x, y: g.baseY + bob, z: z, lane: g.lane, spin: distance - g.d, fading: g.fading))
        }
        for p in activePickups {
            let z = distance - p.d
            entityScratch.append(EntityState(id: p.id, kind: p.kind, x: Tuning.laneX[p.lane], y: p.baseY, z: z, lane: p.lane, spin: distance - p.d, fading: false))
        }

        snapshot = GameSnapshot(
            mode: mode, distance: distance, traveledDistance: distance - scoreOffset,
            speed: effectiveSpeed, rampSpeed: speed,
            playerX: px, playerY: jumpY, playerScaleY: sy, bankZ: bankZ,
            worldFrom: worldFrom, worldTo: worldTo, worldBlend: worldBlend,
            worldOrdinal: maxWorld,   // flips on the same tick as worldTo (stepWorld) — the sky
                                      // swap beat still lands on the arrival flourish frame
            shieldActive: shield, magnetRemaining: magnetT, doublerRemaining: doublerT,
            chronoRemaining: chronoT,
            boostRemaining: boostT, sneakersRemaining: superSneakersT, flowStreak: flowStreak,
            sliding: slideT > 0, grounded: grounded,
            stumbleRemaining: stumbleT,
            usedCheckpoint: usedCheckpoint,
            entities: entityScratch,
            warden: warden?.state(charge: wardenCharge, playerX: px),
            wardenCharge: wardenCharge,
            blastFrontZ: blastWave.map { distance - $0.frontD },
            score: score, gems: gemCount, mult: mult, best: best
        )
    }

    private func emit(_ fx: FXEvent) { onFX?(fx) }
}
