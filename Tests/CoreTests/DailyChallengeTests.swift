import XCTest
@testable import PrismRush

@MainActor
final class DailyChallengeTests: XCTestCase {

    /// Golden values: these pin the seed derivation forever. If any of these change, every
    /// player's daily track changes — that is a `layoutVersion` bump, not an edit here.
    /// v2.3 (S-013): the default layoutVersion is **12** — THE WARDEN, MADE A FIGHT.
    /// `wardenArenaLength` 660 → 770, so 110 m more of every third world is kept clear of spawned
    /// obstacles. Like the v10 bump the seeded spawn STREAM is byte-identical; what changes is which
    /// of its output survives `Warden.suppresses`. The default-arg goldens below are the v12 values.
    ///
    /// The 2026-6-10 v12 value is exactly the pin S-012 pre-armed, which is the point of pre-arming:
    /// the bump is proved to reshuffle the seed space rather than to have been rederived after the
    /// fact to match whatever the code now does.
    ///
    /// Every value here was derived independently, in Python, from the SplitMix64 constants and the
    /// `folded ^ tag ^ (version << 48)` mix — never read back off the Swift it pins. The script
    /// reproduced all EIGHT pre-existing pins BEFORE emitting a new one, which is what makes the new
    /// values trustworthy; a model that cannot rebuild the old pins may not be used to write new ones.
    func testGoldenSeeds() async {
        XCTAssertEqual(DailyChallenge.seed(year: 2026, month: 6, day: 10), 0x03B5_B844_D08B_98AF)
        XCTAssertEqual(DailyChallenge.seed(year: 2026, month: 6, day: 11), 0x440D_2303_981F_5A63)
        XCTAssertEqual(DailyChallenge.seed(year: 2025, month: 12, day: 31), 0x6FFD_8C22_9B59_C919)
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
        XCTAssertEqual(DailyChallenge.seed(year: 2026, month: 6, day: 10, layoutVersion: 11),
                       0xD6A1_D120_8B63_B231)
        // Pre-armed pin for the NEXT layout change (layoutVersion 13).
        XCTAssertEqual(DailyChallenge.seed(year: 2026, month: 6, day: 10, layoutVersion: 13),
                       0x9E49_3424_C18A_59C5, "layoutVersion must reshuffle the whole seed")
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
