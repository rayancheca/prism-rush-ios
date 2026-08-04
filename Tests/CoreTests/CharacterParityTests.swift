import XCTest
@testable import PrismRush

/// Decree 2 — previews never lie — as a test rather than as a convention.
///
/// A character is drawn twice: as RealityKit meshes (`RealityRenderer.buildCharacter`,
/// `buildCrest`, `buildAura`) and as Canvas paths (`AnimatedCharacterSwatch`). Both now derive
/// every proportion from `CharacterGeometry`, so they agree by construction; these pins make any
/// "tune one side" drift a loud failure.
///
/// **This file used to be `#if canImport(UIKit)`-gated** and therefore did not run under
/// `swift test` — because `CharacterProportions` lived in `Render/`, which `Package.swift` never
/// compiled. That gate is why PR-0312 (23 of 24 characters cropped) survived sixteen sessions:
/// the only tests that could have caught it were invisible to CI. The spec moved to `Meta/`, the
/// gate is gone, and these run on Linux on every push.
final class CharacterParityTests: XCTestCase {

    // MARK: - Body — the v1.3 shipped pins, unchanged

    func testProportionContractPins() {
        // The rig sphere is the v1.3 shipped body — the reference everything is relative to.
        XCTAssertEqual(CharacterGeometry.sphereRadius, 0.62, accuracy: 0.0001)
        // Cube spans ~85% of the sphere diameter (rig 1.06 / 1.24); corners 0.18 / 1.06.
        XCTAssertEqual(CharacterGeometry.cubeEdgeRatio, 0.855, accuracy: 0.005,
                       "cube edge / sphere diameter")
        XCTAssertEqual(CharacterGeometry.cubeCornerRatio, 0.170, accuracy: 0.005,
                       "cube corner radius / cube edge")
        // Crystal: DESIGN_characters §4.1 — 95% wide, 115% tall vs the sphere radius.
        XCTAssertEqual(CharacterGeometry.crystalHalfWidthRatio, 0.95, accuracy: 0.0001)
        XCTAssertEqual(CharacterGeometry.crystalHalfHeightRatio, 1.15, accuracy: 0.0001)
    }

    func testRigDimensionsReproduceShippedSphereAndCube() {
        // The derived rig dims must be EXACTLY what shipped in v1.3 — the parity fix moved
        // the preview's cube span and the crystal's 3D elongation, never the sphere or cube.
        let edge = CharacterGeometry.sphereRadius * 2 * CharacterGeometry.cubeEdgeRatio
        XCTAssertEqual(edge, 1.06, accuracy: 0.0001, "rig cube edge")
        XCTAssertEqual(edge * CharacterGeometry.cubeCornerRatio, 0.18, accuracy: 0.0001,
                       "rig cube corner radius")
    }

    func testCrystalElongationIsRealInBothLayers() {
        // §4.1's vertical elongation (~1.21× taller than wide) — the rig octahedron now
        // carries it too, instead of the old symmetric 0.78 (wide in 3D, slim in 2D).
        let ratio = CharacterGeometry.crystalHalfHeightRatio
                  / CharacterGeometry.crystalHalfWidthRatio
        XCTAssertEqual(ratio, 1.15 / 0.95, accuracy: 0.001)
        XCTAssertGreaterThan(ratio, 1.0, "crystal must read taller than wide on BOTH sides")
        // And the crystal stays narrower than the sphere body, as every preview promised.
        XCTAssertLessThan(CharacterGeometry.crystalHalfWidthRatio, 1.0)
    }

    // MARK: - Crest, antenna and aura — no coverage AT ALL before v2.4
    //
    // `grep -rn "crest\|aura" Tests/ UITests/` returned zero matches for sixteen sessions, on
    // either side of the seam. Every number below is the rig's, converted to bodyR; they are
    // pinned so that the next session to touch either layer has to touch this file too.

    func testCrestGeometryMatchesTheRig() {
        let g = CharacterGeometry.self
        XCTAssertEqual(g.Ears.height, 0.36 / 0.62, accuracy: 0.0001)
        XCTAssertEqual(g.Ears.offsetX, 0.26 / 0.62, accuracy: 0.0001)
        XCTAssertEqual(g.Fin.heights, [0.24 / 0.62, 0.42 / 0.62, 0.28 / 0.62])
        XCTAssertEqual(g.Horns.length, 0.42 / 0.62, accuracy: 0.0001)
        XCTAssertEqual(g.Horns.lean, 0.5, accuracy: 0.0001)
        XCTAssertEqual(g.Crown.spikeHeight, 0.18 / 0.62, accuracy: 0.0001)
        XCTAssertEqual(g.Crown.spikeCount, 5)
        XCTAssertEqual(g.Halo.radius, 0.34 / 0.62, accuracy: 0.0001)
        XCTAssertEqual(g.Aura.majorRadius, 0.95 / 0.62, accuracy: 0.0001)
        XCTAssertEqual(g.Aura.nodeCount, 1, "the swatch's second node was never in the game")
    }

    /// The specific divergences this pass closed, pinned as inequalities against the values the
    /// swatch used to draw — so a future edit that quietly restores one of them fails here with
    /// its own name on it.
    func testTheClosedDivergencesStayClosed() {
        // Horns were the worst: the swatch drew the apex at 1.370 bodyR, 2.02x the rig's 0.680.
        let hornApex = CharacterGeometry.Horns.offsetX
                     + sin(CharacterGeometry.Horns.lean) * CharacterGeometry.Horns.length
        XCTAssertEqual(hornApex, 0.680, accuracy: 0.002, "horn apex reach, bodyR")
        XCTAssertLessThan(hornApex, 1.0, "the swatch's old 1.370 must never come back")

        // The crown's centre spike was 2.14x, its outer spikes 1.45x — one crest, two factors.
        XCTAssertLessThan(CharacterGeometry.Crown.spikeHeight, 0.40)
        // Ears and fin were a consistent ~1.55x.
        XCTAssertLessThan(CharacterGeometry.Ears.height, 0.70)
        XCTAssertLessThan(CharacterGeometry.Fin.heights.max()!, 0.80)
        // The antenna was 17% SHORT of the rig — the one divergence pointing the other way.
        XCTAssertEqual(CharacterGeometry.antennaStemLength, 0.42 / 0.62, accuracy: 0.0001)
        XCTAssertGreaterThan(CharacterGeometry.antennaStemLength, 0.60)
    }

    /// D1 — the rig pinned the antenna socket at world y 1.21 for every body shape, so the stem
    /// was buried a third of the way into a crystal and floated clear of a cube.
    func testTheAntennaSocketIsShapeAwareAndTheSphereIsUnchanged() {
        let g = CharacterGeometry.self
        // The sphere is the shipped look and must be reproduced byte-for-byte.
        XCTAssertEqual(g.antennaBase(.sphere), (1.21 - 0.66) / 0.62, accuracy: 0.0001,
                       "the shipped sphere socket must not move")
        // Every shape now sockets the stem INSIDE its own body, by the same depth.
        for shape in [Skin.BodyShape.sphere, .cube, .crystal] {
            let base = g.antennaBase(shape)
            XCTAssertLessThan(base, g.bodyTop(shape), "\(shape): stem floats above the body")
            XCTAssertEqual(g.bodyTop(shape) - base, g.antennaSocketDepth, accuracy: 0.0001)
        }
        // The old hard-coded world 1.21 put the crystal's stem base 0.360 bodyR BELOW its body
        // top — a third of the way down the gem — and the cube's 0.032 bodyR ABOVE its body top,
        // floating. Both are stated as the depths they were, so the defect stays legible.
        let oldCrystalBase = Float((1.21 - 0.72) / 0.62)
        XCTAssertEqual(g.bodyTop(.crystal) - oldCrystalBase, 0.360, accuracy: 0.002,
                       "the crystal's stem used to start a third of the way down the gem")
        let oldCubeBase = Float((1.21 - 0.66) / 0.62)
        XCTAssertEqual(g.bodyTop(.cube) - oldCubeBase, -0.032, accuracy: 0.002,
                       "the cube's stem used to float clear of its own head")
        // The corrected base lifts the crystal's socket by 0.247 bodyR and drops the cube's.
        XCTAssertEqual(g.antennaBase(.crystal) - oldCrystalBase, 0.247, accuracy: 0.002)
        XCTAssertLessThan(g.antennaBase(.cube), oldCubeBase)
    }

    /// D4 — floppy ears hard-coded world y 0.92 instead of hanging off the crest anchor, so a
    /// crystal body wore them in the wrong place.
    func testFloppyEarsHangOffTheCrestAnchorForEveryShape() {
        let g = CharacterGeometry.self
        for shape in [Skin.BodyShape.sphere, .cube, .crystal] {
            let ear = g.crestAnchor(shape) - g.Floppy.dropBelowAnchor
            XCTAssertLessThan(ear, g.crestAnchor(shape), "\(shape): ears must hang below the crown")
            XCTAssertGreaterThan(ear + g.Floppy.radiusY, 0, "\(shape): ears must reach the head")
        }
        // The sphere keeps its shipped position exactly (rig world 0.92, body centre 0.66).
        XCTAssertEqual(g.crestAnchor(.sphere) - g.Floppy.dropBelowAnchor,
                       Float((0.92 - 0.66) / 0.62), accuracy: 0.0001)
    }

    // MARK: - Extent — the pin that makes cropping impossible rather than fixed-once

    /// Every skin's drawn extent must be finite, positive, and actually contain its own body.
    func testEverySkinHasASaneExtent() {
        for skin in SkinCatalog.all {
            let e = CharacterGeometry.extent(for: skin)
            XCTAssertTrue(e.up.isFinite && e.down.isFinite && e.side.isFinite, skin.id)
            XCTAssertGreaterThanOrEqual(e.up, CharacterGeometry.bodyTop(skin.bodyShape), skin.id)
            XCTAssertGreaterThanOrEqual(e.side, CharacterGeometry.bodyHalfWidth(skin.bodyShape),
                                        skin.id)
            XCTAssertGreaterThan(e.down, 0, skin.id)
        }
    }

    /// The roster envelope every call site sizes its canvas from. If a future session adds a
    /// character that needs more room than this, the number moves and every canvas follows —
    /// which is the entire point. This pin exists so that move is deliberate and visible in a
    /// diff, not a silent re-crop of the other 24.
    func testTheRosterEnvelopeIsPinned() {
        let e = CharacterGeometry.rosterExtentInSizeUnits
        // All three axes are set by monarch — the roster's largest body (scale 1.10) wearing the
        // widest feature (the aura, 1.678 bodyR) and a tall antenna (h 1.2, tip 1.5). `down` is
        // the trail wisp rather than the aura: 1.31 bodyR of streaming puffs outreach it.
        XCTAssertEqual(e.side, 0.923, accuracy: 0.01, "roster half-width, in units of `size`")
        XCTAssertEqual(e.up, 1.111, accuracy: 0.01, "roster reach above centre")
        XCTAssertEqual(e.down, 0.771, accuracy: 0.01, "roster reach below centre")
        // A canvas sized from this must hold every single skin, with the bob at its worst.
        for skin in SkinCatalog.all {
            let s = CharacterGeometry.extent(for: skin)
            let k = 0.5 * skin.scale
            XCTAssertLessThanOrEqual(s.side * k, e.side + 0.0001, "\(skin.id) overflows sideways")
            XCTAssertLessThanOrEqual(s.up * k, e.up + 0.0001, "\(skin.id) overflows upward")
            XCTAssertLessThanOrEqual(s.down * k, e.down + 0.0001, "\(skin.id) overflows downward")
        }
    }

    /// The regression this whole pass exists to prevent: at the OLD canvas defaults
    /// (`widthScale 1.0`, `heightScale 1.5`, `verticalAnchor 0.5`) the roster does not fit. If
    /// someone ever "simplifies" the canvas back to those numbers, this says why they cannot.
    func testTheOldCanvasDefaultsProvablyDoNotFitTheRoster() {
        let e = CharacterGeometry.rosterExtentInSizeUnits
        XCTAssertGreaterThan(e.side, 0.5, "widthScale 1.0 gave each side only 0.5 x size")
        XCTAssertGreaterThan(e.up, 0.75, "heightScale 1.5 at anchor 0.5 gave 0.75 x size above")
    }
}
