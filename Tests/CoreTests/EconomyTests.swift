import XCTest
@testable import PrismRush

@MainActor
final class EconomyTests: XCTestCase {

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12) -> Date {
        var c = DateComponents(); c.year = y; c.month = m; c.day = d; c.hour = h
        return Calendar.current.date(from: c)!
    }

    // MARK: daily reward + streak (F1/F2)

    func testDailyRewardFirstClaim() async {
        let store = ProfileStore(testing: Profile())
        XCTAssertTrue(store.dailyRewardAvailable(now: date(2026, 6, 10)))
        let r = store.claimDailyReward(now: date(2026, 6, 10))
        XCTAssertEqual(r?.streak, 1)
        XCTAssertEqual(r?.coins, 100)
        XCTAssertEqual(store.profile.coins, 100)
        XCTAssertNil(store.claimDailyReward(now: date(2026, 6, 10, 18)), "can't claim twice in one day")
    }

    func testDailyStreakIncrementsNextDay() async {
        let store = ProfileStore(testing: Profile())
        _ = store.claimDailyReward(now: date(2026, 6, 10))           // day 1 → 100
        let r2 = store.claimDailyReward(now: date(2026, 6, 11))      // day 2 → 150
        XCTAssertEqual(r2?.streak, 2)
        XCTAssertEqual(r2?.coins, 150)
    }

    func testDailyStreakResetsAfterGap() async {
        let store = ProfileStore(testing: Profile())
        _ = store.claimDailyReward(now: date(2026, 6, 10))
        _ = store.claimDailyReward(now: date(2026, 6, 11))
        let r = store.claimDailyReward(now: date(2026, 6, 14))       // 2-day gap → reset to streak 1
        XCTAssertEqual(r?.streak, 1)
        XCTAssertEqual(r?.coins, 100)
    }

    func testDailyRewardCapsAtMaxTier() async {
        let store = ProfileStore(testing: Profile())
        XCTAssertEqual(store.dailyReward(forStreak: 7), 1000)
        XCTAssertEqual(store.dailyReward(forStreak: 99), 1000)
    }

    // MARK: free timed chest (F1)

    func testFreeChestTiming() async {
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

    func testSpendAndAddCoins() async {
        let store = ProfileStore(testing: Profile())
        store.addCoins(500)
        XCTAssertTrue(store.spendCoins(200))
        XCTAssertEqual(store.profile.coins, 300)
        XCTAssertFalse(store.spendCoins(1000), "can't overspend")
        XCTAssertEqual(store.profile.coins, 300)
    }

    // MARK: world purchases (v1.4 — the worlds tab shows ALL cards, locked ones buyable)

    func testUnlockWorldSpendsAndUnlocksIndividually() async {
        let store = ProfileStore(testing: Profile())

        // Insufficient funds: nothing spent, nothing unlocked.
        XCTAssertFalse(store.unlockWorld(1), "broke players can't buy")
        XCTAssertTrue(store.profile.purchasedWorlds.isEmpty)

        // Buy world 5 outright while worlds 1–4 are still locked — purchases are INDIVIDUAL.
        store.addCoins(4_000)
        XCTAssertTrue(store.unlockWorld(5))
        XCTAssertEqual(store.profile.coins, 4_000 - 3_200, "spends exactly worldPrice(5)")
        XCTAssertEqual(store.profile.purchasedWorlds, [5])
        XCTAssertTrue(store.isWorldStartable(5))
        XCTAssertFalse(store.isWorldStartable(4), "a purchased world 5 with world 4 locked is fine")
        XCTAssertEqual(store.highestStartableWorld, 5)

        // The purchase must NOT count as "reached": achievements / world bonus / XP stay
        // reach-based (rules 9/10) and the legacy reach display is untouched.
        XCTAssertEqual(store.profile.maxWorldReached, 0, "buying never touches maxWorldReached")
        XCTAssertEqual(store.unlockedWorldCount, 1)

        // Idempotent: already-purchased and already-reached worlds refuse (no double spend).
        XCTAssertFalse(store.unlockWorld(5), "already purchased")
        XCTAssertEqual(store.profile.coins, 800)
        store.mutate { $0.maxWorldReached = 3 }
        XCTAssertFalse(store.unlockWorld(2), "already reached — nothing to buy")
        XCTAssertEqual(store.profile.coins, 800)
        XCTAssertTrue(store.isWorldStartable(2), "reach alone makes a world startable")

        // Range guards: world 0 is free, the display cap bounds the ladder, garbage refuses.
        XCTAssertFalse(store.unlockWorld(0))
        XCTAssertFalse(store.unlockWorld(-1))
        XCTAssertFalse(store.unlockWorld(ProfileStore.worldDisplayCount))
        XCTAssertFalse(store.isWorldStartable(-1))
        XCTAssertEqual(store.profile.purchasedWorlds, [5])

        // Reach + purchase combine: highest startable follows whichever is deeper.
        store.mutate { $0.maxWorldReached = 7 }
        XCTAssertEqual(store.highestStartableWorld, 7)
        XCTAssertEqual(ProfileStore(testing: Profile()).highestStartableWorld, 0,
                       "fresh profile starts at world 0")
    }

    // MARK: revive (F3)

    func testReviveResumesPlayWithGrace() async {
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

    // MARK: clock-manipulation hardening (P1)
    // Exploit: set the device clock forward, claim, set it back — the future-dated `last…`
    // timestamp must NOT make the reward readable as available again.

    func testDailyRewardClockRollbackExploitBlocked() async {
        let store = ProfileStore(testing: Profile())
        let realNow = date(2026, 6, 10)
        let future = date(2026, 6, 20)
        XCTAssertNotNil(store.claimDailyReward(now: future), "claim while clock is set forward")
        // Clock set back: the stored claim is in the future relative to `now` → clamps to "today".
        XCTAssertFalse(store.dailyRewardAvailable(now: realNow), "future-dated claim must read as claimed")
        XCTAssertNil(store.claimDailyReward(now: realNow), "no infinite-claim loop")
        XCTAssertEqual(store.pendingDailyStreak(now: realNow), store.profile.loginStreak,
                       "clamped read keeps the streak stable instead of crediting a bonus day")
    }

    func testChestClockRollbackExploitBlocked() async {
        let store = ProfileStore(testing: Profile())
        let realNow = date(2026, 6, 10)
        let future = date(2026, 6, 20)
        XCTAssertNotNil(store.openFreeChest(now: future, reward: 100))
        // Clock set back: the future open must read as "just opened" — cooldown fully re-armed.
        XCTAssertFalse(store.chestReady(now: realNow))
        XCTAssertNil(store.openFreeChest(now: realNow, reward: 100))
        XCTAssertEqual(store.secondsUntilChest(now: realNow), ProfileStore.chestInterval, accuracy: 0.001)
    }

    func testSanitizedClampsFutureTimestampsOnLoad() async {
        let now = date(2026, 6, 10)
        let future = date(2027, 1, 1)
        var p = Profile()
        p.lastDailyClaim = future
        p.lastChestOpen = future
        p.dailyMissionDate = future
        p.dailyChallengeDate = future
        let s = ProfileStore.sanitized(p, now: now)
        XCTAssertEqual(s.lastDailyClaim, now)
        XCTAssertEqual(s.lastChestOpen, now)
        XCTAssertEqual(s.dailyMissionDate, now)
        XCTAssertEqual(s.dailyChallengeDate, now)
        // Past timestamps pass through untouched (no save is ever harmed by sanitizing).
        var ok = Profile()
        let past = date(2026, 6, 1)
        ok.lastDailyClaim = past
        ok.lastChestOpen = past
        XCTAssertEqual(ProfileStore.sanitized(ok, now: now), ok)
    }

    // MARK: profile schema resilience (G5 + decoder)

    func testProfileDecodesLegacyJSONWithoutWiping() async throws {
        // An old save: has the removed `powerUpLevels`, lacks the new daily/chest fields.
        let legacy = #"{"coins":1234,"selectedSkin":"ember","ownedSkins":["default","ember"],"powerUpLevels":{"shield":2},"maxWorldReached":4}"#
        let data = legacy.data(using: .utf8)!
        let p = try JSONDecoder().decode(Profile.self, from: data)
        XCTAssertEqual(p.coins, 1234)
        XCTAssertEqual(p.selectedSkin, "ember")
        XCTAssertEqual(p.maxWorldReached, 4)
        XCTAssertEqual(p.loginStreak, 0, "missing new field defaults, not throws")
        XCTAssertNil(p.lastChestOpen)
        // v1.3's six new fields default too — old saves never wipe, never fail (iron rule 7).
        XCTAssertEqual(p.totalXP, 0)
        XCTAssertEqual(p.xpLevelRewarded, 1)
        XCTAssertNil(p.weeklyMissionDate)
        XCTAssertEqual(p.challengeRewardTier, 0)
        XCTAssertEqual(p.seenSkins, ["default"])
        XCTAssertTrue(p.bestDistanceByWorld.isEmpty)
        XCTAssertTrue(p.purchasedWorlds.isEmpty, "v1.4 world purchases default empty on legacy saves")
    }
}
