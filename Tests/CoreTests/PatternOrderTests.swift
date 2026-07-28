import XCTest
@testable import PrismRush

/// Iron rule 4: the spawner gates by prefix index, so the catalogue ORDER is load-bearing.
/// These tests pin the order, the SIX-tier ladder, and the exact per-pattern RNG consumption — any
/// drift here silently reshuffles every seeded run and must be a conscious `layoutVersion`
/// decision, never an accident.
///
/// v1.8 amends the old "moving walls stay LAST" shorthand. Tier six put the chasm behind them, so
/// the pins below are on the LITERAL indices each pattern occupies (moving walls 13, chasm 14)
/// rather than on `Patterns.count - 1`. The rule's real content — every tier is a prefix, and a
/// pattern's index is its unlock rank — is what the ladder test enforces.
@MainActor
final class PatternOrderTests: XCTestCase {

    func testCatalogueOrderAndPatternIdentity() async {
        XCTAssertEqual(Patterns.count, 15)
        for idx in 0..<Patterns.count {
            var rng = SplitMix64(seed: 42)
            var out: [SpawnCmd] = []
            let len = Patterns.run(idx, base: 100, rng: &rng, out: &out)
            XCTAssertGreaterThan(len, 0)

            func n(_ matches: (SpawnCmd) -> Bool) -> Int { out.filter(matches).count }
            let movings = n { if case .movingTall = $0 { return true }; return false }
            let rings = n { if case .ring = $0 { return true }; return false }
            let pads = n { if case .boostPad = $0 { return true }; return false }
            let splits = n { if case .splitBar = $0 { return true }; return false }
            let chasms = n { if case .chasm = $0 { return true }; return false }

            // Each late unlock is EXCLUSIVE to its index — the prefix gate depends on it.
            XCTAssertEqual(movings, idx == 13 ? 2 : 0, "moving walls must live only at index 13")
            XCTAssertEqual(rings, idx == 9 ? 1 : 0, "ringArc is index 9")
            XCTAssertEqual(pads, idx == 10 ? 1 : 0, "overdriveRunway is index 10")
            XCTAssertEqual(splits, idx == 12 ? 1 : 0, "splitBar moved to index 12")
            XCTAssertEqual(chasms, idx == 14 ? 1 : 0, "the chasm is index 14 — the sole tier-six unlock")

            if idx == 10 {
                // The runway is the breather beat: gems + one pad, NOTHING lethal.
                XCTAssertEqual(out.count, 1 + 10 + 8 + 6, "runway = 1 pad + 24 gems")
            }
            if idx == 14 {
                // 3 run-up gems + a 7-gem ballistic arc + exactly one gap, and nothing else: this
                // pattern prices TIMING, so it must never grow a second hazard to read.
                XCTAssertEqual(out.count, 3 + 7 + 1, "the chasm pattern = 10 gems + 1 gap")
            }
        }
    }

    /// The chasm's gap must sit where the arc's jump is highest, or its two-sided window stops being
    /// symmetric and the pattern turns into a coin flip at one end of the speed range.
    ///
    /// Derived independently of `Patterns` from the ballistic constants: with `y(t) = v0·t − g·t²/2`,
    /// the feet clear `chasmClearance` between the two roots, and the launch cue is arc gem 0. The
    /// check is that the launch may be equally early or late — the margins on the two sides match.
    func testChasmSitsAtTheApexSoItsWindowIsSymmetric() async {
        let v0 = Tuning.jumpV0, g = Tuning.gravity, c = Tuning.chasmClearance
        let disc = (v0 * v0 - 2 * g * c).squareRoot()
        let tIn = (v0 - disc) / g, tOut = (v0 + disc) / g        // airborne-above-clearance window

        for base in [2_560.0, 3_200, 5_000, 9_600] {
            var rng = SplitMix64(seed: 7)
            var out: [SpawnCmd] = []
            _ = Patterns.run(14, base: base, rng: &rng, out: &out)

            let gems = out.compactMap { cmd -> Double? in
                if case let .gem(d, _, _) = cmd { return d }; return nil
            }.sorted()
            let launch = gems[3]                                  // arc gem 0 (after 3 run-up gems)
            guard let centre = out.compactMap({ cmd -> Double? in
                if case let .chasm(d) = cmd { return d }; return nil
            }).first else { return XCTFail("pattern 14 placed no chasm at base \(base)") }

            let v = min(Tuning.speedCap, Tuning.speedStart + launch * Tuning.speedRamp)
            // How far the launch may drift late (feet still up at the near rim) and early (feet
            // still up at the far rim), in metres of track.
            let slackLate = (centre - Tuning.chasmHalfLength) - (launch + tIn * v)
            let slackEarly = (launch + tOut * v) - (centre + Tuning.chasmHalfLength)

            XCTAssertEqual(slackLate, slackEarly, accuracy: 0.05,
                           "the gap must be centred on the apex at base \(base)")
            XCTAssertGreaterThan(slackLate / v, 0.20,
                                 "launch slack must stay near jumpBuffer (base \(base))")
        }
    }

    /// The sixth tier must not disturb the five below it. Every band under `chasmDiff` has to draw
    /// from exactly the same range as v1.7 did — `maxIndex` there returns 14, which is what
    /// `Patterns.count` used to evaluate to. If someone "tidies" that literal into `Patterns.count`,
    /// tier five silently gains the tier-six pattern and every seeded run below 2,560 m changes.
    func testSixthTierLeavesTheEarlierLadderByteIdentical() async {
        let v17Ladder: [(Double, Int)] = [
            (0, 5), (259, 5), (260, 9), (575, 9), (576, 11),
            (1_439, 11), (1_440, 13), (1_919, 13), (1_920, 14), (2_559, 14),
        ]
        for (d, want) in v17Ladder {
            XCTAssertEqual(Spawner.maxIndex(forDistance: d), want,
                           "tier ladder below chasmDiff must match v1.7 exactly (d=\(d))")
        }
        // And act one below the gate never draws the chasm at all.
        for d in stride(from: 0.0, to: Tuning.chasmDiff * Tuning.diffFullAt, by: 20) {
            XCTAssertLessThanOrEqual(Spawner.maxIndex(forDistance: d), 14,
                                     "the chasm must not be selectable at d=\(d)")
        }
    }

    func testTierLadderMonotoneAndRNGCountsPinned() async {
        // Monotone non-decreasing availability across the whole ramp.
        var prev = 0
        for d in stride(from: 0.0, through: 6_400, by: 4) {
            let m = Spawner.maxIndex(forDistance: d)
            XCTAssertGreaterThanOrEqual(m, prev, "maxIndex must never shrink (d=\(d))")
            XCTAssertLessThanOrEqual(m, Patterns.count)
            prev = m
        }
        // Exact six-tier boundaries (260 m / diff 0.18 / 0.45 / 0.6 / 0.8 over diffFullAt 3200).
        XCTAssertEqual(Spawner.maxIndex(forDistance: 0), 5)
        XCTAssertEqual(Spawner.maxIndex(forDistance: 259), 5)
        XCTAssertEqual(Spawner.maxIndex(forDistance: 260), 9)
        XCTAssertEqual(Spawner.maxIndex(forDistance: 575), 9)
        XCTAssertEqual(Spawner.maxIndex(forDistance: 576), 11)
        XCTAssertEqual(Spawner.maxIndex(forDistance: 1_439), 11)
        XCTAssertEqual(Spawner.maxIndex(forDistance: 1_440), 13)
        XCTAssertEqual(Spawner.maxIndex(forDistance: 1_919), 13)
        XCTAssertEqual(Spawner.maxIndex(forDistance: 1_920), 14)
        XCTAssertEqual(Spawner.maxIndex(forDistance: 2_559), 14)
        XCTAssertEqual(Spawner.maxIndex(forDistance: 2_560), Patterns.count)   // diff 0.8 → the chasm
        // Act two's draw table bypasses `maxIndex`, so tier six MUST be open before act two starts
        // or the table can spawn a pattern the ladder has not unlocked.
        XCTAssertLessThanOrEqual(Tuning.chasmDiff * Tuning.diffFullAt, Tuning.actTwoAt)

        // Per-pattern RNG call counts, pinned exactly (0–8 unchanged; 9:1, 10:1, 11:1, 12:2, 13:0,
        // 14:1 — the chasm draws only its lane; its placement is pure f(d)).
        let expected = [1, 1, 0, 1, 1, 3, 1, 2, 0, 1, 1, 1, 2, 0, 1]
        for (idx, want) in expected.enumerated() {
            XCTAssertEqual(Self.rngCalls(forPattern: idx), want,
                           "pattern \(idx) RNG consumption drifted — that is a layoutVersion decision")
        }
    }

    /// Exact RNG-call counter: SplitMix64 advances its state by a fixed increment per `next()`
    /// and its output is a bijection of state, so probing the post-pattern stream against a
    /// stepped fresh stream recovers the call count with zero ambiguity.
    private static func rngCalls(forPattern idx: Int) -> Int {
        let seed: UInt64 = 0x5EED_0001
        var rng = SplitMix64(seed: seed)
        var out: [SpawnCmd] = []
        _ = Patterns.run(idx, base: 1_000, rng: &rng, out: &out)
        let probe = rng.next()
        for n in 0...8 {
            var fresh = SplitMix64(seed: seed)
            for _ in 0..<n { _ = fresh.next() }
            if fresh.next() == probe { return n }
        }
        return -1
    }
}
