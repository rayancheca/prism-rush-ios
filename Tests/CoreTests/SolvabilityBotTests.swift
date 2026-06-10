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

    func testGreedyBotSurvives200Seeds() {
        let targetDistance = 6_000.0
        let seedCount = 200
        let maxTicks = 200_000   // safety bound (~1700 s sim) — real runs finish far sooner

        var failures: [Failure] = []

        for s in 0..<seedCount {
            // Spread the seeds widely so they exercise distinct pattern streams.
            let seed = UInt64(s) &* 0x9E37_79B9_7F4A_7C15 &+ 0x1234_5678
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
            let laneStr = e.kind == .bar ? "ALL" : (e.kind == .movingTall ? "mv(ph=\(String(format: "%.2f", e.phase)))" : "\(e.lane)")
            return String(format: "    %@ lane=%@ arrival=%+.2f", "\(e.kind)", laneStr, arrival)
        }.joined(separator: "\n")
    }
}
