import RealityKit
import simd

/// Code-generated meshes RealityKit doesn't provide as primitives. Built from a `MeshDescriptor`
/// (positions + triangle indices). No normals: every material here is `UnlitMaterial`, so lighting
/// — and therefore normals — is ignored. Winding is CCW-outward (back faces are culled).
@MainActor
enum ProceduralMesh {

    /// Diamond/gem shape: 6 vertices, 8 faces.
    static func octahedron(_ r: Float) -> MeshResource {
        let p: [SIMD3<Float>] = [
            [r, 0, 0], [-r, 0, 0], [0, r, 0], [0, -r, 0], [0, 0, r], [0, 0, -r],
        ]
        let idx: [UInt32] = [
            2, 4, 0,  2, 0, 5,  2, 5, 1,  2, 1, 4,   // top fan
            3, 0, 4,  3, 5, 0,  3, 1, 5,  3, 4, 1,   // bottom fan
        ]
        return build(p, idx, fallback: r)
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

    private static func build(_ positions: [SIMD3<Float>], _ indices: [UInt32], fallback: Float) -> MeshResource {
        var d = MeshDescriptor(name: "procedural")
        d.positions = MeshBuffers.Positions(positions)
        d.primitives = .triangles(indices)
        return (try? MeshResource.generate(from: [d])) ?? .generateSphere(radius: fallback)
    }
}
