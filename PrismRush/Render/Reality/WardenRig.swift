import Foundation
import RealityKit
import UIKit

/// The Warden's render rig (v1.9): the craft ahead, its shield, its exposed core, and the beams.
///
/// Kept out of `RealityRenderer` because that file is already the largest in the project and this is
/// a self-contained set piece with its own lifetime — it exists only while `GameSnapshot.warden` is
/// non-nil. Built from `MeshDescriptor` helpers and RealityKit primitives with `UnlitMaterial`
/// only, so it adds no binary assets (iron rule 6).
///
/// **Every colour here is world-blind, and that is the lesson the chasm paid for.** A hazard has to
/// mean the same thing in all twelve world families, and the palette accents swing all the way to
/// pure white in two of them — so a beam tinted with `accent2` would become invisible exactly where
/// it most needed to read. The craft is a desaturated steel-violet (the chasm's trick: lighter than
/// the deck, so geometry carries it) and everything lethal is one fixed hostile red.
@MainActor
final class WardenRig {
    /// Steel-violet hull — reads against every world because it is lighter than the black deck.
    private static let hullHue: UInt32 = 0xDCE8FF
    /// The one-value-darker keel. Under an unlit renderer a step in VALUE is the only thing that
    /// gives a body form, so this is not decoration — it is the difference between a solid and a
    /// silhouette (the owner's "just a basic triangle").
    private static let plateHue: UInt32 = 0x4C5F92
    /// **Violet, not the near-white the design table specified.** Verified on the simulator: white
    /// spars on a pale hull under a dome that is taller than they are simply vanish — the health
    /// readout was invisible in its first build. Violet is far in hue from BOTH reserved meanings
    /// (hazard red `0xFF3355`, shield cyan `0x66E0FF`), so it can carry a third channel without
    /// ever being mistaken for "this will kill you" or "this is protected".
    private static let sparHue: UInt32 = 0xC77BFF
    private static let shieldHue: UInt32 = 0x66E0FF   // cool: intact, not yet dangerous
    private static let hazardHue: UInt32 = 0xFF3355   // hostile: the core, and anything lethal
    private static let hazardDimHue: UInt32 = 0xD92742

    /// Where the strike is drawn, in track units ahead of the player. The beam resolves against the
    /// player's own plane, so it is drawn just in front of them — far enough to see coming, close
    /// enough that "that column is over my lane" is a single glance.
    private static let strikeZ: Double = -9
    /// The gun beam's mesh is built one unit long and scaled on Z to reach the hull, so the craft
    /// closing in does not require rebuilding geometry every frame.
    private static let gunBeamUnitLength: Float = 1

    /// How far the full-width shapes reach across the deck. Wider than the three lanes so the slab
    /// and the wall visibly run off both edges of the track — that is what says "there is no lane to
    /// move to" without the player having to check three lanes and infer it.
    private static let fullWidth: Float = 12

    /// **Height magnitude is not the read.** The scouts measured ~96 px per world unit of height
    /// against a 214 px lane step at the strike plane, so at 33 m/s a player cannot judge "is that
    /// red band at 0.85 or at 0.95". The discriminator has to be a binary, and the codebase already
    /// knows which one works: the chasm reads because it INTERRUPTS the neon grid.
    ///
    /// So the two full-width shapes are told apart by whether the grid survives under them:
    ///   FLOOR   — sits ON the deck. The grid is gone edge to edge. Nothing to run under → jump.
    ///   CURTAIN — hangs from the sky and stops at 0.95, leaving a clean strip of lit grid running
    ///             beneath it. Something to run under → slide.
    /// Reinforced by opposite motion (the slab grows up, the wall comes down) and by opposite pitch
    /// direction in the audio cue. Colour is NOT a channel — everything lethal stays one fixed
    /// world-blind red, because `accent2` goes pure white in two palettes.
    private static let curtainHem: Float = 0.95

    // MARK: - Presence (v2.0)

    /// **How big the craft is, and why it is not a taste call.**
    ///
    /// Measured off the shipped captures: the craft painted **0.46% of the frame**, and an ordinary
    /// wall — a thing the player has dodged since metre one — painted 4× that. The floor for a boss
    /// is therefore "bigger than an ordinary wall" ≈ 1.84%. At ×1.70 it paints ≈2.2%; at ×1.45 it
    /// paints 1.45% and fails the bar. 1.70 is the smallest scale that clears it.
    ///
    /// Applied to the individual PARTS, never to the `craft` entity: the halo and the core have
    /// their own radius budgets (see `haloScale` and the core, which is a lethal-red readability
    /// surface and must not balloon with the hull).
    private static let craftScale: Float = 1.70

    /// **The hull is authored ASYMMETRICALLY about its origin, and that exists to protect the
    /// telegraph rather than the boss.**
    ///
    /// The lance column and the curtain hang from `w.y`. A symmetric hull at ×1.70 would put `w.y`
    /// at mid-hull, so every shot would emerge from the middle of the ship; pinning the shots to the
    /// hull's underside instead would drop the column top from 4.2 to 2.755 and cut its on-screen
    /// descent by 37% — a huge loss on the most time-critical cue in the game.
    ///
    /// So the mass sits ABOVE the origin and the emitter just below it. Cost, measured: the column's
    /// tip travels 517 px instead of 602 (−14%) and the curtain's band is 390 px instead of 475
    /// (−18%). Both stay unmistakable, and both now visibly hang off the ship.
    private static let emitterDrop: Float = 0.55

    /// Spars are the health readout, and the count is deliberately not the primary channel: 6→5 and
    /// 5→4 are counting tasks, not subitizing tasks (the reliable limit is ~4), and the player's eye
    /// is on the deck. They shed **outermost-first, alternating right then left**, so what actually
    /// reads is the SPAN narrowing toward the centre, with the last one standing over the core.
    ///
    /// Pure function of `coreHits`; no RNG, so nothing here can perturb a seeded run.
    /// For n = 5 the order is 4, 0, 3, 1, 2. Pinned by `WardenRigTests`.
    static func shedIndex(hit: Int, of n: Int) -> Int {
        hit % 2 == 0 ? (n - 1) - hit / 2 : (hit - 1) / 2
    }

    private static let sparCount = 6

    /// The whole rig. `craft` moves with the Warden; `beams` stays in world space, because the deck
    /// plates belong on the deck in front of the PLAYER — parenting them to a craft hovering five
    /// units up and twenty-six ahead would float the one element that has to read as floor.
    private let group = Entity()
    private let craft = Entity()
    private let beams = Entity()
    private let hull: ModelEntity        // the disc, circular in PLAN so yaw is free
    private let dome: ModelEntity        // three value steps — the only way a hull reads as a solid
    private let rim: ModelEntity         // the bright outline that survives at 2% of frame
    private var spars: [ModelEntity] = []    // the health readout (§shedIndex)
    private var debris: [ModelEntity] = []   // world-space, launched as a spar sheds
    private var debrisT: [Double] = []       // per-debris life, ≤ 0 = parked
    private var debrisV: [SIMD3<Float>] = []
    private let halo: ModelEntity        // the shield, scaled by what is left of it
    private let core: ModelEntity        // only visible once the shield is down

    // Rig clock + edge detection (v2.0). `sync` used to receive no `dt` and hold no state, so
    // nothing time-based or edge-triggered was expressible at all — which is most of why the owner's
    // verdict was "no animations, same every time".
    private var idleT: Double = 0
    private var lastCoreHits = 0
    private var lastPhase: WardenPhase?
    private var panels: [ModelEntity] = []   // one per lane, flat on the deck (LANCE only)
    private var columns: [ModelEntity] = []  // one per lane, descending as the beam winds up
    private let gunBeam: ModelEntity         // the phase-1 auto-fire, drawn for the first time (S-009)
    private let floorSlab: ModelEntity       // full width, grows UP out of the deck — jump it
    private let curtainWall: ModelEntity     // full width, descends from the sky and STOPS — slide it

    private let matHazard: UnlitMaterial
    private let matHazardDim: UnlitMaterial
    private let matShield: UnlitMaterial

    init() {
        matHazard = UnlitMaterial(color: Self.rgb(Self.hazardHue))
        matHazardDim = UnlitMaterial(color: Self.rgb(Self.hazardDimHue))
        matShield = UnlitMaterial(color: Self.rgb(Self.shieldHue))

        let s = Self.craftScale
        let plate = UnlitMaterial(color: Self.rgb(Self.plateHue))

        // **Circular in plan, not an octahedron.** The shipped `octahedron(rx: 2.7, rz: 1.9)` has a
        // rhombic plan silhouette whose projected half-width swings 43% per half revolution, so a
        // circular rim would detach from it by up to 1.30 u ≈ 142 px at the sides — and it would
        // kill the yaw-invariance that lets the craft turn for free.
        hull = ModelEntity(mesh: ProceduralMesh.bandedSphere(radius: 1, bands: 1, segments: 24, rings: 4),
                           materials: [plate])
        hull.scale = SIMD3<Float>(2.45, 0.42, 2.45) * s

        // **Three flat material slots is the only way a hull reads as more than an outline here.**
        // `UnlitMaterial` has no normals, so a single-colour body has no form at all — it is a
        // silhouette. Banding the dome is what turns the craft into a solid object.
        dome = ModelEntity(mesh: ProceduralMesh.bandedSphere(radius: 1, bands: 3, segments: 24, rings: 3),
                           materials: [UnlitMaterial(color: Self.rgb(Self.hullHue)),
                                       UnlitMaterial(color: Self.rgb(0xBCC6E4)),
                                       plate])
        dome.scale = SIMD3<Float>(1.18, 0.55, 1.18) * s
        dome.position = SIMD3<Float>(0, 0.60 * s, 0)

        // The bright outline is what actually survives at 2% of frame.
        rim = ModelEntity(mesh: ProceduralMesh.torus(major: 2.86, minor: 0.24, majorSeg: 24, minorSeg: 7),
                          materials: [UnlitMaterial(color: Self.rgb(0xE6ECFA))])
        rim.orientation = simd_quatf(angle: .pi / 2, axis: SIMD3<Float>(1, 0, 0))
        rim.scale = SIMD3<Float>(repeating: s)

        // The shield reads as a ring around the hull rather than a bubble over it: a sphere would
        // need transparency to avoid hiding the craft, and this renderer is unlit and opaque.
        //
        // **Re-radiused for the bigger hull, and the design spec's own numbers were wrong here.**
        // It priced the rim's outer edge at `major × scale` = 4.862 and omitted the torus MINOR
        // radius; the true outer edge is `(2.86 + 0.24) × 1.70` = 5.270. Its halo scale would have
        // cleared the rim by 0.03 u ≈ 2 px — the cyan ring welded to the hull for the whole 7 s
        // window, which is precisely the failure it was written to prevent. These values satisfy
        // its two stated constraints against the corrected figure: clearance ≥ 0.40 u (0.53 here)
        // and a shrink swing ≥ 1.2 u (1.20 here).
        halo = ModelEntity(mesh: ProceduralMesh.torus(major: 5.3, minor: 0.30, majorSeg: 28, minorSeg: 7),
                           materials: [matShield])
        halo.orientation = simd_quatf(angle: .pi / 2, axis: SIMD3<Float>(1, 0, 0))

        // Unscaled by `craftScale` on purpose: it is a lethal-red readability surface, and the one
        // thing on this craft whose size must not follow a presentation decision.
        core = ModelEntity(mesh: ProceduralMesh.octahedron(0.75), materials: [matHazard])
        // **Slung clearly BELOW the belly, and that is not cosmetic.** The camera sits at y 5.1 and
        // looks DOWN on a craft hovering at 4.2, so anything level with the hull's underside is
        // occluded by an opaque disc 8.3 units across. A first pass placed it at the hull's bottom
        // edge and the core was invisible for the entire exposed phase — while the HUD said
        // "CORE EXPOSED". Verified on the simulator. At −1.05 it protrudes 1.09 units clear of the
        // hull, and its lowest pixel still lands ~30 px above the hard floor the strike read needs.
        core.position = SIMD3<Float>(0, -1.05, 1.20)
        core.isEnabled = false

        // The two full-width shapes. Both are deep (13) so they read as a band the player is running
        // INTO rather than a line they are crossing, and both are scaled in `sync` rather than
        // rebuilt — a unit box scaled on one axis costs nothing per frame.
        // Tapered so it reads as leaving the player and arriving at the craft rather than as a
        // rod. Uses the beam helper that already ships in seven decor files and had never once been
        // pointed at the Warden.
        gunBeam = ModelEntity(mesh: ProceduralMesh.beamAlongTrack(halfWidthNear: 0.16,
                                                                  halfWidthFar: 0.05),
                              materials: [matShield])
        gunBeam.isEnabled = false

        floorSlab = ModelEntity(mesh: .generateBox(width: Self.fullWidth, height: 1, depth: 13),
                                materials: [matHazardDim])
        floorSlab.isEnabled = false
        curtainWall = ModelEntity(mesh: .generateBox(width: Self.fullWidth, height: 1, depth: 13),
                                  materials: [matHazardDim])
        curtainWall.isEnabled = false

        craft.addChild(hull)
        craft.addChild(dome)
        craft.addChild(rim)
        craft.addChild(halo)
        craft.addChild(core)

        // The spars: a standing crown on the hull's shoulder. Solid octahedra rather than cards, so
        // they are visible at every yaw. `isEnabled` alone is the whole health readout.
        let sparMesh = ProceduralMesh.octahedron(rx: 0.16, ry: 1, rz: 0.16)
        let sparMat = UnlitMaterial(color: Self.rgb(Self.sparHue))
        for i in 0..<Self.sparCount {
            let a = 2 * Float.pi * Float(i) / Float(Self.sparCount)
            let spar = ModelEntity(mesh: sparMesh, materials: [sparMat])
            // On the hull's outer shoulder (r 3.95 world) rather than beside the dome. Inboard they
            // sat at r 2.98 against a dome of radius 2.01 that stood taller than they did, so they
            // were inside its silhouette and read as lumps. Out here they break the outline, which
            // is the only thing that survives at 2% of frame.
            spar.scale = SIMD3<Float>(1, 0.45, 1) * s
            spar.position = SIMD3<Float>(cos(a) * 3.95, 0.35, sin(a) * 3.95)
            spar.isEnabled = false
            craft.addChild(spar)
            spars.append(spar)

            // Debris lives in WORLD space (`beams`), never re-parented. The spec's design called for
            // `setParent(preservingWorldTransform:)` on the live spar; computing the launch point
            // directly is the same beat without the trap that RealityKit preserves the LOCAL
            // transform by default — which would teleport the part to the origin on the exact frame
            // the beat exists to sell.
            let d = ModelEntity(mesh: sparMesh, materials: [sparMat])
            d.scale = SIMD3<Float>(1, 0.45, 1) * s
            d.isEnabled = false
            beams.addChild(d)
            debris.append(d)
            debrisT.append(0)
            debrisV.append(.zero)
        }
        group.addChild(craft)
        group.addChild(beams)
        beams.addChild(gunBeam)
        beams.addChild(floorSlab)
        beams.addChild(curtainWall)

        for lane in 0..<3 {
            let x = Float(Tuning.laneX[lane])
            // The deck plate: this is the read. S-006 proved the neon grid is the canvas that makes
            // a hazard legible, so the beam announces itself ON the floor, where the player is
            // already looking, rather than only in the sky where the craft is. It runs from just
            // behind the player far up the track, so the lane it claims is unmistakable.
            let panel = ModelEntity(mesh: .generateBox(width: 2.0, height: 0.03, depth: 13),
                                    materials: [matHazardDim])
            panel.position = SIMD3<Float>(x, 0.04, Float(Self.strikeZ))
            panel.isEnabled = false
            beams.addChild(panel)
            panels.append(panel)

            // A vertical column that descends onto the lane and touches the deck exactly as the
            // beam fires — so "when" is as legible as "where", with no countdown and no number.
            // Placed near the player's own plane rather than at the craft: the strike happens
            // where the player is standing, so that is where it has to be drawn.
            let column = ModelEntity(mesh: .generateBox(width: 1.0, height: 1, depth: 1.0),
                                     materials: [matHazardDim])
            column.position = SIMD3<Float>(x, 0, Float(Self.strikeZ))
            column.isEnabled = false
            beams.addChild(column)
            columns.append(column)
        }
        group.isEnabled = false
    }

    func install(into root: Entity) { root.addChild(group) }

    /// Return every part to its as-built state.
    ///
    /// **This is not defensive tidying — without it the second Warden of a run arrives dismembered.**
    /// The rig is constructed once at renderer init and reused for every encounter, so a run that
    /// reaches world 9 fights three Wardens with the same entities and the same shed spars.
    private func resetRig() {
        for s in spars { s.isEnabled = false }
        for i in debris.indices { debris[i].isEnabled = false; debrisT[i] = 0 }
        craft.orientation = .init()
        core.isEnabled = false
        halo.isEnabled = true
        hull.isEnabled = true; dome.isEnabled = true; rim.isEnabled = true
        idleT = 0
        lastCoreHits = 0
    }

    /// Push one frame. `nil` means there is no encounter and the whole rig switches off.
    func sync(_ w: WardenState?, dt: Double, reduceMotion: Bool) {
        guard let w else {
            if group.isEnabled { group.isEnabled = false; lastPhase = nil; resetRig() }
            return
        }
        if !group.isEnabled { group.isEnabled = true }
        if lastPhase != w.phase {
            if w.phase == .arriving { resetRig() }
            lastPhase = w.phase
        }
        idleT += dt
        stepDebris(dt)

        // `z` is negative-ahead in the core's convention, matching `EntityState`. Only the craft
        // moves; `beams` stays anchored in world space around the player.
        //
        // All three axes are live now (S-009). `z` was a hard constant for the whole of v1.9 despite
        // a comment claiming otherwise, so the craft never approached, never recoiled and never
        // retreated — it appeared, hung, and vanished. `x` leans it toward the player's lane.
        craft.position = SIMD3<Float>(Float(w.x), Float(w.y), Float(w.z))

        // The phase-1 gun, drawn for the first time. The design has always said the character
        // auto-fires to break the shield, and the HUD has always shown a charge bar — but there was
        // no emitter anywhere in the renderer (a grep for muzzle/tracer/bullet/projectile returned
        // two comments and zero code). The player was watching a meter drain and being told it was
        // a gun. A tapered beam from the player's plane to the hull makes the gem → power link
        // visible without changing a single rule.
        let firingGun = w.phase == .shielded
        gunBeam.isEnabled = firingGun
        if firingGun {
            // Reaches from just in front of the player to the hull, so both ends are anchored to
            // something real. `beamAlongTrack` is built ONE UNIT long down −Z, so scaling Z is the
            // length. (The older `ProceduralMesh.beam` fans along +Y with every vertex at z 0 — S-009
            // used it here and scaled Z, which does nothing to a zero-thickness quad, and shipped a
            // sliver standing in front of the player for the entire shield phase.)
            //
            // **It must be AIMED, not laid flat (v2.0).** The fixed height was the second half of
            // the same bug: the shaft ran horizontally at y 1.05 while the craft hovers at 4.2, so
            // it reached the right depth and passed 3.1 units UNDER the hull — a gun visibly
            // shooting beneath the thing it was supposedly breaking. `look(at:)` points the mesh's
            // own −Z at the craft's emitter, and the length becomes the true 3-D distance.
            let muzzle = SIMD3<Float>(Float(w.x) * 0.35, 0.9, -2.2)
            let target = SIMD3<Float>(Float(w.x), Float(w.y) - Self.emitterDrop, Float(w.z))
            gunBeam.position = muzzle
            gunBeam.look(at: target, from: muzzle, relativeTo: beams)
            let reach = simd_length(target - muzzle)
            // Thicker with charge: the bar the player has been filling all run is now a thing they
            // can see hitting something.
            //
            // **Always the shield hue, never hazard red.** Red means "this can kill you" everywhere
            // else in this rig, and the player's own gun is never lethal to the player — a red shaft
            // during the one phase that has no telegraph is the single most confusable thing this
            // pass could add.
            let power = 0.45 + 0.55 * Float(w.charge)
            gunBeam.scale = SIMD3<Float>(power, power, max(0.01, reach))
        }

        // Idle yaw. A constant, sub-1.5 Hz turn sells "hovering, watching", and it **stops dead the
        // instant a telegraph begins** — stillness in the sky is a stronger peripheral cue than any
        // motion, and it costs zero eye position 900 px from the deck the player is reading.
        //
        // This replaces a 34° INSTANTANEOUS SNAP that fired the moment a hit landed
        // (`angle: coreHits * 0.6 + t * 0.35`). That was a discontinuity, not a beat, and it was
        // the only "animation" the craft had. Reduce Motion holds the craft still, as before.
        if !reduceMotion && w.telegraphProgress <= 0 {
            craft.orientation = simd_quatf(angle: Float(idleT) * 0.21, axis: SIMD3<Float>(0, 1, 0))
        }

        // THE SHED: damage is subtractive geometry (v2.0).
        //
        // It earns its keep three ways. It is the only health readout whose channels — how many,
        // and how wide the span — are static geometry, so it survives Reduce Motion intact where
        // every motion channel has to be gated. Its debris IS the detonation geometry, so the
        // explosion costs no new mesh. And it is what lets the HUD's hit-pip row live away from the
        // craft: the fight's state is on the boss now, not only in a label drawn across it.
        let needed = max(1, w.coreHitsNeeded)
        if w.coreHits > lastCoreHits {
            for h in lastCoreHits..<min(w.coreHits, needed) {
                launchDebris(Self.shedIndex(hit: h, of: needed), craftY: Float(w.y), craftZ: Float(w.z))
            }
        }
        lastCoreHits = w.coreHits
        for i in 0..<Self.sparCount {
            spars[i].isEnabled = i < needed && !isShed(i, hits: w.coreHits, of: needed)
        }

        // Shield: the halo shrinks onto the hull as it fails, then goes out entirely. Scale rather
        // than fade, because an opaque unlit material has no honest way to fade.
        let sf = Float(w.shieldFraction)
        if sf > 0 {
            halo.isEnabled = true
            halo.scale = SIMD3<Float>(repeating: 1.16 + 0.24 * sf)
            // Spins faster the closer it is to failing — 42°/s at full, 202°/s at the breaking
            // point. One line, no new screen area, and no telegraph to compete with (a telegraph is
            // structurally impossible in `.shielded`). It turns "watch a bar drain" into "watch it
            // lose its grip", which is the whole of the owner's complaint about phase one.
            if !reduceMotion {
                let spin = Float(idleT) * (0.73 + 2.79 * (1 - sf))
                halo.orientation = simd_quatf(angle: .pi / 2, axis: SIMD3<Float>(1, 0, 0))
                    * simd_quatf(angle: spin, axis: SIMD3<Float>(0, 0, 1))
            }
            core.isEnabled = false
        } else {
            halo.isEnabled = false
            core.isEnabled = w.phase != .leaving
            // **The core no longer shrinks.** One object, one health channel: the spars are the
            // count, the station creep is the pressure, and a shrinking core was a third redundant
            // readout of the same value — one that made the boss LESS visible the closer it was to
            // dying, which is backwards.
        }

        // The strike. Exactly ONE shape is ever drawn, and the other two are switched off — a lance
        // and a curtain on screen together would put two contradictory verbs in the same frame,
        // which is the decree-6 failure the whole shape system exists to avoid.
        let t = Float(w.telegraphProgress)
        let hot = w.striking
        let live = w.telegraphProgress > 0 || hot
        let mat = hot ? matHazard : matHazardDim

        // The per-lane plates are the LANCE's read and only the lance's. They occlude the grid
        // unconditionally, so leaving them on under a curtain would erase the strip of lit grid that
        // is the *entire* discriminator between "run under it" and "jump it".
        let lanceLive = live && w.band == .lance
        for lane in 0..<3 {
            let panel = panels[lane], column = columns[lane]
            guard lanceLive, w.closes(lane) else {
                if panel.isEnabled { panel.isEnabled = false; column.isEnabled = false }
                continue
            }
            panel.isEnabled = true
            column.isEnabled = true
            panel.model?.materials = [mat]
            column.model?.materials = [mat]
            // Widen the plate as the shot charges, so peripheral vision catches it even when the
            // player is watching the deck rather than the sky.
            panel.scale = SIMD3<Float>(hot ? 1.0 : (0.45 + 0.55 * t), 1, 1)

            // The column descends from the craft's altitude to the deck. Its unit box is 1 high, so
            // scaling y by the remaining reach and sitting it at half that keeps its TOP pinned up
            // in the sky while its bottom edge falls — the shot visibly coming down, not growing up.
            //
            // **The top is the CRAFT's height, not a constant (S-009).** It used to be a hardcoded
            // 7.5 against a craft hovering at 5.2, so a lance's top edge was cut flat 256 px ABOVE
            // the thing supposedly firing it: the attacks did not come from the attacker. Reading
            // the craft's live y ties the shot to its source for one line, and keeps doing so now
            // that the craft's height and depth both animate.
            let drop = max(1, Float(w.y) - Self.emitterDrop)
            let reach = hot ? drop : drop * min(1, t)
            column.scale = SIMD3<Float>(hot ? 1 : 0.55, max(0.01, reach), hot ? 1 : 0.55)
            column.position = SIMD3<Float>(Float(Tuning.laneX[lane]),
                                           drop - reach / 2, Float(Self.strikeZ))
        }

        // FLOOR — grows UP out of the deck to its lethal height, blotting out the grid edge to edge.
        // Its bottom stays pinned at 0 so the growth reads as the deck itself rising.
        let floorLive = live && w.band == .floor
        floorSlab.isEnabled = floorLive
        if floorLive {
            let full = Float(Tuning.wardenFloorKillTop)
            let h = max(0.02, hot ? full : full * min(1, t))
            floorSlab.model?.materials = [mat]
            floorSlab.scale = SIMD3<Float>(1, h, 1)
            floorSlab.position = SIMD3<Float>(0, h / 2, Float(Self.strikeZ))
        }

        // CURTAIN — descends from the sky and STOPS at the hem, leaving lit grid running underneath.
        // Its top stays pinned in the sky while the hem falls, the exact inverse of the floor, so
        // the two shapes are opposite motion as well as opposite occlusion.
        let curtainLive = live && w.band == .curtain
        curtainWall.isEnabled = curtainLive
        if curtainLive {
            // Same rule as the lance: the wall hangs from the craft, not from a constant.
            let top = max(Self.curtainHem + 0.5, Float(w.y) - Self.emitterDrop)
            let hem = hot ? Self.curtainHem : top - (top - Self.curtainHem) * min(1, t)
            let h = max(0.02, top - hem)
            curtainWall.model?.materials = [mat]
            curtainWall.scale = SIMD3<Float>(1, h, 1)
            curtainWall.position = SIMD3<Float>(0, hem + h / 2, Float(Self.strikeZ))
        }
    }

    private func isShed(_ i: Int, hits: Int, of n: Int) -> Bool {
        for h in 0..<min(hits, n) where Self.shedIndex(hit: h, of: n) == i { return true }
        return false
    }

    /// Fling the shed spar off the hull.
    ///
    /// **Life is capped below the recover gap on purpose.** `wardenAttackRecover` is 0.35–0.40 s at
    /// every rank, so debris is always gone before the next telegraph begins — nothing this beat
    /// throws can still be moving inside a window the player must read (decree 6).
    ///
    /// **Z velocity is negative: away from the player.** Nothing the player must NOT chase is ever
    /// allowed to move toward them.
    private func launchDebris(_ i: Int, craftY: Float, craftZ: Float) {
        guard i >= 0, i < debris.count else { return }
        let local = spars[i].position
        let d = debris[i]
        d.position = SIMD3<Float>(local.x, craftY + local.y, craftZ + local.z)
        d.orientation = .init()
        d.isEnabled = true
        debrisT[i] = min(0.34, Double(Tuning.wardenRecoverByRank.min() ?? 0.35) - 0.02)
        let outward = SIMD3<Float>(local.x, 0, local.z)
        let n = max(0.001, (outward.x * outward.x + outward.z * outward.z).squareRoot())
        debrisV[i] = SIMD3<Float>(outward.x / n * 2.0, 1.2, outward.z / n * 2.0 - 0.8)
    }

    private func stepDebris(_ dt: Double) {
        for i in debris.indices where debrisT[i] > 0 {
            debrisT[i] -= dt
            if debrisT[i] <= 0 { debris[i].isEnabled = false; continue }
            debris[i].position += debrisV[i] * Float(dt)
            debris[i].orientation *= simd_quatf(angle: Float(dt) * 11.2, axis: SIMD3<Float>(0.4, 1, 0.2))
        }
    }

    private static func rgb(_ hex: UInt32) -> UIColor {
        UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}
