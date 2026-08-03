import RealityKit
import simd
import UIKit

/// **THE WARDEN'S GROUND** — the structure that makes 770 m of cleared deck a PLACE (v2.4, D-038).
///
/// The owner played the v2.3 Warden, which had just had nine separate complaints fixed, and said it
/// *"still feels very empty"*. Playing it confirms why, and the reason is not the fight's tuning:
/// **the arena is furnished less than open track.** Two mechanisms stack.
///
///   1. `Warden.suppresses` deliberately deletes every obstacle and boost pad from the arena so the
///      telegraph is the only thing to read (decree 6). That is correct and stays.
///   2. `WorldDecor.style` disables every side silhouette for folded world ordinal ≥ 3 — and
///      Wardens live at worlds 3, 6 and 9. **The three arenas a player actually meets are the only
///      stretches in the game with no side decor at all.**
///
/// So the player crosses into the boss arena and the world gets emptier. On a 26 s capture of a
/// rank-1 encounter every frame from 2,418 m onward held nothing but black sky, blue grid, the
/// craft and gems (`docs/agent/audits/scratch/s014_play_report.md`).
///
/// This class answers that with geometry the suppression rule never touches, because `suppresses`
/// filters `SpawnCmd`s and decor is not one. Nothing here is an obstacle, nothing here collides,
/// and **nothing here can reach `Core/`** — so the 200-seed solvability proof, every daily golden
/// and `DailyChallenge.layoutVersion` are all untouched by its existence. It reads distance off the
/// snapshot and draws.
///
/// **Four rules it obeys, stated so they are not re-litigated:**
///
/// 1. *Nothing crosses a lane.* Everything is outboard of x ±4.2 (the obstacle span is ±3.8) or
///    above y 11. The owner's v2.2 verdict was *"blocking the view of everything"* about 23.2 u² of
///    frontal area; this adds **zero** inside the lane corridor.
/// 2. *Thin sections.* Max cross-section 0.55 u, so even where a far pylon crosses the craft's rim
///    it is a few pixels.
/// 3. *No new motion.* Every piece is static in world space and the world scroll supplies the
///    movement, so there is nothing for Reduce Motion to gate and nothing that blinks. The only
///    blinking thing in the game is the 7 Hz stumble ring, and competing with it would be a
///    legibility bug.
/// 4. *No RNG, ever.* Every position is `k × spacing` from the arena mouth. The structure is
///    identical every time you meet it, which is most of what makes somewhere a place rather than a
///    sample of noise — and it means this file cannot perturb a seeded run even in principle.
@MainActor
final class ArenaShell {

    // MARK: geometry constants
    //
    // All in world units. x ±3.8 is the obstacle span and ±3.3 the outer lane lines, so the kerb at
    // ±4.5 is the closest anything gets — outboard of everything the player reads, inboard of the
    // ribs, and still on the 16-wide ground plane.

    private static let ribX: Float = 5.6
    private static let ribHeight: Float = 10.5
    private static let ribSpacing: Double = 22        // 1.5 Hz at 33 m/s
    private static let lightX: Float = 5.30
    private static let kerbX: Float = 4.5
    private static let kerbSpacing: Double = 20       // tiles butt end to end → reads continuous
    private static let kerbTileLength: Float = 20

    /// The visible band, in `z`. The backdrop wall sits at z −65 and is the practical far clip; a
    /// piece is worth a transform write only inside this.
    private static let zFar: Float = -70
    private static let zNear: Float = 14

    /// Structure tone: lighter than the deck, world-blind. Borrowed from the chasm's rim, which is
    /// the one piece of geometry in the game already proven to read as "solid thing" at speed
    /// without belonging to any world's palette.
    private static let structureHex: UInt32 = 0x2A23_40
    /// The DIM violet, not the hazard's `0xC77BFF`. A saturated violet arena would collide with the
    /// one channel that has to stay unambiguous — the thing about to hit you.
    private static let groundVioletHex: UInt32 = 0x7B3B_C4

    // MARK: pools

    private let group = Entity()
    private var ribs: [Entity] = []          // one per pair: two pylons + two lights, parented
    private var kerbTiles: [Entity] = []     // one per tile: body + cap, both sides
    private let gate = Entity()
    private var gateParts: [ModelEntity] = []

    private var lightMats: [ModelEntity] = []   // the pieces whose colour follows the world
    private var styledWorld = -1

    // MARK: build

    init(root: Entity) {
        let structure = UnlitMaterial(color: Self.rgb(Self.structureHex))

        // ONE mesh per family, scaled per instance — the trick `WorldDecor` uses so that 54 entities
        // cost 7 meshes rather than 54.
        let pylonMesh = MeshResource.generateBox(width: 0.45, height: 1, depth: 0.9, cornerRadius: 0.05)
        let lightMesh = MeshResource.generateBox(width: 0.16, height: 1, depth: 0.16)
        let kerbMesh = MeshResource.generateBox(width: 0.5, height: 0.22,
                                                depth: Self.kerbTileLength, cornerRadius: 0.03)
        let capMesh = MeshResource.generateBox(width: 0.5, height: 0.05, depth: Self.kerbTileLength)

        // RIBS — paired pylons straddling the track, with a neon stroke on each inner face. The
        // stroke is what actually reads at 30 m/s; the pylon is the mass behind it.
        for _ in 0..<Self.poolSize(spacing: Self.ribSpacing) {
            let pair = Entity()
            for side in [Float(-1), 1] {
                let pylon = ModelEntity(mesh: pylonMesh, materials: [structure])
                pylon.scale = SIMD3<Float>(1, Self.ribHeight, 1)
                pylon.position = SIMD3<Float>(side * Self.ribX, Self.ribHeight / 2, 0)
                pair.addChild(pylon)

                let light = ModelEntity(mesh: lightMesh, materials: [structure])
                light.scale = SIMD3<Float>(1, 8.2, 1)
                light.position = SIMD3<Float>(side * Self.lightX, 4.4, 0)
                pair.addChild(light)
                lightMats.append(light)
            }
            pair.isEnabled = false
            group.addChild(pair)
            ribs.append(pair)
        }

        // KERB — the rails. The closest, fastest-moving thing in the frame, and therefore the
        // strongest speed cue the arena can own: it stays on screen until it is past the player's
        // shoulder, where nothing else in this file reaches.
        for _ in 0..<Self.poolSize(spacing: Self.kerbSpacing) {
            let tile = Entity()
            for side in [Float(-1), 1] {
                let body = ModelEntity(mesh: kerbMesh, materials: [structure])
                body.position = SIMD3<Float>(side * Self.kerbX, 0.11, 0)
                tile.addChild(body)

                let cap = ModelEntity(mesh: capMesh, materials: [structure])
                cap.position = SIMD3<Float>(side * Self.kerbX, 0.235, 0)
                tile.addChild(cap)
                lightMats.append(cap)
            }
            tile.isEnabled = false
            group.addChild(tile)
            kerbTiles.append(tile)
        }

        // GATES — the mouth and the exit, and the only full-span geometry here.
        //
        // **Why a full-span header is safe when a hanging bar was not.** A gate at `into == 0`
        // renders at `z == into`, which is >= 0 — behind the player — for the entire window in which
        // a Warden can exist (it arms only inside `Tuning.wardenArmWindow`, the first 60 m). It is
        // seen on the APPROACH, when the sky is empty and the deck is clear, and it leaves the frame
        // over the TOP rather than across the deck. The exit gate is 770 m later, by which time the
        // fight is long over (worst case 758 m, measured 438 m), and the two are never in the
        // visible band together.
        for side in [Float(-1), 1] {
            let pylon = ModelEntity(mesh: pylonMesh, materials: [structure])
            pylon.scale = SIMD3<Float>(1.6, 13, 1.2)
            pylon.position = SIMD3<Float>(side * Self.ribX, 6.5, 0)
            gate.addChild(pylon)
            gateParts.append(pylon)
        }
        let header = ModelEntity(mesh: MeshResource.generateBox(width: 13.2, height: 0.5, depth: 0.9),
                                 materials: [structure])
        header.position = SIMD3<Float>(0, 13.0, 0)
        gate.addChild(header)
        gateParts.append(header)

        let lintel = ModelEntity(mesh: MeshResource.generateBox(width: 12.4, height: 0.14, depth: 0.14),
                                 materials: [structure])
        lintel.position = SIMD3<Float>(0, 12.68, 0)
        gate.addChild(lintel)
        lightMats.append(lintel)

        gate.isEnabled = false
        group.addChild(gate)

        root.addChild(group)
    }

    /// Slots needed to cover the visible band at `spacing`, plus one so a piece entering at the far
    /// edge never has to wait for one to leave at the near edge.
    private static func poolSize(spacing: Double) -> Int {
        Int((Double(zNear - zFar) / spacing).rounded(.up)) + 1
    }

    // MARK: per-frame

    /// Place everything for this frame, or switch the whole shell off.
    ///
    /// The early return is the common case by a wide margin: arenas are 770 m of every 2,400, and
    /// the visible band adds only ~84 m, so this costs one `Warden.arenaWorld` call — a division and
    /// a modulo — on roughly two frames in three.
    func update(distance: Double, world: Int, mode: GameMode) {
        guard mode != .menu,
              let start = Self.arenaStart(forDistance: distance) else {
            if group.isEnabled { group.isEnabled = false }
            return
        }
        group.isEnabled = true
        restyleIfNeeded(world: world)

        let into = distance - start

        Self.place(ribs, spacing: Self.ribSpacing, into: into)
        Self.place(kerbTiles, spacing: Self.kerbSpacing, into: into)

        // The two gates, 770 m apart, can never both be in an 84 m band — so one group serves both.
        let mouthZ = Float(into)
        let exitZ = Float(into - Tuning.wardenArenaLength)
        if mouthZ > Self.zFar && mouthZ < Self.zNear {
            gate.isEnabled = true
            gate.position.z = mouthZ
        } else if exitZ > Self.zFar && exitZ < Self.zNear {
            gate.isEnabled = true
            gate.position.z = exitZ
        } else if gate.isEnabled {
            gate.isEnabled = false
        }
    }

    /// The absolute distance at which the arena containing — or about to contain — `d` begins.
    ///
    /// Deliberately WIDER than `Warden.isArena`: the mouth gate has to be drawn while the player is
    /// still approaching it, which is the whole point of an entrance. `Warden.metresToNextArena`
    /// supplies the approach half and `Warden.arenaWorld` the inside half, so this stays a pure
    /// function of distance and agrees with the sim by construction rather than by a second copy of
    /// the arithmetic.
    private static func arenaStart(forDistance d: Double) -> Double? {
        if let w = Warden.arenaWorld(forDistance: d) {
            return Double(w) * Tuning.worldLength
        }
        // Not inside one: draw the approach only once the mouth is inside the visible band, and the
        // exit gate of the arena just left behind for as long as it is still on screen.
        if let ahead = Warden.metresToNextArena(from: d), ahead < Double(-zFar) {
            return d + ahead
        }
        let w = Int((d / Tuning.worldLength).rounded(.down))
        if w > 0, w % Tuning.wardenEveryWorlds == 0 {
            let start = Double(w) * Tuning.worldLength
            let into = d - start
            if into >= Tuning.wardenArenaLength && into < Tuning.wardenArenaLength + Double(zNear - zFar) {
                return start
            }
        }
        return nil
    }

    /// One formula, used by every family: feature `k` sits at `start + k × spacing`, therefore at
    /// `z = into − k × spacing`. `kFirst` is the lowest `k` not yet past the near edge, so the pool
    /// always covers a contiguous run and no slot is ever wasted behind the camera.
    private static func place(_ slots: [Entity], spacing: Double, into: Double) {
        let kFirst = max(0, Int(((into - Double(zNear)) / spacing).rounded(.down)) + 1)
        let last = Int(Tuning.wardenArenaLength / spacing)
        for (j, slot) in slots.enumerated() {
            let k = kFirst + j
            let z = Float(into - Double(k) * spacing)
            let live = k <= last && z > zFar && z < zNear
            if slot.isEnabled != live { slot.isEnabled = live }
            if live { slot.position.z = z }
        }
    }

    /// Recolour the light strips to the world's own accent, exactly the rule side decor uses — so an
    /// arena belongs to the world it interrupts and hue-shifts with the evolution cycle instead of
    /// looking like a prefab dropped into every one of them.
    ///
    /// Guarded on the ordinal so it allocates on a world change and never per frame.
    private func restyleIfNeeded(world: Int) {
        guard world != styledWorld else { return }
        styledWorld = world
        let tint = Theme.evolvedPalette(ordinal: world).accent2
        // 0.6 is `WorldDecor.dim`'s factor: decor must read as background, never compete with an
        // obstacle. Mixed halfway to the ground violet so the arena is legibly the Warden's even in
        // a world whose accent is already violet (world 9's grid is — see the play report).
        let mixed = SIMD3<Float>(
            tint.x * 0.6 * 0.5 + 0.482 * 0.5,
            tint.y * 0.6 * 0.5 + 0.231 * 0.5,
            tint.z * 0.6 * 0.5 + 0.769 * 0.5
        )
        let mat = UnlitMaterial(color: UIColor(red: CGFloat(mixed.x), green: CGFloat(mixed.y),
                                               blue: CGFloat(mixed.z), alpha: 1))
        for e in lightMats { e.model?.materials = [mat] }
    }

    private static func rgb(_ hex: UInt32) -> UIColor {
        UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}
