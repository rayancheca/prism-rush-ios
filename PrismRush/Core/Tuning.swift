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
    // Difficulty gating thresholds for the pattern catalogue (verbatim from the shipped code:
    // `dist<260 ? 5 : (diff<0.45 ? 9 : 11)` patterns selectable; see Spawner).
    static let earlyDistance: Double = 260
    static let midDiff: Double = 0.45

    // Collision / lifecycle (derived from the reference; named to avoid magic numbers).
    static let obstacleZHalf: Double = 0.95       // |z| < this → obstacle is at the player plane
    static let recycleObstacleZ: Double = 10      // obstacle behind camera → recycle
    static let recycleCollectibleZ: Double = 8    // gem / pickup behind camera → recycle
    static let pickupZHalf: Double = 1.1, pickupXHalf: Double = 1.1, pickupYHalf: Double = 1.3
    static let magnetGemXRate: Double = 7, magnetGemYRate: Double = 5
    static let nearMissBonus: Int = 25, gemBaseScore: Int = 10

    // Spawn / speed lerp factors.
    static let speedLerp: Double = 1.5, overDecel: Double = 22
    static let bankRate: Double = 0.32, bankLerp: Double = 10, slideLerp: Double = 14
    static let landSquashY: Double = 0.68, airStretchY: Double = 1.18, airHoldY: Double = 1.12

    // Pool caps — bound the live entity count (renderer pools mirror these).
    static let capLow = 18, capTall = 14, capBar = 6, capGem = 72, capShield = 4, capMagnet = 4
}
