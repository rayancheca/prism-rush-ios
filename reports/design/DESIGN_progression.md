# DESIGN_progression.md — Prism Rush v1.3 XP / Levels / Economy

Role: progression & economy designer. Scope: XP system, level curve, level rewards,
character-unlock levels, 4 new earn loops, balance pass, surfacing, test plan.
NO ads, NO new dependencies, App Store shipping.

Iron-rule compliance up front:

- **No Core/spawner/RNG change anywhere in this design.** XP lives in `Meta/`, style
  coins are counted from already-emitted `FXEvent`s in the UI layer. The solvability
  bot is untouched and **`DailyChallenge.layoutVersion` does NOT need a bump for the
  progression work alone** (the mechanics designer's in-run changes own that bump).
- All new Profile fields decode via `decodeIfPresent ?? default` (rule 7).
- All payouts are per-death deltas / once-per-run via the existing `statsRecorded`
  guard and `applyRunSummary` single entry point (rule 9).
- Challenge runs keep no-revive/no-checkpoint semantics (rule 10) — XP rides the
  existing path without weakening either.
- G3: surfacing reads `ProfileStore.shared.profile.x` inline / via computed vars,
  never `@State`-captures the store, never snapshots `store.profile` into a `let`
  at the top of `body`.

---

## 1. XP SYSTEM

### 1.1 Per-run XP formula

Computed from `RunSummary` only (pure, deterministic, Linux-testable — mirrors the
missions pipeline). New pure type `XPCurve` in `PrismRush/Meta/XPCurve.swift`.

```
runXP = distanceXP + gemXP + styleXP + comboXP + worldXP   (clamped 0...2_000)

distanceXP = Int(summary.distance / 10)                     // 1 XP per 10 m survived
gemXP      = summary.gems * 2                               // 2 XP per gem
styleXP    = (summary.nearMissCloses + summary.slicks) * 5  // 5 XP per CLOSE/SLICK
comboXP    = summary.bestMult * 10                          // 10..50 (multiplier mastery)
worldXP    = max(0, (summary.worldsCrossed - 1) - summary.startWorld) * 25
```

**Why this shape:**

- *Distance* is the engagement floor — every run pays XP, even a bad one (~10–30 XP),
  so a brand-new player levels visibly from minute one.
- *Gems + combo* reward routing/greed without dominating (a gem-perfect run roughly
  doubles the distance term).
- *Style XP at 5×* is the deliberate skill premium — it ties directly into the
  mechanics designer's risk play: threading CLOSE/SLICK is the fastest way to level.
- *World XP uses the crossed-this-run delta*, not the absolute world ordinal, so a
  checkpoint start cannot farm world XP it didn't earn (same rule the coin payout
  already enforces at `GameView.swift:387`).
- **`doubleCoins` (IAP) does NOT multiply XP.** XP is progression, coins are currency;
  keeping IAP out of the level curve keeps the game non-pay-to-progress and the App
  Store narrative clean.
- Clamp at 2,000 XP/run bounds a marathon/exploit run to ~4 levels early game,
  <1 level past L15.

Typical values: weak run (300 m, 10 gems, mult 1) ≈ **60 XP**; average run (800 m,
30 gems, 4 style, mult 3, 2 worlds crossed) ≈ **240 XP**; great run (2,000 m, 80 gems,
12 style, mult 5, 4 worlds crossed) ≈ **570 XP**.

**`RunSummary` change** (`PrismRush/Meta/MissionCatalog.swift:6–17`): add one field
with a default — non-persisted value type, zero decode risk, missions untouched:

```swift
var startWorld: Int = 0   // checkpoint start world (0 = full run) — XP/world-delta basis
```

`GameView.recordRunResults` (after line 432) sets `summary.startWorld = runStartWorld`.

### 1.2 Level curve, levels 1..30

XP to go from level *n* to *n+1*: `xpToNext(n) = 150 * (n + 1)`, level cap **30**.
Single closed form: trivial to pin in tests, trivial to steepen in v1.4 if telemetry
shows top-out is too fast. Implemented as a precomputed table so the doc and the code
can never disagree:

```swift
enum XPCurve {
    static let maxLevel = 30
    /// Cumulative XP required to BE level (index+1). cumulativeXP[0] == 0 (level 1).
    static let cumulativeXP: [Int] = {
        var total = 0
        return (1...maxLevel).map { n in defer { total += 150 * (n + 1) }; return total }
    }()
    static func level(for totalXP: Int) -> Int {
        (cumulativeXP.lastIndex { $0 <= max(0, totalXP) } ?? 0) + 1
    }
    static func xpIntoLevel(for totalXP: Int) -> (current: Int, needed: Int) { … }
    static func xp(for s: RunSummary) -> Int { /* §1.1 formula, clamped 0...2_000 */ }
}
```

Cumulative table (pin these exact numbers in the unit test):

| Lv | Cum. XP | Lv | Cum. XP | Lv | Cum. XP |
|----|---------|----|---------|----|---------|
| 1  | 0       | 11 | 9,750   | 21 | 34,500  |
| 2  | 300     | 12 | 11,550  | 22 | 37,800  |
| 3  | 750     | 13 | 13,500  | 23 | 41,250  |
| 4  | 1,350   | 14 | 15,600  | 24 | 44,850  |
| 5  | 2,100   | 15 | 17,850  | 25 | 48,600  |
| 6  | 3,000   | 16 | 20,250  | 26 | 52,500  |
| 7  | 4,050   | 17 | 22,800  | 27 | 56,550  |
| 8  | 5,250   | 18 | 25,500  | 28 | 60,750  |
| 9  | 6,600   | 19 | 28,350  | 29 | 65,100  |
| 10 | 8,100   | 20 | 31,350  | 30 | 69,600  |

Pacing check (240 XP avg/run): **level 2 after ~2 runs** (300 XP — first-session
dopamine); level 5 in ~9 runs (first hour); **level 10 in ~34 runs ≈ one engaged day
/ two casual days** (8,100 XP); level 15 end of casual week 1; level 22 in week 2;
level 30 in ~2 weeks casual / ~1 week engaged. Matches the brief's ramp targets.

### 1.3 Rewards per level

Two reward streams, granted atomically inside `applyRunSummary`:

**Coin grants (banded — easy to display, easy to test):**

| New level | Coin grant |
|-----------|-----------|
| 2–9       | 100 each  |
| 10–19     | 250 each  |
| 20–29     | 500 each  |
| 30        | 2,000     |

Lifetime total: 8×100 + 10×250 + 10×500 + 2,000 = **10,300 coins** — meaningful
faucet, not inflationary against the §3 sink ladder.

**Character unlocks at FIXED levels** (character designer owns the ids/looks; these
levels are frozen here and must appear in their roster table):

| Unlock level | Slot | Pacing intent |
|--------------|------|---------------|
| **3**  | XP character #1 | first session — proves the loop within ~20 minutes |
| **6**  | XP character #2 | day 1–2 — first "come back tomorrow" pull |
| **10** | XP character #3 | engaged day 1 / casual day 3–4 — the milestone level |
| **15** | XP character #4 | end of week 1 — sustains the first week |
| **22** | XP character #5 | week 2 — long-pull aspirational |

Unlock is **derived, not persisted**: a character with `unlockLevel` is playable iff
`XPCurve.level(for: profile.totalXP) >= unlockLevel`. No ownership set to migrate, no
cloud-merge edge case, and the locked tiles in character select always show a live,
truthful "LV 15" chip. (Coin-priced characters keep using `ownedSkins` as today.)

### 1.4 Exact Profile fields (rule 7 pattern)

`PrismRush/Meta/Profile.swift` — add to the struct, `CodingKeys` (Profile.swift:56–64),
and `init(from:)` (Profile.swift:66–96):

```swift
// Progression — XP/levels (level + xp-into-level are DERIVED from totalXP, never stored).
var totalXP: Int = 0              // lifetime XP; cloud-merges as max()
var xpLevelRewarded: Int = 1      // highest level whose level-up coin grant was paid (watermark)

// Weekly missions (§2.2).
var weeklyMissionDate: Date? = nil    // UTC week the current weekly slots belong to

// Daily challenge placement rewards (§2.4).
var challengeRewardTier: Int = 0      // highest threshold tier paid TODAY (0..3; resets w/ UTC day)
```

```swift
// CodingKeys additions:
case totalXP, xpLevelRewarded, weeklyMissionDate, challengeRewardTier

// init(from:) additions — identical decodeIfPresent ?? default shape:
totalXP            = try c.decodeIfPresent(Int.self,  forKey: .totalXP) ?? d.totalXP
xpLevelRewarded    = try c.decodeIfPresent(Int.self,  forKey: .xpLevelRewarded) ?? d.xpLevelRewarded
weeklyMissionDate  = try c.decodeIfPresent(Date.self, forKey: .weeklyMissionDate) ?? d.weeklyMissionDate
challengeRewardTier = try c.decodeIfPresent(Int.self, forKey: .challengeRewardTier) ?? d.challengeRewardTier
```

`ProfileStore.sanitized` (ProfileStore.swift:50–57) gains one clamp:

```swift
if let t = p.weeklyMissionDate, t > now { p.weeklyMissionDate = now }
```

`mergeFromCloud` (ProfileStore.swift:369–386) gains conservative merges:

```swift
merged.totalXP = max(merged.totalXP, remote.totalXP)
merged.xpLevelRewarded = max(merged.xpLevelRewarded, remote.xpLevelRewarded)
// weeklyMissionDate / challengeRewardTier: deliberately NOT merged (device-local boards;
// missionProgress already merges by max; worst case is one re-earned challenge tier whose
// coins wash out in the max(coins) merge — same accepted risk class as daily boards today).
```

### 1.5 Insertion point — exactly once per run

**`ProfileStore.applyRunSummary` (ProfileStore.swift:213–228)** is the single hook.
It is called from `GameView.recordRunResults` at GameView.swift:434 **only on the
first death** (guarded by `statsRecorded`, GameView.swift:403/415); post-revive deaths
never re-enter. XP therefore inherits once-per-run for free — no new guard needed.

```swift
/// Result of folding a run: what the game-over panel animates.
struct LevelUpResult: Equatable, Sendable {
    let xpGained: Int
    let levelBefore: Int
    let levelAfter: Int
    let coinsGranted: Int            // sum of banded grants for every level crossed
    let unlockedLevels: [Int]        // crossed levels that are character-unlock levels
}

@discardableResult
func applyRunSummary(_ summary: RunSummary, now: Date = Date()) -> LevelUpResult {
    refreshDailyMissions(now: now)
    refreshWeeklyMissions(now: now)                      // §2.2
    let xp = XPCurve.xp(for: summary)
    let before = XPCurve.level(for: profile.totalXP)
    let after  = XPCurve.level(for: profile.totalXP + xp)
    var grant = 0
    if after > before {
        // Pay each crossed level once, watermarked — cloud merge can never double-pay.
        let firstUnpaid = max(before, profile.xpLevelRewarded) + 1
        if firstUnpaid <= after {
            grant = (firstUnpaid...after).reduce(0) { $0 + XPCurve.coinGrant(forLevel: $1) }
        }
    }
    mutate {
        $0.totalXP += xp
        if grant > 0 { $0.coins += grant; $0.totalCoinsEarned += grant }
        $0.xpLevelRewarded = max($0.xpLevelRewarded, after)
        for m in MissionCatalog.perRun { … }             // existing body unchanged
        for m in MissionCatalog.dailyPool { … }
        for m in MissionCatalog.weeklyPool { Self.bump(…) }   // §2.2
        for m in MissionCatalog.achievements { … }
    }
    let unlocked = after > before
        ? CharacterCatalog.xpUnlockLevels.filter { $0 > before && $0 <= after } : []
    return LevelUpResult(xpGained: xp, levelBefore: before, levelAfter: after,
                         coinsGranted: grant, unlockedLevels: unlocked)
}
```

`GameView.recordRunResults` (GameView.swift:434) captures the result:

```swift
lastLevelUp = store.applyRunSummary(summary)   // new @ObservationIgnored-free model state
```

(`lastLevelUp: LevelUpResult?` joins `lastCoinsEarned` etc. as plain GameModel state
consumed by the game-over panel; cleared in `startRun`.)

### 1.6 Anti-exploit decisions (with justification)

| Question | Decision | Why |
|----------|----------|-----|
| Checkpoint runs grant XP? | **YES** | They still exercise skill and `summary.distance` already excludes the head-start; the `startWorld` field (§1.1) zeroes the world XP for skipped worlds, mirroring the coin rule at GameView.swift:387. Only Game Center is checkpoint-gated (rule 10), not progression. |
| Daily-challenge runs grant XP? | **YES** | Same `applyRunSummary` path; revive is already disabled so there's nothing to farm. Spotlights the daily grind — the game-over panel badges it "CHALLENGE XP". |
| Post-revive tail XP? | **NO** (not granted) | Consistent with the existing missions trade-off (GameView.swift:419–422 comment): first death carries the run. Revives buy score/leaderboard, not progression. |
| Clock rollback vs XP? | **N/A by construction** | Run XP is run-gated, not time-gated — there is deliberately NO daily XP bonus, so XP needs zero new timestamps. The only new timestamp in v1.3 is `weeklyMissionDate`, which copies the daily clamp pattern verbatim (§2.2). |
| Cloud merge double-grants? | **Blocked by watermark** | `totalXP` merges max(); `xpLevelRewarded` merges max(); grants only pay levels above the watermark, so a merge that raises level without a run pays nothing twice. |
| IAP inflates XP? | **NO** | `coinMultiplier` applies to coins only (Profile.swift:50); `XPCurve.xp` never reads the profile. |

---

## 2. FOUR NEW EARN LOOPS (no ads)

Five candidates were offered; the four below are chosen because they map 1:1 to the
owner's complaints (nothing pulls forward, shop thin, in-run repetitive, challenge
dead-ends). The fifth — escalating the login ladder — is **cut**: today's ladder
(ProfileStore.swift:110, `[100,150,200,300,400,500,1000]`) is already an escalating
7-day ladder paying 1,000/day at maturity, the single largest existing faucet.
Buffing it adds inflation, not motivation. It stays exactly as is.

### 2.1 Level-up coin grants (§1.3)

- **Amounts**: 100 / 250 / 500 / 2,000 banded; lifetime cap 10,300 (structural — level
  cap 30 + `xpLevelRewarded` watermark).
- **Timestamps**: none needed (run-gated).
- **Caps**: each level pays exactly once, ever, across devices (watermark merges max).

### 2.2 Weekly mission set with big payout

- **Shape**: 3 slots drawn deterministically per UTC week from a new
  `MissionCatalog.weeklyPool` (new `Mission.Scope.weekly`), exactly mirroring the
  daily board (MissionCatalog.swift:84–93, 121–131).
- **Week key**: `weeksSinceEpoch = daysSinceEpoch / 7` (UTC, consistent with every
  other rollover — rule from ProfileStore.swift:166–181).
- **Slot draw**: `SplitMix64(seed: UInt64(bitPattern: Int64(weeksSinceEpoch)) ^ weeklyTag)`
  with a distinct domain tag `0x5745_454B_4C59_3133` ("WEEKLY13") — can never collide
  with the daily-mission or challenge streams. (Meta-layer RNG; does NOT touch run
  seeds — no layoutVersion implication.)
- **Pool (8, targets ≈ 6–7× daily, rewards 600–900)**:

| id | Title | Metric | Target | Reward |
|----|-------|--------|--------|--------|
| `wk.gems1k`   | Collect 1,000 gems this week     | gems         | 1,000  | 700 |
| `wk.dist20k`  | Travel 20,000 m this week        | distance     | 20,000 | 800 |
| `wk.runs30`   | Finish 30 runs this week         | runsFinished | 30     | 600 |
| `wk.close75`  | Score 75 CLOSE bonuses this week | nearMisses   | 75     | 900 |
| `wk.slick35`  | Score 35 SLICK bonuses this week | slickBonuses | 35     | 900 |
| `wk.slide60`  | Slide 60 times this week         | slides       | 60     | 600 |
| `wk.chest10`  | Open 10 free chests this week    | chestsOpened | 10     | 600 |
| `wk.streak25` | Reach a 25-gem streak this week  | streakBest   | 25     | 700 |

- **Cap**: 3 claims/week, structural; max ≈ **2,250–2,600 coins/week**.
- **Rollover + clock clamp** — copy `refreshDailyMissions` (ProfileStore.swift:199–210)
  verbatim with week keys:

```swift
func refreshWeeklyMissions(now: Date = Date()) {
    let thisWeek = Self.daysSinceEpoch(now) / 7
    if let last = profile.weeklyMissionDate,
       Self.daysSinceEpoch(min(last, now)) / 7 == thisWeek { return }   // min() = rollback clamp
    let ids = Set(MissionCatalog.weeklyPool.map(\.id))
    mutate {
        $0.weeklyMissionDate = now
        for id in ids { $0.missionProgress.removeValue(forKey: id); $0.claimedMissions.remove(id) }
    }
}
```

  Plus the `sanitized` future-clamp (§1.4). `claimMission` gains a `.weekly` case
  identical to `.daily` (claim only this week's 3 slots; ProfileStore.swift:284–288
  pattern). `applyRunSummary` and `unclaimedCount` iterate the weekly pool alongside
  the daily pool.

### 2.3 In-run style bonus coins (risk play → currency)

- **What**: CLOSE and SLICK near-misses pay coins as a 4th breakdown line on death.
  Direct tie-in to the mechanics designer's risk loop — the dangerous line is now the
  profitable line.
- **Formula**: `styleCoins = min(closesThisRun + slicksThisRun, 40) * 2 * coinMultiplier`
  (2 coins per style event, **hard cap 40 events/run** = 80 base coins, doubler
  applies because this IS currency).
- **Where**: `GameView.recordRunResults` (GameView.swift:386–396) — add a fourth
  per-death delta with the exact pattern of the existing three:

```swift
let styleEvents = min(closesThisRun + slicksThisRun, 40)
lastCoinsFromStyle = max(0, styleEvents * 2 * mult - styleCoinsAwarded)
styleCoinsAwarded += lastCoinsFromStyle
// … fold into coinsDelta alongside gems/distance/worlds.
```

  New GameModel vars `styleCoinsAwarded` / `lastCoinsFromStyle` reset in `startRun`
  (GameView.swift:190–194 block). Counters `closesThisRun`/`slicksThisRun` already
  exist (GameView.swift:288/291) — **zero Core change, zero RNG consumption, no
  layoutVersion bump.**
- **Caps/timestamps**: per-run cap 40 events; no timestamps (run-gated, delta-safe
  across revives by construction).
- **Worth**: ~8 coins on an average run, ~80 on a style-perfect run.

### 2.4 Daily challenge placement rewards (local thresholds)

GC board placement is optional/online; rewards must be **local score thresholds** so
every player gets them offline:

| Tier | Today's challenge best ≥ | Cumulative payout |
|------|--------------------------|-------------------|
| 1 | 1,000  | 100 |
| 2 | 5,000  | 250 (=100+150) |
| 3 | 15,000 | 500 (=100+150+250) |

- **Where**: extend `recordChallengeRun` (ProfileStore.swift:328–341). Pay the
  difference between the new tier's cumulative sum and the already-paid tier's sum;
  store `challengeRewardTier`; **reset tier to 0 when the UTC day key changes** (the
  same `sameDay` check already computed at line 330, which already routes through
  `clamped()` — clock-rollback hardening inherited for free).

```swift
let tiers = [(1_000, 100), (5_000, 150), (15_000, 250)]      // (threshold, increment)
let newTier = tiers.lastIndex { score >= $0.0 }.map { $0 + 1 } ?? 0
let paidTier = sameDay ? profile.challengeRewardTier : 0
let payout = (paidTier..<max(paidTier, newTier))
    .reduce(0) { $0 + tiers[$1].1 }
mutate {
    … existing best/date/calendar code …
    $0.challengeRewardTier = sameDay ? max($0.challengeRewardTier, newTier) : newTier
    if payout > 0 { $0.coins += payout; $0.totalCoinsEarned += payout }
}
```

- **Cap**: 500/day hard, once per UTC day; improving your score later the same day
  pays only the newly crossed tiers. Returns the payout so `GameView` can toast
  "CHALLENGE TIER \(n) · +\(coins)".

---

## 3. BALANCE

### 3.1 Updated faucet table (no-IAP, casual = 60 min/day, ~12 runs/hour)

| Source | Formula / amount | Per active hour | Per day (casual) |
|--------|------------------|-----------------|------------------|
| Run base (gems+dist+worlds) | ~62/run (unchanged) | 744 | 744 |
| **Style coins (new)** | ~8/run, cap 80 | 96 | 96 |
| Free chest | 60–220 per 30 min | ~280 | ~280 |
| Daily login (existing ladder) | 100–1,000 by streak | — | ~300 (wk-1 avg) |
| Daily missions (3 slots) | ~110 each | — | ~330 |
| Per-run missions + achievements (drip) | one-time claims | — | ~100 (wk 1) |
| **Level-up grants (new)** | banded §1.3 | — | ~250 (wk-1 avg, front-loaded) |
| **Weekly missions (new)** | ≤2,600/wk | — | ~330 amortized |
| **Challenge tiers (new)** | ≤500/day | — | ~250 |
| **Total** | | | **≈ 2,600–2,700 coins/day wk 1** |

Effective earn rate rises from ~16 to **~19–21 coins/min of play during week 1**
(decaying toward ~17 steady-state as one-time grants dry up) — a +25% faucet, all of
it attached to *doing something* (styling, leveling, weekly goals, the challenge).

### 3.2 Sink ladder — 16-character roster pricing

Roster split (character designer owns ids/looks; economy owns price/level points):
**1 default + 5 XP-locked (L3/6/10/15/22, free at level) + 1 IAP premium (Aurora-class,
$1.99) + 9 coin-priced.** Coin ladder (replaces/extends the current 5-skin ladder at
SkinCatalog.swift:19–24 — existing owned ids are honored; existing prices map onto the
nearest rung):

| Rung | Price | Casual affordability (wk 1) |
|------|-------|------------------------------|
| 1 | 300   | day 1 |
| 2 | 500   | day 1 |
| 3 | 800   | day 2 |
| 4 | 1,200 | day 2–3 |
| 5 | 1,800 | day 3–4 |
| 6 | 2,500 | day 4–5 (Midas 1,500 slots below this) |
| 7 | 3,500 | day 5–6 |
| 8 | 5,000 | day 7 |
| 9 | 7,500 | week 2 (savings goal) |

Total coin sink ≈ **23,100** (vs ~3,300 today — the "shop feels thin" fix) + revives
(150/300, unchanged — at ~19 CPM a first revive still costs ~8 minutes of earning,
which keeps it a real decision).

**Unlock cadence check (the target: casual unlocks something every 1–2 days in week
1):** Day 1 → L3 character + rung 1–2 purchase. Day 2 → L6 character + rung 3.
Day 3–4 → L10 character + rung 4–5. Day 5–6 → rung 6–7. Day 7 → L15 character + rung 8.
**Seven+ unlock moments in seven days. ✓** `doubleCoins` IAP roughly halves the coin
waits without touching XP gates.

Existing skin price adjustments: **none required** — Ember/Void/Toxic/Mono stay as
budget entry rungs; Midas (1,500) sits naturally between rungs 4 and 5. New characters
take the new rungs.

---

## 4. SURFACING (G3-safe)

1. **Game-over panel first** (GameOverView.swift; count-up scaffolding already exists
   at lines 43, 150–160): under the coin breakdown rows add an **XP row + bar**:
   "+240 XP" counts up, the level bar fills from `levelBefore` progress to
   `levelAfter` progress; on level-up the bar overshoots, snaps, and a "LEVEL 7"
   burst shows the coin grant ("+250") and — at unlock levels — "NEW CHARACTER
   UNLOCKED · TAP" which deep-links to character select (everything tappable leads
   somewhere). Data source is **GameModel state** (`lastLevelUp: LevelUpResult?`,
   set once in `recordRunResults`), not a live store re-derivation — per-run results
   are model state; the shared store is never `@State`-captured.
2. **Menu hero badge second**: small "LV 7" chip + thin XP bar near the character
   preview (the idle-preview hero the UI designer is building). Reads
   `XPCurve.level(for: ProfileStore.shared.profile.totalXP)` via a computed property
   evaluated inside `body` — never `let p = store.profile` at the top of body (G3).
   Tapping the chip opens the Profile level card.
3. **Profile screen**: full level card — level, XP-into-level / needed, next
   character-unlock preview ("LEVEL 10 — ???" silhouette).
4. **Character select**: locked tiles show "LV 15" lock chips; tapping a locked tile
   shows exactly how much XP remains (pull-forward, not a dead tap).

---

## 5. TEST PLAN (new file `Tests/CoreTests/ProgressionTests.swift` + EconomyTests additions)

Follows the `ProfileStore(testing:)` + injectable-`now` style of EconomyTests.swift.

| # | Test | Pins |
|---|------|------|
| 1 | `testXPCurvePinnedThresholds` | cumulativeXP[L2]=300, L5=2,100, L10=8,100, L20=31,350, L30=69,600; `level(for:)` inverse round-trips at every boundary ±1; level caps at 30; negative XP → level 1. |
| 2 | `testXPFormulaFromSummary` | crafted RunSummary → exact XP; per-run clamp at 2,000; `startWorld` zeroes checkpoint world XP; doubleCoins profile does NOT change XP. |
| 3 | `testApplyRunSummaryGrantsXPAndLevels` | one call adds formula XP; crossing L2 pays 100; multi-level jump pays the sum of every crossed band; no level crossed → 0 grant; `totalCoinsEarned` tracks grants. |
| 4 | `testLevelGrantWatermarkIdempotent` | raise `totalXP` (simulated cloud merge to L9) with `xpLevelRewarded=9` → next run's level-ups pay only NEW levels; watermark never pays the same level twice. |
| 5 | `testWeeklySlotsDeterministic` | same week → same 3 slots; adjacent weeks differ; weekly tag ≠ daily tag stream (slot sets differ for day 0 vs week 0). |
| 6 | `testWeeklyRolloverWipesProgressAndClaims` | progress + claim, advance 7 UTC days → board clean; same week → untouched. |
| 7 | `testWeeklyClockRollbackBlocked` | claim this week, set clock back a week → `min(last, now)` keeps board claimed (mirrors `testDailyRewardClockRollbackExploitBlocked`, EconomyTests.swift:91). |
| 8 | `testStyleCoinsDeltaAndCap` | 45 style events → capped at 40×2; revive then second death pays only the new delta (per-death delta pattern); doubler doubles. |
| 9 | `testChallengeTiersPayOncePerDay` | score 16k → 500; replay same day score 20k → +0; next UTC day resets tier; mid-day improvement 800→6k pays exactly 250. |
| 10 | `testProfileDecodesLegacyJSONWithNewFieldsDefaulted` | legacy JSON without the four new keys decodes: totalXP=0, xpLevelRewarded=1, weeklyMissionDate=nil, challengeRewardTier=0 (extends EconomyTests.swift:137 pattern). |
| 11 | `testSanitizedClampsWeeklyDate` | future `weeklyMissionDate` clamps to now on load (extends EconomyTests.swift:114). |
| 12 | `testCloudMergeKeepsMaxXPAndWatermark` | merge profile with higher/lower totalXP & watermark → max wins both; coins not double-granted post-merge. |

Regression gates: full suite stays green (95 existing + ~12 new); **solvability bot
untouched** (no Core/spawner/RNG change in this design — explicitly verified by the
absence of any `PrismRush/Core/` diff except the additive `RunSummary.startWorld`
field, which is consumed only by Meta/UI).

### Implementation file map

| Change | File |
|--------|------|
| `XPCurve` (formula, table, grants, unlock levels ref) | `PrismRush/Meta/XPCurve.swift` (new) |
| Profile fields + CodingKeys + decodeIfPresent | `PrismRush/Meta/Profile.swift:5–97` |
| sanitized clamp, applyRunSummary XP+grants, refreshWeeklyMissions, weekly claim case, challenge tiers, cloud merge | `PrismRush/Meta/ProfileStore.swift:50, 213, 199 (mirror), 281, 328, 369` |
| `RunSummary.startWorld`, `Scope.weekly`, weeklyPool, weeklyTag/slots | `PrismRush/Meta/MissionCatalog.swift:6, 55, 84 (mirror), 119 (mirror)` |
| style-coin delta, `summary.startWorld`, `lastLevelUp` capture | `PrismRush/UI/GameView.swift:190, 386–396, 423–434` |
| XP row/bar + level-up burst | `PrismRush/UI/GameOverView.swift` |
| LV chip + XP bar (menu), level card (profile), lock chips (character select) | `MenuView.swift`, `ProfileView.swift`, `CharacterSelectView.swift` |
| New tests | `Tests/CoreTests/ProgressionTests.swift` (new), `EconomyTests.swift` |
