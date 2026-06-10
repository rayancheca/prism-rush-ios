import RealityKit
import simd
import UIKit

/// Side-of-track scenery that defines each world's silhouette: emissive towers (Metropolis),
/// floating crystals (Caverns), pyramids (Sands). Slots scroll toward the camera and, when they
/// pass behind it, jump back to the horizon **re-styled for the current world** — so a new world's
/// decor visibly arrives toward the player rather than popping in around them.
@MainActor
final class WorldDecor {
    @MainActor private final class Slot {
        let group = Entity()
        let tower: ModelEntity
        let crystal: ModelEntity
        let pyramid: ModelEntity
        var d: Float
        let side: Float
        var floating = false
        var baseY: Float = 0
        var bob: Float
        init(tower: ModelEntity, crystal: ModelEntity, pyramid: ModelEntity, d: Float, side: Float, bob: Float) {
            self.tower = tower; self.crystal = crystal; self.pyramid = pyramid
            self.d = d; self.side = side; self.bob = bob
            group.addChild(tower); group.addChild(crystal); group.addChild(pyramid)
        }
    }

    private let count = 14
    private let gap: Float = 13
    private var span: Float { Float(count) * gap }
    private var slots: [Slot] = []

    private let towerMesh: MeshResource
    private let crystalMesh: MeshResource
    private let pyramidMesh: MeshResource

    init(root: Entity) {
        towerMesh = .generateBox(width: 2.4, height: 6, depth: 2.4, cornerRadius: 0.05)
        crystalMesh = .generateCone(height: 5, radius: 1.2)
        pyramidMesh = ProceduralMesh.pyramid(halfBase: 1.9, height: 4)

        for i in 0..<count {
            for side in [Float(-1), 1] {
                let s = Slot(
                    tower: ModelEntity(mesh: towerMesh, materials: [UnlitMaterial(color: .magenta)]),
                    crystal: ModelEntity(mesh: crystalMesh, materials: [UnlitMaterial(color: .magenta)]),
                    pyramid: ModelEntity(mesh: pyramidMesh, materials: [UnlitMaterial(color: .magenta)]),
                    d: Float(i) * gap,
                    side: side,
                    bob: Float.random(in: 0...6.28)
                )
                style(s, world: 0)
                root.addChild(s.group)
                slots.append(s)
            }
        }
    }

    func update(distance: Double, world: Int, elapsed: Double) {
        let dist = Float(distance)
        for s in slots {
            var z = dist - s.d
            if z > 14 {                      // passed behind the camera → recycle at the horizon
                s.d += span
                style(s, world: world)
                z = dist - s.d
            }
            s.group.position.z = z
            if s.floating {
                s.crystal.position.y = s.baseY + sin(Float(elapsed) + s.bob) * 0.35
            }
        }
    }

    /// Re-skin a slot for `world`: pick the silhouette, randomize size/placement, dim the tint so
    /// decor reads as background rather than competing with obstacles.
    private func style(_ s: Slot, world: Int) {
        let w = world % 3
        s.tower.isEnabled = (w == 0)
        s.crystal.isEnabled = (w == 1)
        s.pyramid.isEnabled = (w == 2)
        s.floating = false

        let x = s.side * Float.random(in: 6.6...11.5)
        s.group.position.x = x
        let tint = Self.dim(Theme.worlds[w].accent2)

        switch w {
        case 0:
            let h = Float.random(in: 3.5...13)
            s.tower.scale = SIMD3<Float>(Float.random(in: 0.7...1.3), h / 6, Float.random(in: 0.7...1.3))
            s.tower.position.y = h / 2
            s.tower.model?.materials = [UnlitMaterial(color: tint)]
        case 1:
            let h = Float.random(in: 2.5...7)
            s.crystal.scale = SIMD3<Float>(Float.random(in: 0.7...1.4), h / 5, Float.random(in: 0.7...1.4))
            s.crystal.orientation = simd_quatf(angle: Float.random(in: -0.25...0.25), axis: SIMD3<Float>(0, 0, 1))
            s.floating = Float.random(in: 0...1) < 0.4
            s.baseY = s.floating ? Float.random(in: 2.5...5) : h / 2
            s.crystal.position.y = s.baseY
            s.crystal.model?.materials = [UnlitMaterial(color: tint)]
        default:
            let h = Float.random(in: 2...6.5)
            s.pyramid.scale = SIMD3<Float>(Float.random(in: 0.8...1.6), h / 4, Float.random(in: 0.8...1.6))
            s.pyramid.orientation = simd_quatf(angle: Float.random(in: 0...1), axis: SIMD3<Float>(0, 1, 0))
            s.pyramid.position.y = 0
            s.pyramid.model?.materials = [UnlitMaterial(color: tint)]
        }
    }

    private static func dim(_ v: SIMD3<Float>) -> UIColor {
        UIColor(red: CGFloat(v.x) * 0.6, green: CGFloat(v.y) * 0.6, blue: CGFloat(v.z) * 0.6, alpha: 1)
    }
}
