import XCTest
@testable import PrismRush

@MainActor
final class DailyChallengeTests: XCTestCase {

    /// Golden values: these pin the seed derivation forever. If any of these change, every
    /// player's daily track changes — that is a `layoutVersion` bump, not an edit here.
    /// v1.7: the default layoutVersion is 8 (the second act + risk-priced gems) — the default-arg
    /// goldens below are the v8 values. The 2026-6-10 v8 value is exactly the pin that was pre-armed
    /// when v7 shipped, which is the point of pre-arming: the bump is proved to reshuffle the seed
    /// space rather than rederive it.
    func testGoldenSeeds() async {
        XCTAssertEqual(DailyChallenge.seed(year: 2026, month: 6, day: 10), 0x2FC8_A9EA_C0B9_E30F)
        XCTAssertEqual(DailyChallenge.seed(year: 2026, month: 6, day: 11), 0xBFF2_6A8C_F071_4E3A)
        XCTAssertEqual(DailyChallenge.seed(year: 2025, month: 12, day: 31), 0xA85E_D821_2B32_0A21)
        // Older layout versions stay reachable explicitly — proves each bump reshuffled, not rederived.
        XCTAssertEqual(DailyChallenge.seed(year: 2026, month: 6, day: 10, layoutVersion: 5),
                       0x6390_28BA_85C6_9769)
        XCTAssertEqual(DailyChallenge.seed(year: 2026, month: 6, day: 10, layoutVersion: 6),
                       0xCF1D_7FAA_DFEF_898D)
        XCTAssertEqual(DailyChallenge.seed(year: 2026, month: 6, day: 10, layoutVersion: 7),
                       0xA7A5_9815_BF47_186A)
        // Pre-armed pin for the NEXT spawn-stream change (layoutVersion 9).
        XCTAssertEqual(DailyChallenge.seed(year: 2026, month: 6, day: 10, layoutVersion: 9),
                       0x6BF4_7293_9ED0_79AB, "layoutVersion must reshuffle the whole seed")
    }

    func testConsecutiveDatesDiffer() async {
        var prev = DailyChallenge.seed(year: 2026, month: 1, day: 1)
        for day in 2...28 {
            let s = DailyChallenge.seed(year: 2026, month: 1, day: day)
            XCTAssertNotEqual(s, prev, "consecutive dates must produce distinct seeds")
            prev = s
        }
    }

    /// Two cores started from the same daily seed play the identical run — the property the
    /// shared daily leaderboard stands on.
    func testSameDailySeedYieldsIdenticalRun() async {
        let seed = DailyChallenge.seed(year: 2026, month: 6, day: 10)
        let h1 = RNGTests.runHash(seed: seed, ticks: 10_000)
        let h2 = RNGTests.runHash(seed: seed, ticks: 10_000)
        XCTAssertEqual(h1, h2, "same daily seed must yield an identical run")
    }
}
