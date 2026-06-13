import Foundation
import Observation

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
    @ObservationIgnored private(set) var magnetT: Double = 0
    @ObservationIgnored private(set) var doublerT: Double = 0  // gems pay double currency while > 0
    @ObservationIgnored private(set) var chronoT: Double = 0   // slow-mo: distance integrates at × chronoFactor
    @ObservationIgnored private(set) var boostT: Double = 0    // overdrive: world speed × boostFactor (capped)
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

    @ObservationIgnored private(set) var activeObstacles: [CoreEntity] = []
    @ObservationIgnored private(set) var activeGems: [CoreEntity] = []
    @ObservationIgnored private(set) var activePickups: [CoreEntity] = []

    @ObservationIgnored private var rng: SplitMix64
    @ObservationIgnored private var spawner = Spawner()
    @ObservationIgnored private var accumulator: Double = 0
    @ObservationIgnored private var nextId: Int = 0

    init(seed: UInt64 = .random(in: .min ... .max)) {
        rng = SplitMix64(seed: seed)
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
            let wn = Int((startDistance / Tuning.worldLength).rounded(.down))
            let wi = ((wn % 3) + 3) % 3
            maxWorld = wn; world = wi; worldFrom = wi; worldTo = wi; worldBlend = 1
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

    /// Reset to the fresh menu state. Reseeds if `seed` is given (else a new random stream).
    func reset(seed: UInt64?) {
        rng = SplitMix64(seed: seed ?? .random(in: .min ... .max))
        spawner = Spawner()
        mode = .menu; distance = 0; scoreOffset = 0; speed = Tuning.menuSpeed; revivesUsed = 0
        deathDistance = 0; usedCheckpoint = false
        px = 0; laneIndex = 1; jumpY = 0; vy = 0; grounded = true; slideT = 0; sy = 1
        bankZ = 0; jumpBuf = 0
        world = 0; maxWorld = 0; worldFrom = 0; worldTo = 0; worldBlend = 1
        shield = false; invulnT = 0; magnetT = 0; doublerT = 0; chronoT = 0
        boostT = 0; flowStreak = 0; flowSurges = 0
        bonus = 0; score = 0; gemCount = 0; streak = 0; bestStreak = 0; mult = 1
        activeObstacles.removeAll(keepingCapacity: true)
        activeGems.removeAll(keepingCapacity: true)
        activePickups.removeAll(keepingCapacity: true)
        accumulator = 0; nextId = 0
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
        if invulnT > 0 { invulnT = max(0, invulnT - dt) }
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
            grounded = false; vy = Tuning.jumpV0; slideT = 0; sy = Tuning.airStretchY
            emit(.jumped(x: px))
        } else {
            jumpBuf = Tuning.jumpBuffer   // buffered: fires on landing
        }
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

    func slide() {
        guard mode == .play else { return }
        slideT = Tuning.slideDuration
        sy = Tuning.slideScaleY               // snap to the low slide profile immediately (responsive +
        if !grounded { vy = Tuning.slamVy }   // avoids the mid-lerp window where a bar still clips you)
        emit(.slid(x: px))
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
                    jumpBuf = 0; grounded = false; vy = Tuning.jumpV0; sy = Tuning.airStretchY
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
        case .bar, .splitBar: return 0
        case .movingTall: return sin((distance - e.d) * Tuning.movingWallFreq + e.phase) * Tuning.movingWallAmplitude
        default: return Tuning.laneX[e.lane]
        }
    }

    private func stepObstacles(_ dt: Double) {
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

            if mode == .play && invulnT <= 0 && abs(z) < Tuning.obstacleZHalf {
                let hit: Bool
                switch e.kind {
                case .bar: hit = Collisions.barHit(playerTop: pb.top, playerBottom: pb.bottom, z: z)
                case .splitBar: hit = Collisions.splitBarHit(playerTop: pb.top, playerBottom: pb.bottom, playerX: px, openLane: e.lane, z: z)
                case .low: hit = Collisions.lowHit(playerBottom: pb.bottom, playerX: px, obstacleX: ox, z: z)
                case .tall, .movingTall: hit = Collisions.tallHit(playerX: px, obstacleX: ox, z: z)
                default: hit = false
                }
                if hit {
                    if shield {
                        // The grace window outlives the kill band: patterns 3/7/9 pair talls at the
                        // same `d`, and the partner wall stays lethal for several more ticks.
                        shield = false; invulnT = Tuning.invulnDuration; streak = 0; mult = 1
                        flowStreak = 0   // taking a hit (even absorbed) breaks the flow
                        emit(.shieldAbsorbed(x: px))
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
                    switch e.kind {
                    case .tall, .movingTall:
                        let dx = abs(px - ox)
                        if Collisions.closeNearMiss(dx: dx) {
                            bonus += Tuning.nearMissBonus * mult
                            emit(.nearMiss(kind: .close, x: px))
                            registerFlowNearMiss()
                        }
                    case .bar:
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
                default:
                    break
                }
                continue
            }
            i += 1
        }
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

    /// Test/diagnostic hook: wipe every live entity and park the spawner so hand-built scenarios
    /// (`debugSpawn`) run with zero procedural interference.
    func debugClearTrack() {
        activeObstacles.removeAll(keepingCapacity: true)
        activeGems.removeAll(keepingCapacity: true)
        activePickups.removeAll(keepingCapacity: true)
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
        laneIndex = 1; px = Tuning.laneX[1]
        jumpY = 0; vy = 0; grounded = true; slideT = 0; sy = 1
        shield = true
        // A continue resets only what could bank *free* momentum: the boost timer and the flow
        // streak. Earned consumable timers (magnet / doubler / chrono) deliberately carry over —
        // the player collected them and a paid revive should never confiscate them (decree 5:
        // advertised bonuses are always delivered). `magnetT`/`doublerT`/`chronoT` are intentionally
        // left running.
        boostT = 0; flowStreak = 0
        speed = max(speed, Tuning.speedStart)   // paid continues resume instantly, not from the decel floor
        activeObstacles.removeAll()
        activeGems.removeAll()
        activePickups.removeAll()
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

    private func apply(_ cmd: SpawnCmd) {
        switch cmd {
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
        case let .ring(d, lane, y):
            guard pickupCount(.ring) < Tuning.capRing else { return }
            activePickups.append(CoreEntity(id: takeId(), kind: .ring, lane: lane, d: d, x: Tuning.laneX[lane], baseY: y, phase: 0, passed: false, fading: false))
        case let .boostPad(d, lane):
            guard pickupCount(.boostPad) < Tuning.capBoostPad else { return }
            activePickups.append(CoreEntity(id: takeId(), kind: .boostPad, lane: lane, d: d, x: Tuning.laneX[lane], baseY: 0.05, phase: 0, passed: false, fading: false))
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
            entityScratch.append(EntityState(id: e.id, kind: e.kind, x: x, y: e.baseY, z: z, lane: e.lane, spin: 0, fading: false))
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
            boostRemaining: boostT, flowStreak: flowStreak,
            sliding: slideT > 0, grounded: grounded,
            usedCheckpoint: usedCheckpoint,
            entities: entityScratch,
            score: score, gems: gemCount, mult: mult, best: best
        )
    }

    private func emit(_ fx: FXEvent) { onFX?(fx) }
}
