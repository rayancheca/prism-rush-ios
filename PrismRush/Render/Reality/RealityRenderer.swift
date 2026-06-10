import SwiftUI
import RealityKit
import simd
import UIKit

/// RealityKit adapter implementing `RendererPort`. Owns the whole virtual scene under `root`
/// (camera, backdrop, ground, scrolling grid, player rig) and maps each snapshot to entities via
/// `EntityPools`. Phase 3 is gray-box: untextured `UnlitMaterial` primitives in the World-1 palette.
/// (World crossfade, decor, character face and particles arrive in Phases 4–5.)
@MainActor
final class RealityRenderer: RendererPort {
    let root = Entity()

    private let camera = PerspectiveCamera()
    private let playerRig = Entity()
    private var rungs: [Entity] = []
    private var pools: EntityPools!

    // Fixed World-1 palette colors (Phase 3).
    private let cAccent  = UIColor(red: 0,        green: 245/255.0, blue: 1,         alpha: 1) // #00F5FF
    private let cAccent2 = UIColor(red: 1,        green: 43/255.0,  blue: 214/255.0, alpha: 1) // #FF2BD6
    private let cGrid    = UIColor(red: 1,        green: 43/255.0,  blue: 214/255.0, alpha: 1)
    private let cGold    = UIColor(red: 1,        green: 210/255.0, blue: 61/255.0,  alpha: 1) // #FFD23D
    private let cWhite   = UIColor.white
    private let cBg      = UIColor(red: 7/255.0,  green: 2/255.0,   blue: 26/255.0,  alpha: 1) // #07021A

    private let rungSpacing: Float = 4
    private let rungCount = 36

    // Code-generated meshes, built once and shared across all instances of their kind.
    private let gemMesh: MeshResource
    private let magnetMesh: MeshResource

    init() {
        gemMesh = ProceduralMesh.octahedron(0.34)
        magnetMesh = ProceduralMesh.torus(major: 0.30, minor: 0.12)
        buildScene()
        pools = EntityPools(root: root) { [weak self] kind in
            self?.makeEntity(kind) ?? ModelEntity()
        }
    }

    func install(into content: RealityViewCameraContent) {
        content.add(root)
    }

    // MARK: RendererPort

    func sync(_ snap: GameSnapshot) {
        let px = Float(snap.playerX)

        // Camera: follow with a touch of look-ahead, FOV opens with speed.
        camera.camera.fieldOfViewInDegrees = 62 + Float(clampD((snap.speed - 7) / 27, 0, 1)) * 9
        var cp = camera.position
        cp.x += (px * 0.42 - cp.x) * 0.15
        cp.y = 5.1
        cp.z = 9.6
        camera.position = cp
        camera.look(at: SIMD3<Float>(px * 0.3, 1.3, -5), from: cp, relativeTo: nil)

        // Player rig: lane/jump position, squash-&-stretch, lane bank. Hidden on death.
        playerRig.isEnabled = snap.mode != .over
        playerRig.position = SIMD3<Float>(px, Float(snap.playerY), 0)
        let sy = Float(snap.playerScaleY)
        let sx = 1 + (1 - sy) * 0.45
        playerRig.scale = SIMD3<Float>(sx, sy, sx)
        playerRig.orientation = simd_quatf(angle: Float(snap.bankZ), axis: SIMD3<Float>(0, 0, 1))

        // Scroll the grid rungs toward the camera.
        let off = Float(snap.distance.truncatingRemainder(dividingBy: Double(rungSpacing)))
        for (i, r) in rungs.enumerated() {
            r.position.z = off + 10 - Float(i) * rungSpacing
        }

        // Spawned entities.
        pools.sync(snap.entities) { entity, s in
            entity.position = SIMD3<Float>(Float(s.x), Float(s.y), Float(s.z))
            if s.kind == .gem || s.kind == .shield || s.kind == .magnet {
                entity.orientation = simd_quatf(angle: Float(s.spin) * 0.9, axis: SIMD3<Float>(0, 1, 0))
            }
        }
    }

    func fire(_ event: FXEvent) {
        // Particles, screen shake, popups and haptics arrive in Phase 5.
    }

    /// Clear all pooled entities (called when a run restarts).
    func resetEntities() { pools.releaseAll() }

    // MARK: scene construction

    private func buildScene() {
        camera.camera.fieldOfViewInDegrees = 62
        camera.position = SIMD3<Float>(0, 5.1, 9.6)
        camera.look(at: SIMD3<Float>(0, 1.3, -5), from: camera.position, relativeTo: nil)
        root.addChild(camera)

        let backdrop = ModelEntity(mesh: .generatePlane(width: 140, height: 90), materials: [UnlitMaterial(color: cBg)])
        backdrop.position = SIMD3<Float>(0, 12, -65)
        root.addChild(backdrop)

        let ground = ModelEntity(mesh: .generatePlane(width: 16, depth: 260), materials: [UnlitMaterial(color: UIColor(white: 0.02, alpha: 1))])
        ground.position = SIMD3<Float>(0, -0.02, -110)
        root.addChild(ground)

        // Lane edges (±3.3) and dividers (±1.1).
        for x in [Float(-3.3), -1.1, 1.1, 3.3] {
            let line = ModelEntity(mesh: .generateBox(width: 0.06, height: 0.02, depth: 260), materials: [UnlitMaterial(color: cGrid)])
            line.position = SIMD3<Float>(x, 0, -110)
            root.addChild(line)
        }

        // Scrolling rungs (motion read).
        for _ in 0..<rungCount {
            let r = ModelEntity(mesh: .generateBox(width: 9, height: 0.04, depth: 0.14), materials: [UnlitMaterial(color: cGrid)])
            root.addChild(r)
            rungs.append(r)
        }

        let body = ModelEntity(mesh: .generateSphere(radius: 0.62), materials: [UnlitMaterial(color: cAccent)])
        body.position = SIMD3<Float>(0, 0.66, 0)
        playerRig.addChild(body)
        root.addChild(playerRig)
    }

    private func makeEntity(_ kind: EntityKind) -> Entity {
        switch kind {
        case .low:        return boxEntity(1.9, 0.85, 0.9, cAccent2)
        case .tall:       return boxEntity(1.9, 3.2, 0.9, cAccent)
        case .movingTall: return boxEntity(1.9, 3.2, 0.9, cAccent2)   // danger tint
        case .bar:
            let g = Entity()
            let crossbar = boxEntity(7.6, 0.7, 0.7, cAccent2)
            crossbar.position = SIMD3<Float>(0, 1.3, 0)
            g.addChild(crossbar)
            return g
        case .gem:    return ModelEntity(mesh: gemMesh, materials: [UnlitMaterial(color: cGold)])
        case .shield: return sphereEntity(0.42, cWhite)
        case .magnet: return ModelEntity(mesh: magnetMesh, materials: [UnlitMaterial(color: cAccent)])
        }
    }

    private func boxEntity(_ w: Float, _ h: Float, _ d: Float, _ c: UIColor) -> ModelEntity {
        ModelEntity(mesh: .generateBox(width: w, height: h, depth: d, cornerRadius: 0.04), materials: [UnlitMaterial(color: c)])
    }

    private func sphereEntity(_ r: Float, _ c: UIColor) -> ModelEntity {
        ModelEntity(mesh: .generateSphere(radius: r), materials: [UnlitMaterial(color: c)])
    }
}
