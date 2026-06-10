import XCTest
@testable import PrismRush

@MainActor
final class RNGTests: XCTestCase {

    /// SplitMix64 is a pure function of its seed.
    func testSplitMixDeterministicSequence() {
        var a = SplitMix64(seed: 0xDEAD_BEEF)
        var b = SplitMix64(seed: 0xDEAD_BEEF)
        for _ in 0..<10_000 {
            XCTAssertEqual(a.next(), b.next())
        }
    }

    func testSplitMixDifferentSeedsDiverge() {
        var a = SplitMix64(seed: 1)
        var b = SplitMix64(seed: 2)
        var differ = false
        for _ in 0..<32 where a.next() != b.next() { differ = true; break }
        XCTAssertTrue(differ, "distinct seeds should produce distinct streams quickly")
    }

    func testUnitInRange() {
        var r = SplitMix64(seed: 99)
        for _ in 0..<100_000 {
            let u = r.unit()
            XCTAssertGreaterThanOrEqual(u, 0)
            XCTAssertLessThan(u, 1)
        }
    }

    /// Same seed → identical 10k-tick run. This is the property the whole test suite relies on.
    func testRunIsReproducible() {
        let h1 = Self.runHash(seed: 0xABCD_1234, ticks: 10_000)
        let h2 = Self.runHash(seed: 0xABCD_1234, ticks: 10_000)
        XCTAssertEqual(h1, h2, "identical seed must yield an identical run")
    }

    func testDifferentSeedsProduceDifferentRuns() {
        let h1 = Self.runHash(seed: 11, ticks: 6_000)
        let h2 = Self.runHash(seed: 22, ticks: 6_000)
        XCTAssertNotEqual(h1, h2, "different seeds should diverge")
    }

    /// Drive a fully deterministic autopilot run and fold every tick's state into a 64-bit hash.
    static func runHash(seed: UInt64, ticks: Int) -> UInt64 {
        let core = GameCore(seed: 1)
        core.startRun(seed: seed)
        var h: UInt64 = 1_469_598_103_934_665_603   // FNV-1a offset basis
        func fold(_ x: UInt64) { h = (h ^ x) &* 1_099_511_628_211 }
        for _ in 0..<ticks {
            Autopilot.drive(core)
            core.tick(Tuning.tickDt)
            fold(core.distance.bitPattern)
            fold(core.px.bitPattern)
            fold(UInt64(bitPattern: Int64(core.score)))
            fold(UInt64(bitPattern: Int64(core.gemCount)))
            fold(UInt64(core.activeObstacles.count))
            fold(UInt64(core.activeGems.count))
            fold(core.mode == .play ? 1 : (core.mode == .over ? 2 : 0))
        }
        return h
    }
}
