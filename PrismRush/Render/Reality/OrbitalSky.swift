import RealityKit
import simd
import UIKit

/// World 4 — "Orbital Drift": the first bespoke sky family (v1.5). A planet limb curves across the
/// low horizon, a tethered astronaut drifts and slowly tumbles mid-sky, a satellite or two glide
/// past with a blinking nav-light, and a deep starfield twinkles behind it all. Self-contained
/// (its own entities + build/restyle/animate) so `WorldSky` just enables it and forwards two calls
/// — the scalable shape every new world copies, keeping the shared file small.
///
/// Same invariants as the legacy families: geometry built ONCE at init and recycled; placement is
/// deterministic from a LOCAL `SplitMix64` seeded by the absolute world ordinal (never the run RNG —
/// rule 2); per-frame work is transform + `isEnabled` writes only (zero allocation); all motion is
/// subtle and Reduce-Motion-gated. Everything is procedural mesh + `UnlitMaterial` (rule 6).
@MainActor
final class OrbitalSky {
    let root = Entity()

    private static let starCap = 44

    // Planet limb (a big sphere mostly below the horizon) + its atmosphere glow disc.
    private var planet: ModelEntity!
    private var planetGlow: ModelEntity!
    private var planetBands: [ModelEntity] = []      // faint surface bands (discs clipped by the body)

    // Astronaut: a small entity tree that drifts + tumbles as one.
    private let astronaut = Entity()
    private var astroParts: [ModelEntity] = []       // every painted part (for retint)
    private var visor: ModelEntity!
    private var astroBase = SIMD3<Float>(0, 10, -34)
    private var tumbleAxis = SIMD3<Float>(0, 1, 0)

    // Satellites: box body + two wing panels + a blinking nav light.
    @MainActor private final class Sat {
        let group = Entity()
        var navLight: ModelEntity!
        var baseX: Float = 0, baseY: Float = 0, z: Float = 0
        var speed: Float = 0, phase: Double = 0, blink: Float = 0
    }
    private var sats: [Sat] = []
    private var satParts: [ModelEntity] = []

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

        // Planet limb — a large sphere; restyle parks it low so only its lit upper curve shows.
        planet = ModelEntity(mesh: .generateSphere(radius: 1), materials: [Self.mat(.black)])
        planetGlow = ModelEntity(mesh: disc, materials: [Self.mat(.black)])
        root.addChild(planetGlow)
        root.addChild(planet)
        for _ in 0..<2 {
            let band = ModelEntity(mesh: disc, materials: [Self.mat(.black)])
            band.isEnabled = false
            planet.addChild(band)
            planetBands.append(band)
        }

        buildAstronaut()
        root.addChild(astronaut)

        // Satellites.
        for _ in 0..<2 {
            let s = Sat()
            let body = ModelEntity(mesh: .generateBox(width: 0.5, height: 0.5, depth: 0.9, cornerRadius: 0.05),
                                   materials: [Self.mat(.gray)])
            let wingMesh = MeshResource.generateBox(width: 1.5, height: 0.04, depth: 0.5, cornerRadius: 0.01)
            let wingL = ModelEntity(mesh: wingMesh, materials: [Self.mat(.darkGray)])
            wingL.position = SIMD3<Float>(-1.05, 0, 0)
            let wingR = ModelEntity(mesh: wingMesh, materials: [Self.mat(.darkGray)])
            wingR.position = SIMD3<Float>(1.05, 0, 0)
            let nav = ModelEntity(mesh: ProceduralMesh.disc(radius: 0.12), materials: [Self.mat(.red)])
            nav.position = SIMD3<Float>(0, 0.32, 0.46)
            s.group.addChild(body); s.group.addChild(wingL); s.group.addChild(wingR); s.group.addChild(nav)
            s.navLight = nav
            s.group.isEnabled = false
            root.addChild(s.group)
            satParts.append(contentsOf: [body, wingL, wingR])   // nav light keeps its fixed warning tint
            sats.append(s)
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
        starZ = .init(repeating: -55, count: Self.starCap)
        starTwinkle = .init(repeating: 1, count: Self.starCap)
        starPhase = .init(repeating: 0, count: Self.starCap)
        starScale = .init(repeating: 0.1, count: Self.starCap)
    }

    /// Astronaut entity tree — helmet sphere + tinted visor disc, box torso/backpack, four box
    /// limbs. Parts list drives retint; the whole group drifts + tumbles in `animate`.
    private func buildAstronaut() {
        func box(_ w: Float, _ h: Float, _ d: Float, _ pos: SIMD3<Float>) -> ModelEntity {
            let e = ModelEntity(mesh: .generateBox(width: w, height: h, depth: d, cornerRadius: 0.04),
                                materials: [Self.mat(.white)])
            e.position = pos
            astronaut.addChild(e)
            astroParts.append(e)
            return e
        }
        let helmet = ModelEntity(mesh: .generateSphere(radius: 0.5), materials: [Self.mat(.white)])
        helmet.position = SIMD3<Float>(0, 0.95, 0)
        astronaut.addChild(helmet); astroParts.append(helmet)
        visor = ModelEntity(mesh: ProceduralMesh.disc(radius: 0.32), materials: [Self.mat(.black)])
        visor.position = SIMD3<Float>(0, 0.98, 0.46)        // on the helmet front, facing camera
        helmet.addChild(visor)                              // rides the helmet, not retinted as a body part
        _ = box(0.78, 0.95, 0.5, SIMD3<Float>(0, 0.1, 0))   // torso
        _ = box(0.55, 0.4, 0.3, SIMD3<Float>(0, 0.15, -0.42)) // backpack
        _ = box(0.26, 0.7, 0.26, SIMD3<Float>(-0.56, 0.18, 0)) // left arm
        _ = box(0.26, 0.7, 0.26, SIMD3<Float>(0.56, 0.18, 0))  // right arm
        _ = box(0.3, 0.7, 0.3, SIMD3<Float>(-0.22, -0.62, 0))  // left leg
        _ = box(0.3, 0.7, 0.3, SIMD3<Float>(0.22, -0.62, 0))   // right leg
        astronaut.scale = SIMD3<Float>(repeating: 1.6)
    }

    // MARK: restyle (world boundary / Reduce-Motion flip — never per frame)

    func restyle(palette pal: WorldPalette, world: Int) {
        var r = SplitMix64(seed: 0x0_4B17A1 &+ UInt64(bitPattern: Int64(world)) &* 0x9E37_79B9_7F4A_7C15)

        // Colors mix toward bg so the layer reads as background; the astronaut is the brightest thing.
        let planetC = Self.blend(pal, pal.grid, 0.42)
        let glowC = Self.blend(pal, pal.accent, 0.22)
        let bandC = Self.blend(pal, pal.accent, 0.34)
        let suitC = Self.lift(pal.accent2, 0.30)
        let visorC = Self.blend(pal, pal.accent, 0.55)
        let satC = Self.blend(pal, pal.accent, 0.38)
        let starC = Self.lift(pal.accent, 0.35)

        // Planet limb: large, parked low on one horizon side so only the upper curve shows.
        let side: Float = (world / Theme.worlds.count) % 2 == 0 ? -1 : 1   // alternate side per cycle
        let pr = Float(r.range(9, 12))
        planet.scale = SIMD3<Float>(repeating: pr)
        planet.position = SIMD3<Float>(side * Float(r.range(6, 11)), Float(r.range(-7.5, -5.5)), -60)
        planet.model?.materials = [Self.mat(planetC)]
        planetGlow.scale = SIMD3<Float>(repeating: pr * 1.18)
        planetGlow.position = SIMD3<Float>(planet.position.x, planet.position.y, -60.6)
        planetGlow.model?.materials = [Self.mat(glowC)]
        for (i, b) in planetBands.enumerated() {
            b.isEnabled = true
            b.scale = SIMD3<Float>(1, Float(r.range(0.10, 0.18)), 1)        // thin band across the sphere
            b.position = SIMD3<Float>(0, Float(r.range(0.1, 0.5)) * (i == 0 ? 1 : -1), 1.001)
            b.model?.materials = [Self.mat(bandC)]
        }

        // Astronaut: mid-sky, off to the side opposite the planet, facing roughly camera.
        astroBase = SIMD3<Float>(-side * Float(r.range(3.5, 7.5)), Float(r.range(8.5, 12)), Float(r.range(-36, -30)))
        astronaut.position = astroBase
        tumbleAxis = simd_normalize(SIMD3<Float>(Float(r.range(-1, 1)), Float(r.range(0.3, 1)), Float(r.range(-0.4, 0.4))))
        for p in astroParts { p.model?.materials = [Self.mat(suitC)] }
        visor.model?.materials = [Self.mat(visorC)]

        // Satellites.
        for i in sats.indices {
            sats[i].baseX = Float(r.range(-12, 12))
            sats[i].baseY = Float(r.range(12.5, 16.5))
            sats[i].z = Float(-50 - 4 * Float(i)) - Float(r.range(0, 3))
            sats[i].speed = Float(r.range(0.18, 0.34)) * (i % 2 == 0 ? 1 : -1)
            sats[i].phase = r.range(0, 60)
            sats[i].blink = Float(r.range(0.7, 1.3))
            sats[i].group.position = SIMD3<Float>(sats[i].baseX, sats[i].baseY, sats[i].z)
            sats[i].group.orientation = simd_quatf(angle: Float(r.range(-0.4, 0.4)), axis: SIMD3<Float>(0, 0, 1))
        }
        for p in satParts { p.model?.materials = [Self.mat(satC)] }

        // Starfield — scattered across the upper sky, parked at their twinkle base.
        starCount = min(Self.starCap, 30 + 3 * (world / Theme.worlds.count))
        for (i, st) in stars.enumerated() {
            guard i < starCount else { st.isEnabled = false; continue }
            starBaseX[i] = Float(r.range(-24, 24))
            starBaseY[i] = Float(r.range(5.5, 18))
            starZ[i] = Float(r.range(-62, -48))
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
            astronaut.position = astroBase
            astronaut.orientation = simd_quatf(angle: 0.3, axis: tumbleAxis)
            for i in sats.indices {
                sats[i].group.position = SIMD3<Float>(sats[i].baseX, sats[i].baseY, sats[i].z)
                sats[i].navLight?.isEnabled = true
            }
            return
        }
        let t = Float(elapsed)
        // Astronaut: gentle weightless drift + a slow continuous tumble.
        astronaut.position = astroBase + SIMD3<Float>(sin(t * 0.13) * 1.1,
                                                       sin(t * 0.17 + 1) * 0.8,
                                                       sin(t * 0.11) * 0.6)
        astronaut.orientation = simd_quatf(angle: t * 0.22, axis: tumbleAxis)
        // Satellites: drift across and wrap; nav light blinks.
        for i in sats.indices {
            let x = Self.wrap(Double(sats[i].baseX) + (elapsed + sats[i].phase) * Double(sats[i].speed), span: 46)
            sats[i].group.position = SIMD3<Float>(Float(x),
                                                  sats[i].baseY + sin(t * 0.2 + Float(i) * 2.1) * 0.3,
                                                  sats[i].z)
            let on = sin(t * sats[i].blink * 3.0 + Float(i)) > 0
            if sats[i].navLight?.isEnabled != on { sats[i].navLight?.isEnabled = on }
        }
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

    private static func wrap(_ v: Double, span: Double) -> Double {
        var w = v.truncatingRemainder(dividingBy: span)
        if w < 0 { w += span }
        return w - span / 2
    }
}
