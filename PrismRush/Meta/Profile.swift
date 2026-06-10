import Foundation

/// The player's persistent meta-game state: currency, lifetime stats, unlocks, cosmetics, and
/// progression. Pure `Codable` value type so it can be stored locally and synced to iCloud.
struct Profile: Codable, Equatable, Sendable {
    var coins: Int = 0

    // Lifetime stats.
    var bestScore: Int = 0
    var totalRuns: Int = 0
    var totalDistance: Double = 0
    var totalGems: Int = 0
    var totalCoinsEarned: Int = 0
    var bestStreak: Int = 0

    // Progression — highest world ordinal reached (enables level select / checkpoint start).
    var maxWorldReached: Int = 0

    // Cosmetics.
    var ownedSkins: Set<String> = ["default"]
    var selectedSkin: String = "default"

    // Power-up upgrade levels (0 = base). Keyed by power-up id.
    var powerUpLevels: [String: Int] = [:]

    // Monetization flags (set by StoreKit purchases).
    var doubleCoins: Bool = false
    var ownedProducts: Set<String> = []

    // Settings.
    var muted: Bool = false
    var reduceFlash: Bool = false

    var coinMultiplier: Int { doubleCoins ? 2 : 1 }
}
