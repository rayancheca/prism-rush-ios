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
    ///
    /// **Cut 4.3× in S-012 (E7), and the reason is one measurement.** The old ladder paid 10,300
    /// coins across L1→L30, and L30 takes roughly 73–81 minutes of play. Running for those same
    /// 73–81 minutes pays 4,630–6,265 coins on the S-011 faucet. **Levelling was paying 1.6–2.2×
    /// what playing pays** — so the session that made SKILL the largest term in the faucet was
    /// immediately out-earned by a counter that goes up no matter how you play.
    ///
    /// Add the power-up charges (`levelUpCharges` below, 13,050 coins at shop prices before its own
    /// cut) and the L1→L30 giveaway came to 23,350 coins of priceable value against a permanent
    /// catalogue of 83,500 — **28% of the whole game, handed out for levelling**, which is what
    /// undercuts the only sinks that alter play.
    ///
    /// 2,400 total keeps the ladder a real on-ramp — it is still the fastest coins a new player
    /// ever sees, and the shape (a flat early band, a rising middle, a milestone at 30) is
    /// unchanged — while landing at 38–52% of the run faucet over the same stretch instead of 160–220%.
    /// Lifetime total across the ladder: **2,400 coins**.
    static func coinGrant(forLevel n: Int) -> Int {
        switch n {
        case 2...9:   return 25     // 8 levels →   200
        case 10...19: return 60     // 10 levels →  600
        case 20...29: return 120    // 10 levels → 1,200
        case 30:      return 400    // the milestone
        default:      return 0      // level 1 is the start; out-of-range pays nothing
        }
    }

    /// Power-up charges granted for reaching level `n`.
    ///
    /// **Was a flat multiply in `GameView` and is now per-level, which is the point.** The old rule
    /// was `slowMo += 2·levels; speedUp += 2·levels; shield += levels; coinSurge += levels` — 58
    /// slow-mos, 58 speed-ups, 29 shields and 29 Coin Surges by L30, worth 13,050 coins at shop
    /// prices plus an UNBOUNDED coin-surge stack (a surge doubles a run's payout and charges never
    /// expire, so 29 of them are worth whatever your 29 best runs are worth).
    ///
    /// Halving the consumables and putting the surge on a five-level milestone takes the priceable
    /// value to 6,584 and the surges to 6. Expressing it per-LEVEL rather than per-level-UP is what
    /// makes a milestone rule possible at all, and it also fixes a latent bug in the old form: a run
    /// that crossed two levels at once multiplied by the delta, so the grant was correct only by
    /// accident of the bands being flat.
    static func levelUpCharges(forLevel n: Int) -> (slowMo: Int, speedUp: Int, shield: Int, coinSurge: Int) {
        guard n >= 2 else { return (0, 0, 0, 0) }
        return (slowMo: 1,
                speedUp: 1,
                // Every other level, so a shield stays the scarcest of the three — it is the only
                // one that converts directly into surviving a mistake.
                shield: n % 2 == 0 ? 1 : 0,
                // The only source of Coin Surges left in the game now that neither the shop nor the
                // Mystery Box grants one (D-026). Five-level milestones: 6 across the whole ladder.
                coinSurge: n % 5 == 0 ? 1 : 0)
    }

    /// Levels that auto-unlock a character (R1: Pebble L3, Blossom L6, Shard L12, Eclipse L25;
    /// v1.4 roster adds Circuit L8, Nebula L18 — a beat between every original gap).
    /// Single source of truth — `SkinCatalogTests` asserts the catalog's `.level` skins match.
    static let xpUnlockLevels: [Int] = [3, 6, 8, 12, 18, 25]

    /// In-run style coins (the 4th per-death delta in GameView). The doubler multiplies because this
    /// IS currency (unlike XP).
    ///
    /// **Uncapped as of v2.1 (S-011), and it now counts streaks.** It used to be
    /// `min(closes + slicks, 40) * 2` — a hard ceiling of 80 coins a run, which measured out at
    /// about **6% of a payout** while gems carried 76–87% of it. The one term that asked whether the
    /// player played WELL was the one term that could not grow, so the game paid for pickup and not
    /// for play. The owner's call in S-011 was that skill should pay much more.
    ///
    /// `surges` is `GameCore.flowSurges` — one per `Tuning.flowPerSurge` near-misses with no contact
    /// between them. Paying it in currency is what makes a clean risky LINE worth more than the same
    /// number of near-misses scattered across a run: the streak term is superlinear in composure
    /// while the per-event term is linear in volume. Together they are the game's greed lever, and
    /// they are the only part of the faucet a player can raise without simply running further.
    static func styleCoins(closes: Int, slicks: Int, surges: Int, multiplier: Int) -> Int {
        ((closes + slicks) * Tuning.styleCoinRate + surges * Tuning.flowSurgeCoins) * multiplier
    }

    /// World-purchase price ladder (v1.4): the worlds tab shows ALL 12 cards; locked ones are
    /// buyable outright with coins. `worldPrices[i - 1]` is world `i` (1-based — world 0 is free).
    /// Escalating so early skips stay accessible against the ~2.6k/day casual faucet while deep
    /// skips remain savings goals. Total sink across the ladder: 59,400 coins.
    static let worldPrices: [Int] = [
        400, 800, 1_400, 2_200, 3_200, 4_400, 5_800, 7_400, 9_200, 11_200, 13_400,
    ]

    /// Coin price to buy starting world `index` outright (0 = the free starting world). The first 11
    /// rungs use the authored ladder; deeper worlds (the evolved cycles, v1.6) escalate linearly so
    /// buying ever-deeper checkpoints stays a meaningful savings goal instead of dead-ending.
    static let worldPriceStepBeyondLadder = 2_000
    static func worldPrice(_ index: Int) -> Int {
        guard index >= 1 else { return 0 }
        if index <= worldPrices.count { return worldPrices[index - 1] }
        return worldPrices[worldPrices.count - 1] + (index - worldPrices.count) * worldPriceStepBeyondLadder
    }
}
