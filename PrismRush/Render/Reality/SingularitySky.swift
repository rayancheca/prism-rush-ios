import RealityKit
import simd
import UIKit

/// World 11 — "Singularity": the white endgame. A single radiant white-hot core hangs high and
/// far on the deep-violet field, ringed by a ladder of concentric spectrum tori that slowly
/// breathe outward and recycle, an eight-spoke ray crown rotating behind the core, a static
/// flare strung along one axis, and one huge dim wash disc farthest back. The brilliant core +
/// rainbow rings ARE the "white endgame" — never a white background (which would break every
/// dark-bg obstacle/ground/gem material), so the field stays 0x140A2E violet (decree 6).
///
/// Same invariants as OrbitalSky: geometry built ONCE at init and recycled; placement is
/// deterministic from a LOCAL `SplitMix64` seeded by the absolute world ordinal (never the run
/// RNG — rule 2); per-frame work is transform + `isEnabled` writes only (zero allocation); all
/// motion is subtle and Reduce-Motion-gated. Procedural mesh + `UnlitMaterial` only (rule 6).
@MainActor
final class SingularitySky {
    let root = Entity()

    private static let ringCount = 6
    private static let rayCount = 8
    private static let flareCap = 5

    // Core: one very bright disc + a softer halo behind it.
    private var core: ModelEntity!
    private var halo: ModelEntity!
    private var coreBase = SIMD3<Float>(0, 11, -52)
    private var coreBaseScale: Float = 2.2          // radius set in restyle; the pulse multiplies it

    // Wash: the largest, dimmest disc farthest back.
    private var wash: ModelEntity!

    // Rings: concentric tori flattened in Z, each a fixed spectrum tint; they expand + recycle.
    @MainActor private final class Ring {
        let entity: ModelEntity
        var phase: Float = 0          // 0…1 expansion offset, recycles
        var spin: Float = 0           // gentle per-ring roll for life
        init(_ e: ModelEntity) { entity = e }
    }
    private var rings: [Ring] = []

    // Rays: eight beams as children of one group that rotates as a whole behind the core.
    private let rayGroup = Entity()
    private var rays: [ModelEntity] = []

    // Flare: a few bright discs strung along one axis (static).
    private var flares: [ModelEntity] = []
    private var flareCount = 0

    init(parent: Entity) {
        build()
        root.isEnabled = false
        parent.addChild(root)
    }

    // MARK: build (once)

    private func build() {
        let disc = ProceduralMesh.disc()

        // Wash (farthest, dimmest) → core halo → core (brightest), back to front.
        wash = ModelEntity(mesh: disc, materials: [Self.mat(.black)])
        root.addChild(wash)

        // Ray crown sits just behind the core; built before the core so the core overdraws it.
        for _ in 0..<Self.rayCount {
            let beam = ModelEntity(mesh: ProceduralMesh.beam(length: 5, halfWidthNear: 0.55, halfWidthFar: 0.04),
                                   materials: [Self.mat(.black)])
            rayGroup.addChild(beam)
            rays.append(beam)
        }
        root.addChild(rayGroup)

        // Rings (concentric, flattened in Z so they read as rings facing the camera).
        for i in 0..<Self.ringCount {
            let major = 1.5 + Float(i) * 0.7
            let t = ModelEntity(mesh: ProceduralMesh.torus(major: major, minor: 0.08),
                                materials: [Self.mat(.black)])
            t.scale = SIMD3<Float>(1, 1, 0.18)        // flatten toward the camera plane
            root.addChild(t)
            rings.append(Ring(t))
        }

        halo = ModelEntity(mesh: disc, materials: [Self.mat(.black)])
        root.addChild(halo)
        core = ModelEntity(mesh: disc, materials: [Self.mat(.white)])
        root.addChild(core)

        // Flares strung along one axis (static).
        for _ in 0..<Self.flareCap {
            let f = ModelEntity(mesh: disc, materials: [Self.mat(.white)])
            f.isEnabled = false
            root.addChild(f)
            flares.append(f)
        }
    }

    // MARK: restyle (world boundary / Reduce-Motion flip — never per frame)

    func restyle(palette pal: WorldPalette, world: Int) {
        var r = SplitMix64(seed: 0x0_51_9A1A_71_7E &+ UInt64(bitPattern: Int64(world)) &* 0x9E37_79B9_7F4A_7C15)

        // Six fixed bright spectrum tints (the rainbow ladder) — author-fixed, full-bright but thin.
        let spectrum: [UIColor] = [
            UIColor(red: 1.00, green: 0.27, blue: 0.45, alpha: 1),   // rose
            UIColor(red: 1.00, green: 0.70, blue: 0.20, alpha: 1),   // amber
            UIColor(red: 0.95, green: 0.96, blue: 0.30, alpha: 1),   // chartreuse
            UIColor(red: 0.30, green: 0.95, blue: 0.55, alpha: 1),   // green
            UIColor(red: 0.30, green: 0.78, blue: 1.00, alpha: 1),   // cyan
            UIColor(red: 0.70, green: 0.45, blue: 1.00, alpha: 1),   // violet
        ]

        // Core radiant white; halo a softer wash of the same; wash + rays mix toward bg (background).
        let coreC = Self.lift(pal.accent, 0.70)                  // accent lifted toward white
        let haloC = Self.lift(pal.accent, 0.40)
        let washC = Self.blend(pal, pal.grid, 0.18)              // very dim, barely above the field
        let rayC = Self.blend(pal, pal.accent2, 0.42)            // dim gold spokes behind the core

        // Core high + centred + far; tiny lateral drift per world so it never pins dead-centre.
        coreBase = SIMD3<Float>(Float(r.range(-2.5, 2.5)), Float(r.range(10, 13)), Float(r.range(-54, -50)))
        let coreR = Float(r.range(2.0, 2.6))
        coreBaseScale = coreR
        core.position = coreBase
        core.scale = SIMD3<Float>(repeating: coreR)
        core.model?.materials = [Self.mat(coreC)]
        halo.position = SIMD3<Float>(coreBase.x, coreBase.y, coreBase.z - 0.4)
        halo.scale = SIMD3<Float>(repeating: coreR * 2.4)
        halo.model?.materials = [Self.mat(haloC)]

        // Wash: one huge dim disc farthest back, centred on the core.
        wash.position = SIMD3<Float>(coreBase.x, coreBase.y, -62)
        wash.scale = SIMD3<Float>(repeating: Float(r.range(13, 16)))
        wash.model?.materials = [Self.mat(washC)]

        // Rings: concentric on the core, each its own spectrum tint, staggered expansion phases.
        rayGroup.position = SIMD3<Float>(coreBase.x, coreBase.y, coreBase.z + 0.2)
        for (i, ring) in rings.enumerated() {
            ring.entity.position = SIMD3<Float>(coreBase.x, coreBase.y, coreBase.z + 0.6)
            ring.phase = Float(i) / Float(Self.ringCount)
            ring.spin = Float(r.range(-0.12, 0.12))
            ring.entity.scale = SIMD3<Float>(1, 1, 0.18)
            ring.entity.model?.materials = [Self.mat(spectrum[i % spectrum.count])]
            ring.entity.isEnabled = true
        }

        // Ray crown: eight spokes at equal angular intervals, anchored at the group origin.
        for (i, beam) in rays.enumerated() {
            let a = Float(i) / Float(Self.rayCount) * 2 * .pi
            beam.position = .zero
            beam.orientation = simd_quatf(angle: a, axis: SIMD3<Float>(0, 0, 1))
            beam.model?.materials = [Self.mat(rayC)]
        }

        // Flares: a few bright discs strung along one diagonal axis through the core (static).
        flareCount = min(Self.flareCap, 3 + Int(r.range(0, 2.99)))
        let axis = simd_normalize(SIMD2<Float>(Float(r.range(-1, 1)), Float(r.range(-1, 1)) * 0.4))
        for (i, f) in flares.enumerated() {
            guard i < flareCount else { f.isEnabled = false; continue }
            let d = Float(i + 1) * Float(r.range(2.4, 3.4))
            f.position = SIMD3<Float>(coreBase.x + axis.x * d, coreBase.y + axis.y * d, coreBase.z + 0.1)
            f.scale = SIMD3<Float>(repeating: Float(r.range(0.18, 0.42)) / Float(i + 1) + 0.12)
            f.model?.materials = [Self.mat(Self.lift(pal.accent2, 0.45))]
            f.isEnabled = true
        }
    }

    // MARK: animate (transform + isEnabled only)

    func animate(elapsed: Double, reduceMotion: Bool) {
        if reduceMotion {
            rayGroup.orientation = simd_quatf(angle: 0, axis: SIMD3<Float>(0, 0, 1))
            core.scale = SIMD3<Float>(repeating: coreBaseScale)
            for ring in rings {
                ring.entity.scale = SIMD3<Float>(1, 1, 0.18)    // settle each ring at its base radius
                ring.entity.orientation = simd_quatf(angle: 0, axis: SIMD3<Float>(0, 0, 1))
            }
            return
        }
        let t = Float(elapsed)

        // Ray crown: the whole spoke group rotates slowly behind the core.
        rayGroup.orientation = simd_quatf(angle: t * 0.06, axis: SIMD3<Float>(0, 0, 1))

        // Rings: each breathes outward (phase advances 0→1) then recycles back small — a steady
        // expansion ladder. `grow` scales the torus's already-baked radius (major 1.5…5).
        for ring in rings {
            let p = (ring.phase + t * 0.045).truncatingRemainder(dividingBy: 1)
            let grow = 0.4 + p * 1.25                           // 0.4× → 1.65× the base radius
            ring.entity.scale = SIMD3<Float>(grow, grow, 0.18)
            ring.entity.orientation = simd_quatf(angle: t * ring.spin, axis: SIMD3<Float>(0, 0, 1))
        }

        // Core: a gentle radiant pulse so the white heart feels alive — always off the stored base.
        let pulse = 1 + 0.05 * sin(t * 0.8)
        core.scale = SIMD3<Float>(repeating: coreBaseScale * pulse)
    }

    // MARK: color helpers (mirror WorldSky.blend/lift so the family reads as background)

    private static func mat(_ c: UIColor) -> UnlitMaterial { UnlitMaterial(color: c) }

    private static func blend(_ p: WorldPalette, _ v: SIMD3<Float>, _ t: Float) -> UIColor {
        let c = p.bg + (v - p.bg) * t
        return UIColor(red: CGFloat(c.x), green: CGFloat(c.y), blue: CGFloat(c.z), alpha: 1)
    }

    private static func lift(_ v: SIMD3<Float>, _ t: Float) -> UIColor {
        let c = v + (SIMD3<Float>(1, 1, 1) - v) * t
        return UIColor(red: CGFloat(c.x), green: CGFloat(c.y), blue: CGFloat(c.z), alpha: 1)
    }
}
