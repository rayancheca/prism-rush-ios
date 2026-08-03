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
    /// readout was invisible in its first build.
    ///
    /// **v2.3 makes this the Warden's whole signature rather than a third channel.** It used to be
    /// justified as "far in hue from hazard red and shield cyan", and that reasoning died with the
    /// red: the fight now speaks ONE hostile colour, and everything the Warden owns — its spars, its
    /// thrown walls, its holes, its portcullises — is violet. The spars can never be confused with a
    /// thrown hazard despite sharing a hue, because they are 7.4 units up in the sky on a craft and
    /// a hazard is on the deck; nothing puts them side by side.
    private static let sparHue: UInt32 = 0xC77BFF

    // MARK: the wind-up (v2.4, D-038)
    //
    // `windUpFrom` is the fraction of the gap that stays neutral before the tell begins. 0.62 puts
    // the anticipation in the last ~0.38 of every interval — 0.59 s at rank 1 down to 0.42 s at
    // rank 3 — which is long enough to read as a gesture and short enough that the craft still
    // spends most of the gap simply hovering. Making it much earlier would leave the boss
    // permanently mid-lunge, which reads as a pose rather than as a warning.
    private static let windUpFrom: Double = 0.62
    /// Radians of nose-down pitch at full wind-up (~14°). Deliberately small: the tell has to be
    /// peripheral, because the player's eyes belong on the deck (decree 6).
    private static let windUpPitch: Float = 0.25
    /// Hull swell at full wind-up. 4% — visible as a change, invisible as a size.
    private static let windUpSwell: Float = 0.04
    /// Peak bank of the damage flinch, in radians (≈ 21°). Big enough to read at 900 px, small
    /// enough that a saucer banking does not look like it is leaving.
    private static let hitRoll: Float = 0.37
    private static let shieldHue: UInt32 = 0x66E0FF   // cool: intact, not yet dangerous
    /// The hostile violet, matching `RealityRenderer.cWardenHazard` — see there for why the red
    /// (`0xFF3355`) went. Used for the exposed core and anything that means "this is the fight".
    private static let hazardHue: UInt32 = 0xC77BFF
    private static let hazardDimHue: UInt32 = 0x7B3BC4
    /// The core is the one thing on the craft the player is trying to HIT, so it is deliberately
    /// the brightest element in the rig — hotter than the spars that share its hue, so "shoot here"
    /// never has to compete with "this is how much health it has left".
    private static let coreHue: UInt32 = 0xF2D0FF

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
    /// **2.55, up from 1.70 (S-012).** Nothing about the model changed — the craft simply moved
    /// out. v2.1 hung it at `wardenStandOff` 19; v2.2 hangs it at the THROW LEAD (34 m falling to
    /// 22 m as it takes damage), because a hazard that materialises further away than the craft
    /// supposedly throwing it is a lie the player can see, and decree 2 is that previews never lie.
    ///
    /// At 34 m the same model subtends 19/34 = 0.56× of its v2.1 size, which reads as the boss
    /// having quietly shrunk — and "no presence, just a basic triangle" was the owner's verdict that
    /// S-009 was fixing when it staged the craft in the first place. 1.70 × 1.5 restores ~85% of the
    /// old apparent size at full health and MORE than it as the craft closes in, so the fight now
    /// ends with the boss at its largest instead of starting there.
    private static let craftScale: Float = 2.55

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
    /// The craft's aim (yaw × wind-up pitch), held across a throw flash so the flinch can be
    /// composed on top of it without the frozen-during-throw behaviour being lost.
    private var aim = simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0))
    private let gunBeam: ModelEntity         // the phase-1 auto-fire, drawn for the first time (S-009)

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
        core = ModelEntity(mesh: ProceduralMesh.octahedron(0.75),
                           materials: [UnlitMaterial(color: Self.rgb(Self.coreHue))])
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
        //
        // **v2.4 adds the wind-up, which is what the stillness was missing.** Stopping dead is a
        // good cue and it stays, but on its own it made the craft's whole vocabulary "turning" and
        // "not turning" — across 42 frames sampled from a real encounter the craft was pixel-
        // identical in every one (`docs/agent/audits/scratch/s014_play_report.md`). D-038's *"a boss
        // in the sky doing nothing"* was literally true. Now the last third of every gap is an
        // anticipation beat: the craft rears back and tips its nose at the deck, and the harder it
        // is wound the more it leans. The dead air becomes the tell.
        let wind = Float(max(0, w.throwCharge - Self.windUpFrom) / (1 - Self.windUpFrom))
        if !reduceMotion {
            if w.throwFlash <= 0 {
                // Yaw eases to a HALT as the wind-up builds rather than being cut at the telegraph,
                // so the stop is something the player can see coming instead of a discontinuity.
                let yaw = simd_quatf(angle: Float(idleT) * 0.21 * (1 - wind),
                                     axis: SIMD3<Float>(0, 1, 0))
                // Nose-down pitch: it is aiming at the deck, and the axis is the one channel on this
                // rig that nothing else uses, so the tell can never be confused with damage (the
                // spars), the shield (the halo) or the throw itself (the recoil on z).
                let pitch = simd_quatf(angle: wind * Self.windUpPitch, axis: SIMD3<Float>(1, 0, 0))
                aim = yaw * pitch
            }
            // THE FLINCH (S-015). A hard bank on ROLL — the last free axis on this rig — decaying
            // with `hitFlash`. Damage previously moved nothing at all: the spars shed, which is a
            // state change rather than a reaction, and armour chips did not even do that. Roll is
            // chosen for the same reason pitch was chosen for the wind-up: no other channel uses it,
            // so "it got hurt" can never be misread as "it is about to throw".
            //
            // Composed on top of `aim` rather than replacing it, and `aim` is held (not recomputed)
            // through a throw flash, so a hit landing mid-throw still flinches without unfreezing
            // the yaw halt the telegraph depends on.
            let roll = simd_quatf(angle: Float(w.hitFlash) * Self.hitRoll, axis: SIMD3<Float>(0, 0, 1))
            craft.orientation = aim * roll
        }
        // The hull swells slightly as it loads. Scale is legible at 900 px away where a rotation of
        // a near-radially-symmetric saucer is not, and it is the same "something is charging" idiom
        // the shield halo already uses on its own axis.
        //
        // Written unconditionally (with the wind zeroed under Reduce Motion) rather than skipped, so
        // toggling the accommodation mid-fight cannot strand the hull at whatever size it had.
        let swell = 1 + (reduceMotion ? 0 : wind) * Self.windUpSwell
        if craft.scale.x != swell { craft.scale = SIMD3<Float>(repeating: swell) }

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

        // **THE THREE RED BANDS ARE GONE (v2.2).**
        //
        // Everything that used to be drawn here — the per-lane lance plates and columns, the floor
        // slab growing out of the deck, the curtain wall descending from the sky — was the single
        // biggest source of the owner's "the fight is a red thing that covers the screen". The
        // S-011 render audit put numbers on it: a full-width opaque red band on screen for 92–95%
        // of the exposed phase with a 100 ms dark gap between shapes, a curtain erasing 100% of the
        // track beyond 5.3 m, and a floor whose "wind-up" delivered 379 of its final 440 px in one
        // frame.
        //
        // The verb design was never the problem and it survives untouched: a Warden still asks for
        // lane, jump and slide in a scripted order with disjoint answers. What changed is that each
        // shape is now a REAL OBSTACLE thrown onto the deck (`GameCore.throwHazard`), drawn by the
        // same pooled meshes the spawner's obstacles use and read by rules the player has had 2,400
        // metres to learn. There is nothing left for the rig to paint on the strike plane, because
        // there is no strike plane.
        //
        // What the craft does instead is THROW: `WardenState.throwFlash` drives the muzzle recoil
        // (applied to `z` in `WardenEncounter.state`) and the renderer's `.wardenThrew` burst fires
        // at the hull. The attack and the attacker are visibly the same event for the first time.
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
        // Shed parts clear well before the next throw, so debris never accumulates into a cloud
        // around the craft. Sized off the shortest throw interval rather than a literal, so it
        // tracks the tuning table if that changes.
        debrisT[i] = min(0.34, (Tuning.wardenThrowIntervalByRank.min() ?? 1.65) * 0.2)
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
