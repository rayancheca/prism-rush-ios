# PRISM RUSH — Build State

> Single source of truth for session resumability. On any fresh session: read this first, then continue.
> Last updated: end of Phase 6.

## Current phase
**Base game (Phases 0–6) COMPLETE + pushed. Now in the FREE-TO-PLAY EXPANSION (user-requested).**

### F2P expansion plan & progress (post-base-game)
- [x] **E1 Slide animation** — `snapshot.sliding/grounded`; renderer does a forward-lean pancake + ground
      dust. Screenshot-verified (was indistinguishable before).
- [x] **E2 Economy foundation** — `Meta/`: `Profile` (Codable: coins/stats/unlocks/skins/progression/IAP),
      `ProfileStore` (@Observable, UserDefaults + iCloud KVS sync), `SkinCatalog` (7 procedural skins).
      Coins earned at run end (gems + distance/50, ×2 if doubleCoins), shown on game-over + menu, persisted
      across launches (verified). Best score migrated into the profile. Renderer applies the selected skin.
- [x] **E3** — menu hub (PLAY + Characters/Shop/Worlds nav) + Character-select grid (procedural skin
      previews, buy/equip with coins, equipped state). `MetaScreenScaffold`/`CoinBadge`/`CharacterSwatch`
      shared chrome. `PR_SCREEN` debug flag opens a sheet for screenshots. Both screenshot-verified.
- [ ] **E4** — Shop + StoreKit 2 IAP (coin packs, double-coins, bundles) + a `.storekit` test config.
- [x] **E5a** — Level select / checkpoint start: `GameCore.startRun(startDistance:)` begins at a reached
      world's difficulty/palette while `scoreOffset` keeps score & coins counting from zero. `LevelSelectView`
      grid (per-world color, "Nm in", furthest highlighted). `PR_DEMOPROFILE` debug seeds progression for
      screenshots. Verified (7 worlds shown).
- [ ] **E5b** — more in-run power-ups (2× coins pickup) + wire permanent double-coins.
- [ ] **E6** — Accounts: Sign in with Apple + Game Center friends/leaderboards.
- [ ] **E7** — Profile/stats screen + polish; privacy manifest update; ship prep.

> NEW HUMAN GATES (Apple Developer account): enable capabilities **iCloud (KV)**, **Sign in with Apple**,
> **Game Center**, **In-App Purchase**; create IAP products in App Store Connect; sign + upload.

## Base-game phase (original 8-phase plan)
**Phase 6 COMPLETE → Phase 7 (QA soak) / Phase 8 (ship) remain for the base game.**

## Environment (probed Phase 0)
| Fact | Value |
|---|---|
| Xcode | 26.5 (17F42), iOS 26 SDK |
| Swift | 6.3.2 — language mode 6, strict concurrency `complete` |
| xcodegen | 2.45.4 (Homebrew 5.1.14) |
| Repo root | `~/Desktop/ClaudeProjects/projects/prism-rush-ios` (git) |
| **Primary dev/QA sim** | **iPhone 17 Pro · iOS 26.5 · UDID `10C15FE0-3D9A-40D5-9E45-C0702E906DF3`** |
| 6.9" screenshot sim | iPhone 17 Pro Max · iOS 26.5 · UDID `52DF5467-1BF8-40B2-BD4D-8EEECA9062DF` |
| fastlane / xcbeautify | absent (both optional) |

**Deviation:** scripts target **iPhone 17 Pro (iOS 26.5)** — "iPhone 16 Pro" from the directive does not
exist here. Override via `PR_SIM_NAME`/`PR_SIM_OS`/`PR_SIM_UDID`.

## Completed checklist
- [x] **Phase 0** — env probed, sim chosen, git init, tree created.
- [x] **Phase 1** — project.yml, app shell, contracts (`Tuning`/`Models`/`RendererPort`), spinning-neon
      `RealityView` placeholder. BUILD SUCCEEDED, screenshot-verified (`reports/shots/phase1_placeholder.png`).
- [x] **Phase 2** — full deterministic `Core/`: `RNG` (SplitMix64), `GameCore` (1/120 fixed-timestep tick),
      `Spawner`, `Patterns` (11, verbatim), `Collisions` (pure predicates), `Autopilot` (greedy bot).
- [x] Tests: `RNGTests`(5) determinism+reproducibility, `CollisionTests`(14) boundaries,
      `DifficultyTests`(4) monotonic speed/gap+gating, `SolvabilityBotTests`(1) **200 seeds × 6000m, 0 deaths**.
      `xcodebuild test` → **26 tests, 0 failures**.
- [x] Parallel deliverables: `Store/metadata.md` (within all char limits), `Store/icon_1024.png`
      (verified 1024×1024 opaque neon prism-slime), `Tools/{gen_icon.swift,screenshots.sh,ci.sh}`.
- [x] **Phase 3** — `RealityRenderer: RendererPort` + `EntityPools`, virtual camera follow + speed-FOV,
      player rig (squash/stretch + bank), scrolling neon grid/ground/backdrop. SwiftUI `GameView` drives the
      loop via `SceneEvents.Update` → `core.advance` → `renderer.sync`. HUD/Menu/GameOver overlays,
      DragGesture swipe/tap input. `PR_AUTOPLAY`/`PR_DEMO` env flags drive the Autopilot for deterministic
      screenshots. BUILD SUCCEEDED; all 26 tests green; menu/play/game-over screenshot-verified
      (`reports/shots/phase3_{menu,play,over2}.png`). Score-freeze bug found-by-screenshot and fixed.

- [x] **Phase 4** — world crossfade (palettes/obstacle tints/grid/backdrop from `worldFrom/To/blend`),
      `WorldDecor` per-world silhouettes with horizon-swap (towers / crystals / pyramids), character face
      (eyes + pupils + blink + antenna), procedural meshes (octahedron gem, torus magnet, pyramid) via
      `MeshDescriptor`. All 3 worlds screenshot-verified with correct palettes + decor (Metropolis/Caverns/
      Sands). 26 tests green. Walkthrough README updated with 3-world shots + pushed.

- [x] **Phase 5** — pooled CPU `ParticleSystem` (trail, gem bursts, landing dust, death shatter, shield/
      pickup pops) driven by `fire(FXEvent)`; screen shake (decay 2.2/s, off the follow position, Reduce-
      Motion gated); SwiftUI `EffectsOverlay` (rising score popups, CLOSE/SLICK near-miss text, world banner,
      white flash frames); `Haptics` service (UIFeedbackGenerator map). All screenshot-verified (trail +
      shatter + banner + CLOSE all captured). 26 tests green.

- [x] **Phase 6** — `Synth` (pure-Foundation DSP, unit-tested), `SynthEngine` (AVAudioEngine: 10-node SFX
      pool + ducked music mixer, `.ambient` session), `Music` (contiguous 8th-note step buffers → sample-
      accurate, no wall-clock drift; refilled + faded from the game loop), `Persistence` (best + mute).
      SFX/music routed from `GameModel.handleFX`; mute button + persisted best score wired. `SynthTests`
      green; all SFX/music rendered to `reports/audio/*.wav` and verified (correct durations + non-silent).

## Next 3 actions (Phase 7 — QA soak / Phase 8 — ship)
1. **Soak** — 15-min autoplay run; assert bounded live entity count each minute (no leaks/growth trend) and
    no AVAudioEngine stalls in logs. Write `reports/SOAK.md`.
2. **Ship — icon/screenshots** — wire `Store/icon_1024.png` into an `AppIcon.appiconset`; capture App Store
    screenshots at 6.9" (17 Pro Max) via `Tools/screenshots.sh` (6.5" sim absent — flag).
3. **Ship — archive** — `xcodebuild archive` + `-exportArchive` (method app-store-connect) with an export
    options plist. HUMAN GATES: Team ID, ASC app record + Game Center leaderboard `prismrush.best`, name
    availability, signed upload. (GameCenterService still TODO — lazy auth on first game-over.)

## Resolved polish backlog
- Gems are now octahedrons, magnet a torus (procedural meshes). ✓
- Wind/speed lines (above speed 22) — deferred minor polish (not yet implemented).
- Floating popups use an approximate lane→screen mapping (not full 3D projection) — acceptable.

## Decision log
- **Renderer = RealityKit** (Plan B / SceneKit NOT triggered; RealityView surface verified in Phase 1).
- **Phase-3 loop driver:** `SceneEvents.Update` subscription per the directive — probe its Swift-6
  closure-isolation (likely needs `MainActor.assumeIsolated`) at the start of Phase 3.
- **`PRODUCT_NAME` = `PrismRush`** (no space) + `CFBundleDisplayName = "Prism Rush"`. The spaced product
  name broke `TEST_HOST` derivation; this also removes spaces from all script paths.
- **Autopilot tuning (5 fixes, each found via a death-trace ring buffer; bot is test-only + future autoplay):**
  1. Air-slam bars when airborne (slide gated on grounded → couldn't duck a bar mid-jump).
  2. Air-slam to recover after any jump — a jump arc spans ~27 units at top speed and would land on the
     next obstacle.
  3. `blockedNow` lanes: a tall still in `|z|<0.95` after passing (arrival ∈ (-1.3,1.0)) still blocks its
     lane — don't drift into a just-passed tall.
  4. Transit guard: never cross THROUGH a lane whose tall is in/entering its kill band.
  5. Stay-unless-forced: only leave the current lane when a tall bears down within 15 units — don't chase a
     far-future-optimal lane into a nearer low.
- **Audio** stays Phase 6 (keeps each commit's app build green; audio is not yet in the `sources` glob).
- **RealityView content type = `RealityViewCameraContent`** (module `_RealityKit_SwiftUI`), make closure is
  `@MainActor @Sendable (inout RealityViewCameraContent) async`. The loop's `SceneEvents.Update` handler runs
  on the main thread but isn't statically isolated → wrap its body in `MainActor.assumeIsolated`. Verified.
- **Score freezes at death** (`die()` captures it; `tick()` only advances it while `.play`) — post-death
  decel keeps `distance` climbing and was otherwise inflating the score past the locked best.

## Blockers
- None.

## HUMAN GATES (do not fake — for the operator)
- [ ] Apple Developer **Team ID** → `project.yml` `DEVELOPMENT_TEAM` before archiving (Phase 8).
- [ ] App Store Connect app record + Game Center leaderboard **`prismrush.best`** (Phase 8).
- [ ] Name-availability check for **"Prism Rush"** (flagged by docs-aso; Phase 8).
- [ ] The actual signed upload (Phase 8).

## Commit log (every commit builds)
- `phase1`: scaffold + contracts + verified placeholder RealityView.
- `phase2`: deterministic Core + full test suite green (26 tests; 200-seed solvability bot).
- `phase3`: RealityKit renderer + SwiftUI shell, gray-box playable. menu/play/over screenshot-verified.
- `phase4-wip`: procedural meshes (octahedron gem, torus magnet, pyramid) via MeshDescriptor; walkthrough
  README + `docs/screenshots/`; pushed to GitHub (rayancheca/prism-rush-ios, public).
- `phase4`: world crossfade + WorldDecor (horizon-swap) + character face. All 3 worlds screenshot-verified;
  README updated with 3-world walkthrough.
- `phase5`: juice — pooled particles, screen shake, score popups, world banner, flash, haptics.
  Banner+near-miss+crossfade hero shot captured; README refreshed.
- `phase6`: synthesized audio (Synth/SynthEngine/Music) + Persistence (best/mute) + mute button. SFX/music
  rendered to reports/audio/*.wav and verified; SynthTests green (29 tests total).

## Note on running tests
NEVER drive screenshots / `simctl launch` on the dev sim (10C15FE0) while `xcodebuild test` runs on it —
concurrent app installs crash the test host and report a false "TEST FAILED" (the suite itself is fine).
