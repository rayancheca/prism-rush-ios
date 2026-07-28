import XCTest
@testable import PrismRush

/// The spawner's core invariant: every pattern it can place is survivable with the legal moveset.
/// A deterministic greedy autopilot must clear 6,000 distance on 200 distinct seeds with zero deaths.
/// Any failing seed prints the obstacle window around the death for diagnosis.
@MainActor
final class SolvabilityBotTests: XCTestCase {

    private struct Failure {
        let seed: UInt64
        let distance: Double
        let lane: Int
        let window: String
    }

    func testGreedyBotSurvives200Seeds() async {
        botSoak(seedCount: 200, targetDistance: 6_000, seedSalt: 0x1234_5678)
    }

    /// Deeper soak: fewer seeds than the 6,000 m sweep, but to 12,000 m — split bars, chrono
    /// slow-mo pickups and moving walls all run at full density (difficulty caps at 3,200 m)
    /// across several world loops. Widened 10 → 64 seeds (still ~1 s; CODE_REVIEW.md §20.6) so the
    /// full-density tail is sampled far more broadly while staying cheap.
    func testGreedyBotSurvivesDeepRuns() async {
        botSoak(seedCount: 64, targetDistance: 12_000, seedSalt: 0xDEE9_5EED)
    }

    /// A solvability proof that never meets the hazard is not a proof.
    ///
    /// The tier-six chasm is the only obstacle the bot must JUMP with a window on both sides, and it
    /// only unlocks at 2,560 m — well inside the 6,000 m sweep, but nothing above actually checks
    /// that. This test closes that hole: it replays the same seeds the soak uses and counts the
    /// chasms the bot is actually driven across, so a future change that quietly stops spawning them
    /// (a tier gate moved, a pool table edited, a cap set to 0) turns the green soak red here instead
    /// of leaving it green and meaningless.
    func testTheSoakActuallyDrivesTheBotAcrossChasms() async {
        var crossed = 0
        var seedsWithAChasm = 0
        for s in 0..<24 {
            let seed = UInt64(s) &* 0x9E37_79B9_7F4A_7C15 &+ 0x1234_5678
            let core = GameCore(seed: 1)
            core.startRun(seed: seed)
            var seen = Set<Int>()
            var ticks = 0
            while core.mode == .play && core.distance < 6_000 && ticks < 400_000 {
                Autopilot.drive(core)
                core.tick(Tuning.tickDt)
                ticks += 1
                // Count a chasm once its far rim is behind the player — i.e. actually survived.
                for o in core.activeObstacles where o.kind == .chasm {
                    if core.distance > o.d + Tuning.chasmHalfLength { seen.insert(o.id) }
                }
            }
            XCTAssertEqual(core.mode, .play, "seed \(seed) died — the soak should have caught this")
            if !seen.isEmpty { seedsWithAChasm += 1 }
            crossed += seen.count
        }
        XCTAssertEqual(seedsWithAChasm, 24, "every 6,000 m run must meet the tier-six pattern")
        XCTAssertGreaterThan(crossed, 24 * 3,
                             "the chasm should be a recurring beat past 2,560 m, not a rarity")
    }

    /// v1.3 containment invariant (geometric, no sim): the overdrive runway emits ZERO obstacles,
    /// and even the LATEST possible pad trigger followed by a full boost at the hard speed cap
    /// dies inside the pattern (5.1 + 1.0 × 36 = 41.1 < 48). This is why the boost can never
    /// coexist with an obstacle, and why the Autopilot needs zero changes for it.
    func testOverdriveRunwayContainmentInvariant() async {
        for base in [600.0, 1_600, 3_200, 8_000] {
            for seed: UInt64 in [1, 99, 0xABCD] {
                var rng = SplitMix64(seed: seed)
                var out: [SpawnCmd] = []
                let len = Patterns.run(10, base: base, rng: &rng, out: &out)
                var padD: Double?
                for cmd in out {
                    switch cmd {
                    case .gem:
                        break
                    case let .boostPad(d, _):
                        XCTAssertNil(padD, "runway must place exactly one pad")
                        padD = d
                    default:
                        XCTFail("overdrive runway emitted a non-gem, non-pad spawn: \(cmd)")
                    }
                }
                guard let pad = padD else { XCTFail("runway placed no pad at base \(base)"); continue }
                let latestTrigger = (pad - base) + Tuning.pickupZHalf   // 4 + 1.1 = 5.1
                XCTAssertLessThan(latestTrigger + Tuning.boostDuration * Tuning.boostSpeedMax, len,
                                  "worst-case boost travel must end inside the runway")
            }
        }
    }

    /// Force-feed the bot a boost pad mid-procedural-run, then require 200 m of normal spawning
    /// after the trigger with zero deaths: the bot's leads already scale with effectiveSpeed, and
    /// the containment invariant keeps obstacles out of the boost window.
    func testBotSurvivesForcedBoostIntoNextPattern() async {
        for s in 0..<5 {
            let seed = UInt64(s) &* 0x9E37_79B9_7F4A_7C15 &+ 0xB005_7AD5
            let core = GameCore(seed: 1)
            core.startRun(seed: seed)
            var boosted = false
            var boostedAt = 0.0
            core.onFX = { if case .boostStarted = $0 { boosted = true } }

            var ticks = 0
            var nextPadTick = 240
            while core.mode == .play && ticks < 200_000 {
                Autopilot.drive(core)
                if !boosted && ticks >= nextPadTick {
                    // Drop a pad right under the bot's lane; if it crosses airborne it just
                    // misses, so retry until one actually triggers (pads are never lethal).
                    core.debugSpawn(.boostPad(d: core.distance + 3, lane: core.laneIndex))
                    nextPadTick = ticks + 600
                }
                core.tick(Tuning.tickDt)
                ticks += 1
                if boosted && boostedAt == 0 { boostedAt = core.distance }
                if boosted && core.distance > boostedAt + 200 { break }
            }
            XCTAssertTrue(boosted, "seed \(seed): a forced pad must eventually trigger")
            XCTAssertEqual(core.mode, .play,
                           "seed \(seed): bot died within 200 m of a forced boost\n\(Self.dumpWindow(core))")
        }
    }

    private func botSoak(seedCount: Int, targetDistance: Double, seedSalt: UInt64) {
        let maxTicks = 400_000   // safety bound (~3300 s sim) — real runs finish far sooner

        var failures: [Failure] = []

        for s in 0..<seedCount {
            // Spread the seeds widely so they exercise distinct pattern streams.
            let seed = UInt64(s) &* 0x9E37_79B9_7F4A_7C15 &+ seedSalt
            let core = GameCore(seed: 1)
            core.startRun(seed: seed)

            var ticks = 0
            while core.mode == .play && core.distance < targetDistance && ticks < maxTicks {
                Autopilot.drive(core)
                core.tick(Tuning.tickDt)
                ticks += 1
            }

            if core.mode == .over {
                failures.append(Failure(
                    seed: seed,
                    distance: core.distance,
                    lane: core.laneIndex,
                    window: Self.dumpWindow(core)
                ))
            } else if core.distance < targetDistance {
                failures.append(Failure(
                    seed: seed, distance: core.distance, lane: core.laneIndex,
                    window: "STALLED (hit maxTicks without dying or reaching target)"
                ))
            }
        }

        if !failures.isEmpty {
            var msg = "\n\(failures.count)/\(seedCount) seeds failed the solvability bot:\n"
            for f in failures.prefix(12) {
                msg += String(format: "  seed=%llu died at d=%.1f lane=%d\n%@\n", f.seed, f.distance, f.lane, f.window)
            }
            XCTFail(msg)
        }
    }

    /// Dump every obstacle within ±12 units of the player, sorted by arrival, for diagnosis.
    private static func dumpWindow(_ c: GameCore) -> String {
        let near = c.activeObstacles
            .map { (e: CoreEntity) -> (Double, CoreEntity) in (e.d - c.distance, e) }
            .filter { abs($0.0) <= 12 }
            .sorted { $0.0 < $1.0 }
        if near.isEmpty { return "    (no obstacles within ±12 — likely a moving-wall timing miss)" }
        return near.map { (arrival, e) in
            let laneStr: String
            switch e.kind {
            case .bar: laneStr = "ALL"
            case .splitBar: laneStr = "open=\(e.lane)"
            case .movingTall: laneStr = "mv(ph=\(String(format: "%.2f", e.phase)))"
            default: laneStr = "\(e.lane)"
            }
            return String(format: "    %@ lane=%@ arrival=%+.2f", "\(e.kind)", laneStr, arrival)
        }.joined(separator: "\n")
    }
}
