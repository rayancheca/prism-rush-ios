import RealityKit
import simd
import UIKit

/// World 4 — "Tidal Glow": a bioluminescent deep-ocean trench (v1.5). Two or three jellyfish hang
/// mid-sky — domed bell (flattened sphere) ringed by a torus rim, a bright core disc glowing inside,
/// and a fan of tentacle strips swaying beneath — drifting up and down while the bell scale-pulses.
/// A couple of very dim light shafts rake down from the surface, a slow cloud of plankton motes
/// rises through the water, and a low seabed ridge sits on the horizon. Self-contained (its own
/// entities + build/restyle/animate) so `WorldSky` just enables it and forwards two calls.
///
/// Same invariants as the other sky families: geometry built ONCE at init and recycled; placement is
/// deterministic from a LOCAL `SplitMix64` seeded by the absolute world ordinal (never the run RNG —
/// rule 2); per-frame work is transform + `isEnabled` writes only (zero allocation); all motion is
/// subtle and Reduce-Motion-gated. Everything is procedural mesh + `UnlitMaterial` (rule 6).
@MainActor
final class TidalSky {
    let root = Entity()

    private static let planktonCap = 32

    // Jellyfish: a small entity tree (bell + rim + core + tentacle fan) that bobs + pulses as one.
    @MainActor private final class Jelly {
        let group = Entity()
        let bell = Entity()                 // holds the dome + rim + core so the pulse scales them together
        var dome: ModelEntity!
        var core: ModelEntity!
        var baseY: Float = 0
        var phase: Float = 0
        var bobAmp: Float = 0
        var bobRate: Float = 0
        var pulseRate: Float = 0
    }
    private var jellies: [Jelly] = []
    private var jellyParts: [ModelEntity] = []     // bell domes + rims (retint to accent2/accent)
    private var jellyCores: [ModelEntity] = []     // inner glow discs (retint to accent)
    private var tentacles: [ModelEntity] = []      // every tentacle strip (retint to bell colour, dimmer)

    // Light shafts: thin beams raking down from the surface (very dim).
    private var shafts: [ModelEntity] = []

    // Seabed: a low dim ridge near the horizon.
    private var seabed: ModelEntity!

    // Plankton (shared disc mote pattern) — slow rising glints.
    private var plankton: [ModelEntity] = []
    private var planktonBaseX: [Float] = [], planktonBaseY: [Float] = [], planktonZ: [Float] = []
    private var planktonRise: [Float] = [], planktonSpan: [Float] = []
    private var planktonTwinkle: [Float] = [], planktonPhase: [Float] = [], planktonScale: [Float] = []
    private var planktonCount = 0

    init(parent: Entity) {
        build()
        root.isEnabled = false
        parent.addChild(root)
    }

    // MARK: build (once)

    private func build() {
        let disc = ProceduralMesh.disc()

        // Three jellyfish (restyle enables the count it wants).
        for _ in 0..<3 {
            let j = Jelly()
            // Bell dome: a sphere flattened on Y so it reads as an upturned bowl.
            let dome = ModelEntity(mesh: .generateSphere(radius: 1), materials: [Self.mat(.white)])
            dome.scale = SIMD3<Float>(1, 0.6, 1)
            j.dome = dome
            j.bell.addChild(dome)
            jellyParts.append(dome)
            // Rim torus hugging the bell edge (lies in XY, hole faces +Z — tilt it flat under the bell).
            let rim = ModelEntity(mesh: ProceduralMesh.torus(major: 1.0, minor: 0.06), materials: [Self.mat(.white)])
            rim.orientation = simd_quatf(angle: .pi / 2, axis: SIMD3<Float>(1, 0, 0))   // lay it horizontal
            rim.position = SIMD3<Float>(0, -0.18, 0)
            j.bell.addChild(rim)
            jellyParts.append(rim)
            // Bright core disc glowing inside the bell, facing the camera.
            let core = ModelEntity(mesh: ProceduralMesh.disc(radius: 0.42), materials: [Self.mat(.white)])
            core.position = SIMD3<Float>(0, -0.05, 0.18)
            j.core = core
            j.bell.addChild(core)
            jellyCores.append(core)
            j.group.addChild(j.bell)
            // Tentacle fan: 5 strips hung straight down, fanned radially about Y + a slight forward tilt.
            let tentMesh = ProceduralMesh.tentacleStrip(length: 3, width: 0.25, amplitude: 0.5)
            for k in 0..<5 {
                let t = ModelEntity(mesh: tentMesh, materials: [Self.mat(.white)])
                t.position = SIMD3<Float>(0, -0.4, 0)
                let yaw = Float(k) / 5 * 2 * .pi
                t.orientation = simd_quatf(angle: yaw, axis: SIMD3<Float>(0, 1, 0))
                    * simd_quatf(angle: 0.18, axis: SIMD3<Float>(1, 0, 0))   // lean the fan toward camera
                j.bell.addChild(t)
                tentacles.append(t)
            }
            j.group.isEnabled = false
            root.addChild(j.group)
            jellies.append(j)
        }

        // Light shafts — thin trapezoids fanning DOWN (built fanning +Y, flipped via orientation).
        for _ in 0..<3 {
            let shaft = ModelEntity(mesh: ProceduralMesh.beam(length: 9, halfWidthNear: 0.1, halfWidthFar: 1.2),
                                    materials: [Self.mat(.white)])
            shaft.isEnabled = false
            root.addChild(shaft)
            shafts.append(shaft)
        }

        // Seabed ridge — a low silhouette band near the horizon (heights filled at restyle scale).
        let heights: [Float] = (0..<16).map { i in 1.0 + 0.6 * sin(Float(i) * 0.9) + 0.3 * sin(Float(i) * 2.3) }
        seabed = ModelEntity(mesh: ProceduralMesh.ridge(width: 70, heights: heights), materials: [Self.mat(.black)])
        root.addChild(seabed)

        // Plankton.
        for _ in 0..<Self.planktonCap {
            let p = ModelEntity(mesh: disc, materials: [Self.mat(.white)])
            p.isEnabled = false
            root.addChild(p)
            plankton.append(p)
        }
        planktonBaseX = .init(repeating: 0, count: Self.planktonCap)
        planktonBaseY = .init(repeating: 0, count: Self.planktonCap)
        planktonZ = .init(repeating: -52, count: Self.planktonCap)
        planktonRise = .init(repeating: 0.3, count: Self.planktonCap)
        planktonSpan = .init(repeating: 10, count: Self.planktonCap)
        planktonTwinkle = .init(repeating: 1, count: Self.planktonCap)
        planktonPhase = .init(repeating: 0, count: Self.planktonCap)
        planktonScale = .init(repeating: 0.1, count: Self.planktonCap)
    }

    // MARK: restyle (world boundary / Reduce-Motion flip — never per frame)

    func restyle(palette pal: WorldPalette, world: Int) {
        var r = SplitMix64(seed: 0x0_71DA_7C13 &+ UInt64(bitPattern: Int64(world)) &* 0x9E37_79B9_7F4A_7C15)

        // Colours mix toward bg so the layer reads as background; jellyfish bells are the brightest thing.
        let bellC = Self.lift(pal.accent2, 0.28)               // violet bells, lifted
        let bellAltC = Self.lift(pal.accent, 0.30)             // some bells teal instead
        let coreC = Self.lift(pal.accent, 0.45)                // bright teal core glow
        let tentC = Self.blend(pal, pal.accent2, 0.45)         // tentacles dimmer than the bell
        let shaftC = Self.blend(pal, pal.accent, 0.12)         // very dim light shafts
        let bedC = Self.blend(pal, pal.grid, 0.30)             // dim teal seabed

        // Jellyfish — scattered across the upper sky at varied depth. Count grows slightly per cycle.
        let jellyCount = min(3, 2 + (world / Theme.worlds.count) % 2)
        for (i, j) in jellies.enumerated() {
            guard i < jellyCount else { j.group.isEnabled = false; continue }
            let side: Float = (i % 2 == 0) ? -1 : 1
            let x = side * Float(r.range(3.5, 13))
            j.baseY = Float(r.range(8.5, 15))
            let z = Float(r.range(-50, -38))
            j.group.position = SIMD3<Float>(x, j.baseY, z)
            let scale = Float(r.range(1.7, 2.7))
            j.group.scale = SIMD3<Float>(repeating: scale)
            j.phase = Float(r.range(0, 2 * .pi))
            j.bobAmp = Float(r.range(0.5, 1.1))
            j.bobRate = Float(r.range(0.12, 0.22))
            j.pulseRate = Float(r.range(0.5, 0.9))
            // Alternate bell tint so the school isn't uniform; cores stay bright teal.
            let useAlt = r.unit() < 0.4
            j.dome.model?.materials = [Self.mat(useAlt ? bellAltC : bellC)]
            j.core.model?.materials = [Self.mat(coreC)]
            j.group.isEnabled = true
        }
        // Rims share the bell tints — retint every bell part (domes + rims) in one pass keeps it simple:
        // domes were just set above, so only repaint rims (the odd entries weren't touched). Simpler to
        // paint all jellyParts to the primary bell colour, then re-bright the active domes' cores.
        for (k, part) in jellyParts.enumerated() where k % 2 == 1 {   // rims are the 2nd part per jelly
            part.model?.materials = [Self.mat(bellC)]
        }
        for t in tentacles { t.model?.materials = [Self.mat(tentC)] }

        // Light shafts — angled down from the top, raking across the sky. Built fanning +Y, so flip ~π.
        for (i, shaft) in shafts.enumerated() {
            let sx = Float(r.range(-16, 16))
            let topY = Float(r.range(16, 20))
            shaft.position = SIMD3<Float>(sx, topY, Float(r.range(-58, -50)))
            // Point the beam DOWNWARD with a slight slant.
            let tilt = Float(r.range(-0.22, 0.22))
            shaft.orientation = simd_quatf(angle: .pi + tilt, axis: SIMD3<Float>(0, 0, 1))
            shaft.model?.materials = [Self.mat(shaftC)]
            shaft.isEnabled = i < 2 + (world / Theme.worlds.count) % 2
        }

        // Seabed — a low dim ridge whose crest peeks above the horizon; most of it sits below y = 0.
        seabed.position = SIMD3<Float>(0, Float(r.range(-2.0, -0.5)), -56)
        seabed.scale = SIMD3<Float>(1, Float(r.range(2.2, 3.2)), 1)
        seabed.model?.materials = [Self.mat(bedC)]

        // Plankton — a slow rising cloud through the water column.
        planktonCount = min(Self.planktonCap, 26 + 3 * (world / Theme.worlds.count))
        let planktonC = Self.lift(pal.accent, 0.4)
        for (i, p) in plankton.enumerated() {
            guard i < planktonCount else { p.isEnabled = false; continue }
            planktonBaseX[i] = Float(r.range(-22, 22))
            planktonBaseY[i] = Float(r.range(4, 16))
            planktonZ[i] = Float(r.range(-58, -44))
            planktonRise[i] = Float(r.range(0.18, 0.45))
            planktonSpan[i] = Float(r.range(8, 16))
            planktonTwinkle[i] = Float(r.range(0.5, 1.2))
            planktonPhase[i] = Float(r.range(0, 2 * .pi))
            let s = Float(r.range(0.05, 0.13))
            planktonScale[i] = s
            p.scale = SIMD3<Float>(repeating: s)
            p.position = SIMD3<Float>(planktonBaseX[i], planktonBaseY[i], planktonZ[i])
            p.model?.materials = [Self.mat(planktonC)]
            p.isEnabled = true
        }
    }

    // MARK: animate (transform + isEnabled only)

    func animate(elapsed: Double, reduceMotion: Bool) {
        if reduceMotion {
            for j in jellies {
                j.group.position.y = j.baseY
                j.bell.scale = SIMD3<Float>(repeating: 1)
            }
            return
        }
        let t = Float(elapsed)
        // Jellyfish: gentle vertical bob + a slow bell scale-pulse (tentacles ride the bell, sway baked).
        for j in jellies {
            j.group.position.y = j.baseY + sin(t * j.bobRate + j.phase) * j.bobAmp
            let pulse = 1 + 0.07 * sin(t * j.pulseRate + j.phase)
            j.bell.scale = SIMD3<Float>(pulse, 1 / pulse, pulse)   // squash-and-stretch keeps volume
        }
        // Plankton: rise slowly and wrap; gentle twinkle modulates each mote's base scale.
        for i in 0..<planktonCount {
            let y = planktonBaseY[i]
                + Float(Self.wrap(Double(elapsed) * Double(planktonRise[i]) + Double(planktonPhase[i]),
                                  span: Double(planktonSpan[i])))
            plankton[i].position.y = y
            let tw = 0.6 + 0.4 * sin(t * planktonTwinkle[i] + planktonPhase[i])
            plankton[i].scale = SIMD3<Float>(repeating: max(0.02, planktonScale[i] * tw))
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
