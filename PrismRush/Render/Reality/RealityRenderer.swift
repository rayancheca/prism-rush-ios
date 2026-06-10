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

    // Selected character skin (`followsWorld` = the default look that tracks the world accent).
    private var skinBodyHex: UInt32 = 0
    private var skinAntennaHex: UInt32 = 0
    private var skinFollowsWorld = true

    private var elapsed: Double = 0
    private var blinkT: Double = 3
    private var shake: Float = 0
    private var lastSpeed: Float = 0
    private var camX: Float = 0
    private let reduceMotion = UIAccessibility.isReduceMotionEnabled

    private var particles: ParticleSystem!

    // Latest blended obstacle tints, captured each frame for the pools' place closure.
    private var tintAccent = UIColor.cyan
    private var tintAccent2 = UIColor.magenta

    init() {
        gemMesh = ProceduralMesh.octahedron(0.34)
        magnetMesh = ProceduralMesh.torus(major: 0.30, minor: 0.12)
        buildScene()
        pools = EntityPools(root: root) { [weak self] kind in
            self?.makeEntity(kind) ?? ModelEntity()
        }
        decor = WorldDecor(root: root)
        particles = ParticleSystem(parent: root)
    }

    func install(into content: RealityViewCameraContent) {
        content.add(root)
    }

    // MARK: RendererPort

    func sync(_ snap: GameSnapshot) {
        let pal = Palette(snap)
        tintAccent = pal.accent
        tintAccent2 = pal.accent2

        // Backdrop + grid + character recolor (crossfade + selected skin).
        let bodyColor = skinFollowsWorld ? pal.accent : uiHex(skinBodyHex)
        let antennaColor = skinFollowsWorld ? pal.accent2 : uiHex(skinAntennaHex)
        setColor(backdrop, pal.bg)
        for r in rungs { setColor(r, pal.grid) }
        for l in laneLines { setColor(l, pal.grid) }
        setColor(playerBody, bodyColor)
        setColor(antenna, bodyColor)
        setColor(antennaTip, antennaColor)

        // Camera follow + speed FOV + decaying screen shake (kept off the follow position so it
        // doesn't bleed into the lerp; Reduce Motion disables it).
        let px = Float(snap.playerX)
        lastSpeed = Float(snap.speed)
        camera.camera.fieldOfViewInDegrees = 62 + Float(clampD((snap.speed - 7) / 27, 0, 1)) * 9
        camX += (px * 0.42 - camX) * 0.15
        let shakeX = (!reduceMotion && shake > 0) ? Float.random(in: -1...1) * shake * 0.3 : 0
        let shakeY = (!reduceMotion && shake > 0) ? Float.random(in: -1...1) * shake * 0.3 : 0
        let cp = SIMD3<Float>(camX + shakeX, 5.1 + shakeY, 9.6)
        camera.position = cp
        camera.look(at: SIMD3<Float>(px * 0.3, 1.3, -5), from: cp, relativeTo: nil)

        // Player rig: lane/jump pose, squash-&-stretch, bank, plus a pronounced forward-lean slide.
        playerRig.isEnabled = snap.mode != .over
        playerRig.position = SIMD3<Float>(px, Float(snap.playerY), 0)
        let sy = Float(snap.playerScaleY)
        var sx = 1 + (1 - sy) * 0.45
        if snap.sliding { sx *= 1.35 }                       // flatten wider into a pancake
        playerRig.scale = SIMD3<Float>(sx, sy, sx)
        let bankQ = simd_quatf(angle: Float(snap.bankZ), axis: SIMD3<Float>(0, 0, 1))
        let leanQ = simd_quatf(angle: snap.sliding ? -0.6 : 0, axis: SIMD3<Float>(1, 0, 0))
        playerRig.orientation = bankQ * leanQ

        // Ground dust kicked up during a slide so it's unmistakable.
        if snap.mode == .play, snap.sliding, snap.grounded {
            particles.burst(x: px + Float.random(in: -0.35...0.35), y: 0.12, z: 0.45,
                            color: tintAccent, count: 3, power: 1.6, spread: 0.12, life: 0.32)
        }

        // Grid scroll.
        let off = Float(snap.distance.truncatingRemainder(dividingBy: Double(rungSpacing)))
        for (i, r) in rungs.enumerated() { r.position.z = off + 10 - Float(i) * rungSpacing }

        // Spawned entities.
        let accent = tintAccent, accent2 = tintAccent2
        pools.sync(snap.entities) { entity, s in
            let y: Float = (s.kind == .bar) ? 1.3 : Float(s.y)
            entity.position = SIMD3<Float>(Float(s.x), y, Float(s.z))
            switch s.kind {
            case .tall:
                (entity as? ModelEntity).map { $0.model?.materials = [UnlitMaterial(color: accent)] }
            case .low, .bar, .movingTall:
                (entity as? ModelEntity).map { $0.model?.materials = [UnlitMaterial(color: accent2)] }
            case .gem, .shield, .magnet:
                entity.orientation = simd_quatf(angle: Float(s.spin) * 0.9, axis: SIMD3<Float>(0, 1, 0))
            }
        }

        // Speed trail behind the player.
        if snap.mode == .play {
            particles.burst(x: px + Float.random(in: -0.2...0.2), y: 0.25 + Float(snap.playerY), z: 0.5,
                            color: tintAccent, count: 2, power: 0.8, spread: 0.08, life: 0.4)
        }

        // Per-world decor.
        decor.update(distance: snap.distance, world: snap.worldTo, elapsed: elapsed)
    }

    func fire(_ event: FXEvent) {
        switch event {
        case let .gemCollected(x, y, _):
            particles.burst(x: Float(x), y: Float(y), z: 0, color: cGold, count: 7, power: 3, spread: 0.15, life: 0.45)
        case let .landed(x):
            particles.burst(x: Float(x), y: 0.1, z: 0.2, color: tintAccent, count: 8, power: 2.5, spread: 0.3, life: 0.35)
        case let .pickup(kind, x, y):
            particles.burst(x: Float(x), y: Float(y), z: 0, color: kind == .shield ? cWhite : tintAccent, count: 24, power: 4.5, spread: 0.3, life: 0.6)
        case let .shieldAbsorbed(x):
            particles.burst(x: Float(x), y: 1.2, z: 0, color: cWhite, count: 30, power: 6, spread: 0.4, life: 0.6)
            shake = max(shake, 0.5)
        case let .died(x):
            particles.burst(x: Float(x), y: 1, z: 0, color: tintAccent2, count: 70, power: 7, spread: 0.5, life: 0.9)
            particles.burst(x: Float(x), y: 1, z: 0, color: cWhite, count: 40, power: 9, spread: 0.3, life: 0.7)
            shake = 1
        case .jumped, .slid, .laneChanged, .nearMiss, .worldChanged:
            break   // popups / banner / haptics handled by the UI layer
        }
    }

    /// Time-based animation (blink, particles, shake decay) — driven by the loop's wall-clock dt.
    func advanceVisuals(_ dt: Double) {
        elapsed += dt
        blinkT -= dt
        if blinkT < -0.12 { blinkT = Double.random(in: 2.2...4.2) }
        let blink: Float = blinkT < 0 ? 0.1 : 1
        for eye in eyes { eye.scale = SIMD3<Float>(1, blink, 1) }
        particles.step(Float(dt), speed: lastSpeed)
        if shake > 0 { shake = max(0, shake - Float(dt) * 2.2) }
    }

    func resetEntities() {
        pools.releaseAll()
        particles.reset()
        shake = 0
    }

    func applySkin(bodyHex: UInt32, antennaHex: UInt32, followsWorld: Bool) {
        skinBodyHex = bodyHex
        skinAntennaHex = antennaHex
        skinFollowsWorld = followsWorld
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
        case .gem:        return ModelEntity(mesh: gemMesh, materials: [UnlitMaterial(color: cGold)])
        case .shield:     return sphereEntity(0.42, cWhite)
        case .magnet:     return ModelEntity(mesh: magnetMesh, materials: [UnlitMaterial(color: .cyan)])
        }
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

    private func setColor(_ e: ModelEntity?, _ c: UIColor) { e?.model?.materials = [UnlitMaterial(color: c)] }
}

/// The current crossfaded world palette as `UIColor`s.
private struct Palette {
    let bg, grid, accent, accent2: UIColor
    init(_ snap: GameSnapshot) {
        let a = Theme.worlds[snap.worldFrom % 3]
        let b = Theme.worlds[snap.worldTo % 3]
        let t = Float(snap.worldBlend)
        func ui(_ v: SIMD3<Float>) -> UIColor {
            UIColor(red: CGFloat(v.x), green: CGFloat(v.y), blue: CGFloat(v.z), alpha: 1)
        }
        bg = ui(Theme.mix(a.bg, b.bg, t))
        grid = ui(Theme.mix(a.grid, b.grid, t))
        accent = ui(Theme.mix(a.accent, b.accent, t))
        accent2 = ui(Theme.mix(a.accent2, b.accent2, t))
    }
}
