import XCTest
@testable import PrismRush

/// Flow surge (v1.3): every 3rd CLOSE/SLICK detonates a score bonus + a 10-gem fountain in the
/// player's lane — derived purely from state, consuming ZERO RNG. These tests pin the cadence,
/// the resets, the escalation level, and (critically) determinism + spawn-stream isolation.
@MainActor
final class FlowTests: XCTestCase {

    /// Start a clean run with the spawner parked.
    private func cleanCore(seed: UInt64 = 2) -> GameCore {
        let core = GameCore(seed: seed)
        core.startRun(seed: seed)
        core.debugClearTrack()
        return core
    }

    /// Manufacture one SLICK: slide, then let a bar cross the player plane on the next tick.
    private func slick(_ core: GameCore) {
        core.slide()
        core.debugSpawn(.bar(d: core.distance - Tuning.obstacleZHalf - 0.01))
        core.tick(Tuning.tickDt)
    }

    func testSurgeEveryThirdWithFountainInLane() async {
        let core = cleanCore()
        var surges: [Int] = []
        core.onFX = { if case let .flowSurge(level, _) = $0 { surges.append(level) } }
        let bonus0 = core.bonus

        slick(core); slick(core)
        XCTAssertEqual(core.flowStreak, 2)
        XCTAssertTrue(surges.isEmpty, "no surge before the 3rd near-miss")
        XCTAssertTrue(core.activeGems.isEmpty)

        slick(core)
        XCTAssertEqual(core.flowStreak, 0, "the surge consumes the streak (§C.1: since last surge/reset)")
        XCTAssertEqual(surges, [1], "exactly one surge on the 3rd near-miss")
        XCTAssertEqual(core.bonus - bonus0, 3 * Tuning.nearMissBonus + Tuning.flowSurgeScore)

        // Fountain: fountainGems gems, in the PLAYER's lane, lead 26, spacing 1.7 — no RNG anywhere.
        XCTAssertEqual(core.activeGems.count, Tuning.fountainGems)
        let ds = core.activeGems.map(\.d).sorted()
        XCTAssertEqual(ds[0], core.distance + Tuning.fountainLead, accuracy: 1e-9)
        for i in 1..<ds.count {
            XCTAssertEqual(ds[i] - ds[i - 1], Tuning.fountainSpacing, accuracy: 1e-9)
        }
        for g in core.activeGems {
            XCTAssertEqual(g.lane, core.laneIndex, "fountain sprays into the player's lane")
            XCTAssertEqual(g.baseY, 0.8, accuracy: 1e-9)
        }

        core.advance(realDt: Tuning.tickDt)
        XCTAssertEqual(core.snapshot.flowStreak, core.flowStreak, "snapshot mirrors the streak")
    }

    func testStreakResetsOnShieldAbsorbAndDeath() async {
        // Shield absorb breaks the flow…
        let core = cleanCore(seed: 6)
        var surges = 0
        core.onFX = { if case .flowSurge = $0 { surges += 1 } }
        core.debugSpawn(.shield(d: core.distance + 3, lane: 1))
        var guardTicks = 0
        while !core.shield && guardTicks < 600 { core.tick(Tuning.tickDt); guardTicks += 1 }
        XCTAssertTrue(core.shield, "scenario setup: shield collected")

        slick(core); slick(core)
        XCTAssertEqual(core.flowStreak, 2)
        core.debugSpawn(.tall(d: core.distance + 0.5, lane: 1))
        core.tick(Tuning.tickDt)
        XCTAssertEqual(core.mode, .play, "shield absorbed the hit")
        XCTAssertEqual(core.flowStreak, 0, "an absorbed hit still breaks the flow")

        // …and the NEXT 3 near-misses surge again from zero (which then consumes the streak).
        slick(core); slick(core); slick(core)
        XCTAssertEqual(surges, 1)
        XCTAssertEqual(core.flowStreak, 0, "surged on the 3rd — streak consumed")

        // Death zeroes it too.
        let core2 = cleanCore(seed: 7)
        slick(core2); slick(core2)
        XCTAssertEqual(core2.flowStreak, 2)
        core2.debugForceDie()
        XCTAssertEqual(core2.flowStreak, 0, "death breaks the flow")
    }

    /// Surges on the 3rd, 6th and 9th near-miss carry escalating levels 1, 2, 3 (audio/visuals
    /// key off it); the streak itself wraps to 0 at every surge (§C.1 — since last surge/reset).
    func testSurgeLevelsEscalate() async {
        let core = cleanCore(seed: 8)
        var surges: [Int] = []
        core.onFX = { if case let .flowSurge(level, _) = $0 { surges.append(level) } }
        for n in 1...9 {
            slick(core)
            // Space the slicks so spent bars recycle (capBar) — the player may well run through
            // earlier fountains meanwhile; that is normal play and must not disturb the cadence.
            for _ in 0..<80 { core.tick(Tuning.tickDt) }
            XCTAssertEqual(core.flowStreak, n % Tuning.flowPerSurge)
        }
        XCTAssertEqual(surges, [1, 2, 3], "every 3rd near-miss, with 1-based escalation levels")
    }

    /// (a) Same seed + same deterministic inputs → identical run hash, fountains included.
    /// (b) Different input trace on the same seed → IDENTICAL obstacle/pattern stream: surges and
    ///     fountains consume zero RNG, so the seeded spawn stream cannot be perturbed by play.
    func testDeterminismAndPatternStreamIsolation() async {
        let seed: UInt64 = 0xF10F_F10F
        let a1 = Self.autopilotRun(seed: seed, ticks: 14_000, extraJumps: false)
        let a2 = Self.autopilotRun(seed: seed, ticks: 14_000, extraJumps: false)
        XCTAssertGreaterThan(a1.surges, 0, "the bot must actually surge during the soak window")
        XCTAssertEqual(a1.hash, a2.hash, "same seed + same inputs → identical run, fountains included")
        XCTAssertEqual(a1.surges, a2.surges)

        let b = Self.autopilotRun(seed: seed, ticks: 14_000, extraJumps: true)
        XCTAssertGreaterThan(b.extraJumps, 0, "trace B must genuinely differ (safe jumps injected)")
        XCTAssertGreaterThan(b.surges, 0)
        let n = min(a1.obstacles.count, b.obstacles.count)
        XCTAssertGreaterThan(n, 60, "soak must cover a meaningful number of patterns")
        for i in 0..<n {
            XCTAssertEqual(a1.obstacles[i].kind, b.obstacles[i].kind,
                           "obstacle #\(i) kind diverged — spawn stream is NOT input-isolated")
            XCTAssertEqual(a1.obstacles[i].lane, b.obstacles[i].lane, "obstacle #\(i) lane diverged")
            XCTAssertEqual(a1.obstacles[i].d, b.obstacles[i].d, accuracy: 0.6,
                           "obstacle #\(i) drifted beyond fill-tick jitter")
        }
    }

    private struct RunTrace {
        var hash: UInt64
        var surges: Int
        var extraJumps: Int
        var obstacles: [(kind: EntityKind, lane: Int, d: Double)]
    }

    /// Drive a deterministic autopilot run, optionally injecting provably-safe extra jumps (only
    /// when grounded with no obstacle within 30 units) to vary the input trace without dying.
    private static func autopilotRun(seed: UInt64, ticks: Int, extraJumps: Bool) -> RunTrace {
        let core = GameCore(seed: 1)
        core.startRun(seed: seed)
        var trace = RunTrace(hash: 1_469_598_103_934_665_603, surges: 0, extraJumps: 0, obstacles: [])
        core.onFX = { if case .flowSurge = $0 { trace.surges += 1 } }
        func fold(_ x: UInt64) { trace.hash = (trace.hash ^ x) &* 1_099_511_628_211 }
        var maxSeenId = 0
        var sinceJump = 0
        for _ in 0..<ticks {
            guard core.mode == .play else { break }
            Autopilot.drive(core)
            if extraJumps {
                sinceJump += 1
                if sinceJump >= 600 && core.grounded {
                    let nearest = core.activeObstacles.map { $0.d - core.distance }
                        .filter { $0 > -2 }.min() ?? .infinity
                    if nearest > 30 { core.jump(); trace.extraJumps += 1; sinceJump = 0 }
                }
            }
            core.tick(Tuning.tickDt)
            // Log freshly spawned obstacles in spawn order (entity ids are strictly increasing).
            var fresh = core.activeObstacles.filter { $0.id > maxSeenId }
            if !fresh.isEmpty {
                fresh.sort { $0.id < $1.id }
                for e in fresh { trace.obstacles.append((e.kind, e.lane, e.d)) }
                maxSeenId = fresh.last!.id
            }
            fold(core.distance.bitPattern)
            fold(core.px.bitPattern)
            fold(UInt64(bitPattern: Int64(core.score)))
            fold(UInt64(bitPattern: Int64(core.gemCount)))
            fold(UInt64(bitPattern: Int64(core.flowStreak)))
            fold(core.boostT.bitPattern)
            fold(UInt64(core.activeGems.count))
        }
        return trace
    }
}
