import XCTest
@testable import PrismRush

/// Missions, achievements, and the daily-challenge meta layer (ProfileStore + MissionCatalog).
/// Everything is `now:`-injectable and UTC-based, so rollover and determinism are pinned exactly.
@MainActor
final class MissionsTests: XCTestCase {

    // MARK: helpers

    /// A specific instant in UTC (daily missions/challenge roll over at UTC midnight).
    private func utc(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12, _ min: Int = 0) -> Date {
        var c = DateComponents()
        c.year = y; c.month = m; c.day = d; c.hour = h; c.minute = min
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal.date(from: c)!
    }

    /// A run summary that scores `value` on `metric` (and nothing else).
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
        case .revives: s.revives = Int(value)
        case .multiplierHit: s.bestMult = Int(value)
        }
        return s
    }

    // MARK: daily slot rotation — determinism + rollover

    func testDailySlotsAreDeterministicPerDay() async {
        for day in [0, 1, 20_614, 20_615, 999_999] {
            let a = MissionCatalog.dailySlots(daysSinceEpoch: day)
            let b = MissionCatalog.dailySlots(daysSinceEpoch: day)
            XCTAssertEqual(a.map(\.id), b.map(\.id), "same day → identical board")
            XCTAssertEqual(a.count, 3)
            XCTAssertEqual(Set(a.map(\.id)).count, 3, "slots must be distinct")
            for m in a {
                if case .daily = m.scope {} else { XCTFail("daily slots must come from the daily pool") }
            }
        }
    }

    func testDailySlotsRotateAcrossDays() async {
        // Boards on consecutive days won't always differ (C(8,3) combinations), but across a week
        // there must be variety — a frozen board means the seeding is broken.
        let boards = (0..<7).map { MissionCatalog.dailySlots(daysSinceEpoch: 20_600 + $0).map(\.id) }
        XCTAssertGreaterThan(Set(boards).count, 1, "daily boards must rotate")
    }

    func testDailyBoardRolloverResetsProgressAndClaims() async {
        let store = ProfileStore(testing: Profile())
        let day1 = utc(2026, 6, 10)
        let day2 = utc(2026, 6, 11)

        // Pick a non-chest slot from day 1's board and complete it.
        let slot = store.dailyMissions(now: day1).first { $0.metric != .chestsOpened }!
        store.applyRunSummary(summary(slot.metric, slot.target), now: day1)
        XCTAssertTrue(store.missionState(slot, now: day1).claimable)
        XCTAssertEqual(store.claimMission(slot.id, now: day1), slot.rewardCoins)
        XCTAssertTrue(store.profile.claimedMissions.contains(slot.id))

        // Next UTC day: board regenerates, daily progress + claims are wiped.
        _ = store.dailyMissions(now: day2)
        XCTAssertNil(store.profile.missionProgress[slot.id], "daily progress resets at UTC midnight")
        XCTAssertFalse(store.profile.claimedMissions.contains(slot.id), "daily claims reset at UTC midnight")
    }

    func testDailyMissionAccumulatesAcrossRunsWithinADay() async {
        let store = ProfileStore(testing: Profile())
        let now = utc(2026, 6, 10)
        let slot = store.dailyMissions(now: now).first { !$0.metric.accumulatesByMax && $0.metric != .chestsOpened }!
        let half = slot.target / 2
        store.applyRunSummary(summary(slot.metric, half), now: now)
        XCTAssertFalse(store.missionState(slot, now: now).claimable)
        store.applyRunSummary(summary(slot.metric, half), now: now)
        XCTAssertTrue(store.missionState(slot, now: now).claimable, "daily missions sum across runs")
    }

    // MARK: per-run missions

    func testPerRunMissionTracksBestSingleRunNotSum() async {
        let store = ProfileStore(testing: Profile())
        let now = utc(2026, 6, 10)
        // Three slides per run, twice: a "slide 5 in one run" mission must NOT be satisfied.
        store.applyRunSummary(summary(.slides, 3), now: now)
        store.applyRunSummary(summary(.slides, 3), now: now)
        XCTAssertEqual(store.profile.missionProgress["run.slide5"], 3, "per-run = best single run")
        XCTAssertFalse(store.missionState(MissionCatalog.mission("run.slide5")!, now: now).claimable)
        // One run with 5 slides satisfies it.
        store.applyRunSummary(summary(.slides, 5), now: now)
        XCTAssertTrue(store.missionState(MissionCatalog.mission("run.slide5")!, now: now).claimable)
    }

    func testMultiplierMissionUsesMaxSemantics() async {
        let store = ProfileStore(testing: Profile())
        let now = utc(2026, 6, 10)
        store.applyRunSummary(summary(.multiplierHit, 3), now: now)
        store.applyRunSummary(summary(.multiplierHit, 4), now: now)
        XCTAssertEqual(store.profile.missionProgress["run.mult5"], 4, "max, never summed (3+4 ≠ 7)")
        store.applyRunSummary(summary(.multiplierHit, 5), now: now)
        XCTAssertEqual(store.claimMission("run.mult5", now: now), 150)
    }

    func testClaimOnceSemantics() async {
        let store = ProfileStore(testing: Profile())
        let now = utc(2026, 6, 10)
        store.applyRunSummary(summary(.multiplierHit, 5), now: now)
        XCTAssertEqual(store.claimMission("run.mult5", now: now), 150)
        let coinsAfter = store.profile.coins
        XCTAssertNil(store.claimMission("run.mult5", now: now), "second claim pays nothing")
        XCTAssertEqual(store.profile.coins, coinsAfter)
        XCTAssertNil(store.claimMission("run.mult5", now: now.addingTimeInterval(86_400 * 3)),
                     "per-run claims never reset")
    }

    func testClaimIncompleteMissionPaysNothing() async {
        let store = ProfileStore(testing: Profile())
        let now = utc(2026, 6, 10)
        store.applyRunSummary(summary(.multiplierHit, 4), now: now)
        XCTAssertNil(store.claimMission("run.mult5", now: now))
        XCTAssertEqual(store.profile.coins, 0)
        XCTAssertNil(store.claimMission("nope.bogus", now: now), "unknown ids are inert")
    }

    // MARK: tiered achievements

    func testTieredAchievementClaimsInOrder() async {
        let store = ProfileStore(testing: Profile())
        let now = utc(2026, 6, 10)
        // ach.gems tiers: 100 / 1,000 / 10,000 → 50 / 200 / 1,000 coins.
        store.applyRunSummary(summary(.gems, 1_200), now: now)
        let coinsBeforeClaims = store.profile.coins   // v1.3: big runs also pay level-up grants
        XCTAssertEqual(store.claimMission("ach.gems", now: now), 50, "tier 1 pays first")
        XCTAssertEqual(store.profile.achievementTier["ach.gems"], 1)
        XCTAssertEqual(store.claimMission("ach.gems", now: now), 200, "tier 2 unlocked by the same progress")
        XCTAssertEqual(store.profile.achievementTier["ach.gems"], 2)
        XCTAssertNil(store.claimMission("ach.gems", now: now), "tier 3 needs 10,000 lifetime gems")
        XCTAssertEqual(store.profile.coins, coinsBeforeClaims + 250)

        store.applyRunSummary(summary(.gems, 9_000), now: now)   // lifetime 10,200
        XCTAssertEqual(store.claimMission("ach.gems", now: now), 1_000)
        let s = store.missionState(MissionCatalog.mission("ach.gems")!, now: now)
        XCTAssertTrue(s.claimed, "all tiers exhausted")
        XCTAssertEqual(s.tier, 3)
        XCTAssertNil(store.claimMission("ach.gems", now: now))
    }

    func testLifetimeProgressAccumulatesAcrossDaysAndRuns() async {
        let store = ProfileStore(testing: Profile())
        store.applyRunSummary(summary(.distance, 6_000), now: utc(2026, 6, 10))
        store.applyRunSummary(summary(.distance, 5_000), now: utc(2026, 6, 12))
        XCTAssertEqual(store.profile.missionProgress["ach.dist"], 11_000, "lifetime metrics never reset")
        XCTAssertEqual(store.claimMission("ach.dist", now: utc(2026, 6, 12)), 150)
    }

    func testChestOpensFeedChestMissions() async {
        let store = ProfileStore(testing: Profile())
        let t0 = utc(2026, 6, 10, 8)
        XCTAssertEqual(store.openFreeChest(now: t0, reward: 10), 10)
        XCTAssertEqual(store.openFreeChest(now: t0.addingTimeInterval(31 * 60), reward: 10), 10)
        XCTAssertEqual(store.profile.missionProgress["ach.chests"], 2)
        XCTAssertEqual(store.profile.missionProgress["day.chest2"], 2)
    }

    // MARK: badge count

    func testUnclaimedCountTracksClaimableMissions() async {
        let store = ProfileStore(testing: Profile())
        let now = utc(2026, 6, 10)
        XCTAssertEqual(store.unclaimedCount(now: now), 0)
        store.applyRunSummary(summary(.multiplierHit, 5), now: now)   // run.mult5 ready
        XCTAssertEqual(store.unclaimedCount(now: now), 1)
        _ = store.claimMission("run.mult5", now: now)
        XCTAssertEqual(store.unclaimedCount(now: now), 0)
    }

    // MARK: daily challenge

    func testTodaysChallengeSeedMatchesUTCGoldens() async {
        let store = ProfileStore(testing: Profile())
        // Goldens pinned in DailyChallengeTests (layoutVersion 2 as of v1.3).
        XCTAssertEqual(store.todaysChallengeSeed(now: utc(2026, 6, 10)), 0x1030_754F_4336_7811)
        XCTAssertEqual(store.todaysChallengeSeed(now: utc(2026, 6, 11)), 0x3973_7E07_D8FE_555B)
        // 23:59 and 00:01 straddle UTC midnight → different tracks.
        XCTAssertEqual(store.todaysChallengeSeed(now: utc(2026, 6, 10, 23, 59)),
                       store.todaysChallengeSeed(now: utc(2026, 6, 10, 0, 1)))
        XCTAssertNotEqual(store.todaysChallengeSeed(now: utc(2026, 6, 10, 23, 59)),
                          store.todaysChallengeSeed(now: utc(2026, 6, 11, 0, 1)))
    }

    func testChallengeRunKeepsPerDayBestAndDaysPlayed() async {
        let store = ProfileStore(testing: Profile())
        let day1 = utc(2026, 6, 10)
        store.recordChallengeRun(score: 800, now: day1)
        store.recordChallengeRun(score: 1_200, now: day1.addingTimeInterval(3_600))
        store.recordChallengeRun(score: 900, now: day1.addingTimeInterval(7_200))
        XCTAssertEqual(store.todaysChallengeBest(now: day1.addingTimeInterval(8_000)), 1_200, "per-day best is a max")
        XCTAssertTrue(store.profile.challengeDaysPlayed.contains("2026-06-10"))
        XCTAssertTrue(store.playedChallenge(daysAgo: 0, now: day1))
        XCTAssertFalse(store.playedChallenge(daysAgo: 1, now: day1))
    }

    func testChallengeBestResetsAtUTCRollover() async {
        let store = ProfileStore(testing: Profile())
        store.recordChallengeRun(score: 5_000, now: utc(2026, 6, 10, 23, 59))
        XCTAssertEqual(store.todaysChallengeBest(now: utc(2026, 6, 10, 23, 59)), 5_000)
        // Two minutes later it's a new UTC day: yesterday's best no longer shows…
        XCTAssertEqual(store.todaysChallengeBest(now: utc(2026, 6, 11, 0, 1)), 0)
        // …and a weaker run still becomes the new day's best.
        store.recordChallengeRun(score: 300, now: utc(2026, 6, 11, 0, 5))
        XCTAssertEqual(store.todaysChallengeBest(now: utc(2026, 6, 11, 1)), 300)
        XCTAssertTrue(store.playedChallenge(daysAgo: 1, now: utc(2026, 6, 11, 12)), "yesterday's dot stays lit")
    }

    func testSecondsUntilUTCMidnight() async {
        XCTAssertEqual(ProfileStore.secondsUntilUTCMidnight(now: utc(2026, 6, 10, 23, 59)), 60, accuracy: 0.001)
        XCTAssertEqual(ProfileStore.secondsUntilUTCMidnight(now: utc(2026, 6, 10, 0, 0)), 86_400, accuracy: 0.001)
    }

    // MARK: schema resilience (the new fields must never wipe an old save — and vice versa)

    func testLegacyProfileDecodesWithMissionDefaults() async throws {
        let legacy = #"{"coins":777,"selectedSkin":"ember","ownedSkins":["default","ember"]}"#
        let p = try JSONDecoder().decode(Profile.self, from: legacy.data(using: .utf8)!)
        XCTAssertEqual(p.coins, 777)
        XCTAssertTrue(p.missionProgress.isEmpty)
        XCTAssertTrue(p.claimedMissions.isEmpty)
        XCTAssertTrue(p.achievementTier.isEmpty)
        XCTAssertNil(p.dailyMissionDate)
        XCTAssertEqual(p.dailyChallengeBest, 0)
        XCTAssertTrue(p.challengeDaysPlayed.isEmpty)
        XCTAssertEqual(p.musicVolume, 1)
        XCTAssertEqual(p.sfxVolume, 1)
        XCTAssertTrue(p.hapticsEnabled)
    }

    func testProfileWithMissionFieldsRoundTrips() async throws {
        var p = Profile()
        p.missionProgress = ["ach.gems": 512, "day.runs5": 3]
        p.claimedMissions = ["run.mult5"]
        p.achievementTier = ["ach.gems": 1]
        p.dailyMissionDate = Date(timeIntervalSince1970: 1_780_000_000)
        p.dailyChallengeBest = 4_242
        p.dailyChallengeDate = Date(timeIntervalSince1970: 1_780_000_500)
        p.challengeDaysPlayed = ["2026-06-10", "2026-06-09"]
        p.musicVolume = 0.4
        p.sfxVolume = 0.7
        p.hapticsEnabled = false
        let back = try JSONDecoder().decode(Profile.self, from: JSONEncoder().encode(p))
        XCTAssertEqual(back, p)
    }
}
