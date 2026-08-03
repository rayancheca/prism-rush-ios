# S-017 · missions-seam — the implementation brief

**Scope.** Where the missions feature actually lives, every file:line that participates, what a
rebuild is allowed to touch, and what breaks when it does. Read-only pass at `ba9655d`. Nothing in
the repo was edited except this file. No build, no simctl.

**Verification convention.** Every claim below carries a `file:line`. Claims I could not verify by
reading code (anything that needs a running app or Instruments) are labelled **UNVERIFIED** with the
exact experiment that would settle them.

---

## 0 · The four defects, mapped to code

The owner's four complaints do not share a fix. Here is where each one actually lives, so pass 017
does not spend its budget on the one that is loudest.

| complaint | where it lives | is it a UI problem? |
|---|---|---|
| **"ugly"** | `UI/MissionsView.swift` (577 L) — 4 bespoke section tints at `:25-28`, 17 SF-Symbol call sites, 6 raw hex literals (`s016_design-system.md:133`, `:215`) | **yes**, and only this one |
| **"does nothing"** | `Meta/MissionCatalog.swift` — every reward in the file is `rewardCoins: Int`. There is no other payout type in the data model. Plus the claim→character coupling in §6.1 below | **no** — data model + economy |
| **"not easy to understand"** | The three-scope/four-section split (`MissionsView.swift:41-48`), the invisible 8-entry daily pool of which only 3 are ever claimable (`ProfileStore.swift:568-570`), and §6.1 | **half** |
| **"not rewarding at all"** | `MissionCatalog.swift:100-140` reward literals, costed against `s016_coins-economy.md:§1.2/§1.5` | **no** — pure economy |

**The economy number, so pass 017 does not re-derive it.** Missions contribute
`345 (3 daily) + 318 (weekly amortised) = 663 coins/day` out of a `1,943 coins/day` meta faucet
(`s016_coins-economy.md:§1.2`), against a total income of 3,118–6,641 coins/day depending on play
time (`§1.5`). **Missions are 10–21 % of a player's income.** The one-time side is
`970 (per-run) + 11,350 (achievements) = 12,320` of a 14,720 one-time meta total — i.e. the
achievement ladders *are* the one-time meta faucet, and they pay out over months.

So "not rewarding" is arithmetically true and **cannot be fixed by raising the coin numbers**: the
sink is finite at 83,500 and the whole catalogue is free in 13–27 days already (`§1.5`). Raising
mission coin payouts makes that worse. The fix has to be a *different kind of reward*, which is a
`Mission` schema change, not a `MissionsView` change. See §7.

---

## 1 · Architecture, end to end

```
                            ┌─────────────────────────────────────────────┐
   RUN (Core/, deterministic)│  GameCore.tick → emit(FXEvent)              │
                            └───────────────────┬─────────────────────────┘
                                                │ FXEvent (one-shot, event-driven)
                                                ▼
   ┌──────────────────────────────────────────────────────────────────────────────┐
   │ GameModel.handleFX  (UI/GameView.swift:635-830)                              │
   │   nearMissesThisRun/closesThisRun/slicksThisRun/slidesThisRun/wardens…       │
   │   ALL @ObservationIgnored (GameView.swift:98-105) → do NOT invalidate SwiftUI│
   │   reset in startRun (GameView.swift:503-506)                                 │
   └───────────────────────────────┬──────────────────────────────────────────────┘
                                   │ on FIRST death only, behind `statsRecorded` (GameView.swift:991)
                                   ▼
   ┌──────────────────────────────────────────────────────────────────────────────┐
   │ RunSummary  (Meta/MissionCatalog.swift:6-24)  — pure value type, Linux-safe  │
   │ built at GameView.swift:999-1014, handed over at GameView.swift:1016         │
   └───────────────────────────────┬──────────────────────────────────────────────┘
                                   ▼
   ┌──────────────────────────────────────────────────────────────────────────────┐
   │ ProfileStore.applyRunSummary  (Meta/ProfileStore.swift:426-479)              │
   │   :428-429 refreshDaily/WeeklyMissions   (rollover wipe)                     │
   │   :460-464 perRun      → missionProgress[id] = max(old, v)                   │
   │   :465-473 daily/weekly/achievements → bump() (:481-489, sum or max)         │
   │  ── second, non-run writer ──                                                │
   │ ProfileStore.openFreeChest (:339-348) → bump(metric:.chestsOpened, by: 1)    │
   │   via the flat-amount overload (:492-498)                                    │
   └───────────────────────────────┬──────────────────────────────────────────────┘
                                   ▼
   ┌──────────────────────────────────────────────────────────────────────────────┐
   │ Profile  (Meta/Profile.swift:62-67)  — 5 stored fields, all Codable          │
   │   missionProgress / claimedMissions / achievementTier                        │
   │   dailyMissionDate / weeklyMissionDate                                       │
   │   persisted: ProfileStore.mutate (:88-91) → save() (:655-662)                │
   │              JSONEncoder + UserDefaults + NSUbiquitousKeyValueStore.sync     │
   └───────────────────────────────┬──────────────────────────────────────────────┘
                                   ▼
   ┌──────────────────────────────────────────────────────────────────────────────┐
   │ READ MODEL  ProfileStore.missionState (:541-558) → MissionState (:501-509)   │
   │             MissionBoardSummary.of  (:518-539)   — pure, unit-tested         │
   │             unclaimedCount          (:593-599)   — the hub badge             │
   └───────────────────────────────┬──────────────────────────────────────────────┘
                                   ▼
   ┌──────────────────────────────────────────────────────────────────────────────┐
   │ UI/MissionsView.swift  (577 L)  — 4 sections, ring cards, CLAIM / CLAIM ALL  │
   │ UI/MenuView.swift:343-346         — hub rail badge                           │
   │ UI/CharacterSelectView.swift:186-193, :293 — achievement ladders as unlocks  │
   │ UI/ProfileView.swift:183-207      — "Next Milestone" card → Missions         │
   └───────────────────────────────┬──────────────────────────────────────────────┘
                                   ▼
   ┌──────────────────────────────────────────────────────────────────────────────┐
   │ CLAIM  MissionCard.claim (MissionsView.swift:476-484) ─┐                     │
   │        CLAIM ALL cascade (MissionsView.swift:126-137) ─┴→ claimMission       │
   │ ProfileStore.claimMission (:562-590)                                         │
   │   :564-565 refresh both boards   :567-576 slot-membership gate               │
   │   :579-588 mutate { claimedMissions.insert | achievementTier[id] = tier+1 ;  │
   │                     coins += reward ; totalCoinsEarned += reward }           │
   └───────────────────────────────┬──────────────────────────────────────────────┘
                                   ▼
   ┌──────────────────────────────────────────────────────────────────────────────┐
   │ CONSEQUENCE (the whole of it)                                                │
   │   1. coins += reward                            ← the only universal payout  │
   │   2. achievementTier[id] += 1                                                │
   │        → SkinUnlocks.earned (SkinUnlocks.swift:12) reads achievementTier      │
   │        → ProfileStore.refreshSkinUnlocks, fired on GameModel.closeSheet       │
   │          (GameView.swift:887-889) → grants 3 of 24 characters                 │
   │   NOTHING ELSE. No XP, no boxes, no charges, no world unlock, no title.       │
   └──────────────────────────────────────────────────────────────────────────────┘
```

### 1.1 Every participating file:line

| file:line | role | Linux-compiled? |
|---|---|---|
| `PrismRush/Meta/MissionCatalog.swift:6-24` | `RunSummary` — the 13-field run→meta payload | **yes** (`Package.swift:20`) |
| `…:33-84` | `Mission` (id/title/metric/target/rewardCoins/scope), `Metric` (12 cases), `Scope` (4) | yes |
| `…:43-48` | `Metric.accumulatesByMax` — max vs sum semantics | yes |
| `…:51-66` | `Metric.value(in: RunSummary)` — the ONLY summary→metric map | yes |
| `…:90-97` | 6 per-run missions, 970 coins lifetime | yes |
| `…:100-109` | 8-entry daily pool; **only 3 are on the board any given day** | yes |
| `…:114-122` | 7-entry weekly pool; only 3 on the board | yes |
| `…:125-140` | 7 achievement ladders, 18 tiers, 11,350 coins | yes |
| `…:142-144` | `mission(_ id:)` — linear scan over the concatenation of all four lists | yes |
| `…:148,:152-160` | `dailyTag` + `dailySlots(daysSinceEpoch:)` — SplitMix64, meta-domain | yes |
| `…:165,:168-176` | `weeklyTag` + `weeklySlots(weeksSinceEpoch:)` | yes |
| `PrismRush/Meta/Profile.swift:62-67` | the 5 stored mission fields | **yes** |
| `…:124,:129` | `CodingKeys` entries for those fields | yes |
| `…:157-160,:176` | `init(from:)` `decodeIfPresent ?? default` lines | yes |
| `PrismRush/Meta/ProfileStore.swift:74,:76` | `sanitized` clamps future-dated board dates | **yes** |
| `…:88-91` | `mutate` — the single write door; **calls `save()` synchronously** | yes |
| `…:339-348` | `openFreeChest` — the one non-run mission writer | yes |
| `…:359-373` | `daysSinceEpoch` / `utcDayKey` / `secondsUntilUTCMidnight` | yes |
| `…:377-380`, `:385-396` | `dailyMissions` / `refreshDailyMissions` (**mutates**) | yes |
| `…:400-403`, `:408-420` | `weeklyMissions` / `refreshWeeklyMissions` (**mutates**) | yes |
| `…:426-479` | `applyRunSummary` — XP, level grant, world bests, all 4 mission feeds | yes |
| `…:481-489` | `bump(_:id:metric:in:)` — per-run summary bump | yes |
| `…:492-498` | `bump(_:metric:by:)` — flat bump (chests) | yes |
| `…:501-509` | `MissionState` — the view's whole input (**not `Equatable`**) | yes |
| `…:518-539` | `MissionBoardSummary` — pure 3-way, the PR-0304 fix | yes |
| `…:541-558` | `missionState(_:now:)` | yes |
| `…:562-590` | `claimMission(_:now:)` | yes |
| `…:593-599` | `unclaimedCount(now:)` — hub badge | yes |
| `…:711-712` | cloud merge: `missionProgress` per-key max, `claimedMissions` union | yes |
| `PrismRush/Meta/SkinUnlocks.swift:12` | `.achievement(id, tier)` → `achievementTier[id] >= tier` | yes |
| `PrismRush/UI/MissionsView.swift:1-577` | the entire screen | **NO** |
| `PrismRush/UI/MenuView.swift:331-347` | rail badge, 60 s `TimelineView`, `unclaimedCount` at `:345` | no |
| `PrismRush/UI/CharacterSelectView.swift:186-193` | ladder progress bar for locked skins | no |
| `PrismRush/UI/CharacterSelectView.swift:293` | locked-tap → Missions | no |
| `PrismRush/UI/ProfileView.swift:183-207` | "Next Milestone" card → Missions | no |
| `PrismRush/UI/GameView.swift:98-105` | the 6 per-run FX counters | no |
| `…:503-506` | counter reset in `startRun` | no |
| `…:635-830` | `handleFX` — the increment sites (`:645,:648,:651,:718,:808`) | no |
| `…:991-1016` | `statsRecorded` gate, `RunSummary` build, `applyRunSummary` call | no |
| `…:887-889` | `closeSheet` → `checkSkinUnlocks` (claim → character grant) | no |
| `…:196-212` | `PR_UITEST` seeds of `missionProgress`/`achievementTier` | no |
| `Tests/CoreTests/MissionsTests.swift` (307 L) | the meta-layer suite | yes |
| `Tests/CoreTests/ProgressionTests.swift:250-330` | weekly board suite | yes |
| `Tests/CoreTests/SkinCatalogTests.swift:74-80` | achievement-unlock reachability | yes |
| `Tests/CoreTests/EconomyTests.swift:162-164,:204,:353-358` | mission/economy crossovers | yes |
| `UITests/InteractionUITests.swift:257-280` | the one XCUITest — CLAIM ALL + single claim | no |

---

## 2 · Where progress is advanced from — every call site

**Answer: two writers, both in `ProfileStore` (Meta/), neither in `GameCore`. No mission condition
reads game state per frame.** That is the good news and it is worth not breaking.

### 2.1 The complete writer census

`grep -rn "missionProgress\|achievementTier" PrismRush --include='*.swift'` — writes only:

| # | site | trigger | cadence |
|---|---|---|---|
| 1 | `ProfileStore.swift:463` (perRun, max) | `applyRunSummary` | **once per run** |
| 2 | `ProfileStore.swift:466,:469,:472` → `bump` `:485/:487` | `applyRunSummary` | once per run |
| 3 | `ProfileStore.swift:496` (flat) | `openFreeChest` (`:345`) | once per chest |
| 4 | `ProfileStore.swift:584` `achievementTier[id] = tier + 1` | `claimMission` | once per claim tap |
| 5 | `ProfileStore.swift:392,:416` `removeValue` | `refreshDaily/WeeklyMissions` | once per UTC rollover — **but see §2.3** |
| 6 | `ProfileStore.swift:711` per-key max | iCloud merge | on external KVS change |
| 7 | `GameView.swift:199-205` | `PR_UITEST=1` only | launch |

`Core/` never writes any of them — `grep -rn "missionProgress" PrismRush/Core` → **NOT FOUND**.
`GameCore` mentions missions only in comments (`GameCore.swift:135,:160,:453,:626,:1054`). **Iron
rule 1 holds and nothing in a mission rebuild should be allowed to change that.**

### 2.2 Per-frame exposure: the run side is clean

The six per-run counters (`GameView.swift:98-105`) are all `@ObservationIgnored`, and they are
incremented from `handleFX` — i.e. **once per FXEvent, not once per frame**
(`:645` nearMiss, `:648` close, `:651` slick, `:718` warden, `:808` slide). Because they are
`@ObservationIgnored`, incrementing them cannot invalidate a SwiftUI view. **This is the pattern any
new mission metric must copy.** A new metric that stores its counter on an observed property would
reintroduce D-051 in the worst possible place — inside the run loop.

`Mission.Metric.value(in:)` (`MissionCatalog.swift:51-66`) runs ~28 times total per run
(`applyRunSummary` iterates 6 + 8 + 7 + 7 = 28 catalog entries) — negligible, once per death.

### 2.3 Per-frame exposure: **the hub side is NOT clean — this is the D-051 sibling**

`refreshDailyMissions` (`ProfileStore.swift:385-396`) and `refreshWeeklyMissions` (`:408-420`) are
**mutating** functions. They call `mutate` (`:389`, `:413`), which calls `save()` (`:90`), which does
`JSONEncoder().encode` + `UserDefaults.set` + `cloud.set` + `cloud.synchronize()` (`:656-661`),
synchronously, on the main actor.

They are reached from inside SwiftUI `body` at four places:

| site | path | note |
|---|---|---|
| `MissionsView.swift:37` `claimableMissions` | `:165` → `activeMissions` `:160-161` → `dailyMissions` + `weeklyMissions` | in `body` |
| `MissionsView.swift:39` `summaryStrip` | `:70` → `activeStates` `:110-111` → `activeMissions` | in `body` |
| `MissionsView.swift:41` | `store.dailyMissions(now: now)` directly | in `body` |
| `MissionsView.swift:43` | `store.weeklyMissions(now: now)` directly | in `body` |
| **`MenuView.swift:345`** | `ProfileStore.shared.unclaimedCount(now:)` → `:594-597` refreshes **both** boards, then calls `dailyMissions`/`weeklyMissions` which refresh **again** | in `body`, **on the hub** |

Counted per `MissionsView` body pass: **4 × `refreshDailyMissions` + 4 × `refreshWeeklyMissions`**.
After the first call in a given UTC day the guard at `:387` / `:410-411` early-returns, so only the
first one writes — but that first one performs a full profile encode + UserDefaults write + iCloud
sync **during a view body evaluation**, which is a state mutation during view update.

Two distinct problems, ranked:

- **(a) SEV2 — mutation during `body`.** At a UTC-midnight rollover, or on the very first launch
  (`dailyMissionDate == nil`, `Profile.swift:66`), rendering the hub or the Missions board *writes
  and persists the profile*. `profile` is the observed property of an `@Observable`
  (`ProfileStore.swift:12`), so the write schedules another invalidation of every view that read it.
  It does not loop (the second pass early-returns) but it is undefined behaviour by SwiftUI's own
  contract and it puts a synchronous iCloud call on the render path.
- **(b) SEV2 — per-frame cost on the hub. UNVERIFIED, structurally present.**
  `GameModel`'s update tick calls `core.advance(realDt:)` unconditionally when no sheet is open
  (`GameView.swift:372`), and `advance` ends with `rebuildSnapshot()` (`GameCore.swift:310`), which
  writes `snapshot` — *the one observed property on `GameCore`* (`GameCore.swift:60`, everything
  else is `@ObservationIgnored` at `:65-72`). `GameView.body` reads `model.core.snapshot.mode`
  (`GameView.swift:1420`) and constructs `MenuView` with `model.core.snapshot.best` (`:1423`).
  **S-016's D-051 fix (`GameView.swift:332`) freezes the sim only when a sheet is open** — the hub
  with no sheet still ticks. So on the hub, `MenuView.body` — and therefore
  `ProfileStore.shared.unclaimedCount(now:)` at `MenuView.swift:345` — is re-evaluated at frame
  rate. Each call allocates: 2 pool copies + 2 SplitMix64 states (`MissionCatalog.swift:154-158`,
  `:170-174`), a 19-element `[Mission]` concatenation (`ProfileStore.swift:596-597`), and 19
  `missionState` calls each doing a `[String: Double]` lookup and a `Set<String>` lookup
  (`:542`, `:545`). That is ~19 String-keyed hashes + several array allocations **per frame** on the
  app's home screen.
  **How to settle it:** add a `static var n = 0; n += 1` counter to `unclaimedCount`, launch to the
  hub, idle 5 s, log `n`. If `n ≈ 300–600`, (b) is confirmed. If `n ≈ 5`, SwiftUI is eliding the
  `MenuView` rebuild and (b) is a non-issue. I could not run this (read-only pass).

**Fix shape for both, and it is small:** split reads from writes. Make `dailyMissions`/
`weeklyMissions`/`unclaimedCount` **non-mutating pure reads** that take the already-rolled-over state
as given, and move the rollover write to explicit lifecycle edges that already exist —
`applyRunSummary` (`:428-429`), `claimMission` (`:564-565`), plus `.task`/`.onAppear` and a
`scenePhase == .active` hook. Then cache `unclaimedCount` as a stored property recomputed on those
same edges plus the existing 60 s `TimelineView` tick (`MenuView.swift:331`). This is a
prerequisite for pass 017, not an optional cleanup: any rebuild that makes the board richer makes
the per-body cost worse.

---

## 3 · The `Profile` migration question (iron rule 7)

### 3.1 The five existing fields and their defaults

`Meta/Profile.swift:62-67`:

| field | type | default | reset semantics |
|---|---|---|---|
| `missionProgress` | `[String: Double]` | `[:]` | daily ids wiped at UTC midnight (`ProfileStore.swift:392`), weekly ids at week rollover (`:416`), per-run + achievement ids **never** |
| `claimedMissions` | `Set<String>` | `[]` | same wipe rule (`:393`, `:417`) |
| `achievementTier` | `[String: Int]` | `[:]` | never reset |
| `dailyMissionDate` | `Date?` | `nil` | the rollover watermark |
| `weeklyMissionDate` | `Date?` | `nil` | the rollover watermark |

### 3.2 `init(from:)`, quoted verbatim — the mission lines

`Meta/Profile.swift:134-137, 157-160, 176`:

```swift
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Profile()   // defaults
        coins = try c.decodeIfPresent(Int.self, forKey: .coins) ?? d.coins
        …
        missionProgress = try c.decodeIfPresent([String: Double].self, forKey: .missionProgress) ?? d.missionProgress
        claimedMissions = try c.decodeIfPresent(Set<String>.self, forKey: .claimedMissions) ?? d.claimedMissions
        achievementTier = try c.decodeIfPresent([String: Int].self, forKey: .achievementTier) ?? d.achievementTier
        dailyMissionDate = try c.decodeIfPresent(Date.self, forKey: .dailyMissionDate) ?? d.dailyMissionDate
        …
        weeklyMissionDate = try c.decodeIfPresent(Date.self, forKey: .weeklyMissionDate) ?? d.weeklyMissionDate
```

The pattern is `let d = Profile()` at `:136` and every line reads `?? d.<field>`. A new field must
follow it exactly.

### 3.3 **The trap that iron rule 7 does not name, and it is the real one**

`Profile` declares a **manual `CodingKeys`** (`:117-132`) alongside a manual `init(from:)`
(`:134-183`). The comment at `:114-115` says *"The memberwise + synthesized `encode` remain."* That
synthesized `encode(to:)` is generated **against the manual `CodingKeys` enum**. A stored property
that is added to the struct and to `init(from:)` but **not** to `CodingKeys` will not compile in
`init(from:)` (no such key) — so that half is caught. But the reverse is silent: a property added to
the struct with a `CodingKeys` case and **no** line in `init(from:)` compiles fine, encodes fine, and
decodes to its memberwise default forever — the field silently never round-trips.

I checked HEAD: **46 stored properties, 46 `CodingKeys` cases, 46 decode lines. Nothing is missing
today.** But there is no test that asserts the three counts agree — `testProfileWithMissionFieldsRoundTrips`
(`MissionsTests.swift:253-268`) round-trips a hand-picked subset, and
`testConsumableCountersRoundTripAndCanBeSpent` (`EconomyTests.swift:464`) another. **A rebuild that
adds three or four mission fields is exactly the change that would slip one.** See §6, test T1.

### 3.4 What a new mission field needs, exactly

Four edits, all mandatory, in this order:

1. `Profile.swift` — declare it with an inline default (`var missionStreak: Int = 0`). The default
   must be the *legacy-correct* value, i.e. what a player who has never had this field should read
   as. For counters that is `0`; for a `Date?` watermark it is `nil`; for a set it is `[]`.
2. `Profile.swift:117-132` — add the case to `CodingKeys`.
3. `Profile.swift:134-183` — add `x = try c.decodeIfPresent(T.self, forKey: .x) ?? d.x`.
4. **Decide the cloud-merge rule** in `ProfileStore.merged` (`:672-712`). This is *not* optional and
   the existing code has three precedents to pick from, documented at `:676-680`:
   - monotone counters → `max` (like `missionProgress`, `:711`)
   - monotone sets → `formUnion` (like `claimedMissions`, `:712`)
   - **device-local, deliberately not merged** (like `weeklyMissionDate`, `challengeRewardTier`, and
     every consumable charge) — a `max` merge on a spendable resource *resurrects spent value*.
   A new field that represents *spendable* mission currency (rerolls, keys, tokens) **must** be
   device-local or it becomes a cross-device duplication exploit, exactly as `:678-681` warns for
   charges.
5. If it is a timestamp, add a clamp to `ProfileStore.sanitized` (`:70-77`) beside the four that are
   already there (`:71-76`), or the clock-rollback exploit re-opens.

Additionally: any new field is a **grow-only iCloud KVS payload**. `save()` (`:656-661`) writes the
whole encoded profile to `NSUbiquitousKeyValueStore` on every mutate. KVS has a 1 MB total /
1 MB-per-key limit. A per-mission-id dictionary is fine (28 keys); a per-day history log is not.

---

## 4 · Determinism — what missions may and may not touch

### 4.1 Today: missions are RNG-clean

| question | answer | cite |
|---|---|---|
| Do missions touch `startRun(seed:)`? | **No.** | `grep -rn "startRun" PrismRush/Meta` → NOT FOUND |
| Do missions touch the spawn path? | **No.** | `grep -rn "Spawner\|Patterns" PrismRush/Meta` → NOT FOUND |
| Do missions use RNG at all? | Yes — **two meta-domain SplitMix64 streams**, separated by tag | `MissionCatalog.swift:148` `dailyTag = 0x4D49_5353_494F_4E53` ("MISSIONS"), `:165` `weeklyTag = 0x5745_454B_4C59_3133` ("WEEKLY13") |
| Do those streams feed `DailyChallenge.seed`? | **No** — explicitly, and the docstring says so | `MissionCatalog.swift:162-165`: *"this never feeds `startRun(seed:)`, so it has zero layoutVersion implications (rule 2/3)"* |
| Does `Date()` reach Core/ through missions? | No. Every mission API takes `now: Date = Date()` injected from the UI; Core never sees it | `ProfileStore.swift:377,:385,:400,:408,:427,:541,:563,:593` |

**Consequence: changing mission catalog content, rewards, targets, slot counts, or the pool draw
costs ZERO `layoutVersion` bumps and does not require a solvability-bot re-run.** Changing
`dailyTag`/`weeklyTag`, the pool arrays, or the draw loop *will* change which missions every player
in the world sees on a given date — which is a live-content change, not a determinism break — and it
will break `MissionsTests.testDailySlotsAreDeterministicPerDay` / `…RotateAcross…` and
`ProgressionTests.swift:250-270` only if those pin literal ids. (They pin *stability and rotation*,
not specific ids — `MissionsTests.swift:44-58`, `ProgressionTests.swift:254-270` — so a pool edit
passes them. That is a gap: see test T4.)

### 4.2 Proposed mission types, sorted by determinism cost

| proposal | metric source | costs a `layoutVersion` bump? | costs a bot re-run? |
|---|---|---|---|
| "collect N gems in one run" | existing `RunSummary.gems` | **no** | no |
| "thread N rings in one run" | `FXEvent.ringPassed` (`Models.swift:217`) — **already emitted**, needs one counter in `handleFX` + one `RunSummary` field | **no** | no |
| "fire N blasts" | `FXEvent.blastFired` (`:234`) — already emitted; `blastsThisRun` already exists at `GameView.swift:105` and is **currently unused by missions** | **no** | no |
| "shatter N obstacles" | `FXEvent.obstacleShattered` (`:237`) — already emitted | **no** | no |
| "survive N stumbles" | `FXEvent.stumbled` (`:224`) — already emitted | **no** | no |
| "trigger N overdrive pads" | `FXEvent.boostStarted` (`:218`) | **no** | no |
| "reach flow surge level N" | `core.flowSurges`, already read at `GameView.swift:948` | **no** | no |
| "defeat a Warden in world N" | needs a per-world breakdown; `Profile.swift:35-37` explicitly declines to add one until there is a consumer — pass 017 *is* the consumer | **no** | no |
| "beat today's Daily Challenge score X" | `ProfileStore.recordChallengeRun` | **no** | no |
| **"collect a Mystery Box in a run"** | **requires the in-run box (M7)**, which adds a spawn decision | **YES** — `s016_coins-economy.md:§3.2` already costs this out; the pre-armed v13 pin at `0x9E49_3424_C18A_59C5` is the one to spend | **YES**, 200 seeds × 6,000 m + 12,000 m soak |
| **"collect a special mission-only pickup"** | new entity in the spawn stream | **YES** | **YES** |
| **"complete a mission-specific layout"** | new pattern | **YES**, and it also shifts every pattern index (iron rule 4) | **YES** |

**Recommendation: pass 017 should ship zero spawn-path mission types.** Every one of the first nine
rows is free, and the tenth is already owned by the in-run-box work S-016 scoped. Coupling the
missions rebuild to a `layoutVersion` bump would put a UI/economy pass on the critical path of the
solvability proof for no gain.

**One landmine if a bump does happen anyway:** the goldens live in *two* places —
`DailyChallengeTests` **and** `MissionsTests.testTodaysChallengeSeedMatchesUTCGoldens`
(`MissionsTests.swift:190-204`, currently pinning `0x03B5_B844_D08B_98AF` /
`0x440D_2303_981F_5A63`). That second pin is in the *missions* test file, so a mission-focused pass
is the most likely one to edit it carelessly. It must be re-derived in Python from the SplitMix64
constants, never copied from the Swift it pins (`CLAUDE.md` iron rule 3).

---

## 5 · G3 audit of `MissionsView.swift`

Iron rule 5 has two clauses. Verdict: **clause 1 clean, clause 2 clean, but the screen commits a
third sin the rule does not name.**

### 5.1 `@State` on a shared `@Observable` — CLEAN

`grep -n "@State" PrismRush/UI/MissionsView.swift`:

| line | declaration | verdict |
|---|---|---|
| `:16` | `@State private var claimPulse = 0` | `Int` — fine |
| `:342` | `@State private var appeared = false` | `Bool` — fine |
| `:343` | `@State private var flyAmount = 0` | `Int` — fine |
| `:344` | `@State private var flyTrigger = 0` | `Int` — fine |
| `:559` | `@State private var risen = false` | `Bool` — fine |

No `@State` holds a `ProfileStore`, `GameModel`, `IAPManager`, or any other `@Observable`. **PASS.**

### 5.2 Snapshotting `store.profile` into a `let` at the top of `body` — CLEAN

`MissionsView.swift:31` is `let store = ProfileStore.shared` — that binds the **singleton reference**,
not a value copy of `profile`. Every subsequent read goes `store.profile.…` (`:32`, `:52`, `:55`,
`:59`) or through a method that reads it, so observation tracks the property. This is exactly the
shape iron rule 5 prescribes; the docstring at `:10` says so. `MissionCard` takes `state:` — a
`MissionState` **value** — as a parameter (`:336`), and the parent recomputes it from the live store
each pass (`:178`), which is the correct read-model pattern. **PASS.**

`MenuView.swift:344-345` and `:355-357` reference `ProfileStore.shared` directly in `body`. **PASS.**

### 5.3 **The actual defect: `body` mutates and persists the profile** — SEV2, `MissionsView.swift:37, 39, 41, 43`

This is the item the brief refers to, and it is real, but it is **not the claim path** — the claim
path is correct. Claims happen in button actions:

- `MissionCard.claim()` (`:476-484`) is called from `Button(action: claim)` (`:443`) — an action
  closure, not `body`. It writes the store *first*, then the FX ride the resulting state change
  (`:474-475` documents exactly this ordering). Correct.
- `CLAIM ALL` (`:121-137`) is an unstructured `Task { @MainActor in … }` inside a `Button` action,
  replaying a snapshotted queue against the **same** `now` that built the advertised `+total`
  (`:126-129`). Correct, and the reasoning is documented.

The mutation-in-`body` is the **board refresh**, per §2.3: `:37`, `:39`, `:41` and `:43` each reach
`refreshDailyMissions`/`refreshWeeklyMissions`, which call `mutate` → `save()`. So:

> **Reading the Missions screen on the first launch of a new UTC day writes the profile to
> `UserDefaults` and calls `NSUbiquitousKeyValueStore.synchronize()` from inside a SwiftUI view
> body.**

Same for the hub via `MenuView.swift:345`.

**This must be fixed before the rebuild, not after.** A richer board means more rows, more
`missionState` calls, and more body passes over the same mutating read.

### 5.4 One more, smaller: 8 redundant board refreshes + ~76 `missionState` calls per body pass

Per `MissionsView` body pass: 4 × `refreshDaily` + 4 × `refreshWeekly` (§2.3), and `missionState` is
computed **four times over the same 19 missions** — `activeStates` (`:111`), `claimableMissions`
(`:165`), the `claimAllRow` reduce (`:120`), and `sectionBlock` (`:178`). ~76 calls, each a
String-keyed dictionary + set lookup. Compute the 19 `MissionState`s **once**, at the top of the
`TimelineView` closure, and pass the array down. That is a ~4× reduction for one refactor and it
makes the whole screen a pure function of one array — which is also what makes it testable.

---

## 6 · Tests: what exists, what should exist

### 6.1 The bug the current tests do not catch, and it is a "does nothing" bug

**A completed achievement ladder does not unlock its character until the player taps CLAIM, and no
surface says so.**

- Ownership is `SkinUnlocks.earned` → `.achievement(id, tier)` → `(profile.achievementTier[id] ?? 0) >= tier`
  (`SkinUnlocks.swift:12`).
- `achievementTier` has exactly one writer: `claimMission` (`ProfileStore.swift:584`).
- But `CharacterSelectView.unlockProgress` for `.achievement` reads **`missionProgress`**, the raw
  metric (`CharacterSelectView.swift:187-192`), and renders `min(1, have/target)` with the text
  `"\(Int(have)) / \(Int(target))"`.
- So the card reads **`10,000 / 10,000`, a full bar, and a `lock.fill` + `RUN 10,000 M LIFETIME`
  pill** (`CharacterSelectView.swift:244-252`, `SkinUnlocks.swift:24-28`) — simultaneously.

Three of 24 characters are gated this way: `ach.dist` T1, `ach.gems` T2, `ach.close` T1
(`SkinCatalog.swift:168, 174, 211`). The locked-tap does route to Missions (`CharacterSelectView.swift:293`),
so decree 4 holds — but decree 2 ("previews never lie") and the owner's "not easy to understand" both
land here. **This is the single clearest instance of "missions do nothing": the player finished the
work, the game shows 100 %, and the reward is invisible behind an unexplained tap on another screen.**

Fix options for pass 017 (pick one deliberately, record it as a D-number):
(a) auto-claim achievement tiers the moment `missionProgress` crosses the target inside
`applyRunSummary` — simplest, removes the concept of an unclaimed achievement entirely; or
(b) keep the tap but make the character card read `CLAIM IN MISSIONS ›` instead of the requirement
pill once `missionProgress >= target && achievementTier < tier`, and badge it.

### 6.2 What exists today

**Linux/`swift test` (`Package.swift:16-23` compiles `Core/` + 7 Meta files + `Audio/Synth.swift`):**

| file | mission coverage |
|---|---|
| `MissionsTests.swift:41-58` | daily slot determinism + rotation across 7 days |
| `:64-89` | daily rollover wipe; accumulation across runs within a day |
| `:93-126` | per-run = best-single-run; max vs sum; claim-once-forever |
| `:128-135` | incomplete claims and unknown ids pay nothing |
| `:141-166` | tiered ladders pay in order; lifetime metrics never reset |
| `:168-176` | chest opens feed chest missions |
| `:179-186` | `unclaimedCount` |
| `:190-204` | **the challenge-seed goldens** (`layoutVersion` pin, easy to miss) |
| `:238-268` | legacy decode defaults + mission-field round trip |
| `:276-307` | `MissionBoardSummary` — the PR-0304 regression, 4 cases |
| `ProgressionTests.swift:250-330` | weekly determinism, rollover, claim gating, clock rollback |
| `SkinCatalogTests.swift:74-80` | every `.achievement` unlock names a real ladder at a reachable tier |
| `EconomyTests.swift:162-164` | purchased worlds do not credit `ach.worlds` |
| `EconomyTests.swift:204` | purchased coins do not feed mission/achievement progress |

**XCUITest (`UITests/InteractionUITests.swift`, 12 tests total):** exactly one touches missions —
`testMissionsClaimAllCascadeAndSingleClaim` (`:261-280`). It asserts `railMissions` exists,
`missionsSummary` **exists** (never reads its label), `claimAllButton` appears and then disappears.

**Gaps in one line each:**
- **No test asserts the summary strip's *text*.** PR-0304 can silently regress; `s007_missions.md`
  said this and it is still true.
- **No test covers §6.1** — the claim→character coupling is untested from either side.
- **No test asserts `refresh*` is not called from a read path** (there is nothing to assert against
  today, since reads mutate).
- **No test pins the daily/weekly pool contents or reward totals.**
- **`MissionState` is not `Equatable`** (`ProfileStore.swift:501-509`), so a test cannot
  `XCTAssertEqual` a whole state. Adding `: Equatable` is free and unblocks half the tests below.

### 6.3 Tests pass 017 should ship — all but T7/T8 run under `swift test`

| id | test | file | layer |
|---|---|---|---|
| **T1** | `testEveryProfileFieldRoundTripsThroughCodable` — build a `Profile` with every field set to a **non-default** value via the memberwise init, encode/decode, `XCTAssertEqual`. The memberwise init forces a compile error when a field is added, so the test cannot silently miss one. This is the guard for §3.3. | `MissionsTests` | **Linux** |
| **T2** | `testAchievementCompletionAloneDoesNotUnlockTheCharacter` (or, after the fix, *does*) — set `missionProgress["ach.dist"] = 10_000`, assert `SkinUnlocks.earned(drift, …)` matches the chosen policy from §6.1. Pins the coupling in the layer that owns it. | `SkinCatalogTests` | **Linux** |
| **T3** | `testReadingTheBoardNeverMutatesTheProfile` — snapshot `store.profile`, call `dailyMissions`/`weeklyMissions`/`unclaimedCount`/`missionState` for a date whose board is already current, assert `profile` is unchanged (`Profile: Equatable`, `Profile.swift:5`). Then the same for a **rolled-over** date and assert it still does not mutate, with the write moved to the explicit `refresh` call. This is the regression guard for §2.3/§5.3. | `MissionsTests` | **Linux** |
| **T4** | `testEveryCatalogEntryIsWellFormed` — for all 28 entries: non-empty id, globally unique id, `target > 0` for non-tiered, `rewardCoins > 0` for non-tiered, tiered `targets.count == rewards.count`, tiered targets strictly increasing, tiered rewards non-decreasing. Today `mission(_:)` (`MissionCatalog.swift:142-144`) would silently return the first of two duplicate ids. | `MissionsTests` | **Linux** |
| **T5** | `testBoardRewardBudgetStaysInsideTheCostedBand` — assert `dailySlots(day).map(\.rewardCoins).reduce(+)` and the weekly equivalent stay inside an explicit band for a spread of days, and that the achievement ladder total equals a pinned literal. **This is the test that makes the economy claim in §0 a fact rather than a memory** — if pass 017 raises rewards, this fails loudly and forces the number to be re-costed against `s016_coins-economy.md`. | `MissionsTests` | **Linux** |
| **T6** | `testEveryMetricIsReachedByAtLeastOneCatalogEntryAndViceVersa` — every `Mission.Metric` case either appears in the catalog or is explicitly listed as reserved. Today `.revives` is a dead case whose `RunSummary` field is structurally pinned to 0 (`GameView.swift:1013` runs only on first death; documented in `find-catalog-missions.md` F-1). A rebuild should either use it or delete it, and this test forces the choice. | `MissionsTests` | **Linux** |
| **T7** | XCUITest `testMissionsSummaryStripNeverSaysAllClearOnAFreshBoard` — fresh profile, open Missions, read `missionsSummary`'s **accessibility label** (already set at `MissionsView.swift:90`) and assert it does not contain "All clear". Closes the PR-0304 hole. | `InteractionUITests` | Mac only |
| **T8** | XCUITest `testCompletedLadderSurfacesItsCharacterReward` — with `PR_UITEST` seeding a completed ladder (`GameView.swift:199-205` already does this shape), claim, close the sheet, open Characters, assert the skin is owned. Covers the `closeSheet → checkSkinUnlocks` hop (`GameView.swift:887-889`) that no test touches. | `InteractionUITests` | Mac only |

Note on where to put the logic: **anything pass 017 wants tested must live in `Meta/`, not
`UI/MissionsView.swift`.** `Package.swift:16-23` lists the seven Meta files by name; a new Meta file
(e.g. `MissionBoard.swift` holding the resolved 19-row board as a pure value) **must be added to that
list** or it will not compile on Linux and CI (`.github/workflows/core-tests.yml`) will silently not
cover it. `MissionBoardSummary` (`ProfileStore.swift:518-539`) is the precedent to copy: a pure
decision type in the Linux layer, with its presentation (`symbol`/`tint`) in a private extension in
the view (`MissionsView.swift:305-327`). Copy that split exactly.

---

## 7 · What a rebuild has to change, by defect

Not a design proposal — a statement of which files each of the four complaints forces open.

| defect | files that must change | files that must NOT change |
|---|---|---|
| **ugly** | `UI/MissionsView.swift` only. `s016_design-system.md:442` already specifies the direction: four section tints → one `action` accent + rarity-neutral rules; ring → segmented bar (countable); CLAIM ALL becomes the screen's single E3 emission. | anything in `Meta/` |
| **not easy to understand** | `UI/MissionsView.swift` + `UI/CharacterSelectView.swift:186-193, 244-252` (§6.1) + optionally surfacing the 8-entry daily pool so "3 of 8" is legible | `Core/` |
| **does nothing** | **`Mission.Scope`/`Mission` in `MissionCatalog.swift:33-84`** — a reward type that is not `Int` coins. Then `claimMission` (`ProfileStore.swift:579-588`) to pay it, and `Profile` for whatever it banks (§3.4). | `Core/`, the spawn path, `layoutVersion` |
| **not rewarding** | Same as above **plus** the economy costing. Raising `rewardCoins` is the wrong lever (`s016_coins-economy.md:§1.5` — the catalogue is already free in 13–27 days and 62 % of a casual player's income is skill-free meta). The right lever is a reward the coin economy does not already saturate: `s016_coins-economy.md:§4.1` ranks an **infinite non-arbitrage sink** at #2 and a **free daily box** at #3 — missions are the natural faucet for both. Constraint from D-026, restated at `§4.1`: **no mission reward may grant a coin multiplier.** | — |

---

## 8 · Risk register, worst first

| # | risk | why it is here | mitigation |
|---|---|---|---|
| **R1** | **The rebuild ships as a prettier screen and the owner's "not rewarding" complaint survives it verbatim.** | Three of the four defects are outside `MissionsView.swift`. The screen is the most visible and the least load-bearing. | Land the `Mission` reward-type change (§7 row 3) **before** any pixel moves. Gate the pass on T5. |
| **R2** | **Mission rewards get inflated to "feel rewarding" and quietly break the economy.** The catalogue is already free in 13–27 days; missions are 10–21 % of income. Doubling them takes ~2 days off a 13-day game. | The failure is invisible for weeks — nobody notices a too-generous faucet until nothing is left to buy. | T5 pins the reward budget with a literal. Any change to it must cite a recomputed `s016_coins-economy.md` §1.5 table in the commit message. |
| **R3** | **A new `Profile` field silently never round-trips** (§3.3) — the field exists, compiles, encodes, and reads as its default forever. On a *mission* field that means claimed rewards or streaks vanish on relaunch. | The manual `CodingKeys` + manual `init(from:)` pair makes this a 1-line omission with no compile error. There is no test that catches it today. | **T1, before any field is added.** Plus the merge decision (§3.4 step 4) written down as a D-number, not inferred. |
| **R4** | **The mutation-in-`body` (§5.3) gets carried into the rebuild and multiplied.** A richer board = more rows = more body passes over a mutating read, on a screen that already refreshes both boards 4× per pass. | It is invisible in every test (unit tests call the store directly; the XCUITest never idles on the board). | Fix the read/write split first; **T3** is the guard. Fix `MenuView.swift:345` in the same PR — that one is on the *hub*, where the owner's "the app becomes slow at points" (M5, SEV0) actually lives. |
| **R5** | **A "collect the in-run box" mission gets added and drags a `layoutVersion` bump + a 200-seed bot re-run onto a UI/economy pass.** | It is the single most obvious mission to want once M7 ships, and §4.2 shows it is the only proposal that costs anything. | Ship zero spawn-path mission types in 017 (§4.2). If the owner insists, spend the pre-armed v13 pin `0x9E49_3424_C18A_59C5` and re-derive **both** golden sites — `DailyChallengeTests` **and** `MissionsTests.swift:190-204`. |
| **R6** | **The claim→character coupling (§6.1) gets "fixed" on the Characters screen only**, leaving `achievementTier` still requiring a tap — so the bar and the lock still disagree for anyone who does not visit Missions. | It presents as a Characters bug and will be triaged there. | Pick (a) or (b) in §6.1 explicitly and pin it with **T2** in `SkinCatalogTests`, which is the Linux layer that owns `SkinUnlocks`. |
| **R7** | **Editing `dailyPool`/`weeklyPool` changes what every player in the world sees today**, mid-day, with no versioning. A player 2/3 through `day.close15` loses it when the pool index shifts. | `dailySlots` draws by index from a mutable array (`MissionCatalog.swift:154-158`); adding an entry re-rolls every past and future day. Existing progress is keyed by **id**, so ids that survive keep their progress — but an id that leaves the pool keeps a stale `missionProgress` entry forever (nothing prunes unknown ids). | Append-only pool edits, or accept the re-roll and say so. Add T4's uniqueness check. Consider pruning unknown ids in `refresh*`. |
| **R8** | **`MissionsView.swift` grows past the 800-line ceiling.** It is 577 L today with four section builders, `MissionCard` (211 L) and `CoinFlyUp` inline. A richer board pushes it over. | House rule + `CLAUDE.md`. | Split now: `MissionCard.swift`, `MissionSectionHeaders.swift`, and the pure board resolution into a new `Meta/MissionBoard.swift` — **remembering to add it to `Package.swift:16-23`.** |
| **R9** | **The PR-0304 regression returns unnoticed** — a rebuilt summary strip re-derives "is anything claimable" and a fresh board reads ALL CLEAR again. The owner has already seen this bug once. | No test reads the strip's text (§6.2). `MissionBoardSummary` is well-tested but nothing forces the *view* to use it. | **T7.** Also keep `MissionBoardSummary.of` as the only path to the strip's copy. |
| **R10** | **Swift 6 strict concurrency on any new async claim path.** The CLAIM ALL cascade is an unstructured `Task { @MainActor in … }` (`MissionsView.swift:130`) deliberately (`:122-124`: the claims must finish if the sheet closes). A rebuild that adds reveal animations will want more of these. | Unstructured tasks that outlive their view are the exact shape that leaks or double-fires. | Keep the store as the destination (it is `@MainActor`, `ProfileStore.swift:7`), keep the `now:` snapshot (`:126-129` — a live `Date()` per claim let a midnight rollover pay less than advertised, which is a decree-5 break), and never make the animation a precondition for the payout (`:474-475`). |

---

## 9 · NOT FOUND

Things I looked for and could not find, with the greps:

- **A filed backlog item for the mutation-in-`body`.** `grep -rn "during body\|during a view update\|Modifying state during" docs/` → no matches. `grep -rn "MissionsView\|missions" docs/agent/03_BACKLOG.md` returns 11 lines, none of which is this. §5.3 appears to be a **new finding**; the closest filed item is PR-0304 (`03_BACKLOG.md:1021-1033`, status DONE(S-007)), which is a different bug on the same screen.
- **Any per-frame mission read inside `Core/`.** `grep -rn "missionProgress" PrismRush/Core` → no matches. Core mentions missions only in comments (`GameCore.swift:135,:160,:453,:626,:1054`).
- **Any XP or non-coin payout from a mission claim.** `ProfileStore.claimMission:579-588` writes only `claimedMissions`/`achievementTier`/`coins`/`totalCoinsEarned`. `grep -rn "totalXP" PrismRush/Meta/ProfileStore.swift` → written only in `applyRunSummary:441`.
- **A generic "every Profile field round-trips" test.** `grep -rn "RoundTrip\|roundTrip" Tests/CoreTests` → 2 hits, both field-subset tests (`MissionsTests.swift:253`, `EconomyTests.swift:464`).
- **A `Tests/PrismRushUITests` directory.** XCUITests live at `UITests/InteractionUITests.swift` (`project.yml:52-57`), 12 `func test`s, one of which touches missions.
