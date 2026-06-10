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

    /// Highest selectable pattern index + 1, gated by distance (0–9 verbatim from the shipped
    /// code; v1.2 appends split bars at mid difficulty, moving walls stay last/hardest).
    static func maxIndex(forDistance dist: Double) -> Int {
        let diff = min(1, dist / Tuning.diffFullAt)
        if dist < Tuning.earlyDistance { return 5 }
        if diff < Tuning.midDiff { return 9 }
        if diff < Tuning.movingWallMinDiff { return 11 }  // + gauntlet & split bars — no moving walls yet
        return Patterns.count                              // everything, incl. moving walls (index 11)
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
