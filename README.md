# PRISM RUSH — Native iOS ⚡

A neon, three-world, three-lane hyperspeed endless runner for iPhone. Swipe lanes, jump, slide.
Gem streak multipliers, near-miss bonuses, shield & magnet pickups, worlds that crossfade around
the player, fully synthesized music & SFX, haptics, and a Game Center leaderboard.

**Zero binary assets.** Every mesh, particle, sound, and the app icon is generated in code.

> Native port of a shipped Three.js web prototype. The web build's tuned gameplay numbers are
> treated as ground truth. Full design spec lives in `PROMPT.md`.

## Stack

- **Swift 6** (strict concurrency `complete`), **SwiftUI** app shell, **iOS 18.0+**
- **RealityKit** (`RealityView`, non-AR virtual camera, programmatic `ModelEntity` primitives,
  `UnlitMaterial`-dominant neon look, `ParticleEmitterComponent`)
- **AVAudioEngine** for fully synthesized music + SFX (no audio files)
- **CoreHaptics**, **GameKit** (leaderboard), **UserDefaults** (best score, mute)
- No third-party SPM dependencies.

## Architecture

`Core/` is pure, deterministic, renderer-agnostic Swift (Foundation only) driven by a fixed
**1/120 s** timestep with an accumulator; rendering interpolates. A seeded RNG makes every run
reproducible — which is what makes the test suite (including a 200-seed solvability bot) possible.
The renderer talks to the core through a single `RendererPort` seam, so the RealityKit adapter can
be swapped for a SceneKit fallback without touching gameplay.

```
PrismRush/
  App/      SwiftUI entry + root view
  Core/     GameCore, Spawner, Patterns, Tuning, RNG, Models   (no renderer imports)
  Render/   RendererPort + RealityKit adapter, entity pools, world decor
  UI/       HUD, menu, game-over, score popups, theme
  Audio/    SynthEngine, Music
  Services/ Persistence, GameCenter, Haptics
  Support/  entitlements, privacy manifest
Tests/      Core unit tests (RNG, collisions, difficulty, solvability bot)
Tools/      build / qa / screenshots / icon generation
```

## Build & run

```bash
brew install xcodegen          # one-time
./Tools/build.sh               # xcodegen generate + xcodebuild (Simulator)
./Tools/qa.sh                  # build → install → launch → screenshot
```

Default Simulator target is **iPhone 17 Pro (iOS 26.5)**; override with `PR_SIM_NAME` / `PR_SIM_OS` /
`PR_SIM_UDID`. A real Apple Developer **Team ID** is required only for device builds and App Store
archiving (Phase 8 — see `state.md`).

## Status

Under active construction by Claude Code. Current state, phase gates, and the decision log live in
`state.md`. _(Live workflow screenshots and the technical deep-dive land in the Phase 8 docs pass.)_
