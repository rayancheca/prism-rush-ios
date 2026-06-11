import XCTest
@testable import PrismRush

/// Iron rule 4: the spawner gates by prefix index, so the catalogue ORDER is load-bearing.
/// These tests pin the v1.3 order (moving walls LAST), the five-tier ladder, and the exact
/// per-pattern RNG consumption — any drift here silently reshuffles every seeded run and must
/// be a conscious `layoutVersion` decision, never an accident.
@MainActor
final class PatternOrderTests: XCTestCase {

    func testCatalogueOrderAndPatternIdentity() async {
        XCTAssertEqual(Patterns.count, 14)
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

            // Moving walls are EXCLUSIVE to the last index (the prefix gate depends on it).
            XCTAssertEqual(movings, idx == Patterns.count - 1 ? 2 : 0,
                           "moving walls must live only at index \(Patterns.count - 1) (LAST)")
            XCTAssertEqual(rings, idx == 9 ? 1 : 0, "ringArc is index 9")
            XCTAssertEqual(pads, idx == 10 ? 1 : 0, "overdriveRunway is index 10")
            XCTAssertEqual(splits, idx == 12 ? 1 : 0, "splitBar moved to index 12")

            if idx == 10 {
                // The runway is the breather beat: gems + one pad, NOTHING lethal.
                XCTAssertEqual(out.count, 1 + 10 + 8 + 6, "runway = 1 pad + 24 gems")
            }
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
        // Exact five-tier boundaries (260 m / diff 0.18 / 0.45 / 0.6 over diffFullAt 3200).
        XCTAssertEqual(Spawner.maxIndex(forDistance: 0), 5)
        XCTAssertEqual(Spawner.maxIndex(forDistance: 259), 5)
        XCTAssertEqual(Spawner.maxIndex(forDistance: 260), 9)
        XCTAssertEqual(Spawner.maxIndex(forDistance: 575), 9)
        XCTAssertEqual(Spawner.maxIndex(forDistance: 576), 11)
        XCTAssertEqual(Spawner.maxIndex(forDistance: 1_439), 11)
        XCTAssertEqual(Spawner.maxIndex(forDistance: 1_440), 13)
        XCTAssertEqual(Spawner.maxIndex(forDistance: 1_919), 13)
        XCTAssertEqual(Spawner.maxIndex(forDistance: 1_920), Patterns.count)

        // Per-pattern RNG call counts, pinned exactly (0–8 unchanged; 9:1, 10:1, 11:1, 12:2, 13:0).
        let expected = [1, 1, 0, 1, 1, 3, 1, 2, 0, 1, 1, 1, 2, 0]
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
