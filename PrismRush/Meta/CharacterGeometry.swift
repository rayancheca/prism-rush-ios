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

    // MARK: - Anchors

    /// Where a crest roots, in bodyR above the body centre.
    ///
    /// Rig: `crestY` 1.18 with the body at 0.66 → (1.18 − 0.66) / 0.62. The crystal's rig value
    /// (1.30 against a body centre of 0.72) works out to 0.9355, and the swatch drew 1.02 — a
    /// 9 % gap nobody could see because both were cropped.
    static func crestAnchor(_ shape: Skin.BodyShape) -> Float {
        shape == .crystal ? (1.30 - 0.72) / sphereRadius : (1.18 - 0.66) / sphereRadius
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
        /// rig `spike(halfBase: 0.11, height: 0.36)` — the swatch drew 0.92 bodyR, **1.58× the rig**.
        static let height: Float = 0.36 / sphereRadius               // 0.58065
        static let halfBase: Float = 0.11 / sphereRadius             // 0.17742
        static let offsetX: Float = 0.26 / sphereRadius              // 0.41935
        /// Outward lean, radians. Applied as `∓lean` about z, mirrored per side.
        static let lean: Float = 0.18
        /// The darker inner ear exists only in the swatch today. It is what makes an ear read as
        /// an ear rather than a triangle, so the rig gains it rather than the swatch losing it —
        /// as a fraction of the outer ear.
        static let innerScale: Float = 0.55
    }

    /// Drooping dog/bunny ears at the sides (`RealityRenderer:1304-1310`).
    enum Floppy {
        /// **DEFECT D4, corrected here.** The rig hard-codes world y 0.92 (`:1307`) instead of
        /// hanging off `crestY` like every other crest, so a crystal body wears its ears in the
        /// wrong place. Recorded as a drop BELOW the crest anchor, which is shape-aware for free.
        static let dropBelowAnchor: Float = (1.18 - 0.92) / sphereRadius   // 0.41935
        static let radiusX: Float = 0.17 * 0.7 / sphereRadius        // 0.19194
        static let radiusY: Float = 0.17 * 1.3 / sphereRadius        // 0.35645
        static let offsetX: Float = 0.52 / sphereRadius              // 0.83871
    }

    /// Sawtooth dorsal mohawk across the crown (`RealityRenderer:1311-1314`).
    enum Fin {
        /// Rig spike heights, left → right. The swatch drew [0.60, 1.05, 0.72] — 1.55× throughout.
        static let heights: [Float] = [0.24 / sphereRadius, 0.42 / sphereRadius, 0.28 / sphereRadius]
        static let halfBase: Float = 0.11 / sphereRadius             // 0.17742
        static let spacing: Float = 0.20 / sphereRadius              // 0.32258
    }

    /// Two horns sweeping up and out (`RealityRenderer:1315-1319`).
    ///
    /// **The worst divergence in the file.** The rig leans a 0.42-long spike by 0.5 rad from a
    /// base at x ±0.22, putting its apex at 0.680 bodyR. The swatch drew the apex at
    /// **1.370 bodyR — 2.02× as wide**, which at a 56 pt grid card is 19.3 pt of horn that the
    /// in-run character does not have, and most of why five skins clipped their own card.
    enum Horns {
        static let length: Float = 0.42 / sphereRadius               // 0.67742
        static let halfBase: Float = 0.10 / sphereRadius             // 0.16129
        static let offsetX: Float = 0.22 / sphereRadius              // 0.35484
        /// Outward lean, radians.
        static let lean: Float = 0.5
    }

    /// A ring of points around the crown (`RealityRenderer:1320-1326`).
    enum Crown {
        static let ringRadius: Float = 0.30 / sphereRadius           // 0.48387
        static let ringTube: Float = 0.045 / sphereRadius            // 0.07258
        static let spikeHalfBase: Float = 0.06 / sphereRadius        // 0.09677
        /// Rig spike height. The swatch's centre spike was 0.62 bodyR — **2.14×** — and its
        /// outer spikes 0.42 — 1.45×. Two different inflation factors on one crest.
        static let spikeHeight: Float = 0.18 / sphereRadius          // 0.29032
        static let spikeLift: Float = 0.02 / sphereRadius            // 0.03226
        static let spikeCount = 5
    }

    /// A ring floating above the head (`RealityRenderer:1327-1328`).
    enum Halo {
        /// Height above the crest anchor. The swatch floated it at 0.58 bodyR — 35 % low.
        static let float: Float = 0.55 / sphereRadius                // 0.88710
        static let radius: Float = 0.34 / sphereRadius               // 0.54839
        static let tube: Float = 0.05 / sphereRadius                 // 0.08065
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

        // The trail wisp streams down and behind; it never reaches above the body.
        e = e.union(Extent(up: 0, down: trailWispReach, side: 0))

        // The whole figure rides the idle bob. `bobAmp` is a fraction of the swatch's `size`, and
        // `size = 2 * bodyR / scale`, so in bodyR it is `2 * bobAmp / scale`.
        let bob = Float(skin.idle.bobAmp) * 2 / skin.scale
        return Extent(up: e.up + bob, down: e.down + bob, side: e.side)
    }

    /// How far the trail wisp's last puff reaches below the figure's centre
    /// (`AnimatedCharacterSwatch.drawTrailWisp` — tail at 1.18 bodyR plus the puff radius).
    static let trailWispReach: Float = 1.18 + 0.13

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
