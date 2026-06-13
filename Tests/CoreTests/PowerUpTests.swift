import XCTest
@testable import PrismRush

/// Hand-built scenarios for the v1.2 pickups: Coin Doubler (×2 currency) and Chrono (slow-mo).
@MainActor
final class PowerUpTests: XCTestCase {

    /// Start a clean run with the spawner parked, ready for `debugSpawn` scenarios.
    private func cleanCore(seed: UInt64 = 2) -> GameCore {
        let core = GameCore(seed: seed)
        core.startRun(seed: seed)
        core.debugClearTrack()
        return core
    }

    /// Tick until `cond` holds (bounded), returning whether it did.
    private func tickUntil(_ core: GameCore, max maxTicks: Int = 600, _ cond: () -> Bool) -> Bool {
        var n = 0
        while !cond() && n < maxTicks { core.tick(Tuning.tickDt); n += 1 }
        return cond()
    }

    // MARK: Coin Doubler

    func testDoublerDoublesCurrencyButNotStreak() async {
        let core = cleanCore()
        var picked: [PickupKind] = []
        core.onFX = { if case let .pickup(kind, _, _) = $0 { picked.append(kind) } }

        // Baseline gem: 1 coin, 1 streak.
        core.debugSpawn(.gem(d: core.distance + 3, lane: 1, y: 0.8))
        XCTAssertTrue(tickUntil(core) { core.gemCount == 1 })
        XCTAssertEqual(core.streak, 1)

        // Collect the doubler, then a second gem: +2 currency, still +1 streak.
        core.debugSpawn(.doubler(d: core.distance + 3, lane: 1))
        XCTAssertTrue(tickUntil(core) { core.doublerT > 0 })
        XCTAssertEqual(picked, [.doubler], "reuses FXEvent.pickup with the new kind")
        core.advance(realDt: Tuning.tickDt)   // snapshot rebuilds on `advance`, not bare `tick`
        XCTAssertEqual(core.snapshot.doublerRemaining, core.doublerT, accuracy: 1e-9)
        XCTAssertGreaterThan(core.snapshot.doublerRemaining, 0)

        core.debugSpawn(.gem(d: core.distance + 3, lane: 1, y: 0.8))
        XCTAssertTrue(tickUntil(core) { core.gemCount == 3 }, "doubled gem pays 2 coins")
        XCTAssertEqual(core.streak, 2, "streak (skill stat) never doubles")
        XCTAssertEqual(core.bestStreak, 2)
    }

    func testDoublerExpires() async {
        let core = cleanCore()
        core.debugSpawn(.doubler(d: core.distance + 3, lane: 1))
        XCTAssertTrue(tickUntil(core) { core.doublerT > 0 })
        XCTAssertTrue(tickUntil(core, max: Int(Tuning.doublerDuration / Tuning.tickDt) + 10) { core.doublerT == 0 })

        core.debugSpawn(.gem(d: core.distance + 3, lane: 1, y: 0.8))
        XCTAssertTrue(tickUntil(core) { core.gemCount > 0 })
        XCTAssertEqual(core.gemCount, 1, "post-expiry gems pay single again")
    }

    // MARK: Chrono slow-mo

    func testChronoSlowsDistanceNotTheRamp() async {
        let core = cleanCore()
        core.debugSpawn(.chrono(d: core.distance + 3, lane: 1))
        XCTAssertTrue(tickUntil(core) { core.chronoT > 0 })

        // One tick must integrate distance at exactly speed × chronoFactor.
        let d0 = core.distance
        let expected = core.speed * Tuning.chronoFactor * Tuning.tickDt
        core.tick(Tuning.tickDt)
        XCTAssertEqual(core.distance - d0, expected, accuracy: expected * 0.02,
                       "distance integrates the slowed speed (ramp lerp shifts it only marginally)")
        XCTAssertEqual(core.effectiveSpeed, core.speed * Tuning.chronoFactor, accuracy: 1e-9)

        // The snapshot's `speed` carries the EFFECTIVE value; `rampSpeed` the raw ramp.
        core.advance(realDt: Tuning.tickDt)
        XCTAssertEqual(core.snapshot.speed, core.effectiveSpeed, accuracy: 1e-9)
        XCTAssertEqual(core.snapshot.rampSpeed, core.speed, accuracy: 1e-9)
        XCTAssertGreaterThan(core.snapshot.chronoRemaining, 0)
    }

    func testChronoEndedFiresOnceOnExpiry() async {
        let core = cleanCore()
        var ended = 0
        core.onFX = { if case .chronoEnded = $0 { ended += 1 } }
        core.debugSpawn(.chrono(d: core.distance + 3, lane: 1))
        XCTAssertTrue(tickUntil(core) { core.chronoT > 0 })

        for _ in 0..<(Int(Tuning.chronoDuration / Tuning.tickDt) + 60) { core.tick(Tuning.tickDt) }
        XCTAssertEqual(core.chronoT, 0)
        XCTAssertEqual(ended, 1, "chronoEnded is an edge — fired exactly once")
        XCTAssertEqual(core.effectiveSpeed, core.speed, accuracy: 1e-9, "ramp resumes seamlessly")
    }

    /// The bot must actually EXPERIENCE slow-mo in procedural runs: split-bar patterns place a
    /// reachable chrono in the gap lane, and the autopilot's effective-speed leads stay solvable
    /// while it's active (the soak itself asserts zero deaths).
    func testBotCollectsChronoDuringProceduralRuns() async {
        var chronos = 0
        for s in 0..<10 {
            let seed = UInt64(s) &* 0x9E37_79B9_7F4A_7C15 &+ 0xC400_0001
            let core = GameCore(seed: 1)
            core.startRun(seed: seed)
            core.onFX = { if case .pickup(kind: .chrono, x: _, y: _) = $0 { chronos += 1 } }
            var ticks = 0
            while core.mode == .play && core.distance < 6_000 && ticks < 200_000 {
                Autopilot.drive(core)
                core.tick(Tuning.tickDt)
                ticks += 1
            }
            XCTAssertEqual(core.mode, .play, "seed \(seed) must stay solvable with chrono in play")
        }
        XCTAssertGreaterThan(chronos, 0, "at least one chrono must be collected across the seeds")
    }

    // MARK: manual slow-mo (player-triggered, v1.5)

    func testManualSlowMoActivatesAndDoesNotStack() async {
        let core = cleanCore()
        var pickups: [PickupKind] = []
        core.onFX = { if case let .pickup(kind, _, _) = $0 { pickups.append(kind) } }

        // Fires in play, sets the chrono timer, and emits the same FX as the track pickup.
        XCTAssertTrue(core.activateSlowMo())
        XCTAssertEqual(core.chronoT, Tuning.chronoDuration, accuracy: 1e-9)
        XCTAssertEqual(pickups, [.chrono])

        // No stacking/refresh while one is already running.
        XCTAssertFalse(core.activateSlowMo())
        XCTAssertEqual(pickups.count, 1, "a second deploy mid-effect must be a no-op")

        // Re-armable once it has expired.
        XCTAssertTrue(tickUntil(core) { core.chronoT <= 0 })
        XCTAssertTrue(core.activateSlowMo())
    }

    func testManualSlowMoIgnoredOutsidePlay() async {
        let core = GameCore(seed: 1)               // never started → .menu
        XCTAssertFalse(core.activateSlowMo())
        XCTAssertEqual(core.chronoT, 0)
    }

    // MARK: Super Sneakers (v1.5 — higher-jump track pickup)

    /// Jump once from the ground and return the peak `jumpY` reached before landing.
    private func jumpApex(_ core: GameCore) -> Double {
        core.jump()
        var peak = core.jumpY
        var n = 0
        while !core.grounded && n < 600 { core.tick(Tuning.tickDt); peak = max(peak, core.jumpY); n += 1 }
        return peak
    }

    func testSuperSneakersRaisesJumpApexAndIsNeverLethal() async {
        let core = cleanCore()
        var picked: [PickupKind] = []
        core.onFX = { if case let .pickup(kind, _, _) = $0 { picked.append(kind) } }

        // Baseline apex matches the analytic height jumpV0² / 2g.
        let baseApex = jumpApex(core)
        XCTAssertEqual(baseApex, Tuning.jumpV0 * Tuning.jumpV0 / (2 * Tuning.gravity), accuracy: 0.05)

        // Collect the pickup: it sets the timer, emits the new FX kind, and never kills.
        core.debugSpawn(.superSneakers(d: core.distance + 3, lane: 1))
        XCTAssertTrue(tickUntil(core) { core.superSneakersT > 0 }, "must collect the Super Sneakers")
        XCTAssertEqual(picked, [.superSneakers], "reuses FXEvent.pickup with the new kind")
        XCTAssertEqual(core.mode, .play, "a pickup is never lethal")
        core.advance(realDt: Tuning.tickDt)   // snapshot rebuilds on `advance`
        XCTAssertEqual(core.snapshot.sneakersRemaining, core.superSneakersT, accuracy: 1e-9)
        XCTAssertGreaterThan(core.snapshot.sneakersRemaining, 0)

        // While active, the jump launches meaningfully higher (height ∝ v² → ×1.56 at ×1.25 v0).
        let boostedApex = jumpApex(core)
        XCTAssertGreaterThan(boostedApex, baseApex * 1.4, "Super Sneakers must clearly raise the jump")
    }

    func testSuperSneakersEndedFiresOnceAndRestoresJump() async {
        let core = cleanCore()
        var ended = 0
        core.onFX = { if case .sneakersEnded = $0 { ended += 1 } }
        core.debugSpawn(.superSneakers(d: core.distance + 3, lane: 1))
        XCTAssertTrue(tickUntil(core) { core.superSneakersT > 0 })

        for _ in 0..<(Int(Tuning.superSneakersDuration / Tuning.tickDt) + 60) { core.tick(Tuning.tickDt) }
        XCTAssertEqual(core.superSneakersT, 0)
        XCTAssertEqual(ended, 1, "sneakersEnded is an edge — fired exactly once")

        // Jump height returns to the baseline once the buff expires.
        let apex = jumpApex(core)
        XCTAssertEqual(apex, Tuning.jumpV0 * Tuning.jumpV0 / (2 * Tuning.gravity), accuracy: 0.05,
                       "jump height restores after the buff ends")
    }

    // MARK: Head Start (pre-run consumable, v1.5)

    func testHeadStartLaunchesWithBoostAndIsLeaderboardSafe() async {
        let core = GameCore(seed: 3)
        core.startRun(seed: 3)
        XCTAssertEqual(core.boostT, 0, "a fresh run has no boost")
        XCTAssertFalse(core.usedCheckpoint, "a normal run is leaderboard-eligible")

        XCTAssertTrue(core.activateHeadStart())
        XCTAssertEqual(core.boostT, Tuning.headStartBoostDuration, accuracy: 1e-9,
                       "Head Start launches with a multi-second overdrive boost")
        XCTAssertGreaterThan(core.effectiveSpeed, core.speed,
                             "the boost actually speeds the world up at launch")
        XCTAssertFalse(core.usedCheckpoint,
                       "Head Start must NOT mark the run as a checkpoint (stays leaderboard-eligible)")

        // It expires like any boost, restoring the raw ramp.
        for _ in 0..<(Int(Tuning.headStartBoostDuration / Tuning.tickDt) + 30) { core.tick(Tuning.tickDt) }
        XCTAssertEqual(core.boostT, 0)
        XCTAssertEqual(core.effectiveSpeed, core.speed, accuracy: 1e-9)
    }

    func testHeadStartIgnoredOutsidePlay() async {
        let core = GameCore(seed: 1)   // never started → .menu
        XCTAssertFalse(core.activateHeadStart())
        XCTAssertEqual(core.boostT, 0)
    }

    // MARK: manual Speed Up (player-triggered overdrive, v1.6)

    func testDeployOverdriveActivatesAndDoesNotStack() async {
        let core = cleanCore()
        XCTAssertTrue(core.deployOverdrive())
        XCTAssertEqual(core.boostT, Tuning.speedUpDeployDuration, accuracy: 1e-9)
        XCTAssertGreaterThan(core.effectiveSpeed, core.speed, "overdrive speeds the world up")
        XCTAssertFalse(core.deployOverdrive(), "no stack while one is already running")

        // Re-armable once it has expired.
        XCTAssertTrue(tickUntil(core, max: Int(Tuning.speedUpDeployDuration / Tuning.tickDt) + 30) { core.boostT <= 0 })
        XCTAssertTrue(core.deployOverdrive())
    }

    func testDeployOverdriveIgnoredOutsidePlay() async {
        let core = GameCore(seed: 1)
        XCTAssertFalse(core.deployOverdrive())
        XCTAssertEqual(core.boostT, 0)
    }

    // MARK: manual Shield deploy (v1.6)

    func testDeployShieldActivatesOnceAndRefusesWhenHeld() async {
        let core = cleanCore()
        XCTAssertFalse(core.shield)
        XCTAssertTrue(core.deployShield())
        XCTAssertTrue(core.shield)
        XCTAssertFalse(core.deployShield(), "no waste — refuses while a shield is already held")
    }

    func testDeployShieldIgnoredOutsidePlay() async {
        let core = GameCore(seed: 1)
        XCTAssertFalse(core.deployShield())
        XCTAssertFalse(core.shield)
    }

    // MARK: guaranteed power-up cadence (v1.6)

    func testPowerUpCadenceDeliversEveryKind() async {
        // The cadence cycles all five power-ups, so over a few thousand metres every kind shows up
        // on the track (the old behaviour buried doubler/sneakers ~1,100–1,500 m apart).
        let core = GameCore(seed: 1)
        core.startRun(seed: 7)
        var seen = Set<EntityKind>()
        var ticks = 0
        while core.distance < 4_000 && ticks < 80_000 {
            Autopilot.drive(core)
            core.tick(Tuning.tickDt)
            for p in core.activePickups { seen.insert(p.kind) }
            ticks += 1
        }
        for k in [EntityKind.shield, .magnet, .doubler, .chrono, .superSneakers] {
            XCTAssertTrue(seen.contains(k), "the cadence must deliver \(k) within 4,000 m")
        }
        XCTAssertEqual(core.mode, .play, "the cadence pickups are non-lethal — the run survives")
    }
}
