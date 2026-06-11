import Foundation

/// All gameplay constants, ported verbatim from the shipped Three.js prototype.
/// These are ground truth — do not "improve" them without re-tuning against the reference.
/// `Core/` imports Foundation only; never a renderer.
enum Tuning {
    static let laneX: [Double] = [-2.2, 0, 2.2]
    static let worldLength: Double = 800
    static let worldBlendRate: Double = 0.6   // crossfade speed → ~1.7 s cinematic world transition
    static let speedStart: Double = 17, speedRamp: Double = 0.0052, speedCap: Double = 33
    static let menuSpeed: Double = 7
    static let jumpV0: Double = 10.6, gravity: Double = 26
    static let laneLerpRate: Double = 15   // lane settle ~0.30 s — snappier dodges, strictly easier
    static let slideDuration: Double = 0.55, slideScaleY: Double = 0.38, slamVy: Double = -14
    static let jumpBuffer: Double = 0.25   // widened for human reaction + iOS touch latency

    // Moving wall (pattern 10): deterministic phase + smaller amplitude + slower sweep so a human can
    // read it and a safe lane always exists; only spawns once the player has acclimated (diff >= 0.6).
    static let movingWallAmplitude: Double = 1.6
    static let movingWallFreq: Double = 0.22
    static let movingWallMinDiff: Double = 0.6
    static let bodyRadius: Double = 0.62, groundedCenterY: Double = 0.66
    static let lowKillTop: Double = 0.85
    static let barKillBottom: Double = 0.95, barKillTop: Double = 1.65
    static let laneHitHalfWidth: Double = 1.25
    static let gemPickup = (dz: 1.0, dx: 1.0, dy: 1.15)
    static let magnetDuration: Double = 6, magnetRange: Double = 16
    static let doublerDuration: Double = 10   // gems pay double CURRENCY (skill stats unaffected)
    // Chrono slow-mo: distance integrates at speed × factor while the player ticks at real dt,
    // stretching every dodge window ~1.5× — strictly easier. The raw `speed` ramp is untouched.
    static let chronoDuration: Double = 5, chronoFactor: Double = 0.65
    // Post-absorb grace: patterns place twin talls at the same `d`, so a mid-lane-change shield hit
    // must not let the second wall kill on the same tick (or the next — it's still in the kill band).
    static let invulnDuration: Double = 0.4
    static let streakPerMult: Int = 5, multCap: Int = 5   // v1.3: ×5 at 20 gems — minute one escalates visibly
    static let spawnHorizon: Double = 115
    static let gapMax: Double = 11, gapMin: Double = 5, diffFullAt: Double = 3200
    static let tickDt: Double = 1.0 / 120.0

    // Near-miss windows (tall passed in this |dx| band → CLOSE bonus). The outer edge must stay
    // below the lane pitch (2.2) or simply standing one lane away auto-awards CLOSE.
    static let nearMissInner: Double = 1.25, nearMissOuter: Double = 1.95
    // Difficulty gating thresholds for the pattern catalogue (5-tier prefix ladder, see Spawner).
    static let earlyDistance: Double = 260
    static let midEarlyDiff: Double = 0.18   // v1.3: 576 m — rings & overdrive unlock before the pain
    static let midDiff: Double = 0.45

    // Collision / lifecycle (derived from the reference; named to avoid magic numbers).
    static let obstacleZHalf: Double = 0.95       // |z| < this → obstacle is at the player plane
    static let recycleObstacleZ: Double = 10      // obstacle behind camera → recycle
    static let recycleCollectibleZ: Double = 8    // gem / pickup behind camera → recycle
    static let pickupZHalf: Double = 1.1, pickupXHalf: Double = 1.1, pickupYHalf: Double = 1.3
    static let magnetGemXRate: Double = 7, magnetGemYRate: Double = 7   // y fast enough to reel in arc gems
    static let nearMissBonus: Int = 40, gemBaseScore: Int = 10

    // Spawn / speed lerp factors.
    static let speedLerp: Double = 1.5, overDecel: Double = 22
    static let bankRate: Double = 0.32, bankLerp: Double = 10, slideLerp: Double = 20
    static let landSquashY: Double = 0.68, airStretchY: Double = 1.18, airHoldY: Double = 1.12

    // Pool caps — bound the live entity count (renderer pools mirror these).
    static let capLow = 18, capTall = 14, capBar = 6, capGem = 72, capShield = 4, capMagnet = 4
    static let capDoubler = 2, capChrono = 2, capSplitBar = 6

    // MARK: v1.3 mechanics

    // Ballistic gem arc: gems sit ON the predicted jump path. Pure f(d) — zero RNG (rule 2).
    static let gemArcBaseY: Double = 0.8      // gem 0 height — the grounded jump telegraph
    static let gemArcAirFrac: Double = 0.75   // arc covers the first 75% of the airtime (up, over, ¾ down)
    static let gemArcMaxSpan: Double = 14     // span cap keeps pattern lengths bounded at high speed

    // Prism rings (aim verb): thread the torus mid-jump; PERFECT = bullseye at the apex.
    static let ringY: Double = 2.90           // apex center height: h_max (2.16) + in-air center (0.74)
    static let ringPassDX: Double = 0.9
    static let ringPassDY: Double = 0.9
    static let ringPerfectDY: Double = 0.12
    static let ringZHalf: Double = 0.9
    static let ringScore: Int = 150
    static let ringCoins: Int = 5             // pays into gemCount (currency) — never streak (rule 9)
    static let ringPerfectCoins: Int = 12
    static let capRing = 4

    // Overdrive pads: +30% speed (capped) for one second, contained in an obstacle-free runway —
    // worst-case boost travel (trigger ≤ pad+1.1, then 1.0 s × 36) ends well inside the pattern.
    static let boostDuration: Double = 1.0
    static let boostFactor: Double = 1.3
    static let boostSpeedMax: Double = 36
    static let boostScoreBonus: Int = 60
    static let boostGemBonus: Int = 1         // each gem pays this many extra coins while boosting
    static let capBoostPad = 2

    // Flow surge: every flowPerSurge-th CLOSE/SLICK without a hit detonates a score bonus and a
    // gem fountain sprayed into the player's lane. Deterministic from state — consumes ZERO RNG.
    static let flowPerSurge: Int = 3
    static let flowSurgeScore: Int = 80
    static let fountainGems: Int = 10
    static let fountainLead: Double = 26
    static let fountainSpacing: Double = 1.7
}
