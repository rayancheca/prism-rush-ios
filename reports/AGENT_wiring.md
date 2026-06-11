# AGENT_wiring — final wiring pass (v1.0)

Files touched: `UI/GameView.swift`, `UI/EffectsOverlay.swift` (+ this report).
`Services/GameCenterService.swift` untouched — AGENT_meta.md specs **no** `prismrush.daily`
board; challenge runs go through the existing `submitRun(score:usedCheckpoint:)` (world-0 seeded
⇒ never checkpoint, per AGENT_meta §3).
Verified: `swift test -c release` → **89/89 green**; both edited files pass `swiftc -parse`.

## What was wired (per AGENT_meta.md §§1–8)

1. **Meta screens** — `MetaScreen` gains `.settings`/`.missions`; `metaSheet` renders
   `SettingsView`/`MissionsView`; `PR_SCREEN=settings|missions` debug jumps added.
2. **Entry points** — MenuView call site passes `onSettings`, `onDailyChallenge`, and
   `RewardsBar(model:onMissions:)` routed to `model.open(...)` / `startDailyChallenge()`.
3. **Daily challenge** — `startDailyChallenge()` seeds `startRun` with
   `ProfileStore.todaysChallengeSeed()` and sets `isChallengeRun` **after** the call returns
   (`startRun` clears it at the top, so PLAY / RUN AGAIN never inherit it). `canRevive` gates on
   `!isChallengeRun`; GameOverView gets `revivesLeft: 0` for challenge runs so CONTINUE never
   renders. Checkpoint is structurally impossible (`fromWorld` stays 0).
   `recordRunResults()` folds the score via `recordChallengeRun(score:)`.
4. **Settings persistence** — `install` applies `profile.musicVolume`/`sfxVolume` to the synth and
   `hapticsEnabled` to Haptics (SettingsView already applies changes live — spec §4's split).
5. **Reduce flashing** — `FlashView` gains `reduceFlash: Bool` and scales strength ×0.15;
   `EffectsOverlay.body` reads `ProfileStore.shared.profile.reduceFlash` live (G3).
6. **First-run tutorial** — `totalRuns == 0` PLAY shows `HowToPlayView(doneLabel: "LET'S GO")`
   over the menu (zIndex 2, below EffectsOverlay); dismiss starts the run.
7. **GameOverView full call site** — `previousBest` (captured in `startRun` before death mutates
   the profile best), `runDistance` (`core.traveledDistance`), `timeSurvived`, `bestStreak`,
   `nearMisses` (counted in `handleFX`), exact coin split, `revivesLeft`, `restartCountdown`,
   `onGetCoins`. The meta-sheet gate is lifted per spec §7's alternative: **the Shop sheet alone
   also renders while `.over`**, so GET COINS / EARN ×2 open it directly over the death panel
   (`onGetCoins: { model.open(.shop) }`; closing the sheet returns to the panel).
8. **Coin split** — `recordRunResults` now computes gems/distance/worlds coin deltas per
   component with their own awarded-so-far counters; `coinsDelta` is their sum. No drift vs. the
   old single-base figure: each component is an Int before the multiplier, so the multiplication
   distributes exactly.
9. **Missions feed** — per-run FX counters (`nearMisses` total + close/slick split, slides) feed a
   `RunSummary` passed to `applyRunSummary` **exactly once per run**, on the first death (the
   `!statsRecorded` branch), matching the integration agent's once-only pattern and AGENT_meta
   §8's recommended fix (`runsFinished` counts 1 per call).

## Deliberate decisions / deviations (documented per spec's "decide and document")

- **TIME tile** — spec's snippet passes live `Date().timeIntervalSince(model.runStartedAt)`,
  which would tick up on every re-render while the death panel is open. Instead
  `lastRunDuration` is captured at death-time in `recordRunResults` and passed to both
  GameOverView and `RunSummary.duration`.
- **Post-revive mission progress is not folded** — accepted trade-off of the once-per-run shape
  (spec §8: "carries ~95% of a run's metrics"). Consequence: the `revives` metric is always 0 at
  first death, so revive-based missions never progress until the engine grows a
  `countsAsRun:`-style parameter (Meta/ ownership — out of scope here). Daily/lifetime gems,
  distance etc. from the post-revive tail are likewise dropped.
- **No `prismrush.daily` GC board** — not specced anywhere in AGENT_meta.md or the codebase;
  challenge scores ride the existing `prismrush.best` per-run submission (`usedCheckpoint`
  runs still skipped).

## MAC VERIFICATION CHECKLIST (consolidated from AGENT_integration.md + AGENT_meta.md, deduped)

### Build
1. Full Xcode build (Linux is `swiftc -parse` only — UIKit/RealityKit/SwiftUI never type-checked):
   watch GameView's new GameOverView/MenuView call sites, `symbolEffect(.pulse, options:
   .repeating, isActive:)` (iOS 17 signature), `.sensoryFeedback(trigger:)` closures in
   ShopView/MissionsView, and the haptic double-tap `@MainActor` Task under Swift 6 `complete`.

### Suite
2. `swift test -c release` on macOS → 89/89 (parity with Linux).

### Visual / audio / UX spot checks
3. Menu density: DailyChallengeCard + 3-card RewardsBar between chips and PLAY on an
   iPhone SE-class height; trim card padding on 4.7" if cramped.
4. First launch (fresh install): PLAY opens HowToPlay ("LET'S GO"), dismiss starts the run;
   second PLAY goes straight in. `TabView(.page)` dots visible on the dark backdrop.
5. Daily challenge: card's play button starts a seeded run; two runs the same UTC day produce the
   identical track; death panel shows **no CONTINUE**; card's "today's best" + 7-day dots update
   after the run; RUN AGAIN after a challenge is a normal (unseeded) run.
6. GameOverView: score/"+N" count up smoothly (`contentTransition(.numericText)` needs the
   `onAppear` `withAnimation` — verify animation, not a snap); NEW BEST only on a strict beat of
   the pre-run best, else "BEST n · m TO GO"; coin breakdown line sums to "+N"; TIME tile is
   frozen at death (does not tick); NEED-N-MORE state with coins < 150; GET COINS / EARN ×2 open
   the Shop **over the death panel** and closing returns to it.
7. Revive economy (integration §5 manual steps): single-death payout formula; post-revive death
   pays only the delta; `totalRuns` +1 per whole run; fanfare exactly once even when the best is
   beaten twice in one run.
8. Missions: finish a run → daily/per-run/achievement progress reflects it (gems, distance,
   near-misses, slides); revived-run tail does NOT double `runsFinished`; CLAIM pays once and the
   row collapses; unclaimed badge on the RewardsBar matches.
9. Settings: sliders audibly change volume while dragging AND persist across relaunch (install
   hooks now live); haptics toggle kills/restores haptics immediately; Reduce flashing → death
   flash visibly ~15%; mute button still independent.
10. Watch for "modifying state during view update" at UTC midnight (RewardsBar/MissionsView/
    DailyChallengeCard call rollover-mutating ProfileStore methods in body) — debounce into
    `.task` if seen.
11. Renderer/feel (integration §6): hourglass winding, splitBar segment placement/gap
    readability, chrono FOV dip + slow-mo trail feel, HUD chip column vs. the relocated
    top-trailing mute/pause cluster.
12. CharacterSelect equip-ring animates between cards (grid `.id` rebuild removed); denied-tap
    shake respects Reduce Motion.
13. VoiceOver sweep (missions rows, challenge card, chest cooldown, shop rows, stat tiles) and
    Dynamic Type XL (`@ScaledMetric` copy grows without clipping fixed headings).

### IAP / Game Center
14. ShopView states: "Loading prices…", "Store unavailable — RETRY" (+`lastError`), inline error
    strip; purchase success → `purchaseChime` + success haptic (suppressed when haptics off);
    Restore Purchases from Settings shows the result toast.
15. Game Center: per-run score submits to `prismrush.best` on normal AND challenge deaths;
    checkpoint (world ≥ 1) runs never submit; signed-out ProfileView shows the explainer card.
