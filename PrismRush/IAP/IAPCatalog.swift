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
    let kind: IAPKind
    var isConsumable: Bool { if case .coins = kind { return true } else { return false } }
}

enum IAPCatalog {
    static let products: [IAPProduct] = [
        IAPProduct(id: "com.rayancheca.prismrush.coins.small",  title: "Pouch of Coins",  blurb: "1,200 coins",  fallbackPrice: "$0.99", kind: .coins(1_200)),
        IAPProduct(id: "com.rayancheca.prismrush.coins.medium", title: "Bag of Coins",    blurb: "7,000 coins",  fallbackPrice: "$4.99", kind: .coins(7_000)),
        IAPProduct(id: "com.rayancheca.prismrush.coins.large",  title: "Vault of Coins",  blurb: "16,000 coins", fallbackPrice: "$9.99", kind: .coins(16_000)),
        IAPProduct(id: "com.rayancheca.prismrush.doublecoins",  title: "Double Coins",    blurb: "Earn 2× coins, forever", fallbackPrice: "$2.99", kind: .doubleCoins),
        IAPProduct(id: "com.rayancheca.prismrush.skin.aurora",  title: "Aurora Skin",     blurb: "Exclusive character", fallbackPrice: "$1.99", kind: .skin("aurora")),
    ]

    static var allIDs: [String] { products.map(\.id) }
    static func product(_ id: String) -> IAPProduct? { products.first { $0.id == id } }

    /// Apply a *just-purchased* product (grants consumables too).
    @MainActor
    static func apply(_ id: String, to store: ProfileStore) {
        guard let kind = product(id)?.kind else { return }
        switch kind {
        case .coins(let n):
            store.addCoins(n)
        case .doubleCoins:
            store.mutate { $0.doubleCoins = true; $0.ownedProducts.insert(id) }
        case .skin(let s):
            store.mutate { $0.ownedSkins.insert(s); $0.ownedProducts.insert(id); $0.selectedSkin = s }
        }
    }

    /// Re-apply a restored *non-consumable* entitlement (never re-grants consumable coins).
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
