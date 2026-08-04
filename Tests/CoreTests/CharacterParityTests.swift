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
        // v2.5 REACH values — authored for readability, not inherited from the rig. The rig now
        // reads these rather than carrying its own copy, so one edit here moves both layers.
        XCTAssertEqual(g.Ears.height, 0.56 / 0.62, accuracy: 0.0001)
        XCTAssertEqual(g.Fin.heights, [0.38 / 0.62, 0.65 / 0.62, 0.44 / 0.62])
        XCTAssertEqual(g.Horns.length, 0.65 / 0.62, accuracy: 0.0001)
        XCTAssertEqual(g.Crown.spikeHeight, 0.35 / 0.62, accuracy: 0.0001)
        XCTAssertEqual(g.Halo.radius, 0.44 / 0.62, accuracy: 0.0001)
        // SEATING and identity values — deliberately NOT scaled. A crest is attached to a head and
        // has a character; growing these detaches it or changes what it is. See the file's §3.0 rule.
        XCTAssertEqual(g.Ears.offsetX, 0.26 / 0.62, accuracy: 0.0001)
        XCTAssertEqual(g.Horns.lean, 0.5, accuracy: 0.0001)
        XCTAssertEqual(g.Fin.spacing, 0.20 / 0.62, accuracy: 0.0001)
        XCTAssertEqual(g.Crown.ringRadius, 0.30 / 0.62, accuracy: 0.0001,
                       "the head is only 0.545 bodyR wide at the crest anchor — a bigger ring floats")
        XCTAssertEqual(g.Crown.spikeCount, 5)
        XCTAssertEqual(g.Floppy.dropBelowAnchor, (1.18 - 0.92) / 0.62, accuracy: 0.0001)
        // The aura is untouched by the uplift: it already sets the roster's width on all four
        // legendaries, so growing it is the one change that WOULD cost canvas.
        XCTAssertEqual(g.Aura.majorRadius, 0.95 / 0.62, accuracy: 0.0001)
        XCTAssertEqual(g.Aura.nodeCount, 1, "the swatch's second node was never in the game")
    }

    /// **The rig now READS this spec instead of carrying a parallel copy of it** (v2.5).
    ///
    /// S-018 derived every constant above FROM `buildCrest`/`buildAura`'s literals but never wired
    /// the rig back to them, so `CharacterGeometry` was the source of truth for the swatch and for
    /// `extent(for:)` and *not* for the rig. The practical consequence was sharp: authoring a bigger
    /// ear in the spec would have grown the preview and left the in-run character alone — the exact
    /// over-promise S-018 existed to delete, re-created in one edit, with `testCrestGeometryMatchesTheRig`
    /// failing in a way that invites "fix" by reverting the spec rather than by updating the rig.
    ///
    /// These pin the WORLD-unit values the rig actually builds, `R * <spec>`. They were introduced
    /// against the old literals to prove the rewiring was a no-op (every one reproduced its shipped
    /// literal to within 6e-17) and are now repinned to the v2.5 authored sizes. Keeping them in
    /// world units is not redundant with `testCrestGeometryMatchesTheRig`: that test pins bodyR, and
    /// a botched unit conversion is exactly the class of error that produces a correct-looking ratio
    /// and a wrong-sized character. If someone re-hardcodes a number in `buildCrest`, this test
    /// cannot catch it — nothing in `Meta/` can see `Render/` — but the rig no longer HAS a number
    /// to re-hardcode unless it is put back deliberately.
    func testTheRigsShippedLiteralsAreReproducedFromTheSpec() {
        let R = CharacterGeometry.sphereRadius
        let g = CharacterGeometry.self
        func eq(_ got: Float, _ shipped: Float, _ what: String) {
            XCTAssertEqual(got, shipped, accuracy: 1e-5,
                           "\(what): the rig used to build this at \(shipped); the spec now yields \(got)")
        }
        eq(R * g.Ears.halfBase, 0.16, "ears halfBase");   eq(R * g.Ears.height, 0.56, "ears height")
        eq(R * g.Ears.offsetX, 0.26, "ears offsetX");     eq(g.Ears.lean, 0.18, "ears lean")
        eq(R * g.Floppy.meshRadius, 0.24, "floppy mesh radius")
        eq(R * g.Floppy.offsetX, 0.52, "floppy offsetX")
        eq(R * g.Fin.halfBase, 0.15, "fin halfBase");     eq(R * g.Fin.spacing, 0.20, "fin spacing")
        for (i, shipped) in [Float(0.38), 0.65, 0.44].enumerated() {
            eq(R * g.Fin.heights[i], shipped, "fin spike \(i)")
        }
        eq(R * g.Horns.halfBase, 0.15, "horns halfBase"); eq(R * g.Horns.length, 0.65, "horns length")
        eq(R * g.Horns.offsetX, 0.22, "horns offsetX")
        eq(R * g.Crown.ringRadius, 0.30, "crown ring");   eq(R * g.Crown.ringTube, 0.075, "crown tube")
        eq(R * g.Crown.spikeHalfBase, 0.10, "crown spike halfBase")
        eq(R * g.Crown.spikeHeight, 0.35, "crown spike height")
        eq(R * g.Crown.spikeLift, 0.035, "crown spike lift")
        eq(R * g.Halo.radius, 0.44, "halo radius");       eq(R * g.Halo.tube, 0.09, "halo tube")
        eq(R * g.Halo.float, 0.59, "halo float")
        eq(R * g.Aura.majorRadius, 0.95, "aura major");   eq(R * g.Aura.tube, 0.05, "aura tube")
        eq(R * g.Aura.nodeRadius, 0.09, "aura node")

        // The floppy ear is described twice — as effective radii (which `extent` reads) and as a
        // mesh radius times per-axis scales (which the rig builds). They must agree.
        eq(g.Floppy.meshRadius * g.Floppy.scaleX, g.Floppy.radiusX, "floppy radiusX vs meshRadius*scaleX")
        eq(g.Floppy.meshRadius * g.Floppy.scaleY, g.Floppy.radiusY, "floppy radiusY vs meshRadius*scaleY")
    }

    /// The world-space anchors the rig builds against, which lived as literals inside
    /// `buildCharacter`/`buildCrest` until v2.5. `crestWorldY` must reproduce the shipped 1.18 and
    /// 1.30 — and `crestAnchor` is now an exhaustive `switch`, so a new body shape is a compile
    /// error here rather than a silent inheritance of the sphere's anchor.
    func testTheWorldAnchorsReproduceTheShippedRig() {
        for shape in [Skin.BodyShape.sphere, .cube] {
            XCTAssertEqual(CharacterGeometry.bodyCentreY(shape), 0.66, accuracy: 1e-6)
            XCTAssertEqual(CharacterGeometry.crestWorldY(shape), 1.18, accuracy: 1e-5,
                           "\(shape) crest sat at world y 1.18 in the shipped rig")
        }
        XCTAssertEqual(CharacterGeometry.bodyCentreY(.crystal), 0.72, accuracy: 1e-6)
        XCTAssertEqual(CharacterGeometry.crestWorldY(.crystal), 1.30, accuracy: 1e-5,
                       "the crystal's crest sat at world y 1.30 in the shipped rig")
        // The floppy ear's shipped world height, via the D4 fix that made it anchor-relative.
        let earY = CharacterGeometry.crestWorldY(.sphere)
                 - CharacterGeometry.sphereRadius * CharacterGeometry.Floppy.dropBelowAnchor
        XCTAssertEqual(earY, 0.92, accuracy: 1e-5, "floppy ears hung at world y 0.92 on a sphere")
    }

    /// The specific divergences S-018 closed, still closed — but re-anchored in v2.5, because the
    /// numbers they guarded moved **on purpose**.
    ///
    /// **Read this before touching a bound.** These were originally "must stay near the rig's small
    /// value", which encoded an assumption that turned out to be wrong: that the rig was right and
    /// the swatch was inflated. The rig and swatch did disagree, and S-018 was right to make them
    /// agree — but it made them agree on a number nobody had ever checked for READABILITY. Measured
    /// at the 42 pt shop rail, a crown's point was 6.10 pt tall against a 9 pt smallest type token:
    /// the epic rarity tell was smaller than the price text under it.
    ///
    /// So v2.5 raised them, and the guards are re-anchored to what they were always really for:
    /// **the drawing must never again exceed what the OLD SWATCH drew**, because that is the size
    /// that overflowed every canvas and produced PR-0312/PR-0453. The new authored values land just
    /// under those, which is itself the tell that the old swatch sizes were approximately right and
    /// the rig was the wrong half of the disagreement.
    func testTheClosedDivergencesStayClosed() {
        // Horns were the worst: the swatch drew the apex at 1.370 bodyR, 2.02x the rig's 0.680.
        let hornApex = CharacterGeometry.Horns.offsetX
                     + sin(CharacterGeometry.Horns.lean) * CharacterGeometry.Horns.length
        XCTAssertEqual(hornApex, 0.857, accuracy: 0.002, "horn apex reach, bodyR (v2.5 authored)")
        XCTAssertLessThan(hornApex, 1.370, "the swatch's old 1.370 must never come back")

        // Each bound is the value the OLD SWATCH drew. Authored growth up to it is allowed; past it
        // is the bug coming back. Quoted from the constants' own doc comments.
        XCTAssertLessThan(CharacterGeometry.Crown.spikeHeight, 0.62,
                          "the swatch's old centre spike was 0.62 bodyR")
        XCTAssertLessThan(CharacterGeometry.Ears.height, 0.92,
                          "the swatch's old ear was 0.92 bodyR")
        XCTAssertLessThan(CharacterGeometry.Fin.heights.max()!, 1.05,
                          "the swatch's old centre tooth was 1.05 bodyR")
        // The antenna was 17% SHORT of the rig — the one divergence pointing the other way. It is
        // NOT part of the v2.5 uplift and must not have moved.
        XCTAssertEqual(CharacterGeometry.antennaStemLength, 0.42 / 0.62, accuracy: 0.0001)
        XCTAssertGreaterThan(CharacterGeometry.antennaStemLength, 0.60)
    }

    /// **The uplift must be free.** The whole reason v2.5 could raise every crest at once is that
    /// none of them sets the roster envelope — monarch's aura sets `side`, its antenna sets `up`,
    /// and the trail wisp sets `down`. If a future crest change starts driving an axis, the canvas
    /// grows, `testNoCallSiteBleedsOntoItsNeighbours` fails, and someone will be tempted to widen an
    /// allowance instead of noticing why. This fails first, and says why.
    /// Note the property is about the ROSTER MAXIMUM, not about any one skin. A crest is very often
    /// the tallest thing on its own character — that is the point of a crest — and an earlier draft
    /// of this test wrongly asserted per-skin independence and failed on ten skins. What must hold
    /// is that no crest reaches past the skin that SETS each axis (monarch on all three).
    func testNoCrestDrivesTheRosterEnvelope() {
        func envelope(strippingCrests: Bool) -> CharacterGeometry.Extent {
            SkinCatalog.all.reduce(CharacterGeometry.Extent.zero) { acc, skin in
                var s = skin
                if strippingCrests { s.crest = .none }
                let e = CharacterGeometry.extent(for: s)
                let k = 0.5 * s.scale
                return acc.union(.init(up: e.up * k, down: e.down * k, side: e.side * k))
            }
        }
        let real = envelope(strippingCrests: false)
        let bare = envelope(strippingCrests: true)
        XCTAssertEqual(real.up, bare.up, accuracy: 1e-5,
                       "a crest now sets the roster's upward reach — the canvas must grow, so the "
                       + "call-site slots must be RE-DERIVED, never the bleed allowance widened")
        XCTAssertEqual(real.side, bare.side, accuracy: 1e-5,
                       "a crest now sets the roster's half-width — same warning as above")
        // And so the pinned envelope is the same three numbers S-018 measured, uplift and all.
        XCTAssertEqual(real.side, 0.923, accuracy: 0.01)
        XCTAssertEqual(real.up, 1.111, accuracy: 0.01)
        XCTAssertEqual(real.down, 0.724, accuracy: 0.01)
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
        // widest feature (the aura, 1.677 bodyR), the tallest antenna reach (h 1.2, tip 1.5), and
        // the trail wisp below (1.225 bodyR, which outreaches even the aura's lower arc at 0.730).
        XCTAssertEqual(e.side, 0.923, accuracy: 0.01, "roster half-width, in units of `size`")
        XCTAssertEqual(e.up, 1.111, accuracy: 0.01, "roster reach above centre")
        XCTAssertEqual(e.down, 0.724, accuracy: 0.01, "roster reach below centre")
        // A canvas sized from this must hold every single skin, with the bob at its worst.
        for skin in SkinCatalog.all {
            let s = CharacterGeometry.extent(for: skin)
            let k = 0.5 * skin.scale
            XCTAssertLessThanOrEqual(s.side * k, e.side + 0.0001, "\(skin.id) overflows sideways")
            XCTAssertLessThanOrEqual(s.up * k, e.up + 0.0001, "\(skin.id) overflows upward")
            XCTAssertLessThanOrEqual(s.down * k, e.down + 0.0001, "\(skin.id) overflows downward")
        }
    }

    /// No shipped call site may spill onto its neighbours. This is the test PR-0312 needed and
    /// could never have: the slot numbers used to be literals in `UI/`, which `swift test` does
    /// not compile, so the defect was structurally invisible to CI for sixteen sessions.
    func testNoCallSiteBleedsOntoItsNeighbours() {
        for site in CharacterSwatchSlot.allCases {
            let bleed = site.bleed
            let allowed = site.bleedAllowance
            XCTAssertLessThanOrEqual(bleed.horizontal, allowed.horizontal,
                                     "\(site.rawValue): spills \(bleed.horizontal) pt sideways, "
                                     + "only \(allowed.horizontal) pt is free")
            XCTAssertLessThanOrEqual(bleed.vertical, allowed.vertical,
                                     "\(site.rawValue): spills \(bleed.vertical) pt vertically, "
                                     + "only \(allowed.vertical) pt is free")
        }
    }

    /// The two sites whose neighbours are close enough that they take a zero-bleed slot.
    func testTheTightSitesAreActuallyTight() {
        for site in [CharacterSwatchSlot.selectNextUnlock, .shopFeatured] {
            XCTAssertEqual(site.bleed.horizontal, 0, accuracy: 0.001, site.rawValue)
            XCTAssertEqual(site.bleed.vertical, 0, accuracy: 0.001, site.rawValue)
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
