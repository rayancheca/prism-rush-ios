import Foundation

/// Deterministic seed for the shared daily-challenge run: every player on the same calendar date
/// (and layout version) plays the identical track. Pure core — no `Date`. The meta layer derives
/// `year`/`month`/`day` in UTC (so the whole world rolls over together) and MUST bump
/// `layoutVersion` whenever spawner / pattern / RNG-consumption behaviour changes, otherwise
/// "same seed" silently stops meaning "same track" across app versions.
enum DailyChallenge {
    /// Domain-separation tag ("PRISMDAY") so other date-shaped integers can never collide.
    private static let tag: UInt64 = 0x5052_4953_4D44_4159

    /// Fold y*10000 + m*100 + d with the tag and version, then run one SplitMix64 step so
    /// consecutive dates land in unrelated parts of the seed space.
    /// layoutVersion 2 = v1.3 (ballistic gem arc, ring/overdrive patterns, catalogue reorder,
    /// anti-repeat reroll) — one bump covers every spawn-stream change in the release.
    static func seed(year: Int, month: Int, day: Int, layoutVersion: UInt64 = 2) -> UInt64 {
        let folded = UInt64(year * 10_000 + month * 100 + day)
        var mix = SplitMix64(seed: folded ^ tag ^ (layoutVersion << 48))
        return mix.next()
    }
}
