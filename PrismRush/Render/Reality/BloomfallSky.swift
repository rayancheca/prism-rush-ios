import RealityKit
import simd
import UIKit

/// World 8 — "Bloomfall": a cherry-blossom grove at night. Three or four trees stand along the
/// horizon (boxy trunk + a couple of tapered beam-branches + a flattened sphere canopy in soft
/// pink) and sway gently; petals drift DOWN across the sky with a wide lazy sway and slight tilt;
/// two or three lanterns hang and softly scale-flicker; ONE large pale moon sits high and static
/// behind a faint halo; a low ridge of hills grounds it all. Dreamy and calm — set pieces stay
/// dim so the lanes read in front (decree 6).
///
/// Same invariants as the other bespoke families: geometry is built ONCE at init and recycled;
/// placement is deterministic from a LOCAL `SplitMix64` seeded by the absolute world ordinal
/// (never the run RNG — rule 2); per-frame work is transform + `isEnabled` writes only (zero
/// allocation); all motion is subtle and Reduce-Motion-gated. Everything is procedural mesh +
/// `UnlitMaterial` (rule 6).
@MainActor
final class BloomfallSky {
    let root = Entity()

    private static let petalCap = 40

    // Moon — one large pale disc high in the sky + a faint halo behind it (both static).
    private var moon: ModelEntity!
    private var moonHalo: ModelEntity!

    // Hills — a low ridge silhouette grounding the grove.
    private var hills: ModelEntity!

    // Trees: trunk box + 2-3 tapered branch beams + a flattened-sphere canopy. The whole group
    // sways as one (rotate about its base), so the group's pivot sits at the trunk foot.
    @MainActor private final class Tree {
        let group = Entity()
        let canopyPivot = Entity()       // canopy + branches ride this; swayed about z
        var canopy: ModelEntity!
        var parts: [ModelEntity] = []    // trunk + branches (trunk tint)
        var swaySpeed: Float = 0, swayAmp: Float = 0, phase: Float = 0
        var baseRoll: Float = 0
    }
    private var trees: [Tree] = []
    private var trunkParts: [ModelEntity] = []
    private var canopies: [ModelEntity] = []

    // Lanterns: a bright disc that softly scale-flickers.
    @MainActor private final class Lantern {
        let entity: ModelEntity
        var baseScale: Float = 0.5, flickerSpeed: Float = 1, phase: Float = 0
        init(_ e: ModelEntity) { entity = e }
    }
    private var lanterns: [Lantern] = []

    // Falling petals (shared disc mote pattern) — drift down with wide sway + a slight tilt.
    private var petals: [ModelEntity] = []
    private var petalX: [Float] = [], petalTopY: [Float] = [], petalZ: [Float] = []
    private var petalFall: [Float] = [], petalSway: [Float] = [], petalPhase: [Float] = []
    private var petalTilt: [Float] = [], petalScale: [Float] = []
    private var petalCount = 0

    private static let skyTop: Float = 18      // petals respawn at the top of this band
    private static let skyFloor: Float = 1     // and fade out around here, then wrap

    init(parent: Entity) {
        build()
        root.isEnabled = false
        parent.addChild(root)
    }

    // MARK: build (once)

    private func build() {
        let disc = ProceduralMesh.disc()

        // Moon + halo (parked high in restyle).
        moonHalo = ModelEntity(mesh: disc, materials: [Self.mat(.black)])
        moon = ModelEntity(mesh: disc, materials: [Self.mat(.white)])
        root.addChild(moonHalo)
        root.addChild(moon)

        // Hills — a gentle two-hump ridge, parked low so only its crest shows.
        let hillHeights: [Float] = (0..<24).map { i in
            let u = Float(i) / 23
            return 2.4 + 1.6 * sin(u * 3.1) + 0.9 * sin(u * 7.3 + 1.2)
        }
        hills = ModelEntity(mesh: ProceduralMesh.ridge(width: 90, heights: hillHeights),
                            materials: [Self.mat(.black)])
        root.addChild(hills)

        // Trees.
        for _ in 0..<4 {
            let tr = Tree()
            // Trunk: tall thin box, foot at y = 0 so the group's base is its pivot.
            let trunk = ModelEntity(mesh: .generateBox(width: 0.5, height: 6.0, depth: 0.5, cornerRadius: 0.08),
                                    materials: [Self.mat(.brown)])
            trunk.position = SIMD3<Float>(0, 3.0, 0)
            tr.group.addChild(trunk)
            tr.parts.append(trunk)

            // Canopy pivot sits at the crown so branches + canopy sway about the upper trunk.
            tr.canopyPivot.position = SIMD3<Float>(0, 5.4, 0)
            tr.group.addChild(tr.canopyPivot)

            // 3 tapered branch beams fanning up-and-out from the crown.
            let branchMesh = ProceduralMesh.beam(length: 2.2, halfWidthNear: 0.22, halfWidthFar: 0.05)
            for k in 0..<3 {
                let b = ModelEntity(mesh: branchMesh, materials: [Self.mat(.brown)])
                let ang: Float = (Float(k) - 1) * 0.7        // -0.7, 0, +0.7 rad lean
                b.orientation = simd_quatf(angle: ang, axis: SIMD3<Float>(0, 0, 1))
                tr.canopyPivot.addChild(b)
                tr.parts.append(b)
            }

            // Canopy: flattened sphere (1, 0.7, 1) of soft pink crowning the branches.
            let canopy = ModelEntity(mesh: .generateSphere(radius: 1), materials: [Self.mat(.systemPink)])
            canopy.position = SIMD3<Float>(0, 1.9, 0)
            canopy.scale = SIMD3<Float>(2.6, 1.82, 2.6)      // (1, 0.7, 1) at scale 2.6
            tr.canopyPivot.addChild(canopy)
            tr.canopy = canopy

            tr.group.isEnabled = false
            root.addChild(tr.group)
            trunkParts.append(contentsOf: tr.parts)
            canopies.append(canopy)
            trees.append(tr)
        }

        // Lanterns.
        for _ in 0..<3 {
            let l = ModelEntity(mesh: disc, materials: [Self.mat(.orange)])
            l.isEnabled = false
            root.addChild(l)
            lanterns.append(Lantern(l))
        }

        // Petals.
        for _ in 0..<Self.petalCap {
            let p = ModelEntity(mesh: disc, materials: [Self.mat(.systemPink)])
            p.isEnabled = false
            root.addChild(p)
            petals.append(p)
        }
        petalX = .init(repeating: 0, count: Self.petalCap)
        petalTopY = .init(repeating: Self.skyTop, count: Self.petalCap)
        petalZ = .init(repeating: -42, count: Self.petalCap)
        petalFall = .init(repeating: 1, count: Self.petalCap)
        petalSway = .init(repeating: 1, count: Self.petalCap)
        petalPhase = .init(repeating: 0, count: Self.petalCap)
        petalTilt = .init(repeating: 0, count: Self.petalCap)
        petalScale = .init(repeating: 0.1, count: Self.petalCap)
    }

    // MARK: restyle (world boundary / Reduce-Motion flip — never per frame)

    func restyle(palette pal: WorldPalette, world: Int) {
        var r = SplitMix64(seed: 0xB100_FA11_0CA9_5E08 &+ UInt64(bitPattern: Int64(world)) &* 0x9E37_79B9_7F4A_7C15)

        // Colors mix toward bg so the grove reads as background; moon + lanterns are the brightest.
        let moonC = Self.lift(pal.accent2, 0.55)
        let haloC = Self.blend(pal, pal.accent2, 0.28)
        let hillC = Self.blend(pal, pal.grid, 0.30)
        let trunkC = Self.blend(pal, pal.grid, 0.40)
        let canopyC = Self.blend(pal, pal.accent, 0.50)
        let lanternC = Self.lift(pal.accent2, 0.40)
        let petalC = Self.blend(pal, pal.accent, 0.62)

        // Moon — large, high, static, off to one side; halo a touch wider behind it.
        let moonSide: Float = (world / Theme.worlds.count) % 2 == 0 ? -1 : 1
        let moonR = Float(r.range(2.8, 3.6))
        let moonPos = SIMD3<Float>(moonSide * Float(r.range(7, 12)), Float(r.range(13.5, 16.5)), -58)
        moon.scale = SIMD3<Float>(repeating: moonR)
        moon.position = moonPos
        moon.model?.materials = [Self.mat(moonC)]
        moonHalo.scale = SIMD3<Float>(repeating: moonR * 1.55)
        moonHalo.position = SIMD3<Float>(moonPos.x, moonPos.y, -58.6)
        moonHalo.model?.materials = [Self.mat(haloC)]

        // Hills — parked low so only the crest pokes above the lane horizon.
        hills.position = SIMD3<Float>(0, Float(r.range(-3.0, -1.5)), -50)
        hills.model?.materials = [Self.mat(hillC)]

        // Trees — spread across the sides/horizon, feet near the hill line, varied scale + sway.
        for i in trees.indices {
            let tr = trees[i]
            // Bias trees toward the edges so the lanes (centre) stay open.
            let edge: Float = i % 2 == 0 ? -1 : 1
            let x = edge * Float(r.range(8, 17))
            let scl = Float(r.range(0.9, 1.5))
            tr.group.position = SIMD3<Float>(x, Float(r.range(-3.2, -2.0)), Float(-48 - 3 * i))
            tr.group.scale = SIMD3<Float>(repeating: scl)
            tr.baseRoll = Float(r.range(-0.08, 0.08))
            tr.swaySpeed = Float(r.range(0.22, 0.40))
            tr.swayAmp = Float(r.range(0.04, 0.09))
            tr.phase = Float(r.range(0, 2 * .pi))
            tr.group.orientation = simd_quatf(angle: tr.baseRoll, axis: SIMD3<Float>(0, 0, 1))
            tr.canopyPivot.orientation = simd_quatf(angle: 0, axis: SIMD3<Float>(0, 0, 1))
            tr.group.isEnabled = true
        }
        for p in trunkParts { p.model?.materials = [Self.mat(trunkC)] }
        for c in canopies { c.model?.materials = [Self.mat(canopyC)] }

        // Lanterns — hung at varied heights mid-sky, between the trees.
        for i in lanterns.indices {
            let l = lanterns[i]
            let s = Float(r.range(0.4, 0.7))
            l.baseScale = s
            l.flickerSpeed = Float(r.range(1.4, 2.6))
            l.phase = Float(r.range(0, 2 * .pi))
            l.entity.position = SIMD3<Float>(Float(r.range(-15, 15)), Float(r.range(6.5, 12)), Float(r.range(-46, -40)))
            l.entity.scale = SIMD3<Float>(repeating: s)
            l.entity.model?.materials = [Self.mat(lanternC)]
            l.entity.isEnabled = true
        }

        // Petals — scattered across the sky band, each falling at its own rate with a wide sway.
        petalCount = min(Self.petalCap, 28 + 3 * (world / Theme.worlds.count))
        for (i, p) in petals.enumerated() {
            guard i < petalCount else { p.isEnabled = false; continue }
            petalX[i] = Float(r.range(-22, 22))
            petalTopY[i] = Float(r.range(Double(Self.skyFloor), Double(Self.skyTop)))    // staggered start within the band
            petalZ[i] = Float(r.range(-50, -38))
            petalFall[i] = Float(r.range(0.7, 1.5))
            petalSway[i] = Float(r.range(1.4, 2.8))
            petalPhase[i] = Float(r.range(0, 2 * .pi))
            petalTilt[i] = Float(r.range(0.5, 1.2))
            let s = Float(r.range(0.10, 0.20))
            petalScale[i] = s
            p.scale = SIMD3<Float>(s, s * 0.6, s)                       // petal-ish flattened disc
            p.position = SIMD3<Float>(petalX[i], petalTopY[i], petalZ[i])
            p.model?.materials = [Self.mat(petalC)]
            p.isEnabled = true
        }
    }

    // MARK: animate (transform + isEnabled only)

    func animate(elapsed: Double, reduceMotion: Bool) {
        if reduceMotion {
            for tr in trees {
                tr.canopyPivot.orientation = simd_quatf(angle: 0, axis: SIMD3<Float>(0, 0, 1))
            }
            for l in lanterns { l.entity.scale = SIMD3<Float>(repeating: l.baseScale) }
            for i in 0..<petalCount {
                petals[i].position = SIMD3<Float>(petalX[i], petalTopY[i], petalZ[i])
                petals[i].orientation = simd_quatf(angle: 0, axis: SIMD3<Float>(0, 0, 1))
            }
            return
        }
        let t = Float(elapsed)

        // Trees — canopy + branches sway gently about the crown.
        for tr in trees {
            let roll = sin(t * tr.swaySpeed + tr.phase) * tr.swayAmp
            tr.canopyPivot.orientation = simd_quatf(angle: roll, axis: SIMD3<Float>(0, 0, 1))
        }

        // Lanterns — soft scale-flicker around their base scale.
        for l in lanterns {
            let f = 1 + 0.10 * sin(t * l.flickerSpeed + l.phase)
            l.entity.scale = SIMD3<Float>(repeating: l.baseScale * f)
        }

        // Petals — drift DOWN with a wide lazy sway + slight tilt; wrap back to the top.
        for i in 0..<petalCount {
            let fallen = Double(petalFall[i]) * elapsed
            let span = Double(Self.skyTop - Self.skyFloor)
            var y = Double(petalTopY[i]) - fallen.truncatingRemainder(dividingBy: span)
            if y < Double(Self.skyFloor) { y += span }
            let yf = Float(y)
            let sway = sin(t * petalSway[i] * 0.5 + petalPhase[i]) * 1.6     // WIDE horizontal sway
            petals[i].position = SIMD3<Float>(petalX[i] + sway, yf, petalZ[i])
            petals[i].orientation = simd_quatf(angle: sin(t * petalTilt[i] + petalPhase[i]) * 0.6,
                                               axis: SIMD3<Float>(0, 0, 1))
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
