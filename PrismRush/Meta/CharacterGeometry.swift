import Foundation

/// ONE description of a character's shape, read by BOTH layers that draw one.
///
/// A character is built twice in this app — as RealityKit meshes in
/// `RealityRenderer.buildCharacter/buildCrest/buildAura`, and as Canvas paths in
/// `AnimatedCharacterSwatch`. Until v2.4 the only thing the two shared was the *body*
/// (the five constants below under "body"), which is why `CharacterParityTests` could pin
/// the body and nothing else. Every crest, the antenna and the aura were two hand-tuned
/// number sets with no shared constant and no test: `grep -rn "crest\|aura" Tests/ UITests/`
/// returned zero matches for sixteen sessions, and the two sets had drifted as far as **2.0×**
/// (the swatch drew horns twice as wide as the rig builds them). That is decree 2 — previews
/// never lie — failing quietly, and it is why PR-0312 and PR-0453 kept coming back.
///
/// **Everything here is in `bodyR`** — multiples of the sphere body's radius, measured from the
/// body's centre, +y up. Both layers have a `bodyR`, which is what makes one table serve both:
///
/// | layer | `bodyR` | source |
/// |---|---|---|
/// | rig | `sphereRadius` = 0.62 world units | `RealityRenderer.buildCharacter` |
/// | swatch | `size * 0.5 * skin.scale` points | `AnimatedCharacterSwatch.draw` |
///
/// **Where the two disagreed, the rig's number is the one recorded**, because the rig is the
/// character the player actually runs with and the swatch's crests were authored into a canvas
/// that cropped their tops off (23 of 24 — see `extent(for:)`), so "the swatch was tuned against
/// what it looks like" was never available as an argument. Four places where the *rig* was
/// provably defective are corrected here instead of copied — each is marked `DEFECT` below.
///
/// **What this file deliberately does NOT carry: the face.** The rig's eyes sit at z 0.52, so
/// under the chase camera their screen position depends on the rig's forward lean, which is a
/// function of speed (`RealityRenderer:402`, `pitch = -0.16 * speedNorm`) — the in-run eye ranges
/// over −0.074…+0.029 bodyR and crosses the body equator at speed 29.24. There is no single
/// number to record until someone picks a canonical pose, and the rig is `isEnabled = false`
/// outside a live run (`RealityRenderer:389`) so its rest pose is not a thing anyone sees.
/// Matching the preview to the rest pose would be a decree-2 regression wearing a decree-2
/// justification. The eyes stay where they are on both sides; see D-055.
///
/// Foundation only, and listed in `Package.swift` — so `swift test` compiles it on Linux and
/// `CharacterParityTests` runs everywhere instead of only inside Xcode.
enum CharacterGeometry {

    // MARK: - Body (v1.3 shipped, unchanged — formerly `CharacterProportions`)

    /// Rig sphere body radius, in world units. The datum: every other figure in this file is a
    /// multiple of this, and `1.0 bodyR` means exactly this length.
    static let sphereRadius: Float = 0.62
    /// Cube edge as a fraction of the sphere DIAMETER (rig 1.06 / 1.24).
    static let cubeEdgeRatio: Float = 1.06 / 1.24
    /// Cube corner radius as a fraction of the cube edge (rig 0.18 / 1.06).
    static let cubeCornerRatio: Float = 0.18 / 1.06
    /// Crystal (octahedron) half-width as a fraction of the sphere radius.
    static let crystalHalfWidthRatio: Float = 0.95
    /// Crystal half-height as a fraction of the sphere radius — §4.1's vertical elongation.
    static let crystalHalfHeightRatio: Float = 1.15

    /// How far the body's silhouette reaches straight up from its centre, per shape. The antenna
    /// socket and the crest anchor both hang off this, which is what stops a taller body from
    /// swallowing its own antenna.
    static func bodyTop(_ shape: Skin.BodyShape) -> Float {
        switch shape {
        case .sphere:  return 1.0
        case .cube:    return cubeEdgeRatio
        case .crystal: return crystalHalfHeightRatio
        }
    }

    /// How far the body reaches sideways from its centre, per shape.
    static func bodyHalfWidth(_ shape: Skin.BodyShape) -> Float {
        switch shape {
        case .sphere:  return 1.0
        case .cube:    return cubeEdgeRatio
        case .crystal: return crystalHalfWidthRatio
        }
    }

    /// The rig's body-centre height above the deck, in WORLD units, per shape.
    ///
    /// This was the hidden third number behind every conversion in this file: `crestAnchor` and
    /// `antennaSocketDepth` are both differences measured against it, and until v2.5 it existed only
    /// as two literals inside `RealityRenderer.buildCharacter` (`bodyY = 0.66`, reassigned to `0.72`
    /// for the crystal). Recording it here is what lets the rig compute a crest's world height from
    /// the spec instead of from a parallel literal.
    ///
    /// These are AUTHORED, not derived — the three shapes do not share a rule. Their lowest points
    /// sit at 0.040 (sphere), 0.130 (cube) and 0.007 (crystal) above the deck. A new body shape must
    /// therefore choose a value here rather than inherit one, which is why this is an exhaustive
    /// `switch` and not the ternary it replaced.
    static func bodyCentreY(_ shape: Skin.BodyShape) -> Float {
        switch shape {
        case .sphere:  return 0.66
        case .cube:    return 0.66
        case .crystal: return 0.72
        }
    }

    /// Where a crest sits in WORLD units — the rig's `crestY`, derived rather than re-typed.
    /// Reproduces the shipped 1.18 (sphere/cube) and 1.30 (crystal) exactly.
    static func crestWorldY(_ shape: Skin.BodyShape) -> Float {
        bodyCentreY(shape) + sphereRadius * crestAnchor(shape)
    }

    // MARK: - Anchors

    /// Where a crest roots, in bodyR above the body centre.
    ///
    /// Rig: `crestY` 1.18 with the body at 0.66 → (1.18 − 0.66) / 0.62. The crystal's rig value
    /// (1.30 against a body centre of 0.72) works out to 0.9355, and the swatch drew 1.02 — a
    /// 9 % gap nobody could see because both were cropped.
    /// **Exhaustive on purpose.** This was a `shape == .crystal ? … : …` ternary until v2.5, which
    /// meant it COMPILED for a new body shape and silently handed it the sphere's anchor — on a body
    /// taller than a sphere that roots the crest *inside the head*, with no test failing and both
    /// layers agreeing about the wrong number. A `switch` makes a new shape a build error here,
    /// where the decision belongs.
    static func crestAnchor(_ shape: Skin.BodyShape) -> Float {
        switch shape {
        case .sphere:  return (1.18 - 0.66) / sphereRadius
        case .cube:    return (1.18 - 0.66) / sphereRadius
        case .crystal: return (1.30 - 0.72) / sphereRadius
        }
    }

    /// **DEFECT D1, corrected here.** The rig pins the antenna's stem bottom at world y 1.21 for
    /// every body (`RealityRenderer:1244`) with no shape branch, so the stem's socket depth is an
    /// accident of how tall the body happens to be: it is 0.113 bodyR inside a sphere (correct and
    /// shipped), **0.360 bodyR inside a crystal** — buried, a third of the way down the gem — and
    /// **0.032 bodyR clear of a cube**, floating in mid-air. Deriving it from `bodyTop` reproduces
    /// the sphere byte-for-byte and fixes the other two.
    static let antennaSocketDepth: Float = 1.0 - (1.21 - 0.66) / sphereRadius   // 0.11290 bodyR

    /// Where the antenna's stem bottom sits, in bodyR above the body centre.
    static func antennaBase(_ shape: Skin.BodyShape) -> Float {
        bodyTop(shape) - antennaSocketDepth
    }

    // MARK: - Antenna

    /// Stem length per unit of `Skin.antennaHeightScale` (rig 0.42 world). The swatch drew
    /// `0.56 bodyR` — 17 % short of the rig on every one of the 24 characters.
    static let antennaStemLength: Float = 0.42 / sphereRadius        // 0.67742
    /// Tip sphere radius per unit of `Skin.antennaTipScale` (rig 0.095 world).
    static let antennaTipRadius: Float = 0.095 / sphereRadius        // 0.15323
    /// Stem half-thickness (rig cylinder radius 0.025).
    static let antennaStemRadius: Float = 0.025 / sphereRadius       // 0.04032

    // MARK: - Crests
    //
    // Each case carries the rig's numbers converted to bodyR. The swatch's old values are quoted
    // beside the ones that had actually drifted, so a future reader can see what moved and why
    // rather than having to diff two files in their head.

    /// Upright cat ears flanking the antenna (`RealityRenderer:1299-1303`).
    enum Ears {
        /// v2.5: 0.36 → 0.56 world (**×1.56**). Was `spike(halfBase: 0.11, height: 0.36)`.
        /// At 0.90323 bodyR this lands just under the **0.92** the old swatch drew — see the
        /// section header above for why that is the point rather than a coincidence.
        static let height: Float = 0.56 / sphereRadius               // 0.90323
        /// v2.5: 0.11 → 0.16 world (×1.45). A 6.10 pt-wide ear base at the 42 pt rail was thinner
        /// than the app's smallest type token; widening the base is what stops an ear reading as a
        /// stray line rather than as a triangle.
        static let halfBase: Float = 0.16 / sphereRadius             // 0.25806
        static let offsetX: Float = 0.26 / sphereRadius              // 0.41935
        /// Outward lean, radians. Applied as `∓lean` about z, mirrored per side.
        static let lean: Float = 0.18
        /// Depth squash, as a fraction of the piece's width. **Rig-only** — the swatch is 2-D and
        /// has no z — but it is still a proportion of the character, so it belongs to the spec
        /// rather than to `buildCrest`, where it was an unnamed literal until v2.5.
        static let flatZ: Float = 0.5
        /// The darker inner ear exists only in the swatch today. It is what makes an ear read as
        /// an ear rather than a triangle, so the rig gains it rather than the swatch losing it —
        /// as a fraction of the outer ear. v2.5: 0.55 → 0.62, so the inner ear grows slightly
        /// faster than its shell and does not become a sliver inside a bigger triangle.
        static let innerScale: Float = 0.62
    }

    /// Drooping dog/bunny ears at the sides (`RealityRenderer:1304-1310`).
    enum Floppy {
        /// **DEFECT D4, corrected here.** The rig hard-codes world y 0.92 (`:1307`) instead of
        /// hanging off `crestY` like every other crest, so a crystal body wears its ears in the
        /// wrong place. Recorded as a drop BELOW the crest anchor, which is shape-aware for free.
        static let dropBelowAnchor: Float = (1.18 - 0.92) / sphereRadius   // 0.41935
        /// v2.5: the ear's mesh radius 0.17 → 0.24 world (**×1.41**), scales unchanged.
        static let radiusX: Float = 0.24 * 0.7 / sphereRadius        // 0.27097
        static let radiusY: Float = 0.24 * 1.3 / sphereRadius        // 0.50323
        /// Seating — unchanged. Moving it outward would detach the ears from the head.
        static let offsetX: Float = 0.52 / sphereRadius              // 0.83871
        /// The rig builds this ear as a sphere of `meshRadius` scaled per axis, so the two factors
        /// are recorded separately from the effective radii above. `radiusX == meshRadius * scaleX`
        /// and `radiusY == meshRadius * scaleY` by construction — pinned in `CharacterParityTests`
        /// so the two descriptions can never drift apart.
        static let meshRadius: Float = 0.24 / sphereRadius           // 0.38710
        static let scaleX: Float = 0.7
        static let scaleY: Float = 1.3
        /// Depth squash. Rig-only, like `Ears.flatZ`.
        static let scaleZ: Float = 0.5
    }

    /// Sawtooth dorsal mohawk across the crown (`RealityRenderer:1311-1314`).
    enum Fin {
        /// Spike heights, left → right. v2.5: [0.24, 0.42, 0.28] → [0.38, 0.65, 0.44] world
        /// (**×1.55**), which is essentially the [0.60, 1.05, 0.72] bodyR the old swatch drew.
        static let heights: [Float] = [0.38 / sphereRadius, 0.65 / sphereRadius, 0.44 / sphereRadius]
        /// v2.5: 0.11 → 0.15 world (×1.36).
        static let halfBase: Float = 0.15 / sphereRadius             // 0.24194
        /// Seating — unchanged. Widening it slides the outer teeth off the crown.
        static let spacing: Float = 0.20 / sphereRadius              // 0.32258
        /// Depth squash. Rig-only, like `Ears.flatZ`.
        static let flatZ: Float = 0.4
    }

    /// Two horns sweeping up and out (`RealityRenderer:1315-1319`).
    ///
    /// **The worst divergence in the file.** The rig leans a 0.42-long spike by 0.5 rad from a
    /// base at x ±0.22, putting its apex at 0.680 bodyR. The swatch drew the apex at
    /// **1.370 bodyR — 2.02× as wide**, which at a 56 pt grid card is 19.3 pt of horn that the
    /// in-run character does not have, and most of why five skins clipped their own card.
    enum Horns {
        /// v2.5: 0.42 → 0.65 world (**×1.55**). Apex moves 0.680 → 0.920 bodyR — still well under
        /// the **1.370** the old swatch drew, so the anti-regression guard keeps its teeth.
        static let length: Float = 0.65 / sphereRadius               // 1.04839
        /// v2.5: 0.10 → 0.15 world (×1.50).
        static let halfBase: Float = 0.15 / sphereRadius             // 0.24194
        /// Seating — unchanged.
        static let offsetX: Float = 0.22 / sphereRadius              // 0.35484
        /// Outward lean, radians. Identity — changing it stops them being horns.
        static let lean: Float = 0.5
        /// Depth squash. Rig-only, like `Ears.flatZ`.
        static let flatZ: Float = 0.6
    }

    /// A ring of points around the crown (`RealityRenderer:1320-1326`).
    enum Crown {
        /// Seating — unchanged. The head is only 0.545 bodyR wide at the crest anchor
        /// (`√(1 − crestAnchor²)`), so growing the ring would float it either side of the skull.
        static let ringRadius: Float = 0.30 / sphereRadius           // 0.48387
        /// v2.5: 0.045 → 0.075 world (**×1.67**). The band was 3.05 pt thick at the 42 pt rail.
        static let ringTube: Float = 0.075 / sphereRadius            // 0.12097
        /// v2.5: 0.06 → 0.10 world (×1.67).
        static let spikeHalfBase: Float = 0.10 / sphereRadius        // 0.16129
        /// v2.5: 0.18 → 0.35 world (**×1.94**, the largest uplift in the file). A 6.10 pt point was
        /// the epic rarity tell — smaller than the 9 pt price text beneath it. Lands at 0.565 bodyR,
        /// under the 0.62 the old swatch drew.
        static let spikeHeight: Float = 0.35 / sphereRadius          // 0.56452
        /// v2.5: 0.02 → 0.035 world, kept proportional to the spike.
        static let spikeLift: Float = 0.035 / sphereRadius           // 0.05645
        static let spikeCount = 5
    }

    /// A ring floating above the head (`RealityRenderer:1327-1328`).
    enum Halo {
        /// Height above the crest anchor. v2.5: 0.55 → 0.59 world (×1.07) — lifted only enough to
        /// clear the thicker ring below it, since a halo that floats too high stops reading as
        /// *this character's* halo.
        static let float: Float = 0.59 / sphereRadius                // 0.95161
        /// v2.5: 0.34 → 0.44 world (×1.29).
        static let radius: Float = 0.44 / sphereRadius               // 0.70968
        /// v2.5: 0.05 → 0.09 world (**×1.80**) — a halo is a ring, and a ring reads by its stroke.
        static let tube: Float = 0.09 / sphereRadius                 // 0.14516
    }

    /// The legendary orbit ring (`RealityRenderer:1336-1348`).
    ///
    /// The ring itself is the one feature the two layers already agreed on (1.532 vs 1.500 bodyR —
    /// 2 %). What diverged is the node: the rig orbits **one** sphere of radius 0.145 bodyR, the
    /// swatch drew **two**, each wrapped in a glow disc of `2r`, which is where the extra
    /// 0.26 bodyR of width came from and why all four legendaries clipped on every surface.
    enum Aura {
        /// Ring centre, in bodyR above the body centre (rig ring y 0.70 against a body at 0.66).
        static let centreY: Float = (0.70 - 0.66) / sphereRadius     // 0.06452
        static let majorRadius: Float = 0.95 / sphereRadius          // 1.53226
        static let tube: Float = 0.05 / sphereRadius                 // 0.08065
        /// Tilt off horizontal, radians — the ring's projected semi-minor axis is
        /// `majorRadius * sin(tilt)`.
        static let tilt: Float = 0.38
        static let nodeRadius: Float = 0.09 / sphereRadius           // 0.14516
        /// One, as the rig builds it. The swatch's second node was never in the game.
        static let nodeCount = 1
    }

    // MARK: - Extent — how much room a character actually needs

    /// The box a character's drawing occupies, in bodyR from the figure's centre.
    /// `up`/`down`/`side` are all positive distances.
    struct Extent: Equatable, Sendable {
        var up: Float
        var down: Float
        var side: Float

        static let zero = Extent(up: 0, down: 0, side: 0)

        func union(_ o: Extent) -> Extent {
            Extent(up: max(up, o.up), down: max(down, o.down), side: max(side, o.side))
        }
    }

    /// Everything a skin draws, at the worst phase of its idle animation.
    ///
    /// This is the function that makes cropping impossible rather than fixed-once. It is derived
    /// from the same constants the two layers draw from, so a session that adds a body shape, a
    /// crest or a prop gets a bigger canvas for free instead of discovering six months later that
    /// 23 of 24 characters have their heads cut off.
    ///
    /// **Bob and sway are included on purpose.** A character's identity is static (decree 1) but
    /// the *figure* moves, and a box sized for the rest pose crops the animated one — which is
    /// exactly how the shipped defect happened.
    static func extent(for skin: Skin) -> Extent {
        let shape = skin.bodyShape
        var e = Extent(up: bodyTop(shape), down: bodyTop(shape), side: bodyHalfWidth(shape))

        // Antenna. The stem pivots about its base, so the tallest reach is at zero sway and the
        // widest is at full sway — take both.
        let base = antennaBase(shape)
        let stem = antennaStemLength * skin.antennaHeightScale
        let tipR = antennaTipRadius * skin.antennaTipScale
        let sway = Float(skin.idle.sway)
        e = e.union(Extent(up: base + stem + tipR, down: 0,
                           side: abs(sin(sway)) * stem + tipR))

        // Crest.
        let anchor = crestAnchor(shape)
        switch skin.crest {
        case .none:
            break
        case .ears:
            e = e.union(Extent(up: anchor + Ears.height, down: 0,
                               side: Ears.offsetX + Ears.halfBase))
        case .floppy:
            let cy = anchor - Floppy.dropBelowAnchor
            e = e.union(Extent(up: cy + Floppy.radiusY, down: max(0, Floppy.radiusY - cy),
                               side: Floppy.offsetX + Floppy.radiusX))
        case .fin:
            e = e.union(Extent(up: anchor + (Fin.heights.max() ?? 0), down: 0,
                               side: Fin.spacing + Fin.halfBase))
        case .horns:
            e = e.union(Extent(up: anchor + cos(Horns.lean) * Horns.length, down: 0,
                               side: Horns.offsetX + sin(Horns.lean) * Horns.length))
        case .crown:
            e = e.union(Extent(up: anchor + Crown.spikeLift + Crown.spikeHeight, down: 0,
                               side: Crown.ringRadius + Crown.spikeHalfBase))
        case .halo:
            let cy = anchor + Halo.float
            e = e.union(Extent(up: cy + Halo.tube, down: 0, side: Halo.radius + Halo.tube))
        }

        // Aura — ring plus the orbiting node at its widest pass.
        if skin.hasAura {
            let semiMinor = Aura.majorRadius * sin(Aura.tilt) + Aura.tube
            e = e.union(Extent(up: Aura.centreY + semiMinor + Aura.nodeRadius,
                               down: -Aura.centreY + semiMinor + Aura.nodeRadius,
                               side: Aura.majorRadius + Aura.nodeRadius))
        }

        // The trail wisp streams down and behind; it never reaches above the body. Its sideways
        // swim is a fraction of the swatch's `size`, so in bodyR it grows as the skin shrinks.
        e = e.union(Extent(up: 0, down: TrailWisp.down,
                           side: TrailWisp.side + TrailWisp.swim / skin.scale))

        // The whole figure rides the idle bob. `bobAmp` is a fraction of the swatch's `size`, and
        // `size = 2 * bodyR / scale`, so in bodyR it is `2 * bobAmp / scale`.
        let bob = Float(skin.idle.bobAmp) * 2 / skin.scale
        return Extent(up: e.up + bob, down: e.down + bob, side: e.side)
    }

    /// The trail wisp — five puffs streaming from the body's lower flank down and behind
    /// (`AnimatedCharacterSwatch.drawTrailWisp`). Preview-only: the in-run equivalent is the
    /// renderer's wake, which is a different system with its own extent.
    ///
    /// Both reaches are the maximum of `|position| + radius` over the puff's whole travel, not the
    /// endpoint — the puff shrinks as it falls, so the two do not peak together.
    enum TrailWisp {
        /// head 0.72 → tail 1.18 bodyR below centre, radius 0.13 → 0.045.
        static let down: Float = 1.225
        /// head 0.52 → tail 1.16 bodyR behind centre.
        static let side: Float = 1.205
        /// The sideways swim, as a fraction of `size` — divide by `skin.scale` for bodyR.
        static let swim: Float = 0.036
    }

    /// The worst extent across the whole shipped roster, in units of the swatch's `size` rather
    /// than of `bodyR` — because `bodyR = size * 0.5 * scale`, a character with `scale > 1` needs
    /// more room per unit of `size` than its bodyR figure suggests, and `tide`/`nebula` clipped
    /// their own plain sphere for exactly that reason.
    ///
    /// Call sites size their canvas from this so that **every** character fits in **every** slot,
    /// which keeps relative sizes honest: fitting each skin to its own extent would render the
    /// legendaries smallest of all, and a rarity ladder whose top rung is the tiniest figure on
    /// the shelf is worse than the bug it fixes.
    static var rosterExtentInSizeUnits: Extent {
        SkinCatalog.all.reduce(Extent.zero) { acc, skin in
            let e = extent(for: skin)
            let k = 0.5 * skin.scale          // bodyR per unit of `size`
            return acc.union(Extent(up: e.up * k, down: e.down * k, side: e.side * k))
        }
    }
}
