import Foundation

/// Everything a finished run feeds back into the meta layer (missions, achievements, game-over
/// stats). Built by the game layer from `GameCore` state + counted `FXEvent`s, consumed by
/// `ProfileStore.applyRunSummary`. Pure value type so the whole missions pipeline tests on Linux.
struct RunSummary: Sendable, Equatable {
    var gems: Int = 0             // core.gemCount (doubler pays 2 per gem — currency basis)
    var distance: Double = 0      // core.traveledDistance (checkpoint head-start excluded)
    var nearMissCloses: Int = 0   // counted from FXEvent.nearMiss(kind: .close)
    var slicks: Int = 0           // counted from FXEvent.nearMiss(kind: .slick)
    var slides: Int = 0           // counted from FXEvent.slid
    var bestStreak: Int = 0       // core.bestStreak
    var bestMult: Int = 1         // min(Tuning.multCap, 1 + core.bestStreak / Tuning.streakPerMult)
    var worldsCrossed: Int = 1    // core.maxWorld + 1 (1-based highest world reached this run)
    var revives: Int = 0          // core.revivesUsed
    var duration: Double = 0      // wall-clock seconds in .play this run
    var startWorld: Int = 0       // checkpoint start world (0 = full run) — XP world-delta basis
    var wardensDefeated: Int = 0  // Wardens killed this run (v1.9) — banked once, like every field here
}

/// A mission: a metric, a target, and a coin reward. Four scopes:
/// - `perRun`   — the target must be hit within a single run (progress = best single-run value).
/// - `daily`    — accumulates across today's runs, resets at UTC midnight. Three slots are picked
///                deterministically per UTC day, so everyone sees the same board.
/// - `weekly`   — accumulates across the UTC week (week key = daysSinceEpoch / 7); 3 slots drawn
///                deterministically per week, big payouts (the v1.3 long-pull earn loop).
/// - `lifetimeTiered` — an achievement ladder; each tier pays out once, in order.
struct Mission: Identifiable, Sendable {
    enum Metric: String, Sendable, CaseIterable {
        case gems, distance, nearMisses, slides, slickBonuses, runsFinished
        case streakBest, worldReached, chestsOpened, revives, multiplierHit

        /// Max-style metrics record the best value seen; the rest accumulate by summing.
        var accumulatesByMax: Bool {
            switch self {
            case .streakBest, .worldReached, .multiplierHit: return true
            default: return false
            }
        }

        /// Extract this metric's per-run value from a summary.
        func value(in s: RunSummary) -> Double {
            switch self {
            case .gems: return Double(s.gems)
            case .distance: return s.distance
            case .nearMisses: return Double(s.nearMissCloses)
            case .slides: return Double(s.slides)
            case .slickBonuses: return Double(s.slicks)
            case .runsFinished: return 1
            case .streakBest: return Double(s.bestStreak)
            case .worldReached: return Double(s.worldsCrossed)
            case .chestsOpened: return 0   // bumped by ProfileStore.openFreeChest, not by runs
            case .revives: return Double(s.revives)
            case .multiplierHit: return Double(s.bestMult)
            }
        }
    }

    enum Scope: Sendable {
        case perRun
        case daily
        case weekly
        case lifetimeTiered(targets: [Double], rewards: [Int])
    }

    let id: String
    let title: String
    let metric: Metric
    let target: Double       // perRun/daily target (tiered missions use the tier targets)
    let rewardCoins: Int     // perRun/daily reward (tiered missions use the tier rewards)
    let scope: Scope

    var isTiered: Bool { if case .lifetimeTiered = scope { return true } else { return false } }
}

/// Data-driven mission/achievement list, mirroring `SkinCatalog`. IDs are persistence keys —
/// never reuse one for different semantics.
enum MissionCatalog {
    /// Per-run skill missions: claimable once, forever, when any single run satisfies them.
    static let perRun: [Mission] = [
        Mission(id: "run.mult5",   title: "Hit a ×5 multiplier in one run",   metric: .multiplierHit, target: 5,    rewardCoins: 150, scope: .perRun),
        Mission(id: "run.slide5",  title: "Slide under 5 bars in one run",    metric: .slides,        target: 5,    rewardCoins: 100, scope: .perRun),
        Mission(id: "run.gems60",  title: "Collect 60 gems in one run",       metric: .gems,          target: 60,   rewardCoins: 120, scope: .perRun),
        Mission(id: "run.close8",  title: "Thread 8 CLOSE calls in one run",  metric: .nearMisses,    target: 8,    rewardCoins: 150, scope: .perRun),
        Mission(id: "run.dist2k",  title: "Travel 2,000 m in one run",        metric: .distance,      target: 2000, rewardCoins: 200, scope: .perRun),
    ]

    /// Daily pool — 3 slots are drawn from this per UTC day (see `dailySlots`).
    static let dailyPool: [Mission] = [
        Mission(id: "day.gems150", title: "Collect 150 gems today",       metric: .gems,         target: 150,  rewardCoins: 120, scope: .daily),
        Mission(id: "day.dist3k",  title: "Travel 3,000 m today",         metric: .distance,     target: 3000, rewardCoins: 120, scope: .daily),
        Mission(id: "day.runs5",   title: "Finish 5 runs today",          metric: .runsFinished, target: 5,    rewardCoins: 100, scope: .daily),
        Mission(id: "day.slide10", title: "Slide 10 times today",         metric: .slides,       target: 10,   rewardCoins: 100, scope: .daily),
        Mission(id: "day.close15", title: "Score 15 CLOSE bonuses today", metric: .nearMisses,   target: 15,   rewardCoins: 140, scope: .daily),
        Mission(id: "day.slick6",  title: "Score 6 SLICK bonuses today",  metric: .slickBonuses, target: 6,    rewardCoins: 140, scope: .daily),
        Mission(id: "day.streak18", title: "Reach an 18-gem streak today", metric: .streakBest,  target: 18,   rewardCoins: 120, scope: .daily),
        Mission(id: "day.chest2",  title: "Open 2 free chests today",     metric: .chestsOpened, target: 2,    rewardCoins: 80,  scope: .daily),
    ]

    /// Weekly pool — 3 slots are drawn from this per UTC week (see `weeklySlots`). Targets are
    /// ≈6–7× the daily ones, rewards 600–900; every metric is one the run pipeline already bumps
    /// (R10 — `wk.chest10` deliberately cut: chest opens don't flow through RunSummary).
    static let weeklyPool: [Mission] = [
        Mission(id: "wk.gems1k",   title: "Collect 1,000 gems this week",     metric: .gems,         target: 1_000,  rewardCoins: 700, scope: .weekly),
        Mission(id: "wk.dist20k",  title: "Travel 20,000 m this week",        metric: .distance,     target: 20_000, rewardCoins: 800, scope: .weekly),
        Mission(id: "wk.runs30",   title: "Finish 30 runs this week",         metric: .runsFinished, target: 30,     rewardCoins: 600, scope: .weekly),
        Mission(id: "wk.close75",  title: "Score 75 CLOSE bonuses this week", metric: .nearMisses,   target: 75,     rewardCoins: 900, scope: .weekly),
        Mission(id: "wk.slick35",  title: "Score 35 SLICK bonuses this week", metric: .slickBonuses, target: 35,     rewardCoins: 900, scope: .weekly),
        Mission(id: "wk.slide60",  title: "Slide 60 times this week",         metric: .slides,       target: 60,     rewardCoins: 600, scope: .weekly),
        Mission(id: "wk.streak25", title: "Reach a 25-gem streak this week",  metric: .streakBest,   target: 25,     rewardCoins: 700, scope: .weekly),
    ]

    /// Lifetime achievement ladders (tier N pays once, in order).
    static let achievements: [Mission] = [
        Mission(id: "ach.gems",   title: "Gem Hoarder",     metric: .gems,         target: 0, rewardCoins: 0,
                scope: .lifetimeTiered(targets: [100, 1_000, 10_000], rewards: [50, 200, 1_000])),
        Mission(id: "ach.dist",   title: "Marathoner",      metric: .distance,     target: 0, rewardCoins: 0,
                scope: .lifetimeTiered(targets: [10_000, 50_000, 100_000], rewards: [150, 500, 1_500])),
        Mission(id: "ach.close",  title: "Needle Threader", metric: .nearMisses,   target: 0, rewardCoins: 0,
                scope: .lifetimeTiered(targets: [100, 1_000], rewards: [200, 1_200])),
        Mission(id: "ach.slick",  title: "Limbo Legend",    metric: .slickBonuses, target: 0, rewardCoins: 0,
                scope: .lifetimeTiered(targets: [50, 500], rewards: [150, 1_000])),
        Mission(id: "ach.runs",   title: "Veteran Runner",  metric: .runsFinished, target: 0, rewardCoins: 0,
                scope: .lifetimeTiered(targets: [25, 250, 1_000], rewards: [100, 500, 2_000])),
        Mission(id: "ach.worlds", title: "World Walker",    metric: .worldReached, target: 0, rewardCoins: 0,
                scope: .lifetimeTiered(targets: [3, 6, 12], rewards: [100, 300, 1_500])),
        Mission(id: "ach.chests", title: "Chest Hunter",    metric: .chestsOpened, target: 0, rewardCoins: 0,
                scope: .lifetimeTiered(targets: [10, 100], rewards: [100, 800])),
    ]

    static func mission(_ id: String) -> Mission? {
        (perRun + dailyPool + weeklyPool + achievements).first { $0.id == id }
    }

    /// Domain-separation tag ("MISSIONS") so the daily-mission stream can never collide with the
    /// daily-challenge seed or run seeds.
    private static let dailyTag: UInt64 = 0x4D49_5353_494F_4E53

    /// The 3 daily mission slots for a given UTC day — deterministic (SplitMix64 over the day
    /// number), so every player sees the same board and re-derivation is free.
    static func dailySlots(daysSinceEpoch: Int) -> [Mission] {
        var rng = SplitMix64(seed: UInt64(bitPattern: Int64(daysSinceEpoch)) ^ dailyTag)
        var pool = dailyPool
        var picked: [Mission] = []
        for _ in 0..<min(3, pool.count) {
            picked.append(pool.remove(at: rng.int(0, pool.count - 1)))
        }
        return picked
    }

    /// Domain-separation tag ("WEEKLY13") — the weekly stream can never collide with the daily
    /// mission, daily challenge, or run-seed streams. Meta-layer SplitMix64 only: this never
    /// feeds `startRun(seed:)`, so it has zero layoutVersion implications (rule 2/3).
    private static let weeklyTag: UInt64 = 0x5745_454B_4C59_3133

    /// The 3 weekly mission slots for a given UTC week — deterministic, mirrors `dailySlots`.
    static func weeklySlots(weeksSinceEpoch: Int) -> [Mission] {
        var rng = SplitMix64(seed: UInt64(bitPattern: Int64(weeksSinceEpoch)) ^ weeklyTag)
        var pool = weeklyPool
        var picked: [Mission] = []
        for _ in 0..<min(3, pool.count) {
            picked.append(pool.remove(at: rng.int(0, pool.count - 1)))
        }
        return picked
    }
}
