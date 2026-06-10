import RealityKit
import simd
import UIKit

/// Side-of-track scenery that defines each world's silhouette: emissive towers (Metropolis),
/// floating crystals (Caverns), pyramids (Sands) — plus a rarer alternate per world (stacked
/// spire / stalagmite cluster / obelisk) for variety. Slots scroll toward the camera and, when
/// they pass behind it, jump back to the horizon **re-styled for the current world** — so a new
/// world's decor visibly arrives toward the player rather than popping in around them.
@MainActor
final class WorldDecor {
    @MainActor private final class Slot {
        let group = Entity()
        let tower: ModelEntity
        let crystal: ModelEntity
        let pyramid: ModelEntity
        let altA: ModelEntity       // alternate silhouette parts (mesh swapped at restyle)
        let altB: ModelEntity
        var d: Float
        let side: Float
        var floating = false
        var baseY: Float = 0
        var bob: Float
        var needsRestyle = false
        init(tower: ModelEntity, crystal: ModelEntity, pyramid: ModelEntity,
             altA: ModelEntity, altB: ModelEntity, d: Float, side: Float, bob: Float) {
            self.tower = tower; self.crystal = crystal; self.pyramid = pyramid
            self.altA = altA; self.altB = altB
            self.d = d; self.side = side; self.bob = bob
            group.addChild(tower); group.addChild(crystal); group.addChild(pyramid)
            group.addChild(altA); group.addChild(altB)
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
                    altA: ModelEntity(mesh: towerMesh, materials: [UnlitMaterial(color: .magenta)]),
                    altB: ModelEntity(mesh: towerMesh, materials: [UnlitMaterial(color: .magenta)]),
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

    /// Re-seed every slot around `distance` (run restart / checkpoint start). Without this, a
    /// distance reset leaves all slots hugely behind the player and nothing ever recycles.
    /// Restyling is deferred to the next `update`, which knows the current world.
    func reset(distance: Double) {
        let dist = Float(distance)
        for (j, s) in slots.enumerated() {
            s.d = dist + Float(j / 2) * gap - span / 2   // slots come in side pairs sharing d
            s.needsRestyle = true
        }
    }

    func update(distance: Double, world: Int, elapsed: Double) {
        let dist = Float(distance)
        // sin() has period 2π, so wrapping keeps the bob continuous while bounding the Float.
        let bobT = Float(elapsed.truncatingRemainder(dividingBy: 2 * Double.pi))
        for s in slots {
            var z = dist - s.d
            if z > 14 || s.needsRestyle {    // passed behind the camera → recycle at the horizon
                while z > 14 { s.d += span; z = dist - s.d }
                style(s, world: world)
                s.needsRestyle = false
            }
            s.group.position.z = z
            if s.floating {
                s.crystal.position.y = s.baseY + sin(bobT + s.bob) * 0.35
            }
        }
    }

    /// Re-skin a slot for `world`: pick the silhouette, randomize size/placement, dim the tint so
    /// decor reads as background rather than competing with obstacles.
    private func style(_ s: Slot, world: Int) {
        let w = world % 3
        let alt = Float.random(in: 0...1) < 0.35   // alternate silhouette for this world
        s.tower.isEnabled = (w == 0) && !alt
        s.crystal.isEnabled = (w == 1) && !alt
        s.pyramid.isEnabled = (w == 2) && !alt
        s.altA.isEnabled = alt
        s.altB.isEnabled = alt && w != 2           // the obelisk is a single piece
        s.floating = false

        let x = s.side * Float.random(in: 6.6...11.5)
        s.group.position.x = x
        let tint = Self.dim(Theme.worlds[w].accent2)
        let mat = UnlitMaterial(color: tint)

        switch (w, alt) {
        case (0, false):
            let h = Float.random(in: 3.5...13)
            s.tower.scale = SIMD3<Float>(Float.random(in: 0.7...1.3), h / 6, Float.random(in: 0.7...1.3))
            s.tower.position.y = h / 2
            s.tower.model?.materials = [mat]
        case (0, true):
            // Metropolis spire: two stacked thin boxes, the upper narrower and offset upward.
            let h0 = Float.random(in: 5...10), h1 = h0 * Float.random(in: 0.45...0.7)
            s.altA.model = ModelComponent(mesh: towerMesh, materials: [mat])
            s.altA.scale = SIMD3<Float>(0.28, h0 / 6, 0.28)
            s.altA.position = SIMD3<Float>(0, h0 / 2, 0)
            s.altA.orientation = simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0))
            s.altB.model = ModelComponent(mesh: towerMesh, materials: [mat])
            s.altB.scale = SIMD3<Float>(0.14, h1 / 6, 0.14)
            s.altB.position = SIMD3<Float>(0, h0 + h1 / 2, 0)
            s.altB.orientation = simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0))
        case (1, false):
            let h = Float.random(in: 2.5...7)
            s.crystal.scale = SIMD3<Float>(Float.random(in: 0.7...1.4), h / 5, Float.random(in: 0.7...1.4))
            s.crystal.orientation = simd_quatf(angle: Float.random(in: -0.25...0.25), axis: SIMD3<Float>(0, 0, 1))
            s.floating = Float.random(in: 0...1) < 0.4
            s.baseY = s.floating ? Float.random(in: 2.5...5) : h / 2
            s.crystal.position.y = s.baseY
            s.crystal.model?.materials = [mat]
        case (1, true):
            // Caverns stalagmite cluster: two grounded cones, no float-bob.
            let h0 = Float.random(in: 2.5...5), h1 = h0 * Float.random(in: 0.5...0.8)
            s.altA.model = ModelComponent(mesh: crystalMesh, materials: [mat])
            s.altA.scale = SIMD3<Float>(Float.random(in: 0.6...1), h0 / 5, Float.random(in: 0.6...1))
            s.altA.position = SIMD3<Float>(-0.7, h0 / 2, 0)
            s.altA.orientation = simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0))
            s.altB.model = ModelComponent(mesh: crystalMesh, materials: [mat])
            s.altB.scale = SIMD3<Float>(Float.random(in: 0.4...0.8), h1 / 5, Float.random(in: 0.4...0.8))
            s.altB.position = SIMD3<Float>(0.8, h1 / 2, 0)
            s.altB.orientation = simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0))
        case (2, false):
            let h = Float.random(in: 2...6.5)
            s.pyramid.scale = SIMD3<Float>(Float.random(in: 0.8...1.6), h / 4, Float.random(in: 0.8...1.6))
            s.pyramid.orientation = simd_quatf(angle: Float.random(in: 0...1), axis: SIMD3<Float>(0, 1, 0))
            s.pyramid.position.y = 0
            s.pyramid.model?.materials = [mat]
        default:
            // Sands obelisk: a single tall thin pyramid.
            let h = Float.random(in: 5...9)
            s.altA.model = ModelComponent(mesh: pyramidMesh, materials: [mat])
            s.altA.scale = SIMD3<Float>(0.22, h / 4, 0.22)
            s.altA.position = SIMD3<Float>(0, 0, 0)
            s.altA.orientation = simd_quatf(angle: Float.random(in: 0...1), axis: SIMD3<Float>(0, 1, 0))
        }
    }

    private static func dim(_ v: SIMD3<Float>) -> UIColor {
        UIColor(red: CGFloat(v.x) * 0.6, green: CGFloat(v.y) * 0.6, blue: CGFloat(v.z) * 0.6, alpha: 1)
    }
}
