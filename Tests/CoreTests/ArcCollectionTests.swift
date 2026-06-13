import XCTest
@testable import PrismRush

/// P0 regression net for the v1.3 ballistic gem arc: a single jump triggered when gem 0 is
/// underfoot must collect ALL SEVEN gems at every speed tier, because the gems sit exactly on the
/// predicted jump path. If any of these fail, the arc has drifted off the physics again.
@MainActor
final class ArcCollectionTests: XCTestCase {

    /// Run a clean core up to ≈`atDistance` (speed settled on the ramp target), spawn the REAL arc
    /// (via the `Patterns` test hook) `lead` units ahead, jump `late` units after gem 0, and return
    /// the number of gems collected.
    private func collectArc(atDistance d: Double, late: Double = 0, chrono: Bool = false) -> Int {
        let core = GameCore(seed: 1)
        core.startRun(seed: 1, startDistance: max(0, d - 350))
        core.debugClearTrack()
        while core.distance < d - 25 { core.tick(Tuning.tickDt) }   // settle the speed lerp
        if chrono {
            core.debugSpawn(.chrono(d: core.distance + 3, lane: 1))
            var guardTicks = 0
            while core.chronoT <= 0 && guardTicks < 600 { core.tick(Tuning.tickDt); guardTicks += 1 }
            XCTAssertGreaterThan(core.chronoT, 0, "scenario setup: chrono must be collected")
        }

        var cmds: [SpawnCmd] = []
        Patterns.debugGemArc(d, lane: 1, out: &cmds)
        guard case let .gem(d0, _, _) = cmds[0] else { XCTFail("arc emitted no gem 0"); return 0 }
        for c in cmds { core.debugSpawn(c) }

        var collected = 0
        core.onFX = { if case .gemCollected = $0 { collected += 1 } }
        var jumped = false
        var ticks = 0
        while !core.activeGems.isEmpty && ticks < 6_000 {
            if !jumped && core.distance >= d0 + late { core.jump(); jumped = true }
            core.tick(Tuning.tickDt)
            ticks += 1
        }
        return collected
    }

    /// 7/7 by one jump at gem 0 across the whole speed ramp (v ≈ 18.6, 22.2, 30, 33).
    func testSevenOfSevenAcrossSpeedTiers() async {
        for d in [300.0, 1_000, 2_500, 4_000] {
            XCTAssertEqual(collectArc(atDistance: d), 7, "arc at d=\(d) must be 7/7 on one jump")
        }
    }

    /// Jumping 1.2 units late stays inside the human timing budget (±1.6 worst case at v=17).
    func testJumpLateToleranceStillSevenOfSeven() async {
        for d in [300.0, 1_000, 2_500, 4_000] {
            XCTAssertEqual(collectArc(atDistance: d, late: 1.2), 7, "1.2-late at d=\(d) must still be 7/7")
        }
    }

    /// Chrono shrinks the spatial jump arc (world at 0.65×, player at full rate): an arc placed
    /// for v ≈ 24.5 crossed under slow-mo must still yield ≥ 5/7 (DESIGN_mechanics §1.4 guarantee).
    func testChronoCrossingCollectsAtLeastFive() async {
        XCTAssertGreaterThanOrEqual(collectArc(atDistance: 1_442, chrono: true), 5)
    }

    /// Length law: every arc-bearing pattern must fully contain its spawns — the last spawn sits
    /// at least 2 units before the pattern's end, at every speed (lengths grow with the span).
    func testArcPatternLengthLaw() async {
        for idx in [1, 2, 6, 9, 11] {
            for b in [60.0, 300, 1_000, 2_500, 4_000, 8_000] {
                for seed: UInt64 in [1, 7, 0xBEEF] {
                    var rng = SplitMix64(seed: seed)
                    var out: [SpawnCmd] = []
                    let len = Patterns.run(idx, base: b, rng: &rng, out: &out)
                    let lastD = out.map { cmd -> Double in
                        switch cmd {
                        case let .low(d, _), let .tall(d, _), let .movingTall(d, _), let .bar(d),
                             let .splitBar(d, _), let .gem(d, _, _), let .shield(d, _),
                             let .magnet(d, _), let .doubler(d, _), let .chrono(d, _),
                             let .superSneakers(d, _),
                             let .ring(d, _, _), let .boostPad(d, _):
                            return d
                        }
                    }.max() ?? b
                    XCTAssertLessThanOrEqual(lastD + 2, b + len,
                                             "pattern \(idx) at b=\(b) spills past its length")
                }
            }
        }
    }
}
