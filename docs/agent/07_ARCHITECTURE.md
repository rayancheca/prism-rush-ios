# Architecture map

Prism Rush — neon three-lane endless runner for iPhone. Swift 6 (strict concurrency `complete`),
SwiftUI + RealityKit, zero third-party dependencies, zero binary assets except one sanctioned app
icon. Surveyed at branch `claude/beautiful-davinci-797e3b`, HEAD `7e87380`.

## How to use this document

This file replaces repo exploration. Read it in step 3 of the session protocol instead of grepping
the tree; it names every directory, every seam, every long-lived type, the exact per-field shapes
that cross the Core↔Render boundary, and 100+ falsifiable invariants. It is updated when
**structure** changes — a new directory, a new type on a seam, a changed protocol, a changed
persistence key, a new invariant. It is not updated for ordinary bug fixes. **When this file and
the code disagree, the code wins**: verify against the cited `file:line`, act on the code, then fix
this file in the same session. Line numbers drift; the surrounding symbol names do not, so search
by symbol when a line does not match.

---

## 0. Shape at a glance

```
                        ┌──────────────────────────────────────────┐
                        │  App/     @main scene + test-host bypass │
                        └────────────────────┬─────────────────────┘
                                             │ constructs
                        ┌────────────────────▼─────────────────────┐
                        │  UI/GameView.swift → GameModel           │  THE HUB
                        │  owns: core, renderer, haptics, synth    │  @MainActor @Observable
                        │  drives: SceneEvents.Update frame loop   │
                        └──┬──────────┬──────────┬──────────┬──────┘
                           │          │          │          │
        ┌──────────────────▼──┐   ┌───▼──────┐ ┌─▼───────┐ ┌▼──────────────┐
        │ Core/               │   │ Render/  │ │ Audio/  │ │ Services/     │
        │ deterministic sim   │   │ RealityK │ │ synth   │ │ GC / Apple ID │
        │ 1/120 s fixed tick  │   │ pools    │ │ DSP     │ │ haptics       │
        │ SplitMix64 seeded   │   │ 12 skies │ │ AVAudio │ │ keychain      │
        │ Foundation ONLY     │   │          │ │         │ │               │
        └─────────┬───────────┘   └────▲─────┘ └─────────┘ └───────────────┘
                  │  GameSnapshot (value, per frame)  │
                  │  FXEvent      (value, per edge)   │
                  └───────────────────────────────────┘
                              RendererPort — the ONE seam

        ┌──────────────────────────────────────────────────────────────┐
        │ Meta/  Profile (44 Codable fields) + ProfileStore singleton  │
        │        economy, XP, missions, skins, cloud merge             │
        │ IAP/   StoreKit 2 wrapper + 7-SKU catalog                    │
        │ UI/    26 SwiftUI files: hub, 6 meta sheets, in-run overlays │
        └──────────────────────────────────────────────────────────────┘
```

Six lines:

1. **One isolation domain.** Every long-lived type is `@MainActor`. Zero actors, zero
   `@unchecked Sendable`, zero `nonisolated(unsafe)`, zero `DispatchQueue`, zero `Task.detached`.
   The only escape hatch is `MainActor.assumeIsolated`, exactly 9 times.
2. **One clock.** RealityKit's `SceneEvents.Update` (`GameView.swift:255`) drives everything: the
   sim, the renderer, the music pump, the effect ageing. Nothing else ticks.
3. **One seam.** `RendererPort` — `GameSnapshot` in, `FXEvent` in, nothing out. That is what makes
   the sim headless-testable on Linux with no Apple SDK.
4. **One write funnel for saves.** `ProfileStore.mutate(_:)` is the only writer of `profile`, and
   it saves to UserDefaults + iCloud KVS synchronously on every call.
5. **One determinism story, with a caveat.** A seed determines the spawn stream *for the Autopilot*;
   for a human using chrono/boost the boundary leaks (§4).
6. **Two build systems.** `project.yml`+xcodegen builds the app (70 Swift files); `Package.swift`
   compiles 18 pure files for `swift test` on Linux CI (178 tests, ~7.3 s).

### Real counts (measured at HEAD `7e87380`)

| directory | files | Swift lines | SPM-compiled? |
|---|---:|---:|---|
| `PrismRush/App/` | 2 | 32 | no |
| `PrismRush/Core/` | 10 | 1,577 | **yes, whole directory** |
| `PrismRush/Render/` | 16 | 4,758 | no |
| `PrismRush/UI/` | 26 | 8,688 | no |
| `PrismRush/Meta/` | 7 | 1,623 | **yes, all 7 named individually** |
| `PrismRush/IAP/` | 2 | 290 | no |
| `PrismRush/Audio/` | 3 | 722 | **only `Synth.swift`** |
| `PrismRush/Services/` | 4 | 308 | no |
| `PrismRush/Support/` | 2 (non-Swift) | 0 | no |
| `Tests/` | 21 | 3,493 | `Tests/CoreTests` only |
| `UITests/` | 1 | 290 | no |
| `Tools/` | 6 | 574 | no |

Production Swift total: **17,998 lines across 70 files.**

> **CLAUDE.md is stale on these numbers.** It says "12 spawn patterns" (code: 14), "95 tests
> (89 unit + 6 XCUITest)" (real: 196 = 185 unit + 11 UI), and "Core/, 4 Meta files, Audio/Synth.swift"
> (`Package.swift` lists **7** Meta files). Its *decrees and iron rules* are current and
> authoritative; its *facts* are not. Do not size a change against it.

---

## 1. Directory tour

### `PrismRush/App/` — 2 files, 32 lines

**What lives there.** The `@main` entry point and a single routing view.

**Responsible for.** Declaring the scene, forcing dark colour scheme, hiding the status bar and home
indicator, and bypassing the whole game when the app is running as the XCTest host.

**Must never.** Construct any subsystem, hold state, or grow. `RootView` observing anything would
turn `@State private var model = GameModel()` (`GameView.swift:915`) into a repeated construction
of the entire renderer + audio graph (see GOT-01).

| path | lines | responsibility |
|---|---:|---|
| `App/PrismRushApp.swift` | 13 | `@main`; one `WindowGroup` → `RootView()`, `.preferredColorScheme(.dark)`, `.statusBarHidden(true)`, `.persistentSystemOverlays(.hidden)`. |
| `App/RootView.swift` | 19 | `isUnitTesting` (static, reads `XCTestConfigurationFilePath`) → black rectangle; otherwise `GameView()`. |

### `PrismRush/Core/` — 10 files, 1,577 lines

**What lives there.** The entire deterministic simulation: fixed-timestep loop, all mutable sim
state, the seeded RNG, the 14-pattern spawn catalogue, pure collision predicates, the greedy
Autopilot bot, and the daily-challenge seed derivation.

**Responsible for.** Owning all sim state and advancing it in fixed 1/120 s steps; being the sole
consumer of randomness through one seeded `SplitMix64`; producing one immutable `GameSnapshot` per
rendered frame plus a stream of one-shot `FXEvent`s; deciding what is lethal, collectible, a
near-miss, a score, a world transition; guaranteeing the generated track is survivable (empirically,
via the bot).

**Must never.** Import a renderer, UIKit, SwiftUI, RealityKit, AVFoundation, StoreKit or GameKit
(every file is Foundation-only; `GameCore.swift` additionally imports `Observation`, which is
Linux-available). Perform a side effect — it *describes* what happened via `onFX`. Call `Date()` or
any wall clock. Use `Double.random`/`Int.random` inside the sim (the two `.random` calls are seed
*entry points*, not consumption). Change the number or order of `rng` calls in the spawn path
without bumping `DailyChallenge.layoutVersion`. Reorder the pattern catalogue.

| path | lines | responsibility |
|---|---:|---|
| `Core/GameCore.swift` | 736 | The engine. `@Observable @MainActor final class`. Fixed-timestep tick loop, all mutable sim state, spawn application, collision dispatch, scoring/economy, snapshot construction, FX emission. |
| `Core/Patterns.swift` | 192 | `SpawnCmd` enum (13 cases) + the 14-entry pattern catalogue. Each pattern appends spawns and returns its length. Ballistic `gemArc` helper. |
| `Core/Models.swift` | 142 | `GameMode`, `PickupKind`, `EntityKind`, `EntityState`, `GameSnapshot`, `NearMissKind`, `FXEvent` — the whole Core↔Render vocabulary. |
| `Core/Autopilot.swift` | 134 | `@MainActor enum`, stateless greedy bot. `decide(_:) -> Decision`, `drive(_:)` applies lane → jump → slide. Powers the solvability soak and in-app attract mode. |
| `Core/Tuning.swift` | 125 | Every gameplay constant in one `enum`. Ground truth. |
| `Core/Collisions.swift` | 95 | Pure static predicates for every hit/pickup test, extracted so they are unit-testable at boundary values. |
| `Core/Spawner.swift` | 85 | `struct`. Advances a distance cursor ahead of the player, picks a pattern index (tier-gated + anti-repeat), lays the zero-RNG gap coin trail, emits `SpawnCmd`s. |
| `Core/RNG.swift` | 34 | `SplitMix64: RandomNumberGenerator, Sendable`. `unit()`, `range`, `int`, `pick`, `chance` — each exactly one `next()`. |
| `Core/DailyChallenge.swift` | 28 | Pure `(year, month, day, layoutVersion) -> UInt64`. Domain tag `0x5052_4953_4D44_4159` = "PRISMDAY". |
| `Core/Math.swift` | 6 | `lerp`, `clampD`, `clampI` — global `@inline(__always)` funcs. |

### `PrismRush/Render/` — 16 files, 4,758 lines

**What lives there.** One protocol file plus the RealityKit adapter: scene graph, camera, character
rig, entity pools, procedural meshes, a CPU particle system, side decor, and 12 per-world sky
families (3 legacy inline + 9 `BespokeSky` classes).

**Responsible for.** Owning the entire virtual scene under one root `Entity`; translating a
`GameSnapshot` into transforms and `isEnabled` flips; translating `FXEvent`s into particle bursts,
camera impulses and pose timers; owning *all* camera behaviour (follow spring, FOV modulation, slide
dip/roll, jump lift, shake); owning the character skin pipeline; owning every piece of visual state
the core deliberately does not model (velocity estimates, gallop phase, blink clock, particle debt
accumulators, sky animation phases); honouring Reduce Motion live.

**Must never.** Mutate game state (the seam is one-directional). Consume the run RNG — every sky
family seeds a *local* `SplitMix64` from the absolute world ordinal; renderer-only `Float.random` is
allowed because it can never reach `Core/`. Derive character colour from the world (owner decree 1).
Hardcode an entity height — `s.y` is authoritative. Add binary assets: every mesh is a
`MeshDescriptor`, every material an `UnlitMaterial`. Rebuild the character rig per frame. Move the
backdrop plane off `z = -65`. Let a sky family read `Date()` or the run clock for its cadence.

| path | lines | responsibility |
|---|---:|---|
| `Render/RendererPort.swift` | 15 | The single `@MainActor` protocol seam: `sync(GameSnapshot)` + `fire(FXEvent)`. |
| `Render/Reality/RealityRenderer.swift` | 1,106 | The whole RealityKit adapter: scene graph, camera, character rig + skin pipeline, world palette materials, pooled placement, FX dispatch, per-frame visual clock. |
| `Render/Reality/WorldDecor.swift` | 848 | `WorldDecor` (28 side-of-track scenery slots that scroll + recycle) and `WorldSky` (the far-background atmosphere layer; owner/dispatcher for all 12 sky families). |
| `Render/Reality/ProceduralMesh.swift` | 303 | All code-generated `MeshResource`s + `CharacterProportions`, the shared rig/preview silhouette constants. |
| `Render/Reality/BloomfallSky.swift` | 288 | Ordinal 8 — moon + halo, hill ridge, 4 swaying blossom trees, 3 lanterns, 40 petals. |
| `Render/Reality/TempestSky.swift` | 284 | Ordinal 10 — 2 cloud ridges, haze disc, 3 lightning groups on a locally-seeded strike cadence, 40 rain streaks. |
| `Render/Reality/AshfallSky.swift` | 275 | Ordinal 5 — volcano cone, breathing lava pool + halo, 3 lava seams, 2 ash ridges, 36 embers. |
| `Render/Reality/TidalSky.swift` | 259 | Ordinal 4 — up to 3 pulsing jellyfish, 3 light shafts, seabed ridge, 32 plankton motes. |
| `Render/Reality/OrbitalSky.swift` | 257 | Ordinal 3 — planet limb, tumbling astronaut, drifting satellites with blinking nav lights, 44-star field. |
| `Render/Reality/BorealisSky.swift` | 245 | Ordinal 6 — 3–4 aurora curtains, up to 7 ice shards, snow plain ridge, 34 snowflakes. |
| `Render/Reality/EventideSky.swift` | 232 | Ordinal 9 — black-hole sphere, 2 counter-spinning accretion tori, horizon ring, 2 polar jets, 3 nebula washes, 42 stars. |
| `Render/Reality/SingularitySky.swift` | 211 | Ordinal 11 — radiant core + halo, 6 expanding spectrum rings, 8-spoke ray crown, flare chain, wash disc. |
| `Render/Reality/DatastreamSky.swift` | 201 | Ordinal 7 — baked-perspective grid wall, vanishing-point glow disc, 4 flickering pylons, 30 column motes. |
| `Render/Reality/ParticleSystem.swift` | 129 | Fixed **560**-slot CPU particle pool: unlit-sphere bursts with manual gravity + world-scroll drift, optional z-stretch streaks, per-colour material cache (bounded at 64). |
| `Render/Reality/EntityPools.swift` | 82 | Reconciles the snapshot's stable `EntityState.id` set against live `Entity`s; per-`EntityKind` free lists; no spawn/despawn churn. |
| `Render/Reality/BespokeSky.swift` | 23 | `BespokeSky` protocol (`root` / `restyle(palette:world:)` / `animate(elapsed:reduceMotion:)`) + conformances. |

### `PrismRush/UI/` — 26 files, 8,688 lines

**What lives there.** `GameModel` (the app hub — it lives inside `GameView.swift`), the root
`GameView` ZStack, every in-run overlay, the hub, six meta sheets, three sub-surfaces, two modal
overlays, the design-token file, and two procedural preview renderers.

**Responsible for.** Owning the app's single mutable hub; driving the frame loop; translating touches
into core intents; owning the run lifecycle above the core (pause, first-run gate, revive economy,
restart cooldown, challenge flag, loadout consumption); folding a finished run into the profile
exactly once per death; presenting every surface and routing between them.

**Must never.** Mutate `Core/` state outside the documented intent methods. Introduce randomness the
core consumes. Call `recordRunResults` outside the `.died` FX branch. `@State` a shared
`@Observable`, or snapshot `store.profile` into a `let` at the top of `body` (rule G3). Let banked
consumables or revives reach a Daily Rush. Show a meta sheet during `.play`. Ship a dimmed dead
control. Render `profile.selectedSkin` directly instead of `ProfileStore.equippedSkinID`. Let a
locked skin render owned-bright. Spend coins without a preview first.

| path | lines | responsibility |
|---|---:|---|
| `UI/GameView.swift` | 1,224 | **`GameModel`** (hub: engine + renderer + audio + haptics + run recording + input) **and** the root `GameView` ZStack. |
| `UI/ShopView.swift` | 822 | Storefront: hero offer slot, coin-pack 2×2 grid with computed value badges, perks, coin-spend packs + Mystery Box, characters rail, honest store-state chrome. |
| `UI/WorldPreviewCanvas.swift` | 777 | Procedural per-world vignette (chip/card/hero) — 12 bespoke sky signatures + lane grid, mirroring each world's in-game `WorldSky`. |
| `UI/LevelSelectView.swift` | 594 | Worlds ladder: PLAY-FROM-HERE header, NEXT UNLOCK strip, adaptive card grid, `PlayConfirmPanel` + `UnlockPanel` overlays. |
| `UI/CharacterSelectView.swift` | 586 | 24-page swipeable hero carousel + NEXT UNLOCK spotlight + four rarity grids; one state button per skin does equip/buy/route. |
| `UI/MissionsView.swift` | 523 | Missions board: summary strip, CLAIM ALL, four sections of `MissionCard` ring rows with claim + coin fly-up. |
| `UI/GameOverView.swift` | 476 | Death panel: score band, coin+XP earn band, stat chips, CONTINUE / RUN AGAIN / BACK TO MENU. |
| `UI/CharacterSwatch.swift` | 443 | `AnimatedCharacterSwatch` (Canvas+TimelineView procedural preview) and `CharacterHeroStage`. |
| `UI/Theme.swift` | 309 | 12 world palettes + evolution math, role palette, type scale, spacing/radius tokens, `NeonCard`, `NeonButtonStyle`, `ShakeEffect`. |
| `UI/MenuView.swift` | 301 | The hub. Five zones (status strip / hero stage / PLAY / rewards rail / nav row). Generic over its `loadout` child on purpose. |
| `UI/HowToPlayView.swift` | 289 | Five-card swipeable tutorial. Dual mode: info-only, or the pre-first-run gate whose final button commits the deferred run. |
| `UI/ProfileView.swift` | 285 | Progression home: level card + settings gear, Sign in with Apple card, three stats states, Game Center row. |
| `UI/HUDView.swift` | 272 | Non-interactive in-run readout: meters/score, ghost-chase chip, gem·mult pill, power-up chips, flow pips, live XP bar. |
| `UI/ClaimRibbon.swift` | 295 | **Replaced `RewardsBar.swift` in S-005 (PR-0452).** The hub's claim ribbon (`railRewards`: full-width gold bar when the daily bonus or free chest is claimable, slim tertiary strip when not) + `DailyRushLauncher` (`railDaily`, sits beside PLAY) + the 280 pt rewards mini-sheet. Missions moved out entirely — it is a nav-rail exit on `MenuView` now. |
| `UI/SettingsView.swift` | 242 | Three volume sliders, haptics + reduce-flash toggles, Power-Ups / How to Play / Restore Purchases rows, tappable version row. |
| `UI/MysteryBoxView.swift` | 198 | Gacha reveal overlay: honest odds table → OPEN (spend) → wobble/burst → reward. |
| `UI/EffectsOverlay.swift` | 186 | Screen-space juice: rising popups, world banner, white flash, shield-break glass crack. |
| `UI/PowerUpGlyph.swift` | 172 | `PowerUpKind` enum (10 cases, id + identity hue) and its `Canvas`-drawn procedural glyph. |
| `UI/PowerUpsView.swift` | 154 | Static reference catalog of every power-up + the CONTINUE explainer. |
| `UI/SplashView.swift` | 116 | Launch splash: wordmark drop, character flip-spin out of a shard burst, TAP TO START. |
| `UI/PackRewardBurst.swift` | 109 | Purchase reveal for coin-spend packs (ring + sparks + medallion, auto-dismiss 1,300 ms). |
| `UI/LogoMark.swift` | 107 | Procedural "PRISM RUSH" wordmark: chromatic-fringe ghosts, gradient fill, baseline wave, slant, clock-derived shimmer sweep. |
| `UI/PauseOverlay.swift` | 75 | Pause veil: RESUME (also tap-anywhere) + QUIT TO MENU. |
| `UI/MetaScreenScaffold.swift` | 60 | Shared chrome for full-screen meta sheets: back chevron, title, coin badge, scrolling content. |
| `UI/LoadoutStrip.swift` | 57 | Hub chips to arm Head Start / Coin Surge for the next run. |
| `UI/CoinBadge.swift` | 56 | `CoinBadge` (glyph + rolling amount, optionally tappable) and `CoinGlyph`. |

### `PrismRush/Meta/` — 7 files, 1,623 lines

**What lives there.** The persisted save and its store, plus every catalog and every pure economy
function.

**Responsible for.** Being the only writer of persistent player state; owning the economy end-to-end
(every faucet and sink); being pure and Linux-testable; holding catalogs as data, not code paths;
deriving rather than storing anything derivable (level from `totalXP`, coin multiplier from
`doubleCoins`, equipped skin from `selectedSkin ∩ ownedSkins`).

**Must never.** Import UIKit/RealityKit/SwiftUI (all 7 files are Foundation-only; `ProfileStore`
guards `NSUbiquitousKeyValueStore` behind `#if canImport(Darwin)`). Use the Core seeded RNG for meta
randomness. Add a `Profile` field without a default *and* a `decodeIfPresent ?? default` line.
Re-pay a cumulative reward. Fold a purchased-world start into `maxWorldReached`. Let a skin follow
the world palette. Count purchased coins as earned. `max()`-merge consumable counters.

| path | lines | responsibility |
|---|---:|---|
| `Meta/ProfileStore.swift` | 710 | `@MainActor @Observable` singleton owning the `Profile`: mutation API, whole economy, UserDefaults + iCloud KVS persistence, the pure two-way merge. |
| `Meta/SkinCatalog.swift` | 296 | The 24-character roster as pure data + the Prism shimmer clock→colour function. |
| `Meta/Profile.swift` | 172 | The persisted save: 44 `Codable` fields + the granted-transaction ledger; hand-written resilient `init(from:)`. |
| `Meta/MissionCatalog.swift` | 165 | `RunSummary`, `Mission`/`Metric`/`Scope`, the per-run/daily/weekly/achievement lists, deterministic per-day/per-week slot draws. |
| `Meta/ShopValue.swift` | 149 | StoreKit-free shop value math: pack badges, featured rotation, coin-spend catalogue + Mystery Box odds, `StoreState`. |
| `Meta/XPCurve.swift` | 96 | `LevelUpResult` + the whole progression curve: cumulative XP table, per-run XP, banded level-up grants, style coins, world price ladder. |
| `Meta/SkinUnlocks.swift` | 35 | The single place a skin's unlock requirement is evaluated (`earned`) and rendered (`requirementText`). |

### `PrismRush/IAP/` — 2 files, 290 lines

**What lives there.** The 7 real-money SKUs and the StoreKit 2 wrapper.

**Responsible for.** Turning verified transactions into profile mutations exactly once; honest
availability states.

**Must never.** Grant an entitlement from an unverified transaction (all three sites pattern-match
`case .verified`). Re-grant consumables on restore. Widen the
`Products.storekit` / `IAPCatalog` / App Store Connect ID triple — the five original IDs are frozen
character-for-character.

| path | lines | responsibility |
|---|---:|---|
| `IAP/IAPManager.swift` | 213 | `@MainActor @Observable` StoreKit 2 wrapper: product load with availability states + backoff, purchase, restore, `Transaction.updates` listener. |
| `IAP/IAPCatalog.swift` | 77 | The 7 SKUs, what each grants, and the two grant entry points (`apply` for purchases, `restore` for entitlements). |

### `PrismRush/Audio/` — 3 files, 722 lines

**What lives there.** Pure DSP (`Synth.swift`), the AVAudioEngine graph, and a sample-accurate
sequencer.

**Responsible for.** All sound, from first principles — zero audio asset files. Keeping audio alive
across interruptions/route changes/config changes. Two independent music contexts (calm hub bed vs
in-run bed) with independent sliders plus a shared SFX level and a global mute.

**Must never.** Import AVFoundation into `Synth.swift` (it is the only `Audio/` file in
`Package.swift`). Gate music *scheduling* on mute — mute is a mixer ramp, because gating scheduling
desyncs `Music.scheduledFrames`. Call `Music.reanchor()` with the engine stopped (it raises). Let an
`SFX` case render non-deterministically (each is rendered once and cached forever).

| path | lines | responsibility |
|---|---:|---|
| `Audio/Synth.swift` | 412 | Pure-Foundation DSP: renders every SFX and one music 8th-note step to `[Float]`; owns the `SFX` catalog and the 12 per-world `Bed`s. |
| `Audio/SynthEngine.swift` | 208 | `@MainActor` AVAudioEngine graph: 10 pooled SFX nodes, PCM buffer cache, master-mute ramp, `.playback` session, interruption/route/config recovery. |
| `Audio/Music.swift` | 102 | `@MainActor` sample-accurate 132-BPM sequencer: back-to-back step buffers into one player node, fade-in/out, duck envelope. |

### `PrismRush/Services/` — 4 files, 308 lines

**What lives there.** Game Center, Sign in with Apple, haptics, Keychain.

**Responsible for.** Player identity and social ranking; physical feedback from the same `FXEvent`
stream; small-secret storage.

**Must never.** Submit a checkpoint run to the global leaderboard. Make Game Center / sign-in / store
failures user-visible as errors (decree 3). Store the Apple user id in UserDefaults. Sync those
Keychain items (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, no `kSecAttrSynchronizable`).

| path | lines | responsibility |
|---|---:|---|
| `Services/AccountService.swift` | 88 | `@MainActor @Observable` singleton: Sign in with Apple, Keychain-backed user id + given name, credential-state revalidation. |
| `Services/Haptics.swift` | 88 | `@MainActor` FXEvent → `UIFeedbackGenerator` mapping, gem rate-limit, periodic generator re-prepare. |
| `Services/GameCenterService.swift` | 77 | `@MainActor @Observable` singleton: GC auth, best/daily score submission, leaderboard UI. IDs `prismrush.best`, `prismrush.daily`. |
| `Services/Keychain.swift` | 55 | Minimal generic-password get/set/delete for two short strings. |

### `PrismRush/Support/` — 2 non-Swift files

| path | responsibility |
|---|---|
| `Support/PrivacyInfo.xcprivacy` | Privacy manifest. Declares one required-reason API category (`NSPrivacyAccessedAPICategoryUserDefaults` / `CA92.1`) and an **empty** `NSPrivacyCollectedDataTypes`. Lands at the bundle root, not in `Support/`. |
| `Support/PrismRush.entitlements` | Sign in with Apple + Game Center + ubiquity-KVS. **GENERATED** by xcodegen from `project.yml`'s `entitlements.properties` — never hand-edit. |

### `Tests/` — 21 files, 3,493 lines

**What lives there.** `Tests/CoreTests/` (20 files, the SPM target, also compiled into the Xcode
unit bundle) plus `Tests/WorldPaletteTests.swift` (Xcode-only).

**Responsible for.** Proving the sim is deterministic and survivable; freezing every seeded-run
input; guarding real money and real save data; keeping the pure layers runnable anywhere.

**Must never.** Reference UIKit / SwiftUI / RealityKit / StoreKit / AVFoundation / GameKit from
`Tests/CoreTests` (the documented escape hatch is `#if canImport(UIKit)`, used by
`CharacterParityTests`). Edit a `DailyChallengeTests` golden to make a failure go away — that is a
`layoutVersion` bump, not a test edit.

Notable files: `EconomyTests.swift` (526 lines, 30 tests), `ProgressionTests.swift` (393, 15),
`PowerUpTests.swift` (278, 16), `GameplayTests.swift` (271, 12), `MissionsTests.swift` (263, 18),
`SkinCatalogTests.swift` (240, 5), `FlowTests.swift` (174, 4), `CollisionTests.swift` (173, 21),
`SynthTests.swift` (169, 10), `SolvabilityBotTests.swift` (152, 4 — 6.8 s of a 7.3 s suite),
`ShopValueTests.swift` (114, 15), `RingTests.swift` (100, 3), `ArcCollectionTests.swift` (87, 4),
`PatternOrderTests.swift` (83, 2), `DifficultyTests.swift` (67, 5), `RNGTests.swift` (65, 5),
`CharacterParityTests.swift` (48, 3 — iOS bundle only), `DailyChallengeTests.swift` (44, 3),
`SmokeTests.swift` (20, 2), `BoostTests.swift` (132, 4), `WorldPaletteTests.swift` (47, 4).

### `UITests/` — 1 file, 290 lines

`UITests/InteractionUITests.swift` — 11 XCUITests driving the real app: game-over routes, skin
equip, pause/resume/quit, revive, rewards rail, hub nav, locked-skin copy, XP line, world buy flow,
first-run tutorial gate, missions claim. **CI never runs these** (`ios-build.yml` passes
`-only-testing:PrismRushTests`); only a human running `Tools/ci.sh` executes them.

### `Tools/` — 6 files, 574 lines

| path | lines | responsibility |
|---|---:|---|
| `Tools/gen_icon.swift` | 307 | Standalone CoreGraphics script rendering the opaque 1024² icon PNG, then byte-copying it into `Assets.xcassets` (only when `outPath` is exactly `Store/icon_1024.png`). |
| `Tools/screenshots.sh` | 131 | App Store capture: boot 6.9″ (+ 6.5″ if present), install/launch, 6 named shots on fixed sleeps. **Does not drive the app** — unattended it writes 6 identical frames. |
| `Tools/render_sfx.swift` | 48 | Compiles against `Synth.swift` alone to dump 9 SFX + 3 world music bars as WAVs. Badly stale vs the current catalog. |
| `Tools/ci.sh` | 47 | Local 3-stage gate: generate ▸ `build.sh` ▸ `xcodebuild test` (whole scheme = unit **and** UI targets). |
| `Tools/qa.sh` | 23 | Visual QA loop: boot a hardcoded sim UDID, build, install, launch, sleep, screenshot into `reports/shots/`. |
| `Tools/build.sh` | 18 | `xcodegen generate --quiet` + `xcodebuild build` for `$PR_SIM_NAME`/`$PR_SIM_OS`, `-derivedDataPath .dd`, signing off. |

CI: `.github/workflows/core-tests.yml` (19 lines, `swift:6.0-noble` on ubuntu-24.04, `swift test -c
release`, every push/PR) and `.github/workflows/ios-build.yml` (65 lines, macos-15, xcodegen ▸
`build-for-testing` on a generic sim ▸ `test-without-building -only-testing:PrismRushTests` on
`iPhone 16, OS=latest`).

---

## 2. The Core↔Render seam

### The protocol, verbatim (`Render/RendererPort.swift:8-15`)

```swift
@MainActor
protocol RendererPort: AnyObject {
    /// Push the latest immutable world snapshot. Called once per rendered frame.
    func sync(_ snapshot: GameSnapshot)

    /// React to a one-shot gameplay effect (burst, world banner, death shatter, …).
    func fire(_ event: FXEvent)
}
```

**Direction.** Core → renderer only. There is no return value anywhere on the seam and nothing flows
back. Both payload types are `Sendable` value types; the protocol is whole-`@MainActor`.

**Owner.** `GameModel` holds the concrete renderer directly:
`@ObservationIgnored let renderer = RealityRenderer()` (`GameView.swift:12`).

**Not on the protocol.** `advanceVisuals(_:)`, `resetEntities()`, `applySkin(_:)` and
`install(into:)` are `RealityRenderer`-specific API the caller uses directly. A second renderer (the
documented SceneKit Plan B) would have to re-declare them. **`RendererPort` has no test double and
no test of its own.**

### Call-ordering contract (per frame, `GameView.swift:255-292`)

```
core.advance(realDt: dt)      // :280  — emits 0..n FXEvents SYNCHRONOUSLY from inside tick()
                              //         each → onFX → GameModel.handleFX → renderer.fire(fx)
renderer.advanceVisuals(dt)   // :282  — MUST run immediately before sync; sets lastDt
renderer.sync(core.snapshot)  // :283  — exactly once per rendered frame
```

Three consequences a future session must know:

1. **All of a frame's `fire()` calls happen before that frame's `advanceVisuals`/`sync`.** A frame
   with 3 catch-up ticks delivers FX three separate times before `sync` ever runs.
2. Because `fire` runs first, timers it arms (`jumpStretchT`, `landSquashT`) lose one `dt` in
   `advanceVisuals` before `sync` consumes them.
3. `advanceVisuals` reads flags that the *previous* frame's `sync` wrote (`lastSpeed`, `runBobOn`,
   `speedNorm`, `lastSliding`) — several fields are one frame stale **by design**.
   `resetEntities()` zeroes them (`RealityRenderer.swift:685`) for exactly this reason.

### `GameSnapshot` — every field (`Core/Models.swift:53-116`)

Value type, `Sendable`, **not `Equatable`** (this matters — see GOT-02).

| field | type | meaning | read by Render? |
|---|---|---|---|
| `mode` | `GameMode` | `.menu` / `.play` / `.over` | yes |
| `distance` | `Double` | **ABSOLUTE** odometer; matches world labels + the HUD meters readout | yes |
| `traveledDistance` | `Double` | metres run **this attempt** (`distance − scoreOffset`); XP / fair score | no (HUD only) |
| `speed` | `Double` | **EFFECTIVE** world speed (chrono-slowed, boost-raised) — FOV/scroll/trails | yes |
| `rampSpeed` | `Double` | raw difficulty-ramp speed, un-buffed; HUD/debug only | no |
| `playerX` | `Double` | lateral position (lerped toward `laneX[laneIndex]`) | yes |
| `playerY` | `Double` | jump height | yes |
| `playerScaleY` | `Double` | slide/squash/stretch scale | yes |
| `bankZ` | `Double` | cosmetic body lean | yes |
| `worldFrom` | `Int` | **legacy 0–2 palette family**, NOT the world | **no — deliberately ignored** |
| `worldTo` | `Int` | ditto | **no** |
| `worldBlend` | `Double` | 0 → fully `worldFrom`, 1 → fully `worldTo` | yes |
| `worldOrdinal` | `Int` | **ABSOLUTE** world index (`core.maxWorld`); what Render actually uses | yes |
| `shieldActive` | `Bool` | shield held | yes |
| `magnetRemaining` | `Double` | seconds | no (HUD) |
| `doublerRemaining` | `Double` | seconds; > 0 → gems pay double coins | no (HUD) |
| `chronoRemaining` | `Double` | seconds; > 0 → slow-mo | yes |
| `boostRemaining` | `Double` | seconds; mirrors `boostT` | yes |
| `sneakersRemaining` | `Double` | seconds; > 0 → Super Sneakers | yes |
| `flowStreak` | `Int` | near-miss count toward a surge (HUD pips show `% flowPerSurge`) | no |
| `sliding` | `Bool` | slide active | yes |
| `grounded` | `Bool` | on the floor | yes |
| `usedCheckpoint` | `Bool` | run began mid-track — meta layer must skip GC submit | no |
| `entities` | `[EntityState]` | every visible obstacle / gem / pickup this frame | yes |
| `score` | `Int` | frozen at death | no (HUD) |
| `gems` | `Int` | gems this run | no (HUD) |
| `mult` | `Int` | 1…5 | no (HUD) |
| `best` | `Int` | best score, snapshotted from the profile at launch | no (HUD) |

`GameSnapshot.initial` (`Models.swift:86`) is the menu/attract state: `.menu`, speed
`Tuning.menuSpeed`, `worldBlend 1`, `mult 1`, no entities.

### `EntityState` — every field (`Core/Models.swift:35-49`)

`Sendable, Identifiable, Equatable`.

| field | type | meaning |
|---|---|---|
| `id` | `Int` | stable **within a run**; `GameCore.nextId` resets to 0 on `reset()` |
| `kind` | `EntityKind` | see below |
| `x` | `Double` | lateral world position |
| `y` | `Double` | **authoritative height** — never re-derive (bar centre 1.3, low 0.425, tall 1.6) |
| `z` | `Double` | relative to the player. **negative = AHEAD, positive = behind** (`z = distance − d`) |
| `lane` | `Int` | −1 for full-span (bars); for a `splitBar` it is the **OPEN (safe)** lane |
| `spin` | `Double` | accumulated phase for spinning/bobbing collectibles (derived from `distance − d`, so deterministic) |
| `fading` | `Bool` | being magneted/absorbed; renderer may fade it |

### `EntityKind` — 13 cases (`Core/Models.swift:14-28`)

`low` (hop), `tall` (change lane), `movingTall` (oscillating, danger-tinted), `bar` (full-span
overhead — slide), `splitBar` (covers 2 of 3 lanes), `gem` (octahedron), `shield` (icosahedron),
`magnet` (torus), `doubler`, `chrono`, `superSneakers`, `ring` (never lethal), `boostPad` (floor
decal — grounded contact triggers overdrive).

### `PickupKind` — 5 cases (`Core/Models.swift:9-11`)

`shield`, `magnet`, `doubler`, `chrono`, `superSneakers`.

### `NearMissKind` — 2 cases (`Core/Models.swift:119-121`)

`close` (squeezed past a tall), `slick` (slid under a bar).

### `FXEvent` — all **16** cases (`Core/Models.swift:125-142`)

> The `render.md` scratch file says 17. It is **wrong** — the source has 16. Verified by reading
> `Models.swift` in full.

| case | payload | handled visually? |
|---|---|---|
| `laneChanged` | `x: Double` | yes |
| `jumped` | `x: Double` | yes (arms a 0.12 s stretch timer) |
| `landed` | `x: Double` | yes (squash) |
| `slid` | `x: Double` | yes (drops a skid) |
| `gemCollected` | `x, y: Double, streak: Int` | yes |
| `nearMiss` | `kind: NearMissKind, x: Double` | **ignored by the renderer** (`RealityRenderer.swift:569-571`) |
| `pickup` | `kind: PickupKind, x, y: Double` | yes |
| `worldChanged` | `index: Int, ordinal: Int` | yes (crossfade + banner) |
| `shieldAbsorbed` | `x: Double` | yes (glass crack) |
| `chronoEnded` | — (edge) | **ignored** — restore is snapshot-driven |
| `sneakersEnded` | — (edge) | **ignored** — snapshot-driven |
| `ringPassed` | `x, y: Double, perfect: Bool` | yes (dedicated ring-pulse torus) |
| `boostStarted` | `x: Double` | yes (FOV punch) |
| `boostEnded` | — (edge) | **ignored** — snapshot-driven |
| `flowSurge` | `level: Int, x: Double` | yes |
| `died` | `x: Double` | yes (120 skin + 60 white particles, `shake = 1.4`) |

The four ignored cases are a **deliberate design rule**: boost/sneakers/chrono *restore* is driven
from the snapshot, so a dropped edge can never strand the FOV punch or leave the boots on.

### `SpawnCmd` — all 13 cases (`Core/Patterns.swift:4-18`)

Internal to Core (never crosses the render seam), but it is the only currency between
`Patterns`/`Spawner` and `GameCore.apply`. Every case carries an absolute distance `d`.

`low(d, lane)`, `tall(d, lane)`, `movingTall(d, phase)`, `bar(d)`, `splitBar(d, openLane)`,
`gem(d, lane, y)`, `shield(d, lane)`, `magnet(d, lane)`, `doubler(d, lane)`, `chrono(d, lane)`,
`superSneakers(d, lane)`, `ring(d, lane, y)`, `boostPad(d, lane)`.

`CoreEntity` (`GameCore.swift:5`) is the internal mutable pre-snapshot record; `d` is the absolute
spawn distance and never crosses the seam.

---

## 3. The fixed-timestep simulation model

### `advance(realDt:)` — the whole thing (`GameCore.swift:158-169`)

```swift
func advance(realDt: Double) {
    // A NaN/inf/negative dt (suspend hiccups, clock jumps) must never reach the accumulator:
    // `min(NaN, 0.1)` is NaN, which then sticks and bricks the run.
    guard realDt.isFinite, realDt > 0 else { return }
    accumulator += min(realDt, 0.1)
    while accumulator >= Tuning.tickDt {
        tick(Tuning.tickDt)
        accumulator -= Tuning.tickDt
    }
    rebuildSnapshot()
}
```

| property | value / behaviour |
|---|---|
| **Tick rate** | `Tuning.tickDt = 1.0 / 120.0` exactly |
| **dt sanitation** | NaN, ±inf, 0 and negative are dropped *before* the accumulator. The early `return` also **skips `rebuildSnapshot()`** — a junk frame leaves the previous snapshot, which is correct. Pinned by `GameplayTests.testAdvanceSurvivesNaNAndJunkDt`. |
| **Long-frame clamp** | `min(realDt, 0.1)` → ceiling of **12 ticks per call**. Anything beyond 100 ms of wall clock is **discarded, not deferred** — a deliberate spiral-of-death guard. Backgrounding 5 s loses 4.9 s of simulated time; the world does not fast-forward. |
| **Leftover time** | the sub-tick remainder persists in `accumulator` across calls, so at 60 Hz the pattern is 2,2,2,2… ticks with no drift accumulation. |
| **First frame** | no special case. `accumulator` starts at 0 from `init`/`reset`. `init` calls `rebuildSnapshot()` once so `snapshot` is a valid `.menu` state before any frame. |
| **Snapshot cadence** | `rebuildSnapshot()` runs **once per `advance` call**, never inside `tick`. Bare `tick(_:)` does *not* rebuild — three test files carry an explicit comment about this (`PowerUpTests.swift:39`, `BoostTests.swift:91`). |
| **Pause/resume** | the core has **no pause concept**. `GameView.swift:262-265` returns before calling `advance` while `paused`, so no dt is accumulated at all — a perfect freeze with no catch-up burst. Music keeps pumping. |
| **`tick(_:)` visibility** | internal, not private, and accepts an arbitrary dt so tests can drive exact step counts. Production only ever passes `Tuning.tickDt`. |
| **Interpolation** | the core performs **none**. The doc comment says "rendering interpolates"; the renderer receives raw post-tick state, so any smoothing is the renderer's job. |

### Fixed tick order (`GameCore.swift:172-198`)

```
1. stepSpeedAndDistance(dt)   — ALL modes
2. stepWorld(dt)              — blend all modes; ordinal advance .play only
3. if mode == .play { spawn() }
4. stepPlayer(dt)
5. stepObstacles(dt)
6. stepGems(dt)
7. stepPickups(dt)
8. magnetT / doublerT / chronoT / boostT / superSneakersT / invulnT decay  — ALL modes,
   chrono/boost/sneakers emit their EDGE event on crossing 0
9. if mode == .play { score = Int(((distance - scoreOffset) * 2).rounded(.down)) + bonus }
```

The order is load-bearing: spawn happens *after* distance advances (so the horizon is
post-increment) and *before* collisions (so a spawn can never be hit on its spawn tick — its `d` is
at least `distance + 60`).

### What each mode does inside a tick

| step | `.menu` | `.play` | `.over` |
|---|---|---|---|
| `stepSpeedAndDistance` | lerps toward `menuSpeed = 7`; **`distance` still integrates** | lerps toward `min(33, 17 + d·0.0052)` | decelerates at `overDecel = 22`/s²; **`distance` still integrates** (~25 m of drift over ~1.4 s) |
| `stepWorld` | blend advances | blend + ordinal advance, emits `.worldChanged` | blend advances |
| `spawn()` | — | yes | — |
| `stepPlayer` / `stepObstacles` / `stepGems` / `stepPickups` | run, but every scoring/lethal branch is `mode == .play`-guarded | full | run, mode-guarded |
| buff timers | decay | decay | **decay**, emitting the three edge events |
| `score` recompute | — | yes | — (frozen by `die()`) |

**Menu drift is unbounded**: an app left on the hub accrues 7 m/s indefinitely. `startRun` resets it.

---

## 4. The determinism boundary

### Intended vs actual

**Intended** (stated in `RNG.swift:3-4` "Seed fully determines every run" and `GameCore.swift:20-21`
"a seed fully determines a run"): the seed plus `startDistance` determine everything.

**Actual**: the spawn stream is a function of

1. the seed (via `rng`), **and**
2. the sequence of `distance` values at the ticks where `cursor < distance + spawnHorizon` first
   becomes true — because `Spawner.fill` is called with `dist: distance` (the *player's* position,
   sampled that tick) and uses it for **both** `maxIndex(forDistance:)` and `gap(forDistance:)`
   (`GameCore.swift:301`, `Spawner.swift:35-48`), **and therefore**
3. transitively, on anything that changes per-tick distance increments: **`chronoT` and `boostT`**,
   i.e. player pickups and manual power-up deploys.

**Where they diverge.** Per-pattern `gap` differs by ~5e-4 m under a buff, and that drift
accumulates in `cursor`. Once accumulated drift moves a pattern across a tier boundary
(260 / 576 / 1440 / 1920 m), `maxIndex` differs, the `rng.int(0, maxIdx − 1)` draw differs, and the
whole downstream stream diverges. For the Daily Rush this means "same seed = same track" holds only
for players who use the same power-ups at the same moments.

**Why no test catches it.** The Autopilot never collects pickups — `Autopilot.Decision` has only
lane/jump/slide verbs — so the soak and hash paths never exercise chrono or boost. Every
determinism test passes. (`FlowTests.testDeterminismAndPatternStreamIsolation` proves input
isolation only for lane/jump/slide inputs, and compares `d` with a 0.6-unit tolerance.)

**Two secondary, non-RNG leaks** (they change the visible track but not the RNG stream):

- `freeLaneNear` (`GameCore.swift:320-334`) reads `activeObstacles`, which the shield-absorb path
  mutates (`GameCore.swift:410-411`) — so an absorb near a cadence mark can flip it from skipped to
  placed, shifting `powerUpIndex` and therefore the *kind* of every subsequent cadence pickup.
- The flow-surge fountain and the coin trails push `activeGems` toward `capGem = 72`; once capped,
  `apply` **silently drops** later gems (`GameCore.swift:667`) — no log, no counter, no FX.

### Complete ordered list of RNG consumption sites

Every `rng` consumption in the entire Core. Each of `int`, `pick`, `chance`, `range` is exactly one
`unit()` = one `next()`.

**Per spawner iteration** (`Spawner.fill`, one iteration per placed pattern):

| # | site | file:line | calls |
|---|---|---|---:|
| 1 | `var idx = rng.int(0, maxIdx - 1)` | `Spawner.swift:39` | 1 |
| 2 | anti-repeat reroll `if idx == lastIdx \|\| idx == prevIdx { idx = rng.int(0, maxIdx - 1) }` | `Spawner.swift:44` | 0 or 1 (**data-dependent**) |
| 3 | `Patterns.run(idx, …)` | `Spawner.swift:47` | 0–3, table below |

**Per pattern** — pinned as the vector `[1,1,0,1,1,3,1,2,0,1,1,1,2,0]` by
`PatternOrderTests.testTierLadderMonotoneAndRNGCountsPinned`:

| idx | pattern | consumption sites, in order | count |
|---:|---|---|---:|
| 0 | gem line | `rng.int(0,2)` lane | 1 |
| 1 | low + arc | `rng.int(0,2)` lane | 1 |
| 2 | triple low + arc | — | 0 |
| 3 | twin talls | `rng.int(0,2)` free lane | 1 |
| 4 | bar + gem line | `rng.int(0,2)` gem lane | 1 |
| 5 | tall zigzag ×3 | `rng.int(0,2)` l1, `rng.pick` l2, `rng.pick` l3 | 3 |
| 6 | tall+low+low mixed | `rng.int(0,2)` free lane | 1 |
| 7 | twin talls + pickup | `rng.int(0,2)` free lane, then `rng.unit()` pickup-kind roll | 2 |
| 8 | double bar | — | 0 |
| 9 | prism ring | `rng.int(0,2)` lane | 1 |
| 10 | overdrive runway | `rng.int(0,2)` lane | 1 |
| 11 | gauntlet | `rng.int(0,2)` free lane | 1 |
| 12 | split bar | `rng.int(0,2)` open lane, then `rng.chance(0.35)` chrono | 2 |
| 13 | moving walls ×2 | — | 0 |

**Zero-RNG spawn sources** (all deliberate, all documented in-code):

- the gap coin trail (`Spawner.swift:53-58`, placed at `cursor − gap + 1.0` up to `cursor − 0.5`
  into `Spawner.safeEntryLane`);
- pattern 7's `gemLine` to the pickup, pattern 8's three trails, pattern 11's free-lane trail + arc
  + trailing line;
- every `gemArc` (pure `f(d)` via `crossingSpeed`);
- the guaranteed power-up cadence (`GameCore.spawn`, lines 307-314 + `cadenceCommand`) — cycles
  `powerUpIndex % 5` through shield/magnet/doubler/chrono/superSneakers;
- the flow-surge gem fountain (`registerFlowNearMiss`, lines 456-459);
- `activateSlowMo`, `activateHeadStart`, `deployShield`, `deployOverdrive`,
  `debugActivateSuperSneakers`, `debugSpawn`.

**Non-spawn RNG: none.** The only other `rng` touch is construction (`init`, `reset`).

### The pattern tier ladder (`Spawner.maxIndex(forDistance:)`, `Spawner.swift:24-32`)

`maxIndex` returns an **exclusive** upper bound; the draw is `rng.int(0, maxIdx - 1)`. Every tier is
a **prefix** of the catalogue, so a tier can only ever add patterns, never remove them.
`diff = min(1, dist / diffFullAt)` with `diffFullAt = 3200`.

| tier | condition | distance range | maxIndex | newly unlocked |
|---:|---|---|---:|---|
| 1 | `dist < earlyDistance` | 0 – 259.99 m | 5 | 0–4: gem line, low+arc, triple low, twin talls, bar |
| 2 | `diff < midEarlyDiff (0.18)` | 260 – 575.99 m | 9 | 5 zigzag, 6 mixed row, 7 pickup, 8 double bar |
| 3 | `diff < midDiff (0.45)` | 576 – 1439.99 m | 11 | 9 prism ring, 10 overdrive runway |
| 4 | `diff < movingWallMinDiff (0.6)` | 1440 – 1919.99 m | 13 | 11 gauntlet, 12 split bar |
| 5 | otherwise | 1920 m + | 14 (`Patterns.count`) | 13 moving walls |

Pinned twice: `DifficultyTests.testPatternGating` (8 exact boundaries) and
`PatternOrderTests.testTierLadderMonotoneAndRNGCountsPinned` (monotonicity sweep at 4-unit
resolution), plus a "World 2 has no moving walls" fairness test.

`PatternOrderTests.testCatalogueOrderAndPatternIdentity` additionally pins, for every index:
`movingTall` count is 2 iff idx == 13 and 0 otherwise; `ring` count is 1 iff idx == 9; `boostPad` 1
iff idx == 10; `splitBar` 1 iff idx == 12; and idx 10 emits exactly 1 pad + 24 gems and nothing
lethal.

### `DailyChallenge.layoutVersion` — the bump rule

```swift
static func seed(year: Int, month: Int, day: Int, layoutVersion: UInt64 = 7) -> UInt64 {
    let folded = UInt64(year * 10_000 + month * 100 + day)
    var mix = SplitMix64(seed: folded ^ tag ^ (layoutVersion << 48))   // tag = "PRISMDAY"
    return mix.next()
}
```

**Rule (iron rule 3 + the file's own header):** any change to spawner behaviour, pattern content,
pattern order, or RNG consumption *anywhere in the spawn path* is a bump. Note that v5 and v6 were
bumped for **zero-RNG** changes — adding or moving deterministic entities counts, because the shared
track visibly differs.

| version | release | what changed |
|---:|---|---|
| 2 | v1.3 | ballistic gem arc, ring + overdrive patterns, catalogue reorder, anti-repeat reroll |
| 3 | v1.5 | Super Sneakers re-bands pattern 7's pickup roll |
| 4 | v1.6 | guaranteed power-up cadence adds deterministic pickups |
| 5 | v1.6 | path-aware coin trail (gap breadcrumbs + pattern-7 gem line) |
| 6 | v1.6 | gauntlet fairness (pattern 11's bar→triple-low gap 9u → 27u + free-lane trail) |
| **7** | v1.6 | **current default** — anti-repeat widened to the last TWO patterns + continuous trail through pattern 8's double bars |

Goldens pinned by `DailyChallengeTests.testGoldenSeeds`:

- `(2026,6,10) → 0xA7A59815BF47186A`, `(2026,6,11) → 0xF0F4337E40DF9E9F`,
  `(2025,12,31) → 0x2A346E773D331D4E` (all at the default v7)
- explicit older pins: v5 → `0x639028BA85C69769`, v6 → `0xCF1D7FAADFEF898D`
- **a pre-armed v8 pin: `0x2FC8A9EAC0B9E30F`.** Bumping the default to 8 must reproduce that value;
  the test is designed so the next bump is a one-line change with the golden already in place.

Plus `testConsecutiveDatesDiffer` (28 days) and `testSameDailySeedYieldsIdenticalRun` (two 10k-tick
Autopilot runs must hash identically via `RNGTests.runHash`).

### "Solvable", operationally

Not a proof — an empirical soak (`SolvabilityBotTests`):

- construct `GameCore(seed: 1)`, then `startRun(seed:)` with
  `seed = s &* 0x9E3779B97F4A7C15 &+ salt` for `s` in `0..<N`;
- each tick: `Autopilot.drive(core)` **then** `core.tick(Tuning.tickDt)` — the bot acts first, on
  pre-tick state;
- two soaks: **200 seeds × 6,000 m** (salt `0x12345678`, 4.26 s) and **64 seeds × 12,000 m** (salt
  `0xDEE95EED`, 2.55 s, so full-density content past `diffFullAt = 3200` is broadly sampled);
- safety bound 400,000 ticks (~3,333 s). Reaching it without dying is a **STALLED failure**, not a
  pass;
- failure ⇒ dump every obstacle within ±12 units of the player, sorted by arrival, for the first 12
  failing seeds;
- plus a forced-boost test: inject a `boostPad` under the bot, require 200 m of normal spawning
  after the trigger with no death;
- crucially **the bot never collects pickups**, so the soak proves the track is clearable with the
  *base* moveset and no buffs. Buffs can only make it easier.

---

## 5. Actor isolation topology

Prism Rush is a **single-domain app**. There is exactly one isolation domain — `@MainActor` — and
every long-lived type lives in it. Grep over `PrismRush/`, `Package.swift`, `project.yml` and
`Tools/` returns:

| construct | occurrences |
|---|---:|
| `actor` declarations | **0** |
| `@unchecked Sendable` | **0** |
| `nonisolated(unsafe)` | **0** |
| `Task.detached` | **0** |
| `DispatchQueue` | **0** |
| `@preconcurrency` | **0** |
| `@retroactive` | **0** |
| `.unsafeFlags` | **0** |
| `MainActor.assumeIsolated` | **9** |
| `nonisolated` (declaration) | **1** (`Services/GameCenterService.swift:63`) |
| `deinit` | **0** |
| `removeObserver` | **0** |

Every one of the 34 `class` declarations in `PrismRush/` is `@MainActor` (verified by enumerating
`class [A-Z]` and reading each declaration site). Concurrency risk is therefore not "two threads
touching one object" — it is concentrated in (a) the 9 `assumeIsolated` assertion sites, (b) the
11 unstructured `Task { }` hops into StoreKit / GameKit, and (c) **re-entrancy on the main actor**,
which is a live defect (`ProfileStore` mutating and persisting itself from inside a SwiftUI `body`
— PR-0257 territory, see §Singletons).

---

### The map

Grouped by lifetime. "Isolation" is the declaration as written; "touched by" is who actually calls
it, which is the column that matters.

#### App-lifetime singletons (4)

| Type | File:line | Isolation | Owns | Touched by |
|---|---|---|---|---|
| `ProfileStore` | `Meta/ProfileStore.swift:7-9`, `.shared` at `:10` | `@MainActor @Observable final class` | the `Profile`, `UserDefaults` key `pr.profile.v1`, the iCloud KVS mirror of the same key, the per-install `pr.device.id` slot | **everything.** 16 files under `PrismRush/UI/` reference `.shared`, plus `IAP/IAPManager.swift`. Mutated by `GameModel` (run start/death/deploy/skin), `IAPCatalog.apply`/`restore`, `SettingsView`, `ShopView`, `MysteryBoxView`, `LevelSelectView`, `MissionsView`, `CharacterSelectView`, and by itself from `mergeFromCloud()` (`:692`) |
| `IAPManager` | `IAP/IAPManager.swift:19-21`, `.shared` at `:26` | `@MainActor @Observable final class` | `products`, `availability`, `lastError`, `pendingProductIDs`, `updatesTask` (`:42`), `retryTask` (`:43`) | `GameModel.install` (`UI/GameView.swift:144`), `ShopView.swift:14`, `SettingsView.swift:177,179` |
| `GameCenterService` | `Services/GameCenterService.swift:6-8`, `.shared` at `:9` | `@MainActor @Observable final class`, `: NSObject, GKGameCenterControllerDelegate` | `authenticated` (`:14`); installs the **process-global** `GKLocalPlayer.local.authenticateHandler` | `GameModel.install` (`UI/GameView.swift:145`), `recordRunResults` (`:781, :791`), `ProfileView.swift:12` |
| `AccountService` | `Services/AccountService.swift:5-7`, `.shared` at `:8` | `@MainActor @Observable final class` | `userID`, `displayName`, `lastError`; Keychain items `pr.appleUserID` / `pr.appleName` | `ProfileView.swift:11` only |

> `trace-concurrency.md` says "19 UI files read `.shared` in `body`". The measured count is **16**
> UI files + `IAPManager.swift` = 17 files total. Corrected here.

#### SwiftUI entry points (structs; `body` is implicitly `@MainActor` via the `App`/`View` protocols)

| Type | File:line | Isolation | Owns |
|---|---|---|---|
| `PrismRushApp` | `App/PrismRushApp.swift:4` | `struct: App`, implicit `@MainActor body` | the single `WindowGroup` |
| `RootView` | `App/RootView.swift:8` | `struct: View` | nothing — no `@State`, no `@Environment`. Branches on `XCTestConfigurationFilePath` (`:9-10`) to skip the RealityKit scene under the unit-test host |
| `GameView` | `UI/GameView.swift:914` | `struct: View` | `@State private var model = GameModel()` (`:915`), `showSplash`, `showHowToPlayInfo`, `@Environment(\.scenePhase)` (`:924`) |

`RootView` owning **no** observable state is the only reason `GameView()` is constructed once. That
is a property of the current code, not an enforced invariant — see PR-0258 / trace-findings #6.

#### Run-lifetime graph (one instance each, rooted at `GameModel`)

| Type | File:line | Isolation | Owns | Touched by |
|---|---|---|---|---|
| `GameModel` | `UI/GameView.swift:8-10` | `@MainActor @Observable final class` | `core`, `renderer`, `haptics`, `synth` (`:11-14`), the `EventSubscription` `sub` (`:15`), the frame loop, the per-run award watermarks (`:45-50`) | `GameView` and every meta sheet it hands itself to |
| `GameCore` | `Core/GameCore.swift:22-23` | `@Observable @MainActor final class` | the whole sim: `snapshot` (`:25`), `onFX` (`:28`), the `Spawner` value (`:75`), the `SplitMix64` RNG | driven **only** from `GameModel`'s `SceneEvents.Update` closure (`UI/GameView.swift:280`) and the gesture handlers; read by `HUDView`, `GameOverView`, `Autopilot` |
| `RealityRenderer` | `Render/Reality/RealityRenderer.swift:10-11` | `@MainActor final class: RendererPort` | the scene root, ~40 IUO `ModelEntity!` fields, cached `UnlitMaterial`s, `reduceMotionObserver` (`:115`) | `GameModel` only |
| `EntityPools` | `Render/Reality/EntityPools.swift:5-6` | `@MainActor final class` | pooled entities per `EntityKind`; holds a `[weak self]` factory back to the renderer (`RealityRenderer.swift:170-172`) | `RealityRenderer` only |
| `WorldDecor` | `Render/Reality/WorldDecor.swift:11-12` | `@MainActor final class` | ground/rung decor; constructs `WorldSky` at `:50` | `RealityRenderer` only (constructed `RealityRenderer.swift:178`) |
| `WorldSky` | `Render/Reality/WorldDecor.swift:205-206` | `@MainActor final class` | the 3 legacy family roots (metro/cavern/sands, `:214-216`) + the 9 bespoke skies (`:288-290`) + `famRoots` (`:291`) | `WorldDecor` only |
| `OrbitalSky`, `TidalSky`, `AshfallSky`, `BorealisSky`, `DatastreamSky`, `BloomfallSky`, `EventideSky`, `TempestSky`, `SingularitySky` | `Render/Reality/OrbitalSky.swift:15-16`, `TidalSky.swift:16-17`, `AshfallSky.swift:18-19`, `BorealisSky.swift:16-17`, `DatastreamSky.swift:15-16`, `BloomfallSky.swift:17-18`, `EventideSky.swift:16-17`, `TempestSky.swift:17-18`, `SingularitySky.swift:16-17` | each `@MainActor final class`, each conforming to `BespokeSky` | its own entity subtree + animation state | `WorldSky` only, via the `[any BespokeSky]` array |
| 11 nested particle classes: `WorldDecor.Slot:13`, `DatastreamSky.Pylon:29`, `TempestSky.Bolt:34`, `TidalSky.Jelly:23`, `EventideSky.Ring:27`, `SingularitySky.Ring:34`, `AshfallSky.Seam:33`, `OrbitalSky.Sat:34`, `BorealisSky.Shard:34`, `BloomfallSky.Tree:32`, `BloomfallSky.Lantern:45` | as listed | each `@MainActor private final class` | one entity + its per-frame phase | its enclosing sky only |
| `ParticleSystem` | `Render/Reality/ParticleSystem.swift:8-9` | `@MainActor final class` | the burst/trail particle pool | `RealityRenderer` only (constructed `:179`) |
| `SynthEngine` | `Audio/SynthEngine.swift:10-11` | `@MainActor final class` | one `AVAudioEngine` with **13 attached nodes** (`:56-61`: sfxMixer, musicMixer, musicPlayer + 10 SFX players), the SFX buffer cache, `observers: [NSObjectProtocol]` (`:24`), an `os.Logger` (`:25`) | `GameModel` (`play`, `musicPump` per frame), `SettingsView.swift:89-91` writes the volume properties live |
| `Music` | `Audio/Music.swift:6-7` | `@MainActor final class` | the sequencer clock; wraps a **non-Sendable** `AVAudioPlayerNode` + `AVAudioMixerNode` + `AVAudioFormat` handed in at `init` (`:25-30`) | `SynthEngine` only |
| `Haptics` | `Services/Haptics.swift:5-6` | `@MainActor final class` | 6 `UIFeedbackGenerator`s (`:7-12`), the gem rate-limit clock | `GameModel` (`tick` per frame, `handle(fx)`) |

#### `@MainActor` stateless namespaces and the seam protocol

| Type | File:line | Isolation | Why it is MainActor |
|---|---|---|---|
| `RendererPort` | `Render/RendererPort.swift:8-9` | `@MainActor protocol: AnyObject` | the Core↔Render seam (§2); makes every conformer MainActor by construction |
| `Autopilot` | `Core/Autopilot.swift:9-10` | `@MainActor enum` (no stored state) | it reads `GameCore`, which is MainActor |
| `ProceduralMesh` | `Render/Reality/ProceduralMesh.swift:7-8` | `@MainActor enum` | `MeshResource` generation is a RealityKit main-actor API |
| `IAPCatalog` | `IAP/IAPCatalog.swift:22` | plain `enum`; two `@MainActor static func`s at `:46` (`apply`) and `:65` (`restore`) | only the two functions that mutate a `ProfileStore` need isolation; the catalogue data does not |

#### Nonisolated namespaces holding only immutable statics

`Tuning` (`Core/Tuning.swift:6`), `Patterns` (`Core/Patterns.swift:26`), `Collisions`
(`Core/Collisions.swift:5`), `DailyChallenge` (`Core/DailyChallenge.swift:8`), `Synth`
(`Audio/Synth.swift:6`), `SkinCatalog` (`Meta/SkinCatalog.swift:85`), `SkinUnlocks`
(`Meta/SkinUnlocks.swift:6`), `MissionCatalog` (`Meta/MissionCatalog.swift:77`), `XPCurve`
(`Meta/XPCurve.swift:18`), `ShopValue` (`Meta/ShopValue.swift:23`), `ShopConsumables`
(`Meta/ShopValue.swift:83`), `StoreAvailability` (`Meta/ShopValue.swift:136`), `Keychain`
(`Services/Keychain.swift:9`), `Theme` (`UI/Theme.swift:14`), `CharacterProportions`
(`Render/Reality/ProceduralMesh.swift:288`). Plus three free `@inline(__always)` pure functions in
`Core/Math.swift:4-6` (`lerp`, `clampD`, `clampI`) — global funcs, no state.

All hold `static let` only. Under `SWIFT_STRICT_CONCURRENCY: complete` (`project.yml:11`) a
non-`Sendable` global `static let` is a hard error, so **the fact that the app compiles is the proof
that their element types are `Sendable`** — there is no annotation to read.

> Correction to `trace-concurrency.md`: it lists `Palette` among these namespaces. `Palette` is a
> `private struct` at `Render/Reality/RealityRenderer.swift:1088`, constructed per `sync()` call
> from a `GameSnapshot` — a transient value, not a namespace and not global state.

---

### What guarantees the core is single-domain

Four things stop `GameCore` being reached from two isolation domains. Three are structural
(compiler-enforced); one is not.

**Structural — the compiler rejects the alternative:**

1. **`GameCore` is `@MainActor`** (`Core/GameCore.swift:22-23`). Every stored property and every
   method is MainActor-isolated, so a call from any nonisolated context is a compile error, not a
   race. This is the whole guarantee; everything else supports it.
2. **Both build systems run complete checking.** Xcode: `SWIFT_VERSION: "6.0"` +
   `SWIFT_STRICT_CONCURRENCY: complete` (`project.yml:10-11`). SwiftPM:
   `// swift-tools-version:6.0` (`Package.swift:1`) with **no** `swiftLanguageMode` downgrade and
   **no** `swiftSettings` anywhere in the manifest, so the package builds in Swift 6 language mode,
   which implies complete checking. There is no configuration in which the isolation is only a
   warning.
3. **There is no second domain to be reached from.** Zero `actor` declarations, zero
   `Task.detached`, zero `DispatchQueue`, zero `.unsafeFlags`. All 11 unstructured `Task { }` sites
   (`GameCenterService.swift:39,49`; `IAPManager.swift:64,102,108,117,202`; `AccountService.swift:42`;
   `Haptics.swift:62`; `SettingsView.swift:176,211`; `MysteryBoxView.swift:164,174`;
   `MissionsView.swift:111`; `ShopView.swift:762,792`; `CharacterSelectView.swift:302,320,330`;
   `PackRewardBurst.swift:98`; `LevelSelectView.swift:582`) are created inside `@MainActor` contexts
   and therefore **inherit** MainActor isolation; three additionally spell it (`Task { @MainActor }`).
   None of them touches `GameCore`.
   *(`trace-run-lifecycle.md` §5.9 calls `GameCenterService.swift:39` a detached Task. It is not —
   `Task { }` inside a `@MainActor` method. `trace-concurrency.md` and `trace-findings.md` are
   correct; that is the one factual error across the two traces.)*
4. **The tests inherit the same constraint.** Every `XCTestCase` that constructs a `GameCore` is
   `@MainActor` (`GameplayTests.swift:7`, `RingTests.swift:7`, `SolvabilityBotTests.swift:7`,
   `PowerUpTests.swift:5`, `DifficultyTests.swift:4`, `FlowTests.swift:7`, and the rest). That is
   not a convention the authors chose to follow — it is what (1) forces. A consequence a future
   session should not be surprised by: **the "headless deterministic core" is still main-actor
   bound**, so the 200-seed solvability bot runs its 400,000-tick soaks on the main actor.

**Not structural — asserted at runtime, not proven by a type:**

5. **The hot path enters through an assertion, not an isolation annotation.** The entire game loop —
   including the only call to `core.advance` in the shipping app (`UI/GameView.swift:280`) — lives
   inside `MainActor.assumeIsolated { }` at `UI/GameView.swift:256`, inside a RealityKit
   subscription handler whose declared type is
   `_handler: @escaping (E) -> Swift.Void` with **no** `@MainActor` and **no** `@Sendable`
   (`_RealityKit_SwiftUI.framework/…/_RealityKit_SwiftUI.swiftinterface:417`). The compiler is not
   proving main-actor delivery here; `assumeIsolated` performs a runtime executor check and calls
   `fatalError` on mismatch. So for the hot path the guarantee is "the process crashes if it is ever
   violated", which is a very different thing from "it cannot be violated".

**Conventional only (no enforcement at all in the Xcode target):**

6. Iron rule 1 ("`Core/` never imports a renderer or UIKit") holds today —
   `grep '^import' PrismRush/Core/` returns only `Foundation` (10 files) and `Observation`
   (`GameCore.swift:2`). But nothing enforces it in the Xcode target; the only mechanism is
   `Package.swift:14-24`, whose explicit source list would fail the Linux build if `Core/` grew a
   UIKit import. That mechanism does not cover a *new* file added to `Core/` in Xcode — see PR-0218.

---

### Every isolation escape hatch

Guilty until proven innocent. One row per occurrence. The **only** escape-hatch construct present is
`MainActor.assumeIsolated`, which asserts and traps; the codebase contains none of the *silencing*
kind (`@unchecked Sendable`, `nonisolated(unsafe)`), which race instead of crashing.

| file:line | construct | why it is there | verdict | what would prove it |
|---|---|---|---|---|
| `Meta/ProfileStore.swift:42` | `MainActor.assumeIsolated` | `NSUbiquitousKeyValueStore.didChangeExternallyNotification` block observer registered with `queue: .main` (`:40`); `mergeFromCloud()` is MainActor | **PROVEN-SAFE** | Already proven: the block form takes an `NS_SWIFT_SENDABLE` block (`Foundation/NSNotification.h:51`) and `OperationQueue.main` dispatches to the main dispatch queue, which is the MainActor's executor |
| `IAP/IAPManager.swift:60` | `MainActor.assumeIsolated` | `UIApplication.willEnterForegroundNotification` block observer, `queue: .main` (`:58`) | **PROVEN-SAFE** | same `queue: .main` argument |
| `Audio/SynthEngine.swift:165` | `MainActor.assumeIsolated` | `AVAudioSession.interruptionNotification`, `queue: .main` (`:163`). The `note.userInfo` read at `:164` is deliberately **outside** the block (a nonisolated read of a `UInt`) | **PROVEN-SAFE** | same |
| `Audio/SynthEngine.swift:171` | `MainActor.assumeIsolated` | `AVAudioSession.routeChangeNotification`, `queue: .main` (`:170`) | **PROVEN-SAFE** | same |
| `Audio/SynthEngine.swift:174` | `MainActor.assumeIsolated` | `.AVAudioEngineConfigurationChange` on `engine`, `queue: .main` (`:173`) | **PROVEN-SAFE** | same |
| `Render/Reality/RealityRenderer.swift:184` | `MainActor.assumeIsolated` | `UIAccessibility.reduceMotionStatusDidChangeNotification`, `queue: .main` (`:182`) | **PROVEN-SAFE** | same |
| `Services/GameCenterService.swift:64` | `MainActor.assumeIsolated` inside a `nonisolated func` (`:63`) | `GKGameCenterControllerDelegate` carries **no** MainActor annotation in the iOS 26.5 SDK (`GameKit.framework/Headers/GKGameCenterViewController.h:94-98` — grep for `NS_SWIFT_UI_ACTOR` across the whole GameKit header set returns zero hits), forcing the conformance to be `nonisolated` | **PROVEN-SAFE** | UIKit's own contract: a `UIViewController` presentation-dismissal delegate callback is main-thread. The parameter is a `UIViewController` subclass, a `@MainActor` type — a framework delivering it off-main would be handing a MainActor object to a nonisolated caller |
| `UI/GameView.swift:256` | `MainActor.assumeIsolated` wrapping the **entire frame loop** (`:256-291`) | RealityKit's `content.subscribe(to:componentType:_:)` handler type is nonisolated (`_RealityKit_SwiftUI.swiftinterface:417`) | **PROBABLY-SAFE** | No written contract exists. Three pieces of evidence, none of them a guarantee: (a) the handler is **not** `@Sendable`, so Swift's model already assumes it stays in one isolation region; (b) the payload `SceneEvents.Update` carries `let scene: Scene`, and `Scene` is `@preconcurrency @MainActor public class` (`RealityFoundation.swiftinterface:7063-7065, 8663`) — off-main delivery would hand a MainActor object to a nonisolated closure; (c) 11 XCUITests (`UITests/InteractionUITests.swift`) plus every `PR_AUTOPLAY` screenshot run drive thousands of ticks per invocation through this exact assertion without trapping. Only Apple documentation or an SDK annotation would upgrade this to PROVEN |
| `Services/GameCenterService.swift:18` | `MainActor.assumeIsolated` wrapping the body of `GKLocalPlayer.local.authenticateHandler` (`:17-25`) | `authenticateHandler` is a plain, unannotated Objective-C block property | **UNPROVEN** | I checked the SDK directly: `GameKit.framework/Headers/GKLocalPlayer.h:255` declares it `void(^authenticateHandler)(UIViewController * __nullable viewController, NSError * __nullable error)` with **no** `NS_SWIFT_UI_ACTOR`, no `NS_SWIFT_SENDABLE`, and no thread-delivery note; there is no MainActor annotation anywhere in the GameKit headers. The (b)-style argument applies here too — the parameter is a `@MainActor` `UIViewController` — but that is an inference from SDK typing, not a contract, and unlike `GameView.swift:256` this site has **no** reliable empirical coverage. Proof would require instrumenting the handler (`Thread.isMainThread` / `dispatchPrecondition`) on a real device across the cold-launch, sign-in-sheet, and already-authenticated paths |

**PR-0251 is filed as a conditional SEV0 whose condition is unproven** (`docs/agent/03_BACKLOG.md`,
§"Findings from the cross-cutting traces"). Read the severity precisely: *if* GameKit ever delivers
`authenticateHandler` off-main, the app hard-traps at launch and is unlaunchable; *whether* it ever
does is a fact about undocumented framework behaviour that this repo cannot establish. The backlog
assigns the question to AUDIT-006. The de-risking fix is zero-cost and already used elsewhere in the
same codebase: replace the assertion with an explicit hop, exactly as `AccountService.swift:41-43`
does for `getCredentialState`. That is not "silencing an isolation error" (forbidden by
`01_RULES.md` §4) — it is replacing an assertion with a real hop.

**Summary of guilt.** 7 of 9 are `queue: .main` block observers or a UIKit delegate callback and are
provably correct — they are boilerplate the language forces on you, not compiler-silencers. The 2
that cannot be proven (`GameView.swift:256`, `GameCenterService.swift:18`) are both "framework
callback with no isolation annotation", and both trap rather than race. **None of the 9 hides a
cross-thread mutation.**

---

### Non-isolated callbacks delivered on main

Every entry point where code outside the app's control re-enters it. "Token retained?" matters
because there is **no `deinit` and no `removeObserver` anywhere in `PrismRush/`** — a stored token
is currently unused, but a discarded one makes removal permanently impossible.

| Callback | Registered at | Registered from | How it reaches MainActor | Token retained for removal? |
|---|---|---|---|---|
| `NSUbiquitousKeyValueStore.didChangeExternallyNotification` | `Meta/ProfileStore.swift:38-43` | `init()` only — **not** `init(testing:)` (`:25-29`), so tests never register it | `queue: .main` + `assumeIsolated` (`:42`) → `mergeFromCloud()` | **No — discarded.** `addObserver(forName:object:queue:using:)`'s return value is dropped. The SDK header explicitly says the return value "should be held onto by the caller in order to remove the observer" (`Foundation/NSNotification.h:52-53`) |
| `UIApplication.willEnterForegroundNotification` | `IAP/IAPManager.swift:57-61` | `start()`, guarded by `observingForeground` (`:45,:53-54`) and `#if canImport(UIKit)` | `queue: .main` + `assumeIsolated` (`:60`) → `refreshIfUnavailable()` | **No — discarded** |
| `AVAudioSession.interruptionNotification` | `Audio/SynthEngine.swift:163-169` | `observeSessionNotifications()`, called as the **last statement of `init()`** (`:75`) — not from `start()`, so a never-started engine still registers | `queue: .main`; `note.userInfo` read at `:164` outside the block; `assumeIsolated` (`:165`) → `recoverEngine()` | Yes — appended to `observers` (`:24`), never removed ("app-lifetime" per the comment) |
| `AVAudioSession.routeChangeNotification` | `Audio/SynthEngine.swift:170-172` | same | `queue: .main` + `assumeIsolated` (`:171`) → `recoverIfStalled()` | Yes — same array, never removed |
| `.AVAudioEngineConfigurationChange` (`object: engine`) | `Audio/SynthEngine.swift:173-175` | same | `queue: .main` + `assumeIsolated` (`:174`) → `recoverIfStalled()` | Yes — same array, never removed |
| `UIAccessibility.reduceMotionStatusDidChangeNotification` | `Render/Reality/RealityRenderer.swift:181-187` | last statement of `init()` | `queue: .main` + `assumeIsolated` (`:184`) | Yes — `reduceMotionObserver` (`:115`), never removed |
| GameKit `GKLocalPlayer.local.authenticateHandler` | `Services/GameCenterService.swift:17-25` | `authenticate()`, called once from `GameModel.install` (`UI/GameView.swift:145`) | **`assumeIsolated` with no queue guarantee** (`:18`) — the UNPROVEN row above | N/A — a process-global closure slot. Setting it again replaces it; it is never cleared. It permanently retains a reference path to `GameCenterService.shared` |
| GameKit `gameCenterViewControllerDidFinish` | `Services/GameCenterService.swift:63-67` | delegate assigned at `:59` (`vc.gameCenterDelegate = self`) | `nonisolated func` + `assumeIsolated` (`:64`) | N/A — `gameCenterDelegate` is a `weak` property (`GKGameCenterViewController.h:51`); released with the view controller |
| StoreKit `Transaction.updates` | `IAP/IAPManager.swift:201-212` | `listenForTransactions()`, called from `start()` (`:51`) if `updatesTask == nil` | **No hatch needed.** The `Task { }` at `:202` is created inside a `@MainActor` method, so it inherits MainActor and every `for await` resumption lands on the main actor | Stored in `updatesTask` (`:42`), **never cancelled** (intended: app-lifetime). Note `guard let self … else { continue }` (`:204`): if `self` ever died, the loop would keep draining `Transaction.updates` without calling `finish()`, forever. Unreachable while it is a singleton |
| StoreKit `Transaction.currentEntitlements` | `IAP/IAPManager.swift:193-199` | awaited from the `Task { }` at `:64-67` | inherits MainActor from `start()` | One-shot |
| AuthenticationServices `getCredentialState` completion | `Services/AccountService.swift:41-53` | `refreshCredentialState()` from `init()` (`:19`) | **`Task { @MainActor [weak self] }` (`:42`) — an actual hop, not an assertion.** This is the correct pattern and the direct contrast to `GameCenterService.swift:18` | One-shot; nothing to remove |
| SwiftUI `SignInWithAppleButton(onCompletion:)` | `UI/ProfileView.swift:134` → `account.handle($0)` | SwiftUI | SwiftUI delivers view callbacks on MainActor; no hatch | N/A |
| RealityKit `SceneEvents.Update` (the frame loop) | `UI/GameView.swift:255-292` | `GameModel.install(_:)`, called from `RealityView { content in … }` (`:1050-1051`) | `assumeIsolated` (`:256`) — the PROBABLY-SAFE row above | `EventSubscription` stored in `GameModel.sub` (`:15`); never explicitly cancelled (no `deinit`) |
| SwiftUI `onChange(of: scenePhase)` | `UI/GameView.swift:1220-1222` → `model.pauseForBackground()` | SwiftUI | MainActor by SwiftUI contract; no hatch | N/A |
| **AVAudio render-thread callbacks** | — | — | **There are none.** Both `scheduleBuffer` calls pass `completionHandler: nil` (`Audio/Music.swift:82`, `Audio/SynthEngine.swift:155`), and there is no `installTap` and no `AVAudioSourceNode` anywhere. The real-time audio thread never re-enters app code | N/A |

---

### Singletons and global mutable state

#### The four `.shared` instances

| Singleton | Declared | Who mutates it | From which domain | Risk |
|---|---|---|---|---|
| `ProfileStore.shared` | `Meta/ProfileStore.swift:10` | `mutate(_:)` (`:90-93`) is the **single write funnel** — every persistence side effect in the app originates there. Callers: `GameModel` (run start / death / deploy / mute / skin), `IAPCatalog.apply`/`restore` (`IAP/IAPCatalog.swift:47,66`), `SettingsView`, `ShopView`, `MysteryBoxView`, `LevelSelectView`, `MissionsView`, `CharacterSelectView`, and `mergeFromCloud()` (`:697`) | MainActor only | **Both a test blocker and a re-entrancy hazard.** Every `mutate` synchronously runs `JSONEncoder().encode` → `UserDefaults.standard.set` → `cloud.set` → `cloud.synchronize()` (`:620-627`), with no debounce. And it is called **from inside SwiftUI view bodies**: `MenuView.swift` navRail → `unclaimedCount(now:)` (`:558-564`) → `refreshDailyMissions` (`:385`) / `refreshWeeklyMissions` (`:408`), each of which can `mutate`; same shape at `MissionsView.swift:41,43`. **S-005 moved the `RewardsBar` call site — it is now `MenuView`'s `navRail`, inside a 60 s `TimelineView`; the hazard moved, it did not go away**. Converges today only because `refreshDailyMissions` early-returns once the stored UTC day matches (`:387`) |
| `IAPManager.shared` | `IAP/IAPManager.swift:26` | its own async methods; the `Transaction.updates` loop (`:201-212`) | MainActor | Medium — network-dependent state, StoreKit-driven, not deterministic |
| `GameCenterService.shared` | `Services/GameCenterService.swift:9` | `authenticated` written at `:22` — **from inside an instance method, via the singleton rather than `self`**. Harmless while `.shared` is the only instance; a second instance could never observe its own auth state (trace-findings #9, SEV3) | MainActor (assumed — the UNPROVEN row) | Low |
| `AccountService.shared` | `Services/AccountService.swift:8` | `handle(_:)` (`:60`), `signOut()` (`:82`), the credential-state hop (`:42-52`) | MainActor via an explicit `Task { @MainActor }` | Low |

#### Stored global mutable state

**None.** No `static var` with storage, no top-level `var`, no top-level `let`. All four `static var`
hits in the codebase are computed properties: `Theme.neon` (`UI/Theme.swift:292`),
`Synth.stepDuration` / `Synth.stepFrames` (`Audio/Synth.swift:273-274`), `IAPCatalog.allIDs`
(`IAP/IAPCatalog.swift:38`).

#### Process-global state outside the app's types (behaves like a global)

| Store | Keys / slot | Mutated by |
|---|---|---|
| `UserDefaults.standard` | `pr.profile.v1`, `pr.device.id`, legacy `pr.appleUserID` / `pr.appleName` | `ProfileStore.save()` (`:622`), `persistentDeviceKey()` (`:56`), `AccountService.loadMigrating` (`:28`, delete-after-migrate) |
| `NSUbiquitousKeyValueStore.default` | `pr.profile.v1` (same key string) | `ProfileStore.save()` (`:624-625`) |
| Keychain (generic password) | `pr.appleUserID`, `pr.appleName` | `AccountService.handle()` (`:74,:77`), `signOut()` (`:85-86`) |
| `GKLocalPlayer.local.authenticateHandler` | one closure slot | `GameCenterService.authenticate()` (`:17`) |
| `AVAudioSession.sharedInstance()` | category set to `.playback` | `SynthEngine.start()` (`:86`) |

#### Determinism risk, test blocker, or both

| Item | Classification | Detail |
|---|---|---|
| `ProfileStore.shared` reads/writes the **real** `UserDefaults` and the **real** iCloud KVS in any process that touches it | **test blocker** | The evidence is in the source: `UI/GameView.swift:146-192` (`PR_DEMOPROFILE`) is ~45 lines of *exact pins* whose comments say "coins banked or worlds purchased by a prior CI cycle must never flip those outcomes" and "XP and metrics banked by earlier autoplay/CI cycles on this simulator would otherwise re-grant Pebble & co." That is inter-run state leakage papered over at the app layer |
| Unit tests are clean of it | — | Every test builds `ProfileStore(testing:)` (`:25-29`, `persisting = false`); grep finds **zero** `ProfileStore.shared` under `Tests/` or `UITests/`. Caveat: on Darwin `init(testing:)` still evaluates the stored-property default `private let cloud = NSUbiquitousKeyValueStore.default` (`:20`), so a macOS `swift test` instantiates the real KVS object. It never reads or writes it (no observer, `persisting == false`) — inert |
| The two discarded observer tokens | **test blocker** | `Meta/ProfileStore.swift:38` and `IAP/IAPManager.swift:57`. An integration test that wants to build and tear down a `ProfileStore` with `persisting: true` cannot |
| Meta-layer randomness | **determinism risk** (outside Core, so iron rule 2 is not violated) | `ProfileStore.openMysteryBox` uses `Double.random` (`:137`, injectable via `roll:`); `openFreeChest` uses `Int.random(in: 60...220)` (`:341`, injectable via `reward:`). Both are unpinnable in a live run |
| Core's only nondeterminism entry point | **determinism risk, by design** | `GameCore.init(seed: UInt64 = .random(in: .min ... .max))` (`Core/GameCore.swift:81`) and `rng = SplitMix64(seed: seed ?? .random(...))` (`:139`). A run started without an explicit seed is not reproducible; the daily challenge, the bot and the golden tests always pass one. `returnToMenu` calls `reset(seed: nil)` (`UI/GameView.swift:497`) — trace-findings #14 asks for an explicit exemption comment so a future reader does not "fix" it wrongly |
| `GameCore` and `Autopilot` are `@MainActor` | **constraint, not a bug** | The deterministic core cannot be exercised off the main actor; the SPM suite runs its assertions there |

---

### Sendable boundary

**Nothing in this app is sent between isolation domains by app code.** There is one domain, so the
`Sendable` conformances on the value types are documentation and future-proofing, not load-bearing.
`GameSnapshot` (`Core/Models.swift:53`) is `Sendable`, is handed to the renderer once per frame
(`UI/GameView.swift:283`), and **never leaves the main actor**. The §2 seam is a MainActor→MainActor
call that happens to pass an immutable value.

The declared-`Sendable` value types, all immutable-by-construction or copied on assignment:

`GameMode` · `PickupKind` · `EntityKind` · `EntityState` · `GameSnapshot` · `NearMissKind` ·
`FXEvent` (`Core/Models.swift:4,9,14,35,53,119,125`) · `SpawnCmd` (`Core/Patterns.swift:4`) ·
`SplitMix64` (`Core/RNG.swift:5`) · `Profile` (`Meta/Profile.swift:5`) · `Skin` + its nested
`BodyShape`/`PupilStyle`/`Crest`/`Rarity`/`Unlock`/`Idle` (`Meta/SkinCatalog.swift:9-37`) ·
`RunSummary` · `Mission` · `Mission.Metric` · `Mission.Scope` (`Meta/MissionCatalog.swift:6,27,28,58`) ·
`LevelUpResult` (`Meta/XPCurve.swift:6`) · `PackBadge` · `ShopPack` · `ConsumableGrant` ·
`CoinSpendItem` · `StoreState` (`Meta/ShopValue.swift:9,17,58,69,128`) · `IAPKind` · `IAPProduct`
(`IAP/IAPCatalog.swift:5,11`) · `Synth.Bed` · `Synth.SFX` (`Audio/Synth.swift:286,350`) ·
`WorldPalette` (`UI/Theme.swift:6`).

**What actually crosses a nominal isolation boundary**, and what it is:

| Crossing | Type | Value type? | Why it is acceptable |
|---|---|---|---|
| The 6 `NotificationCenter` block observers | `Notification` | struct — but its `userInfo` is `[AnyHashable: Any]?`, an unchecked hole | The block is `NS_SWIFT_SENDABLE` (`Foundation/NSNotification.h:51`). Only one site reads `userInfo`: `Audio/SynthEngine.swift:164` extracts `AVAudioSessionInterruptionTypeKey` as a `UInt` — a scalar. The rest ignore the payload entirely |
| `[weak self]` captures inside those `@Sendable` blocks | `ProfileStore`, `IAPManager`, `SynthEngine`, `RealityRenderer` | **No — reference types** | Legal and safe: a `@MainActor`-isolated class is implicitly `Sendable`, and the closures only *touch* `self` inside `assumeIsolated`, i.e. on the main actor |
| RealityKit frame event | `SceneEvents.Update` | struct **wrapping a reference** — `let scene: Scene`, and `Scene` is `@preconcurrency @MainActor public class` (`RealityFoundation.swiftinterface:7063-7065, 8663`), so the event is **not** `Sendable` | The app reads only `event.deltaTime` (`UI/GameView.swift:258`) and never `event.scene`. The handler is not `@Sendable`, so Swift already models it as staying in one region — see the PROBABLY-SAFE verdict |
| GameKit auth callback parameter | `UIViewController?` | **No — a `@MainActor`, non-`Sendable` reference type** | This is the one non-value crossing that is **not proven safe**. It arrives in a nonisolated closure (`Services/GameCenterService.swift:17`) and is used immediately inside `assumeIsolated` (`:19-20` → `GameCenterService.present`). See PR-0251 |
| GC delegate callback parameter | `GKGameCenterViewController` | **No — a `@MainActor`, non-`Sendable` reference type** | Same shape as above, but covered by the UIKit view-controller-delegate contract (`Services/GameCenterService.swift:63-65`) |
| StoreKit async sequences | `Transaction`, `Product`, `VerificationResult` | Yes — StoreKit 2 value types, all `Sendable` | The awaiting `Task`s inherit MainActor (`IAP/IAPManager.swift:194, 203`), so the elements are consumed on the main actor |
| Sign in with Apple credential state | `ASAuthorizationAppleIDProvider.CredentialState` | Yes — a `Sendable` enum | Captured by the `Task { @MainActor }` hop at `Services/AccountService.swift:42` |
| Non-Sendable objects held *inside* MainActor classes | `AVAudioEngine`, `AVAudioPlayerNode`, `AVAudioMixerNode`, `AVAudioFormat` (`Audio/SynthEngine.swift:12-20`, handed to `Music` at `Audio/Music.swift:25-30`); `Entity` / `ModelEntity` / `EventSubscription` across `Render/`; the 6 `UIFeedbackGenerator`s (`Services/Haptics.swift:7-12`) | **No** | They never cross anything. Each is reachable only from a `@MainActor` owner, and there is no audio-render-thread or background callback that could reach them (see the last row of §Non-isolated callbacks) |

---

## 6. Data flow for one run

An ordered trace from process start to back-on-the-hub. §2 gives the seam payloads and the
three-call ordering contract; §3 gives the accumulator internals; §4 gives the RNG stream. This
section gives the *call graph* those live inside — who calls what, in what order, and what each step
writes.

### 6.1 Cold launch

| # | Step | file:line | What happens |
|---|---|---|---|
| 1 | Process entry | `App/PrismRushApp.swift:3-13` | `@main struct PrismRushApp: App`. One `WindowGroup` → `RootView()` with `.preferredColorScheme(.dark)`, `.statusBarHidden(true)`, `.persistentSystemOverlays(.hidden)`. **No app delegate, no singleton warm-up, no `@StateObject` container.** |
| 2 | Test-host bypass | `App/RootView.swift:9-10, 13-14` | `isUnitTesting` is a `static let` reading `ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"]`. When true, `body` returns `Color.black.ignoresSafeArea()` and **`GameView` is never constructed** — the whole graph below is skipped in the XCTest host. |
| 3 | `GameView` value init | `UI/GameView.swift:915` | `@State private var model = GameModel()`. A stored-property initializer, so `GameModel()` runs on every `GameView` struct initialization (GOT-01). |
| 4 | `GameModel` stored properties, in declaration order | `UI/GameView.swift:11-14` | See the construction table below. **This is what blocks the first frame** — a synchronous main-actor build of ~12 procedural meshes, ~60 RealityKit entities, and a 13-node `AVAudioEngine` graph, all before SwiftUI lays out a pixel. |
| 5 | `RootView.body` → `GameView.body` → `RealityView` make closure | `UI/GameView.swift:1050-1052` | `RealityView { content in model.install(content) }`. `install` only *attaches* the already-built scene. |
| 6 | `install` | `UI/GameView.swift:139-293` | 13 ordered steps; see the install table below. |
| 7 | Splash | `UI/GameView.swift:922-923, 1211-1215` | `@State private var showSplash = ProcessInfo…["PR_SKIP_SPLASH"] != "1"`. Rendered as the **last** `ZStack` child at `.zIndex(10)`, above HUD, menu, meta sheets and `EffectsOverlay`. |
| 8 | First `SceneEvents.Update` | `UI/GameView.swift:255` | The frame loop, armed last in `install`. |

**Construction order inside `GameModel` (`GameView.swift:11-14`):**

| # | Property | init at | Work done at init |
|---|---|---|---|
| 1 | `let core = GameCore()` | `Core/GameCore.swift:81-87` | Seeds `SplitMix64` from `.random(in: .min ... .max)`, reserves the three entity arrays to the `Tuning.cap*` sizes, one `rebuildSnapshot()` so `snapshot` is a valid `.menu` state before any frame. |
| 2 | `let renderer = RealityRenderer()` | `Render/Reality/RealityRenderer.swift:156-188` | Builds `gemMesh`/`magnetMesh`/`doublerMesh`/`chronoMesh`/`splitBarSegmentMesh`/`ringMesh`/`padMesh`/`sneakerArmMesh` (`:157-166`), two `UnlitMaterial`s, then `buildScene()` (`:169` → `:745-806`), `EntityPools` with a `[weak self]` factory (`:170-172`), three `prewarm` passes for ring/boostPad/superSneakers (`:175-177`), `WorldDecor(root:)` (`:178`), `ParticleSystem(parent:)` (`:179`), and registers the Reduce-Motion observer (`:181-187`). |
| 3 | `let haptics = Haptics()` | `Services/Haptics.swift` (stored props) | Six `UIFeedbackGenerator` instances. |
| 4 | `let synth = SynthEngine()` | `Audio/SynthEngine.swift:45-75` | `AVAudioFormat` guard → on failure the engine is silent-but-alive (`started` stays false and every entry point no-ops). Otherwise attaches 2 mixers + 10 `AVAudioPlayerNode`s + the music player, connects them, constructs `Music`, and registers three session/engine observers (`:163-175`). |

`buildScene()` (`RealityRenderer.swift:745-806`) creates the camera, the backdrop plane, the ground
plane, lane lines, grid rungs, skid boxes, the ring-pulse torus, the shield dome, then
`buildCharacter()` (`:831-910`).

**`install` order (`GameView.swift:139-293`):**

| # | line | Call | Effect |
|---|---|---|---|
| 1 | `:140` | `renderer.install(into: content)` | `content.add(root)` (`RealityRenderer.swift:190-192`). |
| 2 | `:141` | `haptics.prepare()` | `Haptics.swift:21`. |
| 3 | `:142` | `synth.start()` | `SynthEngine.swift:78-97`: `AVAudioSession` category `.playback`, `setActive(true)`, `mainMixerNode.outputVolume = masterTarget` **with no ramp**, `engine.prepare()`, `engine.start()`, `play()` on all 10 SFX nodes. On throw: `started = false`, logged, every later audio call is a no-op. |
| 4 | `:143` | `synth.musicStart(calm: true)` | **Audio starts here** — `SynthEngine.swift:117-124` → `Music.start(targetVolume: 0.4)` (`Music.swift:35-46`, `vol = 0.08` fading over ~0.5 s). This is 57 lines *before* the saved mute is applied at `:200` → PR-0256. |
| 5 | `:144` | `IAPManager.shared.start()` | `IAP/IAPManager.swift:50-66`: installs the `Transaction.updates` listener, registers the foreground re-check observer, then an async `Task { await loadProducts(); await restoreEntitlements() }` (`:64`). The profile touch inside `restoreEntitlements` (`:193-199`) is therefore asynchronous, not part of launch. |
| 6 | `:145` | `GameCenterService.shared.authenticate()` | `Services/GameCenterService.swift:16-26`: installs `GKLocalPlayer.local.authenticateHandler`. Asynchronous — `authenticated` flips later (PR-0271). |
| 7 | `:146-192` | `PR_DEMOPROFILE` pin | QA/CI only. One `ProfileStore.shared.mutate` (`:157`) writing ~20 exact pins → one full save. |
| 8 | `:195-197` | `PR_SKIN` pin | Another `mutate` → another save. |
| 9 | `:199-208` | **Profile → runtime one-shot reads** | `let saved = ProfileStore.shared.profile`, then `synth.muted`, `model.muted`, `synth.musicVolume`, `synth.menuMusicVolume`, `synth.sfxVolume`, `haptics.enabled`, `core.best = saved.bestScore`. Commented as deliberately outside a SwiftUI `body`, so G3 does not apply. `core.best` is never re-synced afterwards (PR-0272). |
| 10 | `:209` | `applyCurrentSkin()` | `:613-615` → `renderer.applySkin(SkinCatalog.skin(ProfileStore.shared.equippedSkinID))` (`RealityRenderer.swift:701`), which sets the skin fields and then tears down and rebuilds the whole character rig (`rebuildCharacter()`, `:810-823`). |
| 11 | `:210` | `checkSkinUnlocks()` | `:621-628` — launch catch-up for characters earned by level / achievement tier / challenge-days while away. Each grant is **queued** via `celebrateMilestone` (`:632-634`) and released by `ageEffects` — under the splash, so it is never seen (PR-0257). |
| 12 | `:211` | `core.onFX = { [weak self] fx in self?.handleFX(fx) }` | The Core→host FX seam, wired once and never rewired. |
| 13 | `:212-253` | Debug env hooks | `PR_AUTOPLAY`/`PR_DEMO` → `core.startRun(seed: 7)`; `PR_WORLD` → `beginRun(fromWorld:seed:7)`; `PR_SHIELD`; `PR_SNEAKERS`; `PR_DEEPWORLDS`; `PR_FIRSTRUN`; `PR_SCREEN`/`PR_FOCUS`. Four of these `mutate` the real profile (PR-0285). |
| 14 | `:255-292` | `sub = content.subscribe(to: SceneEvents.Update.self)` | The per-frame loop, armed **last**. |

**When the profile loads.** `ProfileStore.shared` is a `static let` on a `@MainActor @Observable`
class (`Meta/ProfileStore.swift:10`), so it is created lazily on first access. `init()`
(`:31-48`) runs synchronously: `persistentDeviceKey()` (a `UserDefaults` read plus a possible
`UUID()` write, `:52-58`), `ProfileStore.load(localKey:cloud:)` (`:700-708` — **cloud blob preferred
over local, no merge**), `sanitized(_:)` (`:70-79`), the KVS observer registration (`:38-43`), and
`cloud.synchronize()` (`:44`). On non-Darwin (`:46`) it loads local only. The first touch races
between `SplashView.body:20` and `GameView.swift:157`/`:199` — see §6.7.

### 6.2 Menu → run start

**Entrances.** In `.menu` mode `GameView.body` renders `MenuView` only when `model.activeSheet == nil`
(`GameView.swift:1090-1108`). Three live entrances converge on the same gate:

| Entrance | Call | file:line |
|---|---|---|
| MenuView PLAY | `model.startRun()` | `GameView.swift:1099` |
| Hub → DAILY (beside PLAY) | `model.startDailyChallenge()` | `GameView.swift:433-439` (wired through `MenuView`'s `onDailyRush` closure into `DailyRushLauncher`; was the rail's cell in `RewardsBar`) |
| Worlds → PLAY FROM HERE / world card | `model.startRun(fromWorld:)` | wired through `LevelSelectView` |
| Game-over RUN AGAIN | `model.startRun()` — always `fromWorld: 0` | `GameView.swift:1116` (PR-0259, PR-0011) |

**Ordered call chain from the tap:**

1. `startRun(fromWorld:seed:)` (`GameView.swift:300-302`) does not start anything. It wraps the real
   start in a `[weak self]` closure and hands it to `routeRun`.
2. `routeRun(_:)` (`:308-314`) — the **one first-run gate**: if
   `ProfileStore.shared.profile.totalRuns == 0, !autoplay, !demo` it stores the closure in
   `pendingFirstRunStart`; otherwise it calls it immediately.
3. When deferred, `GameView.body:1152-1157` renders `HowToPlayView(…, doneLabel: "LET'S GO")` at
   `.zIndex(2)`. `confirmFirstRunTutorial()` (`:318-322`) clears the gate **first**, then invokes the
   stored closure (so `beginRun` can never re-gate). `cancelFirstRunTutorial()` (`:325-328`) drops it
   and plays `.uiTick` — no run.
4. `beginRun(fromWorld:seed:consumeLoadout:)` (`:367-426`), in this exact order:

| # | line | Step |
|---|---|---|
| 1 | `:368` | `applyCurrentSkin()` — a **full character-rig rebuild, per run**. |
| 2 | `:369` | `core.startRun(seed: seed, startDistance: Double(fromWorld) * Tuning.worldLength)` (`Tuning.swift:8`, `worldLength = 800`). |
| 3 | `:372-385` | Pre-run loadout consumption. Skipped for the Daily (`consumeLoadout: false`, `:436`). `armedHeadStart` + a banked charge → `mutate` decrement (`:376`) + `core.activateHeadStart()` (`GameCore.swift:235-240`, sets `boostT = Tuning.headStartBoostDuration = 4.5` and emits `.boostStarted`). `armedCoinSurge` + a charge → `mutate` decrement (`:381`) and `coinSurgeActiveThisRun = true`. **Two possible profile saves before the run begins.** |
| 4 | `:386` | `renderer.resetEntities()` (`RealityRenderer.swift:669-694`). |
| 5 | `:389-410` | The run-recording reset block: `isChallengeRun = false`, `playTimeThisRun = 0`, `previousBest = profile.bestScore`, `reachAtRunStart = profile.maxWorldReached`, `overTime`, `canRestart`, `restartCountdown`, `coinsAwardedThisRun`, `distanceRecordedThisRun`, `gemsRecordedThisRun`, the four coin watermarks (`gemCoinsAwarded`/`distCoinsAwarded`/`worldCoinsAwarded`/`styleCoinsAwarded`), `lastLevelUp = nil`, `lastChallengePayout = 0`, the four FX counters (`nearMissesThisRun`/`closesThisRun`/`slicksThisRun`/`slidesThisRun`), `statsRecorded = false`, `newBestCelebrated = false`. |
| 6 | `:413-417` | Tutorial arming: `tutorialActive = PR_TUTORIAL \|\| (totalRuns == 0 && !autoplay && !demo)`; `hintsShown.removeAll()`. |
| 7 | `:418-423` | `runStartWorld = fromWorld`, `paused = false`, `popups.removeAll()`, `milestoneQueue.removeAll()`, `nextMilestoneAt = 0`, `activeSheet = nil`. |
| 8 | `:424-425` | `synth.musicStart()` (full-intensity bed, 0.85) and `synth.play(.startChime)`. |

**Where the seed comes from:**

| Run kind | Seed | file:line |
|---|---|---|
| Normal run | `seed == nil` → `GameCore.reset` uses `SplitMix64(seed: .random(in: .min ... .max))` — non-deterministic by design | `GameCore.swift:139` |
| Daily Rush | `ProfileStore.todaysChallengeSeed()` → UTC y/m/d via the private UTC `Calendar` (`ProfileStore.swift:353-357`) → `DailyChallenge.seed(year:month:day:)` | `ProfileStore.swift:570-573`, consumed at `GameView.swift:436` |
| Checkpoint run | Seed still `nil`; the *world* comes from `startDistance`, not the seed | `GameView.swift:301` → `GameCore.swift:103-112` |
| Autoplay / demo / `PR_WORLD` | Hard-coded `7` | `GameView.swift:212, 216` |

`startDailyChallenge` (`:433-439`) must set `isChallengeRun = true` **after** `beginRun` returns,
because `beginRun:389` unconditionally clears it.

**What `GameCore.startRun` resets** (`GameCore.swift:97-114`): saves `best` (`:98`), calls
`reset(seed:)` (`:138-154` — reseeds the RNG, **replaces the `Spawner` value wholesale** so
`cursor`/`lastIdx`/`prevIdx` reset, zeroes ~30 sim fields, empties the three entity arrays
`keepingCapacity: true`, zeroes `accumulator`/`nextId`/`powerUpCursor`/`powerUpIndex`), restores
`best` (`:100`), sets `mode = .play` and `speed = Tuning.speedStart` (17 — no crawl off the line).
For `startDistance > 0` it additionally sets `usedCheckpoint = true`, `distance`, `scoreOffset`,
`spawner.cursor = startDistance + 60`, `powerUpCursor = startDistance + Tuning.powerUpFirstAt` (150),
and derives `maxWorld`/`world`/`worldFrom`/`worldTo`/`worldBlend` (`:103-112`). Then
`rebuildSnapshot()` (`:113`).

**What is NOT reset:** `core.best` (deliberately preserved, `:98-100`) and everything in §6.6's
"reused" list. **Nothing in `beginRun` ticks** — the first simulated tick is the next
`SceneEvents.Update`.

### 6.3 The per-frame loop

Driver: RealityKit's `SceneEvents.Update` subscription, established at `GameView.swift:255`, held in
`@ObservationIgnored private var sub: EventSubscription?` (`:15`). The whole closure body is wrapped
in `MainActor.assumeIsolated` (`:256`) per iron rule 8 — this is the single largest `assumeIsolated`
site in the codebase.

| # | line | Call | Notes |
|---|---|---|---|
| 1 | `:258` | `let dt = event.deltaTime` | Wall-clock frame delta. |
| 2 | `:259` | `uiClock += dt` | The UI/effects clock — **advances even while paused**, while `ageEffects` (step 15) does not run, so popups and the reward toast age invisibly and dump on resume (PR-0136). |
| 3 | `:260` | `haptics.tick(dt, playing: core.mode == .play && !paused)` | `Services/Haptics.swift:28` — re-`prepare()`s periodically during play. |
| 4 | `:262-265` | **pause short-circuit** | If `paused`: `synth.musicPump(dt:world:)` then `return`. Sim, renderer and effects all frozen; no dt reaches the accumulator at all. |
| 5 | `:267` | `if core.mode == .play { playTimeThisRun += dt }` | Credited *before* the tick that may kill the player (PR-0276). |
| 6 | `:269-271` | `Autopilot.drive(self.core)` | Only under `PR_AUTOPLAY`/`PR_DEMO`, once per **frame** (not per tick). |
| 7 | `:272-275` | `core.debugForceDie()` after 6 s | `PR_DEMO` only. |
| 8 | `:276-278` | `if autoplay, core.mode == .over { startRun() }` | Fires the frame **after** death. |
| 9 | `:280` | **`core.advance(realDt: dt)`** | Accumulator + N × `tick(1/120)` + one `rebuildSnapshot()`. Internals in §3. **No mode guard — this runs on the idle hub too** (PR-0260, GOT-02). |
| 10 | `:281` | `updateTutorialHints(dt:)` | `:333-355`; reads `core.snapshot.entities` only, never Core state. |
| 11 | `:282` | **`renderer.advanceVisuals(dt)`** | `RealityRenderer.swift:577-667`. Runs **before** `sync` by contract (§2). |
| 12 | `:283` | **`renderer.sync(core.snapshot)`** | `RealityRenderer.swift:196-470`; ends in `pools.sync(snap.entities)` (`EntityPools.swift:22-46`), which reconciles by stable snapshot id. |
| 13 | `:284` | `synth.musicPump(dt:world: core.snapshot.worldOrdinal)` | `SynthEngine.swift:126-135` → `rampMaster(dt)` (`:138-145`, ~0.15 s per unit) + `Music.pump`. The `world` argument is **deliberately discarded** (`:132-133`, owner decree: no per-world music). |
| 14 | `:285-289` | Game-over restart gate | `overTime` accumulation, `canRestart` once `overTime > 1.0`, `restartCountdown`. Both written only on change, to avoid spurious observation. |
| 15 | `:290` | `ageEffects()` | `:802-816` — popup pruning (>1.8 s), milestone-queue release (one per `milestoneSpacing = 1.0`, `:40`), toast expiry. |

**Inside step 9, the spawn call chain** (`GameCore.tick:175` → `spawn()`, `GameCore.swift:300-315`):

1. `spawner.fill(to: distance + Tuning.spawnHorizon, dist: distance, rng: &rng) { apply($0) }`
   (`:301`, `Tuning.spawnHorizon = 115`, `Tuning.swift:52`).
2. Then the **zero-RNG guaranteed power-up cadence** (`:307-314`): while `powerUpCursor < horizon`,
   `freeLaneNear(powerUpCursor)` (`:320-334` — scans the live obstacle set; a full-span
   bar/splitBar/movingTall within `Tuning.cadenceClearance` (5) blocks every lane → `nil` → the mark
   is skipped) then `apply(cadenceCommand(powerUpIndex, …))` (`:337-345`, cycling
   shield→magnet→doubler→chrono→superSneakers). `powerUpCursor += Tuning.powerUpCadence` (350) runs
   **unconditionally**; `powerUpIndex += 1` only inside the `if let lane` branch (`:311`).
3. `apply(_:)` (`:649`) is the single spawn sink — cap-gated and given a fresh `takeId()`.

**Where FX re-enter the meta layer.** FX are **not** part of the chain above. `GameCore.emit`
(`:735`) calls `onFX` synchronously **inside `tick`**, inside `advance`'s `while` loop.
`GameModel.handleFX` (`GameView.swift:508-601`) fans out in this order:

1. `renderer.fire(fx)` (`:509` → `RealityRenderer.swift:472-573`),
2. `haptics.handle(fx)` (`:510` → `Haptics.swift:35`),
3. the model's own `switch` — popups, SFX, and the per-run counters
   (`nearMissesThisRun` `:519`, `closesThisRun` `:522`, `slicksThisRun` `:525`, `slidesThisRun` `:575`).

**The one FX case that re-enters the meta layer is `.died`** (`:559-564`): it calls
`recordRunResults()` (`:564`), which performs 4–7 synchronous profile encodes + `UserDefaults`
writes + `cloud.synchronize()` calls **from inside the fixed-timestep tick loop** (PR-0258, PR-0030).
Nothing else in `handleFX` touches `ProfileStore`.

**HUD update is pulled, not pushed.** `HUDView` (`GameView.swift:1061`) holds `let core: GameCore`
and reads `core.snapshot` at the top of `body` (`HUDView.swift:12`). The per-frame `snapshot`
assignment (`GameCore.swift:718-733`) is the only observed mutation, and it invalidates every `body` that
read it — `GameView.body` at `:1068`, `:1090`, `:1110`, `:1145`, `:1169`, `:1178` included.

### 6.4 Death and game over

**Detection — exactly one site.** `stepObstacles` (`GameCore.swift:393-417`). Inside the kill band
`abs(z) < Tuning.obstacleZHalf` (0.95, `Tuning.swift:71`), with `mode == .play && invulnT <= 0`, one
of four predicates fires: `Collisions.barHit` / `splitBarHit` / `lowHit` / `tallHit` — the last taking
`canVault: superSneakersT > 0` (`:396-400`).

- **Shield held** (`:404-412`): `shield = false`, `invulnT = Tuning.invulnDuration`, `streak = 0`,
  `mult = 1`, `flowStreak = 0`, `emit(.shieldAbsorbed(x:))`, the obstacle is removed, `continue`. No
  death.
- **Otherwise** `die()` (`:414`), and the loop **deliberately falls through** (`:415`) — the entity
  stays and all subsequent logic is mode-guarded.

**`die()` (`GameCore.swift:577-584`)** computes the frozen score
(`Int(((distance - scoreOffset) * 2).rounded(.down)) + bonus`), records `deathDistance = distance`,
sets `mode = .over`, resets `streak`/`mult`/`flowStreak`, updates the in-core `best`, and emits
`.died(x: px)`.

**What freezes / what keeps moving:**

| | State |
|---|---|
| **Frozen** | `score` (`:578`, and `tick:197` only recomputes in `.play`), `lastRunDuration` (`GameView.swift:682`), the coin split, `previousBest`, `lastLevelUp`, `lastChallengePayout`. |
| **Still moving** | `distance` — it keeps integrating while `speed` decays at `Tuning.overDecel = 22`/s (`Tuning.swift:79`); see §3's mode table. `revive()` folds that drift into `scoreOffset` (`GameCore.swift:613`), which is the proof the drift is real. `uiClock`, the frame loop, the renderer, the decor and the particle system all keep running. |
| **Visibly wrong** | `GameOverView`'s DISTANCE tile is passed `runDistance: model.core.traveledDistance` — read live in `body`, which re-runs every frame — so it ticks upward for ~1.4 s past the value that was actually paid for (PR-0028). Its neighbour `timeSurvived: model.lastRunDuration` (`:1120`) is correctly frozen. |

**What the host does with `.died`** — `handleFX` case `.died` (`GameView.swift:559-564`), in order:
`flash(0.5)` → `synth.play(.crash)` → `synth.play(.deathSweep)` → `synth.musicStop()` →
`recordRunResults()`. `renderer.fire(.died)` (`RealityRenderer.swift:527-531`) and
`haptics.handle` already ran at `:509-510`.

**What is shown.** Once `rebuildSnapshot()` publishes `mode == .over`, `GameView.body:1109-1134`
constructs `GameOverView` with 22 arguments.

**What the player can do, and the tap cost:**

| Action | Callback | Gate | Taps |
|---|---|---|---|
| **CONTINUE** | `onRevive: { model.reviveForCoins() }` (`:1115` → `:460-474`) | `canRevive` (`:455-458`): `mode == .over && !isChallengeRun && core.revivesUsed < 2 && coins >= reviveCost`, where `reviveCost = 150 * (revivesUsed + 1)` (`:454`) | **1** — no confirmation step. Coins are spent, `core.revive()` (`GameCore.swift:607-630`) clears the field, keeps the lane, grants a shield, folds the decel drift into `scoreOffset`, zeroes `boostT`/`flowStreak`, **keeps magnet/doubler/chrono running by design** (`:619-622`), `speed = max(speed, speedStart)`, `spawner.cursor = distance + 70` |
| **RUN AGAIN** | `onRestart: { model.startRun() }` (`:1116`, button at `GameOverView.swift:100`) | `canRestart` — `overTime > 1.0` (`:286`), with a visible `restartCountdown` | **1**, after ≥1 s. Always `fromWorld: 0` (PR-0259) and it re-enters the loadout consumption path (PR-0011) |
| **MENU** | `onHome: { model.returnToMenu() }` (`:1117`, button at `GameOverView.swift:117`) | none | **1** |
| **GET COINS** | `onGetCoins` (`:1128`) — two call sites: the doubler upsell (`GameOverView.swift:231`) and the unaffordable-revive route (`:443`) | `totalRuns >= 3` for the upsell | **1** to the shop, then the shop's own purchase flow |
| **NEW CHARACTER** | `onCharacters` (`:1133` → `GameOverView.swift:333`) | a level unlock crossed this run | **1** |
| **FULL STATS** | `onFullStats` (`:1134` → `GameOverView.swift:387`) | none | **1** |

The mute (not pause) corner button stays visible (`GameView.swift:1068-1088`); `EffectsOverlay`
(`:1165`) and any open meta sheet (`:1145-1147`) render over the panel.

Two continues cost **150 + 300 = 450 coins** total (`reviveCost` at `GameView.swift:454`, with
`revivesUsed` starting at 0). `trace-run-lifecycle.md` §Suspicious 13 says "300 + 450 coins" — that
scratch file is wrong; `trace-findings.md` #5 and PR-0254 have the right figure.

### 6.5 Run summary → persistence

`recordRunResults()` — `GameView.swift:680-792`. Called on **every** death, so everything cumulative
is paid as a watermarked delta (iron rule 9).

**Order of operations:**

| # | line | Step |
|---|---|---|
| 1 | `:682` | `lastRunDuration = playTimeThisRun`. |
| 2 | `:685-688` | New-best fanfare, latched by `newBestCelebrated` so it fires once per run, compared against the *live* profile that the first death is about to overwrite. |
| 3 | `:696` | `let mult = store.profile.coinMultiplier * (coinSurgeActiveThisRun ? 2 : 1)` — Coin Surge captured at run start, so the basis cannot drift mid-run. Max ×4. |
| 4 | `:698-708` | The four coin components, each `max(0, cumulative × mult − watermark)`, watermark advanced immediately. |
| 5 | `:709-711` | `coinsDelta` = the four components summed; `lastCoinsEarned = coinsDelta`. Each component is an `Int` **before** the multiplier, so the panel's split sums exactly. |
| 6 | `:713-716` | `distanceDelta` / `gemsDelta` — same watermark shape against `distanceRecordedThisRun` / `gemsRecordedThisRun`. |
| 7 | `:722-724` | `reachWorld = ProfileStore.reachCredit(maxWorldThisRun:startWorld:reachAtStart:)` (`ProfileStore.swift:290-292`, `startWorld <= reachAtStart ? maxWorldThisRun : reachAtStart`). |
| 8 | `:726-775` | The two branches (below). |
| 9 | `:779-783` | Challenge folding (below). |
| 10 | `:787` | `checkSkinUnlocks()` — runs *after* the fresh XP / achievement / challenge-calendar state exists, so all three grant kinds land on the same death. |
| 11 | `:791` | Game Center submission (below). |

**The four coin components (`:698-708`):**

| Component | Formula | Watermark |
|---|---|---|
| gems | `core.gemCount * mult` | `gemCoinsAwarded` |
| distance | `Int(core.traveledDistance / 35) * mult` | `distCoinsAwarded` |
| worlds | `max(0, core.maxWorld − runStartWorld) * 5 * mult` | `worldCoinsAwarded` |
| style | `XPCurve.styleCoins(closes:slicks:multiplier:)` = `min(closes + slicks, 40) * 2 * mult` (`XPCurve.swift:75-77`) | `styleCoinsAwarded` |

**Branch A — post-revive death (`statsRecorded == true`, `:728-736`).** One `store.mutate` adding
`coinsDelta` to `coins` + `totalCoinsEarned`, maxing `bestScore`, adding `distanceDelta`/`gemsDelta`,
maxing `bestStreak` and `maxWorldReached`. **`totalRuns` is not incremented, `applyRunSummary` is not
called, missions are not fed** — a documented accepted loss (`:743-746`) that also makes
`RunSummary.revives` structurally always 0 and the `revives` mission metric dead (PR-0255).

**Branch B — first death (`:737-775`).** `statsRecorded = true`, then:

1. `store.recordRun(score:distance:gems:bestStreak:maxWorld:coinsEarned:)` (`ProfileStore.swift:189-200`)
   — one `mutate`, `totalRuns += 1`. **Save #1.**
2. A `RunSummary` (`Meta/MissionCatalog.swift:6-18`) is assembled (`:746-758`) with
   `worldsCrossed = reachWorld + 1`, `startWorld = runStartWorld`, `revives = core.revivesUsed`
   (always 0 here), `duration = lastRunDuration`.
3. `store.applyRunSummary(summary)` (`ProfileStore.swift:427-474`) — result held as model state
   `lastLevelUp` (`:762`, G3).
4. If the level rose (`:763-774`): queue the LEVEL UP milestone, then one `store.mutate`
   (`:769-773`) granting `slowMoCharges += 2*levels`, `speedUpCharges += 2*levels`,
   `shieldCharges += levels`.

**`applyRunSummary` internals (`ProfileStore.swift:427-474`), exact order:**

1. `refreshDailyMissions(now:)` (`:428` → `:385-396`) — may `mutate` on a UTC day rollover.
2. `refreshWeeklyMissions(now:)` (`:429` → `:408-420`) — may `mutate` on a UTC week rollover.
3. `xp = XPCurve.xp(for: summary)` (`:430` → `XPCurve.swift:47-55`):
   `distance/10 + gems*2 + (closes+slicks)*5 + bestMult*10 + max(0, (worldsCrossed-1) − startWorld)*25`,
   clamped `0...2000`. Takes only a `RunSummary`, so `doubleCoins` structurally cannot inflate XP.
4. `before`/`after` from `XPCurve.level(for:)` (`:431-432`).
5. **Watermarked level grant** (`:435-439`): `firstUnpaid = max(before, profile.xpLevelRewarded) + 1`;
   if `firstUnpaid <= after`, sum `XPCurve.coinGrant(forLevel:)` over the band. This is what stops a
   cloud merge that raises the level without a run from double-paying.
6. One `mutate` (`:440-469`): `totalXP += xp`; the grant into `coins` + `totalCoinsEarned`;
   `xpLevelRewarded = max(_, after)`; the per-world `bestDistanceByWorld` credit loop with its
   `into > 0` guard (`:445-454`); per-run missions by max (`:455-459`, **no `v > 0` guard** — writes
   permanent 0-valued keys, PR-0172); daily, weekly and achievement bumps via `Self.bump`
   (`:460-468`, max-style for `accumulatesByMax` metrics, additive otherwise).
7. Returns `LevelUpResult` with the crossed `XPCurve.xpUnlockLevels` (`:470-473`).

**Challenge folding (`GameView.swift:779-783`)** — only when `isChallengeRun`:
`lastChallengePayout = store.recordChallengeRun(score:)` (`ProfileStore.swift:591-610` — per-UTC-day
best, `challengeDaysPlayed` insert trimmed to 60 entries, tier watermark `challengeRewardTier` over
`challengeTiers = [(1000,100),(5000,150),(15000,250)]` (`:584`), payout into `coins` +
`totalCoinsEarned`; `sameDay` routes through `clamped()` so clock rollback is handled), then
`GameCenterService.shared.submitDailyChallenge(score:day: ProfileStore.daysSinceEpoch(Date()))`
(`:781-782`).

**Game Center submission (`:791`).** `GameCenterService.shared.submitRun(score: core.score,
usedCheckpoint: core.usedCheckpoint)`.

| Condition | Behaviour | file:line |
|---|---|---|
| `usedCheckpoint == true` | **The only skip.** Returns immediately | `GameCenterService.swift:32-33` |
| `!authenticated \|\| score <= 0` | Silently dropped, no queue, no retry | `:38` (PR-0271) |
| otherwise | `Task { try? await GKLeaderboard.submitScore(_:context: 0, player:leaderboardIDs: ["prismrush.best"]) }` | `:39-42` |
| daily challenge | Same shape against `"prismrush.daily"`, UTC day as the score `context` | `:47-53` |

Revived runs are **not** excluded — `core.revive()` never sets `usedCheckpoint`, so a paid continue
is fully leaderboard-eligible (PR-0254; iron rule 10 names only checkpoints).

The `Task` at `GameCenterService.swift:39`/`:49` is a plain `Task { }` inside a `@MainActor` method
and therefore **inherits MainActor isolation**. `trace-run-lifecycle.md` §5.9 calls it a "detached
`Task`" — that scratch file is wrong; grep confirms zero `Task.detached` in the repo.

**How many times the profile is encoded and written.** `ProfileStore.mutate` (`:90-93`) calls `save()`
(`:620-627`) **synchronously**, every time, with no batching. A first-death `recordRunResults` can
therefore perform **4–7 full encode + `UserDefaults.set` + `cloud.set` + `cloud.synchronize()` round
trips in one frame**:

| # | Source | file:line | Conditional? |
|---|---|---|---|
| 1 | `recordRun` | `ProfileStore.swift:190` | always (first death) |
| 2 | `refreshDailyMissions` | `:389` | UTC day rollover only |
| 3 | `refreshWeeklyMissions` | `:413` | UTC week rollover only |
| 4 | `applyRunSummary` body | `:440` | always |
| 5 | level-up charge grant | `GameView.swift:769` | on level-up |
| 6 | `recordChallengeRun` | `ProfileStore.swift:597` | challenge runs only |
| 7 | `refreshSkinUnlocks` | `:229` | when a character is granted |

All of it executes from `emit(.died)` inside `GameCore.tick`, inside `advance`'s `while` loop, inside
the `SceneEvents.Update` callback — a hitch on the exact frame the player dies (PR-0258, PR-0030).

**When iCloud sync fires.** On every one of those saves: `cloud.set(data, forKey: localKey)` then
`cloud.synchronize()` (`ProfileStore.swift:624-625`). Inbound merges arrive on the observer at
`:38-43` → `mergeFromCloud()` (`:692-698`) — see §7.4.

### 6.6 Back to menu

**`returnToMenu()` — `GameView.swift:495-504`.** Eight assignments, no more: `paused = false`;
`core.reset(seed: nil)`; `renderer.resetEntities()`; `synth.musicStart(calm: true)` (back to the hub
bed — explicitly *not* `musicStop`); `activeSheet = nil`; `overTime = 0`; `canRestart = false`;
`restartCountdown = 0`.

**Torn down:**

| What | file:line | Detail |
|---|---|---|
| Sim state | `GameCore.reset` (`GameCore.swift:138-154`) | Reseeds the RNG, **replaces the `Spawner` value**, zeroes every sim field except `best`, empties the three entity arrays `keepingCapacity: true`, zeroes `accumulator`/`nextId`/`powerUpCursor`/`powerUpIndex`. Note it does **not** call `rebuildSnapshot()` (PR-0029). |
| Render state | `RealityRenderer.resetEntities` (`:669-694`) | `pools.releaseAll()`, `particles.reset()`, zeroes ~20 camera/pose/emission-debt fields, disables the ring pulse, the shield dome and all 4 skids, `decor.reset(distance: 0)`. Leaves `paletteKey`, `elapsed`, `blinkT`, `auraSpin`, `shimmerStep`, `skidCursor` untouched (PR-0274). |

**Reused across runs, never rebuilt:** `GameModel` and all four subsystems; the entire RealityKit
scene graph under `root` (camera, backdrop, ground, lane lines, rungs, skids, ring pulse, shield
dome, player rig); every pooled entity in `EntityPools`; the audio engine, its SFX buffer cache and
the `Music` sequencer; the `SceneEvents.Update` subscription; `ProfileStore.shared`;
`IAPManager.shared`; `GameCenterService.shared`; and `core.best`.

**Rebuilt every run (not a leak, but not free):** `applyCurrentSkin()` at `beginRun:368` →
`RealityRenderer.applySkin` (`:701`) → `rebuildCharacter()` (`:810-823`) tears down and re-creates
the whole character rig on every run start.

**Survives a run and arguably should not:**

| State | file:line | Consequence |
|---|---|---|
| `isChallengeRun` | not cleared by `returnToMenu` (`:495-504`); only reset at `beginRun:389` | Harmless today because every consumer also gates on `mode` (`:456`, `:837`, `:857`, `:875`, `:1178`); a latent trap for any menu-side consumer (PR-0273) |
| `lastCoinsEarned`, `lastCoinsFrom*`, `lastLevelUp`, `lastChallengePayout`, `lastRunDuration`, `previousBest` | `GameView.swift:67-86` | Stale run state living on the hub; invisible only because `GameOverView` is the sole reader |
| `hintsShown`, `tutorialActive`, `tutorialHint` | reset in `beginRun:414-417`, not in `returnToMenu` | Cosmetic |
| `Haptics.clock`, `Haptics.lastGem` | `Services/Haptics.swift:14-15` | Grow monotonically for the app's lifetime |
| `Music.beat`, `Music.scheduledFrames` | `Audio/Music.swift:12-13` (zeroed only by `start`, `:37-38`) | Same |
| `RealityRenderer.reduceMotionObserver`, `SynthEngine.observers` | `:115` / `SynthEngine.swift:24` | Stored but never removed — there is **no `deinit` and no `removeObserver` anywhere in `PrismRush/`** (grep-verified). Inert while only one `GameModel` exists (PR-0270, PR-0278) |

### 6.7 Where the trace could not follow the code

These are gaps in the *source trace*, not in the code. A session that needs any of them must open the
file, not this document.

| Gap | Why it matters |
|---|---|
| `Core/Patterns.swift` — `Patterns.run(_:base:rng:out:)` and the 12 pattern bodies were not read line by line. | §4's RNG list is derived from the call sites, not from inside each pattern. Iron rule 3's "one extra `rng.unit()` changes every seeded run" is asserted, not verified per pattern. |
| `Core/Collisions.swift` — the kill / near-miss / ring / pad predicates are cited by name only. | Whether `tallHit(canVault:)` can produce a false clear, and the exact near-miss geometry, are unverified. |
| `Render/Reality/WorldDecor.swift` + the ten `*Sky` classes. | What `decor.reset(distance: 0)` (`RealityRenderer.swift:693`) actually leaves behind on a **checkpoint** start is unverified beyond the comment's claim that the recycle loop self-heals on the first update. |
| `Render/Reality/ParticleSystem.swift` — `step`/`burst`/`ring`/`reset`. | Particle budget, and whether `reset()` fully drains live particles across runs. |
| `Audio/Synth.swift` — `step(beat:world:)` and `SFX.samples`. | Only scheduling and volume envelopes were traced, not the DSP. |
| `Core/Autopilot.swift` — `Autopilot.drive`. | Driven once per **frame** at `GameView.swift:269-271`, not once per tick. Whether the 200-seed solvability bot drives ticks directly (and therefore whether the two agree) was not confirmed. |
| `IAP/IAPManager.swift` beyond `listenForTransactions` (`:201-212`). | A `Transaction.updates` grant mutates the profile via `applyOncePerTransaction` (`ProfileStore.swift:161-168`) and can in principle land mid-run; whether it can interleave with the death-frame mutations was not established. |
| `Services/AccountService.swift`. | Never referenced anywhere in the run lifecycle. Only `ProfileView:11` touches it; what constructs it and when is untraced. |
| **SwiftUI ordering between the `RealityView` make closure (`GameView.swift:1051`) and `SplashView.body` (`SplashView.swift:20`).** | Both touch `ProfileStore.shared`, and one of them pays the synchronous UserDefaults + iCloud load. Which runs first could not be determined statically, so it is unknown whether the splash renders the pre- or post-`sanitized` equipped skin on a cold launch with a stale selection. |
| **Whether SwiftUI re-initializes the `GameView` value.** | GOT-01 / PR-0270's real severity. Establishing it needs a runtime counter in `GameModel.init`; a read-only survey cannot. `RootView.body` (`App/RootView.swift:12-18`) observes nothing today, which is the only reason it is currently benign. |

---

## 7. Persistence

Everything the player keeps between launches is one `Profile` value. `ProfileStore` is the only thing
that encodes, decodes, or writes it. There are **no files**, no database, no Core Data — two key/value
stores and (for Sign in with Apple only) two Keychain items.

### 7.1 What is stored and where

| Store | Key | Value | Written at | Read at |
|---|---|---|---|---|
| `UserDefaults.standard` | **`"pr.profile.v1"`** | `Data` — `JSONEncoder().encode(profile)` | `ProfileStore.save():622` | `loadLocal():630`, `load(localKey:cloud:):704` |
| `NSUbiquitousKeyValueStore.default` | **`"pr.profile.v1"`** — the *same* key string | the same `Data` blob | `save():624`, then `cloud.synchronize():625` | `mergeFromCloud():693`, `load():701` |
| `UserDefaults.standard` | `"pr.device.id"` | `String` (a `UUID().uuidString`) | `persistentDeviceKey():56` | `:54` |
| `UserDefaults.standard` | `"pr.appleUserID"`, `"pr.appleName"` | `String` — **legacy only**, migrated to Keychain then deleted | never written now | `AccountService.loadMigrating():24-32` |
| Keychain (generic password) | account `"pr.appleUserID"`, `"pr.appleName"` | UTF-8 `String`, `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` (`Services/Keychain.swift:20`) — never iCloud-Keychain-synced | `AccountService.handle():74,77` | `Keychain.get()` via `loadMigrating():25`; key names at `AccountService.swift:14` |

`localKey` is declared once (`ProfileStore.swift:14`) but **duplicated as a literal** at `:36`, because
`init()` cannot read `self.localKey` before `profile` is assigned. If the two ever drift the app loads
one key and saves to another — a silent total save wipe (PR-0002-adjacent; tracked as a SEV3 with a
SEV0 failure mode).

The KVS is enabled by
`com.apple.developer.ubiquity-kvstore-identifier: $(TeamIdentifierPrefix)$(CFBundleIdentifier)` in
`project.yml`.

**Encoding.** Default `JSONEncoder` — no key strategy, no date strategy. Consequences:

- `Date?` fields serialize as `Double` seconds since the **2001 reference date**, not ISO-8601 or Unix.
- `Set<String>` / `Set<Int>` / `Set<UInt64>` serialize as JSON **arrays** with unstable ordering —
  byte-comparing two saves is meaningless.
- `bestDistanceByWorld: [Int: Double]` is a non-`String`-keyed dictionary, so Swift encodes it as a
  flat alternating `[key, value, key, value…]` array, not an object.
- `encode(to:)` is **synthesized**; `init(from:)` is hand-written (`Profile.swift:124-171`).

**Every persisted field.** 44 stored properties, 44 `CodingKeys` cases (`Profile.swift:109-122`),
44 `decodeIfPresent` lines (`:127-170`), in decode order. "Merged how" refers to
`ProfileStore.merged(local:remote:)` (`:657-689`) — see §7.4.

| # | field | type | default | decode | merged how |
|---:|---|---|---|---:|---|
| 1 | `coins` | `Int` | `0` | 127 | special: `max(local, remote)` + purchased-credit (`:662-663`) — **unsound, PR-0002 / PR-0252** |
| 2 | `slowMoCharges` | `Int` | **`2`** | 128 | kept from local — documented deliberate (`:643-648`) |
| 3 | `speedUpCharges` | `Int` | **`2`** | 129 | kept from local — documented deliberate |
| 4 | `shieldCharges` | `Int` | **`1`** | 130 | kept from local — documented deliberate |
| 5 | `headStartCharges` | `Int` | **`1`** | 131 | kept from local — documented deliberate |
| 6 | `coinSurgeCharges` | `Int` | **`1`** | 132 | kept from local — documented deliberate |
| 7 | `bestScore` | `Int` | `0` | 133 | `max` (`:666`) |
| 8 | `totalRuns` | `Int` | `0` | 134 | kept from local — **undocumented, PR-0036** |
| 9 | `totalDistance` | `Double` | `0` | 135 | kept from local — **undocumented, PR-0036** |
| 10 | `totalGems` | `Int` | `0` | 136 | kept from local — **undocumented, PR-0036** |
| 11 | `totalCoinsEarned` | `Int` | `0` | 137 | kept from local — **undocumented, PR-0036** |
| 12 | `bestStreak` | `Int` | `0` | 138 | kept from local — **undocumented, PR-0036** (a *record*, unlike its `bestScore` sibling) |
| 13 | `maxWorldReached` | `Int` | `0` | 139 | `max` (`:667`); earned-by-play only |
| 14 | `ownedSkins` | `Set<String>` | `["default"]` | 140 | union (`:669`) |
| 15 | `selectedSkin` | `String` | `"default"` | 141 | kept from local, then healed against the merged ownership (`:687`) |
| 16 | `lastDailyClaim` | `Date?` | `nil` | 142 | kept from local — **PR-0253** (farmable) |
| 17 | `loginStreak` | `Int` | `0` | 143 | kept from local — undocumented |
| 18 | `lastChestOpen` | `Date?` | `nil` | 144 | kept from local — **PR-0253** (farmable) |
| 19 | `missionProgress` | `[String: Double]` | `[:]` | 145 | per-key `max` (`:674`) |
| 20 | `claimedMissions` | `Set<String>` | `[]` | 146 | union (`:675`) |
| 21 | `achievementTier` | `[String: Int]` | `[:]` | 147 | per-key `max` (`:676`) |
| 22 | `dailyMissionDate` | `Date?` | `nil` | 148 | kept from local — undocumented |
| 23 | `dailyChallengeBest` | `Int` | `0` | 149 | kept from local — undocumented |
| 24 | `dailyChallengeDate` | `Date?` | `nil` | 150 | kept from local — undocumented |
| 25 | `challengeDaysPlayed` | `Set<String>` | `[]` | 151 | union (`:677`), **not re-trimmed** (the 60-cap only applies on write, `:602-605`) |
| 26 | `doubleCoins` | `Bool` | `false` | 152 | OR (`:671`) — **PR-0003** |
| 27 | `ownedProducts` | `Set<String>` | `[]` | 153 | union (`:670`) — **PR-0003** |
| 28 | `muted` | `Bool` | `false` | 154 | kept from local — undocumented |
| 29 | `reduceFlash` | `Bool` | `false` | 155 | kept from local — undocumented |
| 30 | `musicVolume` | `Double` | `1` | 156 | kept from local — undocumented |
| 31 | `menuMusicVolume` | `Double` | `1` | 157 | kept from local — undocumented |
| 32 | `sfxVolume` | `Double` | `1` | 158 | kept from local — undocumented |
| 33 | `hapticsEnabled` | `Bool` | **`true`** | 159 | kept from local — undocumented |
| 34 | `bestDistanceByWorld` | `[Int: Double]` | `[:]` | 160 | per-key `max` (`:681`); keys are permanent |
| 35 | `totalXP` | `Int` | `0` | 161 | `max` (`:678`) |
| 36 | `xpLevelRewarded` | `Int` | **`1`** | 162 | `max` (`:679`) — the level-grant watermark |
| 37 | `seenSkins` | `Set<String>` | `["default"]` | 163 | union (`:680`) |
| 38 | `weeklyMissionDate` | `Date?` | `nil` | 164 | kept from local — documented deliberate |
| 39 | `challengeRewardTier` | `Int` | `0` | 165 | kept from local — documented deliberate |
| 40 | `purchasedWorlds` | `Set<Int>` | `[]` | 166 | union (`:668`) — **PR-0003** |
| 41 | `totalIAPPurchases` | `Int` | `0` | 167 | `max` (`:672`) |
| 42 | `firstPurchaseBonusUsed` | `Bool` | `false` | 168 | OR (`:673`) |
| 43 | `coinsPurchasedByDevice` | `[String: Int]` | `[:]` | 169 | per-key `max` G-counter (`:660-661`) |
| 44 | `grantedTransactionIDs` | `Set<UInt64>` | `[]` | 170 | union then re-trim to 512 (`:664-665`) |

Derived, never stored: `coinMultiplier` (`Profile.swift:83`), `totalCoinsPurchased` (`:86`),
`playerLevel` (`ProfileStore.swift:217`), `equippedSkinID` (`:214`).

Bounded: `grantedTransactionIDs` (512, `Profile.swift:93-103`), `challengeDaysPlayed` (60,
`ProfileStore.swift:602-605`). **Unbounded and grow-only:** `bestDistanceByWorld`, `purchasedWorlds`,
`missionProgress`, `achievementTier`, `ownedSkins`, `seenSkins`, `coinsPurchasedByDevice` (one slot
per install; `pr.device.id` is regenerated on reinstall). Nothing checks the encoded size against the
1 MB KVS ceiling (PR-0279).

### 7.2 Save triggers

**There is exactly one write path.** `save()` (`ProfileStore.swift:620-627`) is `private` and called
from `mutate(_:)` (`:90-93`) **and nowhere else**. `mergeFromCloud` (`:697`) is the one sanctioned
assignment outside `mutate`, and it calls `save()` itself. Every write is therefore, synchronously on
the main actor: `JSONEncoder().encode` → `UserDefaults.standard.set` → `cloud.set` →
`cloud.synchronize()`. No debounce, no batching, no background queue.

**Every `mutate` call site in the app** (grep-verified, excluding `func mutate` itself):

| File | line(s) | Trigger |
|---|---|---|
| `Meta/ProfileStore.swift` | 95 | `addCoins` |
| | 100 | `spendCoins` |
| | 124 | `buyConsumablePack` (atomic spend+grant) |
| | 139 | `openMysteryBox` |
| | 163 | `applyOncePerTransaction` (records the id in the **same** mutate as the grant) |
| | 190 | `recordRun` |
| | 205 / 206 | `unlock(skin:)` / `select(skin:)` |
| | 229 | `refreshSkinUnlocks` |
| | 236 | `markSkinsSeen` |
| | 278 | `unlockWorld` — **a second save after `spendCoins`** (`:277`), so the purchase is not atomic; a crash between them debits the coins without granting the world (**PR-0177**) |
| | 324 | `claimDailyReward` |
| | 343 | `openFreeChest` |
| | 389 | `refreshDailyMissions` (UTC day rollover) |
| | 413 | `refreshWeeklyMissions` (UTC week rollover) |
| | 440 | `applyRunSummary` |
| | 544 | `claimMission` |
| | 597 | `recordChallengeRun` |
| `UI/GameView.swift` | 157, 196, 231, 236 | Debug env pins (`PR_DEMOPROFILE`, `PR_SKIN`, `PR_DEEPWORLDS`, `PR_FIRSTRUN`) |
| | 376, 381 | Head Start / Coin Surge consumption at run start |
| | 606 | `toggleMute` |
| | 728 | post-revive death payout |
| | 769 | level-up charge grant |
| | 850, 869, 888 | Slow-Mo / Speed Up / Shield deploys — **one save per in-run button press** |
| `UI/SettingsView.swift` | 77, 80, 83 | Volume sliders — the positions live in `@State` seeded in `init` (`:13-15`, `:22-28`) and commit **once per gesture** on `!editing` (`:104-105`), not per drag frame. That `init` snapshot is a deliberate G3 exception and can write stale values back over an iCloud merge (PR-0281) |
| | 120, 127 | Haptics / Reduce Flash toggles |
| `IAP/IAPCatalog.swift` | 72, 74 | `restore` of a non-consumable (`apply` writes via `applyOncePerTransaction`/`grantCoinPack`) |

**A single death produces 4–7 full writes.** The chain and its conditionals are tabulated in §6.5.
The minimum for a first death with no rollovers, no level-up, no challenge and no character grant is
**2** (`recordRun` + the `applyRunSummary` body); the maximum is **7**. A post-revive death produces
exactly **1** (`GameView.swift:728`).

**Reading can also write.** `MenuView`'s `navRail` (was `RewardsBar.swift:23`) calls `store.unclaimedCount(now:)` from inside a
`TimelineView` body; `unclaimedCount` (`ProfileStore.swift:558`) reaches `refreshDailyMissions` /
`refreshWeeklyMissions`, both of which `mutate` on a rollover. Same shape at `MissionsView.swift:41,43`.
This is a state mutation during view evaluation of the observed object (PR-0006). It converges today
only because `refreshDailyMissions` early-returns once the stored day matches (`:387`).

### 7.3 The decode discipline

Iron rule 7: **every `Profile` field is `decodeIfPresent … ?? default`**.

**Held, completely.** All 44 stored properties appear in `CodingKeys` (`Profile.swift:109-122`) and
all 44 are decoded via `decodeIfPresent` against a locally-constructed `let d = Profile()` (`:126`).
There is **no `decode(_:forKey:)` (throwing) call anywhere** in `init(from:)` and no field without a
default. Adding a field to the struct but forgetting `CodingKeys`/decode makes it silently use the
memberwise default forever — harmless. Using `decode(_:forKey:)` instead would make **every existing
save fail to load**.

**What it does NOT protect against.** `decodeIfPresent` guards a *missing* key. It does nothing about:

| Failure | Effect | file:line |
|---|---|---|
| A **type change** on an existing key (`coins: Int` → `Double`, or changing `bestDistanceByWorld`'s key type) | `decodeIfPresent` throws, the `try?` swallows it, and both loaders fall through to `return Profile()` — **every existing player launches into a brand-new profile with no coins, no skins, no stats, no error, no backup, no diagnostic** | `ProfileStore.swift:631` → `:634`; `:701`/`:704` → `:707` (**PR-0250**) |
| A **truncated or corrupt blob** (a KVS partial write) | Identical: total silent wipe | same |
| A **renamed `CodingKeys` case** | The old key is ignored and the field silently resets to its default. Decoding tolerates *extra* keys, so a rename is a one-way data loss | `Profile.swift:109-122` |
| **Out-of-range values** | Nothing clamps them. A hand-set `coins: -5` persists and makes every price unaffordable (`spendCoins` guards `>=`, so gameplay never produces it) | `sanitized(_:now:)` is the only validation, `:70-79` (PR-0282) |
| **Cross-field inconsistency** | Nothing checks `xpLevelRewarded` vs `totalXP`, or `challengeRewardTier` vs `dailyChallengeDate` | — |
| **Forged entitlements** | No signature, no checksum, no receipt cross-check. `Transaction.currentEntitlements` is consulted only at `start()` and on explicit restore, and only ever *adds* — `transaction.revocationDate` is never read anywhere in the codebase | `IAPManager.swift:193-199` (PR-0034, PR-0003) |
| **Encode failure** | `save()` is `guard persisting, let data = try? JSONEncoder().encode(profile) else { return }` — the session silently stops persisting, with no log and no user signal | `ProfileStore.swift:621` |

**The only load-time validation** is `sanitized(_:now:)` (`:70-79`), applied to the loaded profile in
both `init()` branches (`:35`, `:46`) and to the decoded remote in `mergeFromCloud` (`:695`) — but
**not** to the merge *result*. It does exactly two things: clamps the five stored timestamps
(`lastDailyClaim`, `lastChestOpen`, `dailyMissionDate`, `dailyChallengeDate`, `weeklyMissionDate`)
down to `now`, and resets `selectedSkin` to `"default"` if it is not in `ownedSkins`.

Every clamp in the codebase (`sanitized:70`, `clamped(_:now:) = min(stored, now)` at `:83`, the inline
`min(last, now)` at `:387` and `:411`) defends against setting the clock **backwards**. Nothing
defends against setting it **forwards**, which farms both timed faucets (PR-0035).

### 7.4 iCloud merge semantics

**Two entirely different code paths, and only one of them merges.**

| Path | Function | Behaviour |
|---|---|---|
| **Cold launch** | `load(localKey:cloud:)` (`:700-708`) | Returns the **cloud** blob if it decodes; otherwise the local blob; otherwise a fresh `Profile()`. **No merge.** A stale cloud snapshot silently replaces a newer local save — **PR-0005**. |
| **External change while running** | `didChangeExternallyNotification` observer (`:38-43`, `queue: .main`, wrapped in `MainActor.assumeIsolated`) → `mergeFromCloud()` (`:692-698`) | decode → `sanitized(remote)` → `Self.merged(local: profile, remote:)` → if different, assign and `save()` (which writes straight back to the cloud; `merged` is idempotent so two devices bounce one round and converge). |

**`merged(local:remote:)` (`:657-689`) is pure and `static`, so it pins in the Linux SPM suite.** It
starts from `var merged = local` (`:658`) — **every field it does not name keeps the local value.**

| Strategy | Fields | line |
|---|---|---|
| **`max`** | `bestScore`, `maxWorldReached`, `totalIAPPurchases`, `totalXP`, `xpLevelRewarded` | 666, 667, 672, 678, 679 |
| **union (`formUnion`)** | `grantedTransactionIDs` (then re-trimmed to 512), `purchasedWorlds`, `ownedSkins`, `ownedProducts`, `claimedMissions`, `challengeDaysPlayed`, `seenSkins` | 664-665, 668, 669, 670, 675, 677, 680 |
| **OR (`\|\|`)** | `doubleCoins`, `firstPurchaseBonusUsed` | 671, 673 |
| **per-key `max` map** | `missionProgress`, `achievementTier`, `bestDistanceByWorld`, `coinsPurchasedByDevice` | 674, 676, 681, 660-661 |
| **special** | `coins` = `max(local.coins, remote.coins) + max(0, mergedTotalPurchased − winnerPurchased)`, where `winnerPurchased` is the coin-max winner's *pre-merge* `totalCoinsPurchased` | 659-663 |
| **final heal** | `selectedSkin` → `"default"` if not in the merged `ownedSkins` — deliberately **after** the ownership union, so a selection whose unlock arrives in this merge survives | 687 |
| **silently kept from local, documented as deliberate** | the five consumable counters, `weeklyMissionDate`, `challengeRewardTier` | docstring 641-648 |
| **silently kept from local, NOT documented** | `totalRuns`, `totalDistance`, `totalGems`, `totalCoinsEarned`, `bestStreak`, `loginStreak`, `dailyChallengeBest`, `lastDailyClaim`, `lastChestOpen`, `dailyMissionDate`, `dailyChallengeDate`, and all six settings | — |

**Which of these are unsound.** Stated plainly, with the backlog IDs — do not re-derive them:

| Behaviour | Backlog |
|---|---|
| The `coins` credit term re-pays real-money coins that were already spent, because `totalCoinsPurchased` is grow-only while the balance shrinks. Repeatable once per stale device. | **PR-0002** |
| The KVS blob is an **unauthenticated entitlement source**: `mergeFromCloud` validates only JSON well-formedness, then unions `ownedSkins`/`ownedProducts`/`purchasedWorlds` and ORs `doubleCoins`. Nothing re-derives entitlements from `Transaction.currentEntitlements`. | **PR-0003** |
| `load()` prefers the cloud blob outright with no merge, so a stale cloud snapshot discards a newer local save at launch. | **PR-0005** |
| A decode throw on either loader silently substitutes a brand-new `Profile()`. | **PR-0250** |
| `max`-merging the balance while unioning the purchases resurrects spent coins and keeps the item — two devices plus airplane mode, no hex editing. | **PR-0252** |
| `lastDailyClaim` / `lastChestOpen` are not merged, so the daily bonus and the 30-minute chest are farmable by alternating devices while `coins` max-merges. | **PR-0253** |
| Five lifetime stats plus `loginStreak` are silently not merged and are then pushed to the cloud, destroying the other device's higher counters. | **PR-0036** |
| Fabricated `coinsPurchasedByDevice` slots make the credit term re-grant a forged balance on every sync. | **PR-0283** |
| The KVS payload has unbounded growth vectors and no size check against the 1 MB ceiling. | **PR-0279** |

**Sound by construction:** the per-key-max G-counter shape itself (`coinsPurchasedByDevice`, keyed by
the never-synced `pr.device.id`, so two installs can never write the same slot); the `xpLevelRewarded`
watermark paired with `max`-merged `totalXP` (a merge that raises the level without a run cannot
double-pay); the deliberate device-local consumable counters (a `max` merge would resurrect spent
charges every sync, which is strictly worse); and the post-union `selectedSkin` heal.

### 7.5 What a future session must not break

Imperative rules. Each is falsifiable against the cited line.

1. **Never add a `Profile` field without all three of: a default in the struct, a `CodingKeys` case
   (`Profile.swift:109-122`), and a `decodeIfPresent … ?? d.<field>` line (`:127-170`).** Count them:
   44 / 44 / 44 today. Never use throwing `decode(_:forKey:)` in `init(from:)`.
2. **Never change the type of an existing key, and never rename a `CodingKeys` case.** A type change
   throws and the throw is swallowed into a fresh profile (PR-0250); a rename silently resets the
   field. If a type must change, add a *new* key and migrate from the old one — and land the
   quarantine fix from PR-0250 **before** the release that would trigger it, not after.
3. **Never change either `"pr.profile.v1"` literal without changing the other** (`ProfileStore.swift:14`
   and `:36`). Divergence means the app loads one key and saves to another: a silent, total, permanent
   save wipe.
4. **Never write `profile` outside `mutate(_:)`.** The single sanctioned exception is
   `mergeFromCloud:697`, which calls `save()` itself. Any other assignment never reaches UserDefaults
   or iCloud.
5. **Never add a run payout without its own watermark.** `recordRunResults` runs once per *death*, not
   once per run; every cumulative component is `max(0, cumulative − alreadyAwarded)`. Current
   watermarks: `gemCoinsAwarded`, `distCoinsAwarded`, `worldCoinsAwarded`, `styleCoinsAwarded`,
   `distanceRecordedThisRun`, `gemsRecordedThisRun` (`GameView.swift:698-716`). A new component
   without one re-pays the whole run on the second death.
6. **Never call `applyRunSummary` more than once per run.** It is gated by `statsRecorded`
   (`GameView.swift:726`/`:738`). A second call double-counts `runsFinished` (a constant 1 per call)
   and double-accumulates every sum-style daily/weekly metric.
7. **Never lower `xpLevelRewarded`, and never make `totalXP` merge as `max` while `xpLevelRewarded`
   does not** (`ProfileStore.swift:436-439`, `:443`, `:678-679`). That pairing is the only thing
   stopping a cloud merge from re-paying level grants.
8. **Never fold `purchasedWorlds` into `maxWorldReached`.** `unlockWorld` (`:274-280`) must never touch
   it, and `recordRunResults` must keep folding `reachCredit(...)` (`:290-292`), not `core.maxWorld`.
   Breaking this collapses the 59,400-coin world ladder to its deepest purchased rung and pays
   `ach.worlds` for worlds never crossed.
9. **Never split a grant from its replay marker.** `applyOncePerTransaction` (`:161-168`) records the
   StoreKit id in the **same** `mutate` as the payout. Two `mutate` calls mean a crash between them
   re-pays.
10. **Never credit `totalCoinsEarned` from a purchased or gacha payout.** `grantCoinPack` (`:177`) and
    `applyGrant` (`:109`) deliberately skip it, which is what keeps coin-earned missions and
    achievements unbuyable.
11. **Never `max()`-merge the five consumable counters** (`:682-683`). It would resurrect spent charges
    on every sync. Keep them device-local until a per-device earned/spent G-counter exists.
12. **Every new progression field defaults to "keep local" in `merged`.** Adding a field without a
    merge line is a silent decision, not a neutral one — decide explicitly and record it in the
    docstring at `:637-656`.
13. **Never widen the frozen IAP identifier triple** (`IAPCatalog` ↔ `Products.storekit` ↔ App Store
    Connect). `StoreAvailability.afterLoad` requires the full catalog, so an 8th product added in one
    place and not the others downgrades every user to `.notConfigured`.
14. **A skin id, mission id, product id or `coinsPurchasedByDevice` device key is a persistence key.**
    Never reuse one for different semantics (stated at `MissionCatalog.swift:74-75`).
15. **`Skin` must stay non-`Codable`** (`SkinCatalog.swift:9`). Only ids are persisted, which is what
    keeps catalog edits from becoming save migrations.
16. **Run the SPM suite for any change here.** `merged`, `reachCredit`, `coinPackPayout`, `sanitized`,
    `XPCurve` and the whole mission pipeline are `static`/pure precisely so they pin on Linux in
    `swift test -c release` with no simulator.

---

## 8. Invariants

Every entry below is a property the shipped build currently holds and that something else depends
on. Each names the file that owns it, states the property in falsifiable terms, says what edit
breaks it, and names the test that would go red — or says **nothing — untested**, which means the
only thing standing between a future session and a silent regression is this line. Untested
invariants are not weaker claims; they are the expensive ones. IDs are stable: cite them
(`INV-14`) in commit messages and PR descriptions rather than restating the rule.

### 8.1 Simulation and determinism (INV-01 … INV-30)

**INV-01 (Core/ — all 10 files)** — Every file under `PrismRush/Core/` imports `Foundation` and
nothing else, except `GameCore.swift:2` which also imports `Observation` (Linux-available). No
UIKit, SwiftUI, RealityKit, AVFoundation, StoreKit or GameKit anywhere in the layer.
*Breaks if:* a session reaches for `UIColor`, `CGFloat`, `@MainActor`-only UI types, or a
RealityKit vector type inside Core to save a conversion.
*Detected by:* the Linux SPM build — `swift test -c release` in
`.github/workflows/core-tests.yml` compiles `Core/` on `swift:6.0-noble`, where none of those
frameworks exist, so the import fails the job on every push and PR.

**INV-02 (Core/GameCore)** — Core performs no side effects. Its only outward channel is
`emit(_:)` → `onFX` (`PrismRush/Core/GameCore.swift:735`), a synchronous main-actor call made from
*inside* `tick`. An `onFX` handler must therefore never re-enter `GameCore` in a way that mutates
sim state — it is running in the middle of a half-finished step, inside `advance`'s `while` loop.
*Breaks if:* a handler calls `core.jump()`, `core.revive()`, `core.startRun(...)` or `core.reset()`
from an FX callback, or if Core starts playing audio / triggering haptics directly.
*Detected by:* nothing — untested. (Note the live handler chain already does heavy synchronous work
here: `handleFX` → `.died` performs 4–7 full profile encodes and `UserDefaults`/iCloud writes on the
death frame — see the run-lifecycle findings.)

**INV-03 (Core/GameCore, Core/DailyChallenge)** — Core reads no ambient state. There is no `Date()`
or `Calendar` anywhere in the layer — `DailyChallenge.seed(year:month:day:layoutVersion:)`
(`PrismRush/Core/DailyChallenge.swift:8`) takes the date components as parameters precisely so the
UTC derivation lives in Meta. The only two `.random` calls in all of Core are seed *entry* points:
the `GameCore.init` default (`GameCore.swift:81`) and `reset(seed: nil)` (`GameCore.swift:139`).
Both establish the stream; neither is consumed by the sim.
*Breaks if:* a session adds a third `.random`, or derives anything from wall-clock time inside a
tick. Iron rule 2 forbids it; the two existing sites are an explicit exemption, not a precedent.
*Detected by:* nothing — untested. Grep is the only enforcement:
`grep -rn "\.random\|Date()" PrismRush/Core/` must return exactly those two lines.

**INV-04 (Core/RNG, Core/Spawner, Core/Patterns)** — Exactly one `SplitMix64` instance exists per
`GameCore` and it is threaded `inout` all the way down `spawn()` → `Spawner.fill` → `Patterns.run`.
No sub-stream, no second generator, no re-seeding mid-run. `int`, `pick`, `chance` and `range` each
consume exactly one `unit()` = one `next()`.
*Breaks if:* a pattern creates its own local `SplitMix64`, or a helper takes `rng` by value.
*Detected by:* `PatternOrderTests.testTierLadderMonotoneAndRNGCountsPinned` (a local generator would
show up as a changed call count for that index); `RNGTests.testRunIsReproducible` catches a
by-value copy only if it makes the run non-reproducible within the same build.

**INV-05 (Core/Spawner, Core/Patterns)** — Total RNG calls per placed pattern are exactly
`1` (index draw, `Spawner.swift:39`) `+ {0,1}` (anti-repeat reroll, `Spawner.swift:44`) `+
patternCost[idx]`, where `patternCost = [1,1,0,1,1,3,1,2,0,1,1,1,2,0]` (see §4 for the per-site
breakdown). Consuming one extra `rng.unit()` anywhere in the spawn path silently rewrites every
seeded run from that point on.
*Breaks if:* a pattern gains a randomised variant, an existing `rng.int` moves across a branch, or
the reroll becomes a loop instead of a single bounded retry.
*Detected by:* `PatternOrderTests.testTierLadderMonotoneAndRNGCountsPinned`.

**INV-06 (Core/Patterns, Core/Spawner)** — Pattern order is load-bearing: the spawner gates by
prefix index (`Spawner.maxIndex(forDistance:)`, `Spawner.swift:24-31`, returns an *exclusive* upper
bound), so a tier can only ever add patterns, never remove or reorder them. `movingTall` is emitted
by index 13 (`Patterns.count − 1`) and by no other index; `ring` only by 9, `boostPad` only by 10,
`splitBar` only by 12; index 10 emits exactly 1 pad + 24 gems and nothing lethal.
*Breaks if:* a session reorders `Patterns.run`'s switch or inserts a pattern mid-catalogue — a
moving wall reachable from any other index escapes the `movingWallMinDiff = 0.6` (1,920 m) gate and
World 2 stops being fair.
*Detected by:* `PatternOrderTests.testCatalogueOrderAndPatternIdentity`;
`DifficultyTests.testWorld2HasNoMovingWalls`.

**INV-07 (Core/Spawner)** — Both distance→difficulty functions are monotone, bounded and pure
statics: `Spawner.maxIndex(forDistance:)` is non-decreasing in distance and never exceeds
`Patterns.count` (14); `Spawner.gap(forDistance:)` (`Spawner.swift:17-20`) is non-increasing over
`[0, ∞)` and stays inside `[gapMin 5, gapMax 11]`.
*Breaks if:* a tier is expressed as a range rather than a prefix bound (making earlier patterns
unreachable late), or a "difficulty spike" band makes `gap` non-monotone — which would invalidate
the reasoning in INV-13's coin-trail note (the breadcrumb is placed behind the cursor using *this*
pattern's gap as a stand-in for the *previous* one, and only lands correctly because gap shrinks).
*Detected by:* `DifficultyTests.testPatternGating`, `DifficultyTests.testGapMonotonicDown`,
`PatternOrderTests.testTierLadderMonotoneAndRNGCountsPinned`.

**INV-08 (Core/Patterns)** — `Patterns.run` must never emit a spawn whose `d` exceeds
`base + returnedLength`. The spawner advances `cursor += len + gap` (`Spawner.swift:60`), so an
overhanging spawn lands inside the *next* pattern's geometry, which the solvability bot was never
asked to clear.
*Breaks if:* a pattern's trailing gem line or arc is lengthened without raising its returned length
(patterns 1, 2, 6, 9 and 11 all return `max(...)`-style lengths derived from the ballistic span).
*Detected by:* `ArcCollectionTests.testArcPatternLengthLaw` — but **only for indices 1, 2, 6, 9, 11**
(the arc-bearing ones). Indices 0, 3, 4, 5, 7, 8, 10, 12, 13 are untested for spill.

**INV-09 (Core/DailyChallenge)** — Any change to spawner behaviour, pattern content, pattern order,
or RNG consumption anywhere in the spawn path requires bumping `DailyChallenge.layoutVersion`
(currently 7). This includes **zero-RNG** changes: v5 and v6 were both bumped for purely
deterministic additions, because the shared daily track visibly differs. The golden seeds for
(2026,6,10), (2026,6,11) and (2025,12,31) at the current default are frozen, the explicit v5/v6 pins
must keep reproducing, and a v8 golden (`0x2FC8_A9EA_C0B9_E30F`) is pre-armed so the next bump is a
one-line change.
*Breaks if:* a session tunes a pattern and ships without the bump — every player's daily track
changes mid-cycle and two players on the same date no longer race the same layout.
*Detected by:* **nothing — untested for the direction that matters.**
`DailyChallengeTests.testGoldenSeeds` pins the *seed derivation* (it fires only when the version
constant changes), and `RNGTests.runHash` is a same-build self-comparison with no pinned constant.
There is no golden run hash anywhere in the suite, so "changed the track, forgot the bump" passes
every test in the repo. This is convention-only enforcement.

**INV-10 (Core/GameCore.advance)** — dt sanitation happens before the accumulator is touched:
`guard realDt.isFinite, realDt > 0 else { return }` (`GameCore.swift:162`) drops NaN, ±inf, zero and
negative dt — `min(NaN, 0.1)` is NaN, which would poison `accumulator` permanently — and the early
`return` deliberately skips `rebuildSnapshot()`, leaving the previous snapshot intact. The
accumulator then takes `min(realDt, 0.1)` (`GameCore.swift:163`), capping one `advance` call at
**12 ticks**; wall-clock beyond 100 ms is discarded, not deferred (see §3).
*Breaks if:* the guard is relaxed, or the 0.1 clamp is raised without re-deriving the tick ceiling —
a larger clamp reintroduces the spiral of death on a thermally throttled device.
*Detected by:* `GameplayTests.testAdvanceSurvivesNaNAndJunkDt` covers the guard. **The 12-tick
ceiling is untested** — nothing asserts the clamp value or the resulting tick count.

**INV-11 (Core/GameCore)** — `rebuildSnapshot()` runs exactly once per `advance` call
(`GameCore.swift:168`) and never inside `tick`. Bare `tick(_:)` leaves `snapshot` stale by design,
which is what lets tests drive exact step counts without paying snapshot cost.
*Breaks if:* someone "fixes" a test by calling `rebuildSnapshot` from inside `tick` — every
`advance` then allocates and publishes 1–12 snapshots per frame, and `@Observable` fires that many
SwiftUI invalidations.
*Detected by:* nothing — untested directly. Three test files (`PowerUpTests.swift:39`,
`BoostTests.swift:91`, and the arc tests) carry comments relying on the current behaviour, so the
suite would fail *somewhere* — but no test names this property.

**INV-12 (Core/GameCore.spawn, Core/Spawner)** — `Spawner.fill` is called exactly once per tick and
only while `mode == .play` (`GameCore.swift:175, 301`). Calling it twice in one tick advances
`cursor` past patterns without `distance` changing, desynchronising the `gap`/`maxIndex` sampling
from the player's position and silently reshuffling the seeded stream. Calling it in `.menu` or
`.over` would populate a track nobody plays and burn RNG draws.
*Breaks if:* a session adds a "pre-fill on run start" call, or moves `spawn()` out of the mode
guard to warm the pools.
*Detected by:* nothing — untested. `FlowTests.testDeterminismAndPatternStreamIsolation` compares two
traces of the same build, so a double-fill in both traces is invisible to it.

**INV-13 (Core/GameCore.spawn)** — `freeLaneNear` (and therefore the guaranteed power-up cadence)
runs strictly *after* `Spawner.fill` in the same tick (`GameCore.swift:301` then `:308`), so the
obstacle set up to the horizon is complete when the cadence picks a lane. Both cursors advance past
the same horizon together, so a later pattern cannot land on an already-emitted pickup.
*Breaks if:* the two loops are swapped, or the cadence is hoisted into `stepPickups` — a cadence
pickup then materialises inside a wall the same tick, which reads as a deliberate trap.
*Detected by:* nothing — untested. `PowerUpTests.testPowerUpCadenceDeliversEveryKind` pins the
shield→magnet→doubler→chrono→sneakers cycle, not the ordering against `fill`.

**INV-14 (Core/GameCore)** — The guaranteed power-up cadence (`spawn()`'s second loop +
`cadenceCommand`, `GameCore.swift:307-345`) and the flow-surge gem fountain (`registerFlowNearMiss`,
`GameCore.swift:450-462`) both consume **zero RNG**. So do every gap coin trail
(`Spawner.swift:53-58`), every `gemArc`, and all six manual/debug activators. The seeded stream must
be byte-identical whether or not surges fire and whether or not a cadence mark is placed.
*Breaks if:* someone randomises the cadence lane, the fountain spread, or the trail spacing.
*Detected by:* `FlowTests.testDeterminismAndPatternStreamIsolation` — it drives two 14,000-tick
autopilot traces of the same seed, one with extra safe jumps injected, and requires the emitted
obstacle sequence (kind, lane, `d` within 0.6) to match. Note the 0.6 tolerance on `d` explicitly
forgives fill-tick jitter, and injected jumps do not change `effectiveSpeed` — so this test does
**not** cover the chrono/boost divergence described in §4.

**INV-15 (Core/GameCore.tick)** — The step order inside `tick` is load-bearing (the full ordering is
in §3). Two adjacencies specifically: `spawn()` runs *after* `stepSpeedAndDistance`, so the horizon
is computed post-increment; and it runs *before* `stepObstacles`/`stepGems`/`stepPickups`, so a
freshly spawned entity can never be collided with on its spawn tick (its `d` is at least
`distance + 60`). The score recompute (`GameCore.swift:197`) must stay last, after `bonus` has
absorbed every near-miss and surge for the tick.
*Breaks if:* collisions are hoisted above spawning "for cache locality", or the score line moves
above `stepObstacles` — near-miss bonuses then land one tick late.
*Detected by:* nothing — untested. No test asserts the step order.

**INV-16 (Core/GameCore.stepSpeedAndDistance)** — `speed` is monotone non-decreasing while
`mode == .play` and never exceeds `Tuning.speedCap` (33); the target is
`min(33, 17 + distance · 0.0052)`, reached at 3,076.9 m. `effectiveSpeed` is deliberately *not*
monotone — that is what chrono and boost are for.
*Breaks if:* a "rubber-banding" or difficulty-relief mechanic decrements `speed` in `.play`.
*Detected by:* `DifficultyTests.testSpeedMonotonicToCap`, `DifficultyTests.testSpeedTargetFormula`.

**INV-17 (Core/GameCore.effectiveSpeed)** — `effectiveSpeed` (`GameCore.swift:123-129`) is the sole
composition point for temporary speed buffs, in a fixed order: chrono multiplies first
(`×0.65`), then boost (`×1.3`, clamped to `boostSpeedMax = 36`). `speed` itself is never mutated by
a buff, so the difficulty ramp resumes seamlessly the instant a timer ends.
*Breaks if:* any other site multiplies `speed` by a buff factor, or a buff writes `speed` directly —
the ramp then permanently inherits the buff, or snaps backwards when it expires.
*Detected by:* `BoostTests.testEffectiveSpeedCompositionAndCap`,
`PowerUpTests.testChronoSlowsDistanceNotTheRamp`.

**INV-18 (Core/Patterns, Core/GameCore.launchVelocity)** — Ballistic *placement* never reads the
buffed jump. `Patterns` computes arcs and ring heights from `Tuning.jumpV0` and `Tuning.gravity`
(`Patterns.swift:47-50, 142-143`), never from `GameCore.launchVelocity`
(`GameCore.swift:133-135`), which is the only site that applies `superSneakersJumpMult`. Super
Sneakers therefore over-clears obstacles rather than perturbing the seeded track.
*Breaks if:* someone "corrects" the arc height to match the active jump — placement becomes
player-state-dependent and the daily track diverges per player.
*Detected by:* `PowerUpTests.testSuperSneakersRaisesJumpApexAndIsNeverLethal` pins the buff side;
**the placement side is untested** — no test asserts that `Patterns` never reads the buff. (Related
known consequence: at the buffed apex the player's centre is ~4.39, outside the ring's
`ringY 2.90 ± ringPassDY 0.9` window, so Super Sneakers makes prism rings uncollectable.)

**INV-19 (Core/Patterns, Core/Spawner, Core/Autopilot)** — Every emitted `movingTall` carries
`phase: 0` (`Patterns.swift:185-186` — the only two emission sites), and two independent consumers
hardcode the consequence: `Spawner.safeEntryLane` marks lane 1 blocked with the comment "phase-0
wall crosses CENTRE" (`Spawner.swift:78-79`), and `Autopilot` computes the wall's plane position as
`sin(o.phase) · amplitude` (`Autopilot.swift:41`), which is 0.
*Breaks if:* a pattern emits a non-zero phase to add variety — `safeEntryLane` then routes the coin
trail into a wall, and the bot's lane blocking is wrong for the outer lanes.
*Detected by:* nothing — untested for the phase value itself.
`SolvabilityBotTests.testGreedyBotSurvives200Seeds` would likely go red, but only stochastically.

**INV-20 (Core/GameCore.apply, Core/Tuning)** — Pool caps must exceed peak coexisting demand,
because `apply` (`GameCore.swift:649-687`) **silently `return`s** when a cap is hit: the spawn is
dropped, not queued, with no log, no counter and no FX. Current caps: `capLow 18`, `capTall 14`
(shared tall + movingTall), `capBar 6`, `capSplitBar 6`, `capGem 72`, `capShield 4`, `capMagnet 4`,
`capDoubler 2`, `capChrono 2`, `capSuperSneakers 2`, `capRing 4`, `capBoostPad 2`.
*Breaks if:* a session adds gems to a pattern, shortens `gapMin`, or raises `fountainGems` — the
v1.6 "coins mark a takeable route" promise then truncates exactly in the dense stretches where the
player needs the reading aid. `capGem = 72` is already plausibly reachable: pattern 10 alone emits
24 gems, pattern 11 emits 18, gap trails add 4–6 per pattern, and a flow surge injects 10 more.
*Detected by:* nothing — untested. Also note the renderer's prewarm budget (INV-43) is derived from
these numbers, so raising a cap has a second-order cost.

**INV-21 (Core/GameCore)** — `score` is written in exactly two places: the `mode == .play`-guarded
line at the end of `tick` (`GameCore.swift:197`) and `die()` (`GameCore.swift:578`). It is
non-decreasing during a run and frozen from the instant of death through the entire ~1.5 s
deceleration, even though `distance` keeps integrating in `.over`.
*Breaks if:* the mode guard is dropped, or a third writer appears (a bonus paid from the game-over
panel, say) — the player watches their score tick up after they died.
*Detected by:* `GameplayTests.testScoreFreezesAtDeath`.

**INV-22 (Core/GameCore.revive)** — `revive()` folds the post-death drift into the offset
(`scoreOffset += distance - deathDistance`, `GameCore.swift:613`) so `traveledDistance` and `score`
resume exactly where death froze them. A paid continue must never grant free points for the decel.
*Breaks if:* a session resets `distance` instead of adjusting `scoreOffset`, or clears
`deathDistance` before the fold.
*Detected by:* `GameplayTests.testReviveResumesAtFrozenScore` (accuracy 1e-9);
`EconomyTests.testReviveResumesPlayWithGrace`; `GameplayTests.testReviveRestoresPlaySpeed`.

**INV-23 (Core/GameCore, Services/GameCenterService)** — `usedCheckpoint`
(`GameCore.swift:68`) is set **iff** `startRun` was called with `startDistance > 0`
(`GameCore.swift:104`), is cleared only by `reset` (`:142`), and is carried into `GameSnapshot`
(`:729`). `GameCenterService.submitRun` refuses to submit when it is true
(`PrismRush/Services/GameCenterService.swift:33`) — iron rule 10.
*Breaks if:* `activateHeadStart` or `revive` set it (they must not — a head start is
leaderboard-safe by design, `GameCore.swift:232`), or if a future submission path forgets the
guard. **Known gap, not a break:** `revive()` does *not* set it, so a run continued twice for 450
coins is fully eligible for `prismrush.best`. Iron rule 10 names only checkpoints; whether that is
correct is a product decision.
*Detected by:* `GameplayTests.testCheckpointRunIsFlaggedAndScoreOffsetCleared`;
`PowerUpTests.testHeadStartLaunchesWithBoostAndIsLeaderboardSafe`. The `GameCenterService` side is
untested (no test targets that file).

**INV-24 (Core/GameCore.stepObstacles)** — A near-miss is awarded at most once per obstacle entity,
at the tick where `passed` flips (`!passed && z >= obstacleZHalf`, `GameCore.swift:420-421`), only
while `mode == .play`, and never for an obstacle that hit — an absorbed obstacle is removed from
`activeObstacles` on the absorb tick (`GameCore.swift:410-411`) so it can never reach the near-miss
block, and post-death awards are mode-guarded.
*Breaks if:* the `passed` flag is moved, the mode guard is dropped, or the shield path stops
removing the entity — near-miss bonuses then double-pay, and `flowStreak` inflates with them.
Note: `die()` neither breaks nor returns; the loop keeps iterating with the killing entity in place
(`GameCore.swift:413-416`). That is the single most fragile construct in the file and it is safe
only because of these guards.
*Detected by:* `GameplayTests.testNoNearMissAwardThroughShieldOrDeathPaths`;
`GameplayTests.testTallPassingInsideBandAwardsCloseOnce`.

**INV-25 (Core/Tuning)** — The near-miss band constants are locked to the collision geometry:
`nearMissInner == laneHitHalfWidth` (both 1.25, `Tuning.swift:30, 64`), so the CLOSE band begins
exactly where the kill band ends — no gap, no overlap (`tallHit` uses `< 1.25`, `closeNearMiss` uses
`>= 1.25`); and `nearMissOuter` (1.95) must stay strictly below the lane pitch 2.2.
*Breaks if:* the kill width is widened without moving `nearMissInner` (a dead band appears where a
graze pays nothing), or `nearMissOuter` reaches 2.2 — standing one lane away then auto-awards CLOSE
on every tall, and the flow surge fires continuously.
*Detected by:* `GameplayTests.testTallPassingOneLaneAwayAwardsNothing`;
`CollisionTests.testCloseNearMissBand`; `CollisionTests.testTallLateralEscape`.

**INV-26 (Core/GameCore.stepObstacles)** — A shield absorb does three things atomically
(`GameCore.swift:407-412`): clears `shield`, sets `invulnT = Tuning.invulnDuration` (0.4 s ≈ 48
ticks), and **removes the absorbed entity** from `activeObstacles`. The grace window must outlive
the 1.9 m kill band, because patterns 3, 7 and 9 pair talls at the same `d`.
*Breaks if:* `invulnT` is shortened below the band's dwell time, or the absorb stops removing the
entity — the partner wall then finishes the job on the next tick and the shield reads as broken.
*Detected by:* `GameplayTests.testShieldAbsorbSurvivesTwinTallsAtSameDepth`.

**INV-27 (Core/GameCore.registerFlowNearMiss)** — `flowStreak` is always strictly less than
`Tuning.flowPerSurge` (3) between ticks: the surge consumes the streak by resetting it to 0
(`GameCore.swift:452-453`). It also resets to 0 on death (`die()`, `:580`), on a fatal hit, and on
an *absorbed* hit (`:408`).
*Breaks if:* the reset is moved after the fountain emission, or the absorb path stops clearing it —
a shielded player then banks a surge they did not earn.
*Detected by:* `FlowTests.testSurgeEveryThirdWithFountainInLane`;
`FlowTests.testStreakResetsOnShieldAbsorbAndDeath`.

**INV-28 (Core/Collisions)** — Every function in `Collisions` is a pure `static` function of its
arguments (`PrismRush/Core/Collisions.swift:5-93`): no reads of `GameCore` state, no globals, no
isolation annotation. That is what makes them testable at boundary values independently of a
running sim, and it is why `GameCore` and the tests exercise literally the same predicate.
*Breaks if:* one takes a `GameCore` reference or reads a mutable static — the boundary tests then
stop proving anything about the live collision path.
*Detected by:* the whole of `CollisionTests` (26 boundary tests) still compiles and passes, but
**nothing asserts purity itself** — a function that took a core reference would simply need its
tests updated.

**INV-29 (Core/Patterns index 10)** — The overdrive runway is self-contained: it emits **zero**
lethal spawns, and the latest possible pad trigger (`4 + 1.1 = 5.1`) followed by a full boost at the
hard speed cap travels `1.0 s × 36 = 36`, total `41.1 < 48` — the pattern's own length. This is why
the boost can never carry the player into an obstacle and why the Autopilot needs no boost handling
at all.
*Breaks if:* `boostDuration`, `boostSpeedMax`, the pad's position within the pattern, or the
pattern's returned length change without re-deriving `5.1 + boostDuration × boostSpeedMax < length`.
*Detected by:* `SolvabilityBotTests.testOverdriveRunwayContainmentInvariant` (geometric, no sim,
across 4 base distances × 3 seeds); `SolvabilityBotTests.testBotSurvivesForcedBoostIntoNextPattern`.

**INV-30 (Core/Autopilot + Core/Spawner)** — "Solvable" is an empirical soak, not a proof: the
deterministic greedy `Autopilot` must clear **6,000 m on 200 seeds** (salt `0x1234_5678`) and
**12,000 m on 64 seeds** (salt `0xDEE9_5EED`, so full-density content past `diffFullAt = 3200` is
broadly sampled) with **zero deaths and zero stalls** — reaching the 400,000-tick safety bound
without dying counts as a failure, not a pass. Every spawner, pattern, tuning or collision change
must re-run it green.
*Breaks if:* a pattern's internal spacing tightens, `gapMin` drops, or a kill band widens.
*Detected by:* `SolvabilityBotTests.testGreedyBotSurvives200Seeds`,
`SolvabilityBotTests.testGreedyBotSurvivesDeepRuns`.
**Scope correction —** the soak does *not* prove the track is clearable with no buffs. `stepPickups`
(`GameCore.swift:500`) collects by overlap, with no decision verb involved, so the bot walks into
whatever lies in its lane: `PowerUpTests.testBotCollectsChronoDuringProceduralRuns` explicitly
asserts that at least one chrono is collected across 10 procedural seeds. The determinism tests pass
because the bot is *deterministic*, not because it avoids buffs. Any claim of the form "the bot
never collects pickups" (it appears in the layer surveys) is false — do not rely on it.

### 8.2 Renderer (INV-31 … INV-50)

**INV-31 (Render/Reality/RealityRenderer)** — `advanceVisuals(dt)` must be called immediately before
`sync(snapshot)`, exactly once per rendered frame. `advanceVisuals` sets `lastDt` on its second line
(`PrismRush/Render/Reality/RealityRenderer.swift:577-579`) and `sync` reads it for every velocity
estimate, camera spring and particle-debt accumulator. Current and only call site:
`PrismRush/UI/GameView.swift:282-283`.
*Breaks if:* a session calls `sync` twice per frame (double-emitting trail/dust particles and
double-integrating the springs), or calls `sync` without `advanceVisuals` (every debt accumulator
freezes and `lastDt` goes stale).
*Detected by:* nothing — untested. There are no renderer unit tests; `Tests/WorldPaletteTests.swift`
and `Tests/CoreTests/CharacterParityTests.swift` are the only Mac-only tests and neither drives a
frame.

**INV-32 (Render/Reality/RealityRenderer.fire)** — `fire(_:)` for a frame always runs *before* that
frame's `advanceVisuals`/`sync`: `GameCore.emit` calls `onFX` synchronously inside `tick`
(`PrismRush/Core/GameCore.swift:735`) and `core.advance(realDt:)` (`GameView.swift:280`) precedes
the two renderer calls. `fire` may therefore legally arrive before the very first `sync` after a
reset, and must only arm timers/bursts — never read snapshot-derived state that `sync` has not
written yet. Consequence to expect: pose-impulse timers armed in `fire` (`jumpStretchT`,
`landSquashT`) lose one `dt` before `sync` consumes them.
*Breaks if:* a new `fire` case reads `lastSpeed`, `speedNorm`, `runBobOn` or `lastSliding` — those
are written by the *previous* frame's `sync` and are one frame stale by design
(`resetEntities` zeroes them at `:685` for exactly this reason).
*Detected by:* nothing — untested.

**INV-33 (Render/Reality/EntityPools + Core/GameCore)** — Every `GameCore.reset(seed:)` /
`startRun(...)` must be followed by `renderer.resetEntities()` before the next `sync`.
`GameCore.reset` sets `nextId = 0` (`GameCore.swift:152`), so entity ids are reused across runs
**with different kinds**, and `EntityPools.sync` matches purely on `id` and never re-validates
`kind` (`PrismRush/Render/Reality/EntityPools.swift:27-34`; `liveKind` is written only on the
creation path). A stale live mapping renders the wrong mesh forever and files the entity back into
the wrong free list on recycle (`:42`).
*Breaks if:* any new run-start path omits the call. Today `beginRun` (`GameView.swift:386`) and
`returnToMenu` (`GameView.swift:498`) satisfy it; `install()`'s autoplay `core.startRun(seed: 7)`
(`GameView.swift:212`) does **not**, and is safe only because the pools are still empty at that
point.
*Detected by:* nothing — untested, and there is no assertion in `EntityPools` guarding it. This is
the highest-value latent defect in the render layer: one missing call away from a permanent
wrong-mesh render.

**INV-34 (Render/Reality/RealityRenderer)** — The `root` entity must stay at identity transform.
`camera.position = cp` (`RealityRenderer.swift:277`) is a *root-local* write, while
`camera.look(at:from:relativeTo: nil)` on the very next line (`:279`) treats the same `cp` as a
*world* position. They agree only while `root` is untransformed.
*Breaks if:* a session translates, rotates or scales `root` — e.g. to implement a global "world
tilt" or to offset the scene for a UI inset. The camera then looks at the wrong point every frame.
*Detected by:* nothing — untested.

**INV-35 (Render/Reality/RealityRenderer.buildScene)** — The backdrop plane stays at `z = −65`
(`RealityRenderer.swift:757`). All twelve sky families place set pieces at z ≈ −30…−64 tuned against
it; the v1.6 "longer track" experiment at −95 put the track *behind* every `WorldSky` set piece and
was reverted (commit `e61b19d`; the reasoning is preserved in the comment at `:751-755`).
*Breaks if:* someone lengthens the visible track by pushing the backdrop back without repositioning
all twelve skies in lockstep.
*Detected by:* nothing — untested. Visual-only; only a screenshot pass catches it.

**INV-36 (Render/Reality/RealityRenderer.sync)** — The palette recolor block
(`RealityRenderer.swift:203-220`) touches `backdrop`, `rungs`, `laneLines`, `matAccent`,
`matAccent2` and the two tints — and **never the character**. Character colour comes only from
authored skin hexes via `applyCharacterColors` (`:731-741`) and the time-only prismatic shimmer
(`:586-596`, `SkinCatalog.prismaticColor(at:)` takes a clock and nothing else). Owner decree 1: a
character never changes identity with the world, including the default.
*Breaks if:* `playerBody`, `antenna`, `crestParts` or `auraRing` are added to that block "so the
character fits the world" — that is precisely the revoked v1.3 chameleon behaviour.
*Detected by:* `SkinCatalogTests.testPrismaticShimmerIsPureDeterministicAndPeriodic` pins that the
shimmer is a pure function of time (world-blind). Nothing tests the recolor block itself.

**INV-37 (Render/RendererPort)** — The seam is one-directional. `RendererPort`
(`PrismRush/Render/RendererPort.swift`) declares only `sync(GameSnapshot)` and `fire(FXEvent)`, both
returning `Void`; nothing flows back. The renderer must never mutate game state, and must never
become an input source.
*Breaks if:* a renderer method starts calling into `GameCore`, or `sync` gains a return value to
report "what the player actually hit" — the sim stops being headless-testable and the Linux suite
stops meaning anything.
*Detected by:* nothing — untested, though the protocol's `Void` returns make the violation
structurally awkward. Note `advanceVisuals(_:)`, `resetEntities()`, `applySkin(_:)` and
`install(into:)` are **not** on the protocol; a second renderer would have to re-declare them.

**INV-38 (Render/Reality/*)** — No renderer code may touch the run RNG. Renderer-side randomness is
allowed (`Float.random` for shake at `RealityRenderer.swift:267-268`, `Double.random` for blink at
`:601`, `Float.random` in `WorldDecor.style`) precisely because it can never reach `Core/`. Every
sky family instead seeds a **local** `SplitMix64` from the absolute world ordinal (e.g.
`OrbitalSky.swift:139`, `WorldDecor.swift:401`) so set pieces are stable per world.
*Breaks if:* a renderer takes a reference to `GameCore.rng` for "free" determinism — a single draw
there rewrites every seeded track.
*Detected by:* nothing — untested. Structural safety only: `Core/` cannot import `Render/`, and
`rng` is `@ObservationIgnored private`-adjacent state on `GameCore`.

**INV-39 (Render/Reality/RealityRenderer.sync)** — `s.y` from the snapshot is authoritative for
every entity kind; the renderer must never re-derive or hardcode a height
(`RealityRenderer.swift:371-373`; the contract is also written on `EntityState` at
`Core/Models.swift:33-34`). The one kind that must never be *lifted* is `.boostPad` — it is a floor
decal, scaled in XZ only (`RealityRenderer.swift:411-413`).
*Breaks if:* someone inlines "bar = 1.3, low = 0.425, tall = 1.6" (the values look hardcodeable) or
adds a y-pulse to the boost pad. Core then loses the ability to move an obstacle's height without a
renderer change, and the visual stops matching the collision band.
*Detected by:* nothing — untested.

**INV-40 (Render/Reality/RealityRenderer.applySkin)** — `skinScale` is clamped to 0.85…1.12
(`RealityRenderer.swift:707`) and folded into the *pose* only. It must never influence the hitbox,
which lives in Core as `Tuning.bodyRadius` (0.62) and `Tuning.groundedCenterY` (0.66), scaled by the
sim's own `sy`.
*Breaks if:* a skin's visual scale is plumbed into `Collisions.playerBounds` — larger characters
then become genuinely harder to play, which turns a cosmetic into a handicap and makes the
leaderboard skin-dependent.
*Detected by:* the hitbox side is pinned by `CollisionTests.testPlayerBoundsGrounded` and
`CollisionTests.testPlayerBoundsSlidingClearsLow` (which know nothing about skins, so a plumbing
change would have to break them). The clamp itself and the pose-only rule are untested.
`CharacterParityTests.testProportionContractPins` pins the shared silhouette proportions, not the
scale.

**INV-41 (Render/Reality/RealityRenderer.sync)** — A `splitBar`'s two segment x-offsets must be
written every frame (`RealityRenderer.swift:379-391`), derived from `s.lane` — which for a
`splitBar` is the **OPEN (safe)** lane, not a blocked one. A recycled pooled entity carries the
previous split's gap.
*Breaks if:* the placement is moved into the creation path as an optimisation — recycled split bars
then show the gap in the wrong lane, which is a lethal lie. The same inverted-lane trap exists in
`Spawner.safeEntryLane` and `Autopilot`; get the polarity backwards anywhere and the player is
steered into the bar.
*Detected by:* nothing — untested visually. The sim side is pinned by
`CollisionTests.testSplitBarHitInCoveredLane` and
`GameplayTests.testSplitBarSimKillsCoveredLaneSparesGapAndSlide`.

**INV-42 (Render/Reality/ParticleSystem)** — Capacity must exceed peak steady-state live count plus
the largest single burst. Today: dust 360/s × 0.5 s = 180, boosted trail 288/s × 0.45 s ≈ 130, speed
lines 90/s × 0.34 s ≈ 31, sneaker sparks 26/s × 0.5 s = 13 → ≈ 354 live, plus `.died` = 180 in one
frame = 534 < 560 (`ParticleSystem.swift:33`; the budget is spelled out in the comment at `:30-32`).
`emit` advances the cursor at least once and gives up after a full wrap (`:107-108`), so exceeding
the budget silently overwrites live particles.
*Breaks if:* any emission rate or particle lifetime is raised without raising `count`, or a new
burst larger than the current headroom (26 slots) is added.
*Detected by:* nothing — untested.

**INV-43 (Render/Reality/EntityPools.prewarm)** — Every entity kind whose first live spawn is
minutes into a run must be prewarmed at init. Currently `.ring` (`Tuning.capRing` = 4),
`.boostPad` (2) and `.superSneakers` (2) (`RealityRenderer.swift:175-177`).
*Breaks if:* a new late-game kind ships without a prewarm line — its first appearance allocates a
mesh and material mid-run, which is a visible hitch at exactly the moment the player is threading
something new. Also breaks the other way: raising a Core cap (INV-20) without raising the prewarm
count leaves the tail of the pool cold.
*Detected by:* nothing — untested.

**INV-44 (Render/Reality/WorldDecor — `WorldSky`)** — Exactly one `famRoots` entry is enabled at a
time. `WorldSky.update` disables all twelve and enables `skyFamily(world)` on a world change
(`PrismRush/Render/Reality/WorldDecor.swift:313`).
*Breaks if:* an incremental "crossfade the two skies" change enables two roots — the sky draw cost
doubles and two contradictory set pieces stack (a volcano behind an aurora).
*Detected by:* nothing — untested.

**INV-45 (Render/Reality/WorldDecor + UI/Theme + Core/Tuning)** — Three counts must agree:
`famRoots.count` = 12 (`WorldDecor.swift:291`, 3 legacy + 9 `BespokeSky`),
`Theme.worlds.count` = 12, and `Tuning.worldFamilyCount` = 12. `WorldSky.skyFamily` folds by
`famRoots.count` (`:302-305`) while `WorldDecor.style` folds by `Theme.worlds.count` and *then*
indexes the legacy silhouette by `world % 3` (`:104-115`) — which only works because 12 is a
multiple of 3.
*Breaks if:* a 13th palette ships without a 10th bespoke family (or vice versa) — the sky family
desynchronises from the playfield palette. A count that is not a multiple of 3 breaks the legacy
silhouette fold silently.
*Detected by:* `WorldPaletteTests.testCoreFamilyCountMatchesPaletteCount` pins
`Tuning.worldFamilyCount == Theme.worlds.count`; `WorldPaletteTests.testAllTwelveWorldsAreDistinct`
pins the count at 12. **`famRoots.count` and the `% 3` fold are untested** — the third leg of the
tripod is unguarded.

**INV-46 (Render/Reality/*)** — Allocation-heavy rebuilds run on boundary events only, never per
frame: `WorldSky.restyle` and every `BespokeSky.restyle` run at a world boundary or a Reduce-Motion
flip (`WorldDecor.swift:310-319`) and allocate `UnlitMaterial`s freely; `WorldDecor.style` runs only
when a slot recycles past the camera or is flagged `needsRestyle` (`:89-93`); `rebuildCharacter()`
(`RealityRenderer.swift:810`) runs on equip/launch only, from `applySkin` (`:720`).
*Breaks if:* any of them is hoisted into the per-frame path to "keep things in sync" — dozens of
material allocations per frame, on a 120 Hz loop.
*Detected by:* nothing — untested. Note `WorldDecor.reset` deliberately does *not* restyle: it only
re-seeds `s.d` and sets `needsRestyle`, because only the next `update` knows the current world
(`WorldDecor.swift:74-80`). Breaking that pairing leaves every slot styled for the wrong world.

**INV-47 (Render/Reality/BespokeSky conformers + WorldSky animators)** — Every sky family's
`animate(elapsed:reduceMotion:)` writes only transforms and `isEnabled`. No material allocation, no
mesh regeneration, no entity creation. All nine bespoke families and the three legacy animators obey
this today; it is the only reason the sky layer is free at 120 Hz.
*Breaks if:* a family tries to fade something by allocating a new `UnlitMaterial` per frame — the
correct move is to pre-build the variants in `restyle` and toggle `isEnabled`.
*Detected by:* nothing — untested.

**INV-48 (Render/Reality/RealityRenderer + every sky family)** — Reduce Motion is honoured *live*,
not sampled at launch: `RealityRenderer.swift:181-187` registers an observer for
`UIAccessibility.reduceMotionStatusDidChangeNotification` on `.main` and wraps the body in
`MainActor.assumeIsolated` (iron rule 8's pattern). Every path that animates under `!reduceMotion`
must also carry a one-time rest-pose restore, or the element freezes mid-animation when the user
flips the setting: antenna `swayApplied` (`:633-640`, also cleared on a rig rebuild at `:909`),
`auraSpin` (`:647-650`), the sky's
restyle-on-RM-flip (`WorldDecor.swift:316-318`), and the sky root's `position.y = 0` reset
(`WorldDecor.swift:324`).
*Breaks if:* new motion is added inside an `if !reduceMotion` block with no matching restore.
*Detected by:* nothing — untested.

**INV-49 (Render/Reality/RealityRenderer)** — Particle emission rates are per-second, never
per-frame. `trailDebt`, `dustDebt`, `speedLineDebt` and `sneakerDebt`
(`RealityRenderer.swift:119-125`) accumulate `rate * lastDt` and drain integer counts at
`:352-359, 422-433, 438-446, 452-464`.
*Breaks if:* a session writes `count: 3` directly into a `burst` call inside the per-frame path —
density then doubles on a 120 Hz ProMotion device relative to 60 Hz.
*Detected by:* nothing — untested. **Known inconsistency to be aware of:** the camera/pose smoothing
lerps do *not* follow this rule — `chronoDip … * 0.08` (`:233`), `boostFOV … * 0.12` (`:237`),
`vxEst`/`vyEst … * 0.35` (`:243-244`), `slideDip … * 0.28 / 0.14` (`:253`), RM `camX … * 0.15`
(`:259`), `camLift … * 0.25` (`:274`), `slideRoll … * 0.2` (`:282`), magnet-gem shrink `… * 0.35`
(`:397`) all use a fixed per-frame alpha and converge twice as fast at 120 Hz as at 60 Hz, while
their comments quote absolute times. The lateral camera spring (`:262-264`) and the antenna whip
(`:623-625`) correctly scale by `sdt`. Do not copy the wrong pattern.

**INV-50 (Render/Reality/ProceduralMesh)** — Generated meshes are single-sided, wound CCW-outward,
and carry positions + triangle indices only — no normals, because every material in the layer is
`UnlitMaterial` (`ProceduralMesh.swift:4-6`). And `build` silently substitutes
`.generateSphere(radius: fallback)` when `MeshResource.generate` throws
(`ProceduralMesh.swift:278`).
*Breaks if:* a new mesh is wound the other way — it is back-face culled and invisible from the chase
camera, with no error; or a mesh is malformed — it appears as a mystery ball rather than failing
loudly. Both symptoms read as "the entity did not spawn", which sends debugging into `EntityPools`
and Core instead of the mesh.
*Detected by:* nothing — untested. Zero binary assets means there is no golden image to diff
against.

---

### 8.3 UI, input, and the run lifecycle (INV-51 … INV-70)

Everything here lives above the Core↔Render seam (§2) and is enforced by convention, not by the type
system. Almost none of it is covered by an executable test: `GameModel` is one of the types no test
file ever names, and the only behavioural coverage of this layer is `UITests/InteractionUITests.swift`
(11 tests) — which **CI never runs** (see INV-109). Treat "detected by a UITest" as "detected only when
a human runs `Tools/ci.sh`".

- **INV-51 (UI/GameModel)** — `GameModel.install(_:)` runs exactly once per app launch. It subscribes
the `SceneEvents.Update` frame loop, calls `haptics.prepare()`, `synth.start()`,
`synth.musicStart(calm:)`, `IAPManager.shared.start()`, `GameCenterService.shared.authenticate()`,
seeds every audio/haptic setting from the profile, and applies all `PR_*` env overrides
(`PrismRush/UI/GameView.swift:139-293`).
*Breaks if:* a session calls `install` from a second `RealityView` closure, or SwiftUI re-creates the
`RealityView` — the second call replaces `sub`, re-installs the GameKit `authenticateHandler`, and
re-runs the `PR_DEMOPROFILE` profile rewrite (`GameView.swift:146-192`) over live player state.
*Detected by:* **nothing — untested.**

- **INV-52 (UI/frame loop)** — `core.advance(realDt:)` is called exactly once per `SceneEvents.Update`
event (`GameView.swift:283`), with the raw `event.deltaTime`.
*Breaks if:* a second `advance` is added anywhere in the loop body, or a second subscription is
created. The accumulator is fed raw wall-clock dt (§3), so a double call double-integrates distance
and speed and double-drains every power-up timer in the same displayed frame.
*Detected by:* **nothing — untested.** `GameplayTests` pins `advance`'s dt sanitation, never its call
cadence.

- **INV-53 (UI/frame loop)** — the `if self.paused { … return }` early return stays *above*
`core.advance` (`GameView.swift:262-265`). Only `synth.musicPump` runs while paused; the simulation,
the renderer sync, and `ageEffects()` do not.
*Breaks if:* a future edit moves work below the guard, or hoists `advance` above it — the sim then
runs behind the pause veil while the player believes it is frozen.
*Detected by:* **nothing — untested.** `UITests/InteractionUITests.swift` `testPauseResumeAndQuit:74`
asserts only that the "PAUSED" overlay appears and dismisses, never that distance stopped.

- **INV-54 (UI/frame loop, Swift 6)** — the entire frame-loop body is inside
`MainActor.assumeIsolated` (`GameView.swift:256`); RealityKit's `subscribe` handler type is not
MainActor-isolated (iron rule 8).
*Breaks if:* the `assumeIsolated` wrapper is removed to "fix" a warning, or a new non-isolated
framework callback touches `GameModel`/`GameCore` without one. The failure is a `fatalError` trap, not
a silent race — and RealityKit's main-thread delivery is not contractually documented (see
`docs/agent/scratch/trace-concurrency.md` escape hatch #9).
*Detected by:* **nothing — untested** (compile-checked only by `xcodebuild` with
`SWIFT_STRICT_CONCURRENCY: complete`, `project.yml:11`).

- **INV-55 (UI→Core boundary)** — the UI reaches `GameCore` only through its intent methods
(`jump`/`slide`/`changeLane`/`activateSlowMo`/`deployOverdrive`/`deployShield`/`activateHeadStart`/
`startRun`/`revive`/`reset`), and no UI-driven activation consumes the seeded RNG.
*Breaks if:* a surface writes a `private(set)` core field via a new setter, or an activation path
starts drawing from `rng` — every seeded run and the solvability bot shift underneath the change (iron
rules 1 and 2).
*Detected by:* `Tests/CoreTests/FlowTests.swift`
`testDeterminismAndPatternStreamIsolation` (proves player input cannot perturb the obstacle stream) and
`Tests/CoreTests/PatternOrderTests.swift` `testTierLadderMonotoneAndRNGCountsPinned`.

- **INV-56 (UI/run lifecycle)** — `recordRunResults()` is reachable only from the `.died` case of
`handleFX` (`GameView.swift:559-564` → `:680`).
*Breaks if:* a session adds a call from `returnToMenu`, a scene-phase handler, or a retry path. Coin
payouts would be absorbed by the watermarks, but `totalRuns` would increment a second time for one run
whenever `statsRecorded` is still false, and `applyRunSummary` would double-feed every sum-style
mission.
*Detected by:* **nothing — untested.**

- **INV-57 (UI/run lifecycle)** — `statsRecorded` is reset in `beginRun` (`GameView.swift:409`), set
exactly once per run at the first death (`:738`), and is **never** reset by `revive()`.
*Breaks if:* a session clears it in `reviveForCoins` "so the panel updates" — `store.recordRun` and
`store.applyRunSummary` then fire twice for one run (double `totalRuns`, double mission credit, a
second level-grant evaluation).
*Detected by:* **nothing — untested** at the `GameModel` level; the store-side consequence is pinned by
`Tests/CoreTests/MissionsTests.swift` `testPerRunMissionTracksBestSingleRunNotSum` only if a caller
actually double-calls.

- **INV-58 (UI/economy)** — all four per-death coin watermarks (`gemCoinsAwarded`, `distCoinsAwarded`,
`worldCoinsAwarded`, `styleCoinsAwarded`) are reset together in `beginRun`
(`GameView.swift:399-402`), alongside `distanceRecordedThisRun`/`gemsRecordedThisRun` (`:397-398`).
*Breaks if:* a new payout component is added with a watermark that `beginRun` forgets to zero — the
first death of the *next* run computes `max(0, x − stale)` and pays 0 for that component, permanently,
for that install.
*Detected by:* **nothing — untested** (the delta *shape* is pinned in
`Tests/CoreTests/EconomyTests.swift`, but the reset lives in `GameModel`, which no test constructs).

- **INV-59 (UI/challenge)** — `isChallengeRun` is set **after** `beginRun` returns
(`startDailyChallenge`, `GameView.swift:433-437`); `beginRun` hard-resets it to `false` at `:389`.
*Breaks if:* a session sets the flag before calling `beginRun` — the reset wipes it and the Daily Rush
silently becomes a normal run with revive, deploys and loadout all live.
*Detected by:* **nothing — untested.**

- **INV-60 (UI/challenge, decree 5)** — a challenge run can never revive, checkpoint, consume a
loadout, or deploy a banked charge. Four independent gates enforce this and must agree: `canRevive`
(`GameView.swift:454-458`), `startDailyChallenge`'s `consumeLoadout: false` + `fromWorld: 0` (`:436`),
`canDeploySlowMo`/`canDeploySpeedUp`/`canDeployShield`'s `!isChallengeRun` (`:836`, `:855`, `:874`) and
the deploy-layer render gate (`:1178`).
*Breaks if:* any one of the four drops its check — the shared worldwide board becomes pay-to-win, which
is the exact fairness rule iron rule 10 and decree 5 exist to protect.
*Detected by:* **nothing — untested.**

- **INV-61 (UI/economy)** — a deploy spends its charge only inside a *successful* core activation:
`if core.activateSlowMo() { store.mutate { … } }` and the two siblings
(`GameView.swift:849-851`, `:868-870`, `:887-889`).
*Breaks if:* the mutation is hoisted above the `if` — a refused deploy (buff already live, wrong mode)
burns a paid charge and produces nothing, which is precisely the dark pattern decree 5 forbids.
*Detected by:* **nothing — untested.** `Tests/CoreTests/PowerUpTests.swift` pins that the core refuses
to stack a live buff, but never that the charge survives the refusal (charge decrement lives in the UI
layer).

- **INV-62 (UI/first-run gate)** — `confirmFirstRunTutorial` clears `pendingFirstRunStart` *before*
invoking the stored closure (`GameView.swift:319-320`), and the stored closure calls `beginRun`
directly, below the gate.
*Breaks if:* the order is swapped, or the closure is re-routed through `startRun` — with the flag still
set, "LET'S GO" re-opens the tutorial instead of starting the run the player chose.
*Detected by:* `UITests/InteractionUITests.swift`
`testFirstRunGateCoversEntrancesAndCancelNeverStarts:222` (asserts the gated PLAY path reaches
`pauseButton`) — UI bundle, CI never runs it.

- **INV-63 (UI/first-run gate)** — `HowToPlayView.onClose` is always a plain dismissal; only the last
card's button, and only when `onDone` is non-nil, may commit a run
(`PrismRush/UI/HowToPlayView.swift:11-19`, `:56`).
*Breaks if:* a session wires `onClose` to `onDone ?? onClose` for symmetry — backing out of an
informational tutorial tap silently starts a run (AUDIT D6-2).
*Detected by:* `UITests/InteractionUITests.swift`
`testFirstRunGateCoversEntrancesAndCancelNeverStarts:236,245` — asserts `pauseButton` does not exist
after ✕ on both the info and gated paths. UI bundle, CI never runs it.

- **INV-64 (UI/observation)** — `canRestart` stays a **stored, observed** property written from the
frame loop (`GameView.swift:135`, `:287`). `overTime` is `@ObservationIgnored`.
*Breaks if:* someone "simplifies" it to `var canRestart: Bool { overTime > 1.0 }` — the death panel
never invalidates and RUN AGAIN stays greyed out forever. The comment at `GameView.swift:133-135`
records this as a shipped bug.
*Detected by:* **nothing — untested.**

- **INV-65 (UI/effects)** — `ageEffects()` runs on every unpaused frame (`GameView.swift:291` →
`:802`). It is the *only* pruner for `popups`, the only drain for `milestoneQueue`, and the only expiry
for `rewardToast`.
*Breaks if:* it is moved above the pause return, made conditional, or dropped — popups accumulate to
the 12-entry cap and stay on screen, queued LEVEL UP / NEW CHARACTER milestones never release, and a
reward toast never clears.
*Detected by:* **nothing — untested.**

- **INV-66 (UI/effects)** — the popup prune window (1.8 s, `GameView.swift:805`) stays strictly greater
than the longest `PopupStyle.duration` (1.6 s, milestones,
`PrismRush/UI/EffectsOverlay.swift:43`), and milestone releases stay `milestoneSpacing` (1.0 s,
`GameView.swift:40`) apart.
*Breaks if:* the window shrinks below the longest style — milestone text pops off mid-animation; if the
spacing shrinks, two milestone popups render on the identical shared anchor (`worldX: 0`).
*Detected by:* **nothing — untested.**

- **INV-67 (UI/observation, iron rule 5 "G3")** — no surface `@State`s a shared `@Observable`, and no
`body` snapshots `store.profile` into a `let` at the top. Reads are either scalars at point of use or
the *store reference* itself (`MissionsView.swift:31`, and `ClaimRibbon`/`MenuView` since S-005, are the reference form and
are safe).
*Breaks if:* a session hoists `let p = ProfileStore.shared.profile` to the top of a `body`, or writes
`@State private var store = ProfileStore.shared` — observation stops tracking and the view silently
stops re-rendering. Three v1.0 bugs shipped from exactly this shape; `ProfileView.swift:211` is the
closest surviving instance (legal only because it sits inside a computed property evaluated during
`body`).
*Detected by:* **nothing — untested.** `UITests/InteractionUITests.swift`
`testEquipSkinUpdatesImmediately:49` catches one instance of the symptom (a stale character shelf), not
the pattern.

- **INV-68 (UI, decree 2)** — every surface that names or draws the player's character resolves through
`ProfileStore.shared.equippedSkinID`, never `profile.selectedSkin`: `applyCurrentSkin`
(`GameView.swift:613-615`), `SplashView.swift:20`, `MenuView.swift:158`, `CharacterSelectView.swift`,
`ShopView.swift:578`.
*Breaks if:* any surface reads the raw field — an unowned cloud-merged selection makes that surface
claim "EQUIPPED" on a locked skin while the run renders Prism (AUDIT D3-1).
*Detected by:* `Tests/CoreTests/EconomyTests.swift`
`testUnownedSelectedSkinResolverFallsBackWithoutMutating` and
`testCloudMergeHealsSelectionAfterOwnershipUnion` pin the resolver itself; **no test pins that the UI
uses it.**

- **INV-69 (UI, decree 2)** — a locked skin renders as the tease (`silhouette: true`) in *every*
surface: shop hero (`ShopView.swift:200`, `:214`), shop rail (`:584`), select shelf
(`CharacterSelectView.swift:511`), NEXT UNLOCK (`:364`), hero stage (`:107`, via `locked: !owned`).
*Breaks if:* one surface hardcodes `false` — the same skin reads owned-bright on one screen and
locked-dim one tap later (AUDIT D6-5). Note `silhouette` no longer means silhouette: since v1.4 it is
full colour at 0.45/0.6 opacity plus a lock chip (`CharacterSwatch.swift:17-21`).
*Detected by:* `UITests/InteractionUITests.swift` `testHeroStageShowsLockedRequirement:152` covers the
hero stage only. UI bundle, CI never runs it.

- **INV-70 (UI/input)** — `HUDView` stays `allowsHitTesting(false)`
(`PrismRush/UI/HUDView.swift:60`), and the single full-surface `DragGesture` at
`GameView.swift:1056-1058` remains the only input recogniser.
*Breaks if:* the HUD gains a button or drops the modifier — it spans the whole screen including the XP
bar at the bottom edge, so it would swallow every swipe and tap. Conversely, any new full-screen
overlay added *above* the gesture catcher without `allowsHitTesting(false)` creates a dead zone; the
deploy buttons already do this in both bottom thumb corners (`GameView.swift:1178-1186`).
*Detected by:* **nothing — untested.** No UITest performs a gameplay tap, swipe, or lane change.

### 8.4 Meta, economy, persistence, and IAP (INV-71 … INV-90)

This is the best-tested layer in the repo — `EconomyTests` (30), `ProgressionTests` (15),
`MissionsTests` (18), `SkinCatalogTests` (5), `ShopValueTests` (15) all run on Linux CI. The gap is
uniform: every test constructs `ProfileStore(testing:deviceKey:)`
(`PrismRush/Meta/ProfileStore.swift:25`), so the *pure* rules are pinned and the *persistence
plumbing* — `load`, `save`, the KVS observer, the `#if canImport(Darwin)` branch — is executed by zero
tests on any platform.

- **INV-71 (Meta/Profile, iron rule 7)** — every `Profile` stored property has a `CodingKeys` case
(`PrismRush/Meta/Profile.swift:109-122`) and a `decodeIfPresent(…) ?? d.<field>` line in the
hand-written `init(from:)` (`:124-171`), against a locally constructed `let d = Profile()`. Counts must
stay equal: 44 properties, 44 keys, 44 decode lines.
*Breaks if:* a session adds a stored property with a plain `decode(_:forKey:)` (every existing save
then throws and the player is wiped), forgets the `CodingKeys` case (the field never round-trips), or
changes an existing field's type (`coins: Int` → `Double` throws, and the throw is swallowed into a
fresh `Profile()` at `ProfileStore.swift:634`/`:707`).
*Detected by:* `Tests/CoreTests/EconomyTests.swift` `testProfileDecodesLegacyJSONWithoutWiping`,
`Tests/CoreTests/ProgressionTests.swift` `testProfileDecodesLegacyJSONWithNewFieldsDefaulted`,
`Tests/CoreTests/MissionsTests.swift` `testProfileWithMissionFieldsRoundTrips`.

- **INV-72 (Meta/ProfileStore)** — `mutate(_:)` (`ProfileStore.swift:90-93`) is the only function that
writes `profile`; it calls `save()` unconditionally. The single sanctioned exception is
`mergeFromCloud` (`:697`), which assigns and then calls `save()` itself.
*Breaks if:* any code assigns `profile = …` directly — that write never reaches UserDefaults or the
iCloud KVS and is silently lost at next launch.
*Detected by:* **nothing — untested** (no test exercises the persistence path at all).

- **INV-73 (Meta/persistence)** — `save()` writes the identical JSON blob to UserDefaults key
`"pr.profile.v1"` and to `NSUbiquitousKeyValueStore` key `"pr.profile.v1"`
(`ProfileStore.swift:620-627`). The string is a `let localKey` at `:14` **and a duplicated literal at
`:36`** (init cannot use `self.localKey` before `profile` is assigned).
*Breaks if:* one of the two literals is changed and the other is not — the app loads from one key and
saves to the other, i.e. a total, silent, unrecoverable save wipe on the next launch.
*Detected by:* **nothing — untested.**

- **INV-74 (Meta/economy, iron rule 9)** — `applyRunSummary` (`ProfileStore.swift:427`) and
`recordRun` (`:189`) run exactly once per run, gated by `GameModel.statsRecorded`
(`GameView.swift:726`/`:738`).
*Breaks if:* a second call lands — `runsFinished` returns a constant 1 per call, so every daily/weekly
run-count mission double-counts, `totalRuns` double-increments, and every sum-style metric doubles.
*Detected by:* `Tests/CoreTests/MissionsTests.swift`
`testPerRunMissionTracksBestSingleRunNotSum` and `testDailyMissionAccumulatesAcrossRunsWithinADay` pin
the semantics; the *once-per-run gate* itself is **untested**.

- **INV-75 (Meta/economy, iron rule 9)** — `recordRunResults` runs once per **death** (revives
included), and every cumulative payout inside it is `max(0, cumulative × mult − alreadyAwarded)` with
the watermark advanced immediately (`GameView.swift:698-708`). The multiplier is captured once at run
start so a revive cannot change the basis.
*Breaks if:* a new payout component is added without its own `…Awarded` watermark — the second death of
a revived run re-pays the whole run from zero.
*Detected by:* `Tests/CoreTests/EconomyTests.swift` `testReviveResumesPlayWithGrace` plus the delta
arithmetic pinned across `EconomyTests`/`ProgressionTests`; the *watermark set* in `GameModel` is
**untested**.

- **INV-76 (Meta/progression)** — a level's coin grant is paid at most once, ever:
`firstUnpaid = max(before, xpLevelRewarded) + 1` and `xpLevelRewarded = max(xpLevelRewarded, after)`
(`ProfileStore.swift:427-443`). The watermark only ratchets up, and `merged` max-merges both `totalXP`
and `xpLevelRewarded`.
*Breaks if:* `xpLevelRewarded` is ever lowered, defaults to 0 instead of 1, or is dropped from the
merge while `totalXP` keeps max-merging — an iCloud sync then re-pays every level grant.
*Detected by:* `Tests/CoreTests/ProgressionTests.swift` `testLevelGrantWatermarkIdempotent` and
`testCloudMergeKeepsMaxXPAndWatermark`.

- **INV-77 (Meta/economy, iron rule 9/10)** — `maxWorldReached` only ever increases through play.
`unlockWorld` (`ProfileStore.swift:274-280`) never touches it; `recordRunResults` folds
`ProfileStore.reachCredit(maxWorldThisRun:startWorld:reachAtStart:)` (`:290`), not `core.maxWorld`.
*Breaks if:* any code writes `maxWorldReached` from `purchasedWorlds`, or `reachCredit` is bypassed —
one bought-deep death collapses the 59,400-coin world ladder to its deepest purchased rung and pays the
`ach.worlds` achievement for worlds never crossed.
*Detected by:* `Tests/CoreTests/EconomyTests.swift` `testPurchasedWorldStartNeverFoldsIntoReach` and
`testUnlockWorldSpendsAndUnlocksIndividually`.

- **INV-78 (Meta/IAP)** — `applyOncePerTransaction` records the StoreKit transaction id in the **same**
`mutate` as the grant (`ProfileStore.swift:161-169`), and every `IAPCatalog.apply` branch routes
through it (`PrismRush/IAP/IAPCatalog.swift:47-61`).
*Breaks if:* someone splits the marker and the payout into two `mutate` calls, or adds a grant path
that skips `applyOncePerTransaction` — a `Transaction.updates` redelivery (app died before
`finish()`) re-pays base coins, re-bumps `totalIAPPurchases`, and can re-pay the one-time +50% bonus.
*Detected by:* `Tests/CoreTests/EconomyTests.swift` `testGrantCoinPackTransactionReplayIsIdempotent`,
`testApplyOncePerTransactionNonConsumablePath`, `testFirstPurchaseFlagCloudMergeNeverRearms`.

- **INV-79 (Meta/economy)** — `totalCoinsEarned` counts only *earned* coins. `grantCoinPack`
(`ProfileStore.swift:177-186`) and `applyGrant` deliberately never touch it; `recordRun`,
`claimDailyReward`, `openFreeChest`, `claimMission`, `recordChallengeRun` and the level-up grant do.
*Breaks if:* a purchased or gacha payout starts crediting it — coin-earned achievements become buyable
with real money.
*Detected by:* `Tests/CoreTests/EconomyTests.swift` `testFirstPurchaseBonusPaysExactlyOnce` /
`testCoinPackPayoutPureRule` (the payout shape); the *exclusion* is **untested** as such.

- **INV-80 (Meta/sync)** — the five consumable counters (`slowMoCharges`, `speedUpCharges`,
`shieldCharges`, `headStartCharges`, `coinSurgeCharges`) are never merged; `merged` keeps `local`
(`ProfileStore.swift:657-689`, docstring at `:641-648`).
*Breaks if:* a session "fixes" the omission with `max()` — every iCloud sync resurrects charges the
player already spent, which is an unbounded free-consumable faucet.
*Detected by:* `Tests/CoreTests/EconomyTests.swift` `testConsumablesStayDeviceLocalOnCloudMerge`.

- **INV-81 (Meta/sync)** — `merged(local:remote:)` starts from `var merged = local`
(`ProfileStore.swift:658`), so **any `Profile` field without an explicit merge line silently gets
last-writer-wins-by-local** and is pushed back to the cloud by the following `save()`.
*Breaks if:* a new progression field is added to `Profile` and not to `merged` — the other device's
value is destroyed on the next sync, with no error. This has already happened: `totalRuns`,
`totalDistance`, `totalGems`, `totalCoinsEarned`, `bestStreak`, `loginStreak` and `dailyChallengeBest`
are all silently unmerged and are *not* in the docstring's list of deliberate exclusions.
*Detected by:* **nothing — untested** for the general rule; the specific merged fields are pinned by
`Tests/CoreTests/EconomyTests.swift` `testCloudMergeNeverErasesPurchasedCoins` /
`testCloudMergeConcurrentPurchasesOnTwoDevicesBothSurvive` and
`Tests/CoreTests/ProgressionTests.swift` `testCloudMergeKeepsMaxXPAndWatermark`.

- **INV-82 (IAP/restore)** — `IAPCatalog.restore` never re-grants consumables: it `break`s on `.coins`
and never touches `totalIAPPurchases` or `firstPurchaseBonusUsed`
(`PrismRush/IAP/IAPCatalog.swift:65-76`).
*Breaks if:* the `.coins` case is filled in — every Restore Purchases tap re-pays every coin pack the
player ever bought, unbounded, because restore walks `Transaction.currentEntitlements` with no ledger
check.
*Detected by:* **nothing — untested.** `IAPCatalog` and `IAPManager` have zero tests of any kind; only
the `ProfileStore` side of grants is covered.

- **INV-83 (IAP/verification)** — only `.verified` transactions grant. All three sites pattern-match
before touching the store: `purchase` (`PrismRush/IAP/IAPManager.swift:153-157`),
`restoreEntitlements` (`:194-197`), and the `Transaction.updates` listener (`:203-205`).
*Breaks if:* a session unwraps `VerificationResult` with `.payloadValue` or an `if case` that falls
through — unverified (i.e. potentially forged) transactions grant entitlements. Note the current
`.unverified` branch also never calls `transaction.finish()`, so StoreKit redelivers it forever
(`docs/agent/scratch/meta-iap.md` §Suspicious #3).
*Detected by:* **nothing — untested.**

- **INV-84 (IAP/catalog)** — `Products.storekit` product IDs ≡ `IAPCatalog.allIDs`
(`PrismRush/IAP/IAPCatalog.swift:38`), exactly, all 7, with matching types and prices; and the five
original IDs are frozen character-for-character (comment at `IAPCatalog.swift:27`) because they are
live App Store Connect identities.
*Breaks if:* an 8th product is added to `IAPCatalog` without adding it to `Products.storekit` **and**
to App Store Connect — `StoreAvailability.afterLoad` requires `loadedCount >= catalogCount`
(`PrismRush/Meta/ShopValue.swift:139`), so availability can never reach `.ready` again and every user
drops to `.notConfigured`. Renaming an existing ID orphans every past purchase.
*Detected by:* `Tests/CoreTests/ShopValueTests.swift` `testAfterLoadFullCatalogIsReady` /
`testAfterLoadPartialOrEmptyIsNotConfigured` pin the state machine; **no test compares
`Products.storekit` to `IAPCatalog`.**

- **INV-85 (Meta/persistence keys)** — a skin id, mission id, achievement id, product id, or
`coinsPurchasedByDevice` device key is a *persistence key* and can never be reused for different
semantics or renamed (stated at `PrismRush/Meta/MissionCatalog.swift:76`).
*Breaks if:* a mission id is reused for a different objective — every player who already claimed the
old one is silently locked out of the new one via `claimedMissions`; a renamed skin id drops it out of
`ownedSkins` and the player loses a purchase.
*Detected by:* `Tests/CoreTests/SkinCatalogTests.swift` `testCatalogIntegrityAndLegacyPins` freezes 16
legacy skin ids/costs/hexes; mission and product ids are **unpinned**.

- **INV-86 (Meta/economy, decree 5)** — `ShopConsumables.mysteryOdds`
(`PrismRush/Meta/ShopValue.swift:117`) percentages sum to 100 and match `mysteryReward`'s roll bands
exactly (2+8+12+16+22+40 = 100 against bands 0.98/0.90/0.78/0.62/0.40). The odds are shown *before* the
spend.
*Breaks if:* a band is retuned without updating the published table — the app advertises odds it does
not honour, which is the exact dark pattern decree 5 forbids.
*Detected by:* `Tests/CoreTests/EconomyTests.swift` `testMysteryBoxOddsBoundaries` and
`testOpenMysteryBoxSpendsGrantsAndGatesOnCoins`.

- **INV-87 (Meta/sync)** — `coinsPurchasedByDevice` is a grow-only counter with exactly one slot per
install, keyed by `pr.device.id` — a UUID in device-local `UserDefaults`
(`ProfileStore.swift:52-58`) that deliberately never enters `Profile` and therefore never syncs.
Merging takes the per-key max.
*Breaks if:* the device key is moved into `Profile`, derived from the iCloud account, or shared — two
devices write the same slot and the per-key-max merge collapses concurrent real-money purchases into
one, erasing paid coins.
*Detected by:* `Tests/CoreTests/EconomyTests.swift`
`testCloudMergeConcurrentPurchasesOnTwoDevicesBothSurvive`.

- **INV-88 (Meta/time)** — every stored timestamp is read through a clamp: `sanitized(_:now:)`
(`ProfileStore.swift:70`) clamps five dates down to `now` at load, and `clamped(_:now:)` (`:83`)
re-clamps at each read (`dailyRewardAvailable`, `pendingDailyStreak`, `chestReady`,
`secondsUntilChest`, `todaysChallengeBest`, `recordChallengeRun`); `refreshDailyMissions` (`:387`) and
`refreshWeeklyMissions` (`:411`) inline the same `min(last, now)`.
*Breaks if:* a new timed faucet reads `profile.last…` directly — setting the device clock forward,
claiming, and setting it back makes the future-dated stamp read as elapsed forever. (Note the clamps
defend only against a *backwards* clock; a forward clock still farms both timed faucets.)
*Detected by:* `Tests/CoreTests/EconomyTests.swift` `testDailyRewardClockRollbackExploitBlocked`,
`testChestClockRollbackExploitBlocked`, `testSanitizedClampsFutureTimestampsOnLoad`;
`Tests/CoreTests/ProgressionTests.swift` `testWeeklyClockRollbackBlocked`.

- **INV-89 (Meta/catalog)** — `XPCurve.xpUnlockLevels == [3, 6, 8, 12, 18, 25]`
(`PrismRush/Meta/XPCurve.swift:71`) equals exactly the set of `.level(n)` unlocks in `SkinCatalog`
(Pebble 3, Blossom 6, Circuit 8, Shard 12, Nebula 18, Eclipse 25).
*Breaks if:* a level-gated skin is added without extending the array — the game-over "character
unlocked" tease never fires for it, and the next-unlock spotlight skips it.
*Detected by:* `Tests/CoreTests/SkinCatalogTests.swift` `testCatalogIntegrityAndLegacyPins`.

- **INV-90 (Meta/catalog, decree 1)** — no skin tracks the world palette. Every `Skin` carries authored
hexes; Prism's shimmer is `SkinCatalog.prismaticColor(at:)`, a pure clock→RGB function whose signature
structurally cannot see the world (`PrismRush/Meta/SkinCatalog.swift:283`). Derived values are never
stored: level from `totalXP` (`ProfileStore.playerLevel:217`), multiplier from `doubleCoins`
(`Profile.coinMultiplier:83`), equipped skin from `selectedSkin ∩ ownedSkins`
(`ProfileStore.equippedSkinID:214`).
*Breaks if:* a `followsWorld` flag is reintroduced (the revoked v1.3 "Prism the chameleon"
R-decision), or a level/multiplier is cached into `Profile` — the cache and the derivation drift after
any cloud merge.
*Detected by:* `Tests/CoreTests/SkinCatalogTests.swift` `testCatalogIntegrityAndLegacyPins` (asserts no
`followsWorld` and real hexes on every skin) and `testPrismaticShimmerIsPureDeterministicAndPeriodic`.

### 8.5 Audio, services, and platform (INV-91 … INV-100)

`Synth.swift` is pure DSP and is the only `Audio/` file in the SPM target; `SynthEngine`, `Music`,
`Haptics`, `GameCenterService`, `AccountService` and `Keychain` are compiled by `ios-build.yml` but
executed by **zero** tests of any kind.

- **INV-91 (Audio/Synth, Linux)** — `PrismRush/Audio/Synth.swift` imports Foundation and nothing else.
It is the only `Audio/` source listed in `Package.swift:23`.
*Breaks if:* someone adds `import AVFoundation` to move a buffer helper next to its callers —
`swift test` stops compiling on Linux and the whole SFX catalogue drops out of CI coverage in one
commit.
*Detected by:* `.github/workflows/core-tests.yml` (the `swift:6.0-noble` container fails to build).

- **INV-92 (Audio/Synth)** — every `Synth.SFX` case renders a non-empty, finite, audible
(peak > 0.005), non-clipping (peak ≤ 2.0) buffer, and every **non-gem** case satisfies
`sfx.normalized == sfx` (`Synth.swift:350`+). `.gem(streak:)` is the only case with an associated value
and `normalized` folds it mod 26.
*Breaks if:* a second case with an associated value is added without extending `normalized` — the
`[SFX: AVAudioPCMBuffer]` cache in `SynthEngine` becomes unbounded and grows for the process lifetime.
Adding a case without adding it to the test arrays leaves it entirely unpinned.
*Detected by:* `Tests/CoreTests/SynthTests.swift` `testSFXCatalogRendersAndClassifies`,
`testAllSFXAreSane`, `testV13SFXCasesRenderAndClassify`.

- **INV-93 (Audio/Synth)** — `Synth.step(beat:world:)` always returns exactly `Synth.stepFrames`
samples, and every `Synth.Bed.scale` has at least 4 degrees (`Synth.swift:286`).
*Breaks if:* a bed is authored with a 3-degree scale — `step()` indexes `scale[bassPattern[beat % 8]]`
with values 0…3 and `scale[(beat >> 1) % 4]`, so it **traps at runtime**. A variable-length step
desyncs `Music`'s `scheduledFrames += buf.frameLength` accounting.
*Detected by:* `Tests/CoreTests/SynthTests.swift` `testMusicStepsAreSaneAcrossWorlds` (asserts
`s.count == Synth.stepFrames` across 24 worlds × 8 beats).

- **INV-94 (Audio/Music)** — `Music.pump(dt:)` is called exactly once per frame while foregrounded,
**including while paused** (`GameView.swift:263` in the paused branch, `:284` in the normal branch).
*Breaks if:* the paused branch drops `musicPump` — the fade/duck envelope freezes, the master mute ramp
(which only advances inside `rampMaster`, called from `musicPump`, `SynthEngine.swift:135`) stops, and
the player's queue starves after `lookaheadFrames` ≈ 0.909 s, producing a hard audio dropout.
*Detected by:* **nothing — untested** (`Music` is never named by any test).

- **INV-95 (Audio/SynthEngine)** — `Music.scheduledFrames` is reset only together with
`player.stop(); player.play()` (in `start()` and `reanchor()`), and `recoverEngine()` calls
`music?.reanchor()` **only after** `engine.start()` has succeeded.
*Breaks if:* the counter is zeroed alone — it desyncs from `playedFrames()` and the lookahead loop
either spins or starves. If `reanchor()` can run on a stopped engine it raises an ObjC exception
(`Music.swift:60`).
*Detected by:* **nothing — untested.**

- **INV-96 (Audio/mute)** — mute is a mixer-level ramp, never a scheduling gate. `musicStart`'s comment
is explicit; `rampMaster` glides `engine.mainMixerNode.outputVolume` toward `masterTarget` over ~0.15 s
(`SynthEngine.swift:134-144`). SFX playback *is* hard-gated on `!muted` (`:101`) — that is safe because
one-shots have no timeline.
*Breaks if:* someone gates `music?.pump` or the buffer scheduling on `muted` — `scheduledFrames`
desyncs from `playedFrames()` and the sequencer wedges. Corollary: because the ramp only advances
inside `musicPump`, toggling mute does nothing to music when the frame loop is not running.
*Detected by:* **nothing — untested.**

- **INV-97 (Audio/SynthEngine)** — `sfxBusyUntil.count == sfxPlayers.count` at all times
(`SynthEngine.swift:64` establishes it; `schedule` indexes both arrays with the same `idx`).
*Breaks if:* the `for _ in 0..<10` voice-pool loop is resized without re-initialising `sfxBusyUntil` —
an out-of-range index crashes the app on the first SFX.
*Detected by:* **nothing — untested.**

- **INV-98 (Services/GameCenter, iron rule 10)** — `submitRun(score:usedCheckpoint:)` returns without
submitting whenever `usedCheckpoint == true` (`PrismRush/Services/GameCenterService.swift:32-35`);
`submitDailyChallenge` passes `context = ProfileStore.daysSinceEpoch(Date())` (UTC days) so a score's
challenge date is recoverable (`:47-53`). Both submit `core.score`, read at the death tick.
*Breaks if:* the checkpoint guard is dropped — checkpoint runs start at end-game speed from t=0 and
would poison `prismrush.best` for every player. If the context value changes meaning, past daily
scores become unattributable.
*Detected by:* **nothing — untested.** `Tests/CoreTests/GameplayTests.swift` pins that a checkpoint run
sets `usedCheckpoint`, but nothing pins the submission guard.

- **INV-99 (Concurrency, iron rule 8)** — non-isolated callbacks use `MainActor.assumeIsolated` **only**
where main delivery is contractually guaranteed (`queue: .main`, UIKit delegate); callbacks with no
such guarantee hop with `Task { @MainActor }`. Current split: `assumeIsolated` at
`SynthEngine.swift:165, 171, 174`, `ProfileStore.swift:42`, `IAPManager.swift:60`,
`RealityRenderer.swift:184`, `GameCenterService.swift:18` and `:64`, `GameView.swift:256`;
`Task { @MainActor }` at `AccountService.swift:42` (`getCredentialState`, arbitrary queue).
*Breaks if:* a session flips either direction — `assumeIsolated` off-main is a `fatalError` (an
unlaunchable app if it happens in the GameKit auth handler at launch), and an unnecessary `Task` hop
turns a synchronous notification into a deferred one, reordering it against the frame loop.
*Detected by:* **nothing — untested.** Two of the nine sites (GameKit `authenticateHandler`,
RealityKit `SceneEvents.Update`) have **no documented main-thread guarantee** at all — see
`docs/agent/scratch/trace-concurrency.md` §2.

- **INV-100 (Platform declarations)** — Keychain items are `kSecClassGenericPassword` +
`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` with **no** `kSecAttrSynchronizable`
(`PrismRush/Services/Keychain.swift:12-28`); the Apple user id never goes back into `UserDefaults`
(the v1.4.3 migration in `AccountService.loadMigrating` exists to undo exactly that). Separately, every
required-reason API the app calls must appear in `PrismRush/Support/PrivacyInfo.xcprivacy`.
*Breaks if:* an item gains `kSecAttrSynchronizable` (the account id starts crossing devices, unlike the
profile which syncs deliberately via KVS); or a required-reason API is added without a manifest entry.
The manifest currently declares only `NSPrivacyAccessedAPICategoryUserDefaults`/`CA92.1`
(`PrivacyInfo.xcprivacy:7-12`) while `SynthEngine.swift:150` calls
`ProcessInfo.processInfo.systemUptime` — an undeclared `NSPrivacyAccessedAPICategorySystemBootTime`
(`35F9.1`) use that produces `ITMS-91053` on upload.
*Detected by:* **nothing — untested** in-repo; App Store Connect upload validation is the only gate.

### 8.6 Build, tests, and process (INV-101 … INV-110)

These are the invariants a session violates *silently* — the suite stays green, the app still launches,
and the damage surfaces days later.

- **INV-101 (Process/determinism, iron rule 3)** — any change to a spawner, a pattern, or RNG
consumption must (a) keep the solvability bot green and (b) bump `DailyChallenge.layoutVersion` and
re-pin the goldens. `Tests/CoreTests/DailyChallengeTests.swift:7-24` states the prohibition directly:
"that is a `layoutVersion` bump, not an edit here." The current default is 7; the v8 golden is
**pre-armed** at `:23` and must be replaced with the real v8 values and re-armed for v9 when the bump
lands.
*Breaks if:* a session edits the goldens to make a red test go green — every player's daily track
changes without a version bump, so two clients on the same UTC day play different runs against one
shared leaderboard. Consuming one extra `rng.unit()` anywhere in the spawn path does this invisibly.
*Detected by:* `Tests/CoreTests/DailyChallengeTests.swift` `testGoldenSeeds`,
`Tests/CoreTests/PatternOrderTests.swift` `testTierLadderMonotoneAndRNGCountsPinned` (pins the
per-pattern RNG-call vector `[1,1,0,1,1,3,1,2,0,1,1,1,2,0]`), and
`Tests/CoreTests/SolvabilityBotTests.swift` (200 seeds × 6,000 m + 64 seeds × 12,000 m).

- **INV-102 (Process/CI)** — **Linux green ≠ the app builds, and neither proves the app behaves.**
`swift test` compiles 18 files (`Package.swift:14-24`); 52 production files — all of `Render/`, `UI/`,
`App/`, `IAP/`, `Services/`, `Audio/SynthEngine.swift`, `Audio/Music.swift` — are never compiled by
SPM. They *are* type-checked by `.github/workflows/ios-build.yml`'s `build-for-testing` step against a
generic simulator (CLAUDE.md's claim that they are "not even type-checked" is out of date), but their
runtime behaviour is proven only by a human running `Tools/ci.sh`.
*Breaks if:* a session ships a UI, renderer, audio-engine, StoreKit or GameKit change on the strength
of `swift test` alone. Any such change needs a Mac build, and behavioural changes need the XCUITests
that only `ci.sh` runs.
*Detected by:* `.github/workflows/ios-build.yml` for compile errors; **nothing** for behaviour.

- **INV-103 (Build/Package.swift)** — `Package.swift`'s `sources:` is an explicit allow-list. The whole
`"Core"` **directory** is listed (new Core files are picked up automatically), but `Meta/` and
`Audio/` files are named **individually** (`Package.swift:15-23`, 7 Meta files + `Synth.swift`).
*Breaks if:* a new pure file is added to `Meta/` or `Audio/` and not to the list — Linux CI silently
stops compiling and covering it, with no error and no warning. The inconsistency with the `"Core"`
entry is what makes this easy to miss.
*Detected by:* **nothing — untested.** The failure mode is absence, not failure.

- **INV-104 (Tests/Linux)** — `Tests/CoreTests/**` compiles against Foundation + Observation only. No
`import UIKit`, `SwiftUI`, `RealityKit`, `StoreKit`, `AVFoundation`, or `GameKit`.
*Breaks if:* a test reaches for a rendering or StoreKit type — `core-tests.yml` turns red on Linux even
though the local macOS `swift test` may still pass, because macOS exposes more SDK surface than the
Linux container.
*Detected by:* `.github/workflows/core-tests.yml`.

- **INV-105 (Tests/platform gating)** — a test wrapped in `#if canImport(UIKit)`, or placed in
`Tests/` **outside** `Tests/CoreTests/`, does not run under `swift test` and does not run on Linux CI —
and reports no skip. Today that is exactly `Tests/CoreTests/CharacterParityTests.swift:4` (3 tests,
iOS-Simulator bundle only) and `Tests/WorldPaletteTests.swift` (4 tests, Xcode bundle only).
*Breaks if:* a session adds a UIKit-gated test believing it runs everywhere, or if
`ios-build.yml`'s `test-without-building` step is removed or its `name=iPhone 16` simulator lookup
fails — those 7 tests then execute **nowhere** and the Linux job stays green. This is why the file tree
declares 181 tests in `Tests/CoreTests` while `swift test` executes 178.
*Detected by:* **nothing — untested.** Compare measured counts instead: `swift test -c release` = 178,
the Xcode unit bundle = 185, the UI bundle = 11.

- **INV-106 (Process/simulator)** — never run `simctl` screenshots, installs, or launches against the
same simulator while `xcodebuild test` is running on it. `Tools/qa.sh:7` and `Tools/screenshots.sh:22`
install to hardcoded UDIDs; `Tools/build.sh` and `Tools/ci.sh` select **by name** (`PR_SIM_NAME`,
default `iPhone 17 Pro`) and can resolve to a different device with the same name.
*Breaks if:* the two overlap — the concurrent install kills the test host and `xcodebuild` reports a
false "TEST FAILED" that has nothing to do with the code under test.
*Detected by:* **nothing — untested;** it manifests as an unreproducible test failure.

- **INV-107 (Tests/debug hooks)** — `GameCore.debugForceDie` / `debugClearTrack` / `debugSpawn` /
`debugActivateSuperSneakers` and `Patterns.debugGemArc` stay **unconditionally compiled**. There is no
`#if DEBUG` anywhere in `Core/` or `Meta/`.
*Breaks if:* a session wraps them in `#if DEBUG` for hygiene — the suite runs `swift test -c release`
and `xcodebuild` builds Release for archives, so the entire hand-built-scenario idiom
(`cleanCore` → `debugClearTrack` → `debugSpawn`) fails to compile and most of the suite disappears.
*Detected by:* `.github/workflows/core-tests.yml` (`swift test -c release` fails to build).

- **INV-108 (Build/config)** — every `xcodebuild` invocation in `Tools/build.sh:15` and `Tools/ci.sh`
keeps `CODE_SIGNING_ALLOWED=NO` (the project carries a real `DEVELOPMENT_TEAM`,
`project.yml:12`), and `PrismRush/Support/PrismRush.entitlements` is **generated** by xcodegen from
`project.yml`'s `entitlements.properties` (`project.yml:26-27`) and must never be hand-edited.
*Breaks if:* the signing flag is dropped — local and CI builds demand a provisioning profile and fail
on any machine without the team's certificates. If the entitlements file is edited directly, the next
`xcodegen generate` silently reverts it, taking Sign in with Apple / Game Center / iCloud-KVS with it.
*Detected by:* the build itself fails loudly for signing; the entitlements revert is
**undetected — untested.**

- **INV-109 (Tests/XCUITest)** — `InteractionUITests.launch()` must keep setting `PR_SKIP_SPLASH=1`
(the splash covers the menu and every menu assertion in all 11 tests fails without it), and every
UITest must stay tolerant of the fact that **CI never executes them**:
`.github/workflows/ios-build.yml:64` passes `-only-testing:PrismRushTests`, so the UI bundle is
compiled by `build-for-testing` and run only by a human invoking `Tools/ci.sh`.
*Breaks if:* a session treats a green GitHub check as covering behaviour, or relies on `PR_*` env
fixtures (`PR_DEMOPROFILE`, `PR_FIRSTRUN`) whose pinned values in `GameView.swift:146-192` drift from
what the tests assert — those tests assert against numbers baked into the app, not against a fresh
player.
*Detected by:* **nothing — untested** (by construction: the tests that would detect it are the ones not
running).

- **INV-110 (Tools/assets, iron rule 6)** — `Tools/gen_icon.swift` must leave
`PrismRush/Assets.xcassets/AppIcon.appiconset/icon_1024.png` byte-identical to `Store/icon_1024.png`.
The sync fires **only** when `outPath` is exactly the default `"Store/icon_1024.png"`
(`gen_icon.swift:298`), and it deletes the catalog copy before it copies (`:299-306`).
*Breaks if:* the tool is run with a custom output path — the sync is skipped silently and the shipped
springboard icon drifts from the generated one. If the `copyItem` throws after the unconditional
`removeItem`, the tool exits 1 having already deleted the only app icon in the catalog, and the app
builds iconless. Never hand-edit the PNG, and never add anything else to `Assets.xcassets` (the icon
set is the sole carve-out from the zero-binary-assets rule).
*Detected by:* **nothing — untested.**

---

## 9. Gotchas

Things that are **working as designed** and will still cost you twenty minutes. Known *defects* are
not here — they live in `03_BACKLOG.md`. Every line below was re-checked against source at HEAD
`7e87380`.

### Simulation

- **`z` is `distance − d`, so negative means AHEAD of the player and positive means behind**
  (`Core/GameCore.swift:9`, used at `:385`, `:468`, `:505`). The Autopilot uses the *opposite* sign:
  `arrival = o.d − c.distance` (`Core/Autopilot.swift:29`, `:96`). Both conventions appear within a
  few dozen lines of each other in tests.
- **`lane == -1` means full-span bar — except for `.splitBar`, where `lane` is the OPEN (safe) lane**
  (`Core/Models.swift:32`, `Core/Patterns.swift:9`). `Autopilot` and `Spawner.safeEntryLane` both
  invert it. Read it as "blocked" and the bot steers into the bar.
- **`distance` keeps integrating in `.menu` and `.over`.** Menu drift is a constant scroll; the
  `.over` decel slide keeps adding metres, which is why `revive()` folds the delta into `scoreOffset`
  (`Core/GameCore.swift:613`). Only `score` is frozen by `die()`.
- **Four near-identical distance/speed fields.** `snapshot.distance` is absolute;
  `traveledDistance` is `distance − scoreOffset`, i.e. this attempt only (`GameCore.swift:117`);
  `snapshot.speed` is the *effective* (chrono-slowed) speed; `rampSpeed` is the raw ramp. Mixing
  them produces HUD/FOV bugs that only appear while chrono is active.
- **`tick()` does not rebuild the snapshot.** A test that asserts on `core.snapshot` must call
  `advance(realDt:)`; three test files carry an explicit comment saying so.
- **`Spawner.fill(to:dist:…)`'s `dist` is the PLAYER's distance, not the spawn cursor**
  (`Core/Spawner.swift:35`). Patterns are placed up to ~115 m ahead but *gated* by where the player
  is now, so the 260 m tier boundary actually opens tier-2 patterns at cursor positions ~260–375.
- **`chronoFactor` is applied to distance, not to `dt`.** Player physics still run at real time;
  only the world scroll slows. That is what makes chrono strictly easier.
- **Sliding does not clear a low, and jumping does not clear a bar.** Slide bottom is 0.0752 vs
  `lowKillTop` 0.85; bars need `sy < 0.7734`. The landing squash `landSquashY = 0.68` happens to sit
  under the bar threshold, which is the only reason the bot's air-slam-then-land works.
- **The moving-wall gate is always `phase: 0`.** `Patterns` never emits a non-zero phase, and both
  `safeEntryLane` and `Autopilot` hardcode "phase-0 wall crosses CENTRE". Introducing a phase
  silently invalidates both.
- **`Patterns.count == 14` but `run` has a `default: return 14` arm** — an out-of-range index emits
  nothing and advances the cursor 14 m instead of trapping.
- **`reset(seed:)` sets `nextId = 0`** (`Core/GameCore.swift:152`), so entity ids restart from zero
  every run. Anything keyed by id across a reset (renderer pools) must be cleared in the same beat.
- **`GameCore` is `@Observable @MainActor final class`** (`Core/GameCore.swift:22-23`), not an actor
  and not a struct. The "headless deterministic core" is main-actor-bound: the SPM suite, including
  the 200-seed bot, asserts on the main actor.
- **`GameCore.init` and `reset(seed: nil)` call `.random(in: .min ... .max)`**
  (`Core/GameCore.swift:81`, `:139`). That is the *seed source*, not sim randomness, and it is
  deliberate — but it means a freshly constructed core, and every `returnToMenu()`
  (`UI/GameView.swift:497`), is not reproducible. Do not "fix" it into a constant.
- **`jumpBuf` is decremented but never clamped**, so it drifts unboundedly negative over a long run.
  Harmless (`> 0` guards everywhere), startling in a debugger.
- **`apply` silently drops spawns at the pool cap** — no log, no counter, no FX. A "coins are the
  path" trail can be half-missing with zero signal.
- **The gap coin trail is placed BEHIND the current cursor** (`cursor − gap + 1.0` … `cursor − 0.5`)
  using *this* pattern's gap as a stand-in for the previous one. It always lands inside the real gap
  only because gap shrinks monotonically.
- **`freeLaneNear` skips a cadence power-up without advancing `powerUpIndex`**, so the
  shield→magnet→doubler→chrono→sneakers cycle survives the skip but `powerUpCursor` still jumps
  350 m. A dense obstacle stretch can go 700+ m with no cadence pickup.

### Renderer

- **`advanceVisuals` runs *before* `sync`, so several fields are one frame stale by design.**
  `lastSpeed`, `runBobOn`, `speedNorm`, `lastSliding` are written in `sync` and read by the *next*
  frame's `advanceVisuals`. `resetEntities` zeroes them explicitly for this reason
  (`Render/Reality/RealityRenderer.swift:685`).
- **`snapshot.worldFrom` / `worldTo` are the 0–2 palette *family*, not the world.** Everything in
  `Render/` uses `worldOrdinal` and reconstructs the "from" side as `ordinal − 1`
  (`RealityRenderer.swift:1090-1094`). Using `worldFrom` collapses worlds 0 and 3 onto one palette —
  that was the v1.4.3 bug.
- **`Theme.worlds.count == 12`, not 3** (`UI/Theme.swift:22`). `cycle = ordinal / worlds.count`, so
  ordinals 0–11 are all cycle 0 and `Theme.evolvedPalette` is the identity for them; hue rotation and
  the roman-numeral suffix start at ordinal 12 (`Theme.swift:63-68`). Any hardcoded `/3` gives world 3
  a spurious "II".
- **`WorldDecor.style` disables *all* side silhouettes for folded index ≥ 3**
  (`Render/Reality/WorldDecor.swift:105-109`) — worlds 3–11 carry identity purely through
  `WorldSky`. The 28 slot groups still exist and still get a `position.z` write every frame.
- **Vertical camera follow only engages above `playerY ≈ 2.9`** (`RealityRenderer.swift:273`), just
  past a normal jump apex (~2.82). It exists solely for Super Sneakers leaps; ordinary jumps are
  untouched, which reads as "the follow is broken".
- **The slide camera is three separate smoothed channels**, not one: `slideDip` (eye height −2.1 and
  dolly-in −0.8), `lookY` (pitch −0.85), `slideRoll` (−0.06 rad z-roll). Reduce Motion deliberately
  keeps a 0.6-unit height dip, because slide state is gameplay information.
- **`shimmerStep = Int.min` is the "re-derive now" sentinel** set by `applySkin`
  (`RealityRenderer.swift:722`); the prismatic body/trail only repaint when the quantized 30 Hz step
  changes.
- **`elapsed` is app-lifetime, not run-lifetime** (declared `RealityRenderer.swift:81`, incremented
  once per frame at `:578`) and is the animation clock handed to every sky family via
  `decor.update(…elapsed:…)` (`:469`). `resetEntities()` does not reset it, on purpose.
- **`resetEntities()` calls `decor.reset(distance: 0)` unconditionally**, even for a checkpoint start
  at distance 4800. It self-heals on the first `update` via `while z > 14 { s.d += span }` — ~26
  iterations × 28 slots on one frame.
- **`ProceduralMesh.build` silently substitutes a sphere** if `MeshResource.generate` throws
  (`Render/Reality/ProceduralMesh.swift:278`). A broken new mesh shows up as a mystery ball, not an
  error.
- **`WorldDecor` uses the system RNG (`Float.random`) while `WorldSky` uses a local `SplitMix64`.**
  Side decor differs run-to-run for the same world; sky set pieces do not. Both are iron-rule-2 safe
  (neither touches the core RNG); the inconsistency still surprises.
- **`ParticleSystem.emit` advances the cursor before checking for a free slot**
  (`Render/Reality/ParticleSystem.swift:108`), so slot 0 is only ever used after a full wrap.
- **Read `EntityState.y`; never assume a height.** The values (bar 1.3, low 0.425, tall 1.6) look
  hardcodeable and are not.

### UI

- **There is exactly one gesture in the whole app and it fires on finger LIFT.**
  `DragGesture(minimumDistance: 0).onEnded` at `UI/GameView.swift:1058` → `handleGesture`
  (`:893-911`), where a bare `22` pt threshold splits tap from swipe. "The jump feels late" is here,
  not in Core.
- **`core.mode` and `core.snapshot.mode` can disagree for one frame.** `handleGesture`,
  `togglePause`, `canRevive`, `canDeploy*` and the frame loop read the live `core.mode`;
  `GameView.body`'s switch, the corner cluster and the sheet gate read the snapshot's.
- **`GameCore.reset(seed:)` does not call `rebuildSnapshot()`** (`GameCore.swift:138-154`), so
  `returnToMenu()` leaves `snapshot.mode == .over` until the next frame. `startRun` and `revive` do
  rebuild.
- **The death panel's distance keeps ticking** — `GameView.swift:1119` passes the *live*
  `core.traveledDistance` while `.over` is still integrating.
- **`uiClock` advances while paused but `ageEffects` does not.** Pause for 10 s and resume: every
  queued popup expires at once and any live reward toast dies.
- **`beginRun` is bypassed by the autoplay bootstrap.** `install` calls `core.startRun(seed: 7)`
  directly (`GameView.swift:212`), so `previousBest`, `reachAtRunStart`, `statsRecorded` and friends
  are uninitialised for that first demo run.
- **`MenuView` is generic over its `loadout` child on purpose** (`UI/MenuView.swift:20-23`):
  `rewards` is `AnyView`, `loadout` is concrete, because `AnyView` severed `@Observable` tracking and
  produced the "Head Start does nothing" bug. Do not simplify it.
- **The hub is not a `NavigationStack` and meta screens are not `.sheet`s** — they are ZStack layers
  switched by `model.activeSheet` (`GameView.swift:1145`), which is why Profile → Settings works by
  swapping the enum. The only real system sheet in the meta layer is `RewardsMiniSheet`
  (`UI/ClaimRibbon.swift`, the rewards mini-sheet). Meta sheets also render over the death panel, deliberately.
- **The reward toast and tutorial hint are animated at the ZStack root**
  (`GameView.swift:1218-1219`), so those two value changes apply an implicit animation to *every*
  sibling — the `RealityView` container included.
- **Deploy buttons are hidden, not dimmed, at zero charges**, so the `charges == 0` branches inside
  `deployButton` are unreachable from `deployControls`.
- **`silhouette:` no longer means silhouette.** Since v1.4 it renders the full-colour "tease" at 0.45
  opacity plus a solid lock chip; the parameter name was kept so call sites compiled
  (`UI/CharacterSwatch.swift:17-21`).
- **`AnimatedCharacterSwatch` frames itself at `size × size*heightScale` (default 1.5).** A caller
  that wraps it in `.frame(width: size, height: size)` crops the antennas.
- **`CharacterHeroStage` renders the swatch twice when Reduce Motion is off** — the mirrored
  reflection is a second live `Canvas`. That is why the select grid uses bare swatches.
- **`WorldPreviewCanvas` mixes two dispatch schemes**: explicit `case 3…11` for bespoke worlds, then
  a `default` that falls through to `worldIndex % 3`. Adding world 12 to `Theme.worlds` without
  adding a `case` silently gives it a Pulse-City skyline.
- **`WorldCard.isPurchase` is `world > profile.maxWorldReached`** — the gold OWNED badge means
  "bought", not "reached". `maxWorldReached` is deliberately never advanced by a purchase.
- **`ShopView` uses `auroraID` for *every* premium skin's price and accessibility label** (`:597`,
  `:627`); only Aurora is `.iap` today. Three product ids are hardcoded as `private static let`
  (`:680-682`).
- **`Theme.Space` / `Radius` / `TypeScale` exist but the in-run surfaces barely use them.**
  `HUDView`, `GameOverView`, `EffectsOverlay`, `SettingsView`, `MysteryBoxView` and `PowerUpsView`
  use raw `.system(size:)` and raw pt paddings.
- **`PR_*` launch hooks are extensive and live in production `onAppear`/`install` bodies**
  (`GameView.swift:146-253`, plus `PR_MYSTERYBOX`/`PR_BUYPACK` in `ShopView`, `PR_PLAYCONFIRM` in
  `LevelSelectView`, `PR_POWERUPS` in `SettingsView`). `PR_DEMOPROFILE` rewrites the *real* profile.
  They are compiled into release builds too.

### Meta and IAP

- **Reading the missions UI writes to disk.** `dailyMissions`, `weeklyMissions`, `unclaimedCount`,
  `claimMission` and `openFreeChest` all call `refreshDailyMissions`/`refreshWeeklyMissions`, which
  `mutate` → `save()` → `UserDefaults.set` + `cloud.set` + `cloud.synchronize()` on a day/week
  rollover. `MenuView`'s `navRail` calls `unclaimedCount(now:)` **from inside `body`** (was `RewardsBar.swift:23`).
- **`ProfileStore.load` prefers iCloud over local with no merge** (`Meta/ProfileStore.swift:700-708`).
  `merged()` (`:657-689`) is only ever reached from the external-change notification, never at launch.
- **`merged()` keeps the local value for every field it does not name** (`var merged = local`,
  `:658`). Adding a `Profile` field without adding a merge line means "local always wins" silently.
- **Achievement-gated skins need the tier *claimed*, not reached.** `SkinUnlocks.earned` reads
  `profile.achievementTier`, which only `claimMission` advances — running 10,000 m does not grant
  Drift until you open Missions and tap Claim. `GameView.closeSheet` calls `checkSkinUnlocks()`
  specifically so the popup lands on the way out.
- **Two clocks.** Daily login uses `Calendar.current` (`ProfileStore.swift:301-309`); missions, the
  daily challenge and every day key use a UTC gregorian calendar (`:354-355`). A player at UTC+13
  gets their bonus and their mission board on different boundaries.
- **`xpLevelRewarded` defaults to `1`, not `0`** — level 1 pays nothing, so the watermark starts at
  the first unpaid level minus one.
- **`bestDistanceByWorld` keys, and the `0`-valued per-run mission keys written by `applyRunSummary`,
  live forever** — a per-key-max merge can never delete a key. This is the main growth vector against
  the 1 MB KVS value cap.
- **`refreshDailyMissions`'s comment contradicts its code.** The comment says a clock set backwards
  "simply re-rolls the board"; the `min(last, now)` clamp actually *keeps* the current board. The
  code is right; the comment is wrong.
- **`IAPCatalog.apply` auto-equips a purchased skin** (`$0.selectedSkin = s`, `IAPCatalog.swift:58`) —
  buying Aurora silently changes your character. `restore` deliberately does not.
- **`.notConfigured` is the normal pre-App-Store-Connect state and is not an error.** Only a thrown
  `Product.products(for:)` yields `.offline`, and only `.offline` auto-retries; `.ready` never
  downgrades mid-session.
- **Restore Purchases exists only in Settings** (`UI/SettingsView.swift:172-188`, a11y id
  `restorePurchasesRow`). The Shop has no restore button; it only surfaces `lastError`.
- **`Skin` is deliberately not `Codable`** — persisting one would make every catalog edit a
  save-migration problem. And **`SkinCatalog.skin(_:)` never fails**: an unknown id silently becomes
  Prism (`Meta/SkinCatalog.swift:267`), so a typo'd id presents as "the purchase did nothing".
- **`slowMoCharges` and the other consumables are device-local by design** — the docstring at
  `ProfileStore.swift:643-648` explains why a `max()` merge would be worse.
- **The revive rule lives in the UI layer, not Meta, and is three magic numbers**: `reviveCost =
  150 * (revivesUsed + 1)` (`GameView.swift:454`), the cap `< 2` (`:456`), and `2 - revivesUsed`
  again at `:1126`. None is in `Tuning`.
- **`ProfileStore.shared` reads and writes the real `UserDefaults` and real iCloud KVS in any
  process that touches it**, including the UITest host and autoplay runs. That is why
  `PR_DEMOPROFILE` (`GameView.swift:146-192`) is ~45 lines of exact pins. Unit tests avoid it
  entirely by constructing `ProfileStore(testing:)` (`ProfileStore.swift:25-29`); grep finds zero
  uses of `.shared` under `Tests/`.

### Audio and services

- **Production music is pinned to `world = 0` and never varies.** `musicPump` sets `music?.world = 0`
  unconditionally (`Audio/SynthEngine.swift:133`) per an explicit v1.6 owner decree. The 12-entry
  `beds` table, `Synth.step(beat:world:)`'s `world` argument, the cycle-layering code and two whole
  test functions all exercise a path production cannot reach. Reading `Synth.swift` alone tells you
  per-world music ships. It does not.
- **The audible loop is one bar ≈ 1.82 s.** Bass is 8 entries, hat is `beat % 2`, kick `beat % 4`,
  arp `(beat >> 1) % 4` — everything cycles at `beat % 8`, and with `world` pinned, `cycle = 0` so no
  layering ever engages. There is no long-form variation anywhere.
- **Mute is two different mechanisms.** SFX are hard-gated (`play` guards `!muted`); music is a
  ~0.15 s ramp of `engine.mainMixerNode.outputVolume` that only advances inside `rampMaster`, which
  only runs from `musicPump`. **If the frame loop is not running, toggling mute does nothing to
  music.**
- **`AVAudioSession` is `.playback` on purpose** (`Audio/SynthEngine.swift:86`): `.ambient` killed
  audio when the ringer switch was off. Consequence: the silent switch no longer mutes the game.
- **Two music volume sliders feed one `Music.userVolume`.** `musicIsCalm`, flipped only by
  `musicStart(calm:)`, selects between `musicVolume` and `menuMusicVolume`. Dragging the inactive
  one changes nothing audible until the context flips — intended, but it looks like a dead slider if
  you test on the wrong screen.
- **Every `noise()` burst uses the same default seed `0x1234_5678`.** That determinism is what makes
  the SFX buffer cache legitimate; it also means two `noise()` calls at the same offset in one SFX
  would be perfectly correlated. No current SFX does that.
- **The engine format is 44.1 kHz mono Float32 non-interleaved** while the hardware typically runs
  48 kHz; `AVAudioMixerNode` converts. All of `Music`'s frame arithmetic is in the player's 44.1 kHz
  domain — do not mix in a hardware-rate number.
- **`stepFrames` is truncated, not rounded** (`60/132/2 * 44100 = 10022.727 → 10022`), so the real
  tempo is 132.0096 BPM and `stepFrames * beats != dur * sampleRate` exactly.
- **There is no server.** "Account" means an Apple user id string in the Keychain. Saves sync via
  `NSUbiquitousKeyValueStore`, which is tied to the *iCloud* account, not to the Sign in with Apple
  credential. Signing out does not affect save sync.
- **`ProfileView` never presents the unauthenticated leaderboard branch** — both `showLeaderboard()`
  call sites sit behind `if gc.authenticated`, so `GameCenterService.swift:58`'s
  `GKGameCenterViewController(state: .leaderboards)` fallback is unreachable today.
- **Nine `MainActor.assumeIsolated` sites, and zero of anything else.** Grep over `PrismRush/`,
  `Package.swift`, `project.yml` and `Tools/` returns **zero** `@unchecked Sendable`,
  `nonisolated(unsafe)`, `Task.detached`, `DispatchQueue`, `@preconcurrency`, `@retroactive`,
  `.unsafeFlags`. Seven of the nine are provably safe — six wrap notification block observers
  registered with `queue: .main` (`RealityRenderer.swift:184`, `ProfileStore.swift:42`,
  `IAPManager.swift:60`, `SynthEngine.swift:165`, `:171`, `:174`) and one is a UIKit
  view-controller delegate (`GameCenterService.swift:64`). The remaining two rest on undocumented
  conventions: the frame loop's (`UI/GameView.swift:256`, RealityKit's `SceneEvents.Update`) and
  GameKit's (`Services/GameCenterService.swift:18`, `authenticateHandler`).
  **`AccountService.swift:41-43` is the contrasting correct pattern** — it hops via
  `Task { @MainActor }` instead of asserting, because `getCredentialState`'s completion has no
  main-thread guarantee. Copy that shape, not the assertion, for any new non-isolated callback.
  (`trace-run-lifecycle.md` §5.9 calls the Game Center submission a "detached `Task`". It is not —
  `GameCenterService.swift:39` and `:49` are plain `Task { }` inside `@MainActor` methods.)

### Build, tooling, and environment

- **The repo lives under iCloud-synced `~/Desktop`, and that breaks codesigning.** The file provider
  stamps `com.apple.fileprovider.fpfs#P` / `com.apple.FinderInfo` xattrs onto build products faster
  than `xattr -cr` strips them; device builds and archives then fail with "resource fork, Finder
  information, or similar detritus not allowed" (exit 65). Simulator builds in the repo-local `.dd`
  never codesign, so this only surfaces on the first physical-device build or CLI archive. **Fix:
  pass `-derivedDataPath` outside the synced tree** (e.g. `/tmp/prismrush-devicedd`).
- **iCloud also races heavy agent editing into conflict copies** named `<file> 2.swift` /
  `<dir> 2.xcodeproj`. XcodeGen globs them as sources → duplicate-symbol build breaks. `.gitignore`
  blocks the patterns, but after any large multi-agent session run
  `find . -name "* 2.*" -not -path "./.git/*"` and purge before building.
- **`*.xcodeproj` is gitignored and regenerated by `xcodegen` from `project.yml`.** So is
  `PrismRush/Support/PrismRush.entitlements` — it *is* git-tracked, but XcodeGen rewrites it from
  `project.yml:26-32` on every generate. Edit `project.yml`, never the project inspector and never
  the entitlements file.
- **`PrismRush/Support/PrivacyInfo.xcprivacy` lands at the bundle root**, not in a `Support/` folder,
  because Xcode copies resources flat. XcodeGen classifies `.xcprivacy` as a resource and
  `.entitlements` as no-build-phase — that is XcodeGen behaviour, not something this repo asserts.
  Verify with `unzip -l` on the .ipa after any build-config change.
- **`.gitignore` excludes `reports/shots/*.png`.** Every "evidence in `reports/shots/vNN/`" pointer
  in `README.md` and `state.md` is a dead link on a fresh clone. Only `docs/screenshots/` is
  committed.
- **`swift test` runs 178 but `Tests/CoreTests` declares 181, and there is no "skipped" line.** The
  3-test delta is `CharacterParityTests`, wrapped in `#if canImport(UIKit)`
  (`Tests/CoreTests/CharacterParityTests.swift:4`) — false on plain macOS *and* Linux, so SPM
  compiles it to nothing everywhere it runs. It only executes inside the Xcode iOS bundle. For the
  same reason `Tests/WorldPaletteTests.swift` sits directly under `Tests/`, not `Tests/CoreTests/`.
  Moving either file silently changes both platform counts.
- **Every documented test count in the repo is wrong.** `CLAUDE.md` says 95 (89 unit + 6 XCUITest);
  `Tools/ci.sh:10` says 174 at v1.4.3; reality at HEAD is **178 SPM / 185 Xcode unit / 11 XCUITest =
  196**. `CLAUDE.md` also says Linux compiles "4 Meta files"; `Package.swift` lists **7**.
- **`CLAUDE.md` is the least up-to-date document in the repo.** Its *decrees and iron rules* are
  current and authoritative; its architecture and build facts are frozen at ~v1.2. Do not use it to
  size the code.
- **`swift test -c release` is compile-dominated**: 7.28 s of testing, 28.89 s wall clock on a warm
  build. The "~9 s" in `CLAUDE.md` is XCTest time only, and stale.
- **`SolvabilityBotTests` is 96 % of the runtime** (4.26 s + 2.55 s). If the suite suddenly takes
  minutes, a spawner change has pushed the bot toward `maxTicks = 400_000`
  (`Tests/CoreTests/SolvabilityBotTests.swift:93`), which surfaces as a **STALLED failure**, not a
  hang.
- **Two simulators can share the name "iPhone 17 Pro" on the dev machine.** `build.sh`/`ci.sh` select
  **by name**; `qa.sh`/`screenshots.sh` install **by UDID**. They can target different devices in the
  same session. `ci.sh` also regenerates the Xcode project twice (its own step (a), then again inside
  `build.sh`).
- **`gatherCoverageData: true` is set on the scheme (`project.yml:77`) and nothing consumes it.** No
  workflow, script or gate reads the coverage report; the global 80 % rule is unenforced here.
- **`Tools/screenshots.sh` does not drive the app.** It sleeps `PR_SHOT_DELAY` (default 3 s) and
  prints a human-readable hint between shots. Run unattended, all six PNGs are the same frame.
- **`UITests/InteractionUITests.swift` sets `continueAfterFailure = false`** — one early failure hides
  every later assertion in that method, so a broken menu reads as one failure, not ten.
- **Never run `simctl launch` / screenshots on the dev sim while `xcodebuild test` is running on it.**
  Concurrent installs crash the test host and report a false "TEST FAILED".
- **Two design docs, one shipped.** `reports/design/V15_WORLDS_design.md` is the pre-critique draft
  (white World 12, per-world music); `reports/design/V15_WORLDS.md` is the reconciled blueprint that
  matches the code. Nothing in the `_design` file warns you. Same class:
  `reports/AGENT_render.md`'s "NOT yet wired" list was later wired by `reports/AGENT_integration.md`
  §2, and `reports/AGENT_meta.md` §7's TIME-tile snippet is the exact bug `reports/QA.md` fix 1
  removed — do not copy from the spec, copy from `GameView`.

---

## 10. Divergences from the global Swift rules

The user's global rules (`~/.claude/rules/swift/*.md`, `~/.claude/rules/common/*.md`, the
`ios-swiftui` skill) target a Firebase/MVVM/Swift-Testing app-team stack. This repo is a
zero-dependency, deterministic-simulation game with a Linux CI job. It deliberately differs.
**Per the program rules the repo wins.** The point of this table is to stop a future session
"fixing" the repo into compliance with a rule that does not apply to it.

| Rule | What the global rule says | What this repo does | Why the repo is right here | Do not "fix" this |
|---|---|---|---|---|
| **Test framework** | `swift/testing.md`: "Use **Swift Testing** (`import Testing`) for new tests. Use `@Test` and `#expect`." | **Zero** `import Testing` anywhere; 22 files `import XCTest`; 178 SPM tests + 11 XCUITests, all XCTest. The `swift test` tail even prints `✔ Test run with 0 tests in 0 suites` — the idle swift-testing runner finding nothing. | The same test sources are compiled by two harnesses: `swift test` in a `swift:6.0-noble` Linux container (`.github/workflows/core-tests.yml`) and the Xcode iOS bundle. One framework keeps a single reconcilable `Executed N tests` total and makes `grep -cE '^\s*func test'` an exact count — which is how the counts in this document were measured. | Do not add `import Testing` to one file "for the new tests". You split the runner output into two totals and desynchronise the Linux and Mac counts that `08_TESTING.md` pins. |
| **Dependency injection** | `swift/patterns.md`: "Inject protocols with default parameters — production uses defaults, tests inject mocks." | Four `.shared` singletons — `ProfileStore.swift:10`, `AccountService.swift:8`, `IAPManager.swift:26`, `GameCenterService.swift:9` — referenced **directly** inside SwiftUI `body`. | Iron rule G3: `@Observable` tracking only registers when the observable is read during `body`. Routing a store through an injected `any Protocol` existential severs observation — the same failure `AnyView` caused at `MenuView.swift:20-23` ("Head Start does nothing"). Testability is preserved by a *different* seam: `ProfileStore(testing:)` (`ProfileStore.swift:25-29`), with zero `.shared` uses under `Tests/`. | Do not introduce `protocol ProfileStoring` and inject it. You reintroduce the v1.0 observation-bug class in exchange for a mock the tests do not need. |
| **Value types / immutability** | `common/coding-style.md`: "ALWAYS create new objects, NEVER mutate"; `swift/coding-style.md`: "prefer `let`… use `struct` by default, `class` only when identity is needed." | `GameCore` is an `@Observable @MainActor final class` (`Core/GameCore.swift:22-23`) with ~40 mutable stored properties and three mutable entity arrays, mutated in place 120×/s. | The tick runs at a fixed 1/120 s with an accumulator; copy-on-write of that state every tick is exactly the allocation churn the frame budget cannot absorb. Immutability is enforced **at the seam instead**: the core publishes an immutable `GameSnapshot` value once per frame (§2), so every downstream layer is value-typed and `Sendable`. | Do not convert `GameCore` to a struct or make its fields `let`. The immutability guarantee that matters is the snapshot, and it already holds. |
| **Concurrency model** | `swift/patterns.md`: "Use **actors** for shared mutable state instead of locks or queues"; `swift/coding-style.md`: prefer structured concurrency. | `GameCore` and `Autopilot` are `@MainActor` classes (`GameCore.swift:22`, `Autopilot.swift:9`), not actors. The whole frame loop runs inside `MainActor.assumeIsolated` in RealityKit's `SceneEvents.Update` handler (`GameView.swift:256`). Strict concurrency is `complete`, and there is no `Task.detached`, no `DispatchQueue`, no `@unchecked Sendable` in the repo. | The tick's only consumers — the RealityKit renderer and SwiftUI — are already MainActor. An `actor` core would make `sync(snapshot)` an `await` inside the render callback and put the load-bearing tick order (§3) at the mercy of actor reentrancy. Cost, accepted: the SPM suite must assert on the main actor. | Do not refactor `GameCore` into an `actor`. Do add new non-isolated callbacks with `Task { @MainActor }` (`AccountService.swift:41-43`) rather than a new `assumeIsolated`. |
| **Third-party libraries** | `common/development-workflow.md` step 0: search GitHub and package registries first; "Prefer battle-tested libraries over hand-rolled solutions." | `Package.swift` declares **zero** package dependencies; `project.yml` has no SPM/Pods section. Meshes are built with `MeshDescriptor`, audio is DSP in `Audio/Synth.swift`, the app icon is rendered by `Tools/gen_icon.swift`. | It is a stated product constraint (project `CLAUDE.md`, iron rule 6) and it is what makes the Linux CI job possible at all — a `swift:6.0-noble` container can resolve nothing Apple-flavoured. Zero binary assets is the same constraint applied to data. | Do not add SnapKit / Lottie / Firebase / swift-collections / a snapshot-testing library. One dependency ends both "zero deps" and the container CI job. |
| **Formatter / linter** | `swift/coding-style.md`: "**SwiftFormat** for auto-formatting, **SwiftLint** for style enforcement"; `swift/hooks.md` proposes PostToolUse lint hooks. | No `.swiftlint.yml`, no `.swiftformat`, no lint or format step in either workflow (`core-tests.yml`, `ios-build.yml`). | The gates this repo actually enforces are behavioural: the 200-seed solvability soak and the `layoutVersion` goldens (§4). A one-shot reflow of the 17,998 lines under `PrismRush/` (21,734 with tests) would invalidate every `file:line` citation in this document and in `docs/agent/*`, which is the navigation layer future sessions depend on. | Do not run `swiftformat .` or add a lint hook that rewrites files. If you want style enforcement, propose it as its own commit with the doc re-anchoring budgeted in. |
| **Logging** | `swift/hooks.md`: "Flag `print()` statements — use `os.Logger` or structured logging instead." | **Zero** `print(`, zero `OSLog`/`Logger`, zero `fatalError`, zero `assertionFailure`, zero `try!` in all 70 files under `PrismRush/`. Only `Tools/*.swift` prints (5 sites). | The rule's target does not exist — there is nothing to migrate. And `os` is Darwin-only: importing `os.Logger` into anything `Package.swift` lists (`Core/`, 7 `Meta/` files, `Audio/Synth.swift`) breaks the Linux job and violates iron rule 1's Foundation-only constraint on `Core/`. | Do not add logging "for compliance". The real cost is silent *failures* (e.g. `try? await GKLeaderboard.submitScore`, `GameCenterService.swift:40,50`) — add diagnostics only at the specific sites the backlog names, and never inside a Linux-compiled file. |
| **Secrets storage** | `swift/security.md`: "Use **Keychain Services** for sensitive data — never `UserDefaults`." | The Apple user id *is* in the Keychain (`Services/Keychain.swift`). The profile — coins, `purchasedWorlds`, `ownedSkins`, `doubleCoins` — is an unsigned JSON blob in `UserDefaults` key `pr.profile.v1` (`ProfileStore.swift:622`), mirrored verbatim into `NSUbiquitousKeyValueStore` (`:624`). | The rule's subject is credentials, and those are in the Keychain. The profile cannot be: Keychain items do not sync through `NSUbiquitousKeyValueStore`, so moving it there would delete cross-device saves — the whole point of the store. | Do not move the profile to the Keychain. The client-side cheat surface is a real, tracked concern; the answer is signing/validation on the existing store, not a location change that breaks sync. |
| **File size ceiling** | `common/coding-style.md`: "200-400 lines typical, **800 max**." | Four files exceed it: `UI/GameView.swift` 1,224 · `Render/Reality/RealityRenderer.swift` 1,106 · `Render/Reality/WorldDecor.swift` 848 · `UI/ShopView.swift` 822. | `GameView.swift` holds `GameModel` — the app's single hub — plus the one frame loop and the whole ZStack router; splitting it moves `@Observable` ownership across files without reducing coupling, and G3 makes that specific move risky. `RealityRenderer.swift` is the single implementation of `RendererPort`; the seam is the protocol, not the file. **This is the weakest-justified divergence in the table** — `WorldDecor` and `ShopView` are ordinary long files. | Do not split `GameView.swift` because 1,224 > 800. Split it only for a behavioural reason, and never move `@State`/`@Observable` ownership across the new boundary. |
| **Coverage gate** | `common/testing.md`: "Minimum Test Coverage: 80%", enforced. | `gatherCoverageData: true` on the scheme (`project.yml:77`) and **nothing reads the report**. Zero coverage on `Render/`, `UI/`, `IAP/`, `Services/`, and on `ProfileStore`'s persistence + iCloud merge paths. | The suite is deliberately weighted to the deterministic layers, where a numeric gate is meaningful; a percentage gate over SwiftUI view bodies and a RealityKit renderer would be satisfied by assertions that prove nothing. The real gates are the bot soak and the goldens. | Do not add a coverage threshold to CI, and do not write view-body tests to chase a number. Cover the uncovered *behaviour* the backlog names (persistence, merge, IAP grant paths) instead. |

---

## 11. Where to look first

One row per task. Read these files; the rule column is what will bite you if you skip it.

| Task | Files | The rule that bites |
|---|---|---|
| **Changing spawn behaviour, patterns, or the difficulty ramp** | `Core/Spawner.swift` · `Core/Patterns.swift` · `Core/Tuning.swift` · `Core/GameCore.swift` (tick order, §3) | Iron rules 3 + 4. Keep `SolvabilityBotTests` green (200 seeds × 6,000 m **and** 64 × 12,000 m) **and** bump `DailyChallenge.layoutVersion` + repin the `DailyChallengeTests` goldens — a v8 pin is already armed (§4). Pattern order is prefix-index gated; moving walls stay LAST. One extra `rng.unit()` anywhere in the spawn path changes every seeded run. |
| **Touching the economy — coins, XP, prices, missions** | `Meta/ProfileStore.swift` · `Meta/XPCurve.swift` · `Meta/ShopValue.swift` · `Meta/MissionCatalog.swift` · `UI/GameView.swift:680-792` (`recordRunResults`) | Iron rule 9: payouts are per-death deltas `max(0, cumulative − awarded)`, `applyRunSummary` runs once per run, all reward timestamps clamp against clock rollback. Tests to keep green: `EconomyTests` (30), `ProgressionTests` (15), `MissionsTests` (18), `ShopValueTests` (15). |
| **Adding a `Profile` field** | `Meta/Profile.swift` (`init(from:)`) · `Meta/ProfileStore.swift:657-689` (`merged`) | Iron rule 7: `decodeIfPresent ?? default`, and the field needs a default. Decide its merge policy in the same edit — `merged()` starts from `var merged = local`, so an unnamed field means "local silently wins". If it is a collection, bound it: the KVS value cap is 1 MB. |
| **Changing input feel** | `UI/GameView.swift:893-911` (`handleGesture`, the 22 pt tap/swipe split) · `:1058` (the app's only gesture) · `Core/Tuning.swift:20` (`jumpBuffer`) | The gesture is `onEnded` — it fires on finger *lift*. Latency complaints start here, not in `Core`. `GameCore.jump/slide/changeLane` are the only entry points the sim exposes. |
| **Adding a skin or character** | `Meta/SkinCatalog.swift` · `Meta/SkinUnlocks.swift` · `Render/Reality/RealityRenderer.swift:701` (`applySkin`) · `UI/CharacterSwatch.swift` · `UI/CharacterSelectView.swift` · `Tests/CoreTests/SkinCatalogTests.swift` + `CharacterParityTests.swift` | Decree 1 (identity never follows the world — no `followsWorld` on any skin) and decree 2 (menu hero, swatch, shop card and tease must match in-game). `SkinCatalog.skin(_:)` silently returns Prism for an unknown id. `CharacterParityTests` is UIKit-gated — it only runs in the Xcode bundle, never under `swift test`. |
| **Adding or restyling a world** | `UI/Theme.swift` (`worlds`, `evolvedPalette`) · `UI/WorldPreviewCanvas.swift` (add an explicit `case`) · `Render/Reality/WorldDecor.swift` + the `*Sky.swift` family · `Meta/XPCurve.swift` (`worldPrice`) · `Tests/WorldPaletteTests.swift` | `Theme.worlds.count` is the divisor for **both** the family index and the cycle. `WorldPreviewCanvas`'s `default` arm falls back to `worldIndex % 3`, so a new world without a `case` gets the wrong skyline. `WorldDecor` suppresses side silhouettes for folded index ≥ 3. |
| **Touching audio** | `Audio/Synth.swift` (pure DSP) · `Audio/SynthEngine.swift` (AVAudioEngine, cache, ducking, interruption recovery) · `Audio/Music.swift` · `Tests/CoreTests/SynthTests.swift` (10) | `Synth.swift` is listed in `Package.swift` → Foundation only, no AVFoundation, no `os`. Music is pinned to world 0 (`SynthEngine.swift:133`) by owner decree — the per-world tests prove nothing about what a player hears. `.playback` session category is intentional (`:86`). |
| **Touching the renderer** | `Render/RendererPort.swift` (the seam, §2) · `Render/Reality/RealityRenderer.swift` · `EntityPools.swift` · `ProceduralMesh.swift` | Iron rules 1 + 6: `Core/` never learns about the renderer, and there are no binary assets — meshes via `MeshDescriptor`, `UnlitMaterial` only. Linux compiles none of this, so a Mac build (`./Tools/build.sh`) is the only signal a change is even syntactically live. |
| **Any UI or SwiftUI-state change** | `UI/GameView.swift` (`GameModel`, the hub) · the screen's own file · `UI/Theme.swift` | Iron rule G3: never `@State` a shared `@Observable`, never snapshot `store.profile` into a `let` at the top of `body`. Reference `ProfileStore.shared` / `IAPManager.shared` directly in `body`. This anti-pattern shipped three v1.0 bugs. |
| **Concurrency or isolation work** | `Services/AccountService.swift:41-43` (the correct hop) · the nine `assumeIsolated` sites listed in §9 | Iron rule 8, Swift 6 strict `complete`. Wrap main-delivered non-isolated callbacks in `MainActor.assumeIsolated` only when the delivery queue is `.main` by construction; otherwise hop with `Task { @MainActor }`. Do not introduce `Task.detached`, `DispatchQueue`, or `@unchecked Sendable` — the repo currently has none. |
| **Build config, entitlements, capabilities, bundle id, version** | `project.yml` **only** | `*.xcodeproj` and `PrismRush/Support/PrismRush.entitlements` are both regenerated by `xcodegen`. Then run `./Tools/build.sh`. For a codesigned device build or archive, pass `-derivedDataPath` outside this iCloud-synced tree. |
| **A compliance / App Store question** | `docs/agent/06_COMPLIANCE.md` · `docs/SHIP_CHECKLIST.md` · `docs/APP_STORE_SETUP.md` · `PrismRush/Support/PrivacyInfo.xcprivacy` · `Products.storekit` · `project.yml` | Decree 5 (zero ads, no dark patterns, advertised bonuses always delivered) and decree 3 (pre-launch store / empty leaderboard states must look intentional, never like an error). Ships as `MARKETING_VERSION 1.0` despite the v1.6 internal label — `SHIP_CHECKLIST.md`'s "v1.2 overhaul" header is stale, its substance is not. |
| **Verifying anything before you claim it** | `./Tools/ci.sh` (generate + build + full suite) · `swift test -c release` (178 tests, deterministic layers only) · `./Tools/qa.sh` · `./Tools/screenshots.sh` | The SPM suite does not compile `UI/`, `Render/`, the audio engine, StoreKit or GameKit — at best `swiftc -parse`. Any UI/Render/engine change is unverified until a Mac build runs. Never drive the simulator while `xcodebuild test` is using it. |
