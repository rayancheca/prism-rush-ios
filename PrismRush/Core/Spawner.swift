import Foundation

/// Fills the track ahead of the player with patterns, gating difficulty by distance and
/// shrinking the inter-pattern gap as the run heats up. Renderer-agnostic and deterministic.
struct Spawner {
    /// Absolute distance up to which patterns have been placed.
    var cursor: Double = 60

    /// Reused scratch buffer so `fill` allocates nothing per tick once warmed.
    private var scratch: [SpawnCmd] = []

    /// Inter-pattern gap as a function of difficulty (lerps 11 → 5). Pure; tested for monotonicity.
    static func gap(forDistance dist: Double) -> Double {
        let diff = min(1, dist / Tuning.diffFullAt)
        return lerp(Tuning.gapMax, Tuning.gapMin, diff)
    }

    /// Highest selectable pattern index + 1, gated by distance (verbatim from the shipped code).
    static func maxIndex(forDistance dist: Double) -> Int {
        let diff = min(1, dist / Tuning.diffFullAt)
        if dist < Tuning.earlyDistance { return 5 }
        return diff < Tuning.midDiff ? 9 : Patterns.count
    }

    /// Place patterns until the cursor reaches `horizon`. `emit` receives each spawn command.
    mutating func fill(to horizon: Double, dist: Double, rng: inout SplitMix64, emit: (SpawnCmd) -> Void) {
        if scratch.capacity < 64 { scratch.reserveCapacity(64) }
        while cursor < horizon {
            let maxIdx = Spawner.maxIndex(forDistance: dist)
            let idx = rng.int(0, maxIdx - 1)
            scratch.removeAll(keepingCapacity: true)
            let len = Patterns.run(idx, base: cursor, rng: &rng, out: &scratch)
            for cmd in scratch { emit(cmd) }
            cursor += len + Spawner.gap(forDistance: dist)
        }
    }
}
