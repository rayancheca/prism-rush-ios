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

    // Retention / live-ops.
    var lastDailyClaim: Date? = nil   // when the daily bonus was last claimed
    var loginStreak: Int = 0          // consecutive days the daily bonus was claimed
    var lastChestOpen: Date? = nil    // when the free timed chest was last opened

    // Monetization flags (set by StoreKit purchases).
    var doubleCoins: Bool = false
    var ownedProducts: Set<String> = []

    // Settings.
    var muted: Bool = false
    var reduceFlash: Bool = false

    var coinMultiplier: Int { doubleCoins ? 2 : 1 }
}

// Resilient decoding: every field is optional-with-default, so adding or removing fields never fails
// to decode (and never silently wipes a saved profile). The memberwise + synthesized `encode` remain.
extension Profile {
    enum CodingKeys: String, CodingKey {
        case coins, bestScore, totalRuns, totalDistance, totalGems, totalCoinsEarned, bestStreak
        case maxWorldReached, ownedSkins, selectedSkin
        case lastDailyClaim, loginStreak, lastChestOpen
        case doubleCoins, ownedProducts, muted, reduceFlash
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Profile()   // defaults
        coins = try c.decodeIfPresent(Int.self, forKey: .coins) ?? d.coins
        bestScore = try c.decodeIfPresent(Int.self, forKey: .bestScore) ?? d.bestScore
        totalRuns = try c.decodeIfPresent(Int.self, forKey: .totalRuns) ?? d.totalRuns
        totalDistance = try c.decodeIfPresent(Double.self, forKey: .totalDistance) ?? d.totalDistance
        totalGems = try c.decodeIfPresent(Int.self, forKey: .totalGems) ?? d.totalGems
        totalCoinsEarned = try c.decodeIfPresent(Int.self, forKey: .totalCoinsEarned) ?? d.totalCoinsEarned
        bestStreak = try c.decodeIfPresent(Int.self, forKey: .bestStreak) ?? d.bestStreak
        maxWorldReached = try c.decodeIfPresent(Int.self, forKey: .maxWorldReached) ?? d.maxWorldReached
        ownedSkins = try c.decodeIfPresent(Set<String>.self, forKey: .ownedSkins) ?? d.ownedSkins
        selectedSkin = try c.decodeIfPresent(String.self, forKey: .selectedSkin) ?? d.selectedSkin
        lastDailyClaim = try c.decodeIfPresent(Date.self, forKey: .lastDailyClaim) ?? d.lastDailyClaim
        loginStreak = try c.decodeIfPresent(Int.self, forKey: .loginStreak) ?? d.loginStreak
        lastChestOpen = try c.decodeIfPresent(Date.self, forKey: .lastChestOpen) ?? d.lastChestOpen
        doubleCoins = try c.decodeIfPresent(Bool.self, forKey: .doubleCoins) ?? d.doubleCoins
        ownedProducts = try c.decodeIfPresent(Set<String>.self, forKey: .ownedProducts) ?? d.ownedProducts
        muted = try c.decodeIfPresent(Bool.self, forKey: .muted) ?? d.muted
        reduceFlash = try c.decodeIfPresent(Bool.self, forKey: .reduceFlash) ?? d.reduceFlash
    }
}
