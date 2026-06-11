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
    /// Stable per-install slot for the `coinsPurchasedByDevice` G-counter. Device-local on
    /// purpose (never synced): two devices must never increment the SAME slot, or the per-key-max
    /// cloud merge would collapse concurrent real-money purchases into one.
    @ObservationIgnored private let deviceKey: String
    #if canImport(Darwin)
    @ObservationIgnored private let cloud = NSUbiquitousKeyValueStore.default
    #endif
    @ObservationIgnored private let persisting: Bool

    /// Test-only: start from a known profile with persistence + cloud disabled.
    init(testing profile: Profile, deviceKey: String = "test-device") {
        self.profile = profile
        self.persisting = false
        self.deviceKey = deviceKey
    }

    init() {
        persisting = true
        deviceKey = ProfileStore.persistentDeviceKey()
        #if canImport(Darwin)
        profile = ProfileStore.sanitized(
            ProfileStore.load(localKey: "pr.profile.v1", cloud: NSUbiquitousKeyValueStore.default))
        // Pull any newer cloud value when it changes (other device).
        NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: cloud, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.mergeFromCloud() }
        }
        cloud.synchronize()
        #else
        profile = ProfileStore.sanitized(ProfileStore.loadLocal(localKey: localKey))
        #endif
    }

    /// Stable per-install id for the purchased-coins G-counter slot (created once, kept in
    /// device-local UserDefaults — deliberately OUTSIDE the synced profile).
    private static func persistentDeviceKey() -> String {
        let key = "pr.device.id"
        if let existing = UserDefaults.standard.string(forKey: key) { return existing }
        let fresh = UUID().uuidString
        UserDefaults.standard.set(fresh, forKey: key)
        return fresh
    }

    // MARK: clock-manipulation hardening

    /// Clamp any stored timestamp that claims to be in the future down to `now`. Without this, a
    /// player can set the device clock forward, claim a reward, set it back, and the future-dated
    /// `last…` timestamp makes every timer read as elapsed/ready again. Applied to every loaded
    /// profile (local, cloud, and external cloud merges); the read paths clamp too (belt and braces).
    static func sanitized(_ p: Profile, now: Date = Date()) -> Profile {
        var p = p
        if let t = p.lastDailyClaim, t > now { p.lastDailyClaim = now }
        if let t = p.lastChestOpen, t > now { p.lastChestOpen = now }
        if let t = p.dailyMissionDate, t > now { p.dailyMissionDate = now }
        if let t = p.dailyChallengeDate, t > now { p.dailyChallengeDate = now }
        if let t = p.weeklyMissionDate, t > now { p.weeklyMissionDate = now }
        return p
    }

    /// A stored "last claimed/opened" instant, clamped so a future-dated value (clock rollback
    /// exploit) reads as "just now" — i.e. claimed today / cooldown fully re-armed.
    private func clamped(_ stored: Date?, now: Date) -> Date? {
        guard let stored else { return nil }
        return min(stored, now)
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

    // MARK: IAP coin grants (v1.4.1 — first-purchase funnel)

    /// Pure payout rule for a VERIFIED coin-pack purchase: the first coin pack ever bought pays a
    /// one-time +50% bonus (integer half, rounded down — never overpays); every later pack pays
    /// face value. Static + pure so the rule and its idempotence pin in Linux tests.
    static func coinPackPayout(base: Int, bonusUsed: Bool) -> Int {
        bonusUsed ? base : base + base / 2
    }

    /// Run a verified-purchase grant exactly once per StoreKit transaction. The id is recorded
    /// in the SAME mutate as the grant (atomic — a crash can't split marker from payout), so a
    /// `Transaction.updates` redelivery of an unfinished transaction is a no-op: base coins,
    /// bonus AND `totalIAPPurchases` all replay-safe (v1.4.1 review). `nil` = no StoreKit
    /// context (tests / legacy callers): applies unconditionally.
    @discardableResult
    func applyOncePerTransaction(_ transactionID: UInt64?, _ change: (inout Profile) -> Void) -> Bool {
        if let id = transactionID, profile.grantedTransactionIDs.contains(id) { return false }
        mutate {
            if let id = transactionID { $0.recordGrantedTransaction(id) }
            change(&$0)
        }
        return true
    }

    /// Grant a verified coin-pack purchase — called from `IAPCatalog.apply` ONLY (the single
    /// verified-transaction grant path). The bonus flag flips in the same mutate as the payout,
    /// so any later pack can never pay the +50% twice, and `transactionID` makes the WHOLE grant
    /// replay-idempotent via `applyOncePerTransaction`. The payout also lands in the per-device
    /// `coinsPurchasedByDevice` G-counter, so an iCloud merge can never erase real-money coins
    /// (see `merged`). Restores never route here (`IAPCatalog.restore` skips consumables).
    /// Purchased coins are bought, not earned: `totalCoinsEarned` stays untouched.
    func grantCoinPack(_ base: Int, transactionID: UInt64? = nil) {
        guard base > 0 else { return }
        let payout = Self.coinPackPayout(base: base, bonusUsed: profile.firstPurchaseBonusUsed)
        applyOncePerTransaction(transactionID) {
            $0.coins += payout
            $0.coinsPurchasedByDevice[deviceKey, default: 0] += payout
            $0.firstPurchaseBonusUsed = true
            $0.totalIAPPurchases += 1
        }
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

    /// The ONLY way any consumer reads the player's level (R9) — derived, never stored.
    var playerLevel: Int { XPCurve.level(for: profile.totalXP) }

    /// Insert every newly-earned skin into ownedSkins; returns the new ones (for the unlock toast).
    /// ownedSkins insertion IS the dedupe — a skin is "new" exactly once, and the existing
    /// cloud-merge `formUnion(ownedSkins)` syncs grants across devices for free. Coin/IAP skins
    /// never auto-grant (`SkinUnlocks.earned` returns false — they go through buy/shop flows).
    @discardableResult
    func refreshSkinUnlocks(level: Int) -> [Skin] {
        let new = SkinCatalog.all.filter {
            !profile.ownedSkins.contains($0.id) && SkinUnlocks.earned($0, profile: profile, level: level)
        }
        guard !new.isEmpty else { return [] }
        mutate { p in for s in new { p.ownedSkins.insert(s.id) } }
        return new
    }

    /// Clear the NEW badges: everything currently owned has now been seen (CharacterSelect onAppear).
    func markSkinsSeen() {
        guard !profile.ownedSkins.subtracting(profile.seenSkins).isEmpty else { return }
        mutate { $0.seenSkins.formUnion($0.ownedSkins) }
    }

    /// Worlds the level-select tab DISPLAYS (v1.4: every card visible, locked ones purchasable).
    static let worldDisplayCount = 12

    /// The deepest starting world offered in level select (matches the world cards the UI shows).
    static let maxStartWorlds = worldDisplayCount

    /// Highest selectable starting world (0-based), capped to one past what's been reached.
    var unlockedWorldCount: Int { max(1, min(Self.maxStartWorlds, profile.maxWorldReached + 1)) }

    // MARK: world purchases (v1.4 — every world card is startable: reach it OR buy it)

    /// Startable = reached OR purchased. Purchases unlock INDIVIDUALLY — a bought world 5 with
    /// world 4 still locked is fine (each card stands alone; world 0 is always free).
    func isWorldStartable(_ index: Int) -> Bool {
        guard index >= 0 else { return false }
        return index <= profile.maxWorldReached || profile.purchasedWorlds.contains(index)
    }

    /// Deepest startable world (0-based) — reach or purchase, whichever is further. Display-side
    /// only: reach-gated systems (achievements, world coin bonus, XP) keep reading `maxWorldReached`.
    var highestStartableWorld: Int { max(profile.maxWorldReached, profile.purchasedWorlds.max() ?? 0) }

    /// Buy a locked world outright (false if already startable, out of range, or unaffordable).
    /// Deliberately NEVER touches `maxWorldReached`: achievements / world bonus / XP stay
    /// REACH-based (rules 9/10) — a purchased start rides the existing `usedCheckpoint` path,
    /// so the Game Center skip is preserved for free.
    @discardableResult
    func unlockWorld(_ index: Int) -> Bool {
        guard (1..<Self.worldDisplayCount).contains(index),
              !isWorldStartable(index),
              spendCoins(XPCurve.worldPrice(index)) else { return false }
        mutate { $0.purchasedWorlds.insert(index) }
        return true
    }

    /// The world ordinal a finished run may fold into `maxWorldReached` (and feed the reach-based
    /// `ach.worlds` ladder via `RunSummary.worldsCrossed`). A run started WITHIN the reach at
    /// launch credits everything it crossed — pushing past your deepest world still advances
    /// reach. A run started BEYOND it (a PURCHASED world) credits nothing new: otherwise one
    /// bought-deep death would fold the start world into `maxWorldReached`, flip every cheaper
    /// rung startable for free (collapsing the 59,400 ladder to its deepest rung), and pay
    /// reach achievements for never passing world 0 — exactly the fold the `purchasedWorlds`
    /// invariant forbids (rules 9/10). Pure + static so the gate pins in Linux tests.
    static func reachCredit(maxWorldThisRun: Int, startWorld: Int, reachAtStart: Int) -> Int {
        startWorld <= reachAtStart ? maxWorldThisRun : reachAtStart
    }

    // MARK: retention — daily reward, login streak, timed free chest (all `now`-injectable for tests)

    static let dailyTiers = [100, 150, 200, 300, 400, 500, 1000]
    static let chestInterval: TimeInterval = 30 * 60   // a free chest every 30 minutes

    func dailyRewardAvailable(now: Date = Date()) -> Bool {
        guard let last = clamped(profile.lastDailyClaim, now: now) else { return true }
        return !Calendar.current.isDate(last, inSameDayAs: now)
    }

    /// The streak the player would have by claiming now (yesterday → +1, gap → reset to 1).
    func pendingDailyStreak(now: Date = Date()) -> Int {
        guard let last = clamped(profile.lastDailyClaim, now: now) else { return 1 }
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
        guard let last = clamped(profile.lastChestOpen, now: now) else { return true }
        return now.timeIntervalSince(last) >= Self.chestInterval
    }

    func secondsUntilChest(now: Date = Date()) -> TimeInterval {
        guard let last = clamped(profile.lastChestOpen, now: now) else { return 0 }
        return max(0, Self.chestInterval - now.timeIntervalSince(last))
    }

    @discardableResult
    func openFreeChest(now: Date = Date(), reward: Int? = nil) -> Int? {
        guard chestReady(now: now) else { return nil }
        let amount = reward ?? Int.random(in: 60...220)
        refreshDailyMissions(now: now)
        mutate {
            $0.lastChestOpen = now; $0.coins += amount; $0.totalCoinsEarned += amount
            Self.bump(&$0.missionProgress, metric: .chestsOpened, by: 1)
        }
        return amount
    }

    // MARK: missions & achievements

    /// UTC calendar — daily missions and the daily challenge roll over at UTC midnight, worldwide.
    @ObservationIgnored private static let utc: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return c
    }()

    static func daysSinceEpoch(_ date: Date) -> Int {
        Int(floor(date.timeIntervalSince1970 / 86_400))
    }

    /// ISO "yyyy-MM-dd" in UTC — the day key used for challenge calendars + rollover checks.
    static func utcDayKey(_ date: Date) -> String {
        let c = utc.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// Seconds until the next UTC midnight (drives the daily countdowns).
    static func secondsUntilUTCMidnight(now: Date = Date()) -> TimeInterval {
        let next = Double(daysSinceEpoch(now) + 1) * 86_400
        return max(0, next - now.timeIntervalSince1970)
    }

    /// Today's 3 daily mission slots (deterministic per UTC day). Also rolls progress over if the
    /// stored slots belong to a previous day.
    func dailyMissions(now: Date = Date()) -> [Mission] {
        refreshDailyMissions(now: now)
        return MissionCatalog.dailySlots(daysSinceEpoch: Self.daysSinceEpoch(now))
    }

    /// If the UTC day changed since the last visit, wipe daily progress + claims so the new board
    /// starts clean. (A future-dated stored day is clamped by `sanitized`/read order — setting the
    /// clock back simply re-rolls the board; nothing becomes claimable twice in one real day.)
    func refreshDailyMissions(now: Date = Date()) {
        let today = Self.utcDayKey(now)
        if let last = profile.dailyMissionDate, Self.utcDayKey(min(last, now)) == today { return }
        let dailyIDs = Set(MissionCatalog.dailyPool.map(\.id))
        mutate {
            $0.dailyMissionDate = now
            for id in dailyIDs {
                $0.missionProgress.removeValue(forKey: id)
                $0.claimedMissions.remove(id)
            }
        }
    }

    /// This week's 3 weekly mission slots (deterministic per UTC week). Also rolls progress over
    /// if the stored slots belong to a previous week — mirrors `dailyMissions`.
    func weeklyMissions(now: Date = Date()) -> [Mission] {
        refreshWeeklyMissions(now: now)
        return MissionCatalog.weeklySlots(weeksSinceEpoch: Self.daysSinceEpoch(now) / 7)
    }

    /// If the UTC week changed since the last visit, wipe weekly progress + claims so the new
    /// board starts clean. `min(last, now)` is the clock-rollback clamp: setting the clock back
    /// keeps the current board (and its claims) instead of re-rolling a claimable one.
    func refreshWeeklyMissions(now: Date = Date()) {
        let thisWeek = Self.daysSinceEpoch(now) / 7
        if let last = profile.weeklyMissionDate,
           Self.daysSinceEpoch(min(last, now)) / 7 == thisWeek { return }
        let ids = Set(MissionCatalog.weeklyPool.map(\.id))
        mutate {
            $0.weeklyMissionDate = now
            for id in ids {
                $0.missionProgress.removeValue(forKey: id)
                $0.claimedMissions.remove(id)
            }
        }
    }

    /// Fold one finished run into XP/levels (watermarked coin grants), the per-world best map,
    /// and per-run / daily / weekly / lifetime mission progress. Called exactly once per run
    /// (GameView's `statsRecorded` guard) — post-revive deaths never re-enter, so XP inherits
    /// once-per-run for free (rule 9).
    @discardableResult
    func applyRunSummary(_ summary: RunSummary, now: Date = Date()) -> LevelUpResult {
        refreshDailyMissions(now: now)
        refreshWeeklyMissions(now: now)
        let xp = XPCurve.xp(for: summary)
        let before = XPCurve.level(for: profile.totalXP)
        let after = XPCurve.level(for: profile.totalXP + xp)
        // Pay each crossed level once, EVER — watermarked so a cloud merge that raises the level
        // without a run (totalXP/xpLevelRewarded both merge as max) can never double-pay.
        var grant = 0
        let firstUnpaid = max(before, profile.xpLevelRewarded) + 1
        if firstUnpaid <= after {
            grant = (firstUnpaid...after).reduce(0) { $0 + XPCurve.coinGrant(forLevel: $1) }
        }
        mutate {
            $0.totalXP += xp
            if grant > 0 { $0.coins += grant; $0.totalCoinsEarned += grant }
            $0.xpLevelRewarded = max($0.xpLevelRewarded, after)
            // Per-world best distance (R14): credit every world index this run traversed with how
            // far INTO it the run got (absolute position = startWorld·L + distance, L per world).
            let L = Tuning.worldLength
            let finalWorld = max(summary.startWorld, summary.worldsCrossed - 1)
            for w in summary.startWorld...finalWorld {
                let into = min(L, Double(summary.startWorld) * L + summary.distance - Double(w) * L)
                // `into > 0` guard: a malformed summary (worldsCrossed overstating distance) must
                // not seed 0-valued keys — once written they live forever via per-key-max merge.
                guard into > 0 else { continue }
                $0.bestDistanceByWorld[w] = max($0.bestDistanceByWorld[w] ?? 0, into)
            }
            for m in MissionCatalog.perRun {
                // Per-run missions track the best single-run value (the run must do it alone).
                let v = m.metric.value(in: summary)
                $0.missionProgress[m.id] = max($0.missionProgress[m.id] ?? 0, v)
            }
            for m in MissionCatalog.dailyPool {
                Self.bump(&$0.missionProgress, id: m.id, metric: m.metric, in: summary)
            }
            for m in MissionCatalog.weeklyPool {
                Self.bump(&$0.missionProgress, id: m.id, metric: m.metric, in: summary)
            }
            for m in MissionCatalog.achievements {
                Self.bump(&$0.missionProgress, id: m.id, metric: m.metric, in: summary)
            }
        }
        let unlocked = after > before
            ? XPCurve.xpUnlockLevels.filter { $0 > before && $0 <= after } : []
        return LevelUpResult(xpGained: xp, levelBefore: before, levelAfter: after,
                             coinsGranted: grant, unlockedLevels: unlocked)
    }

    private static func bump(_ progress: inout [String: Double], id: String, metric: Mission.Metric, in summary: RunSummary) {
        let v = metric.value(in: summary)
        guard v > 0 else { return }
        if metric.accumulatesByMax {
            progress[id] = max(progress[id] ?? 0, v)
        } else {
            progress[id] = (progress[id] ?? 0) + v
        }
    }

    /// Bump every mission tracking `metric` by a flat amount (non-run events, e.g. chest opens).
    private static func bump(_ progress: inout [String: Double], metric: Mission.Metric, by amount: Double) {
        for m in MissionCatalog.perRun + MissionCatalog.dailyPool + MissionCatalog.weeklyPool
            + MissionCatalog.achievements
        where m.metric == metric {
            progress[m.id] = (progress[m.id] ?? 0) + amount
        }
    }

    /// One mission's live display state.
    struct MissionState {
        var progress: Double
        var target: Double
        var reward: Int
        var claimable: Bool
        var claimed: Bool      // fully exhausted (per-run/daily claimed; tiered = all tiers paid)
        var tier: Int          // tiers already claimed (tiered missions only; else 0)
        var tierCount: Int     // total tiers (tiered missions only; else 1)
    }

    func missionState(_ m: Mission, now: Date = Date()) -> MissionState {
        let progress = profile.missionProgress[m.id] ?? 0
        switch m.scope {
        case .perRun, .daily, .weekly:
            let claimed = profile.claimedMissions.contains(m.id)
            return MissionState(progress: min(progress, m.target), target: m.target, reward: m.rewardCoins,
                                claimable: !claimed && progress >= m.target, claimed: claimed,
                                tier: 0, tierCount: 1)
        case .lifetimeTiered(let targets, let rewards):
            let tier = min(profile.achievementTier[m.id] ?? 0, targets.count)
            let done = tier >= targets.count
            let target = done ? targets[targets.count - 1] : targets[tier]
            let reward = done ? 0 : rewards[min(tier, rewards.count - 1)]
            return MissionState(progress: min(progress, target), target: target, reward: reward,
                                claimable: !done && progress >= target, claimed: done,
                                tier: tier, tierCount: targets.count)
        }
    }

    /// Claim a completed mission → coins. Daily/weekly boards are refreshed first so a stale
    /// claim from yesterday's (or last week's) board can't pay out today.
    @discardableResult
    func claimMission(_ id: String, now: Date = Date()) -> Int? {
        refreshDailyMissions(now: now)
        refreshWeeklyMissions(now: now)
        guard let m = MissionCatalog.mission(id) else { return nil }
        if case .daily = m.scope {
            // Only today's 3 slots are claimable (pool missions still accumulate quietly).
            guard MissionCatalog.dailySlots(daysSinceEpoch: Self.daysSinceEpoch(now))
                .contains(where: { $0.id == id }) else { return nil }
        }
        if case .weekly = m.scope {
            // Only this week's 3 slots are claimable (same rule as the daily board).
            guard MissionCatalog.weeklySlots(weeksSinceEpoch: Self.daysSinceEpoch(now) / 7)
                .contains(where: { $0.id == id }) else { return nil }
        }
        let state = missionState(m, now: now)
        guard state.claimable, state.reward > 0 else { return nil }
        mutate {
            switch m.scope {
            case .perRun, .daily, .weekly:
                $0.claimedMissions.insert(id)
            case .lifetimeTiered:
                $0.achievementTier[id] = state.tier + 1
            }
            $0.coins += state.reward
            $0.totalCoinsEarned += state.reward
        }
        return state.reward
    }

    /// How many missions/achievement tiers are ready to claim (menu badge).
    func unclaimedCount(now: Date = Date()) -> Int {
        refreshDailyMissions(now: now)
        refreshWeeklyMissions(now: now)
        let active = MissionCatalog.perRun + dailyMissions(now: now) + weeklyMissions(now: now)
            + MissionCatalog.achievements
        return active.filter { missionState($0, now: now).claimable }.count
    }

    // MARK: daily challenge (shared seeded run, one track per UTC day)

    /// Seed for today's shared challenge run — derived from the UTC calendar date so the whole
    /// world plays the same track and rolls over together.
    func todaysChallengeSeed(now: Date = Date()) -> UInt64 {
        let c = Self.utc.dateComponents([.year, .month, .day], from: now)
        return DailyChallenge.seed(year: c.year ?? 1970, month: c.month ?? 1, day: c.day ?? 1)
    }

    /// Best score on TODAY'S challenge (0 if not yet played today, UTC).
    func todaysChallengeBest(now: Date = Date()) -> Int {
        guard let last = clamped(profile.dailyChallengeDate, now: now),
              Self.utcDayKey(last) == Self.utcDayKey(now) else { return 0 }
        return profile.dailyChallengeBest
    }

    /// Local placement tiers for the daily challenge: (score threshold, coin increment). Offline-
    /// friendly — every player gets them without Game Center; ≤500 coins/day, once per tier.
    static let challengeTiers = [(1_000, 100), (5_000, 150), (15_000, 250)]

    /// Record a finished challenge run: keeps the per-UTC-day best, marks the day played, and
    /// pays any newly crossed local placement tiers (R16). Returns the payout (0 if none) so
    /// GameView can toast "CHALLENGE TIER n · +coins". The tier watermark resets with the UTC
    /// day; `sameDay` routes through `clamped()`, so clock-rollback hardening is inherited.
    @discardableResult
    func recordChallengeRun(score: Int, now: Date = Date()) -> Int {
        let today = Self.utcDayKey(now)
        let sameDay = clamped(profile.dailyChallengeDate, now: now).map { Self.utcDayKey($0) == today } ?? false
        let newTier = Self.challengeTiers.lastIndex { score >= $0.0 }.map { $0 + 1 } ?? 0
        let paidTier = sameDay ? profile.challengeRewardTier : 0
        let payout = (paidTier..<max(paidTier, newTier)).reduce(0) { $0 + Self.challengeTiers[$1].1 }
        mutate {
            $0.dailyChallengeBest = sameDay ? max($0.dailyChallengeBest, score) : score
            $0.dailyChallengeDate = now
            $0.challengeDaysPlayed.insert(today)
            // Bound storage: the UI only shows a 7-day calendar; keep a generous 60-day window.
            if $0.challengeDaysPlayed.count > 60 {
                let keep = $0.challengeDaysPlayed.sorted().suffix(60)
                $0.challengeDaysPlayed = Set(keep)
            }
            $0.challengeRewardTier = sameDay ? max($0.challengeRewardTier, newTier) : newTier
            if payout > 0 { $0.coins += payout; $0.totalCoinsEarned += payout }
        }
        return payout
    }

    /// Whether the challenge was played on the UTC day `offset` days before today (0 = today).
    func playedChallenge(daysAgo offset: Int, now: Date = Date()) -> Bool {
        let day = now.addingTimeInterval(-Double(offset) * 86_400)
        return profile.challengeDaysPlayed.contains(Self.utcDayKey(day))
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

    /// Conservative two-way profile merge (iCloud): keep the higher progression/coins, union the
    /// monotonic sets, per-key-max the maps (last-writer-wins would lose coins). Pure + static so
    /// the merge rules pin in Linux tests. `totalXP`/`xpLevelRewarded` merge as max — paired with
    /// the grant watermark, a merge that raises level without a run can never double-pay.
    /// `weeklyMissionDate`/`challengeRewardTier` are deliberately NOT merged: device-local boards
    /// (missionProgress already merges by max; same accepted risk class as the daily board).
    ///
    /// COINS (v1.4.1 BLOCKER fix): earned coins keep the conservative max(), but the winning
    /// balance is then credited with every PAID coin-pack payout it has never seen. The
    /// `coinsPurchasedByDevice` G-counter merges per-key max (each install owns its own slot),
    /// so the credit is exactly the real-money coins missing from the max() winner — a merge
    /// can never erase a purchase, and the +50% first-purchase bonus rides the payout
    /// (Decree 5: advertised bonuses are always delivered). Convergent: once both sides carry
    /// the merged counter, the credit is zero forever.
    static func merged(local: Profile, remote: Profile) -> Profile {
        var merged = local
        let winnerPurchased = (local.coins >= remote.coins ? local : remote).totalCoinsPurchased
        merged.coinsPurchasedByDevice = local.coinsPurchasedByDevice
            .merging(remote.coinsPurchasedByDevice) { max($0, $1) }
        merged.coins = max(local.coins, remote.coins)
            + max(0, merged.totalCoinsPurchased - winnerPurchased)
        merged.grantedTransactionIDs.formUnion(remote.grantedTransactionIDs)
        merged.trimGrantedTransactionIDs()
        merged.bestScore = max(merged.bestScore, remote.bestScore)
        merged.maxWorldReached = max(merged.maxWorldReached, remote.maxWorldReached)
        merged.purchasedWorlds.formUnion(remote.purchasedWorlds)
        merged.ownedSkins.formUnion(remote.ownedSkins)
        merged.ownedProducts.formUnion(remote.ownedProducts)
        merged.doubleCoins = merged.doubleCoins || remote.doubleCoins
        merged.totalIAPPurchases = max(merged.totalIAPPurchases, remote.totalIAPPurchases)
        merged.firstPurchaseBonusUsed = merged.firstPurchaseBonusUsed || remote.firstPurchaseBonusUsed
        merged.missionProgress.merge(remote.missionProgress) { mine, theirs in max(mine, theirs) }
        merged.claimedMissions.formUnion(remote.claimedMissions)
        merged.achievementTier.merge(remote.achievementTier) { mine, theirs in max(mine, theirs) }
        merged.challengeDaysPlayed.formUnion(remote.challengeDaysPlayed)
        merged.totalXP = max(merged.totalXP, remote.totalXP)
        merged.xpLevelRewarded = max(merged.xpLevelRewarded, remote.xpLevelRewarded)
        merged.seenSkins.formUnion(remote.seenSkins)
        merged.bestDistanceByWorld.merge(remote.bestDistanceByWorld) { mine, theirs in max(mine, theirs) }
        return merged
    }

    #if canImport(Darwin)
    private func mergeFromCloud() {
        guard let data = cloud.data(forKey: localKey),
              let decoded = try? JSONDecoder().decode(Profile.self, from: data) else { return }
        let remote = ProfileStore.sanitized(decoded)
        let merged = Self.merged(local: profile, remote: remote)
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
