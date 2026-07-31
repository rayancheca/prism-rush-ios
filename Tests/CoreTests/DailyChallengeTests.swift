import XCTest
@testable import PrismRush

@MainActor
final class DailyChallengeTests: XCTestCase {

    /// Golden values: these pin the seed derivation forever. If any of these change, every
    /// player's daily track changes — that is a `layoutVersion` bump, not an edit here.
    /// v2.1 (S-011): the default layoutVersion is **11** — THE LADDER PULLED FORWARD (every tier
    /// gate moves, so `maxIndex` and therefore the pattern draw differ from ~150 m onward) plus the
    /// moving-wall swing applied at all distances. The default-arg goldens below are the v11 values.
    ///
    /// The 2026-6-10 v11 value is exactly the pin S-010 pre-armed, which is the point of pre-arming:
    /// the bump is proved to reshuffle the seed space rather than to have been rederived after the
    /// fact to match whatever the code now does.
    ///
    /// Every value here was derived independently, in Python, from the SplitMix64 constants and the
    /// `folded ^ tag ^ (version << 48)` mix — never read back off the Swift it pins. The script
    /// reproduced all seven pre-existing pins BEFORE emitting a new one, which is what makes the new
    /// values trustworthy; a model that cannot rebuild the old pins may not be used to write new ones.
    func testGoldenSeeds() async {
        XCTAssertEqual(DailyChallenge.seed(year: 2026, month: 6, day: 10), 0xD6A1_D120_8B63_B231)
        XCTAssertEqual(DailyChallenge.seed(year: 2026, month: 6, day: 11), 0xF937_67EA_DC39_CCE6)
        XCTAssertEqual(DailyChallenge.seed(year: 2025, month: 12, day: 31), 0x507D_973F_D27E_90AE)
        // Older layout versions stay reachable explicitly — proves each bump reshuffled, not rederived.
        XCTAssertEqual(DailyChallenge.seed(year: 2026, month: 6, day: 10, layoutVersion: 5),
                       0x6390_28BA_85C6_9769)
        XCTAssertEqual(DailyChallenge.seed(year: 2026, month: 6, day: 10, layoutVersion: 6),
                       0xCF1D_7FAA_DFEF_898D)
        XCTAssertEqual(DailyChallenge.seed(year: 2026, month: 6, day: 10, layoutVersion: 7),
                       0xA7A5_9815_BF47_186A)
        XCTAssertEqual(DailyChallenge.seed(year: 2026, month: 6, day: 10, layoutVersion: 8),
                       0x2FC8_A9EA_C0B9_E30F)
        XCTAssertEqual(DailyChallenge.seed(year: 2026, month: 6, day: 10, layoutVersion: 9),
                       0x6BF4_7293_9ED0_79AB)
        XCTAssertEqual(DailyChallenge.seed(year: 2026, month: 6, day: 10, layoutVersion: 10),
                       0x2F9C_F876_7EBE_A5C0)
        // Pre-armed pin for the NEXT layout change (layoutVersion 12).
        XCTAssertEqual(DailyChallenge.seed(year: 2026, month: 6, day: 10, layoutVersion: 12),
                       0x03B5_B844_D08B_98AF, "layoutVersion must reshuffle the whole seed")
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
