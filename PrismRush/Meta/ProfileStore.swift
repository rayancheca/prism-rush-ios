import Foundation
import Observation

/// Owns the persistent `Profile`. Single source of truth for coins, unlocks, stats and progression,
/// shared across the menu / shop / character-select / game. Persists to `UserDefaults` as JSON and
/// mirrors to iCloud key-value storage so saves follow the player across devices.
@MainActor
@Observable
final class ProfileStore {
    static let shared = ProfileStore()

    private(set) var profile: Profile

    @ObservationIgnored private let localKey = "pr.profile.v1"
    @ObservationIgnored private let cloud = NSUbiquitousKeyValueStore.default

    init() {
        profile = ProfileStore.load(localKey: "pr.profile.v1", cloud: NSUbiquitousKeyValueStore.default)
        // Pull any newer cloud value when it changes (other device).
        NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: cloud, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.mergeFromCloud() }
        }
        cloud.synchronize()
    }

    // MARK: mutation

    func mutate(_ change: (inout Profile) -> Void) {
        change(&profile)
        save()
    }

    func addCoins(_ n: Int) { guard n != 0 else { return }; mutate { $0.coins += n } }

    @discardableResult
    func spendCoins(_ n: Int) -> Bool {
        guard profile.coins >= n else { return false }
        mutate { $0.coins -= n }
        return true
    }

    /// Fold a finished run into lifetime stats + currency.
    func recordRun(score: Int, distance: Double, gems: Int, bestStreak: Int, maxWorld: Int, coinsEarned: Int) {
        mutate {
            $0.coins += coinsEarned
            $0.totalCoinsEarned += coinsEarned
            $0.bestScore = max($0.bestScore, score)
            $0.totalRuns += 1
            $0.totalDistance += distance
            $0.totalGems += gems
            $0.bestStreak = max($0.bestStreak, bestStreak)
            $0.maxWorldReached = max($0.maxWorldReached, maxWorld)
        }
    }

    // MARK: cosmetics / progression helpers

    func owns(skin id: String) -> Bool { profile.ownedSkins.contains(id) }
    func unlock(skin id: String) { mutate { $0.ownedSkins.insert(id) } }
    func select(skin id: String) { mutate { $0.selectedSkin = id } }
    func powerUpLevel(_ id: String) -> Int { profile.powerUpLevels[id] ?? 0 }
    func upgradePowerUp(_ id: String) { mutate { $0.powerUpLevels[id, default: 0] += 1 } }

    /// Highest selectable starting world (0-based), capped to one past what's been reached.
    var unlockedWorldCount: Int { max(1, min(99, profile.maxWorldReached + 1)) }

    // MARK: persistence

    private func save() {
        guard let data = try? JSONEncoder().encode(profile) else { return }
        UserDefaults.standard.set(data, forKey: localKey)
        cloud.set(data, forKey: localKey)
        cloud.synchronize()
    }

    private func mergeFromCloud() {
        guard let data = cloud.data(forKey: localKey),
              let remote = try? JSONDecoder().decode(Profile.self, from: data) else { return }
        // Conservative merge: keep the higher progression/coins (last-writer-wins would lose coins).
        var merged = profile
        merged.coins = max(merged.coins, remote.coins)
        merged.bestScore = max(merged.bestScore, remote.bestScore)
        merged.maxWorldReached = max(merged.maxWorldReached, remote.maxWorldReached)
        merged.ownedSkins.formUnion(remote.ownedSkins)
        merged.ownedProducts.formUnion(remote.ownedProducts)
        merged.doubleCoins = merged.doubleCoins || remote.doubleCoins
        if merged != profile { profile = merged; save() }
    }

    private static func load(localKey: String, cloud: NSUbiquitousKeyValueStore) -> Profile {
        if let data = cloud.data(forKey: localKey), let p = try? JSONDecoder().decode(Profile.self, from: data) {
            return p
        }
        if let data = UserDefaults.standard.data(forKey: localKey), let p = try? JSONDecoder().decode(Profile.self, from: data) {
            return p
        }
        return Profile()
    }
}
