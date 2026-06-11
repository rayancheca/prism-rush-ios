import StoreKit
#if canImport(UIKit)
import UIKit
#endif

/// StoreKit 2 wrapper: loads products, runs purchases with verification, grants entitlements to the
/// `ProfileStore`, and restores non-consumables. Works against `Products.storekit` locally and the
/// real store once the products exist in App Store Connect.
///
/// v1.4.1 — the load surface tells the truth about WHY prices are missing (`availability`):
/// `notConfigured` (request SUCCEEDED, zero/partial catalog — the permanent pre-ASC reality on a
/// real device) is a quiet footnote, never an error banner; only a THROWN request is `offline`,
/// and only `offline` auto-retries (exponential backoff, 60 s cap). `notConfigured` re-checks
/// exactly once per foreground / Shop open — no retry spam against a store that isn't set up yet.
///
/// Errors are never swallowed silently: `lastError` carries a user-presentable message for the
/// most recent failed load / purchase / restore, and the Shop surfaces it inline (ready state)
/// or as a friendly toast (pre-launch states).
@MainActor
@Observable
final class IAPManager {
    /// Honest store states for the pre-launch window.
    enum Availability: Equatable, Sendable {
        case loading        // first load in-flight — shimmer placeholders, no error
        case ready          // full catalog loaded — real prices everywhere
        case notConfigured  // request succeeded but returned zero/partial products (pre-ASC)
        case offline        // request THREW — genuine network/StoreKit failure
    }

    static let shared = IAPManager()

    private(set) var products: [Product] = []
    private(set) var isLoading = false
    /// User-presentable message for the most recent store failure (nil when the last op succeeded).
    private(set) var lastError: String?
    /// True once a `loadProducts()` round-trip has finished (distinguishes "loading" from "failed").
    private(set) var hasLoaded = false
    /// What the Shop should render right now (see `Availability`).
    private(set) var availability: Availability = .loading
    @ObservationIgnored private var updatesTask: Task<Void, Never>?
    @ObservationIgnored private var retryTask: Task<Void, Never>?
    @ObservationIgnored private var retryAttempt = 0
    @ObservationIgnored private var observingForeground = false

    /// Offline auto-retry backoff cap (seconds): 2 → 4 → 8 → 16 → 32 → 60, then stays at 60.
    private static let retryCapSeconds: UInt64 = 60

    func start() {
        if updatesTask == nil { updatesTask = listenForTransactions() }
        #if canImport(UIKit)
        if !observingForeground {
            observingForeground = true
            // One quiet re-check per app foreground — the moment the products go live in ASC is
            // exactly when the player next returns, not something worth polling for.
            NotificationCenter.default.addObserver(
                forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshIfUnavailable() }
            }
        }
        #endif
        Task {
            await loadProducts()
            await restoreEntitlements()
        }
    }

    func loadProducts() async {
        guard !isLoading else { return }
        isLoading = true
        if !hasLoaded { availability = .loading }
        defer { isLoading = false; hasLoaded = true }
        do {
            let loaded = try await Product.products(for: IAPCatalog.allIDs)
            products = loaded.sorted { $0.price < $1.price }
            retryTask?.cancel(); retryTask = nil; retryAttempt = 0
            // A SUCCESSFUL response with a zero/partial catalog means the IAPs don't (fully)
            // exist in App Store Connect yet — pre-launch reality, not an error. No banner.
            availability = products.count >= IAPCatalog.products.count ? .ready : .notConfigured
            if availability == .ready { lastError = nil }
        } catch {
            // A THROW is a genuine network/StoreKit failure. Keep any previously-loaded catalog
            // (stale real prices beat fallbacks) and back off before retrying automatically.
            if products.isEmpty { availability = .offline }
            lastError = "Couldn't reach the App Store. \(error.localizedDescription)"
            scheduleBackoffRetry()
        }
    }

    /// One background reload when the store is not (yet) available — fired on app foreground and
    /// on Shop open ONLY. `notConfigured` never retries on a timer (no spam against a store that
    /// isn't set up); `offline` already has its backoff, this just adds the user-visible moments.
    func refreshIfUnavailable() {
        guard availability == .notConfigured || availability == .offline, !isLoading else { return }
        Task { await loadProducts() }
    }

    /// Manual RETRY (offline card): cancel any pending backoff wait and reload immediately.
    func retryNow() {
        retryTask?.cancel(); retryTask = nil
        Task { await loadProducts() }
    }

    /// Offline-only exponential backoff: one pending retry at a time; success cancels it.
    private func scheduleBackoffRetry() {
        guard availability == .offline else { return }
        retryAttempt = min(retryAttempt + 1, 6)
        let delay = min(Self.retryCapSeconds, UInt64(1) << retryAttempt)
        retryTask?.cancel()
        retryTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: delay * 1_000_000_000)
            guard let self, !Task.isCancelled else { return }
            await self.loadProducts()
        }
    }

    func storeProduct(_ id: String) -> Product? { products.first { $0.id == id } }

    /// Localized price if StoreKit has loaded it, else the catalog fallback.
    func displayPrice(_ id: String) -> String {
        storeProduct(id)?.displayPrice ?? (IAPCatalog.product(id)?.fallbackPrice ?? "")
    }

    /// Numeric price for value math (the Shop's computed badges): live StoreKit price when
    /// loaded, else nil (callers fall back to `IAPProduct.fallbackValue`).
    func priceValue(_ id: String) -> Double? {
        storeProduct(id).map { NSDecimalNumber(decimal: $0.price).doubleValue }
    }

    /// Whether a tap on this product can reach StoreKit right now (false pre-ASC / offline).
    func isPurchasable(_ id: String) -> Bool { storeProduct(id) != nil }

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
