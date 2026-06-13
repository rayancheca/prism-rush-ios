import RealityKit
import simd
import UIKit

/// Side-of-track scenery that defines each world's silhouette: emissive towers (Metropolis),
/// floating crystals (Caverns), pyramids (Sands) — plus a rarer alternate per world (stacked
/// spire / stalagmite cluster / obelisk) for variety. Slots scroll toward the camera and, when
/// they pass behind it, jump back to the horizon **re-styled for the current world** — so a new
/// world's decor visibly arrives toward the player rather than popping in around them.
/// v1.4 adds `WorldSky` (below), the far-background atmosphere layer, owned and driven from here.
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
    private let sky: WorldSky

    init(root: Entity) {
        towerMesh = .generateBox(width: 2.4, height: 6, depth: 2.4, cornerRadius: 0.05)
        crystalMesh = .generateCone(height: 5, radius: 1.2)
        pyramidMesh = ProceduralMesh.pyramid(halfBase: 1.9, height: 4)
        sky = WorldSky(root: root)

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

    func update(distance: Double, world: Int, elapsed: Double, reduceMotion: Bool) {
        sky.update(distance: distance, world: world, elapsed: elapsed, reduceMotion: reduceMotion)
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
        let n = Theme.worlds.count
        if ((world % n) + n) % n == 3 {   // Orbital Drift: clear space at the sides — the sky carries it
            for e in [s.tower, s.crystal, s.pyramid, s.altA, s.altB] { e.isEnabled = false }
            s.floating = false
            return
        }
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
        // Evolved by the ABSOLUTE world (not the 0–2 family `w`) so side decor hue-shifts with the
        // cycle in lockstep with the playfield palette (v1.4.3).
        let tint = Self.dim(Theme.evolvedPalette(ordinal: world).accent2)
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

/// Far-background sky + atmosphere — what makes each palette family unmistakably ITS world in a
/// single frame (v1.4 owner directive): Metropolis gets a two-depth skyline with blinking
/// windows, drifting blimps and searchlight sweeps; Caverns a stalactite ceiling, rotating
/// crystal clusters, rising glow motes and a horizon aurora; Sands floating ringed planets, a
/// low sun with a layered halo, dune silhouettes and heat-shimmer motes.
///
/// Everything is prebuilt ONCE at init and recycled by `restyle` — the sky analog of the slot
/// pool above. Pool caps (one family enabled at a time):
///   Metropolis 32 models · Caverns 46 · Sands 25  (≤ 46 ever visible at once).
/// The identity swap is hard and lands on the exact frame `worldTo` flips — the same beat the
/// lane lines flare toward white and the horizon ring sweep fires, so the new sky reads as part
/// of the arrival flourish (the backdrop-distance counterpart of the horizon slot swap).
/// Placement is deterministic: a LOCAL SplitMix64 seeded from the absolute world index — never
/// the run RNG (rule 2 safe) — so world 7 looks like world 7 in every run, and the cycle index
/// (world / 3) folds into element counts so deep runs feel progressively richer. Materials are
/// fixed per family and built once here; colors mix toward the family bg so the layer always
/// reads as background, never competing with obstacles. Per-frame work is transform writes and
/// `isEnabled` flips only — zero allocation. All motion is subtle and Reduce Motion-gated; under
/// RM the full set piece stays, statically placed.
@MainActor
final class WorldSky {
    // Pool caps (counts ramp with the cycle index, clamped to these).
    private static let capWindows = 22, capBlimps = 2, capBeams = 2
    private static let capStalactites = 13, capClusters = 4, capCaveMotes = 18
    private static let capPlanets = 3, capSandMotes = 14

    // One root per palette family — exactly one enabled after the first update. Stored array
    // (not computed) so per-frame access never allocates.
    private let metroRoot = Entity()
    private let cavernRoot = Entity()
    private let sandsRoot = Entity()
    /// Bespoke v1.5 families live in their own self-contained objects (own entities + build/restyle/
    /// animate); `WorldSky` enables their root and forwards two calls. Their root joins `famRoots` so
    /// the enable/entrance/Reduce-Motion plumbing is shared. New worlds append here, one per file.
    private let orbitalSky: OrbitalSky
    private let famRoots: [Entity]

    // Per-cycle re-tint registry (v1.4.3): every sky element pairs with a recipe that derives its
    // color from a `WorldPalette`. At each world boundary `restyle` recolors the active family
    // toward `Theme.evolvedPalette(ordinal:)`, so deep cycles' set pieces hue-shift in lockstep
    // with the playfield (the renderer backdrop already evolves) instead of staying base-family
    // cyan against a rotated sky. Built once, applied only at restyle — never per frame.
    private typealias TintRecipe = (entity: ModelEntity, color: (WorldPalette) -> UIColor)
    private var famTints: [[TintRecipe]] = [[], [], []]

    private var lastWorld = -1
    private var lastRM = false
    private var swapAt: Double = -10        // entrance ease start (the new sky rises ~1 unit in)

    // Shared upward-drifting mote field (Sands heat shimmer / Caverns glow motes).
    private struct Motes {
        var ents: [ModelEntity] = []
        var baseX: [Float] = [], baseY: [Float] = [], z: [Float] = []
        var rise: [Float] = [], span: [Float] = [], sway: [Float] = [], phase: [Float] = []
        var active = 0
    }

    // -- Metropolis state
    private var farCard: ModelEntity!
    private var nearCard: ModelEntity!
    private var farBuildings: [SIMD2<Float>] = []    // (width, height) — window anchors, far row
    private var farX: [Float] = []                   // building left edges (card-local)
    private var nearBuildings: [SIMD2<Float>] = []   // (width, height) — window/beam anchors
    private var nearX: [Float] = []                  // building left edges (card-local)
    private var windows: [ModelEntity] = []          // first `windowsOnFar` parented to the far card
    private var windowPhase: [Float] = [], windowSpeed: [Float] = []
    private var windowCount = 0
    private static let windowsOnFar = 8              // far row is TALLER — its lights fill the sky band
    private var blimps: [Entity] = []
    private var blimpBaseX: [Float] = [], blimpBaseY: [Float] = [], blimpZ: [Float] = []
    private var blimpSpeed: [Float] = [], blimpPhase: [Double] = []
    private var blimpCount = 0
    private var beams: [ModelEntity] = []
    private var beamLean: [Float] = [], beamPhase: [Float] = []
    private var beamCount = 0

    // -- Caverns state
    private var ceiling: ModelEntity!
    private var stalactites: [ModelEntity] = []
    private var stalactiteCount = 0
    private var clusters: [Entity] = []
    private var clusterSpin: [Float] = [], clusterPhase: [Float] = [], clusterBaseY: [Float] = []
    private var clusterCount = 0
    private var caveMotes = Motes()
    private var auroras: [ModelEntity] = []
    private var auroraBaseX: [Float] = [0, 0]

    // -- Sands state
    private var sunCore: ModelEntity!
    private var sunHalo1: ModelEntity!
    private var sunHalo2: ModelEntity!
    private var planets: [Entity] = []
    private var planetRings: [ModelEntity] = []
    private var planetBaseX: [Float] = [], planetBaseY: [Float] = [], planetZ: [Float] = []
    private var planetPar: [Float] = [], planetPhase: [Float] = []
    private var planetCount = 0
    private var dunes: [ModelEntity] = []
    private var sandMotes = Motes()

    init(root: Entity) {
        orbitalSky = OrbitalSky(parent: root)   // adds + disables its own root
        famRoots = [metroRoot, cavernRoot, sandsRoot, orbitalSky.root]
        let disc = ProceduralMesh.disc()
        buildMetropolis(disc: disc)
        buildCaverns(disc: disc)
        buildSands(disc: disc)
        for r in [metroRoot, cavernRoot, sandsRoot] { r.isEnabled = false; root.addChild(r) }
    }

    /// Map an absolute world ordinal to its sky-family index in `famRoots`. Bespoke worlds (v1.5)
    /// get their own index; everything else folds to the legacy 3-family stub (recolored to the
    /// world's palette) until its motif ships. Worlds 12+ reuse the authored families in step with
    /// the palette cycle.
    private func skyFamily(_ world: Int) -> Int {
        let n = Theme.worlds.count
        switch ((world % n) + n) % n {
        case 3:  return 3                       // Orbital Drift — bespoke
        default: return ((world % 3) + 3) % 3   // legacy stub families
        }
    }

    // MARK: per-frame

    func update(distance: Double, world: Int, elapsed: Double, reduceMotion: Bool) {
        if world != lastWorld {
            lastWorld = world
            let fam = skyFamily(world)
            for (i, r) in famRoots.enumerated() { r.isEnabled = i == fam }
            restyle(world: world)
            swapAt = elapsed
        } else if reduceMotion != lastRM {
            restyle(world: world)   // snap every element back to its static base pose
        }
        lastRM = reduceMotion

        let fam = skyFamily(lastWorld)
        let active = famRoots[fam]
        if reduceMotion {
            if active.position.y != 0 { active.position.y = 0 }
            if fam == 3 { orbitalSky.animate(elapsed: elapsed, reduceMotion: true) }
            return                  // statics only — restyle already posed everything
        }
        // Entrance: the incoming sky rises ~1 unit over 0.7 s, folded into the crossfade flare.
        let f = Float(max(0, (0.7 - (elapsed - swapAt)) / 0.7))
        active.position.y = -1.1 * f * f

        let t = Float(elapsed)
        switch fam {
        case 0:  animateMetropolis(t: t, elapsed: elapsed)
        case 1:  animateCaverns(t: t)
        case 2:  animateSands(t: t, distance: distance)
        case 3:  orbitalSky.animate(elapsed: elapsed, reduceMotion: false)
        default: break   // unreachable — every family has an explicit case (no silent mis-map)
        }
    }

    private func animateMetropolis(t: Float, elapsed: Double) {
        for i in 0..<windowCount {                  // slow deterministic blink (off ~12% of period)
            let on = sin(t * windowSpeed[i] + windowPhase[i]) > -0.78
            if windows[i].isEnabled != on { windows[i].isEnabled = on }
        }
        for i in 0..<blimpCount {
            let x = Self.wrap(Double(blimpBaseX[i]) + (elapsed + blimpPhase[i]) * Double(blimpSpeed[i]), span: 46)
            blimps[i].position = SIMD3<Float>(Float(x),
                                              blimpBaseY[i] + sin(t * 0.21 + Float(i) * 2.6) * 0.4,
                                              blimpZ[i])
        }
        for i in 0..<beamCount {                    // ~15 s sweep period — occasional, readable
            let a = beamLean[i] + sin(t * 0.42 + beamPhase[i]) * 0.5
            beams[i].orientation = simd_quatf(angle: a, axis: SIMD3<Float>(0, 0, 1))
        }
    }

    private func animateCaverns(t: Float) {
        for i in 0..<clusterCount {
            clusters[i].orientation = simd_quatf(angle: t * clusterSpin[i] + clusterPhase[i],
                                                 axis: SIMD3<Float>(0, 1, 0))
            clusters[i].position.y = clusterBaseY[i] + sin(t * 0.3 + clusterPhase[i]) * 0.35
        }
        animateMotes(caveMotes, t: t)
        for (i, a) in auroras.enumerated() {        // amplitude breathes; the band slides slowly
            a.scale.y = 1 + 0.16 * sin(t * 0.33 + Float(i) * 2.1)
            a.position.x = auroraBaseX[i] + sin(t * 0.05 + Float(i)) * 2.5
        }
    }

    private func animateSands(t: Float, distance: Double) {
        for i in 0..<planetCount {                  // deeper planets parallax slower, all wrap offscreen
            let x = Self.wrap(Double(planetBaseX[i]) - distance * Double(planetPar[i]), span: 68)
            planets[i].position = SIMD3<Float>(Float(x),
                                               planetBaseY[i] + sin(t * 0.09 + planetPhase[i]) * 0.4,
                                               planetZ[i])
        }
        animateMotes(sandMotes, t: t)
    }

    private func animateMotes(_ m: Motes, t: Float) {
        for i in 0..<m.active {
            let y = m.baseY[i] + fmodf(m.phase[i] + t * m.rise[i], m.span[i])
            m.ents[i].position = SIMD3<Float>(m.baseX[i] + sin(t * 0.5 + m.phase[i]) * m.sway[i], y, m.z[i])
        }
    }

    // MARK: restyle (world boundary / Reduce Motion flip — never per frame)

    private func restyle(world: Int) {
        // Deterministic per ABSOLUTE world index: every visit to world n looks identical across
        // runs, every cycle varies, and the run RNG is never consumed (rule 2 safe).
        let fam = skyFamily(world)
        let pal = Theme.evolvedPalette(ordinal: world)
        if fam == 3 {                                 // bespoke family owns its own placement + tint
            orbitalSky.restyle(palette: pal, world: world)
            famRoots[fam].position.y = 0
            return
        }
        retint(fam, pal)                              // v1.4.3: hue-shift set pieces per cycle
        var r = SplitMix64(seed: 0x5B1E_55ED &+ UInt64(bitPattern: Int64(world)) &* 0x9E37_79B9_7F4A_7C15)
        let cycle = world / Theme.worlds.count        // cycle 0 for worlds 0–11 (stub at base density)
        switch fam {
        case 0:  restyleMetropolis(&r, cycle: cycle)
        case 1:  restyleCaverns(&r, cycle: cycle)
        default: restyleSands(&r, cycle: cycle)
        }
        famRoots[fam].position.y = 0
    }

    /// Register a sky element so `restyle` can recolor it toward the cycle's evolved palette.
    private func register(_ e: ModelEntity, fam: Int, _ recipe: @escaping (WorldPalette) -> UIColor) {
        famTints[fam].append((e, recipe))
    }

    /// Recolor every registered element of `fam` toward `pal` — runs only at a world boundary.
    private func retint(_ fam: Int, _ pal: WorldPalette) {
        for t in famTints[fam] { t.entity.model?.materials = [UnlitMaterial(color: t.color(pal))] }
    }

    private func restyleMetropolis(_ r: inout SplitMix64, cycle: Int) {
        let farCardX = Float(r.range(-5, 5))
        farCard.position.x = farCardX
        let cardX = Float(r.range(-5, 5))
        nearCard.position.x = cardX
        // The portrait camera only sees |x| ≲ 17 at skyline depth — concentrate every light and
        // set piece on the buildings inside that band (in WORLD space, so a card's own offset
        // can't push a side of the street dark) or the density reads as two lonely dots.
        var eligible: [Int] = []          // near row (window/beam anchors)
        for (b, bld) in nearBuildings.enumerated() where abs(nearX[b] + bld.x / 2 + cardX) < 15 {
            eligible.append(b)
        }
        var eligibleFar: [Int] = []       // far row — taller, so its lights sit up in the sky band
        for (b, bld) in farBuildings.enumerated() where abs(farX[b] + bld.x / 2 + farCardX) < 15 {
            eligibleFar.append(b)
        }
        // Counts ramp with the cycle to the pool cap; past the cap, deep worlds keep diverging via
        // the per-cycle re-tint (`retint`) rather than ever-denser geometry (v1.4.3).
        windowCount = min(Self.capWindows, 16 + 3 * cycle)
        for (i, w) in windows.enumerated() {
            guard i < windowCount else { w.isEnabled = false; continue }
            let far = i < Self.windowsOnFar
            let b: Int
            if far {
                // Tournament pick: the taller of two candidates — far lights must clear the
                // near row's rooflines to actually show against the sky.
                let c0 = eligibleFar[r.int(0, eligibleFar.count - 1)]
                let c1 = eligibleFar[r.int(0, eligibleFar.count - 1)]
                b = farBuildings[c0].y >= farBuildings[c1].y ? c0 : c1
            } else {
                b = eligible[r.int(0, eligible.count - 1)]
            }
            let bld = far ? farBuildings[b] : nearBuildings[b]
            // Bias toward the upper façade — that's the band that reads against the sky.
            w.position = SIMD3<Float>((far ? farX[b] : nearX[b]) + bld.x * Float(r.range(0.18, 0.82)),
                                      bld.y * Float(far ? r.range(0.5, 0.92) : r.range(0.35, 0.9)), 0.3)
            w.scale = SIMD3<Float>(repeating: Float(far ? r.range(0.20, 0.28) : r.range(0.17, 0.26)))
            windowPhase[i] = Float(r.range(0, 2 * .pi))
            windowSpeed[i] = Float(r.range(0.5, 1.4))
            w.isEnabled = true
        }
        blimpCount = min(Self.capBlimps, 1 + cycle)          // distinction past the cap comes from hue
        for (i, g) in blimps.enumerated() {
            g.isEnabled = i < blimpCount
            blimpBaseX[i] = Float(r.range(-11, 11))
            blimpBaseY[i] = Float(r.range(12.5, 16.5))
            blimpZ[i] = Float(-53 + 4 * i) + Float(r.range(0, 2))
            blimpSpeed[i] = Float(r.range(0.25, 0.45)) * (i % 2 == 0 ? 1 : -1)
            blimpPhase[i] = r.range(0, 60)
            g.position = SIMD3<Float>(blimpBaseX[i], blimpBaseY[i], blimpZ[i])   // RM keeps this pose
            // The fin trails: it's built at −x, so flip the hull around when drifting toward −x.
            g.orientation = simd_quatf(angle: blimpSpeed[i] > 0 ? 0 : .pi, axis: SIMD3<Float>(0, 1, 0))
        }
        beamCount = min(Self.capBeams, 1 + cycle)
        for (i, b) in beams.enumerated() {
            guard i < beamCount else { b.isEnabled = false; continue }
            // Rooftop anchor — beam 0 from the left half of the visible street, beam 1 right.
            let half = eligible.count / 2
            let bi = eligible[i == 0 ? r.int(0, half - 1) : r.int(half, eligible.count - 1)]
            let bld = nearBuildings[bi]
            b.position = SIMD3<Float>(nearX[bi] + bld.x / 2, bld.y - 0.4, 0.2)
            beamLean[i] = (i == 0 ? 1 : -1) * Float(r.range(0.10, 0.22))
            beamPhase[i] = Float(r.range(0, 2 * .pi))
            b.orientation = simd_quatf(angle: beamLean[i], axis: SIMD3<Float>(0, 0, 1))
            b.isEnabled = true
        }
    }

    private func restyleCaverns(_ r: inout SplitMix64, cycle: Int) {
        ceiling.position.x = Float(r.range(-5, 5))
        stalactiteCount = min(Self.capStalactites, 9 + 2 * cycle)
        for (i, s) in stalactites.enumerated() {
            guard i < stalactiteCount else { s.isEnabled = false; continue }
            // Evenly spaced with jitter so the fringe reads as one ceiling, never a clump.
            let x = -22 + 44 * (Float(i) + 0.5) / Float(stalactiteCount) + Float(r.range(-1.5, 1.5))
            let len = Float(r.range(2.5, 6.2))
            let girth = Float(r.range(1.0, 1.8))
            s.scale = SIMD3<Float>(girth, len, girth)
            s.position = SIMD3<Float>(x, 14 - len / 2, Float(r.range(-52, -42)))
            s.isEnabled = true
        }
        clusterCount = min(Self.capClusters, 3 + cycle)
        for (i, g) in clusters.enumerated() {
            g.isEnabled = i < clusterCount
            let side: Float = i % 2 == 0 ? -1 : 1
            clusterBaseY[i] = Float(r.range(7.5, 12.5))
            g.position = SIMD3<Float>(side * Float(r.range(8, 18)), clusterBaseY[i],
                                      Float(r.range(-54, -44)))
            g.orientation = simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0))   // RM rest pose
            clusterSpin[i] = Float(r.range(0.15, 0.35))
            clusterPhase[i] = Float(r.range(0, 2 * .pi))
        }
        restyleMotes(&caveMotes, &r, count: 10 + 4 * cycle,
                     x: (-24, 24), y0: (1, 4), span: (8, 13), rise: (0.3, 0.7),
                     z: (-56, -48), scale: (0.08, 0.15))
        for (i, a) in auroras.enumerated() {
            auroraBaseX[i] = Float(r.range(-4, 4))
            a.position.x = auroraBaseX[i]
            a.scale = .one
        }
    }

    private func restyleSands(_ r: inout SplitMix64, cycle: Int) {
        // Low sun: alternate horizon side per cycle; halo discs stagger BEHIND the core.
        let sx = Float(cycle % 2 == 0 ? r.range(-13, -7) : r.range(7, 13))
        let sy = Float(r.range(6.2, 7.6))
        let sr = Float(r.range(4.2, 5.0))
        sunCore.position = SIMD3<Float>(sx, sy, -61.5)
        sunCore.scale = SIMD3<Float>(repeating: sr)
        sunHalo1.position = SIMD3<Float>(sx, sy, -61.9)
        sunHalo1.scale = SIMD3<Float>(repeating: sr * 1.6)
        sunHalo2.position = SIMD3<Float>(sx, sy, -62.3)
        sunHalo2.scale = SIMD3<Float>(repeating: sr * 2.35)
        planetCount = min(Self.capPlanets, 2 + cycle)
        for (i, g) in planets.enumerated() {
            g.isEnabled = i < planetCount
            let fi = Float(i)
            planetZ[i] = -(47 + 5 * fi) - Float(r.range(0, 3))
            planetBaseY[i] = Float(r.range(Double(9.5 + 1.5 * fi), Double(12.5 + 2 * fi)))
            planetBaseX[i] = -20 + 18 * fi + Float(r.range(-4, 4))
            planetPar[i] = Float(r.range(0.010, 0.016)) * (50 / -planetZ[i])   // deeper = slower
            planetPhase[i] = Float(r.range(0, 2 * .pi))
            g.position = SIMD3<Float>(planetBaseX[i], planetBaseY[i], planetZ[i])  // RM pose
            g.scale = SIMD3<Float>(repeating: Float(r.range(Double(1.4 + 0.4 * fi), Double(2.2 + 0.5 * fi))))
            // Ring tilt, alternating lean so two planets never read as copies.
            planetRings[i].orientation = simd_quatf(angle: (i % 2 == 0 ? 1 : -1) * Float(r.range(0.30, 0.55)),
                                                    axis: SIMD3<Float>(0, 0, 1))
                * simd_quatf(angle: .pi / 2, axis: SIMD3<Float>(1, 0, 0))
        }
        for (i, d) in dunes.enumerated() {
            d.position.x = Float(r.range(-7, 7))
            d.scale = SIMD3<Float>(1, Float(r.range(0.9, 1.15)) * (i == 1 ? 1 : 0.85), 1)
        }
        restyleMotes(&sandMotes, &r, count: 8 + 3 * cycle,
                     x: (-20, 20), y0: (0.5, 3), span: (4, 7), rise: (0.2, 0.45),
                     z: (-52, -47), scale: (0.10, 0.18))
    }

    private func restyleMotes(_ m: inout Motes, _ r: inout SplitMix64, count: Int,
                              x: (Double, Double), y0: (Double, Double), span: (Double, Double),
                              rise: (Double, Double), z: (Double, Double), scale: (Double, Double)) {
        m.active = min(m.ents.count, count)
        for i in 0..<m.ents.count {
            let e = m.ents[i]
            guard i < m.active else { e.isEnabled = false; continue }
            m.baseX[i] = Float(r.range(x.0, x.1))
            m.baseY[i] = Float(r.range(y0.0, y0.1))
            m.span[i] = Float(r.range(span.0, span.1))
            m.rise[i] = Float(r.range(rise.0, rise.1))
            m.sway[i] = Float(r.range(0.2, 0.5))
            m.phase[i] = Float(r.range(0, 40))
            m.z[i] = Float(r.range(z.0, z.1))
            e.scale = SIMD3<Float>(repeating: Float(r.range(scale.0, scale.1)))
            e.position = SIMD3<Float>(m.baseX[i], m.baseY[i] + fmodf(m.phase[i], m.span[i]), m.z[i])
            e.isEnabled = true
        }
    }

    // MARK: construction (once — geometry seeds are FIXED so skyline/dune meshes never rebuild)

    private func buildMetropolis(disc: MeshResource) {
        let pal = Theme.worlds[0]
        let matFar = UnlitMaterial(color: Self.blend(pal, pal.accent, 0.12))
        let matNear = UnlitMaterial(color: Self.blend(pal, pal.accent, 0.22))
        let matWindow = UnlitMaterial(color: Self.lift(pal.accent2, 0.25))
        let matBlimp = UnlitMaterial(color: Self.blend(pal, pal.accent2, 0.40))
        let matFin = UnlitMaterial(color: Self.blend(pal, pal.accent, 0.45))
        let matBeam = UnlitMaterial(color: Self.blend(pal, pal.accent, 0.30))

        var r = SplitMix64(seed: 0xC17F_5CAB)   // fixed cosmetic seed — never the run RNG
        farBuildings = (0..<17).map { _ in
            SIMD2(Float(r.range(3.5, 7.0)), Float(r.range(7, 16)))
        }
        nearBuildings = (0..<14).map { _ in
            SIMD2(Float(r.range(4.5, 8.5)), Float(r.range(4, 11)))
        }
        farX = Self.leftEdges(farBuildings, gap: 1.1)
        nearX = Self.leftEdges(nearBuildings, gap: 1.4)
        farCard = ModelEntity(mesh: ProceduralMesh.skyline(buildings: farBuildings, gap: 1.1),
                              materials: [matFar])
        farCard.position = SIMD3<Float>(0, 0, -59)
        nearCard = ModelEntity(mesh: ProceduralMesh.skyline(buildings: nearBuildings, gap: 1.4),
                               materials: [matNear])
        nearCard.position = SIMD3<Float>(0, 0, -50.5)
        metroRoot.addChild(farCard)
        metroRoot.addChild(nearCard)
        register(farCard, fam: 0) { Self.blend($0, $0.accent, 0.12) }
        register(nearCard, fam: 0) { Self.blend($0, $0.accent, 0.22) }

        // Windows + beams ride their card so a restyle x-shift moves the whole street.
        for i in 0..<Self.capWindows {
            let w = ModelEntity(mesh: disc, materials: [matWindow])
            w.isEnabled = false
            (i < Self.windowsOnFar ? farCard : nearCard).addChild(w)
            register(w, fam: 0) { Self.lift($0.accent2, 0.25) }
            windows.append(w)
        }
        windowPhase = .init(repeating: 0, count: Self.capWindows)
        windowSpeed = .init(repeating: 1, count: Self.capWindows)
        for _ in 0..<Self.capBlimps {
            let g = Entity()
            let body = ModelEntity(mesh: .generateSphere(radius: 1), materials: [matBlimp])
            body.scale = SIMD3<Float>(2.0, 0.55, 0.55)
            let fin = ModelEntity(mesh: .generateBox(width: 0.5, height: 0.7, depth: 0.12, cornerRadius: 0.03),
                                  materials: [matFin])
            fin.position = SIMD3<Float>(-1.8, 0.4, 0)
            g.addChild(body)
            g.addChild(fin)
            register(body, fam: 0) { Self.blend($0, $0.accent2, 0.40) }
            register(fin, fam: 0) { Self.blend($0, $0.accent, 0.45) }
            g.isEnabled = false
            metroRoot.addChild(g)
            blimps.append(g)
        }
        blimpBaseX = .init(repeating: 0, count: Self.capBlimps)
        blimpBaseY = .init(repeating: 0, count: Self.capBlimps)
        blimpZ = .init(repeating: 0, count: Self.capBlimps)
        blimpSpeed = .init(repeating: 0, count: Self.capBlimps)
        blimpPhase = .init(repeating: 0, count: Self.capBlimps)
        let beamMesh = ProceduralMesh.beam(length: 16, halfWidthNear: 0.16, halfWidthFar: 1.5)
        for _ in 0..<Self.capBeams {
            let b = ModelEntity(mesh: beamMesh, materials: [matBeam])
            b.isEnabled = false
            nearCard.addChild(b)
            register(b, fam: 0) { Self.blend($0, $0.accent, 0.30) }
            beams.append(b)
        }
        beamLean = .init(repeating: 0, count: Self.capBeams)
        beamPhase = .init(repeating: 0, count: Self.capBeams)
    }

    private func buildCaverns(disc: MeshResource) {
        let pal = Theme.worlds[1]
        let matCeiling = UnlitMaterial(color: Self.blend(pal, pal.accent, 0.15))
        let matStal = UnlitMaterial(color: Self.blend(pal, pal.accent, 0.26))
        let matCrystalA = UnlitMaterial(color: Self.blend(pal, pal.accent, 0.50))
        let matCrystalB = UnlitMaterial(color: Self.blend(pal, pal.accent2, 0.45))
        let matMote = UnlitMaterial(color: Self.blend(pal, pal.accent2, 0.55))
        let matAuroraA = UnlitMaterial(color: Self.blend(pal, pal.accent2, 0.30))
        let matAuroraB = UnlitMaterial(color: Self.blend(pal, pal.accent, 0.24))

        // The chase camera pitches DOWN ~15°, so a band parked high up barely peeks into frame.
        // y 13–37 at z −49 fills the top ~20% of the screen and still covers the max-FOV punch.
        ceiling = ModelEntity(mesh: .generatePlane(width: 120, height: 24), materials: [matCeiling])
        ceiling.position = SIMD3<Float>(0, 25, -49)
        cavernRoot.addChild(ceiling)
        register(ceiling, fam: 1) { Self.blend($0, $0.accent, 0.15) }

        let cone = MeshResource.generateCone(height: 1, radius: 0.30)
        for _ in 0..<Self.capStalactites {
            let s = ModelEntity(mesh: cone, materials: [matStal])
            s.orientation = simd_quatf(angle: .pi, axis: SIMD3<Float>(0, 0, 1))   // apex DOWN
            s.isEnabled = false
            cavernRoot.addChild(s)
            register(s, fam: 1) { Self.blend($0, $0.accent, 0.26) }
            stalactites.append(s)
        }
        var r = SplitMix64(seed: 0xCA4E_0001)   // fixed cosmetic seed
        let shard = ProceduralMesh.octahedron(1)
        for _ in 0..<Self.capClusters {
            let g = Entity()
            let offs: [SIMD3<Float>] = [
                SIMD3(0, Float(r.range(0.4, 0.7)), 0),
                SIMD3(Float(r.range(-0.9, -0.6)), Float(r.range(-0.4, -0.2)), 0.2),
                SIMD3(Float(r.range(0.6, 0.9)), Float(r.range(-0.45, -0.25)), -0.15),
            ]
            for (k, o) in offs.enumerated() {
                let c = ModelEntity(mesh: shard, materials: [k == 1 ? matCrystalB : matCrystalA])
                c.position = o
                c.scale = SIMD3<Float>(repeating: Float(r.range(0.5, 1.0)))
                if k == 1 { register(c, fam: 1) { Self.blend($0, $0.accent2, 0.45) } }
                else { register(c, fam: 1) { Self.blend($0, $0.accent, 0.50) } }
                g.addChild(c)
            }
            g.isEnabled = false
            cavernRoot.addChild(g)
            clusters.append(g)
        }
        clusterSpin = .init(repeating: 0, count: Self.capClusters)
        clusterPhase = .init(repeating: 0, count: Self.capClusters)
        clusterBaseY = .init(repeating: 0, count: Self.capClusters)
        caveMotes = makeMotes(cap: Self.capCaveMotes, mesh: disc, material: matMote, parent: cavernRoot)
        for e in caveMotes.ents { register(e, fam: 1) { Self.blend($0, $0.accent2, 0.55) } }
        let ribbonA = ModelEntity(
            mesh: ProceduralMesh.ribbon(width: 110, thickness: 1.1, amplitude: 1.3, waves: 2.2, phase: 0.4),
            materials: [matAuroraA])
        ribbonA.position = SIMD3<Float>(0, 6.2, -60.4)
        register(ribbonA, fam: 1) { Self.blend($0, $0.accent2, 0.30) }
        let ribbonB = ModelEntity(
            mesh: ProceduralMesh.ribbon(width: 110, thickness: 0.8, amplitude: 0.9, waves: 3.1, phase: 2.2),
            materials: [matAuroraB])
        ribbonB.position = SIMD3<Float>(0, 7.6, -59.6)
        register(ribbonB, fam: 1) { Self.blend($0, $0.accent, 0.24) }
        for a in [ribbonA, ribbonB] {
            cavernRoot.addChild(a)
            auroras.append(a)
        }
    }

    private func buildSands(disc: MeshResource) {
        let pal = Theme.worlds[2]
        let matSun = UnlitMaterial(color: Self.lift(pal.accent2, 0.45))
        let matHalo1 = UnlitMaterial(color: Self.blend(pal, pal.accent2, 0.34))
        let matHalo2 = UnlitMaterial(color: Self.blend(pal, pal.accent, 0.18))
        let matRing = UnlitMaterial(color: Self.blend(pal, pal.accent2, 0.55))
        let planetMats = [
            UnlitMaterial(color: Self.blend(pal, pal.accent, 0.42)),
            UnlitMaterial(color: Self.blend(pal, pal.accent, 0.30)),
            UnlitMaterial(color: Self.blend(pal, pal.accent2, 0.34)),
        ]
        let matDuneFar = UnlitMaterial(color: Self.blend(pal, pal.accent, 0.20))
        let matDuneNear = UnlitMaterial(color: Self.blend(pal, pal.accent, 0.30))
        let matMote = UnlitMaterial(color: Self.blend(pal, pal.accent2, 0.50))

        sunCore = ModelEntity(mesh: disc, materials: [matSun])
        sunHalo1 = ModelEntity(mesh: disc, materials: [matHalo1])
        sunHalo2 = ModelEntity(mesh: disc, materials: [matHalo2])
        for s in [sunHalo2, sunHalo1, sunCore] { sandsRoot.addChild(s!) }
        register(sunCore, fam: 2) { Self.lift($0.accent2, 0.45) }
        register(sunHalo1, fam: 2) { Self.blend($0, $0.accent2, 0.34) }
        register(sunHalo2, fam: 2) { Self.blend($0, $0.accent, 0.18) }

        // Ringed planets: unit sphere + flattened tilted torus, scaled as one group (restyle
        // re-tilts each ring via `planetRings`).
        let ringMesh = ProceduralMesh.torus(major: 1.5, minor: 0.07, majorSeg: 40, minorSeg: 6)
        for i in 0..<Self.capPlanets {
            let g = Entity()
            let body = ModelEntity(mesh: .generateSphere(radius: 1), materials: [planetMats[i % 3]])
            let ring = ModelEntity(mesh: ringMesh, materials: [matRing])
            ring.scale = SIMD3<Float>(1, 1, 0.25)   // flatten the tube along the hole axis
            switch i % 3 {
            case 0:  register(body, fam: 2) { Self.blend($0, $0.accent, 0.42) }
            case 1:  register(body, fam: 2) { Self.blend($0, $0.accent, 0.30) }
            default: register(body, fam: 2) { Self.blend($0, $0.accent2, 0.34) }
            }
            register(ring, fam: 2) { Self.blend($0, $0.accent2, 0.55) }
            g.addChild(body)
            g.addChild(ring)
            g.isEnabled = false
            sandsRoot.addChild(g)
            planets.append(g)
            planetRings.append(ring)
        }
        planetBaseX = .init(repeating: 0, count: Self.capPlanets)
        planetBaseY = .init(repeating: 0, count: Self.capPlanets)
        planetZ = .init(repeating: -50, count: Self.capPlanets)
        planetPar = .init(repeating: 0, count: Self.capPlanets)
        planetPhase = .init(repeating: 0, count: Self.capPlanets)

        var r = SplitMix64(seed: 0xD0_0E5A_4D5)   // fixed cosmetic seed for the dune crests
        func crests(base: Double, a1: Double, a2: Double) -> [Float] {
            let p1 = r.range(0, 2 * .pi), p2 = r.range(0, 2 * .pi)
            let w1 = r.range(1.8, 2.6), w2 = r.range(4.2, 5.6)
            return (0..<36).map { i in
                let u = Double(i) / 35
                return Float(max(0.15, base + a1 * sin(u * w1 * 2 * .pi + p1) + a2 * sin(u * w2 + p2)))
            }
        }
        let duneFar = ModelEntity(mesh: ProceduralMesh.ridge(width: 110, heights: crests(base: 1.7, a1: 1.2, a2: 0.6)),
                                  materials: [matDuneFar])
        duneFar.position = SIMD3<Float>(0, 0, -59)
        register(duneFar, fam: 2) { Self.blend($0, $0.accent, 0.20) }
        let duneNear = ModelEntity(mesh: ProceduralMesh.ridge(width: 110, heights: crests(base: 2.5, a1: 1.9, a2: 0.8)),
                                   materials: [matDuneNear])
        duneNear.position = SIMD3<Float>(0, 0, -52.5)
        register(duneNear, fam: 2) { Self.blend($0, $0.accent, 0.30) }
        for d in [duneFar, duneNear] {
            sandsRoot.addChild(d)
            dunes.append(d)
        }
        sandMotes = makeMotes(cap: Self.capSandMotes, mesh: disc, material: matMote, parent: sandsRoot)
        for e in sandMotes.ents { register(e, fam: 2) { Self.blend($0, $0.accent2, 0.50) } }
    }

    private func makeMotes(cap: Int, mesh: MeshResource, material: UnlitMaterial, parent: Entity) -> Motes {
        var m = Motes()
        for _ in 0..<cap {
            let e = ModelEntity(mesh: mesh, materials: [material])
            e.isEnabled = false
            parent.addChild(e)
            m.ents.append(e)
        }
        m.baseX = .init(repeating: 0, count: cap)
        m.baseY = .init(repeating: 0, count: cap)
        m.z = .init(repeating: -50, count: cap)
        m.rise = .init(repeating: 0.3, count: cap)
        m.span = .init(repeating: 6, count: cap)
        m.sway = .init(repeating: 0.3, count: cap)
        m.phase = .init(repeating: 0, count: cap)
        return m
    }

    // MARK: helpers

    /// Building left edges in card-local coordinates — mirrors the skyline mesh cursor walk.
    private static func leftEdges(_ buildings: [SIMD2<Float>], gap: Float) -> [Float] {
        let total = buildings.reduce(Float(0)) { $0 + $1.x } + gap * Float(buildings.count - 1)
        var x = -total / 2
        var edges: [Float] = []
        edges.reserveCapacity(buildings.count)
        for b in buildings {
            edges.append(x)
            x += b.x + gap
        }
        return edges
    }

    /// Wrap into [−span/2, span/2) — drifting set pieces leave one screen edge and re-enter the
    /// other while still offscreen.
    private static func wrap(_ v: Double, span: Double) -> Double {
        var w = v.truncatingRemainder(dividingBy: span)
        if w < 0 { w += span }
        return w - span / 2
    }

    /// mix(bg, v, t) as UIColor — opaque discs/cards over the bg-colored backdrop read exactly
    /// like `t` opacity, which keeps the whole layer in the background plane.
    private static func blend(_ p: WorldPalette, _ v: SIMD3<Float>, _ t: Float) -> UIColor {
        let c = p.bg + (v - p.bg) * t
        return UIColor(red: CGFloat(c.x), green: CGFloat(c.y), blue: CGFloat(c.z), alpha: 1)
    }

    /// mix(v, white, t) — the bright "lit" variant (sun core, window lights).
    private static func lift(_ v: SIMD3<Float>, _ t: Float) -> UIColor {
        let c = v + (SIMD3<Float>(1, 1, 1) - v) * t
        return UIColor(red: CGFloat(c.x), green: CGFloat(c.y), blue: CGFloat(c.z), alpha: 1)
    }
}
