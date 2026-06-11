# QA — final adversarial review of the v1.2 multi-agent overhaul

Scope: the entire `git diff main...HEAD` (61 files), reviewed file-by-file against the six wave
reports, hunting cross-agent seam mismatches, stale references, economy double-pays, G3
violations, Swift 6 smells, and tuning/text drift.

**Verdict: merge-ready** for everything Linux can prove. Suite: **89/89 green**
(`swift test -c release`, 9.1 s) after fixes; every iOS-only file passes `swiftc -parse`;
an extended **500-seed × 6,000 m bot soak ran clean (0 deaths)** with split bars, chrono,
doubler and moving walls all confirmed present in the tested runs (throwaway probe, removed —
CI time unchanged). Mac type-check/visual items are consolidated below.

---

## Verified OK (checked, found sound)

**Seams**
- `FXEvent` (11 cases) ↔ consumers: `GameView.handleFX`, `Haptics.handle`, `RealityRenderer.fire`
  each cover every case (incl. `.chronoEnded`, both `NearMissKind`s, all 4 `PickupKind`s).
- `EntityKind` (10 cases) ↔ `RealityRenderer.makeEntity` (exhaustive) + pools place closure
  (splitBar segments repositioned per-frame from the OPEN lane; doubler/chrono spin like pickups).
  No leftover `// INTEGRATION` commented arms, no `.piston`/`timeScale` strays.
- Every `Synth.SFX` the UI calls exists; all 20 cases render non-silent (SynthTests); ducking is
  automatic via `ducksMusic`. Zero stale `playSFX([Float])` call sites (hatch now deleted).
- Snapshot contract honored: `speed` = EFFECTIVE (chrono-scaled) and drives FOV/scroll/trails;
  `rampSpeed` raw (unused by renderer, as specced); `doublerRemaining`/`chronoRemaining` drive the
  new HUD chips; `usedCheckpoint` gates `submitRun`. `EntityState.y` authoritative everywhere —
  the renderer's old bar-y hardcode/fallback is gone; mesh extents match the kill bands
  (bar 0.95–1.65 at y 1.3, low top 0.85, splitBar segment width 2.5 = 2×`laneHitHalfWidth`).
- `GameOverView` init ↔ `GameView` call site: all 19 labeled arguments match in name, order and
  type. `MenuView` (10 params) and `RewardsBar(model:onMissions:)` call sites match exactly.
- Mission metrics ↔ FX counters ↔ summary: `.nearMisses`←CLOSE count, `.slickBonuses`←SLICK,
  `.slides`←`.slid`, `.multiplierHit` uses the identical formula in core/HUD/popup/summary
  (`1 + streak/6`, cap 5). Per-run = max-of-single-run, daily/lifetime = sum; all tested.

**Economy (the revive P0)**
- Death→revive→death walked end-to-end: per-component awarded-so-far counters make every payout a
  `max(0, cumulative − awarded)` delta; `totalRuns` +1 once per run; `applyRunSummary` exactly once
  (first death — documented trade-off); fanfare once per run vs pre-run best; breakdown components
  are Ints before the multiplier so gems+distance+worlds == `lastCoinsEarned` exactly.
- Challenge runs: revive disabled (`canRevive` + `revivesLeft: 0`), checkpoint structurally
  impossible, PLAY/RUN AGAIN never inherit the flag, `recordChallengeRun` keeps a per-UTC-day max,
  scores go to `prismrush.best` (per-run) and `prismrush.daily` (UTC day as context).
- Missions can't double-claim (`claimedMissions` / `achievementTier` ordering tested); stale
  claims from yesterday's board are rejected (slot-membership check + refresh-before-claim).
- Forward-clock exploits blocked for ALL four timestamps (`lastDailyClaim`, `lastChestOpen`,
  `dailyMissionDate`, `dailyChallengeDate`) — sanitized on load AND clamped on read; tested.
- Checkpoint starts can't farm `ach.worlds`/world bonus: bonus pays only worlds crossed THIS run,
  and `worldsCrossed` credit for the start world was necessarily already earned when the player
  first reached it (checkpoint unlock requires it).

**Content coverage of the test suite**
- Gating: split bar (idx 10) ≥ 1,440 m, moving walls (idx 11) ≥ 1,920 m, chrono only via pattern
  10, doubler via pattern 7 (≥ 260 m) — all comfortably inside the 6,000 m / 12,000 m bot
  distances. `testBotCollectsChronoDuringProceduralRuns` asserts chrono is actually experienced.
  QA's 500-seed soak additionally asserted ≥1 sighting of each new entity kind: all present.

**Hygiene**
- `Package.swift` sources all exist (Core dir + 4 Meta files + Synth.swift); CI workflow correct.
- `Services/Persistence.swift` deleted with zero stale references (project.yml uses a directory
  glob, so no stale sources list either). ProfileView no longer contains Restore Purchases.
- G3: ProfileStore / IAPManager / AccountService / GameCenterService are read live in `body`
  (no `@State`-captured observables, no profile snapshots into `let`s that gate re-render);
  CharacterSelect's grid `.id()` rebuild hack is gone (HUD's `.id(snap.mult)` is a value-keyed
  transition retrigger, not an identity hack — fine).
- Tuning/text: HowToPlay teaches ×1→×5; gem popup computes from `Tuning` (no stale 5/8/10);
  LevelSelect uses `Tuning.worldLength`; settings defaults (`musicVolume`/`sfxVolume` 1,
  `hapticsEnabled` true) round-trip and apply in `GameModel.install`.

## Fixed in this pass

1. **TIME-survived contract violation** (`UI/GameView.swift`) — `lastRunDuration` was wall-clock
   since `startRun`, but is documented in three places (GameOverView, GameModel, RunSummary) as
   "seconds in `.play` this run". Pausing, idling on the death panel, or shopping before a revive
   inflated the game-over TIME tile and the missions `duration` metric. Now accumulated per-frame
   only while `mode == .play && !paused` (`playTimeThisRun`; `runStartedAt` removed).
   UI-layer — not SPM-testable; verify on Mac: pause 30 s mid-run, die → TIME excludes the pause.
2. **Dead `SynthEngine.playSFX(_ samples:)` removed** — zero call sites; both AGENT_audio and
   AGENT_integration requested deletion once migrated. Removes the uncached re-synthesis footgun.
3. **README shipping checklist missing `prismrush.daily`** — the recurring daily leaderboard was
   added in the final wave (commit `6ed9f41`, after AGENT_wiring recorded "no daily board");
   a human following README step 3 would never create it in ASC and challenge submissions would
   silently no-op. Also fixed the stale "26 tests" claim (→ 89 + Linux `swift test` note).
4. **`Store/metadata.md` contradicted the shipped build** — claimed "In-App Purchases: None",
   "Data Not Collected", "no network calls", and a single leaderboard, while the build ships 5
   IAPs, Game Center (2 boards), Sign in with Apple and iCloud sync (README §Shipping explicitly
   says privacy is no longer "Data Not Collected"). Corrected the factual rows/lines; final ASC
   questionnaire answers remain a human gate (see flag 6).

## Flagged (Mac verification or human decision)

1. **Mac build required** — Linux is parse-only for UIKit/RealityKit/SwiftUI. The consolidated
   checklist in `reports/AGENT_wiring.md` §MAC VERIFICATION stands; highest-risk items:
   `MainActor.assumeIsolated` notification observers (SynthEngine ×3, RealityRenderer ×1,
   ProfileStore ×1, GameCenterService authenticate handler) under Swift 6 `complete`;
   `.sensoryFeedback(trigger:)` closures; `symbolEffect(.pulse, options:isActive:)`; the haptic
   double-tap `Task`; plus the new `playTimeThisRun` change above.
2. **Backward-clock daily-mission farming (accepted, low value)** — rolling the clock BACK
   exposes a previous UTC day's 3 slots while pool progress accrued today persists, allowing up
   to ~3 extra claims (~300–400 coins) per real day of clock fiddling. Forward-clock is fully
   blocked; closing the backward hole needs per-day claim bookkeeping (rework, not a stabilization
   edit). The min()-based refresh deliberately trades this for forward-exploit safety.
3. **Retroactive Double-Coins on mid-run purchase (accepted, player-favoring)** — buying Double
   Coins from the death panel makes the next death's delta retroactively double the components
   already paid this run (`cumulative×mult − awarded`). One-shot per account (non-consumable),
   bounded by one run, not farmable. Fixing requires per-death base-component tracking.
4. **Post-revive tail not folded into missions** — documented AGENT_wiring deviation; `.revives`
   metric exists but no mission uses it and it's always 0 at first death. Fine until a revive
   mission ships; the engine would need a `countsAsRun:`-style second fold.
5. **UTC-midnight body mutation** — RewardsBar/MissionsView/DailyChallengeCard call
   rollover-mutating ProfileStore methods during view evaluation (pre-existing pattern); watch for
   "modifying state during view update" at midnight on Mac and debounce into `.task` if seen.
6. **ASC human gates** — create `prismrush.best` AND recurring `prismrush.daily`; App Privacy
   questionnaire must declare Purchases + Game Center/SiwA identifiers (metadata.md now says so);
   AGENT_docs' character-limit table predates these edits — recount the description if re-counted
   limits matter (name/subtitle/keywords/promo text untouched).

## Final status

- `swift test -c release`: **89/89, 0 failures** (~9 s — CI budget unchanged).
- Extended QA soak: 500 seeds × 6,000 m, **0 deaths, 0 stalls**, all four new content kinds
  observed (probe deleted after the run).
- `swiftc -parse`: all 43 app sources pass, including every file touched by this QA pass.
