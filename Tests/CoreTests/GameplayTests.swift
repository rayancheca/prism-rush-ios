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
        core.onFX = { if case .nearMiss(kind: .close, x: _) = $0 { closes += 1 } }

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

    /// Pinned (reviewer-verified) behaviour: a tall that actually HITS never also pays a near-miss
    /// — not when a shield absorbs it (entity removed), and not after it kills (mode-guarded).
    func testNoNearMissAwardThroughShieldOrDeathPaths() async {
        // Shield path: absorbed wall is removed before it can cross the player plane.
        let core = GameCore(seed: 6)
        core.startRun(seed: 6)
        core.debugClearTrack()
        var nearMisses = 0
        core.onFX = { if case .nearMiss = $0 { nearMisses += 1 } }
        core.debugSpawn(.shield(d: core.distance + 3, lane: 1))
        var guardTicks = 0
        while !core.shield && guardTicks < 600 { core.tick(Tuning.tickDt); guardTicks += 1 }
        core.debugSpawn(.tall(d: core.distance + 0.5, lane: 1))
        for _ in 0..<30 { core.tick(Tuning.tickDt) }
        XCTAssertEqual(core.mode, .play)
        XCTAssertEqual(nearMisses, 0, "an absorbed wall must not also pay CLOSE")

        // Death path: the killing wall stays in the world but scores nothing post-mortem.
        let core2 = GameCore(seed: 6)
        core2.startRun(seed: 6)
        core2.debugClearTrack()
        var nearMisses2 = 0
        core2.onFX = { if case .nearMiss = $0 { nearMisses2 += 1 } }
        core2.debugSpawn(.tall(d: core2.distance + 0.5, lane: 1))
        core2.tick(Tuning.tickDt)
        XCTAssertEqual(core2.mode, .over)
        let frozen = core2.score
        for _ in 0..<240 { core2.tick(Tuning.tickDt) }   // wall crosses the plane during decel
        XCTAssertEqual(nearMisses2, 0, "no CLOSE from the wall that killed you")
        XCTAssertEqual(core2.score, frozen)
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

    // MARK: checkpoint runs (P2)

    func testCheckpointRunIsFlaggedAndScoreOffsetCleared() async {
        let core = GameCore(seed: 9)
        core.startRun(seed: 9, startDistance: 1600)
        XCTAssertTrue(core.usedCheckpoint)
        XCTAssertTrue(core.snapshot.usedCheckpoint, "snapshot must carry the flag to the meta layer")
        XCTAssertEqual(core.traveledDistance, 0, accuracy: 1e-9, "head-start excluded from scoring")
        core.tick(Tuning.tickDt)
        XCTAssertLessThanOrEqual(core.score, 1, "checkpoint head-start must not pre-fill the score")

        // A fresh run is never flagged — and launches at full play speed (no menu-speed crawl).
        core.startRun(seed: 9)
        XCTAssertFalse(core.usedCheckpoint)
        XCTAssertFalse(core.snapshot.usedCheckpoint)
        XCTAssertEqual(core.speed, Tuning.speedStart, accuracy: 1e-9)
    }

    // MARK: magnet minors (P2)

    /// The magnet must not keep pulling once the run is over, and a grabbed gem's `fading` flag is
    /// sticky — the renderer never sees a released gem pop back to full opacity.
    func testMagnetStopsAtDeathAndFadingIsSticky() async {
        let core = GameCore(seed: 3)
        core.startRun(seed: 3)
        core.debugClearTrack()

        // Collect a magnet, then drop a gem one lane over inside the pull window.
        core.debugSpawn(.magnet(d: core.distance + 3, lane: 1))
        var guardTicks = 0
        while core.magnetT <= 0 && guardTicks < 600 { core.tick(Tuning.tickDt); guardTicks += 1 }
        XCTAssertGreaterThan(core.magnetT, 0, "scenario setup: magnet collected")

        core.debugSpawn(.gem(d: core.distance + 8, lane: 0, y: 0.8))
        core.tick(Tuning.tickDt)
        guard let grabbed = core.activeGems.first else { return XCTFail("gem vanished") }
        XCTAssertTrue(grabbed.fading, "magnet grab marks the gem fading")
        XCTAssertNotEqual(grabbed.x, Tuning.laneX[0], "magnet is pulling the gem")

        // Death releases the pull — but never the fade.
        core.debugForceDie()
        core.tick(Tuning.tickDt)
        guard let released = core.activeGems.first else { return }   // (not collected mid-setup)
        let xAtDeath = released.x
        core.tick(Tuning.tickDt)
        XCTAssertEqual(core.activeGems.first?.x, xAtDeath, "no pull while mode != .play")
        XCTAssertEqual(core.activeGems.first?.fading, true, "fading stays sticky once set")
    }

    // MARK: split bar (new obstacle)

    func testSplitBarSimKillsCoveredLaneSparesGapAndSlide() async {
        // In the gap lane: safe.
        let core = GameCore(seed: 4)
        core.startRun(seed: 4)
        core.debugClearTrack()
        core.debugSpawn(.splitBar(d: core.distance + 0.5, openLane: 1))
        core.tick(Tuning.tickDt)
        XCTAssertEqual(core.mode, .play, "centre gap is safe standing up")

        // Sliding in a covered lane: safe.
        core.debugClearTrack()
        core.slide()
        core.debugSpawn(.splitBar(d: core.distance + 0.5, openLane: 0))
        core.tick(Tuning.tickDt)
        XCTAssertEqual(core.mode, .play, "slide clears a covered lane")

        // Standing in a covered lane: fatal.
        while core.slideT > 0 || core.sy < 0.99 { core.tick(Tuning.tickDt) }   // stand back up
        core.debugClearTrack()
        core.debugSpawn(.splitBar(d: core.distance + 0.5, openLane: 0))
        core.tick(Tuning.tickDt)
        XCTAssertEqual(core.mode, .over, "standing under a covered lane is fatal")
    }

    // MARK: v1.2 feel retune (pinned so a regression is a deliberate act)

    func testRetunedFeelConstants() async {
        XCTAssertEqual(Tuning.laneLerpRate, 15, accuracy: 1e-9)
        XCTAssertEqual(Tuning.streakPerMult, 6)
        XCTAssertEqual(Tuning.magnetRange, 16, accuracy: 1e-9)
        XCTAssertEqual(Tuning.magnetGemYRate, 7, accuracy: 1e-9)
        XCTAssertEqual(Tuning.worldBlendRate, 0.6, accuracy: 1e-9)
        XCTAssertEqual(Tuning.nearMissOuter, 1.95, accuracy: 1e-9)
        XCTAssertEqual(Tuning.nearMissBonus, 40)
    }

    /// A paid continue resumes at (at least) full play speed instead of the decel floor.
    func testReviveRestoresPlaySpeed() async {
        let core = GameCore(seed: 5)
        core.startRun(seed: 5)
        core.debugForceDie()
        for _ in 0..<240 { core.tick(Tuning.tickDt) }   // decel toward 0
        XCTAssertLessThan(core.speed, Tuning.speedStart)
        core.revive()
        XCTAssertGreaterThanOrEqual(core.speed, Tuning.speedStart)
    }
}
