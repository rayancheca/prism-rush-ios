import XCTest
@testable import PrismRush

/// Pins the pure Shop value math + store-availability transitions extracted from `ShopView` /
/// `IAPManager` (v1.4.3, CODE_REVIEW.md M4/§20.4). All Linux-runnable — no StoreKit needed.
final class ShopValueTests: XCTestCase {

    // Cheapest-first grid: small(cpu 1200) · med(1400) · large(1600) · mega(2000, best).
    private let small = ShopPack(id: "small", coins: 1_200, price: 1.0)
    private let med   = ShopPack(id: "med",   coins: 7_000, price: 5.0)
    private let large = ShopPack(id: "large", coins: 16_000, price: 10.0)
    private let mega  = ShopPack(id: "mega",  coins: 40_000, price: 20.0)
    private var grid: [ShopPack] { [small, med, large, mega] }

    // MARK: coinsPerUnit

    func testCoinsPerUnitDividesCoinsByPrice() {
        XCTAssertEqual(ShopValue.coinsPerUnit(small), 1_200, accuracy: 0.001)
        XCTAssertEqual(ShopValue.coinsPerUnit(mega), 2_000, accuracy: 0.001)
    }

    func testCoinsPerUnitGuardsNonPositivePrice() {
        // A missing/zero/negative price must never divide by zero or crown a false BEST VALUE.
        XCTAssertEqual(ShopValue.coinsPerUnit(ShopPack(id: "x", coins: 5_000, price: 0)), 0)
        XCTAssertEqual(ShopValue.coinsPerUnit(ShopPack(id: "x", coins: 5_000, price: -1)), 0)
    }

    // MARK: badge selection

    func testBaselineGetsNoBadge() {
        XCTAssertEqual(ShopValue.badge(for: small, in: grid, mediumID: "med"), .none)
    }

    func testBestCoinsPerUnitWinsBestValue() {
        XCTAssertEqual(ShopValue.badge(for: mega, in: grid, mediumID: "med"), .bestValue)
    }

    func testDesignatedMediumGetsBalancedPick() {
        // med is not the best value, so it carries the curated tag.
        XCTAssertEqual(ShopValue.badge(for: med, in: grid, mediumID: "med"), .balancedPick)
    }

    func testAboveBaselineGetsComputedBonusPercent() {
        // large: 1600 cpu vs baseline 1200 → (1600/1200 − 1)·100 = 33.3 → 33.
        XCTAssertEqual(ShopValue.badge(for: large, in: grid, mediumID: "med"), .bonus(33))
    }

    func testBelowBaselineGetsNoBadge() {
        // A pack worse than the cheapest baseline (and neither best nor medium) earns nothing.
        let bad = ShopPack(id: "bad", coins: 1_000, price: 1.0)   // cpu 1000 < baseline 1200
        let packs = [small, bad, mega]
        XCTAssertEqual(ShopValue.badge(for: bad, in: packs, mediumID: "med"), .none)
    }

    func testBestValueOutranksBalancedPick() {
        // If the medium pack is ALSO the best value, bestValue wins (best check comes first).
        let cheapMega = ShopPack(id: "med", coins: 40_000, price: 1.0)   // medium id, but top cpu
        let packs = [small, cheapMega]
        XCTAssertEqual(ShopValue.badge(for: cheapMega, in: packs, mediumID: "med"), .bestValue)
    }

    func testSinglePackAndEmptyGridYieldNone() {
        XCTAssertEqual(ShopValue.badge(for: small, in: [small], mediumID: "med"), .none)
        XCTAssertEqual(ShopValue.badge(for: small, in: [], mediumID: "med"), .none)
    }

    // MARK: featured rotation

    func testFeaturedSkinIsDeterministicPerDay() {
        let pool = ["aurora", "midas", "toxic", "mono"]
        let a = ShopValue.featuredSkin(daySeed: 4242, pool: pool, owned: [], fallback: "coins.medium")
        let b = ShopValue.featuredSkin(daySeed: 4242, pool: pool, owned: [], fallback: "coins.medium")
        XCTAssertEqual(a, b, "same day must yield the same featured skin")
        XCTAssertTrue(pool.contains(a), "an unowned day pick must come from the pool")
    }

    func testFeaturedSkinSkipsOwned() {
        let pool = ["aurora", "midas", "toxic", "mono"]
        let pick = ShopValue.featuredSkin(daySeed: 7, pool: pool, owned: [], fallback: "coins.medium")
        // Owning the natural pick forces a different, still-unowned skin.
        let next = ShopValue.featuredSkin(daySeed: 7, pool: pool, owned: [pick], fallback: "coins.medium")
        XCTAssertNotEqual(next, pick)
        XCTAssertFalse([pick].contains(next), "must skip the owned skin")
    }

    func testFeaturedSkinFallsBackWhenAllOwnedOrEmpty() {
        let pool = ["aurora", "midas"]
        XCTAssertEqual(ShopValue.featuredSkin(daySeed: 1, pool: pool, owned: ["aurora", "midas"],
                                              fallback: "coins.medium"), "coins.medium")
        XCTAssertEqual(ShopValue.featuredSkin(daySeed: 1, pool: [], owned: [],
                                              fallback: "coins.medium"), "coins.medium")
    }

    // MARK: store availability transitions

    func testAfterLoadFullCatalogIsReady() {
        XCTAssertEqual(StoreAvailability.afterLoad(loadedCount: 7, catalogCount: 7), .ready)
        XCTAssertEqual(StoreAvailability.afterLoad(loadedCount: 9, catalogCount: 7), .ready)
    }

    func testAfterLoadPartialOrEmptyIsNotConfigured() {
        XCTAssertEqual(StoreAvailability.afterLoad(loadedCount: 3, catalogCount: 7), .notConfigured)
        XCTAssertEqual(StoreAvailability.afterLoad(loadedCount: 0, catalogCount: 7), .notConfigured)
    }

    func testAfterThrowKeepsReadyButDropsEverythingElseToOffline() {
        // A previously-full catalog keeps serving on a transient throw…
        XCTAssertEqual(StoreAvailability.afterThrow(current: .ready), .ready)
        // …anything less truthfully becomes offline so the RETRY card + backoff engage.
        XCTAssertEqual(StoreAvailability.afterThrow(current: .loading), .offline)
        XCTAssertEqual(StoreAvailability.afterThrow(current: .notConfigured), .offline)
        XCTAssertEqual(StoreAvailability.afterThrow(current: .offline), .offline)
    }

    // MARK: - Mystery Box shortfall (PR-0302)

    /// The view knew only `afford: Bool`, so it could dim the OPEN button but had no number to
    /// show — a dead end with no reason and no route. This is the number it now renders.
    func testMysteryBoxShortfallIsTheGapToTheCost() {
        XCTAssertEqual(ShopConsumables.mysteryBoxShortfall(coins: 0), ShopConsumables.mysteryBoxCost)
        XCTAssertEqual(ShopConsumables.mysteryBoxShortfall(coins: 100), 200)
        XCTAssertEqual(ShopConsumables.mysteryBoxShortfall(coins: ShopConsumables.mysteryBoxCost), 0)
        XCTAssertEqual(ShopConsumables.mysteryBoxShortfall(coins: 5_000), 0, "never negative")
    }
}
