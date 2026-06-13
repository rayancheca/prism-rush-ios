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

    func testNewSFXAreSane() {
        assertSane(Synth.shieldChime(), 0.40, 0.44, "shieldChime")
        assertSane(Synth.magnetChime(), 0.40, 0.44, "magnetChime")
        assertSane(Synth.laneTick(), 0.03, 0.05, "laneTick")
        assertSane(Synth.landThud(), 0.12, 0.16, "landThud")
        assertSane(Synth.purchaseChime(), 0.45, 0.55, "purchaseChime")
        assertSane(Synth.equipClick(), 0.04, 0.08, "equipClick")
        assertSane(Synth.uiTick(), 0.04, 0.07, "uiTick")
        assertSane(Synth.newBestFanfare(), 0.70, 0.80, "newBestFanfare")
        assertSane(Synth.deathSweep(), 0.88, 0.96, "deathSweep")
        assertSane(Synth.doublerPickup(), 0.28, 0.32, "doublerPickup")
        assertSane(Synth.frenzyStart(), 0.40, 0.44, "frenzyStart")
        assertSane(Synth.frenzyEnd(), 0.40, 0.44, "frenzyEnd")
    }

    func testGemPitchRisesWithStreak() {
        // Higher streak → higher fundamental → the zero-crossing rate should differ.
        let a = Synth.gem(streak: 0), b = Synth.gem(streak: 20)
        XCTAssertNotEqual(a, b)
        // The ladder must be an audible step (≥ ~a semitone), even between adjacent streaks.
        XCTAssertGreaterThanOrEqual(Synth.gemPitchStep, 1.07)
        XCTAssertNotEqual(Synth.gem(streak: 1), Synth.gem(streak: 2))
    }

    func testPickupSoundsAreDistinct() {
        XCTAssertNotEqual(Synth.shieldChime(), Synth.magnetChime())
        XCTAssertNotEqual(Synth.doublerPickup(), Synth.shieldChime())
        XCTAssertNotEqual(Synth.frenzyStart(), Synth.frenzyEnd())
    }

    func testDeathSweepNoiseSwells() {
        // The noise layer swells instead of decaying — the tail must still be clearly audible.
        let s = Synth.deathSweep()
        XCTAssertGreaterThan(peak(Array(s.suffix(s.count / 6))), 0.015, "deathSweep dies too early")
    }

    func testSFXCatalogRendersAndClassifies() {
        // Every cacheable case must render non-silent samples (this is what SynthEngine caches).
        let all: [Synth.SFX] = [
            .gem(streak: 5), .jump, .slide, .crash, .chime, .shieldPickup, .magnetPickup,
            .doublerPickup, .worldSweep, .close, .startChime, .laneTick, .landThud,
            .purchaseChime, .equipClick, .uiTick, .newBestFanfare, .deathSweep,
            .frenzyStart, .frenzyEnd,
        ]
        for sfx in all {
            let s = sfx.samples
            XCTAssertFalse(s.isEmpty, "\(sfx) empty")
            XCTAssertFalse(s.contains { $0.isNaN || $0.isInfinite }, "\(sfx) has NaN/Inf")
            XCTAssertGreaterThan(peak(s), 0.005, "\(sfx) is effectively silent")
        }
        // Gem cache keys collapse modulo the 26-step ladder.
        XCTAssertEqual(Synth.SFX.gem(streak: 29).normalized, Synth.SFX.gem(streak: 3).normalized)
        XCTAssertEqual(Synth.SFX.gem(streak: -1).normalized, Synth.SFX.gem(streak: 25).normalized)
        XCTAssertEqual(Synth.SFX.jump.normalized, .jump)
        // Big moments duck the music bed; ticks don't.
        XCTAssertTrue(Synth.SFX.crash.ducksMusic)
        XCTAssertTrue(Synth.SFX.deathSweep.ducksMusic)
        XCTAssertTrue(Synth.SFX.worldSweep.ducksMusic)
        XCTAssertTrue(Synth.SFX.shieldPickup.ducksMusic)
        XCTAssertFalse(Synth.SFX.laneTick.ducksMusic)
        XCTAssertFalse(Synth.SFX.gem(streak: 3).ducksMusic)
    }

    /// v1.3 (R17): the six mechanic SFX render sane, audible, correctly-sized buffers.
    func testV13MechanicSFXAreSane() {
        assertSane(Synth.ringPass(), 0.10, 0.14, "ringPass")
        assertSane(Synth.ringPerfect(), 0.24, 0.28, "ringPerfect")
        assertSane(Synth.boostStart(), 0.34, 0.38, "boostStart")
        assertSane(Synth.boostEnd(), 0.32, 0.36, "boostEnd")
        assertSane(Synth.flowSurgeChime(), 0.50, 0.54, "flowSurge")
        assertSane(Synth.levelUpFanfare(), 0.83, 0.87, "levelUp")
        // PERFECT must read as a bigger moment than the plain pass; boost edges must differ.
        XCTAssertNotEqual(Synth.ringPass(), Synth.ringPerfect())
        XCTAssertNotEqual(Synth.boostStart(), Synth.boostEnd())
        XCTAssertNotEqual(Synth.levelUpFanfare(), Synth.newBestFanfare())
    }

    /// v1.3: the six new SFX cases render finite non-empty buffers (what SynthEngine caches)
    /// and classify correctly for music ducking (big moments duck; per-ring blips don't).
    func testV13SFXCasesRenderAndClassify() {
        let fresh: [Synth.SFX] = [.ringPass, .ringPerfect, .boostStart, .boostEnd, .flowSurge, .levelUp]
        for sfx in fresh {
            let s = sfx.samples
            XCTAssertFalse(s.isEmpty, "\(sfx) empty")
            XCTAssertFalse(s.contains { $0.isNaN || $0.isInfinite }, "\(sfx) has NaN/Inf")
            XCTAssertGreaterThan(peak(s), 0.005, "\(sfx) is effectively silent")
            XCTAssertEqual(sfx.normalized, sfx, "\(sfx) must be its own cache key")
        }
        XCTAssertTrue(Synth.SFX.boostStart.ducksMusic)
        XCTAssertTrue(Synth.SFX.boostEnd.ducksMusic)
        XCTAssertTrue(Synth.SFX.flowSurge.ducksMusic)
        XCTAssertTrue(Synth.SFX.levelUp.ducksMusic)
        XCTAssertFalse(Synth.SFX.ringPass.ducksMusic)
        XCTAssertFalse(Synth.SFX.ringPerfect.ducksMusic)
    }

    func testMusicStepsAreSaneAcrossWorlds() {
        // v1.5: 12 distinct themed beds (worlds 0…11) PLUS the first deep cycle (12…23, layer 1).
        // Every step must stay finite, non-silent, and below the clip ceiling.
        for world in 0..<24 {
            for beat in 0..<8 {
                let s = Synth.step(beat: beat, world: world)
                XCTAssertEqual(s.count, Synth.stepFrames, "step length")
                XCTAssertFalse(s.contains { $0.isNaN || $0.isInfinite })
            }
            let bar = (0..<8).flatMap { Synth.step(beat: $0, world: world) }
            XCTAssertGreaterThan(peak(bar), 0.05, "world \(world) bar is silent")
            XCTAssertLessThanOrEqual(peak(bar), 2.0, "world \(world) bar clips")
        }
    }

    /// v1.5: each of the 12 worlds has its OWN themed bed (neighbours sound distinct), AND a full
    /// loop deeper (world + 12, one cycle up) still layers extra voices — so neither neighbouring
    /// worlds nor deep loops ever sound identical. Worlds 0/1/2 keep the shipped bed (see `beds`).
    func testPerWorldBedsAndDeepCyclesDiffer() {
        let n = Synth.beds.count
        for world in 0..<(n - 1) {                            // every adjacent world bar differs
            let a = (0..<8).flatMap { Synth.step(beat: $0, world: world) }
            let b = (0..<8).flatMap { Synth.step(beat: $0, world: world + 1) }
            XCTAssertNotEqual(a, b, "world \(world) and \(world + 1) must sound distinct")
        }
        for world in 0..<3 {                                  // one cycle deeper layers extra voices
            for beat in 0..<8 {
                XCTAssertNotEqual(Synth.step(beat: beat, world: world),
                                  Synth.step(beat: beat, world: world + n),
                                  "cycle 1 (world \(world + n)) should layer vs cycle 0 (world \(world))")
            }
        }
    }
}
