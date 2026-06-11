import XCTest
@testable import PrismRush

@MainActor
final class DifficultyTests: XCTestCase {

    /// The inter-pattern gap shrinks monotonically from 11 → 5 as distance grows.
    func testGapMonotonicDown() async {
        var prev = Double.infinity
        for d in stride(from: 0.0, through: 6400, by: 25) {
            let g = Spawner.gap(forDistance: d)
            XCTAssertLessThanOrEqual(g, prev + 1e-9, "gap must not increase at d=\(d)")
            XCTAssertGreaterThanOrEqual(g, Tuning.gapMin - 1e-9)
            XCTAssertLessThanOrEqual(g, Tuning.gapMax + 1e-9)
            prev = g
        }
        XCTAssertEqual(Spawner.gap(forDistance: 0), Tuning.gapMax, accuracy: 1e-9)
        XCTAssertEqual(Spawner.gap(forDistance: Tuning.diffFullAt), Tuning.gapMin, accuracy: 1e-9)
    }

    /// Pattern-availability gates open at the documented distances (v1.3 five-tier ladder).
    func testPatternGating() async {
        XCTAssertEqual(Spawner.maxIndex(forDistance: 0), 5)
        XCTAssertEqual(Spawner.maxIndex(forDistance: 259), 5)
        XCTAssertEqual(Spawner.maxIndex(forDistance: 260), 9)        // diff = 0.08 < 0.18
        XCTAssertEqual(Spawner.maxIndex(forDistance: 575), 9)        // diff just under 0.18
        XCTAssertEqual(Spawner.maxIndex(forDistance: 576), 11)       // diff = 0.18 → rings + overdrive runways
        XCTAssertEqual(Spawner.maxIndex(forDistance: 1439), 11)      // diff just under 0.45
        XCTAssertEqual(Spawner.maxIndex(forDistance: 1440), 13)      // diff = 0.45 → gauntlet + split bars (no moving walls)
        XCTAssertEqual(Spawner.maxIndex(forDistance: 1919), 13)      // diff just under 0.6
        XCTAssertEqual(Spawner.maxIndex(forDistance: 1920), Patterns.count) // diff = 0.6 → moving walls unlock
        XCTAssertEqual(Spawner.maxIndex(forDistance: 6000), Patterns.count)
    }

    /// Fairness: World 2 (800–1600 m) must never spawn moving walls — players are still acclimating.
    func testWorld2HasNoMovingWalls() async {
        for d in stride(from: 800.0, through: 1599.0, by: 50) {
            XCTAssertLessThan(Spawner.maxIndex(forDistance: d), Patterns.count,
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
