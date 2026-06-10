import RealityKit
import simd
import UIKit

/// A pooled CPU particle system — bursts of small bright `UnlitMaterial` spheres with manual
/// physics (gravity + world-scroll drift), shrinking as they die. Mirrors the web prototype's
/// point system; bounded pool, no per-frame allocation. Driven by `RendererPort.fire(FXEvent)`.
@MainActor
final class ParticleSystem {
    private struct P {
        var pos: SIMD3<Float> = .zero
        var vel: SIMD3<Float> = .zero
        var life: Float = 0
        var maxLife: Float = 1
        var on = false
    }

    private let group = Entity()
    private let mesh: MeshResource
    private var parts: [P]
    private var ents: [ModelEntity]
    private let count: Int
    private var cursor = 0

    init(parent: Entity, count: Int = 280) {
        self.count = count
        mesh = .generateSphere(radius: 0.085)
        parts = Array(repeating: P(), count: count)
        ents = []
        ents.reserveCapacity(count)
        for _ in 0..<count {
            let e = ModelEntity(mesh: mesh, materials: [UnlitMaterial(color: .white)])
            e.isEnabled = false
            group.addChild(e)
            ents.append(e)
        }
        parent.addChild(group)
    }

    /// Emit `n` particles from a point with random spread/velocity.
    func burst(x: Float, y: Float, z: Float, color: UIColor, count n: Int, power: Float, spread: Float, life: Float) {
        let mat = UnlitMaterial(color: color)
        for _ in 0..<n {
            cursor = (cursor + 1) % count
            let i = cursor
            parts[i].pos = SIMD3(x + .random(in: -spread...spread),
                                 y + .random(in: -spread...spread),
                                 z + .random(in: -spread...spread))
            parts[i].vel = SIMD3(.random(in: -power...power),
                                 .random(in: power * 0.2...power * 1.4),
                                 .random(in: -power...power))
            parts[i].life = life
            parts[i].maxLife = life
            parts[i].on = true
            ents[i].model?.materials = [mat]
            ents[i].position = parts[i].pos
            ents[i].isEnabled = true
        }
    }

    /// Integrate one frame. `speed` drifts particles toward the camera with the world scroll.
    func step(_ dt: Float, speed: Float) {
        for i in 0..<count where parts[i].on {
            parts[i].life -= dt
            if parts[i].life <= 0 {
                parts[i].on = false
                ents[i].isEnabled = false
                continue
            }
            parts[i].vel.y -= 7 * dt
            parts[i].pos += parts[i].vel * dt
            parts[i].pos.z += speed * 0.9 * dt
            ents[i].position = parts[i].pos
            let f = max(0.05, parts[i].life / parts[i].maxLife)
            ents[i].scale = SIMD3(repeating: f)
        }
    }

    func reset() {
        for i in 0..<count where parts[i].on {
            parts[i].on = false
            ents[i].isEnabled = false
        }
    }
}
