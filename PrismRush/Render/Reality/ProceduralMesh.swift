import RealityKit
import simd

/// Code-generated meshes RealityKit doesn't provide as primitives. Built from a `MeshDescriptor`
/// (positions + triangle indices). No normals: every material here is `UnlitMaterial`, so lighting
/// — and therefore normals — is ignored. Winding is CCW-outward (back faces are culled).
@MainActor
enum ProceduralMesh {

    /// Diamond/gem shape: 6 vertices, 8 faces.
    static func octahedron(_ r: Float) -> MeshResource {
        octahedron(rx: r, ry: r, rz: r)
    }

    /// Anisotropic octahedron — per-axis half-extents. The crystal character body uses this so
    /// the vertical elongation DESIGN_characters §4.1 documents (and every preview draws) is
    /// real in 3D too, instead of preview-only (AUDIT D2-5).
    static func octahedron(rx: Float, ry: Float, rz: Float) -> MeshResource {
        let p: [SIMD3<Float>] = [
            [rx, 0, 0], [-rx, 0, 0], [0, ry, 0], [0, -ry, 0], [0, 0, rz], [0, 0, -rz],
        ]
        let idx: [UInt32] = [
            2, 4, 0,  2, 0, 5,  2, 5, 1,  2, 1, 4,   // top fan
            3, 0, 4,  3, 5, 0,  3, 1, 5,  3, 4, 1,   // bottom fan
        ]
        return build(p, idx, fallback: max(rx, max(ry, rz)))
    }

    /// Two octahedra side by side in one mesh (the coin-doubler pickup): the gem vertex set
    /// duplicated at ±`offset` on x, indices rebased for the second copy. One MeshDescriptor.
    static func twinOctahedron(_ r: Float, offset: Float = 0.34) -> MeshResource {
        let base: [SIMD3<Float>] = [
            [r, 0, 0], [-r, 0, 0], [0, r, 0], [0, -r, 0], [0, 0, r], [0, 0, -r],
        ]
        let faces: [UInt32] = [
            2, 4, 0,  2, 0, 5,  2, 5, 1,  2, 1, 4,   // top fan
            3, 0, 4,  3, 5, 0,  3, 1, 5,  3, 4, 1,   // bottom fan
        ]
        var p: [SIMD3<Float>] = []
        var idx: [UInt32] = []
        for (k, dx) in [-offset, offset].enumerated() {
            p.append(contentsOf: base.map { $0 + SIMD3<Float>(dx, 0, 0) })
            idx.append(contentsOf: faces.map { $0 + UInt32(k * base.count) })
        }
        return build(p, idx, fallback: r + offset)
    }

    /// Hourglass for the chrono slow-mo pickup: two four-sided pyramids meeting apex-to-apex at
    /// the origin (square caps at y ±`halfHeight`, pinched waist at the centre). 9 vertices.
    static func hourglass(halfBase b: Float, halfHeight h: Float) -> MeshResource {
        let p: [SIMD3<Float>] = [
            [-b, -h, -b], [b, -h, -b], [b, -h, b], [-b, -h, b],  // bottom square 0..3 (CCW from above)
            [0, 0, 0],                                            // shared waist apex 4
            [-b, h, -b], [b, h, -b], [b, h, b], [-b, h, b],       // top square 5..8
        ]
        let idx: [UInt32] = [
            1, 0, 4,  2, 1, 4,  3, 2, 4,  0, 3, 4,   // lower pyramid sides (outward)
            0, 2, 1,  0, 3, 2,                         // bottom cap (downward)
            5, 6, 4,  6, 7, 4,  7, 8, 4,  8, 5, 4,   // upper inverted-pyramid sides (outward)
            5, 7, 6,  5, 8, 7,                         // top cap (upward)
        ]
        return build(p, idx, fallback: max(b, h))
    }

    /// The shield pickup: a heater-shield crest — flat shoulders, sides sweeping down to a point.
    ///
    /// It used to be `sphereEntity(0.42, cWhite)`, a plain white ball (owner, S-009: *"i dont like
    /// the shield being a white ball it should be an actual shield"*). A ball is also the one
    /// silhouette in the pickup set that carries no meaning — the magnet is a ring, the chrono an
    /// hourglass, the doubler a twin — and it collided with the gems, which are the other small
    /// round bright thing on the deck.
    ///
    /// Built with real thickness rather than as a flat card, because a pickup spins on Y as it
    /// travels: a zero-depth crest would vanish edge-on twice per rotation. The face is a triangle
    /// fan from the centre of each side, and the rim is quads between the two faces, so the crest
    /// reads solid from every angle. Front and back faces are wound opposite so both light up under
    /// an unlit material.
    ///
    /// `halfWidth` is the shoulder half-span, `height` the shoulder-to-tip drop, `halfDepth` the
    /// thickness. Matches the SF Symbol `shield.fill` the HUD chip uses, so the thing on the deck
    /// and the thing in the corner are recognisably one object (decree 2).
    static func shieldCrest(halfWidth w: Float, height h: Float, halfDepth d: Float,
                            segments n: Int = 9) -> MeshResource {
        // The silhouette, as a closed outline walked clockwise from the top-left shoulder.
        // Shoulders are square; the sides bow outward slightly before sweeping to the tip, which is
        // what separates a shield from a plain triangle at a glance.
        var outline: [SIMD2<Float>] = [[-w, h], [w, h]]
        for i in 1...n {
            let t = Float(i) / Float(n)                 // 0 at the right shoulder, 1 at the tip
            // Cosine ease keeps the shoulder square and the taper gentle before it snaps to a point.
            let x = w * cos(t * .pi / 2)
            let y = h - (h * 2) * t * t * 0.5 - h * t   // drops to −h at t = 1
            outline.append([x, y])
        }
        for i in stride(from: n - 1, through: 1, by: -1) {
            let t = Float(i) / Float(n)
            let x = -w * cos(t * .pi / 2)
            let y = h - (h * 2) * t * t * 0.5 - h * t
            outline.append([x, y])
        }

        let m = outline.count
        var p: [SIMD3<Float>] = []
        p.reserveCapacity(m * 2 + 2)
        // 0 = front centre, 1..m = front rim, m+1 = back centre, m+2..2m+1 = back rim.
        p.append([0, 0, d])
        for v in outline { p.append([v.x, v.y, d]) }
        p.append([0, 0, -d])
        for v in outline { p.append([v.x, v.y, -d]) }

        let backC = UInt32(m + 1)
        var idx: [UInt32] = []
        idx.reserveCapacity(m * 12)
        for i in 0..<m {
            let a = UInt32(1 + i), b = UInt32(1 + (i + 1) % m)
            let a2 = backC + 1 + UInt32(i), b2 = backC + 1 + UInt32((i + 1) % m)
            // Both faces are emitted in both windings. The outline's handedness is not obvious by
            // inspection, and a crest that renders invisible from the front is a silent failure the
            // tests cannot see — 76 extra indices is a cheap insurance premium.
            idx.append(contentsOf: [0, a, b,  0, b, a])             // front face (toward +Z)
            idx.append(contentsOf: [backC, b2, a2,  backC, a2, b2]) // back face (toward −Z)
            doubleSidedQuad(a, b, b2, a2, into: &idx)               // the rim
        }
        return build(p, idx, fallback: max(w, h))
    }

    /// Four-sided pyramid for the Solar Sands decor.
    static func pyramid(halfBase b: Float, height h: Float) -> MeshResource {
        let p: [SIMD3<Float>] = [
            [-b, 0, -b], [b, 0, -b], [b, 0, b], [-b, 0, b],  // base 0..3 (CCW from above)
            [0, h, 0],                                         // apex 4
        ]
        let idx: [UInt32] = [
            1, 0, 4,  2, 1, 4,  3, 2, 4,  0, 3, 4,   // sides (outward)
            0, 2, 1,  0, 3, 2,                         // base (downward)
        ]
        return build(p, idx, fallback: b)
    }

    /// Ring for the magnet pickup. Lies in the XY plane (hole faces the camera, along +Z).
    static func torus(major R: Float, minor r: Float, majorSeg: Int = 20, minorSeg: Int = 9) -> MeshResource {
        var pos: [SIMD3<Float>] = []
        pos.reserveCapacity(majorSeg * minorSeg)
        for i in 0..<majorSeg {
            let u = Float(i) / Float(majorSeg) * 2 * .pi
            let (cu, su) = (cos(u), sin(u))
            for j in 0..<minorSeg {
                let v = Float(j) / Float(minorSeg) * 2 * .pi
                let (cv, sv) = (cos(v), sin(v))
                pos.append([(R + r * cv) * cu, (R + r * cv) * su, r * sv])
            }
        }
        var idx: [UInt32] = []
        idx.reserveCapacity(majorSeg * minorSeg * 6)
        for i in 0..<majorSeg {
            for j in 0..<minorSeg {
                let a = UInt32(i * minorSeg + j)
                let b = UInt32(((i + 1) % majorSeg) * minorSeg + j)
                let c = UInt32(((i + 1) % majorSeg) * minorSeg + (j + 1) % minorSeg)
                let d = UInt32(i * minorSeg + (j + 1) % minorSeg)
                idx.append(contentsOf: [a, b, c, a, c, d])
            }
        }
        return build(pos, idx, fallback: R + r)
    }

    /// Flat chevron strip for the overdrive boost pad: `chevrons` V-bands in the XZ plane (y = 0),
    /// tips pointing toward −z (down the oncoming track). Single-sided, wound for +y — it is a
    /// floor decal like the lane lines, only ever seen from the chase camera above. Defaults span
    /// z ≈ ±1.03, visually matching the core's |z| < 1.1 trigger window.
    static func chevronStrip(halfWidth w: Float = 0.85, chevrons: Int = 3, sweep s: Float = 0.5,
                             band t: Float = 0.32, spacing: Float = 0.62) -> MeshResource {
        var p: [SIMD3<Float>] = []
        var idx: [UInt32] = []
        p.reserveCapacity(chevrons * 6)
        idx.reserveCapacity(chevrons * 12)
        let total = Float(chevrons - 1) * spacing + s + t
        for k in 0..<chevrons {
            let z0 = total / 2 - Float(k) * spacing     // rear (camera-side) edge of this chevron
            let base = UInt32(p.count)
            p.append(contentsOf: [
                [-w, 0, z0], [0, 0, z0 - s], [0, 0, z0 - s - t], [-w, 0, z0 - t],  // left arm 0–3
                [w, 0, z0], [w, 0, z0 - t],                                        // right edge 4–5
            ])
            idx.append(contentsOf: [
                base, base + 1, base + 2,  base, base + 2, base + 3,               // left arm
                base + 4, base + 2, base + 1,  base + 4, base + 5, base + 2,       // right arm
            ])
        }
        return build(p, idx, fallback: w)
    }

    // MARK: v1.4 sky meshes (WorldSky) — flat single-sided cards facing the chase camera (+Z),
    // wound CCW-from-+Z so back-face culling never hides them from the player.

    /// Filled disc in the XY plane facing +Z (sun + halo, glow motes, lit windows). Unit radius
    /// is the common case — entities scale it, so ONE mesh serves every disc in the sky.
    static func disc(radius r: Float = 1, segments n: Int = 22) -> MeshResource {
        var p: [SIMD3<Float>] = [[0, 0, 0]]
        p.reserveCapacity(n + 1)
        var idx: [UInt32] = []
        idx.reserveCapacity(n * 3)
        for i in 0..<n {
            let a = Float(i) / Float(n) * 2 * .pi
            p.append([cos(a) * r, sin(a) * r, 0])
        }
        for i in 0..<n {
            idx.append(contentsOf: [0, UInt32(1 + i), UInt32(1 + (i + 1) % n)])
        }
        return build(p, idx, fallback: r)
    }

    /// City-skyline silhouette card: one flat quad per `(width, height)` building, baselines at
    /// y = 0, fixed `gap` between neighbours, the whole row centred on x = 0. A 17-building row
    /// is 34 triangles in ONE mesh — one draw call per depth band.
    static func skyline(buildings: [SIMD2<Float>], gap: Float) -> MeshResource {
        var p: [SIMD3<Float>] = []
        var idx: [UInt32] = []
        p.reserveCapacity(buildings.count * 4)
        idx.reserveCapacity(buildings.count * 6)
        let total = buildings.reduce(Float(0)) { $0 + $1.x } + gap * Float(buildings.count - 1)
        var x = -total / 2
        for b in buildings {
            let base = UInt32(p.count)
            p.append(contentsOf: [[x, 0, 0], [x + b.x, 0, 0], [x + b.x, b.y, 0], [x, b.y, 0]])
            idx.append(contentsOf: [base, base + 1, base + 2, base, base + 2, base + 3])
            x += b.x + gap
        }
        return build(p, idx, fallback: total / 2)
    }

    /// Rolling silhouette ridge (the Sands dune layers): `heights` sampled uniformly across
    /// `width`, filled down to the y = 0 baseline.
    static func ridge(width: Float, heights: [Float]) -> MeshResource {
        let n = heights.count
        var p: [SIMD3<Float>] = []
        var idx: [UInt32] = []
        p.reserveCapacity(n * 2)
        idx.reserveCapacity((n - 1) * 6)
        for (i, h) in heights.enumerated() {
            let x = -width / 2 + width * Float(i) / Float(n - 1)
            p.append([x, 0, 0])                  // bottom edge (even indices)
            p.append([x, max(h, 0.01), 0])       // crest (odd indices)
        }
        for i in 0..<(n - 1) {
            let a = UInt32(i * 2)
            idx.append(contentsOf: [a, a + 2, a + 3, a, a + 3, a + 1])
        }
        return build(p, idx, fallback: width / 2)
    }

    /// Searchlight beam: a thin trapezoid fanning out from the origin along +Y — anchor it on a
    /// rooftop and rotate about Z to sweep.
    static func beam(length: Float, halfWidthNear: Float, halfWidthFar: Float) -> MeshResource {
        let p: [SIMD3<Float>] = [
            [-halfWidthNear, 0, 0], [halfWidthNear, 0, 0],
            [halfWidthFar, length, 0], [-halfWidthFar, length, 0],
        ]
        return build(p, [0, 1, 2, 0, 2, 3], fallback: length)
    }

    /// Wavy horizon band (the Caverns aurora): two-sine top/bottom edges of constant `thickness`
    /// undulating around y = 0.
    static func ribbon(width: Float, thickness: Float, amplitude: Float, waves: Float,
                       phase: Float, samples n: Int = 48) -> MeshResource {
        var p: [SIMD3<Float>] = []
        var idx: [UInt32] = []
        p.reserveCapacity(n * 2)
        idx.reserveCapacity((n - 1) * 6)
        for i in 0..<n {
            let u = Float(i) / Float(n - 1)
            let x = -width / 2 + width * u
            let mid = amplitude * sin(u * waves * 2 * .pi + phase)
                + amplitude * 0.45 * sin(u * waves * 4.7 + phase * 1.7)
            p.append([x, mid - thickness / 2, 0])
            p.append([x, mid + thickness / 2, 0])
        }
        for i in 0..<(n - 1) {
            let a = UInt32(i * 2)
            idx.append(contentsOf: [a, a + 2, a + 3, a, a + 3, a + 1])
        }
        return build(p, idx, fallback: width / 2)
    }

    /// Free-hanging tapering strip (Tidal Glow jellyfish tentacles): a two-rail ribbon running down
    /// −Y, the sway baked in and growing toward the tip, the width tapering to a near-point. Rotate
    /// the entity to fan tentacles radially. Unlike `ridge` it does NOT fill to a baseline.
    static func tentacleStrip(length: Float, width: Float, amplitude: Float, waves: Float = 1.6,
                              phase: Float = 0, segments n: Int = 14) -> MeshResource {
        var p: [SIMD3<Float>] = []
        var idx: [UInt32] = []
        p.reserveCapacity((n + 1) * 2)
        for i in 0...n {
            let u = Float(i) / Float(n)
            let y = -length * u
            let cx = amplitude * sin(u * waves * 2 * .pi + phase) * u   // sway grows toward the tip
            let hw = width * (1 - u) * 0.5 + 0.004                      // taper to a near-point
            p.append([cx - hw, y, 0])
            p.append([cx + hw, y, 0])
        }
        for i in 0..<n {
            let a = UInt32(i * 2)
            idx.append(contentsOf: [a, a + 2, a + 3, a, a + 3, a + 1])
        }
        return build(p, idx, fallback: length)
    }

    /// Receding grid card (Datastream): `cols`+`rows` thin quads in ONE flat XY mesh. Perspective
    /// is BAKED — rows pack toward the top edge (u² spacing) and columns fan toward the centre — so
    /// the static card reads as a grid converging to a vanishing point. One draw call.
    static func gridCard(width: Float, height: Float, cols: Int, rows: Int,
                         lineThickness t: Float = 0.06) -> MeshResource {
        var p: [SIMD3<Float>] = []
        var idx: [UInt32] = []
        func quad(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>, _ d: SIMD3<Float>) {
            let base = UInt32(p.count)
            p.append(contentsOf: [a, b, c, d])
            idx.append(contentsOf: [base, base + 1, base + 2, base, base + 2, base + 3])
        }
        let hw = width / 2, hh = height / 2
        for i in 0...rows {                       // horizontal rungs, dense toward the top
            let u = Float(i) / Float(rows)
            let yy = -hh + height * (u * u)
            let rw = hw * (0.22 + 0.78 * (1 - u))  // narrower near the vanishing top
            quad([-rw, yy - t / 2, 0], [rw, yy - t / 2, 0], [rw, yy + t / 2, 0], [-rw, yy + t / 2, 0])
        }
        for j in 0...cols {                       // verticals fanning toward the top centre
            let v = Float(j) / Float(cols)
            let xBot = -hw + width * v
            let xTop = xBot * 0.22
            quad([xBot - t / 2, -hh, 0], [xBot + t / 2, -hh, 0], [xTop + t / 2, hh, 0], [xTop - t / 2, hh, 0])
        }
        return build(p, idx, fallback: max(hw, hh))
    }

    /// Every face here is emitted with BOTH windings. Nothing in this renderer sets `faceCulling`,
    /// so a back face is silently dropped — and the chasm is seen from above, from behind on
    /// approach, and from directly inside at the apex of a jump. That is exactly the situation
    /// where guessing the winding gets you an invisible obstacle and no error to explain it. Ten
    /// extra triangles buys the whole class of bug.
    private static func doubleSidedQuad(_ a: UInt32, _ b: UInt32, _ c: UInt32, _ d: UInt32,
                                        into idx: inout [UInt32]) {
        idx.append(contentsOf: [a, b, c, a, c, d])                   // front
        idx.append(contentsOf: [a, c, b, a, d, c])                   // back
    }

    /// The chasm's four walls (v1.8) — an open-topped, open-bottomed well sunk into the deck, so
    /// the gap reads as real DEPTH rather than a dark decal painted on the floor. Geometry is what
    /// sells the hole; see `RealityRenderer.chasmEntity` for why colour cannot be relied on.
    /// The floor is a separate mesh so the two can take different materials.
    static func chasmWalls(halfWidth w: Float, halfLength l: Float, depth d: Float) -> MeshResource {
        let p: [SIMD3<Float>] = [
            [-w, 0, -l], [w, 0, -l], [w, 0, l], [-w, 0, l],          // rim   0…3
            [-w, -d, -l], [w, -d, -l], [w, -d, l], [-w, -d, l],      // base  4…7
        ]
        var idx: [UInt32] = []
        idx.reserveCapacity(48)
        doubleSidedQuad(0, 1, 5, 4, into: &idx)                      // far wall
        doubleSidedQuad(1, 2, 6, 5, into: &idx)                      // right wall
        doubleSidedQuad(2, 3, 7, 6, into: &idx)                      // near wall
        doubleSidedQuad(3, 0, 4, 7, into: &idx)                      // left wall
        return build(p, idx, fallback: w)
    }

    /// The chasm's floor, at `-depth`. Kept near-black so the well reads as receding into nothing
    /// while the walls stay visible against the deck.
    static func chasmFloor(halfWidth w: Float, halfLength l: Float, depth d: Float) -> MeshResource {
        let p: [SIMD3<Float>] = [[-w, -d, -l], [w, -d, -l], [w, -d, l], [-w, -d, l]]
        var idx: [UInt32] = []
        doubleSidedQuad(0, 1, 2, 3, into: &idx)
        return build(p, idx, fallback: w)
    }

    /// A sphere split into `bands` horizontal zones, returned as ONE mesh with one PART per zone —
    /// so the caller assigns `bands` flat `UnlitMaterial`s and gets a static spectrum with no
    /// texture, no gradient shader, and no extra entities (v1.8, D-011).
    ///
    /// Zones are equal in HEIGHT, not equal in angle. On a sphere those are the same thing for
    /// surface area (Archimedes' hat-box theorem), so the bands read evenly wide instead of
    /// bunching at the poles — and it makes the rule trivial for the 2-D swatch to mirror exactly:
    /// split the silhouette's height into N equal strips. That shared rule is what keeps decree 2
    /// (previews never lie) true by construction rather than by two lists of numbers agreeing.
    ///
    /// Faces are double-wound, like the chasm: nothing here sets `faceCulling`, and getting the
    /// winding backwards on the PLAYER would make the character invisible.
    static func bandedSphere(radius r: Float, bands: Int, segments: Int = 24, rings: Int = 3) -> MeshResource {
        var descriptors: [MeshDescriptor] = []
        for band in 0..<bands {
            // Band 0 is the TOP (y = +r) so index 0 of the caller's spectrum is the top colour.
            let yTop = r - 2 * r * Float(band) / Float(bands)
            let yBottom = r - 2 * r * Float(band + 1) / Float(bands)
            var p: [SIMD3<Float>] = []
            var idx: [UInt32] = []
            for j in 0...rings {
                let y = yTop + (yBottom - yTop) * Float(j) / Float(rings)
                let ringR = (max(0, r * r - y * y)).squareRoot()
                for i in 0...segments {
                    let a = 2 * Float.pi * Float(i) / Float(segments)
                    p.append([ringR * cos(a), y, ringR * sin(a)])
                }
            }
            let stride = UInt32(segments + 1)
            for j in 0..<UInt32(rings) {
                for i in 0..<UInt32(segments) {
                    let a = j * stride + i, b = a + 1, c = a + stride, d = c + 1
                    idx.append(contentsOf: [a, c, d, a, d, b])       // front
                    idx.append(contentsOf: [a, d, c, a, b, d])       // back
                }
            }
            var desc = MeshDescriptor(name: "band\(band)")
            desc.positions = MeshBuffers.Positions(p)
            desc.primitives = .triangles(idx)
            desc.materials = .allFaces(UInt32(band))                 // one material slot per band
            descriptors.append(desc)
        }
        return (try? MeshResource.generate(from: descriptors)) ?? .generateSphere(radius: r)
    }

    private static func build(_ positions: [SIMD3<Float>], _ indices: [UInt32], fallback: Float) -> MeshResource {
        var d = MeshDescriptor(name: "procedural")
        d.positions = MeshBuffers.Positions(positions)
        d.primitives = .triangles(indices)
        return (try? MeshResource.generate(from: [d])) ?? .generateSphere(radius: fallback)
    }
}

/// ONE source of truth for the character body-silhouette proportions, shared by the 3D rig
/// meshes (`RealityRenderer.buildCharacter`) and the 2D Canvas previews
/// (`AnimatedCharacterSwatch.bodyPath`) — so the select/shop silhouette math and the in-run
/// mesh/scale agree by construction (decree 2, AUDIT D2-5; pinned by CharacterParityTests).
/// Everything is expressed relative to the sphere body: `sphereRadius` in rig world units;
/// the preview's `bodyR` (points) plays exactly the same role.
enum CharacterProportions {
    /// Rig sphere body radius (world units) — the shipped v1.3 value, unchanged.
    static let sphereRadius: Float = 0.62
    /// Cube edge as a fraction of the sphere DIAMETER (rig 1.06 / 1.24 ≈ 0.855 — the preview
    /// previously drew the cube at 100% of the footprint, ~17% wider than the rig renders).
    static let cubeEdgeRatio: Float = 1.06 / 1.24
    /// Cube corner radius as a fraction of the cube edge (rig 0.18 / 1.06).
    static let cubeCornerRatio: Float = 0.18 / 1.06
    /// Crystal (octahedron) half-width as a fraction of the sphere radius — the documented
    /// DESIGN_characters §4.1 silhouette the previews have always sold.
    static let crystalHalfWidthRatio: Float = 0.95
    /// Crystal half-height as a fraction of the sphere radius — §4.1's vertical elongation.
    /// The rig previously shipped a SYMMETRIC octahedron(0.78): ~26% wider than the sphere
    /// where the preview promised 95%, with the elongation existing only in 2D.
    static let crystalHalfHeightRatio: Float = 1.15
}
