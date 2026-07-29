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
        CoinSpendItem(id: "coinSurgePack", title: "Coin Surge Pack", blurb: "+3 coin surges",
                      icon: "dollarsign.circle.fill", hex: 0xFFD23D, cost: 450, grant: .coinSurge(3)),
    ]

    /// Mystery Box reward for a roll in [0, 1). Weighted, honest, with a jackpot — the player can
    /// lose a little on coins-only common rolls but the consumable/jackpot upside keeps it fair
    /// (decree 5: no dark patterns). Pure f(roll), so the odds pin in tests.
    static func mysteryReward(roll: Double) -> ConsumableGrant {
        switch roll {
        case ..<0.40: return .coins(200)    // 40% — common (a small loss vs the 300 cost)
        case ..<0.62: return .coins(400)    // 22% — coin profit
        case ..<0.78: return .slowMo(2)     // 16%
        case ..<0.90: return .headStart(1)  // 12%
        case ..<0.98: return .coinSurge(1)  //  8%
        default:      return .coins(1200)   //  2% — jackpot
        }
    }

    /// The honest odds table for the reveal screen (decree 5: show real odds). Best-first; the
    /// percentages match `mysteryReward`'s bands exactly. (label, percent, tint hex.)
    static let mysteryOdds: [(label: String, pct: Int, hex: UInt32)] = [
        ("1,200 coins — JACKPOT", 2, 0xFFD23D),
        ("Coin Surge ×1",         8, 0xFFD23D),
        ("Head Start ×1",        12, 0xFF9F1C),
        ("Slow-Mo ×2",           16, 0x9BF0FF),
        ("400 coins",            22, 0xFFD23D),
        ("200 coins",            40, 0xFFD23D),
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
