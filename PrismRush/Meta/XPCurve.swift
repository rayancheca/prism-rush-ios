import Foundation

/// Result of folding a run into XP/levels: what the game-over panel animates (XP bar fill,
/// level-up burst, coin grant, character-unlock tease). Plain value type — GameView holds the
/// per-run instance as model state (G3: never re-derived from the live store).
struct LevelUpResult: Equatable, Sendable {
    let xpGained: Int
    let levelBefore: Int
    let levelAfter: Int
    let coinsGranted: Int        // sum of banded grants for every newly-paid level (watermarked)
    let unlockedLevels: [Int]    // crossed levels that are character-unlock levels (R1)
}

/// The v1.3 progression curve: per-run XP, levels 1...30, banded level-up coin grants, the
/// XP-unlock roster levels, and the in-run style-coin helper. Every function is pure — `xp(for:)`
/// reads ONLY the `RunSummary` (never `Profile`), so IAP `doubleCoins` can never inflate XP and
/// the whole ladder pins exactly in Linux tests.
enum XPCurve {
    static let maxLevel = 30

    /// Cumulative XP required to BE level (index + 1); `cumulativeXP[0] == 0` (level 1).
    /// Closed form `xpToNext(n) = 150 * (n + 1)` → L2 = 300, L10 = 8,100, L30 = 69,600.
    static let cumulativeXP: [Int] = {
        var total = 0
        return (1...maxLevel).map { n in defer { total += 150 * (n + 1) }; return total }
    }()

    /// Current level for a lifetime XP total (1...maxLevel; negative totals clamp to level 1).
    static func level(for totalXP: Int) -> Int {
        (cumulativeXP.lastIndex { $0 <= max(0, totalXP) } ?? 0) + 1
    }

    /// Progress within the current level: (XP earned into it, XP the level needs in total).
    /// At the level cap there is no next level — returns (0, 0); render the bar/ring full.
    static func xpIntoLevel(for totalXP: Int) -> (current: Int, needed: Int) {
        let xp = max(0, totalXP)
        let lvl = level(for: xp)
        guard lvl < maxLevel else { return (0, 0) }
        let base = cumulativeXP[lvl - 1]
        return (xp - base, cumulativeXP[lvl] - base)
    }

    /// XP for one finished run — pure f(RunSummary), clamped 0...2,000 so a marathon run is
    /// bounded (~4 early levels, <1 level past L15). Distance is the engagement floor, style is
    /// the deliberate skill premium, and the world term uses the crossed-THIS-RUN delta
    /// (`startWorld` zeroes checkpoint head-starts, mirroring the coin rule).
    static func xp(for s: RunSummary) -> Int {
        let distanceXP = Int(s.distance / 10)                              // 1 XP per 10 m survived
        let gemXP = s.gems * 2                                             // routing/greed
        let styleXP = (s.nearMissCloses + s.slicks) * 5                    // CLOSE/SLICK premium
        let comboXP = s.bestMult * 10                                      // multiplier mastery
        let worldXP = max(0, (s.worldsCrossed - 1) - s.startWorld) * 25    // worlds crossed this run
        return min(max(distanceXP + gemXP + styleXP + comboXP + worldXP, 0), 2_000)
    }

    /// Banded level-up coin grant — paid once, ever, watermarked by `Profile.xpLevelRewarded`.
    /// Lifetime total across the ladder: 10,300 coins.
    static func coinGrant(forLevel n: Int) -> Int {
        switch n {
        case 2...9:   return 100
        case 10...19: return 250
        case 20...29: return 500
        case 30:      return 2_000
        default:      return 0    // level 1 is the start; out-of-range pays nothing
        }
    }

    /// Levels that auto-unlock a character (R1: Pebble L3, Blossom L6, Shard L12, Eclipse L25).
    /// Single source of truth — `SkinCatalogTests` asserts the catalog's `.level` skins match.
    static let xpUnlockLevels: [Int] = [3, 6, 12, 25]

    /// In-run style coins (the 4th per-death delta in GameView): 2 coins per CLOSE/SLICK, hard
    /// cap 40 events/run; the doubler multiplies because this IS currency (unlike XP).
    static func styleCoins(closes: Int, slicks: Int, multiplier: Int) -> Int {
        min(closes + slicks, 40) * 2 * multiplier
    }
}
