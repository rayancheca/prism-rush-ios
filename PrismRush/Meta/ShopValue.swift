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
