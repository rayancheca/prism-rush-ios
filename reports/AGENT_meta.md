# AGENT_meta — meta/retention UI wave handoff (v1.0)

Continuation of the meta wave (first half landed in `2067530`: economy hardening, clock-clamp,
missions engine, daily-challenge meta, settings Profile fields, IAP error surfacing, AccountService
credential check — all with tests). This pass is the UI half plus this wiring spec.

**Suite: 89/89 green** (`swift test -c release`). No new Meta/ source files were needed — the
missions/challenge/settings logic already existed and is fully covered by `MissionsTests` (21) +
`EconomyTests` (11) — so **Package.swift is unchanged**.
Every UI file below passes `swiftc -parse` (Linux can't type-check UIKit/SwiftUI — Mac checklist
at the bottom).

## New files (UI layer — Xcode target via project.yml's directory glob, NOT in the SPM package)

| File | What |
|---|---|
| `PrismRush/UI/DailyChallengeCard.swift` | "TODAY'S RUSH" menu card: per-second countdown to UTC midnight (`TimelineView`, chest-card pattern), today's best, 7-day dot calendar (`playedChallenge(daysAgo:)`), `onPlay` closure. |
| `PrismRush/UI/SettingsView.swift` | Music/SFX sliders (live to `model.synth`, persisted on gesture end), haptics + reduce-flash toggles, How to Play row, Restore Purchases row (moved here from ProfileView, with result toast), version footer. |
| `PrismRush/UI/HowToPlayView.swift` | 3 swipeable shape-built cards (`TabView` `.page`): controls / scoring (streak ladder ×1→×5, CLOSE/SLICK) / power-ups (+ revive). Reachable from Settings. |
| `PrismRush/UI/MissionsView.swift` | Daily section (3 rotating slots + rollover countdown), per-run challenges, tiered achievements with progress bars + "TIER n OF m", gold CLAIM buttons (daily-button chrome), claimed rows collapse to receipts. Reads `ProfileStore.shared` in `body` (G3). |

## Modified files

- **MenuView** — gear button (top-left, `onSettings`), `DailyChallengeCard` between the world chips
  and the rewards bar (`onDailyChallenge`), `.neon` on PLAY/hub/profile buttons, `@ScaledMetric`
  tagline. New closures are **defaulted to `{}`** so the existing GameView call site compiles —
  they do nothing until the wiring below lands.
- **RewardsBar** — third MISSIONS card with gold unclaimed-count badge (`store.unclaimedCount()`),
  `onMissions` closure (defaulted), chest `symbolEffect(.pulse)` when ready (Reduce Motion-gated),
  a11y labels on daily/chest/missions (incl. spoken chest cooldown).
- **GameOverView** — full overhaul; see §GameOverView wiring.
- **ShopView** — "Loading prices…" (`iap.isLoading` + empty), "Store unavailable — RETRY" card
  (`iap.hasLoaded` + empty, shows `lastError`), inline error strip when products exist but the last
  op failed; purchase success plays `synth.purchaseChime` + `.sensoryFeedback(.success)` gated on
  `profile.hapticsEnabled`; rows get combined a11y labels + `.neon`. (A tap with an empty catalog
  already reloads first — `IAPManager.purchase` retries `loadProducts()` internally.)
- **CharacterSelectView** — grid `.id(selectedSkin)` rebuild hack removed; the equip ring animates
  between cards via `.animation(.spring, value: profile.selectedSkin)` (Reduce Motion → none).
  Denied coin purchase → `ShakeEffect` + red ring/badge flash. Premium unowned skins route to the
  shop via `model.open(.shop)` (no new wiring needed — sheet swaps in place).
- **LevelSelectView** — world depth strings now `Int(Double(world) * Tuning.worldLength)`; the
  card count and "furthest" highlight come from `ProfileStore.unlockedWorldCount` (single source,
  capped at `ProfileStore.maxStartWorlds`); cards get a11y labels + `.neon`.
- **ProfileView** — Restore Purchases moved to Settings; Game Center signed-out → inline
  explainer card instead of a dead row; `totalRuns == 0` → "Your story starts with one run."
  zero-state instead of a wall of zeros; stat tiles get a11y labels; `@ScaledMetric` body copy.

---

## WIRING SPEC — for the GameView/EffectsOverlay/Services owner (exact snippets)

### 1. `GameModel.MetaScreen` — two new cases (`UI/GameView.swift`)

```swift
enum MetaScreen { case characters, shop, levels, stats, settings, missions }
```

`GameView.metaSheet(_:)`:

```swift
case .settings: SettingsView(model: model)
case .missions: MissionsView(model: model)
```

Optionally extend the `PR_SCREEN` debug switch: `case "settings": activeSheet = .settings`,
`case "missions": activeSheet = .missions`.

### 2. MenuView / RewardsBar call sites (`GameView.body`, `.menu` case)

```swift
MenuView(best: model.core.snapshot.best,
         coins: ProfileStore.shared.profile.coins,
         onPlay: { model.startRun() },
         onCharacters: { model.open(.characters) },
         onShop: { model.open(.shop) },
         onLevels: { model.open(.levels) },
         onProfile: { model.open(.stats) },
         rewards: AnyView(RewardsBar(model: model, onMissions: { model.open(.missions) })),
         onSettings: { model.open(.settings) },
         onDailyChallenge: { model.startDailyChallenge() })
```

### 3. Daily challenge run (`GameModel`)

```swift
/// True while the current run is today's shared challenge (revive + checkpoint are disabled).
private(set) var isChallengeRun = false
@ObservationIgnored private var runStartedAt = Date()   // also feeds GameOverView's TIME tile

func startDailyChallenge() {
    isChallengeRun = true
    startRun(seed: ProfileStore.shared.todaysChallengeSeed())   // UTC y/m/d → DailyChallenge.seed
}
```

In `startRun(fromWorld:seed:)` add `runStartedAt = Date()` and — important — reset
`isChallengeRun = false` **only when called directly** (e.g. set it false at the top of `startRun`
and have `startDailyChallenge` set it true *after* the call returns), so PLAY/RUN AGAIN never
inherits the flag:

```swift
func startRun(fromWorld: Int = 0, seed: UInt64? = nil) {
    isChallengeRun = false
    runStartedAt = Date()
    ...existing body...
}
func startDailyChallenge() {
    startRun(seed: ProfileStore.shared.todaysChallengeSeed())
    isChallengeRun = true
}
```

Disable revive for challenge runs (fair, shared track):

```swift
var canRevive: Bool {
    core.mode == .over && !isChallengeRun && core.revivesUsed < 2
        && ProfileStore.shared.profile.coins >= reviveCost
}
```

Fold the score into the challenge meta in `recordRunResults()` (after the stats block):

```swift
if isChallengeRun { ProfileStore.shared.recordChallengeRun(score: core.score) }
```

Challenge runs start at world 0 with a fresh seed ⇒ `usedCheckpoint == false`, so the existing
`GameCenterService.submitRun` call already submits them — per AGENT_integration §TODO 4 that is
intended (seeded but otherwise normal runs). Checkpoint is structurally impossible (the card always
calls `startRun(seed:)` with `fromWorld` defaulted to 0); no further gating needed.

`DailyChallengeTests` pins `layoutVersion 1` goldens — **bump `DailyChallenge.layoutVersion`**
whenever spawner/pattern/RNG-consumption changes.

### 4. Settings hooks (`GameModel.install`, per AGENT_integration §TODO 1)

Next to the existing `synth.muted = profile.muted`:

```swift
synth.musicVolume = Float(profile.musicVolume)
synth.sfxVolume = Float(profile.sfxVolume)
haptics.enabled = profile.hapticsEnabled
```

SettingsView already applies changes **live** (`model.synth.musicVolume` / `model.haptics.enabled`)
and persists via `ProfileStore.mutate` — the install lines make them stick across launches.
(If you'd rather not have UI reach into `model.synth`/`model.haptics` directly, add a
`GameModel.applyAudioSettings()` and call it from both places — cosmetic either way.)

### 5. Reduce flashing (`UI/EffectsOverlay.swift`, FlashView)

Scale flash strength to 0.15× when the profile asks for it:

```swift
// FlashView gains: let reduceFlash: Bool
.onChange(of: id) {
    opacity = strength * (reduceFlash ? 0.15 : 1)
    withAnimation(.easeOut(duration: 0.35)) { opacity = 0 }
}
// EffectsOverlay.body:
FlashView(id: model.flashID, strength: model.flashStrength,
          reduceFlash: ProfileStore.shared.profile.reduceFlash)
```

### 6. How to Play before the first run (`GameView`)

```swift
@State private var showFirstRunTutorial = false
// In the .menu case's MenuView init:
onPlay: {
    if ProfileStore.shared.profile.totalRuns == 0 { showFirstRunTutorial = true }
    else { model.startRun() }
},
// In the ZStack (above the menu, below EffectsOverlay):
if showFirstRunTutorial {
    HowToPlayView(onClose: { showFirstRunTutorial = false; model.startRun() },
                  doneLabel: "LET'S GO")
        .transition(.move(edge: .bottom))
        .zIndex(2)
}
```

### 7. GameOverView wiring (all new params are defaulted — current call site still works)

GameModel needs two tiny additions: count near-misses + run duration (both per-run, reset in
`startRun`):

```swift
@ObservationIgnored private var nearMissesThisRun = 0   // reset in startRun
// in handleFX, case .nearMiss: nearMissesThisRun += 1
// expose: var nearMisses: Int { nearMissesThisRun }   (or make it private(set) observed)
```

Capture `previousBest` and the exact coin breakdown in `recordRunResults()` (the breakdown must be
the per-death delta split, matching `lastCoinsEarned`):

```swift
private(set) var previousBest = 0          // set in startRun: previousBest = ProfileStore.shared.profile.bestScore
private(set) var lastCoinsFromGems = 0     // gemsDelta * coinMultiplier
private(set) var lastCoinsFromDistance = 0 // Int(distanceDelta / 35) * coinMultiplier
private(set) var lastCoinsFromWorlds = 0   // worldsCrossedDelta * 5 * coinMultiplier
```

(The existing delta plumbing already computes `gemsDelta`/`distanceDelta`; rounding the split this
way can drift ±1 from `coinsDelta` because the base sums before multiplying — either accept it or
compute the split first and define `coinsDelta` as its sum.)

Then:

```swift
GameOverView(snapshot: model.core.snapshot,
             coinsEarned: model.lastCoinsEarned,
             canRestart: model.canRestart,
             canRevive: model.canRevive,
             reviveCost: model.reviveCost,
             onRevive: { model.reviveForCoins() },
             onRestart: { model.startRun() },
             onHome: { model.returnToMenu() },
             previousBest: model.previousBest,
             runDistance: model.core.traveledDistance,
             timeSurvived: Date().timeIntervalSince(model.runStartedAt),
             bestStreak: model.core.bestStreak,
             nearMisses: model.nearMisses,
             coinsFromGems: model.lastCoinsFromGems,
             coinsFromDistance: model.lastCoinsFromDistance,
             coinsFromWorlds: model.lastCoinsFromWorlds,
             revivesLeft: model.isChallengeRun ? 0 : 2 - model.core.revivesUsed,
             restartCountdown: model.restartCountdown,
             onGetCoins: { model.returnToMenu(); model.open(.shop) })
```

Behavioural notes baked into the view:

- **NEW BEST** fires only on `score > previousBest`; until `previousBest` is wired it falls back to
  the legacy `score >= snapshot.best` heuristic. When not a best, it shows
  "BEST n · m TO GO".
- **CONTINUE** renders whenever `revivesLeft > 0` (or legacy `canRevive`); unaffordable →
  disabled gold button reading "NEED n MORE" + a GET COINS button (only when `onGetCoins != nil`).
  `onGetCoins` must route to the Shop — the snippet above goes via the menu because `metaSheet`
  only renders in `.menu`; if you want the shop directly over the death panel, lift the
  `model.activeSheet` overlay out of the `.menu` condition instead.
- **READY IN n…** uses the observed `restartCountdown` (AGENT_integration §TODO 2 — done).
- Score and "+N" count up (numeric content transition, instant under Reduce Motion); the ×2 gold
  tag shows when `doubleCoins` is owned, otherwise an "EARN ×2" upsell line (also `onGetCoins`).
- "Coins" row is now "Balance"; the run stats grid is distance / time / streak·top-mult /
  near-misses. The coin breakdown line only renders when all three components are passed.

### 8. Missions run summary (`GameModel.recordRunResults`) — the engine is live, the feed isn't

`ProfileStore.applyRunSummary` is fully tested but nothing calls it yet. Build the summary at the
end of `recordRunResults()` (per-death deltas for accumulating metrics, run totals for max-style):

```swift
// Needs two more per-run counters in handleFX (reset in startRun), mirroring nearMisses:
//   case .nearMiss(let kind, _): kind == .close ? closesThisRun += 1 : slicksThisRun += 1
//   case .slid: slidesThisRun += 1
var summary = RunSummary()
summary.gems = gemsDelta                       // delta: daily/lifetime gems never double-count revives
summary.distance = distanceDelta
summary.nearMissCloses = closesDelta           // delta the same way (track …Recorded counters)
summary.slicks = slicksDelta
summary.slides = slidesDelta
summary.bestStreak = core.bestStreak           // max-style: pass the run value, engine maxes
summary.bestMult = min(Tuning.multCap, 1 + core.bestStreak / Tuning.streakPerMult)
summary.worldsCrossed = core.maxWorld + 1      // 1-based, matches ach.worlds targets
summary.revives = core.revivesUsed
summary.duration = Date().timeIntervalSince(runStartedAt)
ProfileStore.shared.applyRunSummary(summary)
```

Caveat: `runsFinished` counts 1 per `applyRunSummary` call — call it on **every** death and
"day.runs5"/"ach.runs" will count revived runs multiple times. Either call it only on the first
death of a run (`!statsRecorded` branch) and fold post-revive deltas with a second call whose
metrics are deltas-only... simplest correct shape: build *delta* summaries on every death (as
above) but zero the max-style fields on post-revive deaths except via max (the engine maxes
anyway, so resending the same `bestStreak` is harmless) — and special-case `runsFinished` by
skipping daily/lifetime `.runsFinished` bumps after the first death. Cleanest: add a
`countsAsRun: Bool` parameter… recommended concrete fix: call `applyRunSummary` only on the
**first** death (it carries ~95% of a run's metrics) and accept that post-revive tail progress
lands on the next run. Decide and document; the engine itself is correct either way.

### 9. Shop purchase audio (AGENT_integration §TODO 3)

Done in ShopView: success path plays `synth.play(.purchaseChime)` (direct `model.synth` access —
same pattern SettingsView uses) + a `.sensoryFeedback(.success)` haptic gated on
`profile.hapticsEnabled`. If you add a `GameModel.purchaseSucceeded()` wrapper, swap the call.

---

## Mac-verification checklist (Linux is parse-only for UI)

1. **Menu density**: DailyChallengeCard + RewardsBar (now 3 cards) between the chips and PLAY —
   check an iPhone SE-class height; the two `Spacer()`s should absorb it, but the card may need
   `.padding` trims on 4.7".
2. `symbolEffect(.pulse, options: .repeating, isActive:)` on the chest icon (iOS 17 signature).
3. `.sensoryFeedback(trigger:) { _, _ in ... }` closures in ShopView/MissionsView compile and fire
   once per increment; haptic suppressed when `hapticsEnabled == false`.
4. `TabView(.page)` dots visible on the dark HowToPlay backdrop
   (`indexViewStyle(.page(backgroundDisplayMode: .always))`).
5. GameOverView: count-up reads smoothly (`contentTransition(.numericText)` needs the
   `withAnimation` in `onAppear` — verify it animates rather than snapping); NEED-N-MORE state by
   setting coins < 150 then dying.
6. CharacterSelect equip-ring animation after removing the grid `.id` rebuild — equip a different
   skin and confirm both cards animate their strokes; denied-tap shake respects Reduce Motion.
7. Settings sliders: audible live volume change while dragging; relaunch persistence **only after
   the install hooks in §4 land**.
8. SettingsView/MissionsView/DailyChallengeCard call `ProfileStore` methods that can `mutate` on
   UTC rollover during view evaluation (`dailyMissions`/`unclaimedCount` → `refreshDailyMissions`)
   — pre-existing pattern (RewardsBar does the same), but watch for "modifying state during view
   update" warnings at midnight UTC; if seen, debounce the refresh into a `.task`.
9. VoiceOver sweep: missions rows, challenge card, chest cooldown, shop rows, stat tiles.
10. Dynamic Type XL: `@ScaledMetric` body copy in menu/shop/profile/game-over should grow without
    clipping the fixed-size headings.

## Test inventory

**89/89 green** (`swift test -c release`) — unchanged from the previous checkpoint, since this
pass added no new Meta logic: the challenge/settings/missions engine and its meta coverage
(21 MissionsTests + 11 EconomyTests, incl. UTC rollover, per-day best, clock-rollback exploits,
and the old-saves-never-wipe decode pins) landed in commit `2067530`. UI layers aren't
SPM-testable on Linux; see the Mac checklist above.
