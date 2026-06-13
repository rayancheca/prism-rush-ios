import XCTest
@testable import PrismRush

@MainActor
final class DailyChallengeTests: XCTestCase {

    /// Golden values: these pin the seed derivation forever. If any of these change, every
    /// player's daily track changes — that is a `layoutVersion` bump, not an edit here.
    /// v1.6: the default layoutVersion is 5 (power-up cadence + path-aware coin trail add track
    /// entities) — the default-arg goldens below are the v5 values. The 2026-6-10 v5 value matches
    /// the pre-armed pin (the bump was prepared in advance).
    func testGoldenSeeds() async {
        XCTAssertEqual(DailyChallenge.seed(year: 2026, month: 6, day: 10), 0x6390_28BA_85C6_9769)
        XCTAssertEqual(DailyChallenge.seed(year: 2026, month: 6, day: 11), 0x1515_F24A_C394_6BBB)
        XCTAssertEqual(DailyChallenge.seed(year: 2025, month: 12, day: 31), 0xA68F_473F_23FF_E012)
        // Older layout versions stay reachable explicitly — proves each bump reshuffled, not rederived.
        XCTAssertEqual(DailyChallenge.seed(year: 2026, month: 6, day: 10, layoutVersion: 3),
                       0xB51F_E337_DB06_ED2F)
        XCTAssertEqual(DailyChallenge.seed(year: 2026, month: 6, day: 10, layoutVersion: 4),
                       0x2E28_5014_7596_8B7D)
        // Pre-armed pin for the NEXT spawn-stream change (layoutVersion 6).
        XCTAssertEqual(DailyChallenge.seed(year: 2026, month: 6, day: 10, layoutVersion: 6),
                       0xCF1D_7FAA_DFEF_898D, "layoutVersion must reshuffle the whole seed")
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
