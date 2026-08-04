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

        // Range guards: world 0 is free, garbage refuses. A deep evolved world (12) is buyable in
        // principle now (v1.6 — no display cap) but refuses HERE because 800 coins can't afford it.
        XCTAssertFalse(store.unlockWorld(0))
        XCTAssertFalse(store.unlockWorld(-1))
        XCTAssertFalse(store.unlockWorld(ProfileStore.worldDisplayCount), "world 12 unaffordable at 800 coins")
        XCTAssertFalse(store.isWorldStartable(-1))
        XCTAssertEqual(store.profile.purchasedWorlds, [5])

        // Reach + purchase combine: highest startable follows whichever is deeper.
        store.mutate { $0.maxWorldReached = 7 }
        XCTAssertEqual(store.highestStartableWorld, 7)
        XCTAssertEqual(ProfileStore(testing: Profile()).highestStartableWorld, 0,
                       "fresh profile starts at world 0")
    }

    func testDeepEvolvedWorldsAreBuyableAndPriced() async {
        // v1.6: worlds past the base 12 (the evolved cycles) are buyable with escalating prices,
        // so progression past Singularity has a point. They never touch maxWorldReached (reach-based).
        let store = ProfileStore(testing: Profile())
        store.addCoins(100_000)
        XCTAssertEqual(XPCurve.worldPrice(11), 13_400, "the authored ladder still holds at world 11")
        XCTAssertEqual(XPCurve.worldPrice(12), 13_400 + XPCurve.worldPriceStepBeyondLadder, "world 12 escalates past the ladder")
        XCTAssertGreaterThan(XPCurve.worldPrice(20), XPCurve.worldPrice(12), "deeper worlds cost more")
        XCTAssertTrue(store.unlockWorld(15), "a deep evolved world is buyable (no display cap)")
        XCTAssertTrue(store.isWorldStartable(15))
        XCTAssertEqual(store.highestStartableWorld, 15)
        XCTAssertEqual(store.profile.maxWorldReached, 0, "buying a deep world never touches reach")
        XCTAssertGreaterThanOrEqual(store.displayedWorldCount, 16, "the ladder extends to show past your furthest")
    }

    /// v1.4 review BLOCKER pin — the RUN pipeline must not undo `unlockWorld`'s invariant.
    /// Exploit chain: buy ONLY world 11 (13,400), start there, die instantly. GameView routes the
    /// fold through `ProfileStore.reachCredit`, so `maxWorldReached` and the reach-based
    /// `ach.worlds` ladder must both stay untouched (rules 9/10) — and a LEGIT start at the reach
    /// that pushes deeper must still advance it.
    func testPurchasedWorldStartNeverFoldsIntoReach() async {
        let store = ProfileStore(testing: Profile())
        store.addCoins(13_400)
        XCTAssertTrue(store.unlockWorld(11))

        // Instant death on the purchased start: deepest world this run == start world == 11,
        // reach at launch 0 → the run credits NOTHING new toward reach.
        let credit = ProfileStore.reachCredit(maxWorldThisRun: 11, startWorld: 11, reachAtStart: 0)
        XCTAssertEqual(credit, 0, "a start beyond reach credits nothing new")
        store.recordRun(score: 100, distance: 12, gems: 1, bestStreak: 1,
                        maxWorld: credit, coinsEarned: 1)
        XCTAssertEqual(store.profile.maxWorldReached, 0,
                       "the run fold must not launder a purchase into reach")
        XCTAssertFalse(store.isWorldStartable(10), "worlds 1–10 stay paid rungs — the ladder holds")
        XCTAssertEqual(store.unlockedWorldCount, 1)

        // ach.worlds ('World Walker', tiers 3/6/12) reads worldsCrossed — the gated feed is
        // credit + 1, so the bought-deep death pins progress at 1 and pays no tier.
        var s = RunSummary()
        s.distance = 12
        s.worldsCrossed = credit + 1
        s.startWorld = 11
        store.applyRunSummary(s, now: date(2026, 6, 10))
        XCTAssertEqual(store.profile.missionProgress["ach.worlds"] ?? 0, 1)
        let walker = MissionCatalog.achievements.first { $0.id == "ach.worlds" }!
        XCTAssertFalse(store.missionState(walker, now: date(2026, 6, 10)).claimable,
                       "World Walker must not fire off a purchased start")

        // Legit start AT the reach pushing 2 worlds deeper: the full fold still advances reach.
        store.mutate { $0.maxWorldReached = 2 }
        let legit = ProfileStore.reachCredit(maxWorldThisRun: 4, startWorld: 2, reachAtStart: 2)
        XCTAssertEqual(legit, 4)
        store.recordRun(score: 100, distance: 12, gems: 1, bestStreak: 1,
                        maxWorld: legit, coinsEarned: 1)
        XCTAssertEqual(store.profile.maxWorldReached, 4, "earned reach keeps folding as before")
    }

    // MARK: IAP first-purchase bonus (v1.4.1 — funnel lever, honest + replay-safe)

    func testCoinPackPayoutPureRule() async {
        XCTAssertEqual(ProfileStore.coinPackPayout(base: 3_000, bonusUsed: false), 4_500)
        XCTAssertEqual(ProfileStore.coinPackPayout(base: 3_000, bonusUsed: true), 3_000)
        XCTAssertEqual(ProfileStore.coinPackPayout(base: 1_200, bonusUsed: false), 1_800)
        XCTAssertEqual(ProfileStore.coinPackPayout(base: 40_000, bonusUsed: false), 60_000)
        XCTAssertEqual(ProfileStore.coinPackPayout(base: 1, bonusUsed: false), 1,
                       "integer half rounds DOWN — the bonus never overpays")
    }

    func testFirstPurchaseBonusPaysExactlyOnce() async {
        let store = ProfileStore(testing: Profile())
        XCTAssertFalse(store.profile.firstPurchaseBonusUsed)
        XCTAssertEqual(store.profile.totalIAPPurchases, 0)

        // First verified coin pack ever: base + 50%.
        store.grantCoinPack(1_200)
        XCTAssertEqual(store.profile.coins, 1_800)
        XCTAssertTrue(store.profile.firstPurchaseBonusUsed)
        XCTAssertEqual(store.profile.totalIAPPurchases, 1)

        // Transaction.updates replay / any later pack: base only — the FLAG dedupes, not the
        // caller, so the StoreKit handler can replay without ever double-paying the bonus.
        store.grantCoinPack(1_200)
        XCTAssertEqual(store.profile.coins, 3_000)
        XCTAssertEqual(store.profile.totalIAPPurchases, 2)

        // Purchased coins are bought, not earned: the mission/achievement feed stays clean.
        XCTAssertEqual(store.profile.totalCoinsEarned, 0)

        // Garbage refuses without side effects.
        store.grantCoinPack(0)
        store.grantCoinPack(-5)
        XCTAssertEqual(store.profile.coins, 3_000)
        XCTAssertEqual(store.profile.totalIAPPurchases, 2)
    }

    func testGrantCoinPackTransactionReplayIsIdempotent() async {
        let store = ProfileStore(testing: Profile())
        store.grantCoinPack(1_200, transactionID: 42)
        XCTAssertEqual(store.profile.coins, 1_800, "first grant pays base + 50% bonus")
        XCTAssertEqual(store.profile.totalIAPPurchases, 1)

        // Transaction.updates redelivery (app died between the saved grant and finish()):
        // SAME id → no-op for base coins, the bonus AND the purchase counter.
        store.grantCoinPack(1_200, transactionID: 42)
        XCTAssertEqual(store.profile.coins, 1_800, "replay must not re-pay the base coins")
        XCTAssertEqual(store.profile.totalIAPPurchases, 1, "replay must not re-bump the counter")

        // A genuinely new transaction still pays (base only — the bonus is spent).
        store.grantCoinPack(1_200, transactionID: 43)
        XCTAssertEqual(store.profile.coins, 3_000)
        XCTAssertEqual(store.profile.totalIAPPurchases, 2)
        XCTAssertEqual(store.profile.grantedTransactionIDs, [42, 43])
    }

    func testApplyOncePerTransactionNonConsumablePath() async {
        let store = ProfileStore(testing: Profile())
        // IAPCatalog.apply's non-consumable branches route through the same primitive — the
        // totalIAPPurchases bump must be replay-safe there too.
        let change: (inout Profile) -> Void = { $0.doubleCoins = true; $0.totalIAPPurchases += 1 }
        XCTAssertTrue(store.applyOncePerTransaction(7, change))
        XCTAssertFalse(store.applyOncePerTransaction(7, change), "redelivery is a no-op")
        XCTAssertEqual(store.profile.totalIAPPurchases, 1)
        // nil = no StoreKit context (tests / legacy callers): applies unconditionally.
        XCTAssertTrue(store.applyOncePerTransaction(nil, change))
        XCTAssertEqual(store.profile.totalIAPPurchases, 2)
    }

    func testGrantedTransactionLedgerBoundedToNewest() async {
        var p = Profile()
        let cap = UInt64(Profile.grantedTransactionIDCap)
        for id in 1...(cap + 88) { p.recordGrantedTransaction(id) }
        XCTAssertEqual(p.grantedTransactionIDs.count, Profile.grantedTransactionIDCap)
        XCTAssertFalse(p.grantedTransactionIDs.contains(1), "oldest ids trim first")
        XCTAssertTrue(p.grantedTransactionIDs.contains(cap + 88), "newest ids always kept")
    }

    /// v1.4.1 BLOCKER pin — an iCloud merge can never erase a real-money coin grant. Review
    /// scenario: iPhone holds 50,000 earned coins; iPad (2,000) buys Pouch of Coins and the
    /// first-purchase bonus pays 1,200+600. The old coins=max() merge returned 50,000 and
    /// destroyed the purchase; the per-device G-counter credit keeps every paid coin in BOTH
    /// merge directions (Decree 5: advertised bonuses are always delivered).
    func testCloudMergeNeverErasesPurchasedCoins() async {
        var iPhone = Profile()
        iPhone.coins = 50_000

        var padStart = Profile(); padStart.coins = 2_000
        let iPad = ProfileStore(testing: padStart, deviceKey: "ipad")
        iPad.grantCoinPack(1_200, transactionID: 99)
        XCTAssertEqual(iPad.profile.coins, 3_800)
        XCTAssertEqual(iPad.profile.totalCoinsPurchased, 1_800, "G-counter carries the FULL payout")

        let onPhone = ProfileStore.merged(local: iPhone, remote: iPad.profile)
        let onPad = ProfileStore.merged(local: iPad.profile, remote: iPhone)
        XCTAssertEqual(onPhone.coins, 51_800, "earned max + the full paid payout (incl. bonus)")
        XCTAssertEqual(onPad.coins, 51_800, "merge is direction-independent")
        XCTAssertTrue(onPhone.firstPurchaseBonusUsed, "the delivered bonus stays spent")
        XCTAssertEqual(onPhone.grantedTransactionIDs, [99], "replay ledger unions across devices")

        // Convergent: re-merging the merged profile with either side credits nothing twice.
        XCTAssertEqual(ProfileStore.merged(local: onPhone, remote: iPad.profile).coins, 51_800)
        XCTAssertEqual(ProfileStore.merged(local: onPhone, remote: iPhone).coins, 51_800)
    }

    func testCloudMergeConcurrentPurchasesOnTwoDevicesBothSurvive() async {
        // Each device bought separately before any sync — DIFFERENT G-counter slots, so neither
        // payout can shadow the other under the per-key-max merge.
        var a = Profile(); a.coins = 1_800; a.coinsPurchasedByDevice = ["a": 1_800]
        var b = Profile(); b.coins = 10_500; b.coinsPurchasedByDevice = ["b": 10_500]
        let m = ProfileStore.merged(local: a, remote: b)
        XCTAssertEqual(m.coins, 12_300, "both real-money payouts survive")
        XCTAssertEqual(ProfileStore.merged(local: b, remote: a).coins, 12_300)
        XCTAssertEqual(m.coinsPurchasedByDevice, ["a": 1_800, "b": 10_500])
    }

    func testFirstPurchaseFlagCloudMergeNeverRearms() async {
        var bought = Profile()
        bought.firstPurchaseBonusUsed = true
        bought.totalIAPPurchases = 3
        let fresh = Profile()
        // OR/max in both directions: a fresh device merging in can never re-arm the bonus or
        // resurrect the starter offer slot.
        XCTAssertTrue(ProfileStore.merged(local: fresh, remote: bought).firstPurchaseBonusUsed)
        XCTAssertTrue(ProfileStore.merged(local: bought, remote: fresh).firstPurchaseBonusUsed)
        XCTAssertEqual(ProfileStore.merged(local: fresh, remote: bought).totalIAPPurchases, 3)
        XCTAssertEqual(ProfileStore.merged(local: bought, remote: fresh).totalIAPPurchases, 3)
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

    // MARK: equipped-skin resolver + self-heal (AUDIT D3-1 — decrees 2+3+4)
    // A cloud merge or stale save can select a skin this device doesn't own. The run already
    // refuses to render it; these pins make every other surface share that truth via
    // `equippedSkinID` and stop the contradiction from persisting.

    func testUnownedSelectedSkinResolverFallsBackWithoutMutating() async {
        var broken = Profile()
        broken.selectedSkin = "aurora"                       // cloud said aurora…
        XCTAssertFalse(broken.ownedSkins.contains("aurora")) // …but it was never owned here
        let store = ProfileStore(testing: broken)
        XCTAssertEqual(store.equippedSkinID, "default", "resolver falls back to the default")
        XCTAssertEqual(store.profile.selectedSkin, "aurora",
                       "the resolver alone never mutates — the selection stays dormant")

        // The moment the skin IS unlocked, the dormant selection takes effect — the cloud's
        // pick is honored with no re-equip needed (AUDIT D3-1: never lose a later-valid choice).
        store.unlock(skin: "aurora")
        XCTAssertEqual(store.equippedSkinID, "aurora")
    }

    func testSanitizedHealsUnownedSelectionOnLoad() async {
        var broken = Profile()
        broken.selectedSkin = "aurora"
        XCTAssertEqual(ProfileStore.sanitized(broken).selectedSkin, "default",
                       "load self-heal: EQUIPPED-on-a-locked-skin can't persist across launches")
        // A consistent save passes through untouched — sanitizing never harms a valid pick.
        var ok = Profile()
        ok.ownedSkins.insert("aurora"); ok.selectedSkin = "aurora"
        XCTAssertEqual(ProfileStore.sanitized(ok).selectedSkin, "aurora")
    }

    func testCloudMergeHealsSelectionAfterOwnershipUnion() async {
        var local = Profile()
        local.selectedSkin = "aurora"                        // the sticky broken combo

        // The merge that brings the unlock: the ownership union runs FIRST, so the cloud
        // selection is NOT lost — it lands already valid (AUDIT D3-1 ordering pin).
        var remote = Profile()
        remote.ownedSkins.insert("aurora")
        XCTAssertEqual(ProfileStore.merged(local: local, remote: remote).selectedSkin, "aurora",
                       "a selection whose unlock arrives in the same merge survives")

        // A merge where nobody owns it: healed to the default — the contradiction can't
        // outlive a merge in either direction.
        XCTAssertEqual(ProfileStore.merged(local: local, remote: Profile()).selectedSkin, "default")
        XCTAssertEqual(ProfileStore.merged(local: Profile(), remote: local).selectedSkin, "default",
                       "remote's unowned pick can't infect the merged profile either")
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
        // v1.4.1's two IAP-funnel fields default too (decodeIfPresent ?? default — iron rule 7).
        XCTAssertEqual(p.totalIAPPurchases, 0)
        XCTAssertFalse(p.firstPurchaseBonusUsed)
        // …and the v1.4.1 review fields (purchased-coin G-counter + replay ledger).
        XCTAssertTrue(p.coinsPurchasedByDevice.isEmpty)
        XCTAssertTrue(p.grantedTransactionIDs.isEmpty)
        // v1.5 pre-run consumable counters default on legacy saves (one each — the goodwill intro).
        XCTAssertEqual(p.slowMoCharges, 2)
        XCTAssertEqual(p.speedUpCharges, 2)
        XCTAssertEqual(p.shieldCharges, 1)
        XCTAssertEqual(p.headStartCharges, 1)
        XCTAssertEqual(p.coinSurgeCharges, 1)
    }

    func testConsumablesStayDeviceLocalOnCloudMerge() async throws {
        // Consumable inventory is deliberately device-local: the LOCAL value wins, so a stale remote
        // can never resurrect spent charges (a max() merge would — see ProfileStore.merged docstring).
        var local = Profile(); local.headStartCharges = 0; local.coinSurgeCharges = 4; local.slowMoCharges = 1; local.speedUpCharges = 2; local.shieldCharges = 3
        var remote = Profile(); remote.headStartCharges = 9; remote.coinSurgeCharges = 9; remote.slowMoCharges = 9
        let m = ProfileStore.merged(local: local, remote: remote)
        XCTAssertEqual(m.headStartCharges, 0, "spent Head Start charges are not resurrected by a merge")
        XCTAssertEqual(m.coinSurgeCharges, 4, "consumables keep the local value (device-local)")
        XCTAssertEqual(m.slowMoCharges, 1)
        XCTAssertEqual(m.speedUpCharges, 2, "speed-up is device-local too")
        XCTAssertEqual(m.shieldCharges, 3, "deployable shield is device-local too")
    }

    func testConsumableCountersRoundTripAndCanBeSpent() async throws {
        // A profile carrying spent/earned consumable counts must encode + decode exactly (no wipe).
        var p = Profile()
        p.headStartCharges = 3
        p.coinSurgeCharges = 0
        p.slowMoCharges = 5
        let data = try JSONEncoder().encode(p)
        let back = try JSONDecoder().decode(Profile.self, from: data)
        XCTAssertEqual(back.headStartCharges, 3)
        XCTAssertEqual(back.coinSurgeCharges, 0)
        XCTAssertEqual(back.slowMoCharges, 5)
    }

    // MARK: coin-spend consumables (v1.5 — Mystery Box + packs)

    func testMysteryBoxOddsBoundaries() async {
        // Pin every band edge of the honest weighted table (decree 5).
        XCTAssertEqual(ShopConsumables.mysteryReward(roll: 0.0), .coins(200))
        XCTAssertEqual(ShopConsumables.mysteryReward(roll: 0.419), .coins(200))
        XCTAssertEqual(ShopConsumables.mysteryReward(roll: 0.42), .coins(350))
        XCTAssertEqual(ShopConsumables.mysteryReward(roll: 0.639), .coins(350))
        XCTAssertEqual(ShopConsumables.mysteryReward(roll: 0.64), .slowMo(3))
        XCTAssertEqual(ShopConsumables.mysteryReward(roll: 0.79), .headStart(2))
        XCTAssertEqual(ShopConsumables.mysteryReward(roll: 0.90), .coins(600))
        XCTAssertEqual(ShopConsumables.mysteryReward(roll: 0.975), .coins(1400))
        XCTAssertEqual(ShopConsumables.mysteryReward(roll: 0.9999), .coins(1400))
    }

    /// **The disclosed odds must BE the rolled odds** (S-019, App Store guideline 3.1.1).
    ///
    /// The reveal screen displayed a 3% jackpot while `mysteryReward` rolled 2.5%, and the error
    /// favoured the house. It survived because nothing tied the two together: `mysteryOdds` had
    /// **zero** test coverage — the whole of `grep -rn mysteryOdds Tests/` was empty — so the
    /// disclosure was a hand-maintained comment on the weights rather than a checked property of
    /// them. Fixed by raising the ROLL to the disclosure (never the reverse: nothing a player has
    /// already seen may become a lie), with the 600-coin band absorbing the 0.5%.
    ///
    /// This measures the SHIPPED function by integration rather than restating its weights, so it
    /// cannot drift out of step with the bands the way a hand-written sum would — the same technique
    /// `testTheMysteryBoxIsWorthWhatItCostsAndCanNeverMintCoins` uses on the expected value.
    func testTheDisclosedOddsAreTheRolledOdds() async {
        // The disclosed table, mapped to the grant each row promises. If a row is ever added or
        // relabelled without a grant to back it, this list stops compiling into a total of 100.
        let disclosed: [(grant: ConsumableGrant, label: String)] = [
            (.coins(ShopConsumables.mysteryJackpotCoins), "1,400 coins — JACKPOT"),
            (.coins(600),      "600 coins"),
            (.headStart(2),    "Head Start ×2"),
            (.slowMo(3),       "Slow-Mo ×3"),
            (.coins(350),      "350 coins"),
            (.coins(200),      "200 coins"),
        ]
        XCTAssertEqual(ShopConsumables.mysteryOdds.count, disclosed.count,
                       "a disclosed row exists with no grant behind it, or vice versa")

        // Measure each band's true width by sampling the shipped function.
        let steps = 200_000
        var measured: [String: Double] = [:]
        for i in 0..<steps {
            let g = ShopConsumables.mysteryReward(roll: (Double(i) + 0.5) / Double(steps))
            measured["\(g)", default: 0] += 100.0 / Double(steps)
        }

        for (row, promise) in zip(ShopConsumables.mysteryOdds, disclosed) {
            XCTAssertEqual(row.label, promise.label,
                           "the odds table's row order changed — the grant mapping above is now wrong")
            let actual = measured["\(promise.grant)"] ?? 0
            XCTAssertEqual(actual, Double(row.pct), accuracy: 0.01, String(format:
                "the reveal screen displays %d%% for \"%@\" but mysteryReward rolls it %.2f%% of the "
                + "time — disclosed odds must be real (guideline 3.1.1), and this gap favouring the "
                + "house is exactly the S-019 defect", row.pct, row.label, actual))
        }

        // And the disclosure must be a complete account of the outcomes, not a selective one.
        XCTAssertEqual(ShopConsumables.mysteryOdds.reduce(0) { $0 + $1.pct }, 100,
                       "the displayed odds do not sum to 100% — some outcome is undisclosed")
        XCTAssertEqual(measured.count, disclosed.count,
                       "mysteryReward can return a grant the reveal screen never discloses")
    }

    /// The advertised jackpot must be the granted one. Two `ShopView` strings said 1,200 against a
    /// real 1,400 — one of them the VoiceOver label, so a screen-reader user was told the wrong
    /// number too. Both now interpolate `mysteryJackpotCoins`; this pins the constant to the table.
    func testTheAdvertisedJackpotIsTheGrantedJackpot() async {
        XCTAssertEqual(ShopConsumables.mysteryReward(roll: 0.999),
                       .coins(ShopConsumables.mysteryJackpotCoins))
        // Compare on digits, not on a formatted string: `Int.formatted()` is locale- and
        // platform-sensitive and this suite must compile and pass on Linux CI.
        let ungrouped = ShopConsumables.mysteryOdds[0].label.replacingOccurrences(of: ",", with: "")
        XCTAssertTrue(ungrouped.contains("\(ShopConsumables.mysteryJackpotCoins)"),
                      "the jackpot row names a different number than the box actually pays")
    }

    /// **The box must not be a trap, and it must not be a printer** (S-012, E6).
    ///
    /// The old table's expected value was 242.7 against a 300 price — −19%, which decree 5 ("no dark
    /// patterns") does not comfortably survive. The fix is not just a re-weight: this test also pins
    /// the STRUCTURAL half, which is that no band may grant a coin multiplier. A Coin Surge doubles
    /// a whole run and banks with no cap, so an 8% surge band made a 300-coin spend net-POSITIVE for
    /// any player who ran deep enough to arm it well — the last surviving violation of D-026.
    func testTheMysteryBoxIsWorthWhatItCostsAndCanNeverMintCoins() async {
        // Per-charge coin values, taken from the surviving packs rather than invented.
        func unitValue(_ id: String) -> Double {
            guard let pack = ShopConsumables.packs.first(where: { $0.id == id }) else { return 0 }
            return Double(pack.cost) / 3.0
        }
        let slowMo = unitValue("slowMoPack"), headStart = unitValue("headStartPack")

        // Integrate the table over [0, 1) at fine resolution — this reads the SHIPPED function, so
        // it cannot drift out of step with the bands the way a hand-written sum would.
        let steps = 200_000
        var ev = 0.0
        for i in 0..<steps {
            switch ShopConsumables.mysteryReward(roll: (Double(i) + 0.5) / Double(steps)) {
            case let .coins(c):     ev += Double(c)
            case let .slowMo(n):    ev += Double(n) * slowMo
            case let .headStart(n): ev += Double(n) * headStart
            case let .speedUp(n):   ev += Double(n) * unitValue("speedUpPack")
            case let .shield(n):    ev += Double(n) * unitValue("shieldPack")
            case .coinSurge:
                XCTFail("the Mystery Box granted a Coin Surge — a 300-coin SPEND that returns a coin "
                        + "multiplier is exactly the arbitrage D-026 deleted the Coin Surge Pack to "
                        + "prevent, and a surge banks uncapped so it is worth the best run you will "
                        + "ever arm it on")
            }
        }
        ev /= Double(steps)
        let price = Double(ShopConsumables.mysteryBoxCost)
        XCTAssertEqual(ev, price, accuracy: price * 0.05, String(format:
            "expected value %.1f against a %.0f price (%.1f%%) — a box more than 5%% either side of "
            + "its own cost is a trap or a printer", ev, price, (ev / price - 1) * 100))

        // And the coin bands ALONE must stay under the price, or the box mints currency from
        // currency with unlimited rolls and no cooldown.
        var coinOnlyEV = 0.0
        for i in 0..<steps {
            if case let .coins(c) = ShopConsumables.mysteryReward(roll: (Double(i) + 0.5) / Double(steps)) {
                coinOnlyEV += Double(c)
            }
        }
        coinOnlyEV /= Double(steps)
        XCTAssertLessThan(coinOnlyEV, price, String(format:
            "coin-only EV is %.1f against a %.0f price — the box is a coin printer", coinOnlyEV, price))
    }

    func testOpenMysteryBoxSpendsGrantsAndGatesOnCoins() async {
        var p = Profile(); p.coins = ShopConsumables.mysteryBoxCost   // exactly one box
        let store = ProfileStore(testing: p)

        // Jackpot roll: spend 300, win 1,400 → coins 1,400; winnings are NOT counted as earned.
        XCTAssertEqual(store.openMysteryBox(roll: 0.99), .coins(1400))
        XCTAssertEqual(store.profile.coins, 1400)
        XCTAssertEqual(store.profile.totalCoinsEarned, 0, "gacha winnings are bought, not earned")

        // Consumable roll: spend + grant the charges.
        XCTAssertEqual(store.openMysteryBox(roll: 0.80), .headStart(2))
        XCTAssertEqual(store.profile.headStartCharges, Profile().headStartCharges + 2)
        XCTAssertEqual(store.profile.coins, 1100)

        // Too poor: nil, no spend, no grant.
        let broke = ProfileStore(testing: Profile())   // 0 coins
        XCTAssertNil(broke.openMysteryBox(roll: 0.0))
        XCTAssertEqual(broke.profile.coins, 0)
        XCTAssertEqual(broke.profile.headStartCharges, Profile().headStartCharges)
    }

    func testBuyConsumablePackSpendsAndGrants() async {
        var p = Profile(); p.coins = 1000
        let store = ProfileStore(testing: p)
        let slowMoPack = ShopConsumables.packs.first { $0.id == "slowMoPack" }!
        XCTAssertTrue(store.buyConsumablePack(slowMoPack))
        XCTAssertEqual(store.profile.coins, 1000 - slowMoPack.cost)
        XCTAssertEqual(store.profile.slowMoCharges, Profile().slowMoCharges + 3)
        XCTAssertEqual(store.profile.totalCoinsEarned, 0, "spending coins on a pack is not earning")

        let broke = ProfileStore(testing: Profile())
        XCTAssertFalse(broke.buyConsumablePack(slowMoPack))
        XCTAssertEqual(broke.profile.slowMoCharges, Profile().slowMoCharges)
    }
}
