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
    /// anti-repeat reroll). layoutVersion 3 = v1.5 (Super Sneakers re-bands pattern 7's pickup roll).
    /// layoutVersion 4 = v1.6 (a guaranteed power-up cadence adds deterministic pickups to the track).
    /// layoutVersion 5 = v1.6 (path-aware coin trail — gap breadcrumbs + a pattern-7 gem line — add
    /// more deterministic gems; zero RNG, but the shared track gains entities, so the seed reshuffles).
    /// layoutVersion 6 = v1.6 (gauntlet fairness — pattern 11's bar→triple-low gap widened 9→27u +
    /// a free-lane coin trail; zero RNG, but moved/added entities reshuffle the shared track).
    /// layoutVersion 7 = v1.6 (anti-repeat widened to the last TWO patterns — varies the seeded
    /// selection stream — plus a continuous coin trail through pattern 8's double bars).
    /// layoutVersion 8 = v1.7 — THE SECOND ACT (PR-0400) + RISK-PRICED GEMS (PR-0414), landed
    /// together in one bump because both touch the spawn path and two bumps would buy nothing.
    /// Past 3,200 m the pattern draw moves to a weighted table (the same single `rng.int` call, but
    /// the slot resolves through a mix that sheds breather beats with depth), the gap continues
    /// 5 → 4, moving walls swing off centre, and a second gem cluster is hung in a lane each
    /// pattern closes. Act one's *selection* is byte-identical to v7; the shared track still
    /// reshuffles, because a layout version is a promise about the whole run.
    static func seed(year: Int, month: Int, day: Int, layoutVersion: UInt64 = 8) -> UInt64 {
        let folded = UInt64(year * 10_000 + month * 100 + day)
        var mix = SplitMix64(seed: folded ^ tag ^ (layoutVersion << 48))
        return mix.next()
    }
}
