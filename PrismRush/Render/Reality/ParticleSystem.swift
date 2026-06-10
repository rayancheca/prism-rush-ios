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
        var stretch: Float = 1      // > 1 renders as a thin z-streak (speed lines)
        var on = false
    }

    private let group = Entity()
    private let mesh: MeshResource
    private var parts: [P]
    private var ents: [ModelEntity]
    private let count: Int
    private var cursor = 0

    // Materials cached per color — bursts fire every few frames and were allocating an
    // UnlitMaterial each call. The palette of tints is small (gold/white/accents), but crossfade
    // accents step through quantized blends, so the cache is bounded by a hard cap.
    private var matCache: [UIColor: UnlitMaterial] = [:]

    init(parent: Entity, count: Int = 400) {
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
    /// `velZ` is added to the random z velocity (directed streams, e.g. speed lines).
    /// `stretchZ > 1` renders each particle as a thin streak scaled (0.05, 0.05, stretchZ).
    func burst(x: Float, y: Float, z: Float, color: UIColor, count n: Int, power: Float,
               spread: Float, life: Float, velZ: Float = 0, stretchZ: Float = 1) {
        guard n > 0 else { return }
        let mat = material(for: color)
        for _ in 0..<n {
            let pos = SIMD3<Float>(x + .random(in: -spread...spread),
                                   y + .random(in: -spread...spread),
                                   z + .random(in: -spread...spread))
            let vel = SIMD3<Float>(.random(in: -power...power),
                                   .random(in: power * 0.2...power * 1.4),
                                   .random(in: -power...power) + velZ)
            emit(pos: pos, vel: vel, life: life, stretch: stretchZ, mat: mat)
        }
    }

    /// One-shot horizon ring sweep (world-change flourish): `n` particles evenly spaced on a
    /// circle in the XY plane at depth `z`, rushing toward the player at `velZ`.
    func ring(y: Float, z: Float, radius: Float, color: UIColor, count n: Int, velZ: Float, life: Float) {
        guard n > 0 else { return }
        let mat = material(for: color)
        for k in 0..<n {
            let a = Float(k) / Float(n) * 2 * .pi
            let pos = SIMD3<Float>(cos(a) * radius, y + sin(a) * radius, z)
            let vel = SIMD3<Float>(cos(a) * 0.8, sin(a) * 0.8 + 3.2, velZ)
            emit(pos: pos, vel: vel, life: life, stretch: 1, mat: mat)
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
            let f = max(0.15, parts[i].life / parts[i].maxLife)
            let s = parts[i].stretch
            ents[i].scale = s == 1 ? SIMD3(repeating: f) : SIMD3(0.05, 0.05, s * f)
        }
    }

    func reset() {
        for i in 0..<count where parts[i].on {
            parts[i].on = false
            ents[i].isEnabled = false
        }
    }

    private func emit(pos: SIMD3<Float>, vel: SIMD3<Float>, life: Float, stretch: Float, mat: UnlitMaterial) {
        // Advance to a free slot so simultaneous bursts don't overwrite live particles (bounded).
        var tries = 0
        repeat { cursor = (cursor + 1) % count; tries += 1 } while parts[cursor].on && tries < count
        let i = cursor
        parts[i].pos = pos
        parts[i].vel = vel
        parts[i].life = life
        parts[i].maxLife = life
        parts[i].stretch = stretch
        parts[i].on = true
        ents[i].model?.materials = [mat]
        ents[i].position = pos
        ents[i].scale = stretch == 1 ? .one : SIMD3(0.05, 0.05, stretch)
        ents[i].isEnabled = true
    }

    private func material(for color: UIColor) -> UnlitMaterial {
        if let m = matCache[color] { return m }
        if matCache.count >= 64 { matCache.removeAll(keepingCapacity: true) }  // hard bound
        let m = UnlitMaterial(color: color)
        matCache[color] = m
        return m
    }
}
