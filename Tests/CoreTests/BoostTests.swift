import XCTest
@testable import PrismRush

/// Overdrive pads (v1.3): grounded-only trigger, the single effectiveSpeed composition point
/// (chrono first, then boost, hard-capped), the boostEnded edge, and the per-gem coin bonus that
/// flows through `gemCount` without touching streak (iron rule 9).
@MainActor
final class BoostTests: XCTestCase {

    /// Start a clean run with the spawner parked, ready for `debugSpawn` scenarios.
    private func cleanCore(seed: UInt64 = 2, startDistance: Double = 0) -> GameCore {
        let core = GameCore(seed: seed)
        core.startRun(seed: seed, startDistance: startDistance)
        core.debugClearTrack()
        return core
    }

    /// Tick until `cond` holds (bounded), returning whether it did.
    private func tickUntil(_ core: GameCore, max maxTicks: Int = 600, _ cond: () -> Bool) -> Bool {
        var n = 0
        while !cond() && n < maxTicks { core.tick(Tuning.tickDt); n += 1 }
        return cond()
    }

    /// An airborne crossing must NOT trigger the pad (it stays on the floor for later);
    /// a grounded crossing does, paying the score bonus once.
    func testTriggerRequiresGrounded() async {
        let core = cleanCore()
        var starts = 0
        core.onFX = { if case .boostStarted = $0 { starts += 1 } }

        // Jump so the entire ±1.1 pad window is crossed mid-air (airtime ≈ 13.9 units at v=17).
        let padD = core.distance + 8
        core.debugSpawn(.boostPad(d: padD, lane: 1))
        XCTAssertTrue(tickUntil(core) { core.distance >= padD - 7 })
        core.jump()
        XCTAssertTrue(tickUntil(core) { core.distance > padD + 2 })
        XCTAssertEqual(core.boostT, 0, "airborne crossing must not trigger the pad")
        XCTAssertEqual(starts, 0)
        XCTAssertEqual(core.activePickups.count, 1, "untriggered pad stays on the floor")

        // Grounded crossing triggers and pays the score bonus.
        let bonus0 = core.bonus
        core.debugSpawn(.boostPad(d: core.distance + 5, lane: 1))
        XCTAssertTrue(tickUntil(core) { core.boostT > 0 }, "grounded crossing must trigger")
        XCTAssertEqual(starts, 1)
        XCTAssertEqual(core.bonus - bonus0, Tuning.boostScoreBonus * core.mult)
    }

    /// effectiveSpeed = chrono first, then boost, capped at boostSpeedMax — the raw ramp `speed`
    /// is never touched.
    func testEffectiveSpeedCompositionAndCap() async {
        // Boost alone: × boostFactor (uncapped at low speed).
        let core = cleanCore()
        core.debugSpawn(.boostPad(d: core.distance + 3, lane: 1))
        XCTAssertTrue(tickUntil(core) { core.boostT > 0 })
        XCTAssertEqual(core.effectiveSpeed, min(core.speed * Tuning.boostFactor, Tuning.boostSpeedMax),
                       accuracy: 1e-9)
        XCTAssertLessThan(core.effectiveSpeed, Tuning.boostSpeedMax, "v≈17 boost stays under the cap")

        // Chrono + boost: capped product of both factors.
        let core2 = cleanCore(seed: 3)
        core2.debugSpawn(.chrono(d: core2.distance + 3, lane: 1))
        XCTAssertTrue(tickUntil(core2) { core2.chronoT > 0 })
        core2.debugSpawn(.boostPad(d: core2.distance + 3, lane: 1))
        XCTAssertTrue(tickUntil(core2) { core2.boostT > 0 })
        XCTAssertEqual(core2.effectiveSpeed,
                       min(core2.speed * Tuning.chronoFactor * Tuning.boostFactor, Tuning.boostSpeedMax),
                       accuracy: 1e-9)

        // Near the ramp cap, 1.3 × 33 would be 42.9 → hard-capped at 36; the raw ramp is untouched.
        let core3 = cleanCore(seed: 4, startDistance: 3_000)
        for _ in 0..<1_000 { core3.tick(Tuning.tickDt) }   // settle the lerp near speedCap
        XCTAssertGreaterThan(core3.speed * Tuning.boostFactor, Tuning.boostSpeedMax, "cap must bind here")
        let rawSpeed = core3.speed
        core3.debugSpawn(.boostPad(d: core3.distance + 3, lane: 1))
        XCTAssertTrue(tickUntil(core3) { core3.boostT > 0 })
        XCTAssertEqual(core3.effectiveSpeed, Tuning.boostSpeedMax, accuracy: 1e-9)
        XCTAssertEqual(core3.speed, rawSpeed, accuracy: 0.1, "boost never writes the raw ramp speed")
    }

    /// boostEnded is an edge fired exactly once; a second pad refreshes the timer (still one edge);
    /// the snapshot mirrors the timer.
    func testBoostEndedEdgeOnceAndSnapshotMirror() async {
        let core = cleanCore()
        var ended = 0
        core.onFX = { if case .boostEnded = $0 { ended += 1 } }

        core.debugSpawn(.boostPad(d: core.distance + 3, lane: 1))
        XCTAssertTrue(tickUntil(core) { core.boostT > 0 })
        core.advance(realDt: Tuning.tickDt)   // snapshot rebuilds on `advance`, not bare `tick`
        XCTAssertEqual(core.snapshot.boostRemaining, core.boostT, accuracy: 1e-9)
        XCTAssertGreaterThan(core.snapshot.boostRemaining, 0)

        // Half-way through, a second pad refreshes the timer back to the full duration.
        for _ in 0..<60 { core.tick(Tuning.tickDt) }   // 0.5 s in
        XCTAssertLessThan(core.boostT, Tuning.boostDuration - 0.4)
        core.debugSpawn(.boostPad(d: core.distance + 2, lane: 1))
        XCTAssertTrue(tickUntil(core) { core.boostT > Tuning.boostDuration - 0.1 }, "second pad refreshes")
        XCTAssertEqual(ended, 0, "no edge while the boost is being extended")

        for _ in 0..<(Int(Tuning.boostDuration / Tuning.tickDt) + 60) { core.tick(Tuning.tickDt) }
        XCTAssertEqual(core.boostT, 0)
        XCTAssertEqual(ended, 1, "boostEnded is an edge — fired exactly once")
    }

    /// While boosting, every gem pays +boostGemBonus EXTRA coins through gemCount — stacking with
    /// the doubler (2+1) — while streak/mult stay strictly per-gem skill stats (rule 9).
    func testGemBonusStacksWithDoublerThroughGemCount() async {
        let core = cleanCore()
        core.debugSpawn(.boostPad(d: core.distance + 3, lane: 1))
        XCTAssertTrue(tickUntil(core) { core.boostT > 0 })

        // Boosted gem: 1 + 1.
        core.debugSpawn(.gem(d: core.distance + 2.5, lane: 1, y: 0.8))
        XCTAssertTrue(tickUntil(core) { core.gemCount == 2 }, "boosted gem pays 1+1 coins")
        XCTAssertEqual(core.streak, 1, "boost coin bonus never bumps streak")

        // Doubler + boost: 2 + 1.
        core.debugSpawn(.doubler(d: core.distance + 2.5, lane: 1))
        XCTAssertTrue(tickUntil(core) { core.doublerT > 0 })
        XCTAssertGreaterThan(core.boostT, 0, "boost must still be live for the stacking gem")
        core.debugSpawn(.gem(d: core.distance + 2.5, lane: 1, y: 0.8))
        XCTAssertTrue(tickUntil(core) { core.gemCount == 5 }, "doubler × boost pays 2+1 per gem")
        XCTAssertEqual(core.streak, 2)

        // After the boost expires the doubler alone pays 2 again.
        XCTAssertTrue(tickUntil(core, max: Int(Tuning.boostDuration / Tuning.tickDt) + 60) { core.boostT == 0 })
        core.debugSpawn(.gem(d: core.distance + 2.5, lane: 1, y: 0.8))
        XCTAssertTrue(tickUntil(core) { core.gemCount == 7 }, "post-boost gems drop the +1")
    }
}
