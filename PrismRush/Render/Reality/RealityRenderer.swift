import SwiftUI
import RealityKit
import simd
import UIKit

/// RealityKit adapter implementing `RendererPort`. Owns the whole virtual scene under `root`
/// (camera, backdrop, ground, scrolling grid, character rig, per-world decor) and maps each snapshot
/// to entities via `EntityPools`. Untextured `UnlitMaterial` throughout — neon, no lighting setup.
/// World palettes crossfade from the snapshot's `worldFrom/worldTo/worldBlend`.
@MainActor
final class RealityRenderer: RendererPort {
    let root = Entity()

    private let camera = PerspectiveCamera()
    private let playerRig = Entity()
    private var playerBody: ModelEntity!
    private var eyes: [ModelEntity] = []
    private var antenna: ModelEntity!
    private var antennaTip: ModelEntity!
    private var backdrop: ModelEntity!
    private var rungs: [ModelEntity] = []
    private var laneLines: [ModelEntity] = []
    private var pools: EntityPools!
    private var decor: WorldDecor!

    private let cGold = UIColor(red: 1, green: 210/255.0, blue: 61/255.0, alpha: 1) // #FFD23D
    private let cWhite = UIColor.white

    private let rungSpacing: Float = 4
    private let rungCount = 36

    private let gemMesh: MeshResource
    private let magnetMesh: MeshResource
    private let doublerMesh: MeshResource   // twin octahedron (coin-doubler pickup, see makeEntity)
    private let chronoMesh: MeshResource    // hourglass (chrono slow-mo pickup)
    private let splitBarSegmentMesh: MeshResource   // one-lane bar segment (two per splitBar)
    private let ringMesh: MeshResource      // prism-ring gate torus (hole faces the camera, +Z)
    private let padMesh: MeshResource       // overdrive-pad floor chevron strip (flat, XZ plane)

    // Selected character skin (`followsWorld` = the default look that tracks the world accent).
    private var skinBodyHex: UInt32 = 0
    private var skinAntennaHex: UInt32 = 0
    private var skinFollowsWorld = true

    // v1.3 skin rig (set by `applySkin(_ skin:)`; the legacy 3-arg shim leaves these at the
    // defaults, so pre-wave-5 callers keep today's exact look). All visual-only — the hitbox
    // (Core's bodyRadius/groundedCenterY) never sees any of this.
    private var skinTrailColor: UIColor?            // nil = wake follows the world accent (Prism)
    private var skinBodyShape: Skin.BodyShape = .sphere
    private var skinScale: Float = 1                // folded into the per-frame pose, 0.85…1.12
    private var skinEyeRadius: Float = 0.13
    private var skinEyeTintHex: UInt32 = 0xFFFFFF
    private var skinPupil: Skin.PupilStyle = .dot
    private var skinAntennaHeight: Float = 1
    private var skinAntennaTip: Float = 1
    private var skinSway: Float = 0                 // radians; 0 = static antenna (legacy shim path)
    private var skinSwaySpeed: Double = 3.2         // = idle.bobSpeed * 2 once a Skin is applied
    private var antennaCenterY: Float = 1.42        // stem centre — the sway pivot (set per rig build)
    private var antennaTipY: Float = 1.675          // tip rest height (set per rig build)
    private var swayApplied = false                 // restore the rest pose once when sway stops

    private var elapsed: Double = 0
    private var blinkT: Double = 3
    private var shake: Float = 0
    private var fovKick: Float = 0          // transient FOV punch (pickup / world change), decays like shake
    private var chronoDip: Float = 0        // smoothed −6° FOV dip while chrono slow-mo is active
    private var boostFOV: Float = 0         // smoothed +6° FOV punch while the overdrive boost runs
    private var slideRoll: Float = 0        // smoothed camera z-roll while sliding
    private var lastSpeed: Float = 0
    private var lastDt: Float = 1 / 60      // wall-clock dt from advanceVisuals (runs before sync)
    private var camX: Float = 0
    private var camXV: Float = 0            // lateral-follow spring velocity (lag + overshoot on swipes)
    private var slideDip: Float = 0         // smoothed 0→1 camera ground-drop while sliding (the P0 read)

    // Pose-extras state. The snapshot carries no velocities, so lateral/vertical speed is estimated
    // from position deltas right here (Core stays untouched). Timers are armed by FX edges.
    private var lastPlayerX: Float = 0
    private var lastPlayerY: Float = 0
    private var vxEst: Float = 0            // smoothed lateral velocity — drives the antenna whip
    private var vyEst: Float = 0            // smoothed vertical velocity — drives the airborne stretch
    private var jumpStretchT: Float = 0     // takeoff anticipation pop, armed by `.jumped`
    private var landSquashT: Float = 0      // landing squash impulse, armed by `.landed`
    private var whip: Float = 0             // antenna whip spring angle: lags/overshoots the body's x-motion
    private var whipVel: Float = 0
    private var runPhase: Float = 0         // run-cycle gallop clock (wraps at 2π; period shrinks with speed)
    private var runBobOn = false            // cached for advanceVisuals (runs BEFORE sync): grounded play run
    private var speedNorm: Float = 0        // cached 0…1 speed factor (FOV punch, lean, antenna bounce)
    private var lastSliding = false         // cached for the eye squint in advanceVisuals

    // Reduce Motion gates shake, the FOV speed-punch/kicks, the slide roll, and speed lines, plus
    // all of the pose extras above. The slide camera keeps a SUBTLE height dip even under RM —
    // slide state is gameplay information, so total removal would hurt readability.
    // Observed live, not just sampled at launch.
    private var reduceMotion = UIAccessibility.isReduceMotionEnabled
    private var reduceMotionObserver: (any NSObjectProtocol)?

    private var particles: ParticleSystem!

    // Time-based emission accumulators — emission rates are per second, not per frame, so the
    // trail/dust/speed-line density is identical at 60 Hz and 120 Hz.
    private var trailDebt: Float = 0
    private var dustDebt: Float = 0
    private var speedLineDebt: Float = 0

    // Slide skid marks: a tiny pool of flattened dark boxes dropped under the player on `.slid`.
    private var skids: [ModelEntity] = []
    private var skidLife: [Float] = []
    private var skidCursor = 0
    private let skidMaxLife: Float = 0.9

    // Ring-pass shockwave: one dedicated torus that scale-pulses outward on `.ringPassed`
    // (gold on a PERFECT bullseye). The pooled ring entity itself vanishes the same frame the
    // core consumes it, so the pulse needs its own entity.
    private var ringPulse: ModelEntity!
    private var ringPulseLife: Float = 0
    private let ringPulseMaxLife: Float = 0.35

    // Latest blended obstacle tints, captured for the pools' place closure and particle bursts.
    private var tintAccent = UIColor.cyan
    private var tintAccent2 = UIColor.magenta

    // Cached materials — rebuilt only when the palette key (worldFrom, worldTo, quantized blend)
    // or the skin changes, never per frame. Extends the D1 obstacle-material fix to the backdrop,
    // grid rungs, lane lines, and character: ~44 UnlitMaterial allocations/frame → 0 in steady state.
    private var paletteKey: Int = -1
    private var matAccent = UnlitMaterial(color: .cyan)
    private var matAccent2 = UnlitMaterial(color: .magenta)
    private let matGemGold: UnlitMaterial
    private let matGemHot: UnlitMaterial    // magnet-pulled gems tint hotter as they shrink

    init() {
        gemMesh = ProceduralMesh.octahedron(0.34)
        magnetMesh = ProceduralMesh.torus(major: 0.30, minor: 0.12)
        doublerMesh = ProceduralMesh.twinOctahedron(0.26, offset: 0.34)
        chronoMesh = ProceduralMesh.hourglass(halfBase: 0.3, halfHeight: 0.42)
        splitBarSegmentMesh = .generateBox(width: 2.5, height: 0.7, depth: 0.7, cornerRadius: 0.04)
        // Ring gate: hole radius 0.79 vs body radius 0.62 — threading reads true to the ±0.9
        // pass window without looking trivially wide. Same generator as the magnet torus.
        ringMesh = ProceduralMesh.torus(major: 0.88, minor: 0.09, majorSeg: 28, minorSeg: 10)
        padMesh = ProceduralMesh.chevronStrip()
        matGemGold = UnlitMaterial(color: UIColor(red: 1, green: 210/255.0, blue: 61/255.0, alpha: 1))
        matGemHot = UnlitMaterial(color: UIColor(red: 1, green: 0.95, blue: 0.75, alpha: 1))
        buildScene()
        pools = EntityPools(root: root) { [weak self] kind in
            self?.makeEntity(kind) ?? ModelEntity()
        }
        // v1.3 pickups: pre-build up to the core's live caps so the first mid-run ring/pad spawn
        // never allocates (the other kinds warm up within seconds; these appear minutes in).
        pools.prewarm(.ring, count: Tuning.capRing)
        pools.prewarm(.boostPad, count: Tuning.capBoostPad)
        decor = WorldDecor(root: root)
        particles = ParticleSystem(parent: root)

        reduceMotionObserver = NotificationCenter.default.addObserver(
            forName: UIAccessibility.reduceMotionStatusDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.reduceMotion = UIAccessibility.isReduceMotionEnabled
            }
        }
    }

    func install(into content: RealityViewCameraContent) {
        content.add(root)
    }

    // MARK: RendererPort

    func sync(_ snap: GameSnapshot) {
        // Recolor only when the palette key changes (world pair or quantized blend step) — in
        // steady state (worldBlend == 1, ~95% of frames) this whole block is skipped, alloc-free.
        let key = (snap.worldFrom % 3) &* 4096 &+ (snap.worldTo % 3) &* 256 &+ Int(snap.worldBlend * 64)
        if key != paletteKey {
            paletteKey = key
            let pal = Palette(snap)
            tintAccent = pal.accent
            tintAccent2 = pal.accent2
            matAccent = UnlitMaterial(color: pal.accent)
            matAccent2 = UnlitMaterial(color: pal.accent2)
            let bodyColor = skinFollowsWorld ? pal.accent : uiHex(skinBodyHex)
            let antennaColor = skinFollowsWorld ? pal.accent2 : uiHex(skinAntennaHex)
            backdrop.model?.materials = [UnlitMaterial(color: pal.bg)]
            let gridMat = UnlitMaterial(color: pal.grid)   // ONE instance shared by every rung
            for r in rungs { r.model?.materials = [gridMat] }
            let laneMat = UnlitMaterial(color: pal.lane)   // pushed toward white mid-crossfade
            for l in laneLines { l.model?.materials = [laneMat] }
            let bodyMat = UnlitMaterial(color: bodyColor)
            playerBody.model?.materials = [bodyMat]
            antenna.model?.materials = [bodyMat]
            antennaTip.model?.materials = [UnlitMaterial(color: antennaColor)]
        }

        // Camera follow + speed FOV + decaying screen shake (kept off the follow position so it
        // doesn't bleed into the lerp; Reduce Motion disables all of the motion flourishes).
        let px = Float(snap.playerX)
        lastSpeed = Float(snap.speed)
        lastSliding = snap.sliding && snap.mode == .play
        runBobOn = snap.mode == .play && snap.grounded && !snap.sliding
        speedNorm = Float(clampD((snap.speed - 7) / 27, 0, 1))
        let speedPunch: Float = reduceMotion ? 0 : speedNorm * 9
        // Chrono slow-mo: ease toward a −6° dip while the timer runs (snap.speed is already the
        // chrono-scaled EFFECTIVE speed, so the speed punch above relaxes with it for free).
        let dipTarget: Float = (!reduceMotion && snap.chronoRemaining > 0 && snap.mode == .play) ? -6 : 0
        chronoDip += (dipTarget - chronoDip) * 0.08
        // Overdrive boost: ease toward a +6° punch while `boostRemaining` runs and back out when
        // it ends — driven by the snapshot (not the edge events) so restore can never be missed.
        let boostTarget: Float = (!reduceMotion && snap.boostRemaining > 0 && snap.mode == .play) ? 6 : 0
        boostFOV += (boostTarget - boostFOV) * 0.12
        camera.camera.fieldOfViewInDegrees = 62 + speedPunch + fovKick + chronoDip + boostFOV

        // Lateral/vertical velocity estimated from position deltas, clamped so the run-start
        // teleport can't spike the pose, then smoothed (~3 frames) so the estimates stay calm.
        let sdt = max(min(lastDt, 1 / 30), 1 / 240)
        vxEst += (min(max((px - lastPlayerX) / sdt, -20), 20) - vxEst) * 0.35
        vyEst += (min(max((Float(snap.playerY) - lastPlayerY) / sdt, -16), 16) - vyEst) * 0.35
        lastPlayerX = px
        lastPlayerY = Float(snap.playerY)

        // Slide camera drop (the P0 readability fix): the eye DIVES toward the ground and the
        // look-at pitches down while sliding — in fast (~0.12 s), out slower (~0.2 s) — so a bar
        // whooshes OVERHEAD exactly as the player ducks under it. Reduce Motion keeps a small
        // height dip only (slide state is gameplay information) and drops the pitch/pull extras.
        let slideTarget: Float = (snap.sliding && snap.mode == .play) ? 1 : 0
        slideDip += (slideTarget - slideDip) * (slideTarget > slideDip ? 0.28 : 0.14)
        let dropY: Float = slideDip * (reduceMotion ? 0.6 : 2.1)
        // Lateral follow: a lightly underdamped spring instead of a flat lerp — the camera lags a
        // swipe then overshoots a touch, which makes lane changes feel kinetic. RM keeps the lerp.
        let followX = px * 0.42
        if reduceMotion {
            camX += (followX - camX) * 0.15
            camXV = 0
        } else {
            camXV += (followX - camX) * 90 * sdt
            camXV *= max(0, 1 - 9.5 * sdt)
            camX += camXV * sdt
        }
        let shaking = !reduceMotion && shake > 0
        let shakeX = shaking ? Float.random(in: -1...1) * shake * 0.55 : 0
        let shakeY = shaking ? Float.random(in: -1...1) * shake * 0.55 : 0
        let cp = SIMD3<Float>(camX + shakeX, 5.1 - dropY + shakeY, 9.6 - (reduceMotion ? 0 : slideDip * 0.8))
        camera.position = cp
        let lookY: Float = 1.3 - (reduceMotion ? 0 : slideDip * 0.85)
        camera.look(at: SIMD3<Float>(px * 0.3, lookY, -5), from: cp, relativeTo: nil)
        // Slight z-roll folded into the look-at while sliding (smoothed both ways).
        let rollTarget: Float = (!reduceMotion && snap.sliding && snap.mode == .play) ? -0.06 : 0
        slideRoll += (rollTarget - slideRoll) * 0.2
        if abs(slideRoll) > 0.0005 {
            camera.orientation = simd_quatf(angle: slideRoll, axis: SIMD3<Float>(0, 0, 1)) * camera.orientation
        }
        if shaking {   // a touch of rotational roll makes impacts read far harder than position alone
            let roll = Float.random(in: -1...1) * shake * 0.012
            camera.orientation = simd_quatf(angle: roll, axis: SIMD3<Float>(0, 0, 1)) * camera.orientation
        }

        // Player rig: lane/jump pose, squash-&-stretch, bank, plus a pronounced forward-lean slide.
        // The renderer-side extras (run gallop, airborne stretch, takeoff pop, landing impulse)
        // layer MULTIPLICATIVELY on Core's playerScaleY baseline and are all RM-gated.
        playerRig.isEnabled = snap.mode != .over
        var sy = Float(snap.playerScaleY)
        var sx = 1 + (1 - sy) * 0.45
        var poseY = Float(snap.playerY)
        var pitch: Float = 0
        if snap.sliding {
            sx *= 1.7                                        // flatten dramatically into a pancake
            pitch = -0.85                                    // nose-down — diving under the bar
        } else if !reduceMotion, snap.mode == .play {
            if snap.grounded {
                // Run cycle: gallop bob whose period shrinks with speed, plus a forward lean
                // proportional to speed. |sin| gives the bounce; sin(2φ) is the matching pulse.
                poseY += abs(sin(runPhase)) * (0.045 + 0.035 * speedNorm)
                pitch = -0.16 * speedNorm
                sy *= 1 + sin(runPhase * 2) * 0.025
            } else {
                // Airborne: stretch with vertical speed (derived from y deltas above), which
                // relaxes to neutral at the apex for free; nose-up rising, nose-down falling.
                let f = min(abs(vyEst) / Float(Tuning.jumpV0), 1)
                sy *= 1 + f * 0.26
                sx *= 1 - f * 0.12
                pitch = min(max(vyEst * 0.022, -0.30), 0.12)
            }
            if jumpStretchT > 0 {                            // takeoff anticipation pop (.jumped edge)
                let e = jumpStretchT / 0.12
                sy *= 1 + 0.16 * e
                sx *= 1 - 0.08 * e
            }
            if landSquashT > 0 {                             // impact squash atop Core's (.landed edge)
                let e = landSquashT / 0.18
                sy *= 1 - 0.22 * e
                sx *= 1 + 0.26 * e
            }
        }
        playerRig.position = SIMD3<Float>(px, poseY, 0)
        playerRig.scale = SIMD3<Float>(sx, sy, sx) * skinScale   // skin size is pose-only; hitbox untouched
        let bankQ = simd_quatf(angle: Float(snap.bankZ), axis: SIMD3<Float>(0, 0, 1))
        let leanQ = simd_quatf(angle: pitch, axis: SIMD3<Float>(1, 0, 0))
        playerRig.orientation = bankQ * leanQ

        // Dust kicked up during a slide — grounded OR mid air-slam — so it's unmistakable.
        // Time-based (≈ the old 6/frame at 60 Hz) so density matches at 120 Hz. The wider x
        // scatter + slightly hotter power turn it into a continuous ground ribbon behind the body.
        if snap.mode == .play, snap.sliding {
            dustDebt += 360 * lastDt
            let n = Int(dustDebt)
            if n > 0 {
                dustDebt -= Float(n)
                particles.burst(x: px + Float.random(in: -0.55...0.55), y: 0.12, z: 0.5,
                                color: skinTrailColor ?? tintAccent, count: n, power: 2.1, spread: 0.2, life: 0.5)
            }
        }

        // Grid scroll.
        let off = Float(snap.distance.truncatingRemainder(dividingBy: Double(rungSpacing)))
        for (i, r) in rungs.enumerated() { r.position.z = off + 10 - Float(i) * rungSpacing }

        // Spawned entities — the two obstacle materials are rebuilt with the palette above, then
        // assigned by reference. Also fixes stale pooled colors.
        let mA = matAccent, mA2 = matAccent2
        let mGold = matGemGold, mHot = matGemHot
        pools.sync(snap.entities) { entity, s in
            // `s.y` is authoritative for EVERY kind (bar/splitBar centre 1.3, low 0.425, tall 1.6
            // now arrive from the core) — never hardcode heights here.
            entity.position = SIMD3<Float>(Float(s.x), Float(s.y), Float(s.z))
            switch s.kind {
            case .tall:
                (entity as? ModelEntity).map { $0.model?.materials = [mA] }
            case .low, .bar, .movingTall:
                (entity as? ModelEntity).map { $0.model?.materials = [mA2] }
            case .splitBar:
                // `s.lane` is the OPEN lane: park the two pooled segments over the other two
                // lanes (recycled entities may carry a different gap, so place every frame).
                let open = (0...2).contains(s.lane) ? s.lane : 1
                let xa = Float(Tuning.laneX[open == 0 ? 1 : 0])
                let xb = Float(Tuning.laneX[open == 2 ? 1 : 2])
                var i = 0
                for child in entity.children {
                    guard let seg = child as? ModelEntity else { continue }
                    seg.position = SIMD3<Float>(i == 0 ? xa : xb, 0, 0)
                    seg.model?.materials = [mA2]
                    i += 1
                }
            case .gem:
                entity.orientation = simd_quatf(angle: Float(s.spin) * 0.9, axis: SIMD3<Float>(0, 1, 0))
                if s.fading {
                    // Magnet-pulled: shrink toward 0.55 and tint hotter as it streaks in.
                    let cur = entity.scale.x
                    entity.scale = SIMD3<Float>(repeating: cur + (0.55 - cur) * 0.35)
                    (entity as? ModelEntity).map { $0.model?.materials = [mHot] }
                } else if entity.scale.x != 1 {
                    entity.scale = .one                      // recycled pooled gem: restore
                    (entity as? ModelEntity).map { $0.model?.materials = [mGold] }
                }
            case .shield, .magnet, .doubler, .chrono:
                entity.orientation = simd_quatf(angle: Float(s.spin) * 0.9, axis: SIMD3<Float>(0, 1, 0))
            case .ring:
                // Gate torus stays face-on (the hole IS the target); a slow scale-pulse keyed off
                // `spin` (= z, deterministic) signals "collectible" without spinning the hole away.
                entity.scale = SIMD3<Float>(repeating: 1 + 0.05 * Float(sin(s.spin * 0.8)))
                (entity as? ModelEntity).map { $0.model?.materials = [mA] }
            case .boostPad:
                // Floor chevrons breathe in the ground plane only (it's a decal — never lift y).
                let pulse = 1 + 0.07 * Float(sin(s.spin * 1.5))
                entity.scale = SIMD3<Float>(pulse, 1, pulse)
                (entity as? ModelEntity).map { $0.model?.materials = [mA] }
            }
        }

        // Speed trail behind the player — time-based (≈ the old 3/frame at 60 Hz). The emission
        // rate breathes with chrono slow-mo so the trail thins while the world crawls. The wake
        // is the skin's own color (Prism keeps nil → world accent); during an overdrive boost it
        // thickens and elongates into streaks.
        if snap.mode == .play {
            let boosting = snap.boostRemaining > 0
            trailDebt += 180 * (snap.chronoRemaining > 0 ? Float(Tuning.chronoFactor) : 1)
                             * (boosting ? 1.6 : 1) * lastDt
            let n = Int(trailDebt)
            if n > 0 {
                trailDebt -= Float(n)
                particles.burst(x: px + Float.random(in: -0.2...0.2), y: 0.25 + Float(snap.playerY), z: 0.5,
                                color: skinTrailColor ?? tintAccent, count: n, power: 0.9, spread: 0.08,
                                life: 0.45, velZ: boosting ? 7 : 0, stretchZ: boosting ? 2.4 : 1)
            }
        }

        // Speed lines above ~26 m/s — and for the whole of an overdrive boost, whose +30% kick is
        // the one moment that must FEEL faster even when the raw speed is still below the gate.
        if snap.mode == .play, !reduceMotion, lastSpeed > 26 || snap.boostRemaining > 0 {
            speedLineDebt += min(70, max((lastSpeed - 26) * 6, snap.boostRemaining > 0 ? 32 : 0)) * lastDt
            let n = Int(speedLineDebt)
            if n > 0 {
                speedLineDebt -= Float(n)
                for _ in 0..<n {
                    particles.burst(x: (Bool.random() ? 4.5 : -4.5) + Float.random(in: -0.5...0.5),
                                    y: Float.random(in: 2...5), z: -8, color: cWhite,
                                    count: 1, power: 0.2, spread: 0.1, life: 0.3,
                                    velZ: lastSpeed * 1.5, stretchZ: 2.8)
                }
            }
        }

        // Per-world decor.
        decor.update(distance: snap.distance, world: snap.worldTo, elapsed: elapsed)
    }

    func fire(_ event: FXEvent) {
        switch event {
        case let .gemCollected(x, y, streak):
            // Streak escalation: gold → cyan → magenta → white as the multiplier tier climbs.
            let tier = min(3, streak / 8)
            let ladder = [cGold, UIColor.cyan, UIColor.magenta, cWhite]
            particles.burst(x: Float(x), y: Float(y), z: 0, color: ladder[tier],
                            count: 12 + 4 * tier, power: 3.2, spread: 0.18, life: 0.6)
        case let .jumped(x):
            // Takeoff: arm the anticipation pop and chuff a small launch puff at the feet
            // (the airborne stretch in sync carries the rest of the arc).
            if !reduceMotion {
                jumpStretchT = 0.12
                particles.burst(x: Float(x), y: 0.1, z: 0.3, color: skinTrailColor ?? tintAccent,
                                count: 7, power: 2.0, spread: 0.26, life: 0.35)
            }
        case let .landed(x):
            particles.burst(x: Float(x), y: 0.1, z: 0.2, color: skinTrailColor ?? tintAccent, count: 10, power: 2.6, spread: 0.32, life: 0.4)
            if !reduceMotion { landSquashT = 0.18 }   // body squash sells the existing dust ring
        case let .laneChanged(x):
            // Skid kick where the dodge started — the antenna whip + camera lateral spring
            // (both velocity-driven in sync/advanceVisuals) carry the rest of the motion.
            if !reduceMotion {
                particles.burst(x: Float(x), y: 0.12, z: 0.4, color: skinTrailColor ?? tintAccent,
                                count: 10, power: 2.4, spread: 0.3, life: 0.38)
            }
        case let .slid(x):
            dropSkid(at: Float(x))
        case let .pickup(kind, x, y):
            switch kind {
            case .shield:
                particles.burst(x: Float(x), y: Float(y), z: 0, color: cWhite, count: 36, power: 4.8, spread: 0.34, life: 0.8)
            case .magnet:
                particles.burst(x: Float(x), y: Float(y), z: 0, color: tintAccent, count: 36, power: 4.8, spread: 0.34, life: 0.8)
            case .doubler:
                // Gold + emerald split burst — reads as "money" against every world palette.
                particles.burst(x: Float(x), y: Float(y), z: 0, color: cGold, count: 18, power: 4.8, spread: 0.3, life: 0.8)
                particles.burst(x: Float(x), y: Float(y), z: 0, color: uiHex(0x00FF88), count: 18, power: 4.8, spread: 0.3, life: 0.8)
            case .chrono:
                // Icy cyan-white shower, slower and longer-lived — time is thickening.
                particles.burst(x: Float(x), y: Float(y), z: 0, color: uiHex(0x9BF0FF), count: 30, power: 3.2, spread: 0.4, life: 1.1)
                particles.burst(x: Float(x), y: Float(y), z: 0, color: cWhite, count: 12, power: 2.2, spread: 0.3, life: 1.1)
            }
            kickFOV()
        case let .shieldAbsorbed(x):
            particles.burst(x: Float(x), y: 1.2, z: 0, color: cWhite, count: 40, power: 6.2, spread: 0.42, life: 0.7)
            shake = max(shake, 0.8)
        case let .died(x):
            // First (colored) burst shatters in the skin's own color; the white flash stays global.
            particles.burst(x: Float(x), y: 1, z: 0, color: skinTrailColor ?? tintAccent2, count: 120, power: 7.5, spread: 0.55, life: 1.2)
            particles.burst(x: Float(x), y: 1, z: 0, color: cWhite, count: 60, power: 9.5, spread: 0.35, life: 0.9)
            shake = 1.4
        case let .worldChanged(index, _):
            // One-shot horizon ring sweep in the incoming world's accent (banner is UI-side).
            let a = Theme.worlds[index % 3].accent
            let accent = UIColor(red: CGFloat(a.x), green: CGFloat(a.y), blue: CGFloat(a.z), alpha: 1)
            particles.ring(y: 4.5, z: -42, radius: 9, color: accent, count: 24, velZ: 26, life: 1.1)
            kickFOV()
        case let .ringPassed(x, y, perfect):
            // Expanding torus shockwave where the gate was threaded (the pooled ring entity is
            // already gone this frame). Gold flash on a PERFECT bullseye, world accent otherwise.
            ringPulse.position = SIMD3<Float>(Float(x), Float(y), 0)
            ringPulse.scale = .one
            ringPulse.model?.materials = [perfect ? matGemGold : matAccent]
            ringPulse.isEnabled = true
            ringPulseLife = ringPulseMaxLife
            particles.burst(x: Float(x), y: Float(y), z: 0, color: perfect ? cGold : tintAccent,
                            count: perfect ? 26 : 14, power: 3.6, spread: 0.5, life: 0.55)
            if perfect { kickFOV() }
        case let .boostStarted(x):
            // Launch flash at the pad. The sustained treatment (+6° FOV, trail streaks, speed
            // lines) keys off `snapshot.boostRemaining` in sync, so restore can never be missed.
            particles.burst(x: Float(x), y: 0.15, z: 0.4, color: tintAccent, count: 26, power: 4.6, spread: 0.5, life: 0.6)
            particles.burst(x: Float(x), y: 0.15, z: 0.4, color: cWhite, count: 10, power: 3.4, spread: 0.3, life: 0.45)
            kickFOV()
        case let .flowSurge(level, x):
            // Aura flash in the player's own wake color, a lane shimmer running ahead, and a
            // sparkle cascade at the fountain spawn point (masks the 26-unit gem pop-in).
            let aura = skinTrailColor ?? tintAccent
            particles.burst(x: Float(x), y: 1.0, z: 0, color: aura,
                            count: 22 + 4 * min(level, 3), power: 3.0, spread: 0.5, life: 0.7)
            for k in 1...6 {
                particles.burst(x: Float(x), y: 0.6, z: -Float(k) * Float(Tuning.fountainLead) / 6,
                                color: aura, count: 3, power: 1.2, spread: 0.25, life: 0.6)
            }
            particles.burst(x: Float(x), y: 0.9, z: -Float(Tuning.fountainLead), color: cGold,
                            count: 16, power: 2.6, spread: 0.5, life: 0.8)
            kickFOV()
        case .nearMiss, .chronoEnded, .boostEnded:
            break   // popups / banner / haptics / audio handled by the UI layer; boost restore
                    // is snapshot-driven (see sync), so `.boostEnded` is audio's edge, not ours
        }
    }

    /// Time-based animation (blink, particles, skids, shake/FOV decay) — driven by the loop's
    /// wall-clock dt (runs immediately before `sync` each frame).
    func advanceVisuals(_ dt: Double) {
        elapsed += dt
        lastDt = Float(dt)
        blinkT -= dt
        if blinkT < -0.12 { blinkT = Double.random(in: 2.2...4.2) }
        // Squint while sliding (motion-free, so never RM-gated): paired with the camera drop it
        // makes a slide readable in a single still frame. A blink wins when both close the lids.
        let lid: Float = blinkT < 0 ? 0.1 : (lastSliding ? 0.3 : 1)
        for eye in eyes { eye.scale = SIMD3<Float>(1, lid, 1) }
        // Run-cycle gallop clock: period shrinks as the speed climbs. Wraps at 2π so sin(φ) and
        // sin(2φ) both stay continuous and Float precision never degrades on marathon runs.
        if runBobOn, !reduceMotion {
            runPhase = (runPhase + Float(dt) * min(max(lastSpeed * 1.1, 6), 24))
                .truncatingRemainder(dividingBy: 2 * .pi)
        }
        // Pose-impulse timers (armed by the `.jumped` / `.landed` edges, consumed in sync).
        if jumpStretchT > 0 { jumpStretchT = max(0, jumpStretchT - Float(dt)) }
        if landSquashT > 0 { landSquashT = max(0, landSquashT - Float(dt)) }
        // Antenna — three motions folded into ONE angle: per-skin idle sway, a whip spring that
        // lags then overshoots the body's lateral velocity (swipes crack it like a car aerial),
        // and a bounce synced to the run bob. The tip swings on an arm around the stem centre so
        // scaled antennae (Pebble 0.6 … Wisp 1.4) stay attached. Zero allocations, two transform
        // writes per frame; all RM-gated with the one-time rest-pose restore below.
        if !reduceMotion {
            let sdtA = Float(min(dt, 1 / 30.0))
            let whipTarget = min(max(-vxEst * 0.05, -0.5), 0.5)
            whipVel += (whipTarget - whip) * 140 * sdtA      // stiffness 140, damping 10:
            whipVel *= max(0, 1 - 10 * sdtA)                 // underdamped → visible overshoot
            whip += whipVel * sdtA
            let swayA = skinSway > 0 ? Float(sin(elapsed * skinSwaySpeed)) * skinSway : 0
            let bounceA = runBobOn ? sin(runPhase) * 0.07 * speedNorm : 0
            let a = swayA + whip + bounceA
            let arm = antennaTipY - antennaCenterY
            antenna.orientation = simd_quatf(angle: a, axis: SIMD3<Float>(0, 0, 1))
            antennaTip.position = SIMD3<Float>(sin(a) * arm, antennaCenterY + cos(a) * arm, 0)
            swayApplied = true
        } else if swayApplied {
            // One-time rest-pose restore when sway stops (Reduce Motion toggled mid-session).
            antenna.orientation = simd_quatf(angle: 0, axis: SIMD3<Float>(0, 0, 1))
            antennaTip.position = SIMD3<Float>(0, antennaTipY, 0)
            swayApplied = false
            whip = 0
            whipVel = 0
        }
        particles.step(Float(dt), speed: lastSpeed)
        stepSkids(Float(dt))
        // Ring-pass shockwave: grow ~2× over its life while scrolling past with the world.
        if ringPulseLife > 0 {
            ringPulseLife -= Float(dt)
            if ringPulseLife <= 0 {
                ringPulse.isEnabled = false
            } else {
                let f = 1 - ringPulseLife / ringPulseMaxLife
                ringPulse.scale = SIMD3<Float>(repeating: 1 + f * 1.1)
                ringPulse.position.z += lastSpeed * Float(dt)
            }
        }
        if shake > 0 { shake = max(0, shake - Float(dt) * 2.2) }
        if fovKick > 0 { fovKick = max(0, fovKick - Float(dt) * 12) }   // +3° decays over ~0.25 s
    }

    func resetEntities() {
        pools.releaseAll()
        particles.reset()
        shake = 0
        fovKick = 0
        chronoDip = 0
        boostFOV = 0
        slideRoll = 0
        slideDip = 0
        camXV = 0
        vxEst = 0; vyEst = 0
        lastPlayerX = 0; lastPlayerY = 0   // runs start at lane centre, grounded
        jumpStretchT = 0; landSquashT = 0
        whip = 0; whipVel = 0
        runPhase = 0
        trailDebt = 0; dustDebt = 0; speedLineDebt = 0
        ringPulseLife = 0
        ringPulse.isEnabled = false
        for i in skids.indices { skidLife[i] = 0; skids[i].isEnabled = false }
        // Re-seed decor around 0. Checkpoint starts (distance > 0) self-heal on the first
        // update: the recycle-while loop walks every slot forward and restyles it once.
        decor.reset(distance: 0)
    }

    /// v1.3 skin pipeline: colors + trail tint + rig geometry + idle sway from one `Skin` recipe.
    /// Rebuilds the character rig — called on equip/launch only, NEVER per frame. Prism
    /// (`bodyHex == 0`) keeps the followsWorld chameleon behavior: nil trail = world accent.
    func applySkin(_ skin: Skin) {
        skinBodyHex = skin.bodyHex
        skinAntennaHex = skin.antennaHex
        skinFollowsWorld = skin.followsWorld
        skinTrailColor = skin.trailHex.map { uiHex($0) }
        skinBodyShape = skin.bodyShape
        skinScale = min(max(skin.scale, 0.85), 1.12)   // visual-only cap — never misrepresent the hitbox
        skinEyeRadius = skin.eyeRadius
        skinEyeTintHex = skin.eyeTintHex
        skinPupil = skin.pupilStyle
        skinAntennaHeight = skin.antennaHeightScale
        skinAntennaTip = skin.antennaTipScale
        skinSway = Float(skin.idle.sway)
        skinSwaySpeed = skin.idle.bobSpeed * 2
        rebuildCharacter()
        paletteKey = -1   // force the cached character/world materials to rebuild next sync
    }

    /// Legacy 3-arg shim — GameView still calls this until the wave-5 rewire (R13); kept compiling
    /// through v1.3, deleted in v1.4. Colors only: the rig stays whatever it currently is.
    func applySkin(bodyHex: UInt32, antennaHex: UInt32, followsWorld: Bool) {
        skinBodyHex = bodyHex
        skinAntennaHex = antennaHex
        skinFollowsWorld = followsWorld
        paletteKey = -1   // force the cached character/world materials to rebuild next sync
    }

    // MARK: scene construction

    private func buildScene() {
        camera.camera.fieldOfViewInDegrees = 62
        camera.position = SIMD3<Float>(0, 5.1, 9.6)
        camera.look(at: SIMD3<Float>(0, 1.3, -5), from: camera.position, relativeTo: nil)
        root.addChild(camera)

        backdrop = ModelEntity(mesh: .generatePlane(width: 140, height: 90), materials: [UnlitMaterial(color: .black)])
        backdrop.position = SIMD3<Float>(0, 12, -65)
        root.addChild(backdrop)

        let ground = ModelEntity(mesh: .generatePlane(width: 16, depth: 260), materials: [UnlitMaterial(color: UIColor(white: 0.02, alpha: 1))])
        ground.position = SIMD3<Float>(0, -0.02, -110)
        root.addChild(ground)

        for x in [Float(-3.3), -1.1, 1.1, 3.3] {
            let line = ModelEntity(mesh: .generateBox(width: 0.06, height: 0.02, depth: 260), materials: [UnlitMaterial(color: .magenta)])
            line.position = SIMD3<Float>(x, 0, -110)
            root.addChild(line)
            laneLines.append(line)
        }

        for _ in 0..<rungCount {
            let r = ModelEntity(mesh: .generateBox(width: 9, height: 0.04, depth: 0.14), materials: [UnlitMaterial(color: .magenta)])
            root.addChild(r)
            rungs.append(r)
        }

        // Slide skid marks (pooled, disabled until dropped).
        let skidMesh = MeshResource.generateBox(width: 0.9, height: 0.01, depth: 2.4)
        for _ in 0..<4 {
            let s = ModelEntity(mesh: skidMesh, materials: [UnlitMaterial(color: UIColor(white: 0.05, alpha: 1))])
            s.isEnabled = false
            root.addChild(s)
            skids.append(s)
            skidLife.append(0)
        }

        // Ring-pass shockwave torus (one-shot flourish; material swapped on fire, never per frame).
        ringPulse = ModelEntity(mesh: ringMesh, materials: [UnlitMaterial(color: .cyan)])
        ringPulse.isEnabled = false
        root.addChild(ringPulse)

        // The rig itself must live under root — buildCharacter() only parents the body parts to
        // the rig. Without this line the whole character is orphaned and never rendered (this is
        // exactly what shipped in v1.3: every play-mode frame shows the wake but no body).
        root.addChild(playerRig)
        buildCharacter()
    }

    /// Tear the character rig down to nothing and rebuild it from the current skin params.
    /// Only ever runs on equip/launch (~7 small entities) — negligible, and never per frame.
    private func rebuildCharacter() {
        playerBody?.removeFromParent()
        for eye in eyes { eye.removeFromParent() }
        eyes.removeAll()
        antenna?.removeFromParent()
        antennaTip?.removeFromParent()
        buildCharacter()
    }

    /// Build the character rig from the stored skin params (defaults reproduce the classic Prism
    /// sphere). Eyes keep the same world-space face anchor for every body shape so the existing
    /// blink/squash code needs no per-shape branches. Sizes per DESIGN_characters §1.6.
    private func buildCharacter() {
        let bodyMesh: MeshResource
        var bodyY: Float = 0.66
        switch skinBodyShape {
        case .sphere:  bodyMesh = .generateSphere(radius: 0.62)
        case .cube:    bodyMesh = .generateBox(width: 1.06, height: 1.06, depth: 1.06, cornerRadius: 0.18)
        case .crystal: bodyMesh = ProceduralMesh.octahedron(0.78); bodyY = 0.72
        }
        let body = ModelEntity(mesh: bodyMesh, materials: [UnlitMaterial(color: .cyan)])
        body.position = SIMD3<Float>(0, bodyY, 0)
        playerRig.addChild(body)
        playerBody = body

        // Eyes face the chase camera (+Z) with a pupil child styled per skin, so the face reads.
        let pupilDark = UnlitMaterial(color: UIColor(white: 0.02, alpha: 1))
        let eyeMat = UnlitMaterial(color: uiHex(skinEyeTintHex))
        for ex in [Float(-0.22), 0.22] {
            let eye = ModelEntity(mesh: .generateSphere(radius: skinEyeRadius), materials: [eyeMat])
            eye.position = SIMD3<Float>(ex, 0.82, 0.52)
            let pupil: ModelEntity
            switch skinPupil {
            case .dot:
                pupil = ModelEntity(mesh: .generateSphere(radius: 0.06), materials: [pupilDark])
            case .wide:
                pupil = ModelEntity(mesh: .generateSphere(radius: 0.085), materials: [pupilDark])
            case .slit:
                pupil = ModelEntity(mesh: .generateSphere(radius: 0.07), materials: [pupilDark])
                pupil.scale = SIMD3<Float>(0.45, 1.5, 1)
            case .glint:
                pupil = ModelEntity(mesh: .generateSphere(radius: 0.06), materials: [pupilDark])
                let glint = ModelEntity(mesh: .generateSphere(radius: 0.025), materials: [UnlitMaterial(color: cWhite)])
                glint.position = SIMD3<Float>(0.025, 0.025, 0.03)
                pupil.addChild(glint)
            }
            pupil.position = SIMD3<Float>(0, 0, 0.1)
            eye.addChild(pupil)
            playerRig.addChild(eye)
            eyes.append(eye)
        }

        // Antenna: stem bottom pinned at y 1.21 whatever the height scale; tip rides on top.
        // The sway code pivots the tip on an arm around the stem CENTRE, so record both heights.
        let h = skinAntennaHeight
        antennaCenterY = 1.21 + 0.21 * h
        antennaTipY = 1.21 + 0.42 * h + 0.045
        antenna = ModelEntity(mesh: .generateCylinder(height: 0.42 * h, radius: 0.025), materials: [UnlitMaterial(color: .cyan)])
        antenna.position = SIMD3<Float>(0, antennaCenterY, 0)
        playerRig.addChild(antenna)

        antennaTip = ModelEntity(mesh: .generateSphere(radius: 0.095 * skinAntennaTip), materials: [UnlitMaterial(color: .magenta)])
        antennaTip.position = SIMD3<Float>(0, antennaTipY, 0)
        playerRig.addChild(antennaTip)
        swayApplied = false   // fresh rig is at rest pose by construction
    }

    private func makeEntity(_ kind: EntityKind) -> Entity {
        switch kind {
        case .low:        return boxEntity(1.9, 0.85, 0.9, .magenta)
        case .tall:       return boxEntity(1.9, 3.2, 0.9, .cyan)
        case .movingTall: return boxEntity(1.9, 3.2, 0.9, .magenta)
        case .bar:        return boxEntity(7.6, 0.7, 0.7, .magenta)
        case .splitBar:   return splitBarEntity()
        case .gem:        return ModelEntity(mesh: gemMesh, materials: [matGemGold])
        case .shield:     return sphereEntity(0.42, cWhite)
        case .magnet:     return ModelEntity(mesh: magnetMesh, materials: [UnlitMaterial(color: .cyan)])
        case .doubler:    return ModelEntity(mesh: doublerMesh, materials: [UnlitMaterial(color: uiHex(0x00FF88))])
        case .chrono:     return ModelEntity(mesh: chronoMesh, materials: [UnlitMaterial(color: uiHex(0x9BF0FF))])
        // Ring/pad get the live accent material reassigned every frame in the place closure
        // (same pattern as obstacles), so the creation-time material is just a safe seed.
        case .ring:       return ModelEntity(mesh: ringMesh, materials: [matAccent])
        case .boostPad:   return ModelEntity(mesh: padMesh, materials: [matAccent])
        }
    }

    /// Two one-lane bar segments under a shared parent. The segments' x offsets are repositioned
    /// every frame by the place closure (the entity's `lane` is the OPEN lane and a recycled
    /// pooled splitBar may need a different gap). Segment width 2.5 matches the collision band
    /// exactly (`laneHitHalfWidth` 1.25 either side of the covered lane), leaving a ~1.9-wide
    /// visible gap over the open lane.
    private func splitBarEntity() -> Entity {
        let parent = Entity()
        for _ in 0..<2 {
            parent.addChild(ModelEntity(mesh: splitBarSegmentMesh, materials: [UnlitMaterial(color: .magenta)]))
        }
        return parent
    }

    private func boxEntity(_ w: Float, _ h: Float, _ d: Float, _ c: UIColor) -> ModelEntity {
        ModelEntity(mesh: .generateBox(width: w, height: h, depth: d, cornerRadius: 0.04), materials: [UnlitMaterial(color: c)])
    }

    private func sphereEntity(_ r: Float, _ c: UIColor) -> ModelEntity {
        ModelEntity(mesh: .generateSphere(radius: r), materials: [UnlitMaterial(color: c)])
    }

    private func uiHex(_ hex: UInt32) -> UIColor {
        UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }

    private func kickFOV() {
        if !reduceMotion { fovKick = max(fovKick, 3) }
    }

    private func dropSkid(at x: Float) {
        skidCursor = (skidCursor + 1) % skids.count
        let e = skids[skidCursor]
        e.position = SIMD3<Float>(x, 0.005, 0.3)
        e.scale = .one
        e.isEnabled = true
        skidLife[skidCursor] = skidMaxLife
    }

    private func stepSkids(_ dt: Float) {
        for i in skids.indices where skidLife[i] > 0 {
            skidLife[i] -= dt
            if skidLife[i] <= 0 {
                skids[i].isEnabled = false
                continue
            }
            skids[i].position.z += lastSpeed * dt            // scroll past with the world
            let f = skidLife[i] / skidMaxLife
            skids[i].scale = SIMD3<Float>(f, 1, 0.6 + 0.4 * f)   // fade via scale
        }
    }
}

/// The current crossfaded world palette as `UIColor`s. `lane` is the grid color pushed toward
/// white by (1 − blend), so lane lines flare during a world crossfade and settle as it completes.
private struct Palette {
    let bg, grid, accent, accent2, lane: UIColor
    init(_ snap: GameSnapshot) {
        let a = Theme.worlds[snap.worldFrom % 3]
        let b = Theme.worlds[snap.worldTo % 3]
        let t = Float(snap.worldBlend)
        func ui(_ v: SIMD3<Float>) -> UIColor {
            UIColor(red: CGFloat(v.x), green: CGFloat(v.y), blue: CGFloat(v.z), alpha: 1)
        }
        let gridV = Theme.mix(a.grid, b.grid, t)
        bg = ui(Theme.mix(a.bg, b.bg, t))
        grid = ui(gridV)
        accent = ui(Theme.mix(a.accent, b.accent, t))
        accent2 = ui(Theme.mix(a.accent2, b.accent2, t))
        lane = ui(Theme.mix(gridV, SIMD3<Float>(1, 1, 1), (1 - t) * 0.85))
    }
}
