import XCTest
@testable import PrismRush

/// Simulation-level regression tests for the v1.2 core fixes: input sanitation, near-miss
/// fairness, shield invulnerability, revive/checkpoint score integrity. Hand-built scenarios
/// use `debugClearTrack()` + `debugSpawn(_:)` so the spawner can't interfere.
@MainActor
final class GameplayTests: XCTestCase {

    // MARK: dt sanitation (P1)

    func testAdvanceSurvivesNaNAndJunkDt() async {
        let core = GameCore(seed: 1)
        core.startRun(seed: 1)
        let d0 = core.distance

        core.advance(realDt: .nan)
        core.advance(realDt: .infinity)
        core.advance(realDt: -0.016)
        core.advance(realDt: 0)
        XCTAssertEqual(core.distance, d0, "junk dt must not step the simulation")

        // The accumulator must not have been poisoned: a normal frame still ticks.
        core.advance(realDt: 1.0 / 60.0)
        XCTAssertGreaterThan(core.distance, d0, "valid dt after junk dt must still advance")
        XCTAssertTrue(core.distance.isFinite)
    }

    // MARK: near-miss fairness (P1)

    /// Standing a full lane away (dx = 2.2) used to auto-award CLOSE on every passed tall.
    func testTallPassingOneLaneAwayAwardsNothing() async {
        let core = GameCore(seed: 1)
        core.startRun(seed: 1)
        core.debugClearTrack()
        var events: [FXEvent] = []
        core.onFX = { events.append($0) }

        // Player settled in the centre lane; a tall in lane 0 is just past the kill band, so the
        // next tick flips `passed` with dx = 2.2.
        let bonus0 = core.bonus
        core.debugSpawn(.tall(d: core.distance - Tuning.obstacleZHalf - 0.01, lane: 0))
        for _ in 0..<8 { core.tick(Tuning.tickDt) }
        XCTAssertEqual(core.bonus, bonus0, "dx 2.2 must not award CLOSE")
        XCTAssertFalse(events.contains { if case .nearMiss = $0 { return true }; return false })
    }

    /// A genuine squeeze (dx ≈ 1.6, mid-lane-change) awards CLOSE — exactly once.
    func testTallPassingInsideBandAwardsCloseOnce() async {
        let core = GameCore(seed: 1)
        core.startRun(seed: 1)
        core.debugClearTrack()
        var closes = 0
        core.onFX = { if case .nearMiss(kind: "CLOSE", x: _) = $0 { closes += 1 } }

        // Drift the player from lane 0 toward centre until dx-to-lane-0 is ~1.6, then let a tall
        // in lane 0 cross the player plane at that exact offset.
        core.changeLane(-1)                                      // lane 1 → 0
        while core.px > Tuning.laneX[0] + 0.05 { core.tick(Tuning.tickDt) }
        core.changeLane(+1)                                      // head back toward centre
        while core.px < Tuning.laneX[0] + 1.58 { core.tick(Tuning.tickDt) }
        core.debugSpawn(.tall(d: core.distance - Tuning.obstacleZHalf - 0.01, lane: 0))
        let bonus0 = core.bonus
        for _ in 0..<20 { core.tick(Tuning.tickDt) }             // pass + plenty of follow-up ticks
        XCTAssertEqual(core.mode, .play, "dx 1.6 is outside the kill width — no death")
        XCTAssertEqual(closes, 1, "CLOSE must be awarded exactly once per obstacle")
        XCTAssertEqual(core.bonus, bonus0 + Tuning.nearMissBonus * core.mult)
    }

    // MARK: shield grace window (P1)

    /// Patterns 3/7/9 place two talls at an identical `d`. A shield absorb must survive BOTH the
    /// same-tick partner hit and the following ticks while that partner is still in the kill band.
    func testShieldAbsorbSurvivesTwinTallsAtSameDepth() async {
        let core = GameCore(seed: 1)
        core.startRun(seed: 1)
        core.debugClearTrack()
        var absorbs = 0
        core.onFX = { if case .shieldAbsorbed = $0 { absorbs += 1 } }

        // Collect a real shield pickup in the centre lane.
        core.debugSpawn(.shield(d: core.distance + 3, lane: 1))
        var guardTicks = 0
        while !core.shield && guardTicks < 600 { core.tick(Tuning.tickDt); guardTicks += 1 }
        XCTAssertTrue(core.shield, "scenario setup: shield pickup must be collected")

        // Two talls at the SAME depth, both overlapping the player, already inside the kill band.
        let d = core.distance + 0.5
        core.debugSpawn(.tall(d: d, lane: 1))
        core.debugSpawn(.tall(d: d, lane: 1))
        core.tick(Tuning.tickDt)
        XCTAssertEqual(core.mode, .play, "the partner tall must not kill on the absorb tick")
        XCTAssertFalse(core.shield)
        XCTAssertEqual(absorbs, 1, "exactly one absorb")
        XCTAssertGreaterThan(core.invulnT, 0)

        // The partner stays in the kill band for ~0.1 s more — the grace window must cover it.
        for _ in 0..<24 { core.tick(Tuning.tickDt) }
        XCTAssertEqual(core.mode, .play, "still alive while the partner wall exits the kill band")

        // After the window expires the player is mortal again.
        while core.invulnT > 0 { core.tick(Tuning.tickDt) }
        core.debugSpawn(.tall(d: core.distance + 0.5, lane: 1))
        core.tick(Tuning.tickDt)
        XCTAssertEqual(core.mode, .over, "invulnerability must expire — next unshielded hit kills")
    }

    // MARK: score integrity at death + revive (P2)

    func testScoreFreezesAtDeath() async {
        let core = GameCore(seed: 5)
        core.startRun(seed: 5)
        for _ in 0..<2_400 { Autopilot.drive(core); core.tick(Tuning.tickDt) }   // 20 s of real play
        core.debugForceDie()
        let frozen = core.score
        let dDeath = core.distance
        for _ in 0..<240 { core.tick(Tuning.tickDt) }                            // 2 s of death decel
        XCTAssertGreaterThan(core.distance, dDeath, "decel still moves the world")
        XCTAssertEqual(core.score, frozen, "score must freeze the instant the run dies")
    }

    /// Distance integrated during the death decel must not leak into the post-revive score.
    func testReviveResumesAtFrozenScore() async {
        let core = GameCore(seed: 5)
        core.startRun(seed: 5)
        for _ in 0..<2_400 { Autopilot.drive(core); core.tick(Tuning.tickDt) }
        core.debugForceDie()
        let frozen = core.score
        let traveledAtDeath = core.traveledDistance
        for _ in 0..<240 { core.tick(Tuning.tickDt) }                            // full decel drift
        XCTAssertGreaterThan(core.traveledDistance, traveledAtDeath + 5, "decel drifted distance")

        core.revive()
        XCTAssertEqual(core.score, frozen, "score immediately after revive == frozen death score")
        XCTAssertEqual(core.traveledDistance, traveledAtDeath, accuracy: 1e-9,
                       "the decel drift is folded into scoreOffset")
        core.tick(Tuning.tickDt)
        XCTAssertLessThanOrEqual(abs(core.score - frozen), 1,
                                 "first post-revive tick resumes from the frozen score (±1 rounding)")
    }
}
