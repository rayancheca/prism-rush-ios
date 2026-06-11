# AGENT_integration — wiring handoff (v1.2)

Files touched (all within ownership): `UI/GameView.swift`, `UI/HUDView.swift`,
`UI/EffectsOverlay.swift`, `UI/PauseOverlay.swift`, `Render/Reality/RealityRenderer.swift`,
`Render/Reality/ProceduralMesh.swift`, `Services/Haptics.swift`, `Services/GameCenterService.swift`.
Verified: `swift test -c release` → **68/68 green**; every edited iOS file passes
`swiftc -parse` (syntax-only — UIKit/RealityKit type-checking needs a Mac build, as usual).

## 1 · Breaking-change fixups (AGENT_core.md)

- `FXEvent.nearMiss` enum: `GameView.handleFX` maps `.close → "CLOSE"` (cyan) / `.slick → "SLICK"`
  (gold). `EffectsOverlay` renders the popup string unchanged — no further mapping needed there.
- Snapshot `speed` (EFFECTIVE, chrono-scaled) is what the renderer already reads for FOV
  punch / scroll / trails / speed lines — verified correct, left as-is. `rampSpeed` is unused in
  the renderer (HUD/debug only, currently unshown).
- `EntityState.y` is authoritative: the renderer's `.bar && y == 0 → 1.3` fallback is **deleted**;
  every kind places from `Float(s.y)`.
- Exhaustive-switch updates for `.chronoEnded` + new `PickupKind`/`EntityKind` cases landed in
  GameView, Haptics and RealityRenderer (fire + makeEntity + place closure).

## 2 · New entity kinds (renderer)

- `.doubler` — armed the prepared `twinOctahedron` mesh, emerald `0x00FF88`, spins like the magnet.
- `.chrono` — new `ProceduralMesh.hourglass(halfBase: 0.3, halfHeight: 0.42)` (two 4-sided pyramids
  apex-to-apex, 9 verts, capped), icy cyan-white `0x9BF0FF`, spins with the other pickups.
- `.splitBar` — parent `Entity` with two pooled box segments (2.5 × 0.7 × 0.7, same chrome as the
  bar). The place closure repositions both segments **every frame** from `s.lane` (the OPEN lane —
  pooled entities get recycled across different gaps): segment width 2.5 equals the collision band
  (`laneHitHalfWidth` 1.25 each side), leaving a ~1.9-wide visible gap over the open lane.
- Pickup FX bursts: doubler = gold+emerald split burst; chrono = slow icy shower; both `kickFOV()`.
- Chrono presentation: smoothed −6° FOV dip while `chronoRemaining > 0` (Reduce Motion-gated,
  reset in `resetEntities`) and the 180/s trail rate is multiplied by `Tuning.chronoFactor` —
  the two marked "frenzy/timeScale" INTEGRATION hooks, keyed off `chronoRemaining` instead.
- `EntityPools` needed no changes (pools per kind appear on demand, bounded by the core caps).

## 3 · Audio wiring (AGENT_audio.md table — all rows)

Every `playSFX([Float])` call site migrated to cached `synth.play(_:)`; **zero `playSFX` call
sites remain** (audio agent may now delete the escape hatch).

| Moment | SFX |
|---|---|
| startRun / revive / daily / chest | `.startChime` / `.shieldPickup` / `.chime` / `.purchaseChime` |
| gem / nearMiss / shieldAbsorbed | `.gem(streak:)` / `.close` / `.chime` |
| pickup shield / magnet / doubler | `.shieldPickup` / `.magnetPickup` / `.doublerPickup` |
| pickup chrono → `.frenzyEnd`; `.chronoEnded` → `.frenzyStart` | falling whoosh into slow-mo, rising whoosh as time resumes (no dedicated chrono SFX exists in `Synth.SFX`; these duck music via `ducksMusic`) |
| died | `.crash` **and** `.deathSweep`, then `musicStop()` |
| worldChanged / jumped / slid | `.worldSweep` / `.jump` / `.slide` |
| laneChanged / landed | `.laneTick` / `.landThud` (core doesn't flag hard landings; thud is quiet by design) |
| new best | `.newBestFanfare` in `recordRunResults`, once per run, detected against `profile.bestScore` **before** the death is folded in |
| equip / coin-skin buy / open-close sheet | `.equipClick` / `.purchaseChime` / `.uiTick` |

## 4 · HUD

- Power-up countdown chips (`powerChip`) in the right column, same glassy `pillBackground` as the
  gems counter: **MAG** (cyan) / **×2** (emerald) / **SLOW** (ice), each `Int(remaining.rounded(.up))`.
  (No magnet indicator previously existed — all three are new, in the established chip style.)
- Multiplier display reads `snap.mult` straight from the core (correct under `streakPerMult 6`);
  the gem **popup** in GameView now computes from `Tuning.multCap`/`Tuning.streakPerMult`/
  `Tuning.gemBaseScore` instead of the stale hardcoded `5 / 8 / 10`.
- Right column gets `.padding(.top, 38)` to clear the relocated mute/pause cluster (see §7c).

## 5 · Revive economy P0

`GameModel` now tracks per-run awarded state (`coinsAwardedThisRun`, `distanceRecordedThisRun`,
`gemsRecordedThisRun`, `statsRecorded`, `newBestCelebrated`, `runStartWorld`), all reset in
`startRun`. `recordRunResults()` (still called on every death) awards
`max(0, cumulative − alreadyAwarded)`:

- First death → `ProfileStore.recordRun(...)` (counts `totalRuns` exactly once).
- Post-revive deaths → `store.mutate` folds **deltas only** (coins, totalCoinsEarned,
  totalDistance, totalGems) plus idempotent maxes (bestScore, bestStreak, maxWorldReached).
- Distance basis is `core.traveledDistance` (excludes checkpoint head-start + revive decel drift).
- World bonus pays `max(0, core.maxWorld − runStartWorld) * 5` — worlds crossed THIS run, so a
  checkpoint start no longer pays for skipped worlds.
- `lastCoinsEarned` (the "+N" on the death panel) is now the **per-death delta** — coins earned
  since the last continue. If design wants the cumulative figure instead, expose
  `coinsAwardedThisRun`.

No `RunRecordingTests` were added: the logic lives in `GameModel` (UI layer, not in the SPM
target) and extracting a pure helper would require touching Core/. **Manual test steps:**
1. Fresh run, no revive: die with G gems at traveled distance D → coins paid once =
   `(G + D/35 + maxWorld·5) × coinMultiplier`; `totalRuns` +1.
2. Revive, die again: second payout is only the post-revive delta; `totalRuns` +1 **total** for
   the whole run; final `totalDistance` increase equals the run's final `traveledDistance`.
3. Checkpoint run (world ≥ 1): no Game Center submission; world bonus only for worlds crossed
   beyond the start world; local best still updates.
4. Beat the best, revive, beat it again: fanfare plays exactly once.

## 6 · Game Center

New `GameCenterService.submitRun(score:usedCheckpoint:)` — returns early when
`usedCheckpoint == true`; GameView calls it with `core.score`/`core.usedCheckpoint`. Local best
behaviour unchanged. Deliberate change: we submit the **per-run score**, not
`profile.bestScore` — bestScore can be checkpoint-earned, and submitting it after a later fair run
would leak the checkpoint score to the leaderboard; GC keeps each player's max, so per-run
submissions converge on the true (fair) best.

## 7 · Small verified fixes

- (a) `EffectsOverlay` world-banner race: `guard !Task.isCancelled` after the sleep in
  `.task(id:)` — a restarted banner can no longer be hidden by its cancelled predecessor.
- (b) `canRestart` is now a **stored observed** property (was computed off `@ObservationIgnored
  overTime`, so the RUN AGAIN gate never triggered a re-render); updated edge-triggered in the
  frame loop, reset in startRun/revive/returnToMenu. Also exposed observed
  `restartCountdown: Int` (whole seconds until unlock, 0 when ready). The "READY…" label itself
  lives in **GameOverView (meta-owned)** — see TODOs.
- (c) Mute/pause cluster anchored top-**trailing** (was floating top-centre); HUD right column
  starts 38 pt lower to clear it.
- (d) Haptics: `prepare()` warms **all six** generators; `tick(dt, playing:)` re-prepares every
  6 s during live play only (GameView passes `mode == .play && !paused`). `.slid` → medium 0.7;
  `.worldChanged` → rigid double-tap (1.0 now, 0.6 echo after 120 ms via a `@MainActor` Task —
  UIFeedbackGenerator has no pattern API); `.chronoEnded` → light 0.5.

## 8 · Pause

"tap anywhere to resume" caption added under QUIT TO MENU (the veil's tap-to-resume gesture
already existed; now it's discoverable).

---

## TODOs for the META agent

1. **Settings hooks**: `synth.musicVolume` / `synth.sfxVolume` (Float 0…1, live, clamped in the
   setters) and `haptics.enabled` (Bool) are ready on GameModel's engines. Persist them in
   `Profile` (alongside `muted`) and re-apply in `GameModel.install` next to `synth.muted =
   profile.muted`. None are persisted today.
2. **GameOverView** (deferred — not my file):
   - Replace `"READY…"` with `"READY IN \(restartCountdown)…"` using the new observed
     `GameModel.restartCountdown` (pass it in like `canRestart`).
   - The "+coins" figure (`lastCoinsEarned`) is now the per-death delta — relabel if desired
     ("+N since continue") or surface the cumulative.
3. **Shop/IAP sounds**: on StoreKit purchase success in ShopView → `model.synth.play(.purchaseChime)`
   (synth is currently `@ObservationIgnored let` on GameModel — wire a small GameModel method
   instead of reaching in, matching `buyOrEquipSkin`). `.uiTick` currently only fires via
   `GameModel.open/closeSheet`.
4. **Daily challenge entry point** (core is ready, no UI exists):
   ```swift
   var cal = Calendar(identifier: .gregorian)
   cal.timeZone = TimeZone(identifier: "UTC")!          // whole world rolls over together
   let c = cal.dateComponents([.year, .month, .day], from: Date())
   model.startRun(seed: DailyChallenge.seed(year: c.year!, month: c.month!, day: c.day!))
   ```
   `GameModel.startRun(fromWorld:seed:)` already accepts the seed. `layoutVersion` is 1 — bump it
   whenever spawner/pattern/RNG-consumption changes (goldens pinned in `DailyChallengeTests`).
   Daily runs are seeded but otherwise normal: scores submit to GC (fromWorld 0 ⇒ not checkpoint).
5. **Audio agent cleanup**: `SynthEngine.playSFX(_ samples:)` has zero call sites — delete when
   convenient. Consider dedicated chrono pickup/restore SFX (I reused `.frenzyEnd`/`.frenzyStart`).
6. **Mac-build verification** (Linux can't type-check UIKit/RealityKit): hourglass winding,
   splitBar child placement/gap readability, chrono FOV dip feel, the haptic double-tap Task under
   Swift 6 `complete`, and the new HUD chip layout vs. the relocated corner buttons.
