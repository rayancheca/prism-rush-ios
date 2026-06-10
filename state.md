# PRISM RUSH — Build State

> Single source of truth for session resumability. On any fresh session: read this first, then continue.
> Last updated: end of Phase 2.

## Current phase
**Phase 2 COMPLETE → entering Phase 3 (gray-box playable).**

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

## Next 3 actions (Phase 3 — gray-box playable)
1. **Render/Reality/** — `RealityRenderer: RendererPort` + `EntityPools` (pool ModelEntity primitives per
    kind, track by snapshot id), virtual camera follow, player rig (body + squash/stretch + bank), scrolling
    grid/ground/backdrop. Drive loop from `content.subscribe(to: SceneEvents.Update.self)` →
    `core.advance(realDt:)` → `renderer.sync(snapshot)`. (Probe the subscribe/retention pattern first.)
2. **UI/** — `GameView` (hosts RealityView + overlays + DragGesture swipe/tap input, 22pt threshold),
    `HUDView` (live score/gems/mult), `MenuView`, `GameOverView`, `Theme` (world palettes).
    Wire `RootView` → `GameView`; delete the Phase-1 placeholder.
3. **QA gate** — add a `PR_AUTOPLAY` env flag (reuses `Autopilot`) so gameplay can be screenshotted
    deterministically on the sim without manual gestures. Screenshot menu + play + game-over; READ them.

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
