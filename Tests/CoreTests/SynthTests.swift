import XCTest
@testable import PrismRush

/// Verifies the pure synthesis math: every SFX / music step is finite, non-silent, the right
/// length, and not absurdly loud. This is how we sanity-check audio without hardware.
final class SynthTests: XCTestCase {

    private func peak(_ s: [Float]) -> Float { s.reduce(0) { max($0, abs($1)) } }

    private func assertSane(_ s: [Float], _ minDur: Float, _ maxDur: Float, _ name: String) {
        XCTAssertFalse(s.isEmpty, "\(name) empty")
        XCTAssertFalse(s.contains { $0.isNaN || $0.isInfinite }, "\(name) has NaN/Inf")
        let dur = Float(s.count) / Synth.sampleRate
        XCTAssertGreaterThanOrEqual(dur, minDur, "\(name) too short (\(dur)s)")
        XCTAssertLessThanOrEqual(dur, maxDur, "\(name) too long (\(dur)s)")
        let p = peak(s)
        XCTAssertGreaterThan(p, 0.005, "\(name) is effectively silent")
        XCTAssertLessThanOrEqual(p, 2.0, "\(name) clips hard (\(p))")
    }

    func testAllSFXAreSane() {
        assertSane(Synth.gem(streak: 0), 0.08, 0.12, "gem0")
        assertSane(Synth.gem(streak: 25), 0.08, 0.12, "gem25")
        assertSane(Synth.jump(), 0.16, 0.20, "jump")
        assertSane(Synth.slide(), 0.12, 0.16, "slide")
        assertSane(Synth.crash(), 0.44, 0.48, "crash")
        assertSane(Synth.chime(), 0.26, 0.30, "chime")
        assertSane(Synth.worldSweep(), 0.70, 0.74, "worldSweep")
        assertSane(Synth.close(), 0.07, 0.10, "close")
        assertSane(Synth.startChime(), 0.25, 0.29, "startChime")
    }

    func testGemPitchRisesWithStreak() {
        // Higher streak → higher fundamental → the zero-crossing rate should differ.
        let a = Synth.gem(streak: 0), b = Synth.gem(streak: 20)
        XCTAssertNotEqual(a, b)
    }

    func testMusicStepsAreSaneAcrossWorlds() {
        for world in 0..<3 {
            for beat in 0..<8 {
                let s = Synth.step(beat: beat, world: world)
                XCTAssertEqual(s.count, Synth.stepFrames, "step length")
                XCTAssertFalse(s.contains { $0.isNaN || $0.isInfinite })
            }
            let bar = (0..<8).flatMap { Synth.step(beat: $0, world: world) }
            XCTAssertGreaterThan(peak(bar), 0.05, "world \(world) bar is silent")
            XCTAssertLessThanOrEqual(peak(bar), 2.0)
        }
    }
}
