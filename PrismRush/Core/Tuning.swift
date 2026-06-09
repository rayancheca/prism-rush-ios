import Foundation

/// All gameplay constants, ported verbatim from the shipped Three.js prototype.
/// These are ground truth — do not "improve" them without re-tuning against the reference.
/// `Core/` imports Foundation only; never a renderer.
enum Tuning {
    static let laneX: [Double] = [-2.2, 0, 2.2]
    static let worldLength: Double = 800
    static let speedStart: Double = 17, speedRamp: Double = 0.0052, speedCap: Double = 33
    static let menuSpeed: Double = 7
    static let jumpV0: Double = 10.6, gravity: Double = 26
    static let laneLerpRate: Double = 12
    static let slideDuration: Double = 0.55, slideScaleY: Double = 0.45, slamVy: Double = -14
    static let jumpBuffer: Double = 0.14
    static let bodyRadius: Double = 0.62, groundedCenterY: Double = 0.66
    static let lowKillTop: Double = 0.85
    static let barKillBottom: Double = 0.95, barKillTop: Double = 1.65
    static let laneHitHalfWidth: Double = 1.25
    static let gemPickup = (dz: 1.0, dx: 1.0, dy: 1.15)
    static let magnetDuration: Double = 6, magnetRange: Double = 13
    static let streakPerMult: Int = 8, multCap: Int = 5
    static let spawnHorizon: Double = 115
    static let gapMax: Double = 11, gapMin: Double = 5, diffFullAt: Double = 3200
    static let tickDt: Double = 1.0 / 120.0

    // Near-miss windows (tall passed in this |dx| band → CLOSE bonus).
    static let nearMissInner: Double = 1.25, nearMissOuter: Double = 2.4
    // Difficulty gating thresholds for the pattern catalogue.
    static let earlyDistance: Double = 260   // first 260m: patterns 1...6 only
    static let midDiff: Double = 0.45        // diff < 0.45: patterns 1...10
}
