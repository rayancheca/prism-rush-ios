import RealityKit
import simd
import UIKit

/// World 10 — "Tempest": a violent lightning storm. A sharp near cloud ridge hangs dark across the
/// top of the sky with a wider, dimmer rear ridge behind it; two-to-three jagged bolt GROUPS (each a
/// zig-zag chain of beam segments assembled into one entity) FLASH on for a couple of frames on a
/// local-seeded random cadence, each synced to a brief disc ground-flash and a haze-disc pulse; fast
/// rain streaks fall in front. Self-contained (own entities + build/restyle/animate) so `WorldDecor`
/// just enables it and forwards two calls — the scalable shape every bespoke world copies.
///
/// Invariants (mirrors OrbitalSky): geometry built ONCE at init and recycled; placement + the flash
/// cadence are deterministic from a LOCAL `SplitMix64` seeded by the absolute world ordinal (never
/// the run RNG, never `Date()` — rule 2); per-frame work is transform + `isEnabled` writes only (zero
/// allocation); flashes are brief so gameplay stays readable (decree 6); Reduce Motion freezes one
/// static pose. Everything is procedural mesh + `UnlitMaterial` (rule 6).
@MainActor
final class TempestSky {
    let root = Entity()

    private static let rainCap = 40
    private static let boltCap = 3

    // Cloud ridges: hang DOWN from the top of the sky (a `ridge` card rotated 180° about Z so the
    // filled-to-baseline body reads as an overcast ceiling). Near = sharp + dark, rear = wide + dim.
    private var nearRidge: ModelEntity!
    private var rearRidge: ModelEntity!

    // Haze: one big dim disc behind the clouds that brightens on each flash.
    private var haze: ModelEntity!

    // Lightning: each group is a chain of zig-zag beam segments under one parent that flashes as a
    // unit, plus a synced disc ground-flash low in the sky. Cadence is local-seeded (no Date()).
    @MainActor private final class Bolt {
        let group = Entity()
        var ground: ModelEntity!
        var nextFire: Double = 1      // seconds of accumulated time until this bolt next strikes
        var litLeft: Double = 0       // seconds the flash stays on (~2 frames)
        var period: Double = 3        // mean seconds between strikes
        var jitter: Double = 2        // +/- spread on the period
        var seed: UInt64 = 0          // local stream advanced for each re-roll (never Date()/.random)
    }
    private var bolts: [Bolt] = []
    private var boltParts: [ModelEntity] = []     // every beam segment (for retint)

    // Rain (shared disc mote pattern, scaled into thin vertical streaks).
    private var rain: [ModelEntity] = []
    private var rainBaseX: [Float] = [], rainTop: [Float] = [], rainZ: [Float] = []
    private var rainSpeed: [Float] = [], rainLen: [Float] = []
    private var rainCount = 0

    // Accumulated elapsed so the cadence advances by per-frame DELTAS, not absolute time.
    private var lastElapsed: Double = 0

    init(parent: Entity) {
        build()
        root.isEnabled = false
        parent.addChild(root)
    }

    // MARK: build (once)

    private func build() {
        let disc = ProceduralMesh.disc()

        // Haze backdrop — a large dim disc parked high and far behind everything.
        haze = ModelEntity(mesh: disc, materials: [Self.mat(.black)])
        root.addChild(haze)

        // Cloud ridges (built with smooth random crests; restyle re-poses + recolors them).
        rearRidge = ModelEntity(mesh: Self.ridgeMesh(width: 70, crest: 9, lumps: 11, seed: 0xC10D),
                                materials: [Self.mat(.black)])
        nearRidge = ModelEntity(mesh: Self.ridgeMesh(width: 56, crest: 12, lumps: 9, seed: 0xC10E),
                                materials: [Self.mat(.black)])
        root.addChild(rearRidge)
        root.addChild(nearRidge)

        // Lightning groups: each a zig-zag chain of tapering beams + a ground-flash disc.
        for _ in 0..<Self.boltCap {
            let b = Bolt()
            var seg = SIMD3<Float>(0, 0, 0)      // running tip in the group's local space (down -Y)
            var ang: Float = 0
            for k in 0..<4 {
                let len: Float = 2.0
                let beam = ModelEntity(mesh: ProceduralMesh.beam(length: len, halfWidthNear: 0.22,
                                                                 halfWidthFar: 0.04),
                                       materials: [Self.mat(.white)])
                // Alternate the zig-zag lean; the beam fans up +Y from its origin, so flip it to
                // point DOWN and rotate into the leaning direction, then advance the tip.
                ang = (k % 2 == 0 ? 1 : -1) * 0.5
                beam.orientation = simd_quatf(angle: .pi + ang, axis: SIMD3<Float>(0, 0, 1))
                beam.position = seg
                b.group.addChild(beam)
                boltParts.append(beam)
                seg += SIMD3<Float>(sin(ang) * len * 0.5, -cos(ang) * len, 0)
            }
            let ground = ModelEntity(mesh: disc, materials: [Self.mat(.white)])
            ground.position = seg + SIMD3<Float>(0, -0.4, 0.2)
            b.group.addChild(ground)
            b.ground = ground
            b.group.isEnabled = false           // off until its first strike
            root.addChild(b.group)
            bolts.append(b)
        }

        // Rain streaks — thin vertical discs (scaled 0.2 × 1.5) falling fast in front of the storm.
        for _ in 0..<Self.rainCap {
            let st = ModelEntity(mesh: disc, materials: [Self.mat(.white)])
            st.scale = SIMD3<Float>(0.2, 1.5, 1)
            st.isEnabled = false
            root.addChild(st)
            rain.append(st)
        }
        rainBaseX = .init(repeating: 0, count: Self.rainCap)
        rainTop = .init(repeating: 18, count: Self.rainCap)
        rainZ = .init(repeating: -40, count: Self.rainCap)
        rainSpeed = .init(repeating: 14, count: Self.rainCap)
        rainLen = .init(repeating: 24, count: Self.rainCap)
    }

    /// A rolling cloud ridge mesh — smooth random crest heights from a LOCAL seed (build-time only,
    /// never the run RNG). `restyle` rotates the card 180° about Z so it hangs from the top edge.
    private static func ridgeMesh(width: Float, crest: Float, lumps: Int, seed: UInt64) -> MeshResource {
        var r = SplitMix64(seed: seed)
        var h: [Float] = []
        let n = lumps
        for i in 0..<n {
            // Two-octave smooth bumps so the silhouette reads as cloud, not noise.
            let u = Float(i) / Float(n - 1)
            let base = crest * (0.45 + 0.55 * Float(0.5 + 0.5 * sin(Double(u) * 6.0 + r.range(0, 6.28))))
            h.append(max(0.5, base + Float(r.range(-1.5, 1.5))))
        }
        return ProceduralMesh.ridge(width: width, heights: h)
    }

    // MARK: restyle (world boundary / Reduce-Motion flip — never per frame)

    func restyle(palette pal: WorldPalette, world: Int) {
        var r = SplitMix64(seed: 0x0_7E33_5701 &+ UInt64(bitPattern: Int64(world)) &* 0x9E37_79B9_7F4A_7C15)

        // Storm palette: clouds mix toward bg (dark, recede), haze a touch of lavender accent, bolts
        // hot white-lavender. Everything stays dim-ish so lane obstacles read in front (decree 6).
        let nearC = Self.blend(pal, pal.grid, 0.20)        // dark overcast near ridge
        let rearC = Self.blend(pal, pal.grid, 0.12)        // even dimmer rear ridge
        let hazeC = Self.blend(pal, pal.accent, 0.16)
        let boltC = Self.lift(pal.accent2, 0.55)
        let groundC = Self.blend(pal, pal.accent2, 0.45)

        // Cloud ridges hang from the top: rotate the up-filled card 180° about Z (now fills DOWN),
        // park its baseline high so only the lumpy lower edge intrudes into the sky.
        let flip = simd_quatf(angle: .pi, axis: SIMD3<Float>(0, 0, 1))
        rearRidge.orientation = flip
        rearRidge.position = SIMD3<Float>(Float(r.range(-4, 4)), Float(r.range(20, 23)), -58)
        rearRidge.model?.materials = [Self.mat(rearC)]
        nearRidge.orientation = flip
        nearRidge.position = SIMD3<Float>(Float(r.range(-3, 3)), Float(r.range(21, 24)), -46)
        nearRidge.model?.materials = [Self.mat(nearC)]

        // Haze disc: big, high, far — pulses on each flash (base scale parked here).
        haze.scale = SIMD3<Float>(repeating: Float(r.range(26, 30)))
        haze.position = SIMD3<Float>(Float(r.range(-3, 3)), Float(r.range(11, 14)), -60)
        haze.model?.materials = [Self.mat(hazeC)]

        // Lightning groups: spread across the sky, hanging from under the cloud ridge. Cadence +
        // ground-flash placement all from the LOCAL stream — deterministic, no Date().
        for i in bolts.indices {
            let b = bolts[i]
            let x = Float(r.range(-15, 15))
            let y = Float(r.range(13, 17))             // top of the bolt, under the cloud edge
            b.group.position = SIMD3<Float>(x, y, Float(r.range(-44, -38)))
            b.group.orientation = simd_quatf(angle: Float(r.range(-0.18, 0.18)), axis: SIMD3<Float>(0, 0, 1))
            b.group.isEnabled = false
            b.ground.scale = SIMD3<Float>(repeating: Float(r.range(3.5, 5.5)))
            b.ground.model?.materials = [Self.mat(groundC)]
            b.period = r.range(2.6, 4.4)
            b.jitter = r.range(1.2, 2.4)
            b.seed = (r.next() | 1)                    // odd, non-zero local stream for re-rolls
            var s = SplitMix64(seed: b.seed)
            b.nextFire = s.range(0.3, b.period)        // staggered first strike
            b.seed = s.next() | 1
            b.litLeft = 0
        }
        for p in boltParts { p.model?.materials = [Self.mat(boltC)] }

        // Rain — fast vertical streaks scattered across the front of the storm.
        rainCount = Self.rainCap
        for i in rain.indices {
            rainBaseX[i] = Float(r.range(-22, 22))
            rainTop[i] = Float(r.range(15, 20))
            rainZ[i] = Float(r.range(-40, -30))
            rainSpeed[i] = Float(r.range(12, 20))
            rainLen[i] = Float(r.range(22, 30))
            let s = Float(r.range(0.7, 1.2))
            rain[i].scale = SIMD3<Float>(0.2 * s, 1.5 * s, 1)
            let startY = rainTop[i] - Float(r.range(0, Double(rainLen[i])))
            rain[i].position = SIMD3<Float>(rainBaseX[i], startY, rainZ[i])
            rain[i].model?.materials = [Self.mat(boltC)]
            rain[i].isEnabled = true
        }

        lastElapsed = 0
    }

    // MARK: animate (transform + isEnabled only)

    func animate(elapsed: Double, reduceMotion: Bool) {
        if reduceMotion {
            lastElapsed = elapsed
            haze.isEnabled = true
            for i in bolts.indices {                  // one frozen mid-storm pose: one bolt struck
                let on = i == 0
                if bolts[i].group.isEnabled != on { bolts[i].group.isEnabled = on }
            }
            for i in 0..<rainCount {                  // streaks parked at their base, no fall
                rain[i].position = SIMD3<Float>(rainBaseX[i], rainTop[i] - rainLen[i] * 0.5, rainZ[i])
            }
            return
        }

        // Per-frame delta (clamped; restyle resets lastElapsed = 0 on each world swap).
        var dt = elapsed - lastElapsed
        if dt < 0 || dt > 0.5 { dt = 1.0 / 60.0 }
        lastElapsed = elapsed
        let t = Float(elapsed)

        // Lightning cadence: count down each bolt's local-seeded timer; on fire, flash for ~2 frames
        // and re-roll the next interval from the bolt's own stream (never Date()/.random).
        var anyLit = false
        for i in bolts.indices {
            let b = bolts[i]
            if b.litLeft > 0 {
                b.litLeft -= dt
                if b.litLeft <= 0 {
                    b.litLeft = 0
                    if b.group.isEnabled { b.group.isEnabled = false }
                } else {
                    anyLit = true
                }
            } else {
                b.nextFire -= dt
                if b.nextFire <= 0 {
                    b.litLeft = 2.0 / 60.0            // ~2 frames on
                    if !b.group.isEnabled { b.group.isEnabled = true }
                    anyLit = true
                    var s = SplitMix64(seed: b.seed) // advance the local stream for the next strike
                    b.nextFire = b.period + s.range(-b.jitter, b.jitter)
                    if b.nextFire < 0.4 { b.nextFire = 0.4 }
                    b.seed = s.next() | 1
                }
            }
        }
        // Haze pulses bright with any active bolt, otherwise its dim base — one isEnabled toggle.
        if haze.isEnabled != anyLit { haze.isEnabled = anyLit }

        // Rain: fast fall, wrapped back to the top of its streak band.
        for i in 0..<rainCount {
            var y = rainTop[i] - Float((Double(rainSpeed[i]) * elapsed).truncatingRemainder(dividingBy: Double(rainLen[i])))
            if y < rainTop[i] - rainLen[i] { y += rainLen[i] }
            // tiny horizontal drift so the squall feels wind-driven
            let x = rainBaseX[i] + sin(t * 0.4 + Float(i)) * 0.3
            rain[i].position = SIMD3<Float>(x, y, rainZ[i])
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
