# S-017 · missions-inventory — what the missions system IS today

READ-ONLY pass at HEAD `ba9655d` (branch main, clean). No build, no simctl. Every claim carries a
`file:line` verified by opening the file at that line. Where I looked and found nothing, I say
NOT FOUND and give the grep.

Files read in full: `PrismRush/Meta/MissionCatalog.swift` (177 lines),
`PrismRush/UI/MissionsView.swift` (576), `PrismRush/Meta/Profile.swift` (184),
`PrismRush/Meta/ProfileStore.swift` (747), `Tests/CoreTests/MissionsTests.swift`,
the weekly block of `Tests/CoreTests/ProgressionTests.swift`, `UITests/InteractionUITests.swift`
(missions leg), plus every consumer found by
`grep -rn "unclaimedCount\|missionState\|dailyMissions(\|weeklyMissions(\|refreshDailyMissions\|refreshWeeklyMissions\|claimMission\|MissionBoardSummary\|MissionCatalog\." --include="*.swift" .`

---

## 0. Executive shape

Missions are **28 catalogue entries in four scopes** (6 per-run + 8 daily pool + 7 weekly pool +
7 achievement ladders totalling 18 tiers), all of which pay **coins and nothing else**, rendered as
**19 cards in one flat scroll on one screen**, reachable from **two places in the whole app**, and
surfaced **nowhere at all in or after a run**. The engine underneath is correct, deterministic,
well-tested and Linux-testable. The product on top of it is a coin dispenser nobody visits.

The owner's four complaints map cleanly onto four different code facts, and only one of them is
about pixels:

| complaint | the code fact | where |
|---|---|---|
| **does nothing** | `GameView` never calls `missionState` / `unclaimedCount` / `MissionCatalog` — a mission completing during a run produces zero feedback anywhere, including on the death panel | §4.1 |
| **not rewarding** | mean daily mission = **115 coins**; the free chest = **mean 140 coins, every 30 min, uncapped, for zero play**. Every mission + achievement ever = 12,320 coins = **14.8%** of the 83,500-coin catalogue and **20.7%** of the world ladder alone | §4.2 |
| **not easy to understand** | 19 cards, 4 sections, 2 different reset clocks, 2 different progress semantics (max vs sum) and a "T2" pip ladder — none of it explained on-screen | §4.3 |
| **ugly** | out of scope for this pass — see `s017_*` craft passes; `MissionsView.swift` is 576 lines of one flat `VStack` inside a `TimelineView` | §4.3 |

Two live correctness defects found by this pass that are **not** in the backlog: **N1** (cloud merge
can resurrect a claim onto a fresh board) and **N2** (CLAIM ALL pays exactly one tier per ladder and
never says so). Details in §5.2.

---

## 1. Every mission type

### 1.1 Per-run "CHALLENGES" — `MissionCatalog.swift:90-97`

Scope `.perRun`. Claimable **once, forever**. Progress = **best single-run value**
(`ProfileStore.swift:460-464`, `max(existing, v)`, no accumulation across runs — pinned by
`MissionsTests.swift:93-104`).

| id | display text | metric | target | reward | advanced by |
|---|---|---|---|---|---|
| `run.mult5` | "Hit a ×5 multiplier in one run" | `.multiplierHit` | 5 | 150 | `ProfileStore.swift:463` ← `GameView.swift:1008` (`min(Tuning.multCap, 1 + bestStreak/streakPerMult)`) |
| `run.slide5` | "Slide under 5 bars in one run" | `.slides` | 5 | 100 | ← `GameView.swift:1006` `slidesThisRun` (counted off `FXEvent.slid`, `GameCore.swift:453`) |
| `run.gems60` | "Collect 60 gems in one run" | `.gems` | 60 | 120 | ← `GameView.swift:1000` `gemsDelta` |
| `run.close8` | "Thread 8 CLOSE calls in one run" | `.nearMisses` | 8 | 150 | ← `GameView.swift:1002` `closesThisRun` |
| `run.dist2k` | "Travel 2,000 m in one run" | `.distance` | 2000 | 200 | ← `GameView.swift:1001` `distanceDelta` |
| `run.warden1` | "Defeat a Warden" | `.wardensDefeated` | 1 | 250 | ← `GameView.swift:1003` `wardensDefeatedThisRun` |

**Lifetime total: 970 coins.** All six are reachable. `run.mult5` sits exactly at the cap
(`Tuning.swift:149` — `multCap: Int = 5`), so it is satisfied at 20 gems of streak, the moment the
multiplier tops out; there is no headroom above it.

### 1.2 Daily pool — `MissionCatalog.swift:100-109`

Scope `.daily`. **8 entries, 3 drawn per UTC day** (`MissionCatalog.swift:152-160`). Progress
**sums** across the day's runs except for max-style metrics (`MissionCatalog.swift:43-48`;
accumulation at `ProfileStore.swift:481-489`).

| id | display text | metric | target | reward | note |
|---|---|---|---|---|---|
| `day.gems150` | "Collect 150 gems today" | `.gems` | 150 | 120 | sum |
| `day.dist3k` | "Travel 3,000 m today" | `.distance` | 3000 | 120 | sum |
| `day.runs5` | "Finish 5 runs today" | `.runsFinished` | 5 | 100 | `value(in:)` is a literal `1` (`MissionCatalog.swift:58`) |
| `day.slide10` | "Slide 10 times today" | `.slides` | 10 | 100 | sum |
| `day.close15` | "Score 15 CLOSE bonuses today" | `.nearMisses` | 15 | 140 | sum |
| `day.slick6` | "Score 6 SLICK bonuses today" | `.slickBonuses` | 6 | 140 | sum |
| `day.streak18` | "Reach an 18-gem streak today" | `.streakBest` | 18 | 120 | **max**, not sum (`MissionCatalog.swift:45`) |
| `day.chest2` | "Open 2 free chests today" | `.chestsOpened` | 2 | 80 | **run-blind**: `value(in:)` returns a literal `0` (`MissionCatalog.swift:61`); only advanced by `ProfileStore.openFreeChest` → `bump(_:metric:by:)` (`ProfileStore.swift:345`, `:492-498`) |

**Mean 115 coins × 3 slots = 345 coins/day.** Matches `s016_coins-economy.md:73`.

### 1.3 Weekly pool — `MissionCatalog.swift:114-122`

Scope `.weekly`. **7 entries, 3 drawn per UTC week** (week key = `daysSinceEpoch / 7`,
`MissionCatalog.swift:168-176`).

| id | display text | metric | target | reward |
|---|---|---|---|---|
| `wk.gems1k` | "Collect 1,000 gems this week" | `.gems` | 1,000 | 700 |
| `wk.dist20k` | "Travel 20,000 m this week" | `.distance` | 20,000 | 800 |
| `wk.runs30` | "Finish 30 runs this week" | `.runsFinished` | 30 | 600 |
| `wk.close75` | "Score 75 CLOSE bonuses this week" | `.nearMisses` | 75 | 900 |
| `wk.slick35` | "Score 35 SLICK bonuses this week" | `.slickBonuses` | 35 | 900 |
| `wk.slide60` | "Slide 60 times this week" | `.slides` | 60 | 600 |
| `wk.streak25` | "Reach a 25-gem streak this week" | `.streakBest` | 25 | 700 |

**Mean 743 × 3 = 2,229/week = 318/day.** The docstring at `MissionCatalog.swift:111-113` records
that a `wk.chest10` was deliberately cut because chest opens don't ride `RunSummary` — correct, and
it means the weekly board is the only one of the four with a homogeneous progress source.

### 1.4 Achievement ladders — `MissionCatalog.swift:125-140`

Scope `.lifetimeTiered`. **7 ladders, 18 tiers.** Each tier pays once, **in order**
(`ProfileStore.swift:549-557`, `:583-584`). Never reset.

| id | title | metric | tier targets | tier rewards | ladder total |
|---|---|---|---|---|---|
| `ach.gems` | Gem Hoarder | `.gems` | 100 / 1,000 / 10,000 | 50 / 200 / 1,000 | 1,250 |
| `ach.dist` | Marathoner | `.distance` | 10k / 50k / 100k m | 150 / 500 / 1,500 | 2,150 |
| `ach.close` | Needle Threader | `.nearMisses` | 100 / 1,000 | 200 / 1,200 | 1,400 |
| `ach.slick` | Limbo Legend | `.slickBonuses` | 50 / 500 | 150 / 1,000 | 1,150 |
| `ach.runs` | Veteran Runner | `.runsFinished` | 25 / 250 / 1,000 | 100 / 500 / 2,000 | 2,600 |
| `ach.worlds` | World Walker | `.worldReached` | 3 / 6 / 12 | 100 / 300 / 1,500 | 1,900 |
| `ach.chests` | Chest Hunter | `.chestsOpened` | 10 / 100 | 100 / 800 | 900 |

**Lifetime total: 11,350 coins.** Matches `s016_coins-economy.md:77`.

`ach.worlds` is **reach-based, not purchase-based** — it is fed by `RunSummary.worldsCrossed`, which
`GameView.swift:1009` sets to `reachWorld + 1` where `reachWorld` comes from
`ProfileStore.reachCredit` (`ProfileStore.swift:290-292`). Buying world 8 does not advance it. That
is deliberate (iron rules 9/10) and is pinned by `EconomyTests.swift:163-165`.

### 1.5 Unreachable / dead entries

- **`Mission.Metric.revives` is declared and used by zero missions.** Grep: `grep -rn "\.revives"
  --include="*.swift" .` returns only the enum case (`MissionCatalog.swift:35`), its
  `value(in:)` arm (`:62`), the `RunSummary` field (`:15`), the capture site
  (`GameView.swift:1012`) and the test helper (`MissionsTests.swift:34`). No `Mission` in any of the
  four catalogues uses it. It is also structurally pinned to 0 — `summary.revives = core.revivesUsed`
  is read inside the `else` branch of `if statsRecorded` (`GameView.swift:979`, `:991`, `:1012`),
  i.e. at the FIRST death, before any revive can have happened. This is backlog **PR-0176**
  (SEV4 after re-score). Still real at HEAD.
- **No mission is unsatisfiable.** `run.warden1` needs one Warden kill and the Warden ships
  (`GameCore.swift` `wardensDefeatedThisRun` wiring, `GameView.swift:1003`); `day.chest2` needs 2
  chests at a 30-min cooldown (`ProfileStore.swift:297`); `ach.worlds` tier 3 needs world 12 =
  9,600 m in one run (`Tuning.swift:8`, `worldLength: Double = 800`), which the difficulty curve
  supports (`s016_coins-economy.md:59` shows a 103,000 m bot run).
- **9 of the 15 pool entries are unclaimable on any given day/week but still accumulate.** See §5.1
  finding **P4**.

---

## 2. The complete lifecycle

### 2.1 Rolling — deterministic, unseeded-RNG-free, `Date()`-driven at the edge only

```swift
// MissionCatalog.swift:148-160
private static let dailyTag: UInt64 = 0x4D49_5353_494F_4E53   // "MISSIONS"
static func dailySlots(daysSinceEpoch: Int) -> [Mission] {
    var rng = SplitMix64(seed: UInt64(bitPattern: Int64(daysSinceEpoch)) ^ dailyTag)
    var pool = dailyPool
    var picked: [Mission] = []
    for _ in 0..<min(3, pool.count) {
        picked.append(pool.remove(at: rng.int(0, pool.count - 1)))
    }
    return picked
}
```

Weekly is the identical shape with tag `0x5745_454B_4C59_3133` ("WEEKLY13") over
`weeksSinceEpoch` (`MissionCatalog.swift:165-176`).

**The roll uses no `Date()` and no unseeded RNG.** It is a pure function of an integer day/week
number, so it is fully testable and identical for every player worldwide. `Date()` enters only as a
default argument at the *store* boundary (`ProfileStore.dailyMissions(now: Date = Date())`,
`:377`), and every call site in the app passes an explicit `now` from a `TimelineView` context date
(`MissionsView.swift:36`, `MenuView.swift:345`) — **except** the single-claim path, which calls
`Date()` directly (`MissionsView.swift:478`; see §5.2 **N3**).

Both streams are domain-separated from the run seed and from each other. `ProgressionTests.swift:269-271`
asserts day-0 and week-0 boards are disjoint. **Neither stream feeds `startRun(seed:)`, so nothing in
this system has `layoutVersion` implications** — stated at `MissionCatalog.swift:163-164` and true.

### 2.2 Reset

```swift
// ProfileStore.swift:385-396
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
```

Weekly is the same over `daysSinceEpoch(now) / 7` (`ProfileStore.swift:408-420`).

- **Trigger:** lazily, on any read — `dailyMissions` (`:378`), `weeklyMissions` (`:401`),
  `applyRunSummary` (`:428-429`), `claimMission` (`:564-565`), `unclaimedCount` (`:594-595`),
  `openFreeChest` (`:342`). There is no timer and no background refresh; the board is refreshed
  because somebody looked at it.
- **Clock rollback:** `min(last, now)` is the clamp; setting the clock back keeps the current board
  and its claims. Pinned by `ProgressionTests.testWeeklyClockRollbackBlocked` (`:306-318`). Forward
  clock is NOT defended (backlog **PR-0035**, and `state.md:475` records backward-clock mission
  farming as an accepted trade-off — note the two statements disagree about which direction is
  open).
- **Unclaimed at reset:** **destroyed, silently, with no warning and no grace period.** The wipe
  removes both `missionProgress` and `claimedMissions` for every pool id, so a mission that was
  100% complete but unclaimed at 23:59 UTC is worth zero at 00:01. Pinned as *correct* behaviour by
  `MissionsTests.testDailyBoardRolloverResetsProgressAndClaims` (`:62-78`) and
  `ProgressionTests.testWeeklyRolloverWipesProgressAndClaims` (`:275-304`).
- **Can progress be lost:** yes, three ways. (a) The reset above. (b) The reset fires on any read
  after rollover, including the hub badge, so it can happen while the player is looking at the hub
  and never opened Missions. (c) **N1** in §5.2 — a cloud merge can import a stale claim onto a
  freshly rolled board.

### 2.3 Advancing

One writer for run-driven progress: `ProfileStore.applyRunSummary` (`:427-479`), called exactly once
per run behind `GameView`'s `statsRecorded` guard (`GameView.swift:979`, `:991`, `:1016`).

```swift
// ProfileStore.swift:460-473
for m in MissionCatalog.perRun {
    let v = m.metric.value(in: summary)
    $0.missionProgress[m.id] = max($0.missionProgress[m.id] ?? 0, v)   // no v > 0 guard — PR-0172
}
for m in MissionCatalog.dailyPool  { Self.bump(&$0.missionProgress, id: m.id, metric: m.metric, in: summary) }
for m in MissionCatalog.weeklyPool { Self.bump(&$0.missionProgress, id: m.id, metric: m.metric, in: summary) }
for m in MissionCatalog.achievements { Self.bump(&$0.missionProgress, id: m.id, metric: m.metric, in: summary) }
```

Note it loops the **whole pool**, not the drawn slots — that is what makes §5.1 **P4** true.

One writer for non-run progress: `openFreeChest` → `bump(_:metric:by:)` (`ProfileStore.swift:345`,
`:492-498`), which bumps **every** mission in all four catalogues carrying that metric. Today only
`.chestsOpened` uses it, hitting `day.chest2` and `ach.chests` (pinned,
`MissionsTests.swift:168-177`).

**Post-revive play is not folded in at all** — the summary is captured at the first death and the
revived tail contributes nothing to any mission (`GameView.swift:979-990` pays coins/stats only, with
the trade-off written out at `:996-998`). Backlog **PR-0255 / PR-0307**, both OPEN, both real at HEAD.

---

## 3. The claim path

### 3.1 CLAIM (single card)

```swift
// MissionsView.swift:476-484
private func claim() {
    let reward = state.reward
    guard ProfileStore.shared.claimMission(mission.id, now: Date()) != nil else { return }
    onClaim()
    if !reduceMotion { flyAmount = reward; flyTrigger += 1 }
}
```

→ `ProfileStore.claimMission` (`:562-590`):

1. `refreshDailyMissions` + `refreshWeeklyMissions` first (`:564-565`) — a stale board can never pay.
2. Catalogue lookup; unknown ids return `nil` (`:566`, pinned `MissionsTests.swift:134`).
3. **Slot gate**: a `.daily` mission must be in today's 3 slots (`:567-571`); a `.weekly` in this
   week's 3 (`:572-576`). Off-board pool entries return `nil` even at 100%.
4. `missionState(m, now:)` recomputed fresh (`:577`); `guard state.claimable, state.reward > 0`.
5. One atomic `mutate` (`:579-588`): mark claimed (`claimedMissions.insert` for
   perRun/daily/weekly, `achievementTier[id] = state.tier + 1` for ladders) **and** credit
   `coins` + `totalCoinsEarned` in the same transaction.

**Reward is credited at `ProfileStore.swift:586-587` and nowhere else.** Coins only. No XP, no
charges, no cosmetic. `totalCoinsEarned` is bumped, which means mission claims count as *earned*
coins for the profile stats — consistent with the daily bonus (`:324`) and deliberately unlike
purchased/gacha coins (`:107-109`, `:176`).

**Idempotent: yes**, and by construction rather than by a flag check.
- perRun/daily/weekly: the second call recomputes `missionState`, sees `claimed == true`, so
  `claimable == false`, and returns `nil` before the mutate (`:545-548`, `:578`). Pinned
  `MissionsTests.testClaimOnceSemantics` (`:116-126`).
- tiered: `state.tier` is re-read from the profile each call, so `achievementTier[id] = tier + 1`
  advances exactly one rung per successful call, never re-pays a paid rung. Pinned
  `MissionsTests.testTieredAchievementClaimsInOrder` (`:139-158`).
- The `.neon` button style does not debounce, but the store recheck makes a double-tap harmless.

### 3.2 CLAIM ALL

`MissionsView.swift:118-155`. Renders only at `claimables.count >= 2` (`:119`). Label advertises
`CLAIM ALL +\(total)` where `total` is the sum of `state.reward` over the claimables (`:120`).
On tap: one `.purchaseChime`, then an unstructured `Task { @MainActor in … }` (`:130-137`) that
claims one mission per 80 ms, incrementing `claimPulse` per landing.

Two things worth knowing:
- It passes the **rendered** `now`, not a live `Date()` — deliberately, with the reasoning written
  out at `:124-129` (a live clock could roll over mid-cascade and silently pay less than the button
  promised). Good. The single-claim path does the opposite (§5.2 **N3**).
- The queue is captured before the loop (`let queue = claimables`, `:121`) and each mission appears
  **once**, so a ladder with two already-earned tiers pays only one of them. See **N2**.

### 3.3 Is the profile mutated from inside a SwiftUI `body`? **YES — confirmed at file:line.**

The filed defect is **PR-0006** (`docs/agent/03_BACKLOG.md:103-113`, SEV1, status OPEN). It cites
`MenuView` only; it is **worse than filed** — the Missions screen itself does it 4× per render pass.

`refreshDailyMissions`/`refreshWeeklyMissions` call `mutate` (`ProfileStore.swift:389`, `:413`),
which calls `save()` (`:92`), which writes `UserDefaults` **and** `cloud.set` +
`cloud.synchronize()` (`:655-662`). Every one of these is inside a view `body`:

| site | call | reaches |
|---|---|---|
| `MissionsView.swift:37` | `claimableMissions(store:now:)` → `:160-161` `store.dailyMissions/weeklyMissions` | `refreshDaily/WeeklyMissions` → `mutate` → `save()` |
| `MissionsView.swift:39` | `summaryStrip` → `:111` `activeStates` → `:160-161` | same |
| `MissionsView.swift:41` | `store.dailyMissions(now: now)` | `refreshDailyMissions` → `mutate` |
| `MissionsView.swift:43` | `store.weeklyMissions(now: now)` | `refreshWeeklyMissions` → `mutate` |
| `MenuView.swift:345` | `ProfileStore.shared.unclaimedCount(now: context.date)` → `ProfileStore.swift:594-596` | both refreshes + `dailyMissions`/`weeklyMissions` again |

All five sit inside a `TimelineView(.periodic(… by: 60))` (`MissionsView.swift:35`,
`MenuView.swift:334`), so the body re-evaluates every 60 s — meaning the mutation fires on the exact
tick a UTC rollover lands, while the view is on screen. This is the CLAUDE.md iron-rule-5 family
that has already shipped three bugs. `02_STATE.md:279` records it as a known ⚠ on the feature grid.

---

## 4. What already exists that the owner may not have seen

### 4.1 The full surface inventory — and where missions are absent

**Present:**
- **Board summary strip** (`MissionsView.swift:69-107`) — a genuine three-state model, not a bool:
  `claimable(count, coins)` / `open(count, coins)` / `allClear`, defined purely in the Linux-testable
  layer at `ProfileStore.swift:518-539`. Copy: `"3 CLAIMABLE · 1,240 COINS WAITING"` /
  `"7 OPEN · UP TO 700 COINS"` / `"ALL CLEAR · NEW BOARD IN 3H 12M"`. Gold **only** when money is
  waiting (`:82-87`), with the coin glyph gated to the same state (`:308-309`).
- **Progress rings** — one per card, animated 0→fraction on appear, static under Reduce Motion
  (`MissionsView.swift:404-422`), gold once claimable, metric glyph in the centre (`:514-529`).
- **Achievement tier ladder pips** — paid tiers gold, current tier wide + tinted, plus a `T2` label
  (`MissionsView.swift:425-439`).
- **Section identity** — TODAY has a live gold timer ring draining to UTC midnight
  (`:193-215`); THIS WEEK has seven purple day-dots with today ringed white (`:218-243`);
  CHALLENGES is cyan; ACHIEVEMENTS is green (`:26-28`).
- **CLAIM ALL cascade** with per-landing haptics and an 80 ms beat (§3.2).
- **Coin fly-up** on a landed claim, deliberately hoisted outside the card so it survives the
  active→receipt swap (`:358-363`, with the reasoning at `:355-357`).
- **Receipt collapse** — an exhausted mission becomes a slim struck-through row (`:489-510`).
- **Full VoiceOver labelling** on every element (`:90`, `:154`, `:214`, `:242`, `:399`, `:509`).
- **Hub badge** — `MenuView.swift:340-347` `navItem("target", "Missions", tint: 0xB26BFF, count:
  ProfileStore.shared.unclaimedCount(now: context.date), identifier: "railMissions")`.
- **Profile milestone card** — under 5 runs, Profile shows `"\(runs) OF 5 RUNS · MISSIONS ARE LIVE
  NOW ›"` which deep-links to the board (`ProfileView.swift:183-207`).

**The "3" badge is fed by `ProfileStore.unclaimedCount(now:)` (`ProfileStore.swift:593-599`)** — the
count of *claimable* entries across all four sections (perRun + today's 3 daily + this week's 3
weekly + achievements). It is a bare count: a 50-coin `ach.gems` tier 1 and a 900-coin `wk.close75`
are both worth "1". Pinned by `MissionsTests.swift:179-187` and `ProgressionTests.swift:321-327`.

**Absent — and this is the mechanical root of "does nothing":**

`GameView.swift` never calls `missionState`, `unclaimedCount`, `dailyMissions`, `weeklyMissions`, or
`MissionBoardSummary`. Verified by
`grep -rn "unclaimedCount\|missionState\|dailyMissions(\|weeklyMissions(\|MissionBoardSummary" PrismRush/UI/GameView.swift`
→ **NOT FOUND** (zero hits). Consequences:

- Completing a mission mid-run produces **no** toast, no FX, no sound, no HUD change.
- The **death panel says nothing** about missions. A player who just finished "Travel 2,000 m in one
  run" for 200 coins learns about it only if they later tap a purple icon on the hub.
- There is no post-run "2 missions advanced" line, no near-miss line ("you were 12 gems short"),
  and no "claim your 340 coins" call to action anywhere on the death path.
- Missions have **exactly two entry points in the whole app**: the hub nav-rail cell and the
  under-5-runs Profile card. `grep -rn "\.missions" PrismRush/UI/` → `GameView.swift:309` (a test
  env hook `PR_SCREEN=missions`), `:1236` (the sheet case), `:1436` (`onMissions:`),
  `ProfileView.swift:185`.
- `ClaimRibbon.swift:5-7` records the design intent explicitly: *"Missions is a BOARD YOU VISIT"* —
  a nav exit with a count badge. That decision is exactly what "does nothing" describes.

**Not present at all:** mission streaks (there is a `loginStreak`, `Profile.swift:59`, but it belongs
to the daily login bonus — grep for any mission streak returns nothing), set/collection completion
bonuses, a weekly "complete all 3" capstone, mission rerolls, mission difficulty choice, non-coin
rewards of any kind.

### 4.2 The economy — "not rewarding" is arithmetic, not vibes

Costed against `s016_coins-economy.md` (do not re-derive; these are its numbers re-checked at HEAD):

| fact | number | cite |
|---|---|---|
| mean daily mission | **115 coins** | `MissionCatalog.swift:100-109` |
| free chest, no play required, **no daily cap** | mean **140 coins** every 30 min | `ProfileStore.swift:297`, `:339-348`; audit `:72` |
| play itself | **58–111 coins/min** (bot floor) | audit `:50-60` |
| all 3 daily missions | 345/day of a **1,943/day** meta faucet = **17.8%** | audit `:73`, `:88-89` |
| every per-run mission ever | 970 | audit `:76` |
| every achievement tier ever | 11,350 | audit `:77` |
| **every mission + achievement in the game, forever** | **12,320** | sum of the two above |
| the world ladder alone | **59,400** (71.1% of an 83,500 catalogue) | audit `:26` |

The three sentences that make the complaint concrete:

1. **One free chest tap (mean 140) pays more than the mean daily mission (115)** — and the chest
   requires no play, no skill, and can be opened 48× a day.
2. **`day.dist3k` pays 120 coins for 3,000 m. The run that covers 3,300 m pays 179 coins on its
   own** (audit `:53`). The mission is worth less than the activity it asks for.
3. **Completing every mission and every achievement tier that will ever exist yields 12,320 coins —
   20.7% of the world ladder, 14.8% of the catalogue.** You cannot buy one deep world with the
   entire lifetime mission economy.

And the reward is **coins only** (`ProfileStore.swift:586-587`). The one non-coin consequence
missions have is indirect and broken: three characters are gated on *claimed* achievement tiers —
`drift` ← `ach.dist` T1 (`SkinCatalog.swift:168`), `facet` ← `ach.gems` T2 (`:174`), `midas` ←
`ach.close` T1 (`:211`) — via `SkinUnlocks.swift:12`
(`case .achievement(let id, let tier): return (profile.achievementTier[id] ?? 0) >= tier`), while
the Characters screen draws its progress bar from raw `missionProgress` (`CharacterSelectView.swift:187-193`).
That is backlog **PR-0318**, OPEN, and still real at HEAD: the bar reads 100% and the character
stays locked with nothing on screen saying "claim the mission".

### 4.3 Comprehension load

One screen, one flat `VStack` (`MissionsView.swift:38-49`), **19 cards**: 6 per-run + 3 daily +
3 weekly + 7 achievements. On that one screen a player must simultaneously understand:

- two different reset clocks (UTC midnight vs UTC week, `:207` / `:235`) — and a **third**
  elsewhere in the app, because the daily *login* bonus rolls at **local** midnight
  (`ProfileStore.swift:301`, `Calendar.current`) while missions roll at **UTC**
  (`:353-357`). Backlog **PR-0174**;
- two different progress semantics — `day.streak18` is a max and `day.gems150` is a sum, rendered
  identically (`MissionCatalog.swift:43-48` vs the identical `MissionCard` at `:369-400`);
- a `T2` pip ladder whose meaning is never stated;
- `compactCount` rendering `2.0k/20k` (`:539-543`) beside `0/5`;
- four colour identities that carry no legend.

Nothing on the screen explains any of it. The section subtitles are the whole tutorial:
`"· ONE-RUN FEATS"` (`:254`) and `"· EVERY TIER PAYS"` (`:272`).

---

## 5. Findings

### 5.1 Structural / product (P-series — mine, this pass)

**P1 · Missions have no in-run or post-run presence at all.** §4.1. Root cause of "does nothing".
`GameView.swift` has zero mission reads (grep NOT FOUND above). Fix belongs on the death panel and
in a completion FX, not on the board.

**P2 · The reward curve loses to the idle faucet.** §4.2. The chest out-pays the mean daily mission
for zero play. Any "prettier board" that does not move these numbers will not answer the complaint.

**P3 · An unclaimed complete mission is destroyed at reset with zero warning.**
`ProfileStore.swift:385-396`, `:408-420`. Nothing on the board says "expires in 3H 12M — claim
first"; the countdown reads `RESETS 3H 12M`, which is framed as *renewal*, not *loss*. A player who
finishes a weekly on Sunday and opens the app on Monday sees an empty board and no receipt.

**P4 · 9 of the 15 pool entries accumulate progress every run that can never be claimed.**
`applyRunSummary` bumps the **whole** `dailyPool` (8) and `weeklyPool` (7)
(`ProfileStore.swift:465-470`), while `claimMission` only pays the 3 drawn slots
(`:567-576`). So 5 daily + 4 weekly missions silently bank progress into `missionProgress` that is
wiped at the next reset without ever being claimable or visible. Pinned as intended behaviour by
`ProgressionTests.swift:289-293`. Not a bug today; it is a **latent design asset** — that hidden
progress is exactly the material a "carry-over" or "your best 3" board would need.

**P5 · The badge is a bare count with no value information.** `ProfileStore.swift:593-599`. "3" could
be 150 coins or 2,600.

**P6 · One flat 19-card scroll with no hierarchy, no filter, and no "what's closest".** §4.3. The
board never tells the player which mission they are nearest to finishing.

### 5.2 New defects found by this pass (N-series — NOT in the backlog)

**N1 · A cloud merge can resurrect a claim onto a freshly-rolled board.** *Derived from code, not
executed.*
`merged()` unions the claim ledger and max-merges progress —
```swift
// ProfileStore.swift:711-712
merged.missionProgress.merge(remote.missionProgress) { mine, theirs in max(mine, theirs) }
merged.claimedMissions.formUnion(remote.claimedMissions)
```
— but it **never merges `dailyMissionDate` or `weeklyMissionDate`** (verified: neither identifier
appears anywhere in `merged`, `ProfileStore.swift:692-726`; the docstring at `:676-678` says
`weeklyMissionDate` is "deliberately NOT merged" and does not mention the daily one at all).
Failure scenario: device A claims `day.gems150` on day N and goes offline. Device B rolls over to
day N+1, wiping the id from both maps. A's stale blob then arrives via
`didChangeExternallyNotification` (`:38-43` → `mergeFromCloud`, `:729-735`); the union re-inserts
`day.gems150` into `claimedMissions` and the max-merge re-imports its completed progress. If
`day.gems150` is in day N+1's slots, B's board shows it as a struck-through receipt row
(`MissionsView.swift:348-352`) and `claimMission` returns `nil` forever for that day. Because
`dailyMissionDate` on B is already N+1, `refreshDailyMissions` will not re-wipe it until N+2.
**No test covers merge × rollover** — `ProfileStoreMergeTests`-style coverage exists for coins and
skins but grep for `claimedMissions` in `Tests/` returns only rollover assertions, never a merge.

**N2 · CLAIM ALL pays exactly one tier per achievement ladder, and nothing says so.**
`MissionsView.swift:118-137`. `claimables` (`:164-166`) contains each `Mission` once, so a ladder
whose progress covers tiers 1 **and** 2 is claimed once by the cascade and re-arms afterwards. The
advertised `CLAIM ALL +\(total)` (`:140`) is therefore *accurate for that press* but understates
what is owed, and the player must notice the re-armed CLAIM button themselves. The XCUITest actually
depends on this behaviour (`UITests/InteractionUITests.swift:280-288` — "exactly one claimable
re-arms after the sweep"), so it is load-bearing, not accidental. Whether it is *desirable* is a
product call for this session.

**N3 · The single-claim path uses a live `Date()` while CLAIM ALL uses the rendered `now`.**
`MissionsView.swift:478` (`claimMission(mission.id, now: Date())`) vs `:132`
(`store.claimMission(mission.id, now: now)`). The CLAIM ALL choice is documented as a deliberate
fix at `:124-129` ("a live `Date()` per claim let a UTC-midnight rollover mid-cascade refresh the
boards and nil the remaining daily claims"). The single-claim path has the same hazard and did not
get the same fix: the board is rendered from a per-minute `TimelineView` tick, so it can be up to
60 s stale; tapping CLAIM in that window across UTC midnight refreshes the board inside
`claimMission` and returns `nil` — **the tap silently does nothing**, with no toast and no
explanation (decree 3).

**N4 · `unclaimedCount` and `dailyMissions`/`weeklyMissions` are query-shaped names that write to
disk and iCloud.** §3.3. This is the mechanism behind PR-0006, but note the naming is the trap: no
call site can tell from the signature that a read persists. Any rebuild should split
`board(now:)` (pure) from `refresh(now:)` (explicit, `.task`-driven).

### 5.3 Known filed defects — status against today's code

| ID | Sev | Item | Filed status | Real at HEAD? |
|---|---|---|---|---|
| **PR-0304** | SEV2 | "ALL CLEAR" on a 0/N board at first launch | **DONE(S-007)** (`03_BACKLOG.md:1021-1032`) | **Fixed.** `MissionBoardSummary` is a pure three-way (`ProfileStore.swift:518-539`), 4 tests (`MissionsTests.swift:279-308`). The paired countdown-unit fix also landed (`MissionsView.swift:285-289` emits `3H 12M`, `:297-300` emits `3D`). |
| **PR-0006** | SEV1 | Reading the board mutates + saves the profile from inside `body` | OPEN (`:103-113`) | **YES, and worse than filed.** Filed against `MenuView` only; §3.3 lists 4 more sites inside `MissionsView.body`. Cited line `ProfileStore.swift:558` is stale — the path is now `:593-599`. |
| **PR-0307** | SEV2 | Post-revive play invisible to missions/achievements/XP | OPEN (`:1059-1070`) | **YES.** `GameView.swift:979-990` (the `statsRecorded` branch) pays coins and stats only; the trade-off is written into the comment at `:996-998`. |
| **PR-0255** | SEV2 | Same defect from the run-lifecycle side; also the root cause of PR-0176 | OPEN (`:775-785`) | **YES.** Same citation. D-007 (`:764`) already ruled that revived runs **should** count for missions and XP — so this is decided-but-unimplemented, not undecided. |
| **PR-0318** | SEV2 | Achievement-gated characters need a CLAIM tap the copy never mentions | OPEN (`:1176-1186`) | **YES.** `SkinUnlocks.swift:12` gates on `achievementTier` (claimed) while `CharacterSelectView.swift:187-193` draws the bar from `missionProgress` (earned). Affects `drift`, `facet`, `midas`. |
| **PR-0176** | SEV4 | `Metric.revives` structurally unsatisfiable | OPEN, re-scored SEV3→SEV4 (`:659`, `:1203`) | **YES**, and still harmless — no mission uses the metric (§1.5). Delete the case or wire it. |
| **PR-0172** | SEV3-table | per-run mission loop has no `v > 0` guard, writes permanent zero entries on the first run | OPEN (`:655`) | **YES.** `ProfileStore.swift:460-464` vs the guarded `bump` at `:481-489`. Cited lines `:455-459`/`:476-484` are stale by ~5. Cosmetic bloat in the save blob; also makes `missionProgress` a poor "has this player ever…" oracle. |
| **PR-0174** | SEV3-table | daily *bonus* rolls at local midnight; daily *missions* + challenge roll at UTC | OPEN (`:657`) | **YES.** `ProfileStore.swift:301`/`:307-309` (`Calendar.current`) vs `:353-357` (UTC). Up to 13 h apart. Directly feeds "not easy to understand". |
| **PR-0035** | SEV2 | forward clock farms the timed faucets | OPEN (`:355-364`) | Touches missions indirectly — `refreshDailyMissions`' `min(last, now)` (`:387`) defends backwards only. Note `state.md:475` and this item disagree about which direction is the accepted trade-off; resolve before quoting either. |
| **PR-0036** | SEV2 | five lifetime stats + `loginStreak` silently not merged | OPEN (`:367-376`) | **YES**, and it is the sibling of **N1** — `merged()` starts from `local` (`:693`) and touches only what it names. |

Backlog items I searched for and did **NOT** find: any item about the missions reward *curve*, about
mission visibility on the death panel, about board comprehension, or about mission progress lost at
reset. Grep: `grep -n -i "mission" docs/agent/03_BACKLOG.md` → 40 hits, all accounted for above or
about the daily-challenge seed goldens. **The four things the owner is actually complaining about
have never been filed.**

---

## 6. Test coverage

### 6.1 What is tested (all Linux-testable — `Package.swift:14-25` compiles `Core/`, 7 `Meta/` files
including `MissionCatalog.swift` + `ProfileStore.swift`, and `Audio/Synth.swift`)

**`Tests/CoreTests/MissionsTests.swift` — 22 tests:**
determinism + distinctness + scope-purity of daily slots (`:42-53`); rotation across a week
(`:55-60`); daily rollover wipes progress *and* claims (`:62-78`); daily sums across runs
(`:80-90`); per-run is best-single-run not sum (`:93-104`); max semantics for `.multiplierHit`
(`:106-114`); claim-once + no reset for per-run (`:116-126`); incomplete claim pays nothing +
unknown ids inert (`:128-137`); tiered ladders claim in order and exhaust (`:139-158`); lifetime
metrics never reset (`:160-166`); chest opens feed both chest missions (`:168-177`); badge count
tracks claimables (`:179-187`); daily-challenge seed goldens from the meta side (`:191-205`,
layoutVersion 12); challenge best/day rollover (`:207-229`); `secondsUntilUTCMidnight` (`:231-235`);
**schema resilience** — legacy JSON decodes with mission defaults + full round-trip (`:238-269`);
and the 4 `MissionBoardSummary` tests that pin PR-0304 (`:279-308`).

**`Tests/CoreTests/ProgressionTests.swift` — 4 weekly tests:**
weekly slot determinism + rotation + **stream isolation from the daily board** (`:250-272`); weekly
rollover wipes progress and claims **and** the off-board slot gate (`:274-304`); weekly clock-rollback
blocked (`:306-318`); `unclaimedCount` includes weekly (`:320-327`).

**Elsewhere:** `EconomyTests.swift:163-165` pins `ach.worlds` as reach-based, not purchase-based.
`SkinCatalogTests.swift:78` validates every `.achievement` unlock resolves to a real tiered mission.

**One XCUITest:** `UITests/InteractionUITests.swift:257-289`
(`testMissionsClaimAllCascadeAndSingleClaim`) — opens the board from `railMissions`, waits on
`missionsSummary`, taps `claimAllButton`, asserts `claim_ach.gems` and `claim_ach.slick` retire and
that CLAIM ALL disappears below 2, then does the single-claim leg on `claim_ach.chests`. It depends
on the demo profile seeded at `GameView.swift:196-210`. Accessibility ids available for driving:
`missionsSummary` (`MissionsView.swift:89`), `claimAllButton` (`:153`), `missionCard_<id>` (`:364`),
`claim_<id>` (`:457`), `railMissions` (`MenuView.swift:346`).

### 6.2 What is structurally untestable

`swift test` compiles **none** of `UI/` (`Package.swift:14-25` — no `UI` entry). So all 576 lines of
`MissionsView.swift` have **zero** unit coverage; the only automated check on that file is the single
XCUITest above, which runs on a Mac simulator. Specifically untestable on Linux and untested on Mac:

- the summary strip's **actual copy** for a real board (the four `MissionBoardSummary` tests feed
  hand-built `MissionState` arrays, `MissionsTests.swift:274-277` — **no test ever builds the real
  19-card board from a real `Profile` and asserts what it says**);
- ring fractions, tier-pip rendering, `compactCount` formatting (`:539-543`);
- the CLAIM ALL cascade's ordering, its 80 ms beat, and the "one tier per ladder" behaviour (**N2**);
- the `Date()`-vs-`now` divergence (**N3**);
- the body-mutation hazard (**N4** / PR-0006) — nothing anywhere asserts that a `body`-reachable
  store call is pure.

### 6.3 Coverage gaps that are *not* structural (i.e. fixable in `swift test` today)

1. **No merge × rollover test.** `merged()` (`ProfileStore.swift:692-726`) is never exercised
   against `claimedMissions`/`missionProgress` with divergent board dates — **N1** would be caught by
   one test.
2. **No reward-value pins.** Nothing asserts any mission's `rewardCoins` or any ladder's totals. An
   economy edit is a silent change today. Given that this session is going to *rewrite* the curve,
   a golden table test is the cheap insurance.
3. **No daily off-board gate test.** The weekly one exists (`ProgressionTests.swift:289-293`); the
   daily equivalent of "a pool mission outside today's slots can never be claimed" does not.
4. **No `bump(_:metric:by:)` breadth test** beyond chests — the helper bumps *every* catalogue
   entry with a matching metric (`ProfileStore.swift:492-498`), which is a live foot-gun for any new
   non-run metric.
5. **No PR-0172 regression test** (zero-valued keys after the first run).
6. **No "every mission is reachable" catalogue test** — nothing asserts that each `Metric`'s target
   is achievable given `Tuning` (e.g. `run.mult5`'s target 5 == `Tuning.multCap` 5 is a
   coincidence nothing protects), and nothing asserts that every declared `Metric` case is used by
   at least one mission (which would have caught `.revives`).

---

## 7. Constraints the rebuild inherits

- **No `layoutVersion` exposure.** Neither mission RNG stream feeds `startRun(seed:)`
  (`MissionCatalog.swift:163-164`, verified — `SplitMix64` is used with dedicated domain tags and
  the result is never handed to the spawner). Adding, removing or reordering missions therefore does
  **not** bump `DailyChallenge.layoutVersion` and does **not** need the solvability bot. **Changing
  the size of a pool DOES change every future board** (the draw is `rng.int(0, pool.count - 1)` over
  a shrinking array, `:157`), so the daily/weekly slot goldens in
  `MissionsTests.testDailySlotsAreDeterministicPerDay` and
  `ProgressionTests.testWeeklySlotsDeterministic` are order- and count-sensitive.
- **`Profile` schema:** every new field needs `decodeIfPresent ?? default` in `init(from:)`
  (`Profile.swift:134-183`) **and** a `CodingKeys` entry (`:117-132`) **and** a merge rule in
  `merged()` (`ProfileStore.swift:692-726`) — the third is the one that gets forgotten (PR-0036,
  N1).
- **Iron rule 5 (G3):** `MissionsView` already reads `ProfileStore.shared` directly in `body`
  (`:31`) — correct. Do not snapshot it. But the *reads themselves must become pure* (§3.3).
- **Decree 5:** any countdown on this board must be real and enforced in code. The existing UTC
  reset is real; a "claim before it expires" framing (P3) would be honest, and a manufactured
  urgency would not.
- **Decree 4:** the badge, the summary strip and every card must lead somewhere. Today the summary
  strip is inert text and the receipt rows are dead.
- **D-046:** binary assets are now allowed, so a mission board is no longer restricted to SF Symbols
  + procedural rings.
