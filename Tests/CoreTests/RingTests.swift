import XCTest
@testable import PrismRush

/// Prism rings (v1.3): boundary values for the pure pass predicate, plus sim-level proof that a
/// scripted jump through the pattern-9 ring pays exactly once — and that grounded running pays
/// nothing (rings are an aim verb, not a touch-grab).
@MainActor
final class RingTests: XCTestCase {

    // MARK: pure predicate boundaries

    func testRingPassBoundaries() async {
        let y = Tuning.ringY
        // Dead-center bullseye: pass + perfect.
        var r = Collisions.ringPass(playerCenterY: y, playerX: 0, ringX: 0, ringY: y, z: 0)
        XCTAssertTrue(r.pass); XCTAssertTrue(r.perfect)
        // Perfect edge (±0.12).
        r = Collisions.ringPass(playerCenterY: y - 0.119, playerX: 0, ringX: 0, ringY: y, z: 0)
        XCTAssertTrue(r.pass); XCTAssertTrue(r.perfect)
        r = Collisions.ringPass(playerCenterY: y - 0.121, playerX: 0, ringX: 0, ringY: y, z: 0)
        XCTAssertTrue(r.pass); XCTAssertFalse(r.perfect, "outside the bullseye is a plain pass")
        // Pass edge (±0.9 vertically).
        r = Collisions.ringPass(playerCenterY: y - 0.89, playerX: 0, ringX: 0, ringY: y, z: 0)
        XCTAssertTrue(r.pass)
        r = Collisions.ringPass(playerCenterY: y - 0.91, playerX: 0, ringX: 0, ringY: y, z: 0)
        XCTAssertFalse(r.pass)
        // Lateral edge (±0.9).
        r = Collisions.ringPass(playerCenterY: y, playerX: 0.89, ringX: 0, ringY: y, z: 0)
        XCTAssertTrue(r.pass)
        r = Collisions.ringPass(playerCenterY: y, playerX: 0.91, ringX: 0, ringY: y, z: 0)
        XCTAssertFalse(r.pass)
        // Depth edge (±0.9).
        r = Collisions.ringPass(playerCenterY: y, playerX: 0, ringX: 0, ringY: y, z: 0.89)
        XCTAssertTrue(r.pass)
        r = Collisions.ringPass(playerCenterY: y, playerX: 0, ringX: 0, ringY: y, z: 0.91)
        XCTAssertFalse(r.pass)
    }

    // MARK: scripted pattern-9 thread

    /// Spawn the real ringArc pattern, steer into its lane, jump on the last telegraph gem →
    /// exactly one PERFECT ringPassed, with the exact score/coin deltas — and no streak bump
    /// from the ring itself (iron rule 9).
    func testScriptedJumpThroughPatternRingPaysOncePerfect() async {
        let core = GameCore(seed: 1)
        core.startRun(seed: 1)
        core.debugClearTrack()
        for _ in 0..<1_200 { core.tick(Tuning.tickDt) }   // settle the speed lerp near the ramp

        var rng = SplitMix64(seed: 3)
        var cmds: [SpawnCmd] = []
        let base = core.distance + 20
        _ = Patterns.run(9, base: base, rng: &rng, out: &cmds)
        var ringD = 0.0, ringLane = -1
        for c in cmds {
            if case let .ring(d, lane, y) = c {
                ringD = d; ringLane = lane
                XCTAssertEqual(y, Tuning.ringY, accuracy: 1e-9, "rings hang at apex height")
            }
        }
        XCTAssertGreaterThan(ringD, base, "pattern 9 must place exactly one ring")
        for c in cmds { core.debugSpawn(c) }
        while core.laneIndex != ringLane { core.changeLane(ringLane > core.laneIndex ? 1 : -1) }

        var perfects: [Bool] = []
        core.onFX = { if case let .ringPassed(_, _, perfect) = $0 { perfects.append(perfect) } }
        let bonus0 = core.bonus, gems0 = core.gemCount

        var jumped = false
        var ticks = 0
        while core.distance < ringD + 10 && ticks < 6_000 {
            if !jumped && core.distance >= base + 3.4 { core.jump(); jumped = true }   // last telegraph gem
            core.tick(Tuning.tickDt)
            ticks += 1
        }

        XCTAssertEqual(perfects, [true], "ringPassed fires exactly once, PERFECT on an apex thread")
        XCTAssertEqual(core.mode, .play, "the pattern's low is cleared by the same jump")
        // 3 telegraph gems (streak 1–3 → mult 1) + the perfect ring. Rings bump NO streak.
        XCTAssertEqual(core.bonus - bonus0, 3 * Tuning.gemBaseScore + Tuning.ringScore)
        XCTAssertEqual(core.gemCount - gems0, 3 + Tuning.ringPerfectCoins)
        XCTAssertEqual(core.streak, 3, "ring coins must not bump the gem streak (rule 9)")
    }

    /// Running under a ring grounded (no jump) must produce no event, no payout — and the ring
    /// must recycle cleanly behind the player.
    func testNoJumpNoRingEvent() async {
        let core = GameCore(seed: 2)
        core.startRun(seed: 2)
        core.debugClearTrack()
        var events = 0
        core.onFX = { if case .ringPassed = $0 { events += 1 } }
        core.debugSpawn(.ring(d: core.distance + 15, lane: 1, y: Tuning.ringY))
        let gems0 = core.gemCount
        for _ in 0..<2_400 { core.tick(Tuning.tickDt) }
        XCTAssertEqual(events, 0, "grounded pass-under is not a thread")
        XCTAssertEqual(core.gemCount, gems0)
        XCTAssertTrue(core.activePickups.isEmpty, "missed ring must recycle behind the player")
    }
}
