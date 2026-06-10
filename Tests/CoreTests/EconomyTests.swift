import XCTest
@testable import PrismRush

@MainActor
final class EconomyTests: XCTestCase {

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12) -> Date {
        var c = DateComponents(); c.year = y; c.month = m; c.day = d; c.hour = h
        return Calendar.current.date(from: c)!
    }

    // MARK: daily reward + streak (F1/F2)

    func testDailyRewardFirstClaim() {
        let store = ProfileStore(testing: Profile())
        XCTAssertTrue(store.dailyRewardAvailable(now: date(2026, 6, 10)))
        let r = store.claimDailyReward(now: date(2026, 6, 10))
        XCTAssertEqual(r?.streak, 1)
        XCTAssertEqual(r?.coins, 100)
        XCTAssertEqual(store.profile.coins, 100)
        XCTAssertNil(store.claimDailyReward(now: date(2026, 6, 10, 18)), "can't claim twice in one day")
    }

    func testDailyStreakIncrementsNextDay() {
        let store = ProfileStore(testing: Profile())
        _ = store.claimDailyReward(now: date(2026, 6, 10))           // day 1 → 100
        let r2 = store.claimDailyReward(now: date(2026, 6, 11))      // day 2 → 150
        XCTAssertEqual(r2?.streak, 2)
        XCTAssertEqual(r2?.coins, 150)
    }

    func testDailyStreakResetsAfterGap() {
        let store = ProfileStore(testing: Profile())
        _ = store.claimDailyReward(now: date(2026, 6, 10))
        _ = store.claimDailyReward(now: date(2026, 6, 11))
        let r = store.claimDailyReward(now: date(2026, 6, 14))       // 2-day gap → reset to streak 1
        XCTAssertEqual(r?.streak, 1)
        XCTAssertEqual(r?.coins, 100)
    }

    func testDailyRewardCapsAtMaxTier() {
        let store = ProfileStore(testing: Profile())
        XCTAssertEqual(store.dailyReward(forStreak: 7), 1000)
        XCTAssertEqual(store.dailyReward(forStreak: 99), 1000)
    }

    // MARK: free timed chest (F1)

    func testFreeChestTiming() {
        let store = ProfileStore(testing: Profile())
        let t0 = date(2026, 6, 10, 12)
        XCTAssertTrue(store.chestReady(now: t0), "never opened → ready")
        XCTAssertEqual(store.openFreeChest(now: t0, reward: 100), 100)
        XCTAssertEqual(store.profile.coins, 100)

        let t10 = t0.addingTimeInterval(10 * 60)
        XCTAssertFalse(store.chestReady(now: t10))
        XCTAssertNil(store.openFreeChest(now: t10, reward: 100))
        XCTAssertEqual(Int(store.secondsUntilChest(now: t10)), 20 * 60)

        XCTAssertTrue(store.chestReady(now: t0.addingTimeInterval(30 * 60)), "ready again after 30 min")
    }

    func testSpendAndAddCoins() {
        let store = ProfileStore(testing: Profile())
        store.addCoins(500)
        XCTAssertTrue(store.spendCoins(200))
        XCTAssertEqual(store.profile.coins, 300)
        XCTAssertFalse(store.spendCoins(1000), "can't overspend")
        XCTAssertEqual(store.profile.coins, 300)
    }

    // MARK: revive (F3)

    func testReviveResumesPlayWithGrace() {
        let core = GameCore(seed: 1)
        core.startRun(seed: 1)
        core.debugForceDie()
        XCTAssertEqual(core.mode, .over)
        core.revive()
        XCTAssertEqual(core.mode, .play)
        XCTAssertEqual(core.revivesUsed, 1)
        XCTAssertTrue(core.shield, "revive grants a one-hit grace shield")
        XCTAssertEqual(core.laneIndex, 1, "player re-centred")
    }

    // MARK: profile schema resilience (G5 + decoder)

    func testProfileDecodesLegacyJSONWithoutWiping() throws {
        // An old save: has the removed `powerUpLevels`, lacks the new daily/chest fields.
        let legacy = #"{"coins":1234,"selectedSkin":"ember","ownedSkins":["default","ember"],"powerUpLevels":{"shield":2},"maxWorldReached":4}"#
        let data = legacy.data(using: .utf8)!
        let p = try JSONDecoder().decode(Profile.self, from: data)
        XCTAssertEqual(p.coins, 1234)
        XCTAssertEqual(p.selectedSkin, "ember")
        XCTAssertEqual(p.maxWorldReached, 4)
        XCTAssertEqual(p.loginStreak, 0, "missing new field defaults, not throws")
        XCTAssertNil(p.lastChestOpen)
    }
}
