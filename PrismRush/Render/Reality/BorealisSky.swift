import RealityKit
import simd
import UIKit

/// World 6 — "Borealis": a frozen tundra under aurora curtains (v1.5). Three to four aurora ribbons
/// hang high in the sky, each slowly sliding laterally while its amplitude/scale breathes; a row of
/// standing ice shards (tall anisotropic octahedra, each with a faint inner glow disc) lines the
/// horizon; a low wide snow-plain ridge caps the ground; and fine snow drifts downward across the
/// whole scene. Self-contained (its own entities + build/restyle/animate) so `WorldSky` just enables
/// it and forwards two calls — the same scalable shape every bespoke world copies.
///
/// Same invariants as the rest of the families: geometry is built ONCE at init and recycled; all
/// placement is deterministic from a LOCAL `SplitMix64` seeded by the absolute world ordinal (never
/// the run RNG — rule 2); per-frame work is transform + `isEnabled` writes only (zero allocation);
/// motion is subtle and Reduce-Motion-gated. Everything is procedural mesh + `UnlitMaterial` (rule 6).
@MainActor
final class BorealisSky {
    let root = Entity()

    private static let auroraCap = 4
    private static let shardCap = 7
    private static let snowCap = 34

    // Aurora curtains: wavy ribbon cards high in the sky. Each slides laterally + breathes.
    private var auroras: [ModelEntity] = []
    private var auroraBaseX: [Float] = []
    private var auroraBaseY: [Float] = []
    private var auroraZ: [Float] = []
    private var auroraSlide: [Float] = []           // lateral slide speed
    private var auroraPhase: [Float] = []
    private var auroraCount = 0

    // Ground ice shards: a tall standing octahedron + a faint inner glow disc that rides its core.
    @MainActor private final class Shard {
        let group = Entity()
        var body: ModelEntity!
        var glow: ModelEntity!
    }
    private var shards: [Shard] = []
    private var shardParts: [ModelEntity] = []       // bodies (for retint)
    private var shardGlows: [ModelEntity] = []        // inner glows (separate, brighter tint)
    private var shardCount = 0

    // Snow plain — a low, wide ridge whose upper edge caps the ground.
    private var plain: ModelEntity!

    // Snowfall (shared disc mote pattern, drifting DOWNWARD).
    private var snow: [ModelEntity] = []
    private var snowBaseX: [Float] = [], snowTopY: [Float] = [], snowZ: [Float] = []
    private var snowFall: [Float] = [], snowSpan: [Float] = [], snowPhase: [Float] = []
    private var snowSway: [Float] = [], snowScale: [Float] = []
    private var snowCount = 0

    init(parent: Entity) {
        build()
        root.isEnabled = false
        parent.addChild(root)
    }

    // MARK: build (once)

    private func build() {
        let disc = ProceduralMesh.disc()

        // Snow plain: a wide ridge sitting low so only its crested upper edge caps the ground.
        let heights: [Float] = (0..<24).map { i in 2.4 + sinf(Float(i) * 0.7) * 0.5 + cosf(Float(i) * 1.9) * 0.3 }
        plain = ModelEntity(mesh: ProceduralMesh.ridge(width: 90, heights: heights),
                            materials: [Self.mat(.black)])
        plain.position = SIMD3<Float>(0, -3.0, -52)
        root.addChild(plain)

        // Aurora curtains — distinct wave shapes so the stack never looks like one repeated band.
        let ribbonSpecs: [(width: Float, thickness: Float, amplitude: Float, waves: Float, phase: Float)] = [
            (14, 1.0, 1.2, 1.3, 0.3),
            (14, 0.85, 1.1, 1.6, 1.9),
            (14, 0.7, 1.25, 1.4, 3.4),
            (14, 0.9, 1.0, 1.8, 5.1),
        ]
        for spec in ribbonSpecs {
            let a = ModelEntity(
                mesh: ProceduralMesh.ribbon(width: spec.width, thickness: spec.thickness,
                                            amplitude: spec.amplitude, waves: spec.waves, phase: spec.phase),
                materials: [Self.mat(.black)])
            a.isEnabled = false
            root.addChild(a)
            auroras.append(a)
        }
        auroraBaseX = .init(repeating: 0, count: Self.auroraCap)
        auroraBaseY = .init(repeating: 12, count: Self.auroraCap)
        auroraZ = .init(repeating: -58, count: Self.auroraCap)
        auroraSlide = .init(repeating: 0, count: Self.auroraCap)
        auroraPhase = .init(repeating: 0, count: Self.auroraCap)

        // Ice shards — tall standing octahedra at the horizon, each with an inner glow disc.
        for _ in 0..<Self.shardCap {
            let s = Shard()
            let body = ModelEntity(mesh: ProceduralMesh.octahedron(rx: 0.3, ry: 1.4, rz: 0.3),
                                   materials: [Self.mat(.black)])
            let glow = ModelEntity(mesh: disc, materials: [Self.mat(.black)])
            glow.position = SIMD3<Float>(0, 0, 0.32)         // sits just in front of the shard core
            glow.scale = SIMD3<Float>(repeating: 0.28)
            s.body = body
            s.glow = glow
            s.group.addChild(body)
            s.group.addChild(glow)
            s.group.isEnabled = false
            root.addChild(s.group)
            shardParts.append(body)
            shardGlows.append(glow)
            shards.append(s)
        }

        // Snowfall.
        for _ in 0..<Self.snowCap {
            let f = ModelEntity(mesh: disc, materials: [Self.mat(.white)])
            f.isEnabled = false
            root.addChild(f)
            snow.append(f)
        }
        snowBaseX = .init(repeating: 0, count: Self.snowCap)
        snowTopY = .init(repeating: 16, count: Self.snowCap)
        snowZ = .init(repeating: -44, count: Self.snowCap)
        snowFall = .init(repeating: 1, count: Self.snowCap)
        snowSpan = .init(repeating: 16, count: Self.snowCap)
        snowPhase = .init(repeating: 0, count: Self.snowCap)
        snowSway = .init(repeating: 0.2, count: Self.snowCap)
        snowScale = .init(repeating: 0.08, count: Self.snowCap)
    }

    // MARK: restyle (world boundary / Reduce-Motion flip — never per frame)

    func restyle(palette pal: WorldPalette, world: Int) {
        var r = SplitMix64(seed: 0x0_B07EA1 &+ UInt64(bitPattern: Int64(world)) &* 0x9E37_79B9_7F4A_7C15)

        // Calm, cold curtains: aurora uses accent2 (lavender) + accent (ice-blue), mixed toward bg so
        // the layer stays a background wash — never a full-bright wall across the lanes (decree 6).
        let plainC = Self.blend(pal, pal.grid, 0.30)
        let shardC = Self.blend(pal, pal.accent, 0.40)
        let shardGlowC = Self.blend(pal, pal.accent, 0.62)
        let snowC = Self.lift(pal.accent, 0.55)

        // Snow plain — low, only the crest shows above the lane floor's far edge.
        plain.model?.materials = [Self.mat(plainC)]

        // Aurora curtains: 3–4 bands stacked high, calm accent2→accent alternation.
        auroraCount = min(Self.auroraCap, 3 + (world / Theme.worlds.count) % 2)
        for (i, a) in auroras.enumerated() {
            guard i < auroraCount else { a.isEnabled = false; continue }
            let curtainC = i % 2 == 0 ? Self.blend(pal, pal.accent2, 0.30) : Self.blend(pal, pal.accent, 0.26)
            auroraBaseX[i] = Float(r.range(-3, 3))
            auroraBaseY[i] = Float(r.range(11, 15.5))
            auroraZ[i] = Float(r.range(-60, -55))
            auroraSlide[i] = Float(r.range(0.04, 0.08)) * (i % 2 == 0 ? 1 : -1)
            auroraPhase[i] = Float(r.range(0, 6.28))
            a.position = SIMD3<Float>(auroraBaseX[i], auroraBaseY[i], auroraZ[i])
            a.scale = SIMD3<Float>(1.4, 1.4, 1)            // widen the curtains to span the sky
            a.model?.materials = [Self.mat(curtainC)]
            a.isEnabled = true
        }

        // Ice shards — a sparse row standing on the horizon, varied height + lean.
        shardCount = min(Self.shardCap, 5 + (world / Theme.worlds.count))
        for (i, s) in shards.enumerated() {
            guard i < shardCount else { s.group.isEnabled = false; continue }
            let x = Float(r.range(-20, 20))
            let h = Float(r.range(0.7, 1.5))               // vertical scale of the shard
            s.group.position = SIMD3<Float>(x, Float(r.range(-1.0, 0.6)), Float(r.range(-50, -42)))
            s.group.scale = SIMD3<Float>(h, h, h)
            s.group.orientation = simd_quatf(angle: Float(r.range(-0.18, 0.18)), axis: SIMD3<Float>(0, 0, 1))
            s.body.model?.materials = [Self.mat(shardC)]
            s.glow.model?.materials = [Self.mat(shardGlowC)]
            s.group.isEnabled = true
        }

        // Snowfall — scattered across the sky, falling downward; brighter ice-white flakes.
        snowCount = min(Self.snowCap, 26 + 2 * (world / Theme.worlds.count))
        for (i, f) in snow.enumerated() {
            guard i < snowCount else { f.isEnabled = false; continue }
            snowBaseX[i] = Float(r.range(-22, 22))
            snowTopY[i] = Float(r.range(9, 17))
            snowZ[i] = Float(r.range(-50, -40))
            snowSpan[i] = Float(r.range(12, 20))
            snowFall[i] = Float(r.range(0.7, 1.5))
            snowPhase[i] = Float(r.range(0, Double(snowSpan[i])))
            snowSway[i] = Float(r.range(0.15, 0.4))
            let sc = Float(r.range(0.05, 0.11))
            snowScale[i] = sc
            f.scale = SIMD3<Float>(repeating: sc)
            f.position = SIMD3<Float>(snowBaseX[i], snowTopY[i], snowZ[i])
            f.model?.materials = [Self.mat(snowC)]
            f.isEnabled = true
        }
    }

    // MARK: animate (transform + isEnabled only)

    func animate(elapsed: Double, reduceMotion: Bool) {
        if reduceMotion {
            for i in 0..<auroraCount {
                auroras[i].position.x = auroraBaseX[i]
                auroras[i].scale = SIMD3<Float>(1.4, 1.4, 1)
            }
            for i in 0..<snowCount {
                snow[i].position = SIMD3<Float>(snowBaseX[i], snowTopY[i] - snowSpan[i] * 0.5, snowZ[i])
            }
            return
        }
        let t = Float(elapsed)
        // Aurora: amplitude breathes (scale.y) + the curtain slides slowly laterally then wraps across
        // a bounded span, so it drifts continuously without escaping frame (mirror animateCaverns).
        for i in 0..<auroraCount {
            auroras[i].scale.y = 1.4 + 0.18 * sin(t * 0.31 + auroraPhase[i])
            let slid = Self.wrap(Double(auroraBaseX[i]) + (elapsed + Double(auroraPhase[i])) * Double(auroraSlide[i]),
                                 span: 8)
            auroras[i].position.x = Float(slid) + sin(t * 0.05 + Float(i)) * 2.0
        }
        // Snowfall: drift straight DOWN with a slight sway, wrapping back to the top of each flake's span.
        for i in 0..<snowCount {
            let fallen = fmodf(snowPhase[i] + t * snowFall[i], snowSpan[i])
            let y = snowTopY[i] - fallen
            snow[i].position = SIMD3<Float>(snowBaseX[i] + sin(t * 0.4 + snowPhase[i]) * snowSway[i],
                                            y, snowZ[i])
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
