import XCTest
@testable import PrismRush

/// v1.3 progression: the XP curve + per-run formula, watermarked level grants, weekly missions
/// (determinism / rollover / rollback), style coins, daily-challenge placement tiers, the
/// per-world best map (R14), the new Profile fields' decode + cloud-merge rules, and the v1.4
/// world-purchase price ladder.
@MainActor
final class ProgressionTests: XCTestCase {

    // MARK: helpers

    /// A specific instant in UTC (weekly missions/challenge roll over on UTC keys).
    private func utc(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12, _ min: Int = 0) -> Date {
        var c = DateComponents()
        c.year = y; c.month = m; c.day = d; c.hour = h; c.minute = min
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal.date(from: c)!
    }

    /// Noon on day 0 of the UTC week containing `date` (week key = daysSinceEpoch / 7), so
    /// `+1 day` is provably the same week and `+7 days` provably the next.
    private func weekStart(of date: Date) -> Date {
        let dse = ProfileStore.daysSinceEpoch(date)
        return Date(timeIntervalSince1970: Double(dse - dse % 7) * 86_400 + 43_200)
    }

    /// A run summary that scores `value` on `metric` (and nothing else) — mirrors MissionsTests.
    private func summary(_ metric: Mission.Metric, _ value: Double) -> RunSummary {
        var s = RunSummary()
        switch metric {
        case .gems: s.gems = Int(value)
        case .distance: s.distance = value
        case .nearMisses: s.nearMissCloses = Int(value)
        case .slides: s.slides = Int(value)
        case .slickBonuses: s.slicks = Int(value)
        case .runsFinished: break              // every summary counts as 1 run
        case .streakBest: s.bestStreak = Int(value)
        case .worldReached: s.worldsCrossed = Int(value)
        case .chestsOpened: break              // fed by openFreeChest, not runs
        case .wardensDefeated: s.wardensDefeated = Int(value)
        case .revives: s.revives = Int(value)
        case .multiplierHit: s.bestMult = Int(value)
        }
        return s
    }

    // MARK: XP curve (§C.2 pins)

    func testXPCurvePinnedThresholds() async {
        XCTAssertEqual(XPCurve.maxLevel, 30)
        XCTAssertEqual(XPCurve.cumulativeXP.count, 30)
        XCTAssertEqual(XPCurve.cumulativeXP[0], 0,      "level 1 starts at 0")
        XCTAssertEqual(XPCurve.cumulativeXP[1], 300,    "L2")
        XCTAssertEqual(XPCurve.cumulativeXP[4], 2_100,  "L5")
        XCTAssertEqual(XPCurve.cumulativeXP[9], 8_100,  "L10")
        XCTAssertEqual(XPCurve.cumulativeXP[19], 31_350, "L20")
        XCTAssertEqual(XPCurve.cumulativeXP[29], 69_600, "L30")

        // level(for:) inverse round-trips at every boundary ±1.
        for lvl in 2...30 {
            let threshold = XPCurve.cumulativeXP[lvl - 1]
            XCTAssertEqual(XPCurve.level(for: threshold), lvl, "exactly at L\(lvl)")
            XCTAssertEqual(XPCurve.level(for: threshold - 1), lvl - 1, "1 XP short of L\(lvl)")
            XCTAssertEqual(XPCurve.level(for: threshold + 1), lvl, "1 XP past L\(lvl)")
        }
        XCTAssertEqual(XPCurve.level(for: 0), 1)
        XCTAssertEqual(XPCurve.level(for: -50), 1, "negative XP clamps to level 1")
        XCTAssertEqual(XPCurve.level(for: 10_000_000), 30, "level caps at 30")

        // xpIntoLevel: progress within the band; (0, 0) sentinel at the cap.
        XCTAssertEqual(XPCurve.xpIntoLevel(for: 0).current, 0)
        XCTAssertEqual(XPCurve.xpIntoLevel(for: 0).needed, 300)
        XCTAssertEqual(XPCurve.xpIntoLevel(for: 300).current, 0)
        XCTAssertEqual(XPCurve.xpIntoLevel(for: 300).needed, 450)
        XCTAssertEqual(XPCurve.xpIntoLevel(for: 749).current, 449)
        XCTAssertEqual(XPCurve.xpIntoLevel(for: 70_000).needed, 0, "cap sentinel — bar renders full")

        XCTAssertEqual(XPCurve.xpUnlockLevels, [3, 6, 8, 12, 18, 25], "R1 + the v1.4 L8/L18 beats")
    }

    func testWorldPriceLadderPinned() async {
        XCTAssertEqual(XPCurve.worldPrice(0), 0, "world 0 is the free starting world")
        XCTAssertEqual(XPCurve.worldPrice(-3), 0, "garbage indices price as free — unlockWorld range-guards anyway")
        let ladder = [400, 800, 1_400, 2_200, 3_200, 4_400, 5_800, 7_400, 9_200, 11_200, 13_400]
        XCTAssertEqual(XPCurve.worldPrices, ladder)
        for (i, price) in ladder.enumerated() {
            XCTAssertEqual(XPCurve.worldPrice(i + 1), price, "world \(i + 1)")
        }
        XCTAssertEqual(XPCurve.worldPrice(99), 13_400 + 88 * XPCurve.worldPriceStepBeyondLadder,
                       "past the ladder, deep evolved worlds escalate (v1.6 — not clamped)")
        XCTAssertEqual(ladder.reduce(0, +), 59_400, "total world sink")
        XCTAssertEqual(ladder.count, ProfileStore.worldDisplayCount - 1,
                       "one rung per displayed world past the free one")
        XCTAssertEqual(ProfileStore.worldDisplayCount, 12)
        XCTAssertEqual(ProfileStore.maxStartWorlds, 12, "legacy alias keeps the v1.3 UI honest")
        // Escalating, always (early skips accessible vs the ~2.6k/day casual faucet).
        for i in 1..<ladder.count {
            XCTAssertGreaterThan(ladder[i], ladder[i - 1], "ladder must escalate")
        }
    }

    func testXPFormulaFromSummary() async {
        // Crafted run: 800 m + 30 gems + 3 CLOSE + 1 SLICK + ×3 + crossed into world 2.
        var s = RunSummary()
        s.distance = 800; s.gems = 30; s.nearMissCloses = 3; s.slicks = 1
        s.bestMult = 3; s.worldsCrossed = 2
        XCTAssertEqual(XPCurve.xp(for: s), 80 + 60 + 20 + 30 + 25, "exact formula (215)")

        // startWorld zeroes the world XP a checkpoint start didn't earn.
        s.startWorld = 1
        XCTAssertEqual(XPCurve.xp(for: s), 190, "checkpoint head-start pays no world XP")
        s.startWorld = 5
        XCTAssertEqual(XPCurve.xp(for: s), 190, "world term never goes negative")

        // Per-run clamp at 2,000.
        var marathon = RunSummary()
        marathon.distance = 25_000; marathon.gems = 500; marathon.bestMult = 5
        XCTAssertEqual(XPCurve.xp(for: marathon), 2_000, "marathon runs are bounded")

        // doubleCoins (IAP) must NOT inflate XP — the formula never reads the profile.
        var paid = Profile(); paid.doubleCoins = true
        let a = ProfileStore(testing: Profile())
        let b = ProfileStore(testing: paid)
        var run = RunSummary(); run.distance = 1_000; run.gems = 40
        a.applyRunSummary(run, now: utc(2026, 6, 10))
        b.applyRunSummary(run, now: utc(2026, 6, 10))
        XCTAssertEqual(a.profile.totalXP, b.profile.totalXP, "IAP never touches the level curve")
    }

    // MARK: applyRunSummary — XP, grants, watermark

    func testApplyRunSummaryGrantsXPAndLevels() async {
        let store = ProfileStore(testing: Profile())
        let now = utc(2026, 6, 10)

        // Run A: exactly 300 XP (290 distance + 10 combo) → L1 → L2 → 25-coin grant.
        var a = RunSummary(); a.distance = 2_900
        let rA = store.applyRunSummary(a, now: now)
        XCTAssertEqual(rA, LevelUpResult(xpGained: 300, levelBefore: 1, levelAfter: 2,
                                         coinsGranted: 25, unlockedLevels: []))
        XCTAssertEqual(store.profile.totalXP, 300)
        XCTAssertEqual(store.profile.coins, 25)
        XCTAssertEqual(store.profile.totalCoinsEarned, 25)
        XCTAssertEqual(store.profile.xpLevelRewarded, 2)
        XCTAssertEqual(store.playerLevel, 2)

        // Run B: clamped 2,000 XP → totalXP 2,300 → L5; pays L3+L4+L5 and tags the L3 unlock.
        var b = RunSummary(); b.distance = 30_000
        let rB = store.applyRunSummary(b, now: now)
        XCTAssertEqual(rB, LevelUpResult(xpGained: 2_000, levelBefore: 2, levelAfter: 5,
                                         coinsGranted: 75, unlockedLevels: [3]))
        XCTAssertEqual(store.profile.coins, 100)
        XCTAssertEqual(store.profile.xpLevelRewarded, 5)

        // Run C: tiny run — XP accrues, no level crossed, zero grant.
        let rC = store.applyRunSummary(RunSummary(), now: now)   // bestMult 1 → 10 XP
        XCTAssertEqual(rC.xpGained, 10)
        XCTAssertEqual(rC.coinsGranted, 0)
        XCTAssertEqual(rC.levelAfter, 5)
        XCTAssertTrue(rC.unlockedLevels.isEmpty)
    }

    /// **The level ladder must not out-earn playing the game** (S-012, E7).
    ///
    /// Measured before the cut: L1→L30 paid 10,300 direct coins and takes roughly 73–81 minutes;
    /// running for those same minutes pays 4,630–6,265 on the S-011 faucet. Levelling was worth
    /// **1.6–2.2× the entire run faucet** — so the session that made SKILL the largest term in the
    /// payout was immediately out-earned by a counter that goes up no matter how you play. Add the
    /// power-up charges and the giveaway came to 23,350 coins of priceable value against an 83,500
    /// catalogue: 28% of the whole game, for levelling.
    ///
    /// This pins the totals rather than the bands, because the total is the claim.
    func testTheWholeLevelLadderPaysLessThanRunningForTheSameTime() async {
        let directCoins = (2...30).reduce(0) { $0 + XPCurve.coinGrant(forLevel: $1) }
        XCTAssertEqual(directCoins, 2_400, "the L1→L30 direct coin total moved — re-derive E7")

        // The run faucet over the same 73–81 minutes, from the S-011 measurement table
        // (docs/agent/audits/AUDIT_011_ECONOMY.md): 4,630 coins at the pessimistic end.
        let runFaucetOverTheSameStretch = 4_630
        XCTAssertLessThan(directCoins, runFaucetOverTheSameStretch, """
            the level ladder pays \(directCoins) coins over the ~77 minutes it takes to reach L30,             against ~\(runFaucetOverTheSameStretch) for actually running. Levelling must be a             bonus on top of playing, never a substitute for it.
            """)

        // The charge grants, valued at the surviving shop prices.
        var slowMo = 0, speedUp = 0, shield = 0, coinSurge = 0
        for n in 2...30 {
            let g = XPCurve.levelUpCharges(forLevel: n)
            slowMo += g.slowMo; speedUp += g.speedUp; shield += g.shield; coinSurge += g.coinSurge
        }
        XCTAssertEqual(slowMo, 29); XCTAssertEqual(speedUp, 29)
        XCTAssertEqual(shield, 15, "shields sit on even levels — the scarcest of the three")
        XCTAssertEqual(coinSurge, 6, "surges sit on five-level milestones, and this is now the ONLY "
                       + "source of them in the entire game (D-026)")

        func packValue(_ id: String) -> Double {
            (ShopConsumables.packs.first { $0.id == id }.map { Double($0.cost) } ?? 0) / 3
        }
        let chargeValue = Double(slowMo) * packValue("slowMoPack")
            + Double(speedUp) * packValue("speedUpPack")
            + Double(shield) * packValue("shieldPack")
        let total = Double(directCoins) + chargeValue

        // The permanent catalogue the giveaway must not swamp.
        let catalogue = 83_500.0
        XCTAssertLessThan(total / catalogue, 0.15, String(format:
            "the L1→L30 giveaway is %.0f coins of priceable value — %.0f%% of the whole %.0f-coin "
            + "catalogue. Above ~15%% it stops being an on-ramp and starts replacing the only sinks "
            + "that alter play.", total, total / catalogue * 100, catalogue))
    }

    func testLevelGrantWatermarkIdempotent() async {
        // Simulated cloud merge to L9 with grants already paid there (watermark 9).
        var p = Profile(); p.totalXP = 6_600; p.xpLevelRewarded = 9
        let store = ProfileStore(testing: p)
        var run = RunSummary(); run.distance = 15_000   // 1,500 + 10 combo = 1,510 XP → L10
        let r = store.applyRunSummary(run, now: utc(2026, 6, 10))
        XCTAssertEqual(r.levelBefore, 9)
        XCTAssertEqual(r.levelAfter, 10)
        XCTAssertEqual(r.coinsGranted, 60, "pays ONLY the newly crossed L10, never L2–L9 again")
        XCTAssertEqual(store.profile.xpLevelRewarded, 10)

        // Watermark ABOVE the reached level (other device is further): nothing pays.
        var q = Profile(); q.totalXP = 6_600; q.xpLevelRewarded = 12
        let store2 = ProfileStore(testing: q)
        let r2 = store2.applyRunSummary(run, now: utc(2026, 6, 10))
        XCTAssertEqual(r2.levelAfter, 10)
        XCTAssertEqual(r2.coinsGranted, 0, "watermark never pays the same level twice")
        XCTAssertEqual(store2.profile.coins, 0)
        XCTAssertEqual(store2.profile.xpLevelRewarded, 12, "watermark only ratchets up")
    }

    func testBestDistanceByWorldTracksTraversedWorlds() async {
        let store = ProfileStore(testing: Profile())
        let now = utc(2026, 6, 10)

        // Full run, 2,000 m: clears worlds 0+1 (800 each), 400 m into world 2.
        var full = RunSummary(); full.distance = 2_000; full.worldsCrossed = 3
        store.applyRunSummary(full, now: now)
        XCTAssertEqual(store.profile.bestDistanceByWorld, [0: 800, 1: 800, 2: 400])

        // Checkpoint run from world 2, 1,000 m: world 2 completes (max), world 3 gets 200 —
        // worlds 0/1 untouched (the head-start earns nothing, R14).
        var cp = RunSummary(); cp.distance = 1_000; cp.worldsCrossed = 4; cp.startWorld = 2
        store.applyRunSummary(cp, now: now)
        XCTAssertEqual(store.profile.bestDistanceByWorld, [0: 800, 1: 800, 2: 800, 3: 200])
    }

    // MARK: weekly missions

    func testWeeklySlotsDeterministic() async {
        for week in [0, 1, 2_944, 2_945, 99_999] {
            let a = MissionCatalog.weeklySlots(weeksSinceEpoch: week)
            let b = MissionCatalog.weeklySlots(weeksSinceEpoch: week)
            XCTAssertEqual(a.map(\.id), b.map(\.id), "same week → identical board")
            XCTAssertEqual(a.count, 3)
            XCTAssertEqual(Set(a.map(\.id)).count, 3, "slots must be distinct")
            for m in a {
                if case .weekly = m.scope {} else { XCTFail("weekly slots must come from the weekly pool") }
                XCTAssertTrue(m.id.hasPrefix("wk."))
            }
        }
        // Boards rotate across weeks (C(7,3) combos — a frozen board means broken seeding).
        let boards = (0..<8).map { MissionCatalog.weeklySlots(weeksSinceEpoch: 2_940 + $0).map(\.id) }
        XCTAssertGreaterThan(Set(boards).count, 1, "weekly boards must rotate")
        // Stream isolation: the WEEKLY13 domain tag draws from its own pool — day 0's board and
        // week 0's board share nothing (and neither stream ever feeds startRun seeds).
        let day0 = Set(MissionCatalog.dailySlots(daysSinceEpoch: 0).map(\.id))
        let week0 = Set(MissionCatalog.weeklySlots(weeksSinceEpoch: 0).map(\.id))
        XCTAssertTrue(day0.isDisjoint(with: week0))
    }

    func testWeeklyRolloverWipesProgressAndClaims() async {
        let store = ProfileStore(testing: Profile())
        let w0 = weekStart(of: utc(2026, 6, 10))
        let sameWeek = w0.addingTimeInterval(86_400)       // day 1 of the same UTC week
        let nextWeek = w0.addingTimeInterval(7 * 86_400)   // day 0 of the next week

        // Complete + claim one of this week's slots in a single run.
        let slot = store.weeklyMissions(now: w0).first { $0.metric != .runsFinished }!
        store.applyRunSummary(summary(slot.metric, slot.target), now: w0)
        XCTAssertTrue(store.missionState(slot, now: w0).claimable)
        let coinsBefore = store.profile.coins
        XCTAssertEqual(store.claimMission(slot.id, now: w0), slot.rewardCoins)
        XCTAssertEqual(store.profile.coins, coinsBefore + slot.rewardCoins)
        XCTAssertTrue(store.profile.claimedMissions.contains(slot.id))

        // A weekly mission OUTSIDE this week's 3 slots can never be claimed (quiet accumulation).
        let slotIDs = Set(store.weeklyMissions(now: w0).map(\.id))
        let offBoard = MissionCatalog.weeklyPool.first { !slotIDs.contains($0.id) }!
        store.mutate { $0.missionProgress[offBoard.id] = offBoard.target }
        XCTAssertNil(store.claimMission(offBoard.id, now: w0), "only this week's slots pay")

        // Same week, next day: board + claim untouched.
        _ = store.weeklyMissions(now: sameWeek)
        XCTAssertTrue(store.profile.claimedMissions.contains(slot.id))

        // Next UTC week: weekly progress + claims wiped, board starts clean.
        _ = store.weeklyMissions(now: nextWeek)
        XCTAssertNil(store.profile.missionProgress[slot.id], "weekly progress resets per UTC week")
        XCTAssertFalse(store.profile.claimedMissions.contains(slot.id), "weekly claims reset per UTC week")
    }

    func testWeeklyClockRollbackBlocked() async {
        let store = ProfileStore(testing: Profile())
        let w0 = weekStart(of: utc(2026, 6, 10))
        let slot = store.weeklyMissions(now: w0).first { $0.metric != .runsFinished }!
        store.applyRunSummary(summary(slot.metric, slot.target), now: w0)
        XCTAssertEqual(store.claimMission(slot.id, now: w0), slot.rewardCoins)

        // Clock set back a week: min(last, now) keeps the claimed board — no re-roll, no re-claim.
        let past = w0.addingTimeInterval(-8 * 86_400)
        store.refreshWeeklyMissions(now: past)
        XCTAssertTrue(store.profile.claimedMissions.contains(slot.id), "rollback can't wipe the claim")
        XCTAssertEqual(store.profile.weeklyMissionDate, w0, "board not re-rolled")
        XCTAssertNil(store.claimMission(slot.id, now: past), "no double pay after rollback")
    }

    func testUnclaimedCountIncludesWeekly() async {
        let store = ProfileStore(testing: Profile())
        let w0 = weekStart(of: utc(2026, 6, 10))
        XCTAssertEqual(store.unclaimedCount(now: w0), 0)
        let slot = store.weeklyMissions(now: w0)[0]
        store.mutate { $0.missionProgress[slot.id] = slot.target }
        XCTAssertEqual(store.unclaimedCount(now: w0), 1, "weekly slots feed the menu badge")
    }

    // MARK: style coins (pure helper — the per-death delta wiring lands in GameView, wave 5)

    /// v2.1 (S-011): style coins are **uncapped** and count streaks. The old test's headline
    /// assertion was "45 events hard-cap at 40 × 2" — that cap is exactly what made skill 6% of a
    /// payout while gems carried 76–87%, and the owner's call was that skill should pay much more.
    /// What this pins now is that the term GROWS without bound, that a streak is worth more than the
    /// same near-misses scattered, and that the doubler still applies because this IS currency.
    func testStyleCoinsAreUncappedAndRewardStreaks() async {
        let rate = Tuning.styleCoinRate, surge = Tuning.flowSurgeCoins

        // Linear in volume, with no ceiling anywhere.
        XCTAssertEqual(XPCurve.styleCoins(closes: 10, slicks: 5, surges: 0, multiplier: 1), 15 * rate)
        XCTAssertEqual(XPCurve.styleCoins(closes: 30, slicks: 15, surges: 0, multiplier: 1), 45 * rate)
        XCTAssertEqual(XPCurve.styleCoins(closes: 300, slicks: 0, surges: 0, multiplier: 1), 300 * rate,
                       "no cap — a 300-near-miss run must pay for all 300")

        // Composure pays on top of volume: the same 45 events are worth more when they came clean.
        let scattered = XPCurve.styleCoins(closes: 45, slicks: 0, surges: 0, multiplier: 1)
        let streaked = XPCurve.styleCoins(closes: 45, slicks: 0, surges: 15, multiplier: 1)
        XCTAssertEqual(streaked - scattered, 15 * surge)
        XCTAssertGreaterThan(streaked, scattered,
                             "a clean line must out-pay the same number of scattered near-misses")

        // The doubler applies to the whole term — style coins ARE currency (unlike XP).
        XCTAssertEqual(XPCurve.styleCoins(closes: 30, slicks: 15, surges: 10, multiplier: 2),
                       (45 * rate + 10 * surge) * 2)
        XCTAssertEqual(XPCurve.styleCoins(closes: 0, slicks: 0, surges: 0, multiplier: 2), 0)
    }

    // MARK: daily-challenge placement tiers

    func testChallengeTiersPayOncePerDay() async {
        let store = ProfileStore(testing: Profile())
        let day1 = utc(2026, 6, 10)

        XCTAssertEqual(store.recordChallengeRun(score: 16_000, now: day1), 500, "all 3 tiers at once")
        XCTAssertEqual(store.profile.challengeRewardTier, 3)
        XCTAssertEqual(store.profile.coins, 500)
        XCTAssertEqual(store.recordChallengeRun(score: 20_000, now: day1.addingTimeInterval(3_600)), 0,
                       "same day, tiers already paid")
        XCTAssertEqual(store.profile.coins, 500)
        XCTAssertEqual(store.profile.dailyChallengeBest, 20_000, "best still tracks")

        // Next UTC day: tier watermark resets, tier 1 pays again.
        let day2 = utc(2026, 6, 11)
        XCTAssertEqual(store.recordChallengeRun(score: 1_200, now: day2), 100)
        XCTAssertEqual(store.profile.challengeRewardTier, 1)

        // Mid-day improvement pays exactly the newly crossed increments.
        let store2 = ProfileStore(testing: Profile())
        XCTAssertEqual(store2.recordChallengeRun(score: 800, now: day1), 0, "below tier 1")
        XCTAssertEqual(store2.recordChallengeRun(score: 6_000, now: day1.addingTimeInterval(7_200)), 250,
                       "tiers 1+2 = 100+150")
        XCTAssertEqual(store2.profile.challengeRewardTier, 2)
        XCTAssertEqual(store2.profile.totalCoinsEarned, 250)
    }

    // MARK: schema resilience + sanitize + merge (the six new fields)

    func testProfileDecodesLegacyJSONWithNewFieldsDefaulted() async throws {
        let legacy = #"{"coins":42,"selectedSkin":"ember","ownedSkins":["default","ember"]}"#
        let p = try JSONDecoder().decode(Profile.self, from: legacy.data(using: .utf8)!)
        XCTAssertEqual(p.coins, 42)
        XCTAssertEqual(p.totalXP, 0)
        XCTAssertEqual(p.xpLevelRewarded, 1)
        XCTAssertNil(p.weeklyMissionDate)
        XCTAssertEqual(p.challengeRewardTier, 0)
        XCTAssertEqual(p.seenSkins, ["default"])
        XCTAssertTrue(p.bestDistanceByWorld.isEmpty)
        XCTAssertTrue(p.purchasedWorlds.isEmpty, "v1.4 field defaults — old saves never wipe")

        // Round-trip with all the new fields populated (pins the [Int: Double] keyed encoding too).
        var q = Profile()
        q.totalXP = 12_345
        q.xpLevelRewarded = 12
        q.weeklyMissionDate = Date(timeIntervalSince1970: 1_780_000_000)
        q.challengeRewardTier = 2
        q.seenSkins = ["default", "bolt"]
        q.bestDistanceByWorld = [0: 800, 3: 412.5]
        q.purchasedWorlds = [3, 7]
        let back = try JSONDecoder().decode(Profile.self, from: JSONEncoder().encode(q))
        XCTAssertEqual(back, q)
    }

    func testSanitizedClampsWeeklyDate() async {
        let now = utc(2026, 6, 10)
        var p = Profile()
        p.weeklyMissionDate = utc(2027, 1, 1)
        XCTAssertEqual(ProfileStore.sanitized(p, now: now).weeklyMissionDate, now,
                       "future weekly stamp clamps to now on load")
        var ok = Profile()
        ok.weeklyMissionDate = utc(2026, 6, 1)
        XCTAssertEqual(ProfileStore.sanitized(ok, now: now), ok, "past stamps pass through")
    }

    func testCloudMergeKeepsMaxXPAndWatermark() async {
        var local = Profile()
        local.coins = 100
        local.totalXP = 5_000; local.xpLevelRewarded = 7
        local.seenSkins = ["default", "ember"]
        local.bestDistanceByWorld = [0: 800, 1: 200]
        local.weeklyMissionDate = utc(2026, 6, 8)
        local.challengeRewardTier = 2
        local.purchasedWorlds = [2]

        var remote = Profile()
        remote.coins = 50
        remote.totalXP = 8_000; remote.xpLevelRewarded = 5
        remote.seenSkins = ["default", "bolt"]
        remote.bestDistanceByWorld = [1: 500, 2: 100]
        remote.weeklyMissionDate = utc(2026, 6, 1)
        remote.challengeRewardTier = 3
        remote.purchasedWorlds = [5]

        let m = ProfileStore.merged(local: local, remote: remote)
        XCTAssertEqual(m.totalXP, 8_000, "max wins")
        XCTAssertEqual(m.xpLevelRewarded, 7, "watermark max wins independently")
        XCTAssertEqual(m.seenSkins, ["default", "ember", "bolt"], "monotonic union")
        XCTAssertEqual(m.bestDistanceByWorld, [0: 800, 1: 500, 2: 100], "per-key max")
        XCTAssertEqual(m.purchasedWorlds, [2, 5], "world purchases union — paid unlocks never vanish")
        XCTAssertEqual(m.weeklyMissionDate, utc(2026, 6, 8), "weekly board is device-local — not merged")
        XCTAssertEqual(m.challengeRewardTier, 2, "challenge tier is device-local — not merged")
        XCTAssertEqual(m.coins, 100)

        // Post-merge no double grant: levels below the merged watermark never pay again.
        var p = Profile(); p.totalXP = m.totalXP; p.xpLevelRewarded = m.xpLevelRewarded
        let store = ProfileStore(testing: p)
        let r = store.applyRunSummary(RunSummary(), now: utc(2026, 6, 10))   // 10 XP, no level
        XCTAssertEqual(r.coinsGranted, 0)
        XCTAssertEqual(store.profile.coins, 0, "merge + run never re-pays paid levels")
    }
}
