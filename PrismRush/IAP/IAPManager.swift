import StoreKit

/// StoreKit 2 wrapper: loads products, runs purchases with verification, grants entitlements to the
/// `ProfileStore`, and restores non-consumables. Works against `Products.storekit` locally and the
/// real store once the products exist in App Store Connect.
///
/// Errors are never swallowed silently: `lastError` carries a user-presentable message for the
/// most recent failed load / purchase / restore, and the Shop surfaces it inline with a retry path.
@MainActor
@Observable
final class IAPManager {
    static let shared = IAPManager()

    private(set) var products: [Product] = []
    private(set) var isLoading = false
    /// User-presentable message for the most recent store failure (nil when the last op succeeded).
    private(set) var lastError: String?
    /// True once a `loadProducts()` round-trip has finished (distinguishes "loading" from "failed").
    private(set) var hasLoaded = false
    @ObservationIgnored private var updatesTask: Task<Void, Never>?

    func start() {
        if updatesTask == nil { updatesTask = listenForTransactions() }
        Task {
            await loadProducts()
            await restoreEntitlements()
        }
    }

    func loadProducts() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false; hasLoaded = true }
        do {
            let loaded = try await Product.products(for: IAPCatalog.allIDs)
            products = loaded.sorted { $0.price < $1.price }
            lastError = products.isEmpty ? "Store returned no products." : nil
        } catch {
            products = []
            lastError = "Couldn't reach the store. \(error.localizedDescription)"
        }
    }

    func storeProduct(_ id: String) -> Product? { products.first { $0.id == id } }

    /// Localized price if StoreKit has loaded it, else the catalog fallback.
    func displayPrice(_ id: String) -> String {
        storeProduct(id)?.displayPrice ?? (IAPCatalog.product(id)?.fallbackPrice ?? "")
    }

    @discardableResult
    func purchase(_ id: String) async -> Bool {
        // If products never loaded (offline at launch), retry the load before failing the tap.
        if products.isEmpty { await loadProducts() }
        guard let product = storeProduct(id) else {
            lastError = "That product isn't available right now."
            return false
        }
        do {
            switch try await product.purchase() {
            case .success(let verification):
                guard case .verified(let transaction) = verification else {
                    lastError = "Purchase couldn't be verified. You have not been charged twice — try Restore Purchases."
                    return false
                }
                IAPCatalog.apply(transaction.productID, to: ProfileStore.shared)
                await transaction.finish()
                lastError = nil
                return true
            case .userCancelled:
                return false   // a cancellation is not an error worth showing
            case .pending:
                lastError = "Purchase is pending approval — it will unlock automatically."
                return false
            @unknown default:
                lastError = "Purchase didn't complete."
                return false
            }
        } catch {
            lastError = "Purchase failed. \(error.localizedDescription)"
            return false
        }
    }

    /// Restore non-consumables. Returns true on success (used for Settings-row feedback).
    @discardableResult
    func restorePurchases() async -> Bool {
        do {
            try await AppStore.sync()   // re-fetch entitlements from the store (may prompt sign-in)
            await restoreEntitlements()
            lastError = nil
            return true
        } catch {
            lastError = "Restore failed. \(error.localizedDescription)"
            return false
        }
    }

    func restoreEntitlements() async {
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result {
                IAPCatalog.restore(transaction.productID, to: ProfileStore.shared)
            }
        }
    }

    private func listenForTransactions() -> Task<Void, Never> {
        Task { [weak self] in
            for await result in Transaction.updates {
                guard self != nil, case .verified(let transaction) = result else { continue }
                IAPCatalog.apply(transaction.productID, to: ProfileStore.shared)
                await transaction.finish()
            }
        }
    }
}
