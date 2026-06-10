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
    #if canImport(Darwin)
    @ObservationIgnored private let cloud = NSUbiquitousKeyValueStore.default
    #endif
    @ObservationIgnored private let persisting: Bool

    /// Test-only: start from a known profile with persistence + cloud disabled.
    init(testing profile: Profile) {
        self.profile = profile
        self.persisting = false
    }

    init() {
        persisting = true
        #if canImport(Darwin)
        profile = ProfileStore.load(localKey: "pr.profile.v1", cloud: NSUbiquitousKeyValueStore.default)
        // Pull any newer cloud value when it changes (other device).
        NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: cloud, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.mergeFromCloud() }
        }
        cloud.synchronize()
        #else
        profile = ProfileStore.loadLocal(localKey: localKey)
        #endif
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

    /// Highest selectable starting world (0-based), capped to one past what's been reached.
    var unlockedWorldCount: Int { max(1, min(99, profile.maxWorldReached + 1)) }

    // MARK: retention — daily reward, login streak, timed free chest (all `now`-injectable for tests)

    static let dailyTiers = [100, 150, 200, 300, 400, 500, 1000]
    static let chestInterval: TimeInterval = 30 * 60   // a free chest every 30 minutes

    func dailyRewardAvailable(now: Date = Date()) -> Bool {
        guard let last = profile.lastDailyClaim else { return true }
        return !Calendar.current.isDate(last, inSameDayAs: now)
    }

    /// The streak the player would have by claiming now (yesterday → +1, gap → reset to 1).
    func pendingDailyStreak(now: Date = Date()) -> Int {
        guard let last = profile.lastDailyClaim else { return 1 }
        if Calendar.current.isDate(last, inSameDayAs: now) { return profile.loginStreak }
        if let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: now),
           Calendar.current.isDate(last, inSameDayAs: yesterday) {
            return profile.loginStreak + 1
        }
        return 1
    }

    func dailyReward(forStreak streak: Int) -> Int {
        Self.dailyTiers[min(max(streak, 1) - 1, Self.dailyTiers.count - 1)]
    }

    @discardableResult
    func claimDailyReward(now: Date = Date()) -> (coins: Int, streak: Int)? {
        guard dailyRewardAvailable(now: now) else { return nil }
        let streak = pendingDailyStreak(now: now)
        let coins = dailyReward(forStreak: streak)
        mutate { $0.lastDailyClaim = now; $0.loginStreak = streak; $0.coins += coins; $0.totalCoinsEarned += coins }
        return (coins, streak)
    }

    func chestReady(now: Date = Date()) -> Bool {
        guard let last = profile.lastChestOpen else { return true }
        return now.timeIntervalSince(last) >= Self.chestInterval
    }

    func secondsUntilChest(now: Date = Date()) -> TimeInterval {
        guard let last = profile.lastChestOpen else { return 0 }
        return max(0, Self.chestInterval - now.timeIntervalSince(last))
    }

    @discardableResult
    func openFreeChest(now: Date = Date(), reward: Int? = nil) -> Int? {
        guard chestReady(now: now) else { return nil }
        let amount = reward ?? Int.random(in: 60...220)
        mutate { $0.lastChestOpen = now; $0.coins += amount; $0.totalCoinsEarned += amount }
        return amount
    }

    // MARK: persistence

    private func save() {
        guard persisting, let data = try? JSONEncoder().encode(profile) else { return }
        UserDefaults.standard.set(data, forKey: localKey)
        #if canImport(Darwin)
        cloud.set(data, forKey: localKey)
        cloud.synchronize()
        #endif
    }

    private static func loadLocal(localKey: String) -> Profile {
        if let data = UserDefaults.standard.data(forKey: localKey),
           let p = try? JSONDecoder().decode(Profile.self, from: data) {
            return p
        }
        return Profile()
    }

    #if canImport(Darwin)
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
    #endif
}
