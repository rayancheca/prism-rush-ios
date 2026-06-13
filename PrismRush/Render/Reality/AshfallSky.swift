import RealityKit
import simd
import UIKit

/// World 5 — "Ashfall": a volcanic-night sky family (v1.5). A dark volcano cone sits low off-centre
/// with a lava pool at its base that breathes (scale-pulses a warm glow); two or three dim lava
/// seams run roughly flat across the lower sky and slide laterally with the parallax; embers rise
/// fast off the cone and flicker out; and two ash ridges — one sharp and far, one nearer and
/// heavier — bank the horizon. Self-contained (its own entities + build/restyle/animate) so
/// `WorldSky` just enables it and forwards two calls — the scalable shape every new world copies.
///
/// Same invariants as the other families: geometry built ONCE at init and recycled; placement is
/// deterministic from a LOCAL `SplitMix64` seeded by the absolute world ordinal (never the run RNG —
/// rule 2); per-frame work is transform + `isEnabled` writes only (zero allocation); all motion is
/// subtle and Reduce-Motion-gated. Everything is procedural mesh + `UnlitMaterial` (rule 6). The
/// volcano stays dark and the seams dim so lane obstacles read in front (decree 6); only the lava
/// pool and embers carry brightness, and never as a wall of colour across the lanes.
@MainActor
final class AshfallSky {
    let root = Entity()

    private static let emberCap = 36

    // Volcano: a dark pyramid silhouette parked low, with a breathing lava-pool disc at its base
    // (the glow rides behind a slightly smaller core so it reads as a molten rim).
    private var volcano: ModelEntity!
    private var lavaPool: ModelEntity!          // bright core (scale-pulses)
    private var lavaGlow: ModelEntity!          // softer halo behind the pool (pulses out of phase)
    private var poolBase: SIMD3<Float> = .init(0, 0, -50)
    private var poolScale: Float = 2.0

    // Lava seams: flat-ish ribbons low in the sky that slide laterally (parallax, NOT phase-flow).
    @MainActor private final class Seam {
        let entity: ModelEntity
        var baseX: Float = 0, baseY: Float = 0, z: Float = 0
        var speed: Float = 0, phase: Double = 0
        init(_ e: ModelEntity) { entity = e }
    }
    private var seams: [Seam] = []

    // Ash ridges: a sharp far crest and a heavier near crest banking the horizon.
    private var farRidge: ModelEntity!
    private var nearRidge: ModelEntity!

    // Embers (shared disc mote pattern) — rise fast off the cone, flicker, recycle.
    private var embers: [ModelEntity] = []
    private var emberBaseX: [Float] = [], emberZ: [Float] = []
    private var emberRise: [Float] = [], emberSpan: [Float] = []
    private var emberPhase: [Float] = [], emberFlick: [Float] = [], emberScale: [Float] = []
    private var emberCount = 0

    init(parent: Entity) {
        build()
        root.isEnabled = false
        parent.addChild(root)
    }

    // MARK: build (once)

    private func build() {
        let disc = ProceduralMesh.disc()

        // Volcano cone — a dark pyramid; restyle parks it low so its base sits near the horizon.
        volcano = ModelEntity(mesh: ProceduralMesh.pyramid(halfBase: 3, height: 4),
                              materials: [Self.mat(.black)])
        root.addChild(volcano)

        // Lava pool: a bright disc at the cone base, plus a softer glow halo behind it. Both face
        // +Z (the camera) and pulse in animate — geometry is fixed here.
        lavaGlow = ModelEntity(mesh: disc, materials: [Self.mat(.black)])
        lavaPool = ModelEntity(mesh: disc, materials: [Self.mat(.black)])
        root.addChild(lavaGlow)
        root.addChild(lavaPool)

        // Lava seams: thin ribbons laid roughly flat/low. Built once at unit form; restyle places
        // and tints them. The undulation is baked into the ribbon mesh; motion is lateral slide.
        for i in 0..<3 {
            let mesh = ProceduralMesh.ribbon(width: 18, thickness: 0.5, amplitude: 0.7,
                                             waves: 2.2, phase: Float(i) * 1.7)
            let e = ModelEntity(mesh: mesh, materials: [Self.mat(.black)])
            e.isEnabled = false
            root.addChild(e)
            seams.append(Seam(e))
        }

        // Ash ridges: two silhouette crests. Sample two static height profiles so each reads as a
        // jagged volcanic skyline rather than a smooth dune. Built once; restyle tints + parks them.
        farRidge = ModelEntity(mesh: ProceduralMesh.ridge(width: 70, heights: Self.ridgeHeights(sharp: true)),
                               materials: [Self.mat(.black)])
        nearRidge = ModelEntity(mesh: ProceduralMesh.ridge(width: 60, heights: Self.ridgeHeights(sharp: false)),
                                materials: [Self.mat(.black)])
        root.addChild(farRidge)
        root.addChild(nearRidge)

        // Embers — warm disc motes that rise fast off the cone.
        for _ in 0..<Self.emberCap {
            let m = ModelEntity(mesh: disc, materials: [Self.mat(.orange)])
            m.isEnabled = false
            root.addChild(m)
            embers.append(m)
        }
        emberBaseX = .init(repeating: 0, count: Self.emberCap)
        emberZ = .init(repeating: -40, count: Self.emberCap)
        emberRise = .init(repeating: 4, count: Self.emberCap)
        emberSpan = .init(repeating: 10, count: Self.emberCap)
        emberPhase = .init(repeating: 0, count: Self.emberCap)
        emberFlick = .init(repeating: 1, count: Self.emberCap)
        emberScale = .init(repeating: 0.1, count: Self.emberCap)
    }

    /// A jagged crest profile for the ash ridges — a fixed deterministic shape (no RNG; identical
    /// every world so the silhouette is stable) sampled across the ridge width.
    private static func ridgeHeights(sharp: Bool) -> [Float] {
        let n = sharp ? 24 : 18
        var h: [Float] = []
        h.reserveCapacity(n)
        for i in 0..<n {
            let u = Float(i) / Float(n - 1)
            // Two offset sines + a sharper harmonic give a banked, peaked ridgeline.
            let base = sin(u * 5.3 + (sharp ? 0.0 : 1.4)) * (sharp ? 1.0 : 0.7)
            let peak = abs(sin(u * 11.0 + (sharp ? 2.1 : 0.5))) * (sharp ? 0.8 : 0.5)
            h.append(max(0.2, 1.0 + base + (sharp ? peak : peak * 0.6)))
        }
        return h
    }

    // MARK: restyle (world boundary / Reduce-Motion flip — never per frame)

    func restyle(palette pal: WorldPalette, world: Int) {
        var r = SplitMix64(seed: 0x0_A54FA1 &+ UInt64(bitPattern: Int64(world)) &* 0x9E37_79B9_7F4A_7C15)

        // Colours mix toward bg so the layer reads as background: the volcano is darkest, the
        // ridges are dim silhouettes, the lava pool + embers carry the warmth (but never blinding).
        let volcanoC = Self.blend(pal, pal.grid, 0.20)            // very dark cone, faint orange tint
        let poolC = Self.lift(pal.accent2, 0.18)                  // molten amber core
        let glowC = Self.blend(pal, pal.accent, 0.55)             // softer red halo
        let seamC = Self.blend(pal, pal.accent, 0.36)             // dim orange seams
        let farC = Self.blend(pal, pal.grid, 0.16)                // far ash crest, nearly bg
        let nearC = Self.blend(pal, pal.grid, 0.26)               // nearer crest, a touch lighter
        let emberC = Self.lift(pal.accent2, 0.34)                 // warm bright embers

        // Volcano: parked low and slightly off-centre so its base meets the horizon band; only the
        // upper cone + lava pool show above the lanes. Alternate side per world cycle.
        let side: Float = (world / Theme.worlds.count) % 2 == 0 ? -1 : 1
        let vScale = Float(r.range(2.6, 3.4))
        let vx = side * Float(r.range(2.5, 6.0))
        let vy = Float(r.range(-6.5, -4.5))
        let vz = Float(r.range(-50, -44))
        volcano.scale = SIMD3<Float>(repeating: vScale)
        volcano.position = SIMD3<Float>(vx, vy, vz)
        volcano.model?.materials = [Self.mat(volcanoC)]

        // Lava pool sits at the cone's base (top of the truncated cone in frame), pulsing.
        poolBase = SIMD3<Float>(vx, vy + vScale * Float(r.range(2.2, 2.8)), vz + 0.4)
        poolScale = vScale * Float(r.range(0.5, 0.7))
        lavaPool.position = poolBase
        lavaPool.scale = SIMD3<Float>(repeating: poolScale)
        lavaPool.model?.materials = [Self.mat(poolC)]
        lavaGlow.position = SIMD3<Float>(poolBase.x, poolBase.y, poolBase.z - 0.5)
        lavaGlow.scale = SIMD3<Float>(repeating: poolScale * 1.6)
        lavaGlow.model?.materials = [Self.mat(glowC)]

        // Lava seams: roughly flat, low in the sky, fanning across. Slide laterally (parallax).
        for i in seams.indices {
            let s = seams[i]
            s.baseX = Float(r.range(-4, 4))
            s.baseY = Float(r.range(2.5, 6.5)) + Float(i)
            s.z = Float(-46 - 3 * i) - Float(r.range(0, 3))
            s.speed = Float(r.range(0.10, 0.22)) * (i % 2 == 0 ? 1 : -1)
            s.phase = r.range(0, 40)
            s.entity.position = SIMD3<Float>(s.baseX, s.baseY, s.z)
            // Lay the seams nearly flat (tilt back about X) so they read as low molten cracks.
            s.entity.orientation = simd_quatf(angle: Float(r.range(-0.5, -0.2)), axis: SIMD3<Float>(1, 0, 0))
            s.entity.scale = SIMD3<Float>(Float(r.range(0.9, 1.2)), Float(r.range(0.6, 1.0)), 1)
            s.entity.model?.materials = [Self.mat(seamC)]
            s.entity.isEnabled = true
        }

        // Ash ridges: far crest deep + tall, near crest lower + heavier, both banking the horizon.
        farRidge.scale = SIMD3<Float>(1, Float(r.range(1.4, 2.0)), 1)
        farRidge.position = SIMD3<Float>(Float(r.range(-4, 4)), Float(r.range(-2.0, -0.5)), Float(r.range(-60, -56)))
        farRidge.model?.materials = [Self.mat(farC)]
        nearRidge.scale = SIMD3<Float>(1, Float(r.range(1.2, 1.7)), 1)
        nearRidge.position = SIMD3<Float>(Float(r.range(-3, 3)), Float(r.range(-3.5, -2.0)), Float(r.range(-52, -48)))
        nearRidge.model?.materials = [Self.mat(nearC)]

        // Embers — rise off the cone region: fast vertical drift, flicker, recycle within a span.
        emberCount = min(Self.emberCap, 26 + 2 * (world / Theme.worlds.count))
        for (i, m) in embers.enumerated() {
            guard i < emberCount else { m.isEnabled = false; continue }
            emberBaseX[i] = vx + Float(r.range(-6, 6))
            emberZ[i] = vz + Float(r.range(-2, 6))
            emberRise[i] = Float(r.range(3.5, 6.5))                  // fast
            emberSpan[i] = Float(r.range(8, 14))
            emberPhase[i] = Float(r.range(0, 1))                     // 0..1 fraction along the rise
            emberFlick[i] = Float(r.range(4, 9))                     // flicker rate
            let s = Float(r.range(0.05, 0.13))
            emberScale[i] = s
            m.scale = SIMD3<Float>(repeating: s)
            m.position = SIMD3<Float>(emberBaseX[i], poolBase.y, emberZ[i])
            m.model?.materials = [Self.mat(emberC)]
            m.isEnabled = true
        }
    }

    // MARK: animate (transform + isEnabled only)

    func animate(elapsed: Double, reduceMotion: Bool) {
        if reduceMotion {
            lavaPool.scale = SIMD3<Float>(repeating: poolScale)
            lavaGlow.scale = SIMD3<Float>(repeating: poolScale * 1.6)
            for i in seams.indices {
                seams[i].entity.position = SIMD3<Float>(seams[i].baseX, seams[i].baseY, seams[i].z)
            }
            for i in 0..<emberCount {
                embers[i].position = SIMD3<Float>(emberBaseX[i],
                                                  poolBase.y + emberSpan[i] * 0.4, emberZ[i])
                embers[i].isEnabled = true
                embers[i].scale = SIMD3<Float>(repeating: emberScale[i])
            }
            return
        }
        let t = Float(elapsed)

        // Lava pool breathes: core pulses, glow halo pulses slightly out of phase (molten swell).
        let pulse = 1.0 + 0.14 * sin(t * 1.3)
        lavaPool.scale = SIMD3<Float>(repeating: poolScale * pulse)
        let glowPulse = 1.0 + 0.20 * sin(t * 1.3 + 0.9)
        lavaGlow.scale = SIMD3<Float>(repeating: poolScale * 1.6 * glowPulse)

        // Seams slide laterally and wrap (parallax, not phase-flow); a faint vertical shimmer.
        for i in seams.indices {
            let s = seams[i]
            let x = Self.wrap(Double(s.baseX) + (elapsed + s.phase) * Double(s.speed), span: 30)
            s.entity.position = SIMD3<Float>(Float(x),
                                             s.baseY + sin(t * 0.3 + Float(i) * 1.6) * 0.18,
                                             s.z)
        }

        // Embers rise fast and recycle; flicker by scaling toward zero between bursts.
        for i in 0..<emberCount {
            let frac = (Double(emberPhase[i]) + elapsed * Double(emberRise[i]) / Double(emberSpan[i]))
                .truncatingRemainder(dividingBy: 1)
            let y = poolBase.y + emberSpan[i] * Float(frac)
            // Drift sideways a touch as they climb, like rising sparks.
            let drift = sin(t * 0.6 + Float(i) * 1.3) * 1.2 * Float(frac)
            embers[i].position = SIMD3<Float>(emberBaseX[i] + drift, y, emberZ[i])
            // Flicker + fade out near the top of the rise.
            let flick = 0.55 + 0.45 * sin(t * emberFlick[i] + Float(i))
            let fade = Float(1 - frac * 0.85)
            let sc = max(0.0, emberScale[i] * flick * fade)
            embers[i].scale = SIMD3<Float>(repeating: sc)
        }
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

    private static func wrap(_ v: Double, span: Double) -> Double {
        var w = v.truncatingRemainder(dividingBy: span)
        if w < 0 { w += span }
        return w - span / 2
    }
}
