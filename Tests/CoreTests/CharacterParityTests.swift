// Mac test bundle only: `CharacterProportions` lives in Render/ (ProceduralMesh.swift), which
// the Linux/SPM package never compiles — the UIKit gate keeps `swift test` green everywhere
// while the full xcodebuild suite enforces the pins.
#if canImport(UIKit)
import XCTest
@testable import PrismRush

/// AUDIT D2-5 pin — preview/rig body-proportion parity. Both sides (the rig meshes in
/// `RealityRenderer.buildCharacter` and the Canvas silhouette in
/// `AnimatedCharacterSwatch.bodyPath`) derive every proportion from `CharacterProportions`,
/// so they agree by construction; these pins make any "tune one side" drift a loud failure
/// and freeze the shipped sphere/cube dimensions exactly.
final class CharacterParityTests: XCTestCase {

    func testProportionContractPins() {
        // The rig sphere is the v1.3 shipped body — the reference everything is relative to.
        XCTAssertEqual(CharacterProportions.sphereRadius, 0.62, accuracy: 0.0001)
        // Cube spans ~85% of the sphere diameter (rig 1.06 / 1.24); corners 0.18 / 1.06.
        XCTAssertEqual(CharacterProportions.cubeEdgeRatio, 0.855, accuracy: 0.005,
                       "cube edge / sphere diameter")
        XCTAssertEqual(CharacterProportions.cubeCornerRatio, 0.170, accuracy: 0.005,
                       "cube corner radius / cube edge")
        // Crystal: DESIGN_characters §4.1 — 95% wide, 115% tall vs the sphere radius.
        XCTAssertEqual(CharacterProportions.crystalHalfWidthRatio, 0.95, accuracy: 0.0001)
        XCTAssertEqual(CharacterProportions.crystalHalfHeightRatio, 1.15, accuracy: 0.0001)
    }

    func testRigDimensionsReproduceShippedSphereAndCube() {
        // The derived rig dims must be EXACTLY what shipped in v1.3 — the parity fix moved
        // the preview's cube span and the crystal's 3D elongation, never the sphere or cube.
        let edge = CharacterProportions.sphereRadius * 2 * CharacterProportions.cubeEdgeRatio
        XCTAssertEqual(edge, 1.06, accuracy: 0.0001, "rig cube edge")
        XCTAssertEqual(edge * CharacterProportions.cubeCornerRatio, 0.18, accuracy: 0.0001,
                       "rig cube corner radius")
    }

    func testCrystalElongationIsRealInBothLayers() {
        // §4.1's vertical elongation (~1.21× taller than wide) — the rig octahedron now
        // carries it too, instead of the old symmetric 0.78 (wide in 3D, slim in 2D).
        let ratio = CharacterProportions.crystalHalfHeightRatio
                  / CharacterProportions.crystalHalfWidthRatio
        XCTAssertEqual(ratio, 1.15 / 0.95, accuracy: 0.001)
        XCTAssertGreaterThan(ratio, 1.0, "crystal must read taller than wide on BOTH sides")
        // And the crystal stays narrower than the sphere body, as every preview promised.
        XCTAssertLessThan(CharacterProportions.crystalHalfWidthRatio, 1.0)
    }
}
#endif
