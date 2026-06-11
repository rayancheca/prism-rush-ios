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

    // Selected character skin (`followsWorld` = the default look that tracks the world accent).
    private var skinBodyHex: UInt32 = 0
    private var skinAntennaHex: UInt32 = 0
    private var skinFollowsWorld = true

    private var elapsed: Double = 0
    private var blinkT: Double = 3
    private var shake: Float = 0
    private var fovKick: Float = 0          // transient FOV punch (pickup / world change), decays like shake
    private var chronoDip: Float = 0        // smoothed −6° FOV dip while chrono slow-mo is active
    private var slideRoll: Float = 0        // smoothed camera z-roll while sliding
    private var lastSpeed: Float = 0
    private var lastDt: Float = 1 / 60      // wall-clock dt from advanceVisuals (runs before sync)
    private var camX: Float = 0

    // Reduce Motion gates shake, the FOV speed-punch/kicks, the slide roll, and speed lines.
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
        matGemGold = UnlitMaterial(color: UIColor(red: 1, green: 210/255.0, blue: 61/255.0, alpha: 1))
        matGemHot = UnlitMaterial(color: UIColor(red: 1, green: 0.95, blue: 0.75, alpha: 1))
        buildScene()
        pools = EntityPools(root: root) { [weak self] kind in
            self?.makeEntity(kind) ?? ModelEntity()
        }
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
        let speedPunch: Float = reduceMotion ? 0 : Float(clampD((snap.speed - 7) / 27, 0, 1)) * 9
        // Chrono slow-mo: ease toward a −6° dip while the timer runs (snap.speed is already the
        // chrono-scaled EFFECTIVE speed, so the speed punch above relaxes with it for free).
        let dipTarget: Float = (!reduceMotion && snap.chronoRemaining > 0 && snap.mode == .play) ? -6 : 0
        chronoDip += (dipTarget - chronoDip) * 0.08
        camera.camera.fieldOfViewInDegrees = 62 + speedPunch + fovKick + chronoDip
        camX += (px * 0.42 - camX) * 0.15
        let shaking = !reduceMotion && shake > 0
        let shakeX = shaking ? Float.random(in: -1...1) * shake * 0.55 : 0
        let shakeY = shaking ? Float.random(in: -1...1) * shake * 0.55 : 0
        let cp = SIMD3<Float>(camX + shakeX, 5.1 + shakeY, 9.6)
        camera.position = cp
        camera.look(at: SIMD3<Float>(px * 0.3, 1.3, -5), from: cp, relativeTo: nil)
        // Slight z-roll folded into the look-at while sliding (smoothed both ways).
        let rollTarget: Float = (!reduceMotion && snap.sliding && snap.mode == .play) ? -0.04 : 0
        slideRoll += (rollTarget - slideRoll) * 0.2
        if abs(slideRoll) > 0.0005 {
            camera.orientation = simd_quatf(angle: slideRoll, axis: SIMD3<Float>(0, 0, 1)) * camera.orientation
        }
        if shaking {   // a touch of rotational roll makes impacts read far harder than position alone
            let roll = Float.random(in: -1...1) * shake * 0.012
            camera.orientation = simd_quatf(angle: roll, axis: SIMD3<Float>(0, 0, 1)) * camera.orientation
        }

        // Player rig: lane/jump pose, squash-&-stretch, bank, plus a pronounced forward-lean slide.
        playerRig.isEnabled = snap.mode != .over
        playerRig.position = SIMD3<Float>(px, Float(snap.playerY), 0)
        let sy = Float(snap.playerScaleY)
        var sx = 1 + (1 - sy) * 0.45
        if snap.sliding { sx *= 1.55 }                       // flatten dramatically into a pancake
        playerRig.scale = SIMD3<Float>(sx, sy, sx)
        let bankQ = simd_quatf(angle: Float(snap.bankZ), axis: SIMD3<Float>(0, 0, 1))
        let leanQ = simd_quatf(angle: snap.sliding ? -0.85 : 0, axis: SIMD3<Float>(1, 0, 0))
        playerRig.orientation = bankQ * leanQ

        // Dust kicked up during a slide — grounded OR mid air-slam — so it's unmistakable.
        // Time-based (≈ the old 6/frame at 60 Hz) so density matches at 120 Hz.
        if snap.mode == .play, snap.sliding {
            dustDebt += 360 * lastDt
            let n = Int(dustDebt)
            if n > 0 {
                dustDebt -= Float(n)
                particles.burst(x: px + Float.random(in: -0.4...0.4), y: 0.12, z: 0.5,
                                color: tintAccent, count: n, power: 1.8, spread: 0.18, life: 0.45)
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
            }
        }

        // Speed trail behind the player — time-based (≈ the old 3/frame at 60 Hz). The emission
        // rate breathes with chrono slow-mo so the trail thins while the world crawls.
        if snap.mode == .play {
            trailDebt += 180 * (snap.chronoRemaining > 0 ? Float(Tuning.chronoFactor) : 1) * lastDt
            let n = Int(trailDebt)
            if n > 0 {
                trailDebt -= Float(n)
                particles.burst(x: px + Float.random(in: -0.2...0.2), y: 0.25 + Float(snap.playerY), z: 0.5,
                                color: tintAccent, count: n, power: 0.9, spread: 0.08, life: 0.45)
            }
        }

        // Speed lines above ~26 m/s: thin streaks at the screen edges rushing past the camera.
        if snap.mode == .play, !reduceMotion, lastSpeed > 26 {
            speedLineDebt += min(70, (lastSpeed - 26) * 6) * lastDt
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
        case let .landed(x):
            particles.burst(x: Float(x), y: 0.1, z: 0.2, color: tintAccent, count: 10, power: 2.6, spread: 0.32, life: 0.4)
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
            particles.burst(x: Float(x), y: 1, z: 0, color: tintAccent2, count: 120, power: 7.5, spread: 0.55, life: 1.2)
            particles.burst(x: Float(x), y: 1, z: 0, color: cWhite, count: 60, power: 9.5, spread: 0.35, life: 0.9)
            shake = 1.4
        case let .worldChanged(index, _):
            // One-shot horizon ring sweep in the incoming world's accent (banner is UI-side).
            let a = Theme.worlds[index % 3].accent
            let accent = UIColor(red: CGFloat(a.x), green: CGFloat(a.y), blue: CGFloat(a.z), alpha: 1)
            particles.ring(y: 4.5, z: -42, radius: 9, color: accent, count: 24, velZ: 26, life: 1.1)
            kickFOV()
        case .jumped, .laneChanged, .nearMiss, .chronoEnded:
            break   // popups / banner / haptics / audio handled by the UI layer
        }
    }

    /// Time-based animation (blink, particles, skids, shake/FOV decay) — driven by the loop's
    /// wall-clock dt (runs immediately before `sync` each frame).
    func advanceVisuals(_ dt: Double) {
        elapsed += dt
        lastDt = Float(dt)
        blinkT -= dt
        if blinkT < -0.12 { blinkT = Double.random(in: 2.2...4.2) }
        let blink: Float = blinkT < 0 ? 0.1 : 1
        for eye in eyes { eye.scale = SIMD3<Float>(1, blink, 1) }
        particles.step(Float(dt), speed: lastSpeed)
        stepSkids(Float(dt))
        if shake > 0 { shake = max(0, shake - Float(dt) * 2.2) }
        if fovKick > 0 { fovKick = max(0, fovKick - Float(dt) * 12) }   // +3° decays over ~0.25 s
    }

    func resetEntities() {
        pools.releaseAll()
        particles.reset()
        shake = 0
        fovKick = 0
        chronoDip = 0
        slideRoll = 0
        trailDebt = 0; dustDebt = 0; speedLineDebt = 0
        for i in skids.indices { skidLife[i] = 0; skids[i].isEnabled = false }
        // Re-seed decor around 0. Checkpoint starts (distance > 0) self-heal on the first
        // update: the recycle-while loop walks every slot forward and restyles it once.
        decor.reset(distance: 0)
    }

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

        buildCharacter()
    }

    private func buildCharacter() {
        let body = ModelEntity(mesh: .generateSphere(radius: 0.62), materials: [UnlitMaterial(color: .cyan)])
        body.position = SIMD3<Float>(0, 0.66, 0)
        playerRig.addChild(body)
        playerBody = body

        // Eyes face the chase camera (+Z) with a dark pupil child, so the face reads clearly.
        for ex in [Float(-0.22), 0.22] {
            let eye = ModelEntity(mesh: .generateSphere(radius: 0.13), materials: [UnlitMaterial(color: cWhite)])
            eye.position = SIMD3<Float>(ex, 0.82, 0.52)
            let pupil = ModelEntity(mesh: .generateSphere(radius: 0.06), materials: [UnlitMaterial(color: UIColor(white: 0.02, alpha: 1))])
            pupil.position = SIMD3<Float>(0, 0, 0.1)
            eye.addChild(pupil)
            playerRig.addChild(eye)
            eyes.append(eye)
        }

        antenna = ModelEntity(mesh: .generateCylinder(height: 0.42, radius: 0.025), materials: [UnlitMaterial(color: .cyan)])
        antenna.position = SIMD3<Float>(0, 1.42, 0)
        playerRig.addChild(antenna)

        antennaTip = ModelEntity(mesh: .generateSphere(radius: 0.095), materials: [UnlitMaterial(color: .magenta)])
        antennaTip.position = SIMD3<Float>(0, 1.66, 0)
        playerRig.addChild(antennaTip)
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
