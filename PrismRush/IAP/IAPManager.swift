import StoreKit

/// StoreKit 2 wrapper: loads products, runs purchases with verification, grants entitlements to the
/// `ProfileStore`, and restores non-consumables. Works against `Products.storekit` locally and the
/// real store once the products exist in App Store Connect.
@MainActor
@Observable
final class IAPManager {
    static let shared = IAPManager()

    private(set) var products: [Product] = []
    private(set) var isLoading = false
    @ObservationIgnored private var updatesTask: Task<Void, Never>?

    func start() {
        if updatesTask == nil { updatesTask = listenForTransactions() }
        Task {
            await loadProducts()
            await restoreEntitlements()
        }
    }

    func loadProducts() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let loaded = try await Product.products(for: IAPCatalog.allIDs)
            products = loaded.sorted { $0.price < $1.price }
        } catch {
            products = []
        }
    }

    func storeProduct(_ id: String) -> Product? { products.first { $0.id == id } }

    /// Localized price if StoreKit has loaded it, else the catalog fallback.
    func displayPrice(_ id: String) -> String {
        storeProduct(id)?.displayPrice ?? (IAPCatalog.product(id)?.fallbackPrice ?? "")
    }

    @discardableResult
    func purchase(_ id: String) async -> Bool {
        guard let product = storeProduct(id) else { return false }
        do {
            switch try await product.purchase() {
            case .success(let verification):
                guard case .verified(let transaction) = verification else { return false }
                IAPCatalog.apply(transaction.productID, to: ProfileStore.shared)
                await transaction.finish()
                return true
            case .userCancelled, .pending:
                return false
            @unknown default:
                return false
            }
        } catch {
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
