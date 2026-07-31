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
    private var shoes: [ModelEntity] = []   // amber boots shown on the feet while Super Sneakers is active
    private var crestParts: [ModelEntity] = []  // cosmetic head crest meshes (v1.6 rarity ladder)
    private var auraRing: ModelEntity?      // legendary orbiting aura torus (v1.6); spun in advanceVisuals
    private var auraSpin: Float = 0         // aura ring rotation phase
    private var backdrop: ModelEntity!
    private var rungs: [ModelEntity] = []
    private var laneLines: [ModelEntity] = []
    private var pools: EntityPools!
    private let wardenRig = WardenRig()   // v1.9 set piece; off unless an encounter is live
    private var decor: WorldDecor!

    private let cGold = UIColor(red: 1, green: 210/255.0, blue: 61/255.0, alpha: 1) // #FFD23D
    private let cWhite = UIColor.white
    // Warden hazard colours (v1.9; **re-hued v2.3**). World-blind by design — the same reason the
    // chasm's walls are: a threat must look identical in all twelve families, and the accents reach
    // pure white in two (Datastream, Tempest).
    //
    // **The red is gone** (owner, S-013: *"i hate the red colour"*). It was `#FF3355`, and it was
    // painted as a flat saturated FILL across every surface a Warden owned — which is also half of
    // *"blocking the view of everything"*, because a full-span slab of saturated red is an opaque
    // wall of colour whether or not the geometry behind it matters.
    //
    // The replacement is a two-tone treatment rather than a new fill colour, and that is the actual
    // fix: a near-black body carries the MASS (the chasm's trick — read by silhouette, not by hue)
    // and a bright violet edge carries the MEANING. Violet was already the Warden's own channel on
    // the craft's spars, so the fight now speaks one colour instead of two, and it is far in hue
    // from both reserved meanings on the deck: gold gems (`#FFD23D`, which share the arena with it)
    // and shield cyan (`#66E0FF`).
    private let cWardenHazard = UIColor(red: 199/255.0, green: 123/255.0, blue: 1, alpha: 1) // #C77BFF
    /// The body. Darker than every world's deck, so it reads as a hole punched in the light rather
    /// than as another coloured surface competing with the track.
    private let cWardenHazardDark = UIColor(red: 42/255.0, green: 31/255.0, blue: 61/255.0, alpha: 1) // #2A1F3D
    private let cWardenShield = UIColor(red: 102/255.0, green: 224/255.0, blue: 1, alpha: 1) // #66E0FF

    private let rungSpacing: Float = 4
    private let rungCount = 36

    private let gemMesh: MeshResource
    private let magnetMesh: MeshResource
    private let doublerMesh: MeshResource   // twin octahedron (coin-doubler pickup, see makeEntity)
    private let chronoMesh: MeshResource    // hourglass (chrono slow-mo pickup)
    private let shieldMesh: MeshResource    // heater-shield crest (shield pickup, S-009)
    private let splitBarSegmentMesh: MeshResource   // one-lane bar segment (two per splitBar)
    private let ringMesh: MeshResource      // prism-ring gate torus (hole faces the camera, +Z)
    private let padMesh: MeshResource       // overdrive-pad floor chevron strip (flat, XZ plane)
    private let sneakerArmMesh: MeshResource // one chevron arm (four per Super Sneakers boost glyph)
    private let chasmShaftMesh: MeshResource // the void well's four walls, sunk into the deck (v1.8)
    private let chasmFloorMesh: MeshResource // the well's floor (darker than the walls)
    private let chasmLidMesh: MeshResource   // opaque panel that interrupts the deck grid
    private let chasmRimMesh: MeshResource   // one lit rim bar (two per chasm: near and far edge)

    // Selected character skin — authored hexes only, NEVER world-driven (owner decree 1).
    // Defaults reproduce Prism's authored identity for the pre-`applySkin` frame.
    private var skinBodyHex: UInt32 = 0x00F5FF
    private var skinAntennaHex: UInt32 = 0xFF2BD6

    // v1.3 skin rig (set by `applySkin(_ skin:)`). All visual-only — the hitbox
    // (Core's bodyRadius/groundedCenterY) never sees any of this.
    private var skinTrailColor =                    // always the skin's OWN color, never the world
        UIColor(red: 0, green: 245 / 255.0, blue: 1, alpha: 1)   // Prism's authored cyan 0x00F5FF
    private var skinBodyShape: Skin.BodyShape = .sphere
    private var skinSpectrum: [UInt32]? = nil       // static banded body (Prism) — see D-011
    private var skinScale: Float = 1                // folded into the per-frame pose, 0.85…1.12
    private var skinEyeRadius: Float = 0.13
    private var skinEyeTintHex: UInt32 = 0xFFFFFF
    private var skinPupil: Skin.PupilStyle = .dot
    private var skinAntennaHeight: Float = 1
    private var skinAntennaTip: Float = 1
    private var skinCrest: Skin.Crest = .none       // cosmetic head crest (v1.6 rarity ladder)
    private var skinCrestHex: UInt32 = 0xFF2BD6     // crest colour (antenna hue, or body if too dark)
    private var skinHasAura = false                 // legendary orbiting aura ring (v1.6)
    private var skinSway: Float = 0                 // radians; set per skin by applySkin
    /// Idle sway angular speed (rad/s) = `idle.bobSpeed · 2π · 0.8` — the EXACT formula the
    /// preview animates (`CharacterSwatch.drawAntenna`), so Tempo's metronome whip reads at
    /// full stage speed in-run (AUDIT D2-3; the old `bobSpeed * 2` ran ~2.5× slower). The
    /// default is Prism's catalog bobSpeed 1.6 Hz for the pre-`applySkin` frame.
    private var skinSwaySpeed: Double = 1.6 * 2 * .pi * 0.8
    // Per-skin blink cadence (catalog `idle.blinkMin/Max`) — the personality the previews sell
    // (Fang "Blinks never", Tempo's 3 s beat) now holds in-run too (AUDIT D2-2). Defaults are
    // Prism's catalog range for the pre-`applySkin` frame.
    private var skinBlinkMin: Double = 2.2
    private var skinBlinkMax: Double = 4.2
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
    private var camLift: Float = 0          // smoothed vertical follow for high/boots jumps (v1.6)
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
    private var sneakerDebt: Float = 0      // amber up-spark cadence while Super Sneakers is active

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

    // A soft translucent dome around the player while a shield is HELD (no timer — it lasts until a
    // hit, then the glass-shatter FX plays). Snapshot-driven so it can never get stuck on/off.
    private var shieldBubble: ModelEntity!
    private var stumbleAura: ModelEntity!   // v2.0: lit while a stumble leaves the player vulnerable
    private var blastRing: ModelEntity!     // v2.2: the shockwave front, driven by snapshot geometry
    // Live craft position, mirrored from the last synced snapshot so FXEvents can land on it.
    private var wardenX: Float = 0
    private var wardenY: Float = Float(Tuning.wardenHoverY)
    private var wardenZ: Float = Float(Tuning.wardenStandOff)
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
    /// The Warden's hazard violet, held as a material so thrown obstacles can be tinted every frame
    /// without allocating. World-blind on purpose: a Warden's wall is the Warden's, in every world.
    /// (v2.3: was `#FF3355`. See `cWardenHazard` for why the red went.)
    private let matWardenHazard = UnlitMaterial(color: UIColor(red: 199/255.0, green: 123/255.0, blue: 1, alpha: 1))
    /// The body tone that goes with it — see `cWardenHazardDark`.
    private let matWardenHazardDark = UnlitMaterial(color: UIColor(red: 42/255.0, green: 31/255.0, blue: 61/255.0, alpha: 1))
    private let matGemGold: UnlitMaterial
    private let matGemHot: UnlitMaterial    // magnet-pulled gems tint hotter as they shrink

    init() {
        gemMesh = ProceduralMesh.octahedron(0.34)
        magnetMesh = ProceduralMesh.torus(major: 0.30, minor: 0.12)
        doublerMesh = ProceduralMesh.twinOctahedron(0.26, offset: 0.34)
        chronoMesh = ProceduralMesh.hourglass(halfBase: 0.3, halfHeight: 0.42)
        // Sized to the old sphere's 0.42 footprint so spacing, pickup radius and the pooled
        // entity's scale are all unchanged — only the silhouette differs.
        shieldMesh = ProceduralMesh.shieldCrest(halfWidth: 0.34, height: 0.42, halfDepth: 0.07)
        splitBarSegmentMesh = .generateBox(width: 2.5, height: 0.7, depth: 0.7, cornerRadius: 0.04)
        // Ring gate: hole radius 0.79 vs body radius 0.62 — threading reads true to the ±0.9
        // pass window without looking trivially wide. Same generator as the magnet torus.
        ringMesh = ProceduralMesh.torus(major: 0.88, minor: 0.09, majorSeg: 28, minorSeg: 10)
        padMesh = ProceduralMesh.chevronStrip()
        sneakerArmMesh = .generateBox(width: 0.36, height: 0.11, depth: 0.11, cornerRadius: 0.035)
        // Chasm: the shaft spans the full deck width (3.8 either side, matching the bar mesh) and
        // the exact collision length, so what you see IS what kills you — the length comes from
        // `Tuning.chasmHalfLength`, never a literal. 1.7 deep reads as a drop without the far floor
        // vanishing under the backdrop.
        chasmShaftMesh = ProceduralMesh.chasmWalls(halfWidth: 3.8,
                                                   halfLength: Float(Tuning.chasmHalfLength),
                                                   depth: 1.7)
        chasmFloorMesh = ProceduralMesh.chasmFloor(halfWidth: 3.8,
                                                   halfLength: Float(Tuning.chasmHalfLength),
                                                   depth: 1.7)
        chasmLidMesh = .generatePlane(width: 7.6, depth: Float(Tuning.chasmHalfLength) * 2)
        chasmRimMesh = .generateBox(width: 7.6, height: 0.14, depth: 0.5, cornerRadius: 0.03)
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
        pools.prewarm(.superSneakers, count: Tuning.capSuperSneakers)
        pools.prewarm(.chasm, count: Tuning.capChasm)   // tier six: first spawn is ~2,560 m in
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
        // Keyed on the ABSOLUTE ordinals (not the 0–2 family), so each evolution cycle gets its
        // own cached materials — worlds 0 and 3 share a family but must not share a palette
        // (v1.4.3). fromOrdinal = toOrdinal − 1 holds because worlds step exactly one at a time
        // during a crossfade; in steady state worldBlend == 1 so the `from` half contributes 0.
        let toOrd = snap.worldOrdinal, fromOrd = max(0, toOrd - 1)
        let key = fromOrd &* 1_000_000 &+ toOrd &* 1_000 &+ Int(snap.worldBlend * 64)
        if key != paletteKey {
            paletteKey = key
            let pal = Palette(snap)
            tintAccent = pal.accent
            tintAccent2 = pal.accent2
            matAccent = UnlitMaterial(color: pal.accent)
            matAccent2 = UnlitMaterial(color: pal.accent2)
            backdrop.model?.materials = [UnlitMaterial(color: pal.bg)]
            let gridMat = UnlitMaterial(color: pal.grid)   // ONE instance shared by every rung
            for r in rungs { r.model?.materials = [gridMat] }
            let laneMat = UnlitMaterial(color: pal.lane)   // pushed toward white mid-crossfade
            for l in laneLines { l.model?.materials = [laneMat] }
            // The character is deliberately ABSENT here: its colors are authored per skin
            // (applied in applySkin / the shimmer step in advanceVisuals) and never react to
            // a world crossfade — owner decree 1.
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
        // Vertical follow (v1.6): when a jump carries the player ABOVE a normal apex (~2.82) — i.e. a
        // Super Sneakers leap — the eye + look-at rise with them so they stay framed instead of flying
        // off the top of the screen (the owner's "camera should follow you up"). Threshold sits just
        // past the normal apex, so ordinary jumps are untouched; smoothed, and returns to 0 on landing.
        let liftTarget = min(2.0, max(0, Float(snap.playerY) - 2.9))
        camLift += (liftTarget - camLift) * 0.25
        let cp = SIMD3<Float>(camX + shakeX, 5.1 - dropY + camLift * 0.6 + shakeY,
                              9.6 - (reduceMotion ? 0 : slideDip * 0.8))
        camera.position = cp
        let lookY: Float = 1.3 + camLift - (reduceMotion ? 0 : slideDip * 0.85)
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
        // Live play only: the death shatter replaces the rig in .over, and on the menu the
        // SwiftUI hero stage is the character moment (the in-world rig idling behind PLAY
        // doubled the character on screen).
        playerRig.isEnabled = snap.mode == .play
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

        // Super Sneakers boots: show on the feet while the buff is live (a glance-readable "it's on").
        let shoesOn = snap.sneakersRemaining > 0 && snap.mode == .play
        for shoe in shoes where shoe.isEnabled != shoesOn { shoe.isEnabled = shoesOn }

        // Shield dome: held-shield readout in-world (gentle breathe, RM-static). It does NOT time out.
        let shieldOn = snap.shieldActive && snap.mode == .play
        shieldBubble.isEnabled = shieldOn
        if shieldOn {
            shieldBubble.position = SIMD3<Float>(px, Float(snap.playerY) + 0.66, 0)
            shieldBubble.scale = SIMD3<Float>(repeating: 1 + (reduceMotion ? 0 : 0.05 * Float(sin(elapsed * 3))))
        }

        // Vulnerability shell: driven from `stumbleRemaining` rather than from the `.stumbled` event,
        // so it can never be left on by a missed edge and can never be missed on a revive — the same
        // snapshot-driven rule the boost and sneakers treatments follow.
        //
        // It strobes at ~9 Hz and, under Reduce Motion, holds steady instead of flashing (a
        // photosensitivity-safe constant tint) rather than being switched off: this is a safety
        // readout, not decoration, and dropping it would leave the accommodation MORE dangerous.
        let vulnerable = snap.stumbleRemaining > 0 && snap.mode == .play
        if vulnerable {
            stumbleAura.position = SIMD3<Float>(px, Float(snap.playerY) + 0.66, 0)
            // Widens as the window runs down, so the ring is at its largest in the last moments of
            // vulnerability — the shape of the risk, not just its presence.
            let urgency = 1 - Float(snap.stumbleRemaining / Tuning.stumbleRecover)
            stumbleAura.scale = SIMD3<Float>(repeating: 1.0 + 0.36 * urgency)
            // **The strobe is the load-bearing channel, not the colour.** Prism — the default
            // character — wears a STATIC RAINBOW (D-011), so a steady red ring hugging its body
            // reads as one more of its own bands; verified on the simulator, where exactly that
            // happened. Nothing else in the game blinks, so blinking is unambiguous where hue is
            // not. Reduce Motion holds it solid instead: this is a safety readout, and a player who
            // cannot have the flicker still needs the ring.
            stumbleAura.isEnabled = reduceMotion || sin(elapsed * 44) > -0.35
        } else if stumbleAura.isEnabled {
            stumbleAura.isEnabled = false
        }

        // THE BLAST's travelling front (v2.2). `blastFrontZ` uses the entity sign convention
        // (negative = ahead), and RealityKit's −z is into the screen, so the position is a straight
        // negation exactly as every obstacle's is. It widens as it runs so the wave reads as
        // expanding rather than as a hoop sliding down the track, and it dims toward the end of its
        // reach so the player can see where the range stops. Never rotated: face-on IS the read.
        if let fz = snap.blastFrontZ {
            let travelled = Float(min(1, max(0, -fz / Tuning.blastRange)))
            blastRing.position = SIMD3<Float>(Float(snap.playerX) * (1 - travelled), 1.35, Float(fz))
            // 1.6 → 4.6 world units of radius. Tuned on the simulator against a first attempt at
            // 2.6 → 7.0, which was wrong for a reason worth writing down: perspective already makes
            // a ring near the camera enormous, so a scale curve that *also* starts wide paints a
            // fat cyan hoop across the exact rows the player is trying to read (decree 6). Born at
            // roughly the body's own width and grown just enough to hold its apparent size as it
            // recedes, it reads as a wave leaving without ever hiding the track it is clearing.
            blastRing.scale = SIMD3<Float>(repeating: 1.6 + 3.0 * travelled)
            blastRing.isEnabled = true
        } else if blastRing.isEnabled {
            blastRing.isEnabled = false
        }

        // Dust kicked up during a slide — grounded OR mid air-slam — so it's unmistakable.
        // Time-based (≈ the old 6/frame at 60 Hz) so density matches at 120 Hz. The wider x
        // scatter + slightly hotter power turn it into a continuous ground ribbon behind the body.
        if snap.mode == .play, snap.sliding {
            dustDebt += 360 * lastDt
            let n = Int(dustDebt)
            if n > 0 {
                dustDebt -= Float(n)
                particles.burst(x: px + Float.random(in: -0.55...0.55), y: 0.12, z: 0.5,
                                color: skinTrailColor, count: n, power: 2.1, spread: 0.2, life: 0.5)
            }
        }

        // Grid scroll.
        let off = Float(snap.distance.truncatingRemainder(dividingBy: Double(rungSpacing)))
        for (i, r) in rungs.enumerated() { r.position.z = off + 10 - Float(i) * rungSpacing }

        // Spawned entities — the two obstacle materials are rebuilt with the palette above, then
        // assigned by reference. Also fixes stale pooled colors.
        let mA = matAccent, mA2 = matAccent2, mWarden = matWardenHazard
        let mGold = matGemGold, mHot = matGemHot
        pools.sync(snap.entities) { entity, s in
            // `s.y` is authoritative for EVERY kind (bar/splitBar centre 1.3, low 0.425, tall 1.6
            // now arrive from the core) — never hardcode heights here.
            entity.position = SIMD3<Float>(Float(s.x), Float(s.y), Float(s.z))
            // **A Warden's wall is red, in every world (v2.2).** Not decoration: inside an arena a
            // thrown obstacle follows a different rule from every other obstacle in the game — it
            // staggers and can never kill — so the player must be able to tell whose wall it is in
            // one frame (decree 6). Red is already the Warden's colour everywhere else in the fight.
            let mObstacle = s.fromWarden ? mWarden : mA
            let mObstacle2 = s.fromWarden ? mWarden : mA2
            switch s.kind {
            case .tall:
                (entity as? ModelEntity).map { $0.model?.materials = [mObstacle] }
            case .bolt:
                // Always the Warden's violet — a shot has no non-Warden variant to distinguish it
                // from, and it spins about its own long axis so a closing spindle reads as a
                // projectile in flight rather than a static dart being scrolled toward you.
                (entity as? ModelEntity).map { $0.model?.materials = [mWarden] }
                entity.orientation = simd_quatf(angle: Float(s.z) * 0.55, axis: SIMD3<Float>(0, 0, 1))
            case .low, .bar, .movingTall:
                (entity as? ModelEntity).map { $0.model?.materials = [mObstacle2] }
            case .hangingBar:
                // Nothing to do per frame: a hanging bar is a multi-part portcullis whose two tones
                // are baked at construction (`hangingBarEntity`), and it is always the Warden's
                // colour anyway — nothing else in the game hangs from the sky with no way over it.
                // The old one-liner tinted `entity as? ModelEntity`, which a composed entity is
                // not, so leaving it here would have silently done nothing and looked deliberate.
                break
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
            case .shield, .magnet, .doubler, .chrono, .superSneakers:
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
            case .chasm:
                // A parent Entity, so `entity as? ModelEntity` fails silently and the seed colour
                // would stick forever — recolour by walking the children, as splitBar does. The
                // walls and floor keep their fixed world-blind materials; the LAST TWO children are
                // the rims and they take the live accent. `suffix(2)` rather than an index so
                // adding another static part to the well can never silently recolour it.
                for child in entity.children.suffix(2) {
                    (child as? ModelEntity)?.model?.materials = [mObstacle2]
                }
            }
        }

        // The Warden set piece (v1.9). Driven from its own snapshot field rather than the
        // entity pools, because it is not an obstacle and must never be pooled as one.
        wardenRig.sync(snap.warden, dt: Double(lastDt), reduceMotion: reduceMotion)
        // Remember where the craft actually IS, so one-shot FX land on it. Its position animates now
        // (arrival approach, lane lean, hit recoil, departure), so the old hardcoded (0, 5.2, −26)
        // in the fire() arms would miss it by up to 26 units mid-encounter.
        if let w = snap.warden {
            wardenX = Float(w.x); wardenY = Float(w.y); wardenZ = Float(-w.z)
        }

        // Speed trail behind the player — time-based (≈ the old 3/frame at 60 Hz). The emission
        // rate breathes with chrono slow-mo so the trail thins while the world crawls. The wake
        // is always the skin's own color (Prism's rides the live shimmer hue, never the world
        // accent); during an overdrive boost it thickens and elongates into streaks.
        if snap.mode == .play {
            let boosting = snap.boostRemaining > 0
            trailDebt += 180 * (snap.chronoRemaining > 0 ? Float(Tuning.chronoFactor) : 1)
                             * (boosting ? 1.6 : 1) * lastDt
            let n = Int(trailDebt)
            if n > 0 {
                trailDebt -= Float(n)
                particles.burst(x: px + Float.random(in: -0.2...0.2), y: 0.25 + Float(snap.playerY), z: 0.5,
                                color: skinTrailColor, count: n, power: 0.9, spread: 0.08,
                                life: 0.45, velZ: boosting ? 7 : 0, stretchZ: boosting ? 2.4 : 1)
            }
        }

        // Super Sneakers: amber up-sparks at the feet while active — a distinct in-world cue that
        // jumps launch higher (decree 6). Kept OFF the player's identity trail (always
        // skinTrailColor, decree 1) by emitting a separate amber layer near the ground.
        if snap.mode == .play, snap.sneakersRemaining > 0, !reduceMotion {
            sneakerDebt += 26 * lastDt
            let n = Int(sneakerDebt)
            if n > 0 {
                sneakerDebt -= Float(n)
                particles.burst(x: px + Float.random(in: -0.3...0.3), y: 0.08 + Float(snap.playerY) * 0.5, z: 0.3,
                                color: uiHex(0xFF8A2B), count: n, power: 1.7, spread: 0.22, life: 0.5)
            }
        }

        // Speed lines above ~22 m/s (owner spec) — and for the whole of an overdrive boost, whose
        // +30% kick is the one moment that must FEEL faster even when the raw speed is below the gate.
        // White streaks at the screen edges (x ±4.5, outside the ±3.3 lanes) so they sell speed
        // without cluttering the central gameplay read (decree 6). Pure render — RM-gated, no RNG.
        if snap.mode == .play, !reduceMotion, lastSpeed > 22 || snap.boostRemaining > 0 {
            speedLineDebt += min(90, max((lastSpeed - 22) * 7, snap.boostRemaining > 0 ? 40 : 0)) * lastDt
            let n = Int(speedLineDebt)
            if n > 0 {
                speedLineDebt -= Float(n)
                for _ in 0..<n {
                    particles.burst(x: (Bool.random() ? 4.5 : -4.5) + Float.random(in: -0.8...0.8),
                                    y: Float.random(in: 1.2...5.2), z: -8, color: cWhite,
                                    count: 1, power: 0.2, spread: 0.1, life: 0.34,
                                    velZ: lastSpeed * 1.6, stretchZ: 3.2)
                }
            }
        }

        // Per-world decor + sky atmosphere (the sky's own motion is RM-gated inside). Fed the
        // ABSOLUTE ordinal, not the 0–2 family — WorldSky's per-world seed + cycle richening
        // (world / 3 element counts) are dead at a family index (v1.4 review fix).
        decor.update(distance: snap.distance, world: snap.worldOrdinal, elapsed: elapsed, reduceMotion: reduceMotion)
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
                particles.burst(x: Float(x), y: 0.1, z: 0.3, color: skinTrailColor,
                                count: 7, power: 2.0, spread: 0.26, life: 0.35)
            }
        case let .landed(x):
            particles.burst(x: Float(x), y: 0.1, z: 0.2, color: skinTrailColor, count: 10, power: 2.6, spread: 0.32, life: 0.4)
            if !reduceMotion { landSquashT = 0.18 }   // body squash sells the existing dust ring
        case let .laneChanged(x):
            // Skid kick where the dodge started — the antenna whip + camera lateral spring
            // (both velocity-driven in sync/advanceVisuals) carry the rest of the motion.
            if !reduceMotion {
                particles.burst(x: Float(x), y: 0.12, z: 0.4, color: skinTrailColor,
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
            case .superSneakers:
                // Amber up-burst — energetic "leap" pop, distinct from the cool-toned pickups.
                particles.burst(x: Float(x), y: Float(y), z: 0, color: uiHex(0xFF8A2B), count: 30, power: 5.0, spread: 0.34, life: 0.8)
                particles.burst(x: Float(x), y: Float(y), z: 0, color: cGold, count: 12, power: 3.6, spread: 0.3, life: 0.7)
            }
            kickFOV()
        case let .shieldAbsorbed(x):
            // Glass shatter: a big white shard burst + a cyan splinter layer, a hard shake, FOV kick —
            // unmistakable that the shield just broke (v1.6).
            particles.burst(x: Float(x), y: 1.2, z: 0, color: cWhite, count: 64, power: 7.6, spread: 0.5, life: 0.8, stretchZ: 1.8)
            particles.burst(x: Float(x), y: 1.2, z: 0, color: uiHex(0x9BF0FF), count: 30, power: 5.6, spread: 0.62, life: 0.7)
            shake = max(shake, 1.3)
            kickFOV()
        // MARK: Wardens (v1.9)
        //
        // All four use the fixed hostile red the rig uses, never a world accent — a hazard has to
        // mean the same thing in all twelve families, and two of them push `accent2` to pure white.
        case .wardenArrived:
            // A ring sweeping IN from the horizon, the mirror of the world-change sweep that goes
            // out: something is arriving, and it is not scenery.
            particles.ring(y: wardenY, z: -wardenZ, radius: 7, color: cWardenHazard,
                           count: 28, velZ: 14, life: 1.0)
            kickFOV()
        case .wardenShieldBroke:
            particles.burst(x: wardenX, y: wardenY, z: -wardenZ, color: cWardenShield,
                            count: 70, power: 8.0, spread: 0.6, life: 0.9)
            if !reduceMotion { shake = max(shake, 0.5) }
        case let .wardenThrew(band, lead):
            // **The muzzle.** A throw fires at the CRAFT, not at the player's plane — that is the
            // whole readability change. v1.9–v2.1 painted the attack on the strike plane at z −9,
            // so the boss and its attack were never visibly connected and the S-011 audit measured
            // the consequence: a red band covering 92–95% of the exposed phase with nothing to say
            // where it came from. Now something visibly leaves the craft and then travels toward
            // you as an object you already know how to read.
            let launchZ = -Float(lead)
            particles.burst(x: wardenX, y: wardenY, z: launchZ, color: cWardenHazard,
                            count: 34, power: 5.5, spread: 0.5, life: 0.5, velZ: 12)
            // A ring in the SHAPE's channel: wide and low for a lance (lanes), tight and high for a
            // curtain (get down), tight and low for a chasm (get up). Peripheral vision catches the
            // ring before the eye has parsed the object.
            particles.ring(y: band == .curtain ? wardenY + 1.2 : 0.6,
                           z: launchZ, radius: band.isLateral ? 5.5 : 3.2,
                           color: cWardenHazard, count: 22, velZ: 16, life: 0.7)
            if !reduceMotion { shake = max(shake, 0.28) }
        case .wardenCoreHit:
            // **Damage has to visibly LEAVE THE PLAYER.** Bursting only at the craft meant something
            // exploded 26 units away with nothing having travelled there, which is the whole reason
            // "why does dodging damage it" reads as arbitrary. It is not arbitrary: the flow surge
            // has always emitted a forward shimmer in the player's own trail colour that lands at
            // `fountainLead` — the same distance the Warden hovers at. The game has been teaching
            // "a clean pass throws something forward to exactly there" for nine versions.
            //
            // So the counter-punch reuses that exact grammar: a trail-coloured cascade running from
            // the player up the track, then the impact at the hull.
            let reach = wardenZ
            for k in 1...7 {
                particles.burst(x: 0, y: 0.9 + Float(k) * 0.42,
                                z: -Float(k) / 7 * reach,
                                color: skinTrailColor, count: 4, power: 1.4, spread: 0.22, life: 0.5)
            }
            particles.burst(x: wardenX, y: wardenY, z: -reach, color: cWardenHazard,
                            count: 46, power: 7.0, spread: 0.45, life: 0.8)
            if !reduceMotion { shake = max(shake, 0.45) }
        case .wardenDefeated:
            particles.burst(x: wardenX, y: wardenY, z: -wardenZ, color: cWhite, count: 90, power: 10, spread: 0.5, life: 1.2)
            particles.burst(x: wardenX, y: wardenY, z: -wardenZ, color: cWardenHazard, count: 120, power: 7.5, spread: 0.7, life: 1.4)
            particles.ring(y: wardenY, z: -wardenZ, radius: 4, color: cWardenShield, count: 30, velZ: 30, life: 1.1)
            if !reduceMotion { shake = max(shake, 1.1) }
            kickFOV()
        case .wardenBrokeOff:
            // Deliberately silent. A break-off is the Warden giving up: nothing happened to the
            // player, so nothing fires. The craft climbing away is the whole statement.
            break

        case let .stumbled(x, fromWarden):
            // **This must not read as slow-mo.** The player has no forward velocity, so cutting the
            // world speed is mechanically what the chrono pickup does — a reward. Chrono NARROWS the
            // FOV by 6° and tints cool; a stumble widens it and throws hot debris, which is the
            // impact grammar the shield-shatter already uses. Nothing about it is cool-toned.
            particles.burst(x: Float(x), y: 0.9, z: 0, color: cWardenHazard,
                            count: 46, power: 6.4, spread: 0.55, life: 0.7, stretchZ: 1.5)
            particles.burst(x: Float(x), y: 0.9, z: 0, color: cWhite,
                            count: 18, power: 4.2, spread: 0.35, life: 0.5)
            // Backward scatter along the deck: the one direction that says "you lost ground".
            particles.burst(x: Float(x), y: 0.12, z: 0.6, color: skinTrailColor,
                            count: 16, power: 3.0, spread: 0.4, life: 0.55)
            if fromWarden {
                // A boss landing a shot is a bigger event than clipping a wall, and it is also the
                // moment the player learns the next one is fatal — so it gets its own ring.
                particles.ring(y: 1.0, z: 0, radius: 1.6, color: cWardenHazard,
                               count: 22, velZ: 8, life: 0.6)
            }
            // 0.70, not the 1.4 of a death: it decays at 2.2/s, so this clears in 0.32 s and cannot
            // still be shaking the frame while the player reads the obstacle that might kill them.
            if !reduceMotion { shake = max(shake, 0.70) }
            kickFOV(5)
        // MARK: THE BLAST (v2.2)
        case let .blastFired(x, y, chargeLeft):
            // The muzzle: a hard forward-directed spray in the SKIN's colour, because this is the
            // player's own act and decree 1 says the player's colour is the player's identity. The
            // hazard red belongs to things that hurt you; this is the one thing you do to them.
            particles.burst(x: Float(x), y: Float(y) + 0.7, z: 0, color: skinTrailColor,
                            count: 34, power: 3.4, spread: 0.3, life: 0.42,
                            velZ: -34, stretchZ: 2.6)
            particles.burst(x: Float(x), y: Float(y) + 0.7, z: 0, color: cWhite,
                            count: 14, power: 2.2, spread: 0.18, life: 0.3, velZ: -22)
            // The last round in the bank kicks harder than the first two — the player should feel
            // the difference between "I have more" and "that was it" without reading the meter.
            let last = chargeLeft < Tuning.blastCost
            if !reduceMotion { shake = max(shake, last ? 0.55 : 0.34) }
            kickFOV(last ? 5 : 3)
        case let .obstacleShattered(_, x, y, z):
            // Debris where the wall WAS. Hazard red, because the thing that just came apart was a
            // thing that was going to kill you — this is the only place the player sees that colour
            // lose. Positive z bias throws it back toward the camera: the path opens toward you.
            particles.burst(x: Float(x), y: Float(y), z: Float(z), color: cWardenHazard,
                            count: 26, power: 4.6, spread: 0.5, life: 0.55, velZ: 9)
            particles.burst(x: Float(x), y: Float(y), z: Float(z), color: cWhite,
                            count: 10, power: 3.2, spread: 0.3, life: 0.34, velZ: 6)

        case let .died(x):
            // First (colored) burst shatters in the skin's own color; the white flash stays global.
            particles.burst(x: Float(x), y: 1, z: 0, color: skinTrailColor, count: 120, power: 7.5, spread: 0.55, life: 1.2)
            particles.burst(x: Float(x), y: 1, z: 0, color: cWhite, count: 60, power: 9.5, spread: 0.35, life: 0.9)
            shake = 1.4
        case let .worldChanged(_, ordinal):
            // One-shot horizon ring sweep in the incoming world's accent (banner is UI-side).
            // Evolved by absolute ordinal so the sweep matches the cycle's palette (v1.4.3).
            let a = Theme.evolvedPalette(ordinal: ordinal).accent
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
            let aura = skinTrailColor
            particles.burst(x: Float(x), y: 1.0, z: 0, color: aura,
                            count: 22 + 4 * min(level, 3), power: 3.0, spread: 0.5, life: 0.7)
            for k in 1...6 {
                particles.burst(x: Float(x), y: 0.6, z: -Float(k) * Float(Tuning.fountainLead) / 6,
                                color: aura, count: 3, power: 1.2, spread: 0.25, life: 0.6)
            }
            particles.burst(x: Float(x), y: 0.9, z: -Float(Tuning.fountainLead), color: cGold,
                            count: 16, power: 2.6, spread: 0.5, life: 0.8)
            kickFOV()
        case .nearMiss, .chronoEnded, .boostEnded, .sneakersEnded:
            break   // popups / banner / haptics / audio handled by the UI layer; boost & sneakers
                    // restore is snapshot-driven (see sync), so these are audio's edges, not ours
        }
    }

    /// Time-based animation (blink, particles, skids, shake/FOV decay) — driven by the loop's
    /// wall-clock dt (runs immediately before `sync` each frame).
    func advanceVisuals(_ dt: Double) {
        elapsed += dt
        lastDt = Float(dt)
        // Re-arm from the skin's OWN catalog range, not a global constant: Fang stares ~5–8 s,
        // Tempo blinks exactly on its 3 s beat — in-run, not just on the select stage (D2-2).
        // Renderer-side randomness is fine here: visual-only, never touches the Core sim.
        blinkT -= dt
        if blinkT < -0.12 { blinkT = Double.random(in: skinBlinkMin...skinBlinkMax) }
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
        // Legendary aura: spin the tilted ring about world-Y so its node orbits the body (RM holds
        // it at rest). Composed spin·tilt; cheap, one transform write, only when a legendary equips.
        if let auraRing {
            if !reduceMotion {
                auraSpin = (auraSpin + Float(dt) * 1.1).truncatingRemainder(dividingBy: 2 * .pi)
                auraRing.orientation = simd_quatf(angle: auraSpin, axis: SIMD3<Float>(0, 1, 0)) * Self.auraTilt
            } else if auraSpin != 0 {
                auraRing.orientation = Self.auraTilt   // one-time rest-pose restore (RM toggled mid-run)
                auraSpin = 0
            }
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
        camLift = 0
        vxEst = 0; vyEst = 0
        lastPlayerX = 0; lastPlayerY = 0   // runs start at lane centre, grounded
        jumpStretchT = 0; landSquashT = 0
        whip = 0; whipVel = 0
        runPhase = 0
        lastSliding = false; runBobOn = false; speedNorm = 0   // sync-cached flags: advanceVisuals runs before the next sync
        trailDebt = 0; dustDebt = 0; speedLineDebt = 0; sneakerDebt = 0
        ringPulseLife = 0
        ringPulse.isEnabled = false
        shieldBubble.isEnabled = false
        stumbleAura.isEnabled = false
        blastRing.isEnabled = false
        for i in skids.indices { skidLife[i] = 0; skids[i].isEnabled = false }
        // Re-seed decor around 0. Checkpoint starts (distance > 0) self-heal on the first
        // update: the recycle-while loop walks every slot forward and restyles it once.
        decor.reset(distance: 0)
    }

    /// v1.3 skin pipeline: colors + trail tint + rig geometry + idle sway/blink cadence from one
    /// `Skin` recipe. Rebuilds the character rig — called on equip/launch only, NEVER per frame.
    /// Character colors are authored per skin, world-blind AND time-invariant (decree 1, tightened
    /// in v1.8): a character is one identity everywhere and always. Prism's 8 s hue shimmer was
    /// removed on the owner's call — a runner that recolours as it runs makes the roster pointless.
    func applySkin(_ skin: Skin) {
        skinBodyHex = skin.bodyHex
        skinAntennaHex = skin.antennaHex
        skinTrailColor = skin.trailHex.map { uiHex($0) } ?? uiHex(skin.bodyHex)
        skinBodyShape = skin.bodyShape
        skinSpectrum = skin.spectrum
        skinScale = min(max(skin.scale, 0.85), 1.12)   // visual-only cap — never misrepresent the hitbox
        skinEyeRadius = skin.eyeRadius
        skinEyeTintHex = skin.eyeTintHex
        skinPupil = skin.pupilStyle
        skinAntennaHeight = skin.antennaHeightScale
        skinAntennaTip = skin.antennaTipScale
        skinCrest = skin.crest
        skinCrestHex = skin.crestHex
        skinHasAura = skin.hasAura
        skinSway = Float(skin.idle.sway)
        skinSwaySpeed = skin.idle.bobSpeed * 2 * .pi * 0.8   // preview parity — see skinSwaySpeed doc
        skinBlinkMin = skin.idle.blinkMin
        skinBlinkMax = skin.idle.blinkMax
        rebuildCharacter()
        applyCharacterColors()
    }

    /// Paint the rig from the authored skin hexes — on equip/rig rebuild only, never per frame,
    /// never from the world palette, and (since v1.8 / D-009) never from a clock either: the body
    /// is its authored `bodyHex` for the whole run. The antenna — stem AND tip — pins to the
    /// `antennaHex`, exactly what the preview strokes (AUDIT D2-1: the swatch is the purchase
    /// promise — a body-colored stem erased Mono's black spike and Thorn's leaf-green cue),
    /// and never moves hue with anything — world or clock.
    private func applyCharacterColors() {
        playerBody.model?.materials = bodyMaterials()
        let antennaMat = UnlitMaterial(color: uiHex(skinAntennaHex))
        antenna.model?.materials = [antennaMat]
        antennaTip.model?.materials = [antennaMat]
        // Crest pins to the crest hue (antenna, or body if the antenna is too dark) — it reads as
        // part of the character, exactly as the swatch strokes it (decree 2). The aura ring keeps
        // its own trail-hue seed.
        let crestMat = UnlitMaterial(color: uiHex(skinCrestHex))
        for part in crestParts { part.model?.materials = [crestMat] }
    }

    // MARK: scene construction

    private func buildScene() {
        camera.camera.fieldOfViewInDegrees = 62
        camera.position = SIMD3<Float>(0, 5.1, 9.6)
        camera.look(at: SIMD3<Float>(0, 1.3, -5), from: camera.position, relativeTo: nil)
        root.addChild(camera)
        wardenRig.install(into: root)

        // The backdrop wall IS the per-world horizon: the bespoke WorldSky set-pieces (Orbital's
        // planet limb, Solar's sun, Ashfall's volcano…) are tuned to sit right at it. Pushing it back
        // (the v1.6 "longer track" experiment at -95) shoved the track BEHIND those set-pieces, so
        // they floated mid-track and read as broken. Restored to the tuned -65 so every world stays
        // polished — a longer track would need each WorldSky's depth repositioned in lockstep.
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

        // Shield dome: a translucent cyan sphere around the player while a shield is held. Explicit
        // transparent blending (tint alpha alone renders opaque on UnlitMaterial) so the character
        // reads THROUGH the low-opacity dome.
        var domeMat = UnlitMaterial(color: UIColor(red: 0.25, green: 0.95, blue: 1, alpha: 1))
        domeMat.blending = .transparent(opacity: .init(floatLiteral: 0.16))
        shieldBubble = ModelEntity(mesh: .generateSphere(radius: 0.98), materials: [domeMat])
        shieldBubble.isEnabled = false
        root.addChild(shieldBubble)

        // Vulnerability ring (v2.0). A stumble leaves the player ONE contact from death for
        // `Tuning.stumbleRecover`, and that is the only state in the game where an ordinary wall is
        // lethal for a reason the deck does not show. It has to read on the BODY, not only in the
        // HUD, because the body is where the player's eyes already are.
        //
        // **A translucent shell was tried first and is wrong**, verified on the simulator: an unlit
        // 30%-opacity red sphere over a bright character composites to a muddy dark disc that reads
        // as a shadow, not a warning — and it dulls the one thing the player is looking at. An
        // OPAQUE ring at full hazard red cannot do either. It also rhymes with what this game has
        // already taught: a ring around a thing is that thing's state (the Warden's shield halo,
        // the prism gate, the legendary aura).
        stumbleAura = ModelEntity(mesh: ProceduralMesh.torus(major: 1.02, minor: 0.085,
                                                             majorSeg: 24, minorSeg: 6),
                                  materials: [UnlitMaterial(color: uiHex(0xFF3355))])
        stumbleAura.orientation = simd_quatf(angle: .pi / 2, axis: SIMD3<Float>(1, 0, 0))
        stumbleAura.isEnabled = false
        root.addChild(stumbleAura)

        // THE BLAST's front (v2.2). Drawn as a real entity positioned from `snapshot.blastFrontZ`
        // rather than as particles, for one reason: the shockwave IS the rule. Where the ring is
        // drawn is exactly where the core has already destroyed things, so a player can learn the
        // range by watching it. Particles drift with gravity and the world scroll (see
        // `ParticleSystem.step`) and would draw the wave somewhere the sim never put it.
        //
        // Face-on to the track (no x-rotation, unlike `stumbleAura`) so it reads as a wall of force
        // travelling away from you rather than a halo lying on the deck.
        blastRing = ModelEntity(mesh: ProceduralMesh.torus(major: 1.0, minor: 0.10,
                                                           majorSeg: 28, minorSeg: 6),
                                materials: [UnlitMaterial(color: cWardenShield)])
        blastRing.isEnabled = false
        root.addChild(blastRing)

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
        for shoe in shoes { shoe.removeFromParent() }
        shoes.removeAll()
        for part in crestParts { part.removeFromParent() }
        crestParts.removeAll()
        auraRing?.removeFromParent()
        auraRing = nil
        buildCharacter()
    }

    /// Build the character rig from the stored skin params (defaults reproduce the classic Prism
    /// sphere). Eyes keep the same world-space face anchor for every body shape so the existing
    /// blink/squash code needs no per-shape branches. Sizes per DESIGN_characters §1.6, all
    /// derived from `CharacterProportions` — the SAME constants the preview's silhouette math
    /// reads, so swatch and rig proportions agree by construction (AUDIT D2-5). Sphere/cube
    /// reproduce the shipped 0.62 / 1.06 exactly; the crystal gains §4.1's real 3D elongation.
    private func buildCharacter() {
        let bodyMesh: MeshResource
        var bodyY: Float = 0.66
        let bodyR = CharacterProportions.sphereRadius
        switch skinBodyShape {
        case .sphere:
            // A spectral skin gets ONE mesh with a part per band, so the body stays a single
            // ModelEntity (squash, blink and the pose code all address it) and the spectrum is
            // just its material array.
            bodyMesh = skinSpectrum.map {
                ProceduralMesh.bandedSphere(radius: bodyR, bands: $0.count)
            } ?? .generateSphere(radius: bodyR)
        case .cube:
            let edge = bodyR * 2 * CharacterProportions.cubeEdgeRatio
            bodyMesh = .generateBox(width: edge, height: edge, depth: edge,
                                    cornerRadius: edge * CharacterProportions.cubeCornerRatio)
        case .crystal:
            bodyMesh = ProceduralMesh.octahedron(rx: bodyR * CharacterProportions.crystalHalfWidthRatio,
                                                 ry: bodyR * CharacterProportions.crystalHalfHeightRatio,
                                                 rz: bodyR * CharacterProportions.crystalHalfWidthRatio)
            bodyY = 0.72
        }
        // Seed materials from the stored skin hexes (not fixed cyan/magenta) so even the
        // pre-first-`applyCharacterColors` frame shows the equipped identity (AUDIT D2-1).
        let body = ModelEntity(mesh: bodyMesh, materials: bodyMaterials())
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
        let antennaMat = UnlitMaterial(color: uiHex(skinAntennaHex))   // stem + tip: D2-1 seed
        antenna = ModelEntity(mesh: .generateCylinder(height: 0.42 * h, radius: 0.025), materials: [antennaMat])
        antenna.position = SIMD3<Float>(0, antennaCenterY, 0)
        playerRig.addChild(antenna)

        antennaTip = ModelEntity(mesh: .generateSphere(radius: 0.095 * skinAntennaTip), materials: [antennaMat])
        antennaTip.position = SIMD3<Float>(0, antennaTipY, 0)
        playerRig.addChild(antennaTip)

        // Super Sneakers boots: two amber forward-pointing shoes at the feet, hidden until the buff
        // is active (toggled in sync). Procedural box mesh — zero binary assets.
        let shoeMesh = MeshResource.generateBox(width: 0.30, height: 0.18, depth: 0.54, cornerRadius: 0.06)
        let shoeMat = UnlitMaterial(color: uiHex(0xFF8A2B))
        for sx in [Float(-0.30), 0.30] {
            let shoe = ModelEntity(mesh: shoeMesh, materials: [shoeMat])
            shoe.position = SIMD3<Float>(sx, 0.10, 0.22)   // wider + lower + toward the chase camera so they read
            shoe.isEnabled = false
            playerRig.addChild(shoe)
            shoes.append(shoe)
        }
        buildCrest()
        buildAura()
        swayApplied = false   // fresh rig is at rest pose by construction
    }

    /// Cosmetic head crest (v1.6 rarity ladder) — built in the authored antenna hue (recolored by
    /// `applyCharacterColors`) and the SAME taxonomy the swatch draws (decree 2: previews never lie).
    /// Every piece parents to the rig so it rides the body; purely visual (never the hitbox).
    private func buildCrest() {
        guard skinCrest != .none else { return }
        let mat = UnlitMaterial(color: uiHex(skinCrestHex))
        let crestY: Float = skinBodyShape == .crystal ? 1.30 : 1.18

        func spike(_ halfBase: Float, _ height: Float, at p: SIMD3<Float>,
                   lean: Float = 0, flatZ: Float = 1) -> ModelEntity {
            let m = ModelEntity(mesh: ProceduralMesh.pyramid(halfBase: halfBase, height: height),
                                materials: [mat])
            m.position = p
            if lean != 0 { m.orientation = simd_quatf(angle: lean, axis: SIMD3<Float>(0, 0, 1)) }
            if flatZ != 1 { m.scale = SIMD3<Float>(1, 1, flatZ) }
            return m
        }
        func horizontalTorus(_ major: Float, _ minor: Float, at p: SIMD3<Float>) -> ModelEntity {
            let m = ModelEntity(mesh: ProceduralMesh.torus(major: major, minor: minor),
                                materials: [mat])
            m.position = p
            m.orientation = simd_quatf(angle: .pi / 2, axis: SIMD3<Float>(1, 0, 0))   // → horizontal
            return m
        }

        switch skinCrest {
        case .none:
            break
        case .ears:                                            // upright cat ears flanking the antenna
            for s in [Float(-1), 1] {
                crestParts.append(spike(0.11, 0.36, at: SIMD3<Float>(s * 0.26, crestY, 0),
                                        lean: -s * 0.18, flatZ: 0.5))
            }
        case .floppy:                                          // drooping dog/bunny ears at the sides
            for s in [Float(-1), 1] {
                let ear = ModelEntity(mesh: .generateSphere(radius: 0.17), materials: [mat])
                ear.position = SIMD3<Float>(s * 0.52, 0.92, 0)
                ear.scale = SIMD3<Float>(0.7, 1.3, 0.5)
                crestParts.append(ear)
            }
        case .fin:                                             // sawtooth dorsal mohawk, tallest mid
            for (x, h) in [(Float(-0.20), Float(0.24)), (0, 0.42), (0.20, 0.28)] {
                crestParts.append(spike(0.11, h, at: SIMD3<Float>(x, crestY, 0), flatZ: 0.4))
            }
        case .horns:                                           // two horns sweeping up and out
            for s in [Float(-1), 1] {
                crestParts.append(spike(0.10, 0.42, at: SIMD3<Float>(s * 0.22, crestY, 0),
                                        lean: -s * 0.5, flatZ: 0.6))
            }
        case .crown:                                           // a ring of points — royalty
            crestParts.append(horizontalTorus(0.30, 0.045, at: SIMD3<Float>(0, crestY, 0)))
            for i in 0..<5 {
                let ang = Float(i) / 5 * 2 * .pi
                crestParts.append(spike(0.06, 0.18,
                                        at: SIMD3<Float>(cos(ang) * 0.30, crestY + 0.02, sin(ang) * 0.30)))
            }
        case .halo:                                            // a ring floating above the head
            crestParts.append(horizontalTorus(0.34, 0.05, at: SIMD3<Float>(0, crestY + 0.55, 0)))
        }
        for part in crestParts { playerRig.addChild(part) }
    }

    /// Legendary aura (v1.6): a tilted orbit ring in the trail hue with a bright node, spun about Y
    /// in `advanceVisuals`. The unmistakable "this one is special" tell — cosmetic, never an
    /// advantage (characters stay cosmetic by decree). Mirrors the swatch's orbiting aura.
    private func buildAura() {
        guard skinHasAura else { return }
        let ring = ModelEntity(mesh: ProceduralMesh.torus(major: 0.95, minor: 0.05,
                                                          majorSeg: 32, minorSeg: 8),
                               materials: [UnlitMaterial(color: skinTrailColor)])
        ring.position = SIMD3<Float>(0, 0.7, 0)
        ring.orientation = Self.auraTilt
        let node = ModelEntity(mesh: .generateSphere(radius: 0.09), materials: [UnlitMaterial(color: cWhite)])
        node.position = SIMD3<Float>(0.95, 0, 0)   // on the ring (local plane) → orbits as the ring spins
        ring.addChild(node)
        playerRig.addChild(ring)
        auraRing = ring
    }

    /// The aura ring's rest tilt: nearly horizontal (orbit), tipped ~22° toward the chase camera.
    private static let auraTilt = simd_quatf(angle: .pi / 2 - 0.38, axis: SIMD3<Float>(1, 0, 0))

    private func makeEntity(_ kind: EntityKind) -> Entity {
        switch kind {
        case .low:        return boxEntity(1.9, 0.85, 0.9, .magenta)
        case .tall:       return boxEntity(1.9, 3.2, 0.9, .cyan)
        case .movingTall: return boxEntity(1.9, 3.2, 0.9, .magenta)
        case .bar:        return boxEntity(7.6, 0.7, 0.7, .magenta)
        case .hangingBar: return hangingBarEntity()
        // A Warden's aimed shot (v2.3): a spindle stretched down the track so its long axis IS its
        // direction of travel. Deliberately as wide as the wall it collides like (`tall` is 1.9),
        // because a projectile drawn narrower than its hitbox reads as dodgeable when it is not —
        // and it tapers to a point at both ends so it reads as a thrown thing rather than a block.
        case .bolt:
            return ModelEntity(mesh: ProceduralMesh.octahedron(rx: 0.95, ry: 0.95, rz: 1.9),
                               materials: [matWardenHazard])
        case .splitBar:   return splitBarEntity()
        case .gem:        return ModelEntity(mesh: gemMesh, materials: [matGemGold])
        // An actual shield crest, not a ball (owner, S-009). A sphere was the one pickup silhouette
        // in the set that carried no meaning, and it collided with the gems — the other small round
        // bright thing on the deck. See `ProceduralMesh.shieldCrest`.
        case .shield:     return ModelEntity(mesh: shieldMesh, materials: [UnlitMaterial(color: cWhite)])
        case .magnet:     return ModelEntity(mesh: magnetMesh, materials: [UnlitMaterial(color: .cyan)])
        case .doubler:    return ModelEntity(mesh: doublerMesh, materials: [UnlitMaterial(color: uiHex(0x00FF88))])
        case .chrono:     return ModelEntity(mesh: chronoMesh, materials: [UnlitMaterial(color: uiHex(0x9BF0FF))])
        case .superSneakers: return sneakersEntity()
        // Ring/pad get the live accent material reassigned every frame in the place closure
        // (same pattern as obstacles), so the creation-time material is just a safe seed.
        case .ring:       return ModelEntity(mesh: ringMesh, materials: [matAccent])
        case .boostPad:   return ModelEntity(mesh: padMesh, materials: [matAccent])
        case .chasm:      return chasmEntity()
        }
    }

    /// The chasm: a sunken well plus two lit rim bars, under a shared parent.
    ///
    /// **The shaft is NOT black, and that is the whole design.** The first cut painted the interior
    /// near-black (`0x03040A`) on the reasoning that a hole is the absence of light. On the
    /// simulator it vanished: the deck is already black with neon grid lines, so a black well on a
    /// black floor left only the two rim bars visible — and an 8 u gap read as two stripes lying on
    /// the track, which a player would parse as a bar to SLIDE under. Exactly the wrong verb, and
    /// exactly the kind of thing that only shows up by running the game.
    ///
    /// So the walls are a desaturated violet-grey, LIGHTER than the deck. It is the geometry, not
    /// the colour, that has to carry it: four walls receding to a floor is unmistakably a hole,
    /// while any hue would fight twelve different world palettes. Deliberately world-blind for the
    /// same reason gems are fixed gold — the void should look identical everywhere, because the
    /// verb it demands is identical everywhere.
    ///
    /// The rims DO take `accent2`, reassigned each frame by the place closure like every other
    /// obstacle, so the hazard still belongs to its world.
    private func chasmEntity() -> Entity {
        let parent = Entity()
        // The LID is what actually makes the gap read, and it took running the game to learn why.
        // A chase camera this low cannot see into a hole until it is almost on top of it — that is
        // just geometry — so depth cues arrive far too late to react to. What IS visible from 65 m
        // is the deck's neon grid, and the one unmistakable statement available is to INTERRUPT it:
        // an opaque panel sitting just above the grid plane, so the glowing track visibly stops for
        // 8 m. Drawn at y 0.045, above the rungs and lane lines but below the 0.05 boost-pad decal,
        // which is the only other thing living on the deck.
        let lid = ModelEntity(mesh: chasmLidMesh, materials: [UnlitMaterial(color: uiHex(0x07060E))])
        lid.position = SIMD3<Float>(0, 0.045, 0)
        parent.addChild(lid)
        parent.addChild(ModelEntity(mesh: chasmShaftMesh,
                                    materials: [UnlitMaterial(color: uiHex(0x2A2340))]))
        parent.addChild(ModelEntity(mesh: chasmFloorMesh,
                                    materials: [UnlitMaterial(color: uiHex(0x08060F))]))
        for side in [Float(-1), Float(1)] {
            let rim = ModelEntity(mesh: chasmRimMesh, materials: [UnlitMaterial(color: .magenta)])
            rim.position = SIMD3<Float>(0, 0.06, side * Float(Tuning.chasmHalfLength))
            parent.addChild(rim)
        }
        return parent
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

    /// Super Sneakers pickup: an amber upward double-chevron (a "boost up" glyph) built from four
    /// angled box arms under a parent — recognisable as "jump higher", and distinct in shape AND
    /// hue from every cool-toned pickup. Spun around Y each frame by the place closure.
    private func sneakersEntity() -> Entity {
        let parent = Entity()
        let mat = UnlitMaterial(color: uiHex(0xFF8A2B))
        let lean = Float.pi / 5   // 36° — the chevron's half-angle
        for yBase in [Float(-0.13), Float(0.11)] {           // two stacked chevrons → "⌃⌃"
            for side in [Float(-1), Float(1)] {
                let arm = ModelEntity(mesh: sneakerArmMesh, materials: [mat])
                arm.position = SIMD3<Float>(side * 0.13, yBase, 0)
                arm.orientation = simd_quatf(angle: -side * lean, axis: SIMD3<Float>(0, 0, 1))
                parent.addChild(arm)
            }
        }
        return parent
    }

    /// The body's material array: one flat `UnlitMaterial` per spectrum band (matching the parts
    /// `bandedSphere` emitted), or a single authored body hex for every other skin. Never reads the
    /// world palette and never reads a clock — decree 1 in space and in time.
    private func bodyMaterials() -> [UnlitMaterial] {
        guard let spectrum = skinSpectrum, skinBodyShape == .sphere else {
            return [UnlitMaterial(color: uiHex(skinBodyHex))]
        }
        return spectrum.map { UnlitMaterial(color: uiHex($0)) }
    }

    /// The hanging bar: a **portcullis, not a slab** (v2.3).
    ///
    /// It shipped in v2.2 as one solid `7.6 × 3.05 × 0.7` box in saturated red, and that is the
    /// thing the owner hit first: *"the wall it created that i had to crouch under was blocking the
    /// view of everything"*. He is describing an occluder, and the arithmetic agrees — a full-span
    /// box standing from the kill line (0.95) to well above any reachable apex (4.0) is 23.2 u² of
    /// opaque frontal area sitting between the camera and every metre of track behind it. There is
    /// nothing to see past it, so the deck the player is about to land on is unreadable until it
    /// clears.
    ///
    /// This builds the same volume out of a frame instead of a fill: a bright HEM at the kill line,
    /// a top header, one mid rail, and seven verticals. Frontal area drops 23.2 → 11.6 u², so
    /// **half the occlusion is gone**, and what is left is a grille the eye reads through.
    ///
    /// Three things it deliberately does NOT do:
    ///
    /// - **It does not change the rule.** `Collisions.hangingBarHit` is untouched; the band is still
    ///   0.95 → 4.0 and still unjumpable from every state including Super Sneakers. The mesh still
    ///   spans exactly its kill band edge to edge, so decree 2 holds — what is drawn is what kills.
    /// - **It does not open a hole anyone could believe in.** Seven verticals leave gaps 0.79 u
    ///   wide against a body 1.0 u across, and the mid rail halves them vertically. Every opening is
    ///   visibly smaller than the player, so "grille" never reads as "gap".
    /// - **It does not bury the answer.** The hem is the brightest element and sits ON the kill line,
    ///   because the single fact the player must extract in one frame is *where the bottom edge is* —
    ///   everything above it is context.
    private func hangingBarEntity() -> Entity {
        let group = Entity()
        let bottom = Float(Tuning.hangingBarKillBottom)     // 0.95
        let top = Float(Tuning.hangingBarKillTop)           // 4.0
        let w: Float = 7.6
        // Local Y is relative to the entity origin, which the core parks at the band's CENTRE
        // (`applyThrown`/`apply` set `baseY` to the midpoint), so every piece is placed as an
        // offset from that midpoint rather than in world space.
        let mid = (bottom + top) / 2
        func place(_ e: ModelEntity, y: Float, x: Float = 0) {
            e.position = SIMD3<Float>(x, y - mid, 0)
            group.addChild(e)
        }
        // The hem — the read. Thick, bright, and its underside IS the kill line.
        let hemH: Float = 0.55
        place(boxEntity(w, hemH, 0.75, cWardenHazard), y: bottom + hemH / 2)
        // Header, capping the band so it reads as a closed structure rather than an open top.
        let headH: Float = 0.30
        place(boxEntity(w, headH, 0.55, cWardenHazardDark), y: top - headH / 2)
        // Mid rail: halves every opening so none of them is body-sized.
        let railY = (bottom + hemH + top - headH) / 2
        place(boxEntity(w, 0.20, 0.55, cWardenHazardDark), y: railY)
        // Seven verticals spanning hem-top to header-bottom.
        let barsTop = top - headH, barsBottom = bottom + hemH
        let slatH = barsTop - barsBottom
        let n = 7
        for i in 0..<n {
            let t = Float(i) / Float(n - 1)                  // 0…1 across the span
            let x = -w / 2 + 0.13 + t * (w - 0.26)
            place(boxEntity(0.26, slatH, 0.5, cWardenHazardDark),
                  y: barsBottom + slatH / 2, x: x)
        }
        return group
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

    /// Transient FOV punch. The default is what every existing call site used, so parameterising it
    /// changes nothing that already shipped; loud one-off beats (a stumble, a Warden arrival) ask
    /// for more. Decay is 12°/s, so +5° lasts ~0.42 s.
    private func kickFOV(_ degrees: Float = 3) {
        if !reduceMotion { fovKick = max(fovKick, degrees) }
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
        // Evolve by ABSOLUTE ordinal so deep cycles diverge (v1.4.3). fromOrdinal = ordinal − 1
        // (worlds step one at a time); at blend == 1 the `from` half contributes nothing.
        let a = Theme.evolvedPalette(ordinal: max(0, snap.worldOrdinal - 1))
        let b = Theme.evolvedPalette(ordinal: snap.worldOrdinal)
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
