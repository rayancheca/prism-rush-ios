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
            let gap = Spawner.gap(forDistance: dist)
            // Path-aware coin trail (v1.6): a short gem breadcrumb leads through the empty gap into
            // THIS pattern's safe entry lane, so following the coins is always a takeable route
            // (Subway-style). Pure of the pattern's spawns + fixed spacing → consumes ZERO RNG (the
            // seeded stream + PatternOrderTests are untouched; the added gems ride layoutVersion 5).
            let lane = Spawner.safeEntryLane(scratch, base: cursor)
            var gd = cursor - gap + 1.0
            while gd < cursor - 0.5 {
                emit(.gem(d: gd, lane: lane, y: 0.8))
                gd += 1.7
            }
            for cmd in scratch { emit(cmd) }
            cursor += len + gap
        }
    }

    /// A lane that's laterally SAFE to enter `base` at (no tall / moving wall / split-bar cover in the
    /// first ~8.5 units — lows/bars are jumped or slid, so they don't block a lane sideways). Prefers
    /// the centre; falls back to centre if (rarely) all three read blocked. Pure → deterministic.
    static func safeEntryLane(_ spawns: [SpawnCmd], base: Double) -> Int {
        var blocked = [false, false, false]
        let zone = base + 8.5
        for cmd in spawns {
            switch cmd {
            case let .tall(d, lane) where d <= zone:
                blocked[lane] = true
            case let .movingTall(d, _) where d <= zone:
                blocked[1] = true                       // phase-0 wall crosses CENTRE; outers stay clear
            case let .splitBar(d, openLane) where d <= zone:
                for l in 0..<3 where l != openLane { blocked[l] = true }
            default:
                break
            }
        }
        for lane in [1, 0, 2] where !blocked[lane] { return lane }
        return 1
    }
}
