import Foundation

/// Fills the track ahead of the player with patterns, gating difficulty by distance and
/// shrinking the inter-pattern gap as the run heats up. Renderer-agnostic and deterministic.
struct Spawner {
    /// Absolute distance up to which patterns have been placed.
    var cursor: Double = 60

    /// Index of the most recently placed pattern (anti-repeat reroll); -1 = none yet. Lives in the
    /// spawner so it resets with it — deterministic for a given seed.
    var lastIdx: Int = -1

    /// Reused scratch buffer so `fill` allocates nothing per tick once warmed.
    private var scratch: [SpawnCmd] = []

    /// Inter-pattern gap as a function of difficulty (lerps 11 → 5). Pure; tested for monotonicity.
    static func gap(forDistance dist: Double) -> Double {
        let diff = min(1, dist / Tuning.diffFullAt)
        return lerp(Tuning.gapMax, Tuning.gapMin, diff)
    }

    /// Highest selectable pattern index + 1 — the v1.3 five-tier prefix ladder (iron rule 4:
    /// every tier is a prefix of the catalogue; moving walls stay LAST).
    static func maxIndex(forDistance dist: Double) -> Int {
        let diff = min(1, dist / Tuning.diffFullAt)
        if dist < Tuning.earlyDistance { return 5 }        // 0–260 m: teach (patterns 0–4)
        if diff < Tuning.midEarlyDiff { return 9 }         // 260–576 m: + zigzag/mixed/pickup/double bar
        if diff < Tuning.midDiff { return 11 }             // 576–1440 m: + rings & overdrive runways
        if diff < Tuning.movingWallMinDiff { return 13 }   // 1440–1920 m: + gauntlet & split bars
        return Patterns.count                              // 1920 m+: full catalogue incl. moving walls
    }

    /// Place patterns until the cursor reaches `horizon`. `emit` receives each spawn command.
    mutating func fill(to horizon: Double, dist: Double, rng: inout SplitMix64, emit: (SpawnCmd) -> Void) {
        if scratch.capacity < 64 { scratch.reserveCapacity(64) }
        while cursor < horizon {
            let maxIdx = Spawner.maxIndex(forDistance: dist)
            var idx = rng.int(0, maxIdx - 1)
            // Anti-repeat (v1.3): one bounded reroll when we draw the same pattern again — repeats
            // stay possible, just half as likely. Conditional extra RNG call → layoutVersion 2.
            if idx == lastIdx { idx = rng.int(0, maxIdx - 1) }
            lastIdx = idx
            scratch.removeAll(keepingCapacity: true)
            let len = Patterns.run(idx, base: cursor, rng: &rng, out: &scratch)
            for cmd in scratch { emit(cmd) }
            cursor += len + Spawner.gap(forDistance: dist)
        }
    }
}
