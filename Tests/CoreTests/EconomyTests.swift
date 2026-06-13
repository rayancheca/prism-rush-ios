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
        XCTAssertEqual(p.headStartCharges, 1)
        XCTAssertEqual(p.coinSurgeCharges, 1)
    }

    func testConsumablesStayDeviceLocalOnCloudMerge() async throws {
        // Consumable inventory is deliberately device-local: the LOCAL value wins, so a stale remote
        // can never resurrect spent charges (a max() merge would — see ProfileStore.merged docstring).
        var local = Profile(); local.headStartCharges = 0; local.coinSurgeCharges = 4; local.slowMoCharges = 1; local.speedUpCharges = 2
        var remote = Profile(); remote.headStartCharges = 9; remote.coinSurgeCharges = 9; remote.slowMoCharges = 9
        let m = ProfileStore.merged(local: local, remote: remote)
        XCTAssertEqual(m.headStartCharges, 0, "spent Head Start charges are not resurrected by a merge")
        XCTAssertEqual(m.coinSurgeCharges, 4, "consumables keep the local value (device-local)")
        XCTAssertEqual(m.slowMoCharges, 1)
        XCTAssertEqual(m.speedUpCharges, 2, "speed-up is device-local too")
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
        XCTAssertEqual(ShopConsumables.mysteryReward(roll: 0.39), .coins(200))
        XCTAssertEqual(ShopConsumables.mysteryReward(roll: 0.40), .coins(400))
        XCTAssertEqual(ShopConsumables.mysteryReward(roll: 0.61), .coins(400))
        XCTAssertEqual(ShopConsumables.mysteryReward(roll: 0.62), .slowMo(2))
        XCTAssertEqual(ShopConsumables.mysteryReward(roll: 0.78), .headStart(1))
        XCTAssertEqual(ShopConsumables.mysteryReward(roll: 0.90), .coinSurge(1))
        XCTAssertEqual(ShopConsumables.mysteryReward(roll: 0.98), .coins(1200))
        XCTAssertEqual(ShopConsumables.mysteryReward(roll: 0.9999), .coins(1200))
    }

    func testOpenMysteryBoxSpendsGrantsAndGatesOnCoins() async {
        var p = Profile(); p.coins = ShopConsumables.mysteryBoxCost   // exactly one box
        let store = ProfileStore(testing: p)

        // Jackpot roll: spend 300, win 1,200 → coins 1,200; winnings are NOT counted as earned.
        XCTAssertEqual(store.openMysteryBox(roll: 0.99), .coins(1200))
        XCTAssertEqual(store.profile.coins, 1200)
        XCTAssertEqual(store.profile.totalCoinsEarned, 0, "gacha winnings are bought, not earned")

        // Consumable roll: spend + grant the charge.
        XCTAssertEqual(store.openMysteryBox(roll: 0.80), .headStart(1))
        XCTAssertEqual(store.profile.headStartCharges, Profile().headStartCharges + 1)
        XCTAssertEqual(store.profile.coins, 900)

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
