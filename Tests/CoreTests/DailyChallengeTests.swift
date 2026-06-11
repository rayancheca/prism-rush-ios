import XCTest
@testable import PrismRush

@MainActor
final class DailyChallengeTests: XCTestCase {

    /// Golden values: these pin the seed derivation forever. If any of these change, every
    /// player's daily track changes — that is a `layoutVersion` bump, not an edit here.
    /// v1.3: the default layoutVersion is 2 (ballistic arc + ring/overdrive patterns + reorder +
    /// anti-repeat) — the default-arg goldens below are the v2 values, recomputed from source.
    func testGoldenSeeds() async {
        XCTAssertEqual(DailyChallenge.seed(year: 2026, month: 6, day: 10), 0x1030_754F_4336_7811)
        XCTAssertEqual(DailyChallenge.seed(year: 2026, month: 6, day: 11), 0x3973_7E07_D8FE_555B)
        XCTAssertEqual(DailyChallenge.seed(year: 2025, month: 12, day: 31), 0x57C7_C353_244E_064B)
        // The v1 golden stays reachable explicitly — proves the bump reshuffled, not rederived.
        XCTAssertEqual(DailyChallenge.seed(year: 2026, month: 6, day: 10, layoutVersion: 1),
                       0xFBC0_C337_38F0_2209)
        // Pre-armed pin for the NEXT spawn-stream change (layoutVersion 3).
        XCTAssertEqual(DailyChallenge.seed(year: 2026, month: 6, day: 10, layoutVersion: 3),
                       0xB51F_E337_DB06_ED2F, "layoutVersion must reshuffle the whole seed")
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
