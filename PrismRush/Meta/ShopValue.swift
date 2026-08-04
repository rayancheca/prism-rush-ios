import Foundation

/// Pure, StoreKit/SwiftUI-free value framing for the Shop (v1.4.3, CODE_REVIEW.md M4/§20.4).
/// `ShopView` and `IAPManager` adapt their StoreKit types into these plain values, so the badge
/// math, the featured rotation, and the store-availability transitions are all unit-testable on
/// Linux — no StoreKit/GameKit needed. Foundation-only; lives in the SPM-compiled layer.

/// Computed value tag for a coin pack (never hardcoded — derived from prices + coin amounts).
enum PackBadge: Equatable, Sendable {
    case none
    case bonus(Int)      // +N% coins-per-currency vs the cheapest pack
    case balancedPick    // the curated mid pack (true by construction, not a fake popularity stat)
    case bestValue       // best coins-per-currency in the grid
}

/// A coin pack reduced to the only fields the value math needs.
struct ShopPack: Equatable, Sendable {
    let id: String
    let coins: Int
    let price: Double
}

enum ShopValue {
    /// Coins per unit of currency (0 when the price is non-positive — pre-load / bad data — so a
    /// missing price can never crown a false BEST VALUE or divide by zero).
    static func coinsPerUnit(_ p: ShopPack) -> Double {
        p.price > 0 ? Double(p.coins) / p.price : 0
    }

    /// Badge for `pack` within `packs` (ordered cheapest-first; `packs.first` is the baseline).
    /// Best coins-per-unit wins `bestValue`; the designated `mediumID` carries `balancedPick`;
    /// any other pack beating the baseline gets its computed `+N% bonus`. The baseline itself and
    /// anything not above it get `none`. Mirrors the original `ShopView.badge` exactly.
    static func badge(for pack: ShopPack, in packs: [ShopPack], mediumID: String) -> PackBadge {
        guard let baseline = packs.first, pack.id != baseline.id,
              let best = packs.max(by: { coinsPerUnit($0) < coinsPerUnit($1) }) else { return .none }
        if pack.id == best.id { return .bestValue }
        if pack.id == mediumID { return .balancedPick }
        let pct = Int((((coinsPerUnit(pack) / max(coinsPerUnit(baseline), 0.001)) - 1) * 100).rounded())
        return pct > 0 ? .bonus(pct) : .none
    }

    /// Today's featured rotation skin: the first non-owned id from a day-seeded shuffle of `pool`;
    /// if every pool skin is owned, `fallback`. Deterministic per day via a UI-local SplitMix64 —
    /// never the run RNG (iron rule 2). Empty pool returns `fallback`.
    static func featuredSkin(daySeed: Int, pool: [String], owned: Set<String>,
                             fallback: String) -> String {
        guard !pool.isEmpty else { return fallback }
        var rng = SplitMix64(seed: UInt64(bitPattern: Int64(daySeed)))
        var shuffled = pool
        for i in (1..<shuffled.count).reversed() { shuffled.swapAt(i, rng.int(0, i)) }
        return shuffled.first { !owned.contains($0) } ?? fallback
    }
}

/// What a coin-spend pack grants, or a Mystery Box rolls. Pure value (no StoreKit) so the catalog,
/// the gacha odds, and the grant math are all unit-testable on Linux.
enum ConsumableGrant: Equatable, Sendable {
    case coins(Int)
    case slowMo(Int)
    case speedUp(Int)
    case shield(Int)
    case headStart(Int)
    case coinSurge(Int)
}

/// A coin-spend shop item — bought with EARNED coins (`ProfileStore.spendCoins`), never StoreKit.
/// Kept out of `IAPCatalog` (which assumes real-money kinds): these are a separate coin economy.
struct CoinSpendItem: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let blurb: String
    let icon: String      // SF Symbol
    let hex: UInt32       // tint
    let cost: Int         // coins
    let grant: ConsumableGrant
}

/// The coin-spend catalogue: power-up packs (top up the pre-run loadout + slow-mo) and the Mystery
/// Box gacha. Pure + Foundation-only; the gacha roll uses a META RNG in `ProfileStore`, never the
/// Core seeded sim (iron rule 2). Odds are exposed here so the shop can be honest (decree 5) and
/// tests can pin them.
enum ShopConsumables {
    static let mysteryBoxID = "mysteryBox"
    static let mysteryBoxCost = 300

    /// The headline prize. **Named rather than retyped, because retyping it is how it went wrong:**
    /// two `ShopView` strings — the card's body copy and its VoiceOver label, so a screen-reader user
    /// got the same wrong number — advertised a "1,200-coin jackpot" against a real 1,400 (S-019).
    /// `mysteryReward` and every piece of shop copy now read this one constant, so the advertised
    /// prize cannot drift from the granted one again.
    static let mysteryJackpotCoins = 1_400

    /// Coin-spend power-up packs (the slow-mo refill the backlog asked for + loadout top-ups).
    static let packs: [CoinSpendItem] = [
        CoinSpendItem(id: "slowMoPack", title: "Slow-Mo Pack", blurb: "+3 slow-mo charges",
                      icon: "hourglass", hex: 0x9BF0FF, cost: 250, grant: .slowMo(3)),
        CoinSpendItem(id: "speedUpPack", title: "Speed-Up Pack", blurb: "+3 speed-up charges",
                      icon: "bolt.fill", hex: 0xFFD23D, cost: 250, grant: .speedUp(3)),
        CoinSpendItem(id: "shieldPack", title: "Shield Pack", blurb: "+3 deployable shields",
                      icon: "shield.lefthalf.filled", hex: 0x00F5FF, cost: 350, grant: .shield(3)),
        CoinSpendItem(id: "headStartPack", title: "Head Start Pack", blurb: "+3 head starts",
                      icon: "bolt.horizontal.fill", hex: 0xFF9F1C, cost: 300, grant: .headStart(3)),
        // **There is deliberately no Coin Surge pack here** (v2.1, S-011 — owner's call).
        //
        // It cost 450 coins for 3 charges, and a charge DOUBLES a run's coin payout. Measured on the
        // pre-v2.1 faucet that was 450 in for **+3,858** out — **8.6× ROI, repeatable, uncapped** —
        // and 17× with the Double Coins IAP on top. You could mint currency with currency, which is
        // what actually made buying a coin pack irrational; the pack SIZES were a red herring
        // (`docs/agent/audits/AUDIT_011_ECONOMY.md` §1.5).
        //
        // The fix is structural rather than a re-price. Pricing it above its own payout would leave
        // a trap item whose safety depends on the faucet never changing again — and the faucet just
        // changed twice in one session. **No coin-spend path may grant a coin multiplier**, so the
        // arbitrage cannot be reintroduced by tuning.
        //
        // **S-012 closed the hole this invariant still had.** The Mystery Box is a 300-COIN SPEND,
        // and it granted a Coin Surge on 8% of rolls — the same shape as the deleted pack, weaker
        // but uncapped, and net-POSITIVE beyond about 15,000 m of run because a surge is valued at
        // the best run you will ever arm it on, not the average one. The band is gone; surges are
        // now earned only, from the level ladder.
    ]

    /// Mystery Box reward for a roll in [0, 1). Pure f(roll), so the odds pin in tests.
    ///
    /// **Re-weighted in S-012, and it was wrong in BOTH directions at once.**
    ///
    /// *Too mean, for almost everybody.* The old table's expected value was 242.7 coins against a
    /// 300-coin price — **−19%** — and re-derived after S-011 deleted the Coin Surge Pack (which is
    /// what the 8% band was being valued at) it was −23%. Decree 5 says no dark patterns, and a box
    /// that takes a fifth of every purchase is at best in tension with that.
    ///
    /// *And simultaneously too generous, for the players who matter least to protect.* A Coin Surge
    /// doubles a whole run's payout and charges bank with no cap, so a deep runner values that 8%
    /// band at their BEST run rather than their average one — the box turns net-positive past a
    /// surged run of roughly 15,000 m. That made the box the last surviving violation of D-026's
    /// structural rule that **no coin-spend path may grant a coin multiplier.**
    ///
    /// Both are fixed by the same edit: the Coin Surge band is gone, and the remaining bands are
    /// weighted so the expected value is the price.
    ///
    ///   0.42 × 200 + 0.22 × 350 + 0.15 × (3 × 83.33) + 0.11 × (2 × 100)
    ///        + 0.07 × 600 + 0.03 × 1,400
    ///     =  84 + 77 + 37.5 + 22 + 42 + 42  =  **304.5** against a 300 cost.
    ///
    /// **S-019 raised the jackpot 2.5% → 3.0% to match what the reveal screen has always claimed.**
    /// `mysteryOdds` below disclosed 3% while this function rolled 2.5%, and the error favoured the
    /// house — App Store guideline 3.1.1 requires disclosed odds to be real. The roll moved up to the
    /// disclosure rather than the disclosure down to the roll: nothing a player already saw becomes a
    /// lie, and nobody's expectation is reduced. **The 600-coin band absorbs the 0.5%** (7.5% → 7.0%),
    /// which is the only bucket that needed to move, because the disclosed table already said 7%
    /// there — so the two tables now agree row-for-row rather than merely summing to the same total.
    /// EV rises 300.5 → 304.5 (+1.3% of price) and the coin-only bands 240.5 → 245, still under the
    /// 300 cost, so the box remains a break-even lottery and not a coin printer.
    ///
    /// Note what that composition says, honestly: the COIN bands alone are 245, i.e. you will
    /// usually get back less money than you spent. The power-up bands are what make the box whole,
    /// and they are 26% of rolls. It is a lottery you break even on, not a coin printer — which,
    /// with unlimited rolls and no cooldown, is the only shape that can be both fair and safe.
    static func mysteryReward(roll: Double) -> ConsumableGrant {
        switch roll {
        case ..<0.42:  return .coins(200)     // 42.0% — the common loss
        case ..<0.64:  return .coins(350)     // 22.0% — a small coin profit
        case ..<0.79:  return .slowMo(3)      // 15.0%
        case ..<0.90:  return .headStart(2)   // 11.0%
        case ..<0.97:  return .coins(600)     //  7.0%
        default:       return .coins(mysteryJackpotCoins)   //  3.0% — jackpot
        }
    }

    /// The honest odds table for the reveal screen (decree 5: show real odds). Best-first; the
    /// percentages match `mysteryReward`'s bands exactly — pinned by
    /// `EconomyTests.testTheDisclosedOddsAreTheRolledOdds`, which is the gate that did not exist
    /// while the two disagreed. (label, percent, tint hex.)
    static let mysteryOdds: [(label: String, pct: Int, hex: UInt32)] = [
        ("1,400 coins — JACKPOT", 3, 0xFFD23D),
        ("600 coins",             7, 0xFFD23D),
        ("Head Start ×2",        11, 0xFF9F1C),
        ("Slow-Mo ×3",           15, 0x9BF0FF),
        ("350 coins",            22, 0xFFD23D),
        ("200 coins",            42, 0xFFD23D),
    ]

    /// Coins still needed to open the box; 0 means affordable.
    ///
    /// Pure, so both CTA states pin in the Linux suite. The view renders from this rather than
    /// re-deriving the comparison itself — the old view knew only `afford: Bool`, which is why it
    /// could dim the button but had no number to show the player (PR-0302).
    static func mysteryBoxShortfall(coins: Int) -> Int { max(0, mysteryBoxCost - coins) }
}

/// Honest store states for the pre-launch window (the former `IAPManager.Availability`).
enum StoreState: Equatable, Sendable {
    case loading        // first load in-flight — shimmer placeholders, no error
    case ready          // full catalog loaded — real prices everywhere
    case notConfigured  // request succeeded but returned zero/partial products (pre-ASC)
    case offline        // request THREW — genuine network/StoreKit failure
}

/// Pure transitions for the store availability machine (the StoreKit calls live in `IAPManager`).
enum StoreAvailability {
    /// State after a SUCCESSFUL product load: a full catalog is `ready`; a zero/partial catalog is
    /// `notConfigured` (pre-ASC reality, not an error).
    static func afterLoad(loadedCount: Int, catalogCount: Int) -> StoreState {
        loadedCount >= catalogCount ? .ready : .notConfigured
    }

    /// State after a THROWN load: a previously-`ready` catalog keeps serving (stale real prices
    /// beat fallbacks; `.ready` never downgrades mid-session); anything else truthfully becomes
    /// `offline` so the RETRY card + backoff engage.
    static func afterThrow(current: StoreState) -> StoreState {
        current == .ready ? .ready : .offline
    }
}
