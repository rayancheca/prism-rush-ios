import Foundation

/// High-level game lifecycle state.
enum GameMode: Sendable, Equatable {
    case menu, play, over
}

/// Collectible power-up kinds.
enum PickupKind: Sendable, Equatable {
    case shield, magnet
}

/// Every renderable spawned thing. Pure data — the renderer maps these onto pooled entities.
enum EntityKind: Sendable, Equatable {
    case low        // low block: hop or it clips your feet
    case tall       // full-height block: must change lane
    case movingTall // oscillating tall wall (high difficulty), tinted as danger
    case bar        // full-span overhead bar: slide or precise jump
    case gem        // octahedron collectible
    case shield     // icosahedron pickup
    case magnet     // torus pickup
}

/// One pooled entity's render state for a single frame.
/// `z` is distance-relative to the player: negative = ahead of the player, positive = behind.
/// `lane` is -1 for full-span entities (bars).
struct EntityState: Sendable, Identifiable, Equatable {
    var id: Int
    var kind: EntityKind
    var x: Double
    var y: Double
    var z: Double
    var lane: Int
    var spin: Double        // accumulated phase for spinning/bobbing collectibles
    var fading: Bool        // entity is being magneted / absorbed: renderer may fade it

    init(id: Int, kind: EntityKind, x: Double = 0, y: Double = 0, z: Double = 0,
         lane: Int = -1, spin: Double = 0, fading: Bool = false) {
        self.id = id; self.kind = kind; self.x = x; self.y = y; self.z = z
        self.lane = lane; self.spin = spin; self.fading = fading
    }
}

/// Immutable per-frame view of the world handed to the renderer. Value type, `Sendable`.
struct GameSnapshot: Sendable {
    var mode: GameMode
    var distance: Double
    var speed: Double
    var playerX: Double
    var playerY: Double
    var playerScaleY: Double
    var bankZ: Double
    var worldFrom: Int
    var worldTo: Int
    var worldBlend: Double          // 0 → fully `worldFrom`, 1 → fully `worldTo`
    var shieldActive: Bool
    var magnetRemaining: Double
    var sliding: Bool
    var grounded: Bool
    var entities: [EntityState]
    var score: Int
    var gems: Int
    var mult: Int
    var best: Int

    /// The menu/attract state shown before the first run.
    static let initial = GameSnapshot(
        mode: .menu,
        distance: 0,
        speed: Tuning.menuSpeed,
        playerX: 0,
        playerY: 0,
        playerScaleY: 1,
        bankZ: 0,
        worldFrom: 0,
        worldTo: 0,
        worldBlend: 1,
        shieldActive: false,
        magnetRemaining: 0,
        sliding: false,
        grounded: true,
        entities: [],
        score: 0,
        gems: 0,
        mult: 1,
        best: 0
    )
}

/// One-shot effects the core emits each tick for the renderer / audio / haptics to react to.
/// The core never performs side effects itself — it only describes what happened.
enum FXEvent: Sendable, Equatable {
    case laneChanged(x: Double)
    case jumped(x: Double)
    case landed(x: Double)
    case slid(x: Double)
    case gemCollected(x: Double, y: Double, streak: Int)
    case nearMiss(kind: String, x: Double)
    case pickup(kind: PickupKind, x: Double, y: Double)
    case worldChanged(index: Int, ordinal: Int)
    case shieldAbsorbed(x: Double)
    case died(x: Double)
}
