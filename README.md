<div align="center">

<img src="docs/screenshots/00_icon.png" width="120" alt="Prism Rush icon">

# PRISM RUSH ⚡ — Native iOS

**A neon, three-world, three-lane hyperspeed endless runner for iPhone.**
Swipe lanes, jump, slide. Chain gem streaks, thread near-misses, dodge moving walls.
Every mesh, every sound, and even the app icon is **generated in code** — zero binary assets.

Built with **Swift 6 · SwiftUI · RealityKit**, ground-up by [Claude Code](https://claude.com/claude-code).

</div>

---

## What it is

Prism Rush is a native port of a shipped Three.js web prototype, rebuilt as a real iOS game. A tiny
glowing slime rides a three-lane track that accelerates the longer you survive. Collect gems to build a
streak multiplier (×1 → ×5), squeeze past tall blocks for **CLOSE** bonuses, slide under bars for
**SLICK** ones, and grab Shield / Magnet pickups. Three worlds — Neon Metropolis, Crystal Caverns,
Solar Sands — crossfade around you every 800 m, then loop back harder.

The interesting part isn't the game; it's how it's built. The entire simulation is a **pure,
deterministic, renderer-agnostic Swift core** driven by a fixed 1/120 s timestep. Because a single seed
fully determines a run, the spawner is **provably fair**: an automated bot clears 6,000 m on 200 distinct
seeds with **zero unavoidable deaths**, enforced as a unit test.

---

## Walkthrough

Every screenshot below is the **actual app running on an iPhone 17 Pro simulator**, driven end-to-end by
the in-engine autopilot (the same bot used in the solvability tests) — real frames, real score, real
collisions.

<table>
<tr>
<td align="center"><img src="docs/screenshots/01_menu.png" width="210"><br><sub><b>1 · Title</b><br>Neon skyline + world select</sub></td>
<td align="center"><img src="docs/screenshots/02_metropolis.png" width="210"><br><sub><b>2 · Neon Metropolis</b><br>Magenta grid, emissive towers</sub></td>
<td align="center"><img src="docs/screenshots/03_caverns.png" width="210"><br><sub><b>3 · Crystal Caverns</b><br>World banner + crossfade + CLOSE near-miss</sub></td>
</tr>
<tr>
<td align="center"><img src="docs/screenshots/04_sands.png" width="210"><br><sub><b>4 · Solar Sands</b><br>Amber dunes + pyramids (24,970)</sub></td>
<td align="center"><img src="docs/screenshots/05_game_over.png" width="210"><br><sub><b>5 · Shatter</b><br>Score freezes, new best</sub></td>
<td align="center"><img src="docs/screenshots/00_icon.png" width="210"><br><sub><b>Icon</b><br>1024² Core Graphics, no text</sub></td>
</tr>
</table>

> The three worlds **crossfade around the player** every 800 m, then loop with rising difficulty —
> each with its own palette, obstacle tints, and decor silhouette, all from the same code.

---

## Free-to-play systems

A full meta-game on top of the runner — currency, a shop, customizable characters, world
checkpoints, secure accounts, and friends competition — driven by an `@Observable` `ProfileStore`
(persists to UserDefaults and **iCloud** key-value sync, so saves follow you across devices).

<table>
<tr>
<td align="center"><img src="docs/screenshots/11_characters.png" width="200"><br><sub><b>Characters</b><br>Buy/equip 7 procedural skins with coins</sub></td>
<td align="center"><img src="docs/screenshots/12_shop.png" width="200"><br><sub><b>Shop</b><br>StoreKit 2 IAP — coin packs, Double Coins, premium skin</sub></td>
<td align="center"><img src="docs/screenshots/13_worlds.png" width="200"><br><sub><b>Worlds</b><br>Checkpoint start from any reached world</sub></td>
</tr>
<tr>
<td align="center"><img src="docs/screenshots/14_profile.png" width="200"><br><sub><b>Profile</b><br>Sign in with Apple · stats · friends leaderboard</sub></td>
<td align="center"><img src="docs/screenshots/10_slide.png" width="200"><br><sub><b>Slide</b><br>Pancake-lean pose + ground dust + SLICK bonus</sub></td>
<td valign="center"><sub>• Coins earned per run (gems + distance, ×2 with Double Coins)<br>• Game Center leaderboard `prismrush.best`<br>• Sign in with Apple + iCloud save sync<br>• Data-driven catalogs (skins / IAP) — easy to extend<br>• 1024² code-generated app icon, zero asset files</sub></td>
</tr>
</table>

> **Developer-ready, not yet live:** all of this is fully coded, built and tested. *Activating* real
> money and accounts needs your Apple Developer account — see **Shipping** below.

---

## Architecture

```
                input (swipe / tap)            SceneEvents.Update (per frame, wall-clock dt)
                       │                                     │
                       ▼                                     ▼
   ┌──────────────────────────────┐   snapshot   ┌────────────────────────────┐
   │  Core/  (pure Swift)          │ ───────────▶ │  Render/  RealityKit        │
   │  • GameCore  (1/120 s tick)   │              │  • RealityRenderer          │
   │  • Spawner + 11 patterns      │   FXEvent    │  • EntityPools (by kind)    │
   │  • Collisions (pure preds)    │ ───────────▶ │  • ProceduralMesh           │
   │  • SplitMix64 RNG (seeded)    │              │  + UI/ SwiftUI HUD/overlays │
   │  • Autopilot (greedy bot)     │              │                            │
   └──────────────────────────────┘              └────────────────────────────┘
        no UIKit / RealityKit imports        RendererPort is the only seam between them
```

- **`Core/`** never imports a renderer; the renderer never owns game state. They meet at one protocol,
  `RendererPort { sync(GameSnapshot); fire(FXEvent) }`. The core hands the renderer an immutable
  per-frame `GameSnapshot` (pooled entity ids, player pose, world-blend, score) and emits one-shot
  `FXEvent`s for juice.
- **Fixed timestep, interpolated render.** `advance(realDt:)` accumulates wall-clock time and steps the
  sim in exact 1/120 s ticks, so physics is identical at 60 Hz or 120 Hz and fully reproducible.
- **Pooling everywhere.** The core caps live entities; the renderer maps stable ids to recycled
  `ModelEntity`s — no per-frame spawn/despawn churn.

```
PrismRush/
  App/      SwiftUI entry + root            Render/Reality/  RealityRenderer, EntityPools, ProceduralMesh
  Core/     GameCore, Spawner, Patterns,    UI/              GameView, HUD, Menu, GameOver, Theme
            Tuning, RNG, Collisions,        Services/        (Persistence, GameCenter, Haptics — WIP)
            Autopilot, Models               Support/         entitlements, PrivacyInfo.xcprivacy
Tests/      RNG · Collision · Difficulty · SolvabilityBot     Tools/  build / qa / screenshots / gen_icon
```

---

## Technical deep-dive

**The hardest decision was making the spawner provably solvable instead of hoping it was.** An endless
runner that occasionally spawns an unavoidable wall feels broken, but you can't manually test infinite
procedural content. The fix falls out of the architecture: because the core is deterministic and seed-
driven, "is every pattern survivable?" becomes a *testable* question. A greedy `Autopilot` plays the game
from the core's public state — steer toward the emptiest lane, jump lows, slide/air-slam bars, predict
moving-wall arrival positions — and a unit test runs it across 200 seeds to 6,000 m and asserts **zero
deaths**. Getting there took five trace-driven autopilot fixes, each found by dumping the last ~44 ticks
before a death: a jump's arc spans ~27 units at top speed (so the bot air-slams to recover), a tall still
inside `|z| < 0.95` after passing still blocks its lane (don't drift into a just-passed wall), never cross
*through* a lane whose tall is in its kill band, and stay put unless a threat is actually bearing down.

The alternative — hand-authoring "safe" patterns and eyeballing them — was rejected because it doesn't
scale to the looping difficulty curve and can't catch the emergent cases where two independently-fair
patterns abut at the minimum gap and become a trap. The bot finds those.

Two more details worth calling out: collision logic is extracted into **pure predicates**
(`lowHit`, `barHit`, `gemPickup`, …) so exact boundary thresholds are unit-tested in isolation from the
running sim; and the renderer uses **`UnlitMaterial` exclusively**, which means custom meshes
(octahedron gems, torus magnets, pyramids) need only positions + triangle indices — no normals, no
lighting setup — built at runtime via `MeshDescriptor`.

Everything compiles under **Swift 6 strict concurrency (`complete`)**, including the RealityKit update
loop (the `SceneEvents.Update` handler runs on the main thread but isn't statically isolated, so its body
is wrapped in `MainActor.assumeIsolated`).

---

## Build & run

Requires Xcode 26+, an iOS 18+ simulator, and [`xcodegen`](https://github.com/yonsm/XcodeGen).

```bash
brew install xcodegen
git clone https://github.com/rayancheca/prism-rush-ios
cd prism-rush-ios

./Tools/build.sh        # xcodegen generate + xcodebuild (Simulator)
./Tools/qa.sh           # build → install → launch → screenshot
```

Watch the engine play itself (used for the screenshots above):

```bash
SIMCTL_CHILD_PR_AUTOPLAY=1 xcrun simctl launch booted com.rayancheca.prismrush
```

Run the test suite (26 tests incl. the 200-seed solvability bot):

```bash
xcodebuild test -project PrismRush.xcodeproj -scheme PrismRush \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' CODE_SIGNING_ALLOWED=NO
```

Device builds / App Store archiving need an Apple Developer **Team ID** in `project.yml`
(`DEVELOPMENT_TEAM`); simulator builds need nothing.

---

## Status

Built phase-by-phase, each gate verified by a real build + on-device screenshot (see `state.md`).

| Phase | | |
|---|---|---|
| 0–1 | Scaffold, contracts, RealityView | ✅ |
| 2 | Deterministic core + tests (26 green, 200-seed bot) | ✅ |
| 3 | Gray-box playable (renderer, input, HUD, menu, game-over) | ✅ |
| 4 | Art pass — 3-world crossfade, per-world decor, character, procedural meshes | ✅ |
| 5 | Juice — pooled particles, screen shake, score popups, world banner, haptics | ✅ |
| 6 | Synthesized 132 bpm synthwave + SFX (AVAudioEngine), best-score/mute persistence | ✅ |

**Free-to-play expansion**

| | | |
|---|---|---|
| E1 | Slide animation (pancake lean + ground dust) | ✅ |
| E2 | Coin economy + `Profile`/`ProfileStore` (UserDefaults + iCloud sync) | ✅ |
| E3 | Menu hub + character select (buy/equip 7 procedural skins) | ✅ |
| E4 | Shop + StoreKit 2 IAP (`Products.storekit` local config) | ✅ |
| E5 | World checkpoints / level select (start from any reached world) | ✅ |
| E6 | Sign in with Apple + Game Center friends leaderboard | ✅ |
| — | Soak hardening · App Store archive · live IAP/accounts | ⏳ needs your Apple account |

## Shipping (your Apple Developer account)

Everything above builds, runs and tests on the simulator with no signing. To go live you (the
account holder) do these once — the code is already wired for them:

1. **Team ID** → `project.yml` `DEVELOPMENT_TEAM`.
2. **Capabilities** (Signing & Capabilities, and on developer.apple.com): In-App Purchase, Sign in
   with Apple, Game Center, iCloud (Key-Value storage).
3. **App Store Connect**: create the app record (bundle `com.rayancheca.prismrush`); add the 5 IAP
   products from `Products.storekit`; create leaderboard **`prismrush.best`**; check the name "Prism
   Rush" is available.
4. **App Privacy** answers in ASC now declare data use (Game Center identity, purchases) — no longer
   "Data Not Collected".
5. `xcodebuild archive` + `-exportArchive` (`method: app-store-connect`) and upload.

> Everything you hear is synthesized at runtime with AVAudioEngine — a 132 bpm synthwave bed
> (kick / hi-hat / saw bass / per-world arp) plus every SFX, still zero asset files. Next: soak
> hardening and the App Store archive (icon and metadata are already generated).

<div align="center"><sub>Built with Claude Code. No third-party runtime dependencies.</sub></div>
