import XCTest
@testable import PrismRush

@MainActor
final class DailyChallengeTests: XCTestCase {

    /// Golden values: these pin the seed derivation forever. If any of these change, every
    /// player's daily track changes — that is a `layoutVersion` bump, not an edit here.
    /// v1.5: the default layoutVersion is 3 (Super Sneakers re-banded pattern 7's pickup roll) —
    /// the default-arg goldens below are the v3 values, recomputed from source. The 2026-6-10 v3
    /// value matches the v1.4 pre-armed pin (the bump was prepared in advance).
    func testGoldenSeeds() async {
        XCTAssertEqual(DailyChallenge.seed(year: 2026, month: 6, day: 10), 0xB51F_E337_DB06_ED2F)
        XCTAssertEqual(DailyChallenge.seed(year: 2026, month: 6, day: 11), 0x644F_F394_241B_D0A0)
        XCTAssertEqual(DailyChallenge.seed(year: 2025, month: 12, day: 31), 0x62BC_53E4_169D_95E0)
        // Older layout versions stay reachable explicitly — proves each bump reshuffled, not rederived.
        XCTAssertEqual(DailyChallenge.seed(year: 2026, month: 6, day: 10, layoutVersion: 1),
                       0xFBC0_C337_38F0_2209)
        XCTAssertEqual(DailyChallenge.seed(year: 2026, month: 6, day: 10, layoutVersion: 2),
                       0x1030_754F_4336_7811)
        // Pre-armed pin for the NEXT spawn-stream change (layoutVersion 4).
        XCTAssertEqual(DailyChallenge.seed(year: 2026, month: 6, day: 10, layoutVersion: 4),
                       0x2E28_5014_7596_8B7D, "layoutVersion must reshuffle the whole seed")
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
