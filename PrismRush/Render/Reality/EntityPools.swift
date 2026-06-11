import RealityKit

/// Pools `Entity` instances per `EntityKind`, keyed to the snapshot's stable ids. No spawn/despawn
/// churn: a vanished id's entity is hidden and returned to its kind's free list for instant reuse.
@MainActor
final class EntityPools {
    private let root: Entity
    private let make: (EntityKind) -> Entity

    private var freeByKind: [EntityKind: [Entity]] = [:]
    private var live: [Int: Entity] = [:]
    private var liveKind: [Int: EntityKind] = [:]
    private var seen = Set<Int>()
    private var vanished: [Int] = []   // scratch buffer, reused across frames (no per-frame alloc)

    init(root: Entity, make: @escaping (EntityKind) -> Entity) {
        self.root = root
        self.make = make
    }

    /// Reconcile the live entity set against this frame's snapshot. `place` positions each entity.
    func sync(_ states: [EntityState], place: (Entity, EntityState) -> Void) {
        seen.removeAll(keepingCapacity: true)
        for s in states {
            seen.insert(s.id)
            let entity: Entity
            if let existing = live[s.id] {
                entity = existing
            } else {
                entity = obtain(s.kind)
                live[s.id] = entity
                liveKind[s.id] = s.kind
                root.addChild(entity)
            }
            place(entity, s)
        }

        // Recycle ids that disappeared this frame.
        vanished.removeAll(keepingCapacity: true)
        for id in live.keys where !seen.contains(id) { vanished.append(id) }
        for id in vanished {
            if let e = live[id] { recycle(e, liveKind[id] ?? .gem) }
            live[id] = nil
            liveKind[id] = nil
        }
    }

    /// Hide everything and return it to the pools (used on run reset).
    func releaseAll() {
        for (id, e) in live { recycle(e, liveKind[id] ?? .gem) }
        live.removeAll(keepingCapacity: true)
        liveKind.removeAll(keepingCapacity: true)
    }

    private func obtain(_ kind: EntityKind) -> Entity {
        if var pool = freeByKind[kind], let e = pool.popLast() {
            freeByKind[kind] = pool
            e.isEnabled = true
            return e
        }
        return make(kind)
    }

    private func recycle(_ e: Entity, _ kind: EntityKind) {
        e.isEnabled = false
        e.removeFromParent()
        freeByKind[kind, default: []].append(e)
    }
}
