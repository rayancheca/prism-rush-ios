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
    private static let hullHue: UInt32 = 0x9AA6C8
    private static let shieldHue: UInt32 = 0x66E0FF   // cool: intact, not yet dangerous
    private static let hazardHue: UInt32 = 0xFF3355   // hostile: the core, and anything lethal
    private static let hazardDimHue: UInt32 = 0xD92742

    /// Where the strike is drawn, in track units ahead of the player. The beam resolves against the
    /// player's own plane, so it is drawn just in front of them — far enough to see coming, close
    /// enough that "that column is over my lane" is a single glance.
    private static let strikeZ: Double = -9
    /// How high the descending column starts. Above the craft's hover height so the shot reads as
    /// coming out of the sky rather than sprouting from the deck.
    private static let columnTop: Double = 7.5

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

    /// The whole rig. `craft` moves with the Warden; `beams` stays in world space, because the deck
    /// plates belong on the deck in front of the PLAYER — parenting them to a craft hovering five
    /// units up and twenty-six ahead would float the one element that has to read as floor.
    private let group = Entity()
    private let craft = Entity()
    private let beams = Entity()
    private let hull: ModelEntity
    private let halo: ModelEntity        // the shield, scaled by what is left of it
    private let core: ModelEntity        // only visible once the shield is down
    private var panels: [ModelEntity] = []   // one per lane, flat on the deck (LANCE only)
    private var columns: [ModelEntity] = []  // one per lane, descending as the beam winds up
    private let floorSlab: ModelEntity       // full width, grows UP out of the deck — jump it
    private let curtainWall: ModelEntity     // full width, descends from the sky and STOPS — slide it

    private let matHazard: UnlitMaterial
    private let matHazardDim: UnlitMaterial
    private let matShield: UnlitMaterial

    init() {
        matHazard = UnlitMaterial(color: Self.rgb(Self.hazardHue))
        matHazardDim = UnlitMaterial(color: Self.rgb(Self.hazardDimHue))
        matShield = UnlitMaterial(color: Self.rgb(Self.shieldHue))

        // A flattened octahedron is a saucer in one primitive: wide, thin, pointed fore and aft.
        hull = ModelEntity(mesh: ProceduralMesh.octahedron(rx: 2.7, ry: 0.85, rz: 1.9),
                           materials: [UnlitMaterial(color: Self.rgb(Self.hullHue))])
        // The shield reads as a ring around the hull rather than a bubble over it: a sphere would
        // need transparency to avoid hiding the craft, and this renderer is unlit and opaque.
        halo = ModelEntity(mesh: ProceduralMesh.torus(major: 3.1, minor: 0.22),
                           materials: [matShield])
        halo.orientation = simd_quatf(angle: .pi / 2, axis: SIMD3<Float>(1, 0, 0))
        core = ModelEntity(mesh: ProceduralMesh.octahedron(0.75), materials: [matHazard])
        core.position = SIMD3<Float>(0, -0.95, 0)
        core.isEnabled = false

        // The two full-width shapes. Both are deep (13) so they read as a band the player is running
        // INTO rather than a line they are crossing, and both are scaled in `sync` rather than
        // rebuilt — a unit box scaled on one axis costs nothing per frame.
        floorSlab = ModelEntity(mesh: .generateBox(width: Self.fullWidth, height: 1, depth: 13),
                                materials: [matHazardDim])
        floorSlab.isEnabled = false
        curtainWall = ModelEntity(mesh: .generateBox(width: Self.fullWidth, height: 1, depth: 13),
                                  materials: [matHazardDim])
        curtainWall.isEnabled = false

        craft.addChild(hull)
        craft.addChild(halo)
        craft.addChild(core)
        group.addChild(craft)
        group.addChild(beams)
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

    /// Push one frame. `nil` means there is no encounter and the whole rig switches off.
    func sync(_ w: WardenState?, reduceMotion: Bool) {
        guard let w else {
            if group.isEnabled { group.isEnabled = false }
            return
        }
        if !group.isEnabled { group.isEnabled = true }

        // `z` is negative-ahead in the core's convention, matching `EntityState`. Only the craft
        // moves; `beams` stays anchored in world space around the player.
        craft.position = SIMD3<Float>(0, Float(w.y), Float(w.z))

        // A slow yaw sells "hovering, watching" without moving anything the player must track.
        // Reduce Motion keeps the craft dead still — it is scenery, never a readability cue.
        if !reduceMotion {
            let t = Float(w.telegraphProgress)
            hull.orientation = simd_quatf(angle: Float(w.coreHits) * 0.6 + t * 0.35,
                                          axis: SIMD3<Float>(0, 1, 0))
        }

        // Shield: the halo shrinks onto the hull as it fails, then goes out entirely. Scale rather
        // than fade, because an opaque unlit material has no honest way to fade.
        let sf = Float(w.shieldFraction)
        if sf > 0 {
            halo.isEnabled = true
            halo.scale = SIMD3<Float>(repeating: 0.55 + 0.45 * sf)
            core.isEnabled = false
        } else {
            halo.isEnabled = false
            // Exposed: the core is lit, and each hit shrinks it — three strikes and it is gone.
            core.isEnabled = w.phase != .leaving
            let left = Float(w.coreHitsNeeded - w.coreHits) / Float(max(1, w.coreHitsNeeded))
            core.scale = SIMD3<Float>(repeating: max(0.25, left))
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
            let drop = Float(Self.columnTop)
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
            let top = Float(Self.columnTop)
            let hem = hot ? Self.curtainHem : top - (top - Self.curtainHem) * min(1, t)
            let h = max(0.02, top - hem)
            curtainWall.model?.materials = [mat]
            curtainWall.scale = SIMD3<Float>(1, h, 1)
            curtainWall.position = SIMD3<Float>(0, hem + h / 2, Float(Self.strikeZ))
        }
    }

    private static func rgb(_ hex: UInt32) -> UIColor {
        UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}
