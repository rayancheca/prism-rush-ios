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
    /// layoutVersion 9 = v1.8 — THE CHASM (PR-0450). The catalogue grows to 15 and a SIXTH tier
    /// opens at 2,560 m, so `Spawner.maxIndex` returns 15 rather than 14 past that point and every
    /// draw from there on differs. The act-two pool tables also grow (21/28/37 slots), which shifts
    /// `rng.int(0, slots − 1)` for every seed past 3,200 m. Below 2,560 m the ladder still returns
    /// 5 / 9 / 11 / 13 / 14, so act one's *selection* is byte-identical again — and the shared track
    /// still reshuffles, for the same reason as v8.
    /// layoutVersion 10 = v1.9 — THE WARDENS (PR-0457). Unlike every bump before it, the seeded
    /// spawn stream is byte-identical: the encounter draws from its own stream derived from the run
    /// seed, and `Spawner.fill` still makes exactly the same `rng` calls in exactly the same order.
    /// What changes is which of those spawns reach the deck — obstacles and boost pads inside a
    /// Warden arena (the first 600 m of every third world) are filtered at `GameCore.apply`. A
    /// layout version is a promise about the whole run, not about the RNG, so the same seed no
    /// longer means the same track and the shared daily must reshuffle.
    /// layoutVersion 11 = v2.1 — THE LADDER, PULLED FORWARD (S-011), plus the moving-wall fix.
    /// Two spawn-path changes in one bump because either alone would have cost the same reshuffle.
    /// (a) Every tier gate moves: 260/576/1,440/1,920/2,560 m → 150/350/600/900/1,200 m, so
    /// `Spawner.maxIndex` returns a different ceiling at nearly every distance under 2,560 m and the
    /// `rng.int(0, maxIdx − 1)` draw differs from ~150 m onward for every seed. This is the first
    /// bump since v7 that changes act one's *selection*, not merely its entities.
    /// (b) `Patterns.wallPhase` now emits ±`wallPhaseSwing` at every distance instead of 0 below
    /// 3,200 m, which changes pattern 13's emitted phase, the lanes `Spawner.movingWallLanes` reports
    /// closed, and therefore its safe-entry breadcrumb and greed line. Zero extra RNG calls; the
    /// track still differs, and a layout version is a promise about the whole run.
    static func seed(year: Int, month: Int, day: Int, layoutVersion: UInt64 = 11) -> UInt64 {
        let folded = UInt64(year * 10_000 + month * 100 + day)
        var mix = SplitMix64(seed: folded ^ tag ^ (layoutVersion << 48))
        return mix.next()
    }
}
