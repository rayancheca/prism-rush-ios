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

    /// Act one must be untouched by v1.7: the second axis (`intensity` / the act-two pool) is exactly
    /// zero before `actTwoAt`, so the flow channel the design bible calls "good design and should not
    /// be touched" is bit-identical there.
    ///
    /// **The wallPhase assertion changed in v2.1 (S-011).** It used to pin `wallPhase == 0` across
    /// all of act one, because `wallPhase` used to be scaled by `Spawner.intensity`, which really is
    /// zero until `actTwoAt` — so that assertion was correct for the OLD behaviour. But it was
    /// pinning a bug wearing a test as a costume: at phase 0 a moving wall sweeps only the centre
    /// (±0.332 u), so BOTH outer lanes stayed permanently safe for the first four minutes of every
    /// run — the owner's exact complaint, *"the moving walls are stupid as you can always survive
    /// them by just sticking to one side."* Measurement showed it was worse than the complaint: an
    /// outer lane cleared the kill half-width by 49% of margin, on both walls, every time, and stayed
    /// clear until d = 6,841 m. `wallPhase` is now a pure function of `index` alone — constant, and at
    /// FULL swing, at every distance including inside act one — so the invariant worth pinning is no
    /// longer "zero before act two" but "always full, and still fair": each wall still leaves at
    /// least one of the three lanes open at its full swing (see `Tuning.wallPhaseSwing`).
    func testTheMovingWallSwingIsConstantAndFairEverywhere() async {
        for d in stride(from: 0.0, through: Tuning.actTwoAt, by: 25) {
            XCTAssertEqual(Spawner.intensity(forDistance: d), 0, accuracy: 1e-12,
                           "act two must not start before \(Tuning.actTwoAt) (d=\(d))")
            XCTAssertNil(Spawner.pool(forDistance: d), "act one draws uniformly, with no table (d=\(d))")
        }
        // wallPhase is a pure function of `index` alone — constant across every distance, in act one
        // AND act two, at the full swing (never scaled toward zero by intensity any more).
        for d in stride(from: 0.0, through: 20_000, by: 500) {
            XCTAssertEqual(Patterns.wallPhase(at: d, index: 0), Tuning.wallPhaseSwing, accuracy: 1e-12,
                           "wall 0 must swing full and positive at every distance (d=\(d))")
            XCTAssertEqual(Patterns.wallPhase(at: d, index: 1), -Tuning.wallPhaseSwing, accuracy: 1e-12,
                           "wall 1 must swing full and negative at every distance (d=\(d))")
        }
        // The fairness property the full swing must never break: at most two of the three lanes are
        // ever closed, so a safe answer always exists for both walls.
        let phase0 = Patterns.wallPhase(at: 0, index: 0)
        let phase1 = Patterns.wallPhase(at: 0, index: 1)
        XCTAssertLessThanOrEqual(Spawner.movingWallLanes(phase0).count, 2,
                                  "wall 0 must never close all three lanes at its full swing")
        XCTAssertLessThanOrEqual(Spawner.movingWallLanes(phase1).count, 2,
                                  "wall 1 must never close all three lanes at its full swing")
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

    /// Pattern-availability gates open at the documented distances.
    ///
    /// **Repinned in v2.1 (S-011)** from the old v1.8 distances (260 / 576 / 1,440 / 1,920 / 2,560 m)
    /// to the pulled-forward ladder (150 / 350 / 600 / 900 / 1,200 m — see the ladder block in
    /// `Tuning`). This is the same mechanical repin already applied to
    /// `PatternOrderTests.testTierLadderMonotoneAndRNGCountsPinned`; this file's copy had been missed.
    func testPatternGating() async {
        XCTAssertEqual(Spawner.maxIndex(forDistance: 0), 5)
        XCTAssertEqual(Spawner.maxIndex(forDistance: 149), 5)
        XCTAssertEqual(Spawner.maxIndex(forDistance: 150), 9)         // diff = 0.046875 < 0.109375
        XCTAssertEqual(Spawner.maxIndex(forDistance: 349), 9)         // diff just under 0.109375
        XCTAssertEqual(Spawner.maxIndex(forDistance: 350), 11)        // diff = 0.109375 → rings + overdrive runways
        XCTAssertEqual(Spawner.maxIndex(forDistance: 599), 11)        // diff just under 0.1875
        XCTAssertEqual(Spawner.maxIndex(forDistance: 600), 13)        // diff = 0.1875 → gauntlet + split bars (no moving walls)
        XCTAssertEqual(Spawner.maxIndex(forDistance: 899), 13)        // diff just under 0.28125
        XCTAssertEqual(Spawner.maxIndex(forDistance: 900), 14)        // diff = 0.28125 → moving walls unlock
        XCTAssertEqual(Spawner.maxIndex(forDistance: 1199), 14)       // diff just under 0.375
        XCTAssertEqual(Spawner.maxIndex(forDistance: 1200), Patterns.count) // diff = 0.375 → the chasm unlocks
        XCTAssertEqual(Spawner.maxIndex(forDistance: 6000), Patterns.count)
    }

    /// Moving walls are never selectable before their own tier-five gate.
    ///
    /// **This used to be a World-2-specific carve-out** ("moving walls must never appear at
    /// 800–1,600 m, players are still acclimating"), pinned back when `movingWallMinDiff` was
    /// 1,920 m — safely past World 2's end, so the carve-out and the gate happened to coincide.
    /// v2.1 (S-011) pulled that gate to 900 m ON PURPOSE (see the ladder block in `Tuning`): the
    /// whole point of the move is that moving walls, like everything else in the catalogue, now
    /// arrive inside the first minute — which is inside World 2's 800–1,600 m span. Re-asserting a
    /// grace period past the pattern's own gate would just reintroduce the "last new thing arrives
    /// too late" problem S-011 exists to fix, so the fairness property worth keeping is the gate
    /// itself, not the old World-2 boundary that used to imply it.
    func testMovingWallsAreNeverSelectableBeforeTheirGate() async {
        let gate = Tuning.movingWallMinDiff * Tuning.diffFullAt
        for d in stride(from: 0.0, to: gate, by: 25) {
            XCTAssertLessThan(Spawner.maxIndex(forDistance: d), 14,
                              "moving walls should not be selectable before their gate at \(gate) m (d=\(d))")
        }
        XCTAssertGreaterThanOrEqual(Spawner.maxIndex(forDistance: gate), 14,
                                     "moving walls must be selectable the moment their gate opens")
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
