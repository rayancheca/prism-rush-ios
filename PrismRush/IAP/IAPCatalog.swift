import Foundation

/// The in-app-purchase product list and what each grants. Product IDs must match the entries you
/// create in App Store Connect (and in `Products.storekit` for local testing).
enum IAPKind: Sendable {
    case coins(Int)        // consumable
    case doubleCoins       // non-consumable: permanent 2× coin earning
    case skin(String)      // non-consumable: unlocks + equips a premium skin
}

struct IAPProduct: Identifiable, Sendable {
    let id: String
    let title: String
    let blurb: String
    let fallbackPrice: String   // shown if StoreKit hasn't loaded real pricing yet
    let fallbackValue: Double   // numeric twin of fallbackPrice — value badges stay computable pre-load
    let kind: IAPKind
    var isConsumable: Bool { if case .coins = kind { return true } else { return false } }
    var coinAmount: Int { if case .coins(let n) = kind { return n } else { return 0 } }
}

enum IAPCatalog {
    /// The first-purchase offer SKU (shown only while `profile.totalIAPPurchases == 0`).
    static let starterID = "com.rayancheca.prismrush.starter"

    static let products: [IAPProduct] = [
        // — the original five (IDs FROZEN — the ASC table must match character-for-character) —
        IAPProduct(id: "com.rayancheca.prismrush.coins.small",  title: "Pouch of Coins",  blurb: "1,200 coins",  fallbackPrice: "$0.99", fallbackValue: 0.99, kind: .coins(1_200)),
        IAPProduct(id: "com.rayancheca.prismrush.coins.medium", title: "Bag of Coins",    blurb: "7,000 coins",  fallbackPrice: "$4.99", fallbackValue: 4.99, kind: .coins(7_000)),
        IAPProduct(id: "com.rayancheca.prismrush.coins.large",  title: "Vault of Coins",  blurb: "16,000 coins", fallbackPrice: "$9.99", fallbackValue: 9.99, kind: .coins(16_000)),
        // Blurb states RUN payout deliberately (PR-0411): `Profile.coinMultiplier` is consumed at
        // exactly one site (GameView.swift:696), so the daily reward, chest, level grant, mission
        // claim and challenge tier are NOT doubled. "2× coins, forever" was false by the app's own
        // `totalCoinsEarned` bookkeeping. Keep this wording in sync with App Store Connect.
        IAPProduct(id: "com.rayancheca.prismrush.doublecoins",  title: "Double Coins",    blurb: "Every run pays 2× coins. Forever.", fallbackPrice: "$2.99", fallbackValue: 2.99, kind: .doubleCoins),
        IAPProduct(id: "com.rayancheca.prismrush.skin.aurora",  title: "Aurora Skin",     blurb: "Exclusive character", fallbackPrice: "$1.99", fallbackValue: 1.99, kind: .skin("aurora")),
        // — v1.4.1 additions —
        IAPProduct(id: starterID,                               title: "Starter Bundle",  blurb: "3,000 coins",  fallbackPrice: "$1.99", fallbackValue: 1.99, kind: .coins(3_000)),
        IAPProduct(id: "com.rayancheca.prismrush.coins.mega",   title: "Crate of Coins",  blurb: "40,000 coins", fallbackPrice: "$19.99", fallbackValue: 19.99, kind: .coins(40_000)),
    ]

    static var allIDs: [String] { products.map(\.id) }
    static func product(_ id: String) -> IAPProduct? { products.first { $0.id == id } }

    /// Apply a *just-purchased* product (grants consumables too). `transactionID` is the
    /// StoreKit transaction id: EVERY branch routes through
    /// `ProfileStore.applyOncePerTransaction`, so a `Transaction.updates` redelivery (app died
    /// between the saved grant and `finish()`) can never re-pay base coins, re-bump
    /// `totalIAPPurchases`, or re-pay the one-time +50% bonus (v1.4.1 review).
    @MainActor
    static func apply(_ id: String, transactionID: UInt64? = nil, to store: ProfileStore) {
        guard let kind = product(id)?.kind else { return }
        switch kind {
        case .coins(let n):
            store.grantCoinPack(n, transactionID: transactionID)
        case .doubleCoins:
            store.applyOncePerTransaction(transactionID) {
                $0.doubleCoins = true; $0.ownedProducts.insert(id); $0.totalIAPPurchases += 1
            }
        case .skin(let s):
            store.applyOncePerTransaction(transactionID) {
                $0.ownedSkins.insert(s); $0.ownedProducts.insert(id); $0.selectedSkin = s; $0.totalIAPPurchases += 1
            }
        }
    }

    /// Re-apply a restored *non-consumable* entitlement (never re-grants consumable coins, never
    /// bumps the purchase counter, never touches the first-purchase bonus).
    @MainActor
    static func restore(_ id: String, to store: ProfileStore) {
        guard let kind = product(id)?.kind else { return }
        switch kind {
        case .coins:
            break
        case .doubleCoins:
            store.mutate { $0.doubleCoins = true; $0.ownedProducts.insert(id) }
        case .skin(let s):
            store.mutate { $0.ownedSkins.insert(s); $0.ownedProducts.insert(id) }
        }
    }
}
