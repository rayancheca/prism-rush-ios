# PRISM RUSH — Build State

> Single source of truth for session resumability. On any fresh session: read this first, then continue.
> Last updated: end of Phase 1.

## Current phase
**Phase 1 COMPLETE → entering Phase 2 (GameCore + tests).**

## Environment (probed Phase 0)
| Fact | Value |
|---|---|
| Xcode | 26.5 (17F42), iOS 26 SDK |
| Swift | 6.3.2 — language mode 6, strict concurrency `complete` |
| xcodegen | 2.45.4 (Homebrew 5.1.14) |
| Repo root | `~/Desktop/ClaudeProjects/projects/prism-rush-ios` (git initialized) |
| **Primary dev/QA sim** | **iPhone 17 Pro · iOS 26.5 · UDID `10C15FE0-3D9A-40D5-9E45-C0702E906DF3`** |
| 6.9" screenshot sim | iPhone 17 Pro Max · iOS 26.5 · UDID `52DF5467-1BF8-40B2-BD4D-8EEECA9062DF` |
| fastlane / xcbeautify | absent (both optional; fastlane lane is conditional in Phase 8) |

**Deviation from directive:** scripts originally targeted "iPhone 16 Pro" which does **not** exist on this
machine. All tooling now targets **iPhone 17 Pro (iOS 26.5)**. Override via `PR_SIM_NAME`/`PR_SIM_OS`/`PR_SIM_UDID` env vars.

## Completed checklist
- [x] Phase 0: environment probed, sim chosen, git init, directory tree created.
- [x] Phase 1: `project.yml`, app shell, load-bearing contracts (`Tuning`, `Models`, `RendererPort`),
      placeholder `RealityView` with a spinning neon `ModelEntity`.
- [x] `xcodegen generate` + `xcodebuild build` → **BUILD SUCCEEDED**, 0 errors / 0 warnings, Swift 6 strict.
- [x] Installed + launched on simulator, screenshot captured & visually verified:
      `reports/shots/phase1_placeholder.png` (neon prism + title render correctly).
- [ ] Phase 2 … (next)

## Next 3 actions
1. **Phase 2 — GameCore:** write `RNG.swift` (SplitMix64), `GameCore.swift` (fixed-timestep tick),
   `Spawner.swift`, `Patterns.swift` (11 patterns) — pure Swift, Foundation only, deterministic via seed.
   Port logic verbatim from the reference Three.js prototype (locked numbers in PROMPT.md).
2. **Phase 2 — Tests:** `RNGTests` (seed→identical 10k-tick hash), `CollisionTests` (boundary tables),
   `DifficultyTests` (monotonic speed/gap), `SolvabilityBotTests` (greedy bot, 200 seeds × 6000m, zero deaths).
   Gate: `xcodebuild test` green.
3. **Parallel (background subagents, build-safe tracks only):** `docs-aso` (Store/metadata.md, README) and
   `tooling` (Tools/gen_icon.swift, screenshots.sh). These produce non-app-compiled artifacts → no build risk.

## Decision log
- **Renderer = RealityKit (RealityView, non-AR).** Probed in Phase 1: `RealityView`, `PerspectiveCamera`,
  `UnlitMaterial(color:)`, `MeshResource.generate{Box,Sphere,Plane}`, `content.entities.first(where:)` all
  compile & render on iOS 26.5 sim. **Plan B (SceneKit) NOT triggered.** Risk now low.
- **Animation driver probe deferred:** Phase 1 placeholder uses `TimelineView(.animation)` (bulletproof).
  The real loop (Phase 3) will use `content.subscribe(to: SceneEvents.Update.self)` per the directive —
  probe that subscription/retention pattern at the very start of Phase 3 before building on it.
- **Code signing:** Simulator builds run with `CODE_SIGNING_ALLOWED=NO`; `DEVELOPMENT_TEAM` left blank.
  Real signing is a Phase 8 human gate.
- **Audio sequencing:** kept in **Phase 6** (not drafted into the app target during Phase 2) so each commit
  stays green — audio Swift would otherwise enter the `sources: [PrismRush]` glob and couple the test build
  to audio correctness. docs/tooling parallelize safely because they are not compiled into the app.

## Blockers
- None.

## HUMAN GATES (do not fake — flagged for the operator)
- [ ] Paste Apple Developer **Team ID** into `project.yml` `DEVELOPMENT_TEAM` before archiving (Phase 8).
- [ ] Create App Store Connect app record + Game Center leaderboard **`prismrush.best`** (Phase 8).
- [ ] Name-availability check for **"Prism Rush"** on the App Store (Phase 8).
- [ ] The actual signed upload to App Store Connect (Phase 8).

## Commit log (every commit builds)
- `phase1`: scaffold + contracts + verified placeholder RealityView. BUILD SUCCEEDED, screenshot verified.
