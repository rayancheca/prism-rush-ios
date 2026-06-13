import RealityKit
import simd
import UIKit

/// World 9 — "Eventide": the edge of a black hole. A large near-black sphere hangs high and centred,
/// framed by two flattened accretion rings (`torus`) that spin slowly in opposite directions, a thin
/// horizon ring that scale-PULSES, twin polar jets (`beam`) firing 180° apart from the hole's poles,
/// a few enormous dim nebula washes, and a deep twinkling starfield. Self-contained (its own
/// entities + build/restyle/animate) so `WorldSky` just enables it and forwards two calls — the
/// scalable shape every new world copies, keeping the shared file small.
///
/// Same invariants as the other families: geometry built ONCE at init and recycled; placement is
/// deterministic from a LOCAL `SplitMix64` seeded by the absolute world ordinal (never the run RNG —
/// rule 2); per-frame work is transform + `isEnabled` writes only (zero allocation); all motion is
/// subtle and Reduce-Motion-gated. Everything is procedural mesh + `UnlitMaterial` (rule 6).
@MainActor
final class EventideSky {
    let root = Entity()

    private static let starCap = 42

    // Black hole core (a very dark sphere) parked high + centred.
    private var hole: ModelEntity!
    private var holeCentre = SIMD3<Float>(0, 12, -56)

    // Accretion: two flattened rings that frame the hole and spin (about Z, opposite directions).
    @MainActor private final class Ring {
        let entity: ModelEntity
        var spin: Float = 0       // radians/sec about Z
        var phase: Float = 0
        init(_ e: ModelEntity) { entity = e }
    }
    private var rings: [Ring] = []

    // Horizon ring: a thin torus just outside the accretion that scale-pulses.
    private var horizonRing: ModelEntity!
    private var horizonBaseScale = SIMD3<Float>(repeating: 1)

    // Polar jets: two beams 180° apart from the hole centre.
    private var jets: [ModelEntity] = []
    private var jetLen: Float = 8

    // Nebula washes: a few large very-dim discs behind everything.
    private var nebulae: [ModelEntity] = []

    // Starfield (shared disc mote pattern).
    private var stars: [ModelEntity] = []
    private var starBaseX: [Float] = [], starBaseY: [Float] = [], starZ: [Float] = []
    private var starTwinkle: [Float] = [], starPhase: [Float] = [], starScale: [Float] = []
    private var starCount = 0

    init(parent: Entity) {
        build()
        root.isEnabled = false
        parent.addChild(root)
    }

    // MARK: build (once)

    private func build() {
        let disc = ProceduralMesh.disc()

        // Nebula washes — large dim discs sitting deepest, behind the hole.
        for _ in 0..<3 {
            let n = ModelEntity(mesh: disc, materials: [Self.mat(.black)])
            n.isEnabled = false
            root.addChild(n)
            nebulae.append(n)
        }

        // Black hole core — a sphere; restyle tints it near-black and parks it high/centred.
        hole = ModelEntity(mesh: .generateSphere(radius: 1), materials: [Self.mat(.black)])
        root.addChild(hole)

        // Accretion rings — flattened tori framing the hole; the hole rides in front of them.
        let ringMesh = ProceduralMesh.torus(major: 3, minor: 0.5, majorSeg: 32, minorSeg: 9)
        for _ in 0..<2 {
            let e = ModelEntity(mesh: ringMesh, materials: [Self.mat(.black)])
            e.isEnabled = false
            root.addChild(e)
            rings.append(Ring(e))
        }

        // Horizon ring — same torus, scaled a touch larger; scale-pulses every frame.
        horizonRing = ModelEntity(mesh: ringMesh, materials: [Self.mat(.black)])
        root.addChild(horizonRing)

        // Polar jets — two thin beams, 180° apart, anchored at the hole centre.
        let beamMesh = ProceduralMesh.beam(length: 1, halfWidthNear: 0.55, halfWidthFar: 0.12)
        for _ in 0..<2 {
            let j = ModelEntity(mesh: beamMesh, materials: [Self.mat(.black)])
            j.isEnabled = false
            root.addChild(j)
            jets.append(j)
        }

        // Starfield.
        for _ in 0..<Self.starCap {
            let st = ModelEntity(mesh: disc, materials: [Self.mat(.white)])
            st.isEnabled = false
            root.addChild(st)
            stars.append(st)
        }
        starBaseX = .init(repeating: 0, count: Self.starCap)
        starBaseY = .init(repeating: 0, count: Self.starCap)
        starZ = .init(repeating: -60, count: Self.starCap)
        starTwinkle = .init(repeating: 1, count: Self.starCap)
        starPhase = .init(repeating: 0, count: Self.starCap)
        starScale = .init(repeating: 0.1, count: Self.starCap)
    }

    // MARK: restyle (world boundary / Reduce-Motion flip — never per frame)

    func restyle(palette pal: WorldPalette, world: Int) {
        var r = SplitMix64(seed: 0x0_E7E1DE9 &+ UInt64(bitPattern: Int64(world)) &* 0x9E37_79B9_7F4A_7C15)

        // Colors mix toward bg so the layer reads as background; the hole is the darkest thing,
        // the accretion the brightest — but still dimmed so lane obstacles stay readable (decree 6).
        let holeC = Self.blend(pal, pal.grid, 0.10)               // near-black, faintly violet
        let ringA = Self.blend(pal, pal.accent, 0.46)             // magenta accretion
        let ringB = Self.blend(pal, pal.accent2, 0.46)            // amber accretion
        let horizonC = Self.lift(pal.accent, 0.30)
        let jetC = Self.blend(pal, pal.accent2, 0.40)
        let nebulaC = Self.blend(pal, pal.accent, 0.16)
        let starC = Self.lift(pal.accent, 0.35)

        // Black hole core — high + centred, far back.
        let hr = Float(r.range(3.2, 3.8))
        holeCentre = SIMD3<Float>(Float(r.range(-2.5, 2.5)), Float(r.range(11, 14)), -56)
        hole.scale = SIMD3<Float>(repeating: hr)
        hole.position = SIMD3<Float>(holeCentre.x, holeCentre.y, holeCentre.z + 0.6)   // in front of rings
        hole.model?.materials = [Self.mat(holeC)]

        // Accretion rings — flattened (1,1,0.18), centred on the hole, slight tilt, opposite spins.
        let ringTints = [ringA, ringB]
        for (i, ring) in rings.enumerated() {
            let s = hr * Float(r.range(1.06, 1.18)) * (i == 0 ? 1.0 : 1.22)
            ring.entity.scale = SIMD3<Float>(s, s, s * 0.18)
            ring.entity.position = holeCentre
            ring.phase = Float(r.range(0, 2 * .pi))
            ring.entity.orientation = simd_quatf(angle: ring.phase, axis: SIMD3<Float>(0, 0, 1))
            ring.spin = Float(r.range(0.05, 0.12)) * (i == 0 ? 1 : -1)
            ring.entity.model?.materials = [Self.mat(ringTints[i])]
            ring.entity.isEnabled = true
        }

        // Horizon ring — just outside the larger accretion; pulse baseline (flattened too).
        let hs = hr * Float(r.range(1.45, 1.6))
        horizonBaseScale = SIMD3<Float>(hs, hs, hs * 0.18)
        horizonRing.scale = horizonBaseScale
        horizonRing.position = holeCentre
        horizonRing.model?.materials = [Self.mat(horizonC)]

        // Polar jets — two beams from the hole centre, 180° apart (vertical poles by default).
        jetLen = hr * Float(r.range(2.4, 3.2))
        for (i, j) in jets.enumerated() {
            j.scale = SIMD3<Float>(Float(r.range(0.8, 1.1)), jetLen, 1)
            j.position = holeCentre
            // beam fans along +Y; rotate one to point up, the other down (180° about Z).
            j.orientation = simd_quatf(angle: i == 0 ? 0 : .pi, axis: SIMD3<Float>(0, 0, 1))
            j.model?.materials = [Self.mat(jetC)]
            j.isEnabled = true
        }

        // Nebula washes — big dim discs scattered behind the hole, deepest layer.
        for n in nebulae {
            let ns = Float(r.range(9, 15))
            n.scale = SIMD3<Float>(repeating: ns)
            n.position = SIMD3<Float>(Float(r.range(-16, 16)), Float(r.range(6, 16)), Float(r.range(-64, -60)))
            n.model?.materials = [Self.mat(nebulaC)]
            n.isEnabled = true
        }

        // Starfield — scattered across the upper sky, parked at their twinkle base.
        starCount = min(Self.starCap, 30 + 3 * (world / Theme.worlds.count))
        for (i, st) in stars.enumerated() {
            guard i < starCount else { st.isEnabled = false; continue }
            starBaseX[i] = Float(r.range(-24, 24))
            starBaseY[i] = Float(r.range(5.5, 18))
            starZ[i] = Float(r.range(-62, -50))
            starTwinkle[i] = Float(r.range(0.4, 1.0))
            starPhase[i] = Float(r.range(0, 2 * .pi))
            let s = Float(r.range(0.06, 0.15))
            starScale[i] = s
            st.scale = SIMD3<Float>(repeating: s)
            st.position = SIMD3<Float>(starBaseX[i], starBaseY[i], starZ[i])
            st.model?.materials = [Self.mat(starC)]
            st.isEnabled = true
        }
    }

    // MARK: animate (transform + isEnabled only)

    func animate(elapsed: Double, reduceMotion: Bool) {
        if reduceMotion {
            for ring in rings {
                ring.entity.orientation = simd_quatf(angle: ring.phase, axis: SIMD3<Float>(0, 0, 1))
            }
            horizonRing.scale = horizonBaseScale
            return
        }
        let t = Float(elapsed)
        // Accretion rings: slow continuous spin about Z, opposite directions.
        for ring in rings {
            ring.entity.orientation = simd_quatf(angle: ring.phase + t * ring.spin, axis: SIMD3<Float>(0, 0, 1))
        }
        // Horizon ring: gentle scale-pulse (radius breathes; flatten ratio held).
        let pulse = 1 + 0.06 * sin(t * 0.7)
        horizonRing.scale = SIMD3<Float>(horizonBaseScale.x * pulse,
                                         horizonBaseScale.y * pulse,
                                         horizonBaseScale.z)
        // Stars: slow twinkle — modulate each star's base scale by a per-star sine.
        for i in 0..<starCount {
            let tw = 0.65 + 0.35 * sin(t * starTwinkle[i] + starPhase[i])
            stars[i].scale = SIMD3<Float>(repeating: max(0.02, starScale[i] * tw))
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
}
