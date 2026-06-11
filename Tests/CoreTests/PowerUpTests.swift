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
}
