import XCTest
@testable import PrismRush

@MainActor
final class DifficultyTests: XCTestCase {

    /// The inter-pattern gap shrinks monotonically: 11 → 5 across act one, then 5 → 4 across act two
    /// (v1.7 — before that it floored at `gapMin` and never moved again).
    func testGapMonotonicDown() async {
        var prev = Double.infinity
        for d in stride(from: 0.0, through: 12_000, by: 25) {
            let g = Spawner.gap(forDistance: d)
            XCTAssertLessThanOrEqual(g, prev + 1e-9, "gap must not increase at d=\(d)")
            XCTAssertGreaterThanOrEqual(g, Tuning.gapFloorActTwo - 1e-9, "gap fell through its floor at d=\(d)")
            XCTAssertLessThanOrEqual(g, Tuning.gapMax + 1e-9)
            prev = g
        }
        XCTAssertEqual(Spawner.gap(forDistance: 0), Tuning.gapMax, accuracy: 1e-9)
        // The two acts must meet exactly at the seam — no step, no kink.
        XCTAssertEqual(Spawner.gap(forDistance: Tuning.diffFullAt), Tuning.gapMin, accuracy: 1e-9)
        XCTAssertEqual(Spawner.gap(forDistance: Tuning.actTwoAt), Tuning.gapMin, accuracy: 1e-9)
        XCTAssertEqual(Spawner.gap(forDistance: Tuning.actTwoFullAt), Tuning.gapFloorActTwo, accuracy: 1e-9)
        // …and the floor holds forever after.
        XCTAssertEqual(Spawner.gap(forDistance: 100_000), Tuning.gapFloorActTwo, accuracy: 1e-9)
    }

    /// Act one must be untouched by v1.7: the second axis is exactly zero before `actTwoAt`, so the
    /// flow channel the design bible calls "good design and should not be touched" is bit-identical.
    func testActOneIsUnchangedByTheSecondAct() async {
        for d in stride(from: 0.0, through: Tuning.actTwoAt, by: 25) {
            XCTAssertEqual(Spawner.intensity(forDistance: d), 0, accuracy: 1e-12,
                           "act two must not start before \(Tuning.actTwoAt) (d=\(d))")
            XCTAssertNil(Spawner.pool(forDistance: d), "act one draws uniformly, with no table (d=\(d))")
            XCTAssertEqual(Patterns.wallPhase(at: d, index: 0), 0, accuracy: 1e-12)
            XCTAssertEqual(Patterns.wallPhase(at: d, index: 1), 0, accuracy: 1e-12)
        }
    }

    /// Act two's intensity is monotone, bounded, and actually reaches full.
    func testSecondActIntensityRamp() async {
        var prev = -Double.infinity
        for d in stride(from: 0.0, through: 20_000, by: 25) {
            let i = Spawner.intensity(forDistance: d)
            XCTAssertGreaterThanOrEqual(i, prev - 1e-9, "intensity must not fall at d=\(d)")
            XCTAssertGreaterThanOrEqual(i, 0)
            XCTAssertLessThanOrEqual(i, 1)
            prev = i
        }
        XCTAssertEqual(Spawner.intensity(forDistance: Tuning.actTwoFullAt), 1, accuracy: 1e-9)
    }

    /// Every wave keeps the WHOLE catalogue reachable — act two shifts the mix, it never deletes a
    /// pattern. The breather beats (0, 10) and the reward beats (9's ring, 10's runway) must survive
    /// to any depth, or a shipped feature silently stops existing in long runs.
    func testEveryWaveKeepsTheFullCatalogueReachable() async {
        for d in [3_300.0, 5_000, 6_500, 9_600, 25_000] {
            guard let pool = Spawner.pool(forDistance: d) else {
                return XCTFail("expected an act-two pool at d=\(d)")
            }
            for idx in 0..<Patterns.count {
                XCTAssertTrue(pool.contains(idx),
                              "pattern \(idx) fell out of the draw table at d=\(d)")
            }
            XCTAssertTrue(pool.allSatisfy { $0 >= 0 && $0 < Spawner.maxIndex(forDistance: d) },
                          "the pool must stay inside the unlocked prefix at d=\(d)")
        }
    }

    /// A moving wall must always leave at least one lane genuinely open, at every phase act two can
    /// produce and everywhere across its sweep through the kill band. This is the fairness floor the
    /// whole swung-phase idea rests on.
    func testSwungMovingWallsAlwaysLeaveALaneOpen() async {
        for d in stride(from: Tuning.actTwoAt, through: 40_000, by: 100) {
            for index in 0...1 {
                let phase = Patterns.wallPhase(at: d, index: index)
                // Sweep the kill band: the wall travels ±(movingWallFreq × obstacleZHalf × 2).
                for step in -10...10 {
                    let swept = phase + Double(step) / 10 * Tuning.movingWallFreq * Tuning.obstacleZHalf * 2
                    let open = (0..<3).filter { !Spawner.movingWallLanes(swept).contains($0) }
                    XCTAssertFalse(open.isEmpty,
                                   "no open lane at d=\(d) wall=\(index) phase=\(swept)")
                }
            }
        }
    }

    /// Pattern-availability gates open at the documented distances (v1.8 six-tier ladder).
    func testPatternGating() async {
        XCTAssertEqual(Spawner.maxIndex(forDistance: 0), 5)
        XCTAssertEqual(Spawner.maxIndex(forDistance: 259), 5)
        XCTAssertEqual(Spawner.maxIndex(forDistance: 260), 9)        // diff = 0.08 < 0.18
        XCTAssertEqual(Spawner.maxIndex(forDistance: 575), 9)        // diff just under 0.18
        XCTAssertEqual(Spawner.maxIndex(forDistance: 576), 11)       // diff = 0.18 → rings + overdrive runways
        XCTAssertEqual(Spawner.maxIndex(forDistance: 1439), 11)      // diff just under 0.45
        XCTAssertEqual(Spawner.maxIndex(forDistance: 1440), 13)      // diff = 0.45 → gauntlet + split bars (no moving walls)
        XCTAssertEqual(Spawner.maxIndex(forDistance: 1919), 13)      // diff just under 0.6
        XCTAssertEqual(Spawner.maxIndex(forDistance: 1920), 14)       // diff = 0.6 → moving walls unlock
        XCTAssertEqual(Spawner.maxIndex(forDistance: 2559), 14)       // diff just under 0.8
        XCTAssertEqual(Spawner.maxIndex(forDistance: 2560), Patterns.count) // diff = 0.8 → the chasm unlocks
        XCTAssertEqual(Spawner.maxIndex(forDistance: 6000), Patterns.count)
    }

    /// Fairness: World 2 (800–1600 m) must never spawn moving walls — players are still acclimating.
    /// Pinned against the literal index 13, not `Patterns.count`: once tier six existed,
    /// `< Patterns.count` only excluded the chasm and stopped proving anything about moving walls.
    func testWorld2HasNoMovingWalls() async {
        for d in stride(from: 800.0, through: 1599.0, by: 50) {
            XCTAssertLessThanOrEqual(Spawner.maxIndex(forDistance: d), 13,
                                     "moving walls should not be selectable at d=\(d) (World 2)")
        }
    }

    /// Speed is non-decreasing throughout a live run and never exceeds the cap.
    func testSpeedMonotonicToCap() async {
        let core = GameCore(seed: 7)
        core.startRun(seed: 7)
        var prev = -Double.infinity
        for _ in 0..<40_000 where core.mode == .play {
            Autopilot.drive(core)
            core.tick(Tuning.tickDt)
            XCTAssertLessThanOrEqual(core.speed, Tuning.speedCap + 1e-6)
            XCTAssertGreaterThanOrEqual(core.speed, prev - 1e-6, "speed dropped while playing")
            prev = core.speed
        }
    }

    /// The closed-form speed target is itself monotonic and capped.
    func testSpeedTargetFormula() async {
        var prev = -Double.infinity
        for d in stride(from: 0.0, through: 8000, by: 10) {
            let target = min(Tuning.speedCap, Tuning.speedStart + d * Tuning.speedRamp)
            XCTAssertGreaterThanOrEqual(target, prev - 1e-9)
            XCTAssertLessThanOrEqual(target, Tuning.speedCap + 1e-9)
            prev = target
        }
    }
}
