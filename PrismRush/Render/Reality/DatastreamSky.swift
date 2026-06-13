import RealityKit
import simd
import UIKit

/// World 7 — "Datastream": inside the machine. ONE big receding `gridCard` is parked far/high as a
/// Tron backdrop wall, a dim glow disc breathes at its vanishing point, 3–4 vertical light pylons
/// FLICKER on/off on a local-seeded cadence, and data motes rise in ORDERLY columns (no sway) — a
/// crisp, digital sky. Self-contained (its own entities + build/restyle/animate) so `WorldSky` just
/// enables it and forwards two calls — the scalable shape every new world copies.
///
/// Same invariants as the other families: geometry built ONCE at init and recycled; placement is
/// deterministic from a LOCAL `SplitMix64` seeded by the absolute world ordinal (never the run RNG —
/// rule 2); per-frame work is transform + `isEnabled` writes only (zero allocation); all motion is
/// subtle and Reduce-Motion-gated. Everything is procedural mesh + `UnlitMaterial` (rule 6).
@MainActor
final class DatastreamSky {
    let root = Entity()

    private static let moteCap = 30
    private static let pylonCount = 4
    private static let moteColumns = 6
    private static let motesPerColumn = 5            // moteColumns * motesPerColumn == moteCap

    // Backdrop grid wall + the glow disc at its vanishing point.
    private var grid: ModelEntity!
    private var vanishGlow: ModelEntity!

    // Vertical light pylons that flicker on/off (isEnabled) on a local-seeded cadence.
    @MainActor private final class Pylon {
        let entity: Entity
        var phase: Float = 0          // flicker phase offset
        var rate: Float = 1           // flicker speed
        var duty: Float = 0           // threshold: higher → on more of the time
        init(_ e: Entity) { entity = e }
    }
    private var pylons: [Pylon] = []

    // Data motes — discs rising in orderly columns, each looping over a fixed travel height.
    private var motes: [ModelEntity] = []
    private var moteBaseX: [Float] = [], moteBaseZ: [Float] = []
    private var moteFloorY: [Float] = [], moteRiseSpan: [Float] = []
    private var moteSpeed: [Float] = [], moteScale: [Float] = []
    private var moteCount = 0

    // Captured at restyle so the per-frame glow pulse never compounds (animate stays state-free).
    private var vanishGlowBase: Float = 6.0

    init(parent: Entity) {
        build()
        root.isEnabled = false
        parent.addChild(root)
    }

    // MARK: build (once)

    private func build() {
        let disc = ProceduralMesh.disc()

        // Backdrop grid wall — perspective baked into the mesh; parked far/high in restyle.
        grid = ModelEntity(mesh: ProceduralMesh.gridCard(width: 70, height: 30, cols: 14, rows: 10),
                           materials: [Self.mat(.black)])
        root.addChild(grid)

        // Vanishing-point glow disc (sits just behind the grid centre, breathes in animate).
        vanishGlow = ModelEntity(mesh: disc, materials: [Self.mat(.black)])
        root.addChild(vanishGlow)

        // Vertical light pylons — a thin beam pointing up (+Y), flicker via isEnabled.
        for _ in 0..<Self.pylonCount {
            let p = ModelEntity(mesh: ProceduralMesh.beam(length: 6, halfWidthNear: 0.05, halfWidthFar: 0.05),
                                materials: [Self.mat(.cyan)])
            let group = Entity()
            group.addChild(p)
            group.isEnabled = false
            root.addChild(group)
            pylons.append(Pylon(group))
        }

        // Data motes.
        for _ in 0..<Self.moteCap {
            let m = ModelEntity(mesh: disc, materials: [Self.mat(.white)])
            m.isEnabled = false
            root.addChild(m)
            motes.append(m)
        }
        moteBaseX = .init(repeating: 0, count: Self.moteCap)
        moteBaseZ = .init(repeating: -50, count: Self.moteCap)
        moteFloorY = .init(repeating: 0, count: Self.moteCap)
        moteRiseSpan = .init(repeating: 10, count: Self.moteCap)
        moteSpeed = .init(repeating: 1, count: Self.moteCap)
        moteScale = .init(repeating: 0.1, count: Self.moteCap)
    }

    // MARK: restyle (world boundary / Reduce-Motion flip — never per frame)

    func restyle(palette pal: WorldPalette, world: Int) {
        var r = SplitMix64(seed: 0x0_DA7A57 &+ UInt64(bitPattern: Int64(world)) &* 0x9E37_79B9_7F4A_7C15)

        // Crisp, digital: dim cyan grid wall, dim teal vanishing glow, near-white pylons + motes —
        // all mixed toward bg so the layer reads as BACKGROUND behind the lanes (decree 6).
        let gridC = Self.blend(pal, pal.grid, 0.40)
        let glowC = Self.blend(pal, pal.accent, 0.26)
        let pylonC = Self.blend(pal, pal.accent, 0.50)
        let moteC = Self.lift(pal.accent2, 0.30)

        // Backdrop grid wall — far + high, centred so its vanishing point is up the screen.
        grid.position = SIMD3<Float>(0, 6, -60)
        grid.model?.materials = [Self.mat(gridC)]

        // Vanishing-point glow — a large dim disc behind the grid centre (its top quarter, where
        // the gridCard's rows converge), pulsing in animate.
        vanishGlow.position = SIMD3<Float>(0, 16, -61)
        vanishGlowBase = Float(r.range(5.5, 7.0))
        vanishGlow.scale = SIMD3<Float>(repeating: vanishGlowBase)
        vanishGlow.model?.materials = [Self.mat(glowC)]

        // Pylons — evenly fanned across the grid, planted low so they rise into the sky band; each
        // gets a local flicker cadence. Tint shared.
        for (i, p) in pylons.enumerated() {
            let frac = (Float(i) + 0.5) / Float(Self.pylonCount)
            let x = (frac - 0.5) * 30 + Float(r.range(-1.5, 1.5))
            p.entity.position = SIMD3<Float>(x, Float(r.range(2.5, 5.0)), Float(r.range(-54, -48)))
            p.entity.scale = SIMD3<Float>(1, Float(r.range(0.9, 1.5)), 1)
            p.phase = Float(r.range(0, 6.283))
            p.rate = Float(r.range(1.6, 3.4))
            p.duty = Float(r.range(0.0, 0.35))        // sin threshold — flickers on/off digitally
            if let model = p.entity.children.first as? ModelEntity { model.model?.materials = [Self.mat(pylonC)] }
        }

        // Data motes — orderly columns: each column shares an x, motes stack at staggered floors and
        // rise straight up (no sway), looping over a fixed span. Cyan-white, dim.
        moteCount = Self.moteCap
        for i in 0..<Self.moteCap {
            let col = i / Self.motesPerColumn
            let row = i % Self.motesPerColumn
            let colFrac = (Float(col) + 0.5) / Float(Self.moteColumns)
            moteBaseX[i] = (colFrac - 0.5) * 34 + Float(r.range(-0.8, 0.8))
            moteBaseZ[i] = Float(r.range(-52, -44))
            let span = Float(r.range(9, 13))
            moteRiseSpan[i] = span
            // Stagger each mote within its column so the stream reads continuous, not in lockstep.
            moteFloorY[i] = Float(r.range(4.5, 6.5)) + (Float(row) / Float(Self.motesPerColumn)) * span
            moteSpeed[i] = Float(r.range(1.4, 2.6))
            let s = Float(r.range(0.08, 0.16))
            moteScale[i] = s
            motes[i].scale = SIMD3<Float>(repeating: s)
            motes[i].position = SIMD3<Float>(moteBaseX[i], moteFloorY[i], moteBaseZ[i])
            motes[i].model?.materials = [Self.mat(moteC)]
            motes[i].isEnabled = true
        }
    }

    // MARK: animate (transform + isEnabled only)

    func animate(elapsed: Double, reduceMotion: Bool) {
        if reduceMotion {
            vanishGlow.scale = SIMD3<Float>(repeating: vanishGlowBase)                 // hold pose
            for p in pylons where !p.entity.isEnabled { p.entity.isEnabled = true }    // all lit, static
            for i in 0..<moteCount {
                motes[i].position = SIMD3<Float>(moteBaseX[i], moteFloorY[i], moteBaseZ[i])
                motes[i].scale = SIMD3<Float>(repeating: moteScale[i])
            }
            return
        }
        let t = Float(elapsed)

        // Vanishing glow: subtle digital pulse around its captured restyle base (never compounds).
        vanishGlow.scale = SIMD3<Float>(repeating: vanishGlowBase * (1 + 0.10 * sin(t * 0.9)))

        // Pylons: flicker on/off on their local cadence — a sine past a per-pylon threshold.
        for p in pylons {
            let on = sin(t * p.rate + p.phase) > p.duty
            if p.entity.isEnabled != on { p.entity.isEnabled = on }
        }

        // Data motes: rise straight up in orderly columns, looping over their span (no sway).
        for i in 0..<moteCount {
            let span = moteRiseSpan[i]
            let raw = (t * moteSpeed[i]).truncatingRemainder(dividingBy: span)
            motes[i].position = SIMD3<Float>(moteBaseX[i], moteFloorY[i] + raw, moteBaseZ[i])
            // Fade in/out at the loop seam via scale so motes don't pop.
            let edge = min(raw, span - raw)
            let fade = min(1, edge / 1.2)
            motes[i].scale = SIMD3<Float>(repeating: max(0.02, moteScale[i] * fade))
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
