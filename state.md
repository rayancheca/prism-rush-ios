# PRISM RUSH — Build State

> Single source of truth for session resumability. On any fresh session: read this first, then continue.
> Last updated: end of **v1.4 (worlds + tease + missions board)**.

## v1.4 — worlds, purchasable ladder, roster 24, missions board (2026-06-11)
| Commit | Scope |
|---|---|
| `9b77316` | Meta: `purchasedWorlds` (decode-defaulted, formUnion merge), `unlockWorld` (never touches `maxWorldReached`), `XPCurve.worldPrice` ladder (400…13,400; 59,400 sink), roster 16→24 (xpUnlockLevels now [3,6,8,12,18,25]) |
| `44673e2` | `WorldSky` (in WorldDecor.swift): per-family sky identity — Sands ringed planets + sun halo + dunes, Metropolis layered skyline + blinking windows + blimps + searchlights, Caverns stalactites + rotating crystals + aurora. Pooled, RM-gated, decor-stream seeded. `PR_WORLD` debug env |
| `ee8ce90` | Worlds tab: full 12-rung ladder, NEXT UNLOCK strip, locked cards w/ price pills, UnlockPanel buy flow (denied shake + GET COINS→Shop), ∞ end-cap; WorldPreviewCanvas per-world signatures |
| `985859b` | Locked-skin tease (full color @0.45 opacity, animated), select @24 w/ rarity counts + NEXT UNLOCK spotlight; missions board overhaul (summary strip, ring cards, section identities, claim FX, CLAIM ALL stagger) |
| `1a10908` | Fixer: **B1 purchased-world reach-credit exploit** (GameView `reachAtRunStart` gate + pinned test), B2 G3 grep regression, WorldSky fed `snapshot.worldOrdinal` (cycle richening was dead code), coin fly-up fix, Dynamic Type tokens, 2 permanent XCUITests (buy flow, mission claim) |

**Test status: 142/142** (132 unit + 10 XCUITest) via `./Tools/ci.sh`. Evidence: `reports/shots/v14/`.
Demo profile (PR_DEMOPROFILE) now pins exact values incl. achievement seeds — sim/screenshot only.

## Current phase
**v1.3 CONTENT UPDATE COMPLETE.** Implemented per the binding contract
`reports/design/V13_SPEC.md` (where it disagrees with the four DESIGN_*.md docs, the spec wins).
What remains is the App Store ops track (unchanged — see §B below and `docs/SHIP_CHECKLIST.md`).

### v1.3 — what shipped (waves 1–5, serialized, disjoint file ownership)
| Wave | Commit | Scope |
|---|---|---|
| 1 core | `cb94f7c` | Ballistic gem arc (7/7 collectible), Prism Rings, Overdrive Pads, Flow Surge, 5-tier pacing + anti-repeat reroll, `streakPerMult` 6→5, `layoutVersion` 1→2 (one bump covers all of v1.3 — R15) |
| 2 meta | `bb1779c` | `XPCurve` levels 1–30 + banded coin grants (`LevelUpResult`), 16-skin roster (`SkinCatalog` v2 + `SkinUnlocks`), weekly missions (3 slots/UTC week), challenge local tiers (R16), 6 new Profile fields (all `decodeIfPresent ?? default`), cloud-merge rules |
| 3 render | `f751a5d` | `applySkin(_ skin: Skin)` rig rebuild (shape/scale/eyes/pupils/antenna/sway), skin-tinted trail/dust/landing/shatter, pooled ring torus + boost chevron, boost FOV punch, flow aura/cascade |
| 4 ui/audio | `4a73d95` + `4d68b83` | Theme tokens (Role/TypeScale/Space/Radius), menu Hero/Verb/Rail/Nav reframe, `AnimatedCharacterSwatch`/`CharacterHeroStage`, stage-and-shelf Characters, Shop 4 sections, Worlds previews + per-world best, HUD diet (flow pips, boost ring, ghost chip), GameOver 3 bands + XP bar, weekly board + CLAIM ALL, six DSP SFX (R17) |
| 5 wiring | this commit | GameView glue: style-coins 4th per-death delta, `summary.startWorld`, `lastLevelUp` model state (G3), challenge payout capture, `applySkin(Skin)` + ownership guard, `refreshSkinUnlocks` at install/post-run/post-challenge/sheet-close with NEW CHARACTER popups, FX→haptics map (R17), six-SFX wiring, pruned MenuView/GameOverView call sites, XCUITest refresh (+2 flows) |

### v1.3 post-review fixer pass (after the 5 adversarial reviews of waves 1–5)
All 3 BLOCKERs + actionable WARNs addressed in one commit on top of `7f3e4f1`:
- **PR_DEMOPROFILE determinism (blocker):** demo profile now pins `totalXP = 0`,
  `xpLevelRewarded = 1`, strips all auto-grant skins and zeroes their metrics
  (`ach.dist`/`ach.close` tiers, `challengeDaysPlayed`) — `testHeroStageShowsLockedRequirement`
  can no longer be poisoned by XP banked into the sim profile by earlier autoplay/CI cycles.
- **Milestone popup queue (blocker):** LEVEL UP / NEW CHARACTER popups (same anchor, often born
  in the same call at L3/L6/L12/L25) now release one per 1.0 s beat with their chime + haptic.
- **flowStreak matches §C.1 verbatim:** resets to 0 at every surge (cadence unchanged — FlowTests
  re-pinned; HUD pips `% flowPerSurge` render identically; renderer never read it).
- buyOrEquipSkin hard-gates non-`.coins`/`.free` unlocks (kills the 0-coin backdoor for
  level/achievement/challenge skins); R14 loop skips non-positive `into` values.
- Shop rail/featured cards focus CharacterSelect on the tapped skin (`initialFocus`, uiux §4.1);
  challengeDays close-task is tracked/cancellable; LockedWorldCard shake is Reduce Motion-gated;
  death-panel sheet gate widened to every sheet (in-sheet routes to Settings/Missions/Worlds no
  longer vanish the stack); V13_SPEC §C.4 amended with the shipped extra params.
- **QA note:** the dev/QA sim + device profiles ran checkpoint summaries before
  `summary.startWorld` landed — wipe the QA profile before the device "BEST HERE" pass so
  corrupted per-world bests can't survive into ship verification.

### v1.3 test status
- `swift test -c release` (SPM, Linux-provable): wave-1/2 suites green (incl. 200-seed × 6,000 m bot
  + 12,000 m deep soak with ZERO `Autopilot.swift` diffs; layoutVersion-2 goldens re-pinned).
- Mac `xcodebuild test` (full gate `./Tools/ci.sh`): **137/137 green** — 129 unit + 8 XCUITest
  (iPhone 17 Pro · iOS 26.5 sim). v1.2 was 95 (89 + 6); v1.3 adds 40 unit + 2 XCUITest
  (the spec's §T "≈121" was an estimate — waves 1–2 landed more pins than budgeted).

### v1.3 economy invariants (re-verified this wave — iron rule 9)
- `applyRunSummary` exactly once per run (GameView `statsRecorded` guard); its `LevelUpResult` is
  captured as **model state** (`lastLevelUp`), never re-derived from the live store (G3).
- All FOUR coin components are per-death deltas (`max(0, cumulative − awarded)`): gems & bonuses
  (rings/boost/fountains pay through `gemCount`), distance, worlds, and the new STYLE line
  (`XPCurve.styleCoins` vs `styleCoinsAwarded` watermark). New-best fanfare once per run.
- Challenge runs still can never revive/checkpoint; checkpoint runs still skip GC submission.

### v1.3 device QA checklist (manual feel pass — needs the operator + a device)
Filed as remaining (automated equivalents are covered by the suite + autoplay):
Bolt trail end-to-end · Prism crossfade regression · Eclipse readability on Caverns (§P parking-lot
candidate `0x232337` lighten) · Reduce Motion statics · Pebble vs Eclipse silhouettes · 7/7 arc by
feel · ring PERFECT timing · overdrive runway feel · flow surge cadence · level-up burst · weekly
board rollover · challenge tier toast.

---

## v1.2 phase notes (superseded by v1.3 above)
Base game (Phases 0–6) + F2P expansion (E1–E6) + the v1.1 critique rounds shipped earlier; the
v1.2 multi-agent overhaul landed on top, then the **Mac verification pass** below confirmed it.

### v1.2 overhaul — wave structure (who built what)
| Wave | Scope | Report |
|---|---|---|
| Tooling | Linux SPM test harness (`Package.swift`) + GitHub Actions CI (`.github/workflows/core-tests.yml`); icon/screenshot/ci scripts | `reports/AGENT_tooling.md` |
| Core | Bug sweep (NaN dt guard, revive score leak, shield double-hit, near-miss band), Coin Doubler, Chrono slow-mo, Split Bar (12th pattern), `DailyChallenge` seeds, retuning — 68 core tests | `reports/AGENT_core.md` |
| Render | Decor reset, alloc-free steady state (palette-key material caching), live Reduce Motion, speed lines/skids/crossfade flourish, doubler/hourglass meshes | `reports/AGENT_render.md` |
| Audio | AVAudioSession resilience + recovery, automatic music ducking, 10 new SFX, cached SFX buffers, volume APIs | `reports/AGENT_audio.md` |
| Meta | Economy hardening (clock-exploit clamps, delta payouts), missions/achievements engine + UI, daily-challenge meta, Settings/HowToPlay/Missions views, GameOver overhaul | `reports/AGENT_meta.md` |
| Integration | Wired core↔render↔audio breaking changes, HUD power-up chips, revive-economy P0 fix in GameModel, GC checkpoint gating | `reports/AGENT_integration.md` |
| Wiring | Meta screens, daily challenge entry, settings persistence, tutorial, reduce-flash, missions feed | `reports/AGENT_wiring.md` |
| QA | Adversarial review of the full diff; fixed TIME-tile contract, stale docs/metadata; 500-seed soak clean | `reports/QA.md` |

### Test status
- `swift test -c release` (Linux & Mac, SPM): **89/89 green** (~9 s) — incl. 200-seed × 6,000 m bot,
  10-seed × 12,000 m deep soak, economy/missions/daily-challenge/synth suites.
- Mac `xcodebuild test`: 89 unit + **6 XCUITest** interaction tests = 95 (needs the Mac).
- Every iOS-only file passes `swiftc -parse` on Linux; **none are type-checked** (UIKit/RealityKit/
  SwiftUI unavailable) — hence the Mac pass below.

## Next actions (in order)

### A. Mac verification — RESULTS (session 2026-06-10, Mac pass after the v1.2 merge)
1. **Build**: ✅ `./Tools/build.sh` → BUILD OK **first try, zero errors/warnings**. Every QA-flagged
   Swift 6 risk site (assumeIsolated observers, `.sensoryFeedback`, `symbolEffect`, haptic Task,
   19/10-arg call sites) compiled clean.
2. **Full suite**: ✅ `xcodebuild test` → **95/95 green** (89 unit incl. 200-seed bot + 6 XCUITest),
   iPhone 17 Pro · iOS 26.5 sim.
3. **Sim spot checks (automated subset)**: ✅ 4-min `PR_AUTOPLAY` watch — no crash, no AVAudioEngine
   stalls, no "modifying state during view update"; world crossfades + decor swap, MAG chip clear of
   the corner cluster, SLICK popups. All 8 meta screens captured (`reports/shots/v12/`, commit
   `9814f2e`): menu+daily card, shop (correct "Store unavailable" fallback under bare simctl — the
   .storekit config only applies via the Xcode scheme), characters, missions, settings, profile
   (signed-out GC explainer), worlds, game over (frozen TIME tile 0:06 at the forced 6-s death ✓,
   coin breakdown sums ✓). GameKit/KVS errlog noise = expected for unsigned sim builds.
   **Remaining**: the manual on-device feel/audio/VO items (§F.4) — in progress with Rayan.
4. **Screenshots**: `./Tools/screenshots.sh` (6.9" sim; 6.5" needs a downloaded iPhone 11 Pro Max sim).

### Device build gotcha (2026-06-10)
The repo lives under iCloud-synced `~/Desktop` — the file provider stamps xattrs on build products
and **codesigned builds out of the repo-local `.dd` fail** with "resource fork/detritus not allowed".
Device builds/CLI archives must use `-derivedDataPath` outside the synced tree (used
`/tmp/prismrush-devicedd`; Xcode GUI archive uses `~/Library/...` and is safe). Sim builds in `.dd`
are unaffected (no codesign). Device install via `devicectl` verified on the iPhone 17 Pro Max
(Developer Mode already enabled).

### B. App Store (after A is green) — full copy-paste detail in `docs/SHIP_CHECKLIST.md`
1. ASC app record (`com.rayancheca.prismrush`, name "Prism Rush" — check availability).
2. 5 IAP products from `Products.storekit` (exact table in the checklist).
3. Game Center: classic `prismrush.best` + **recurring** `prismrush.daily` (daily reset, UTC).
4. Capabilities sanity (auto-managed on first signed build; Team ID already in `project.yml`).
5. App Privacy questionnaire (answers in `Store/metadata.md` §7).
6. Archive + upload.

### Known accepted trade-offs (QA flags — do not "fix" casually)
- Backward-clock daily-mission farming (~300–400 coins/day of clock fiddling) — accepted; closing it
  needs per-day claim bookkeeping. Forward-clock is fully blocked.
- Mid-run Double Coins purchase retroactively doubles the current run's already-paid components —
  one-shot, player-favoring, bounded.
- Post-revive tail isn't folded into missions (`.revives` metric always 0 at first death) — fine
  until a revive mission ships.

---

## History — F2P expansion plan & progress (post-base-game)
- [x] **E1 Slide animation** — `snapshot.sliding/grounded`; renderer does a forward-lean pancake + ground
      dust. Screenshot-verified (was indistinguishable before).
- [x] **E2 Economy foundation** — `Meta/`: `Profile` (Codable: coins/stats/unlocks/skins/progression/IAP),
      `ProfileStore` (@Observable, UserDefaults + iCloud KVS sync), `SkinCatalog` (7 procedural skins).
      Coins earned at run end (gems + distance/50, ×2 if doubleCoins), shown on game-over + menu, persisted
      across launches (verified). Best score migrated into the profile. Renderer applies the selected skin.
- [x] **E3** — menu hub (PLAY + Characters/Shop/Worlds nav) + Character-select grid (procedural skin
      previews, buy/equip with coins, equipped state). `MetaScreenScaffold`/`CoinBadge`/`CharacterSwatch`
      shared chrome. `PR_SCREEN` debug flag opens a sheet for screenshots. Both screenshot-verified.
- [x] **E4** — Shop + StoreKit 2 IAP. `IAP/`: `IAPCatalog` (5 products → coins/doubleCoins/skin grants),
      `IAPManager` (@Observable: load products, verified purchase, grant→ProfileStore, restore entitlements,
      `Transaction.updates` listener). `ShopView` grid (real `displayPrice` when loaded, else fallback).
      `Products.storekit` local config wired into the scheme (`storeKitConfiguration`) so purchases work
      from Xcode/sim. Screenshot-verified. REAL purchases need ASC products + IAP capability (human gate).
- [x] **E5a** — Level select / checkpoint start: `GameCore.startRun(startDistance:)` begins at a reached
      world's difficulty/palette while `scoreOffset` keeps score & coins counting from zero. `LevelSelectView`
      grid (per-world color, "Nm in", furthest highlighted). `PR_DEMOPROFILE` debug seeds progression for
      screenshots. Verified (7 worlds shown).
- [x] **E5b** — DONE in v1.2: Coin Doubler pickup (gems pay 2× coins for 10 s) + permanent
      Double Coins IAP multiplies the run payout (`reports/AGENT_core.md` §A).
- [x] **E6** — Accounts. `GameCenterService` (lazy auth, submit best to `prismrush.best`, present friends
      leaderboard). `AccountService` (Sign in with Apple → stable user id, stored locally). `ProfileView`:
      Sign in with Apple button + lifetime stats grid + Friends Leaderboard + Restore Purchases. Profile
      button added to the menu. GC auth on launch; best submitted on death. Screenshot-verified.
      HUMAN GATES: enable Sign in with Apple + Game Center capabilities; create leaderboard `prismrush.best`.
- [~] **E7** — Chrono slow-mo power-up DONE in v1.2; privacy answers documented
      (`Store/metadata.md` §7); final ship prep = `docs/SHIP_CHECKLIST.md`.

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

## (Superseded) Phase 7/8 plan — replaced by "Next actions" at the top
The old soak/ship plan is folded into `docs/SHIP_CHECKLIST.md`. The 500-seed QA soak (0 deaths,
0 stalls) covered the simulation side; icon/screenshots/archive are steps in the checklist.

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
- **(v1.2) Leaderboards = `prismrush.best` (classic, per-run, checkpoint runs never submitted) +
  `prismrush.daily` (RECURRING, daily reset UTC; context = UTC days-since-epoch).** Submitting per-run
  scores (not `profile.bestScore`) keeps checkpoint-earned bests off the board.
- **(v1.2) `DailyChallenge.layoutVersion` (now 2 — bumped once for all of v1.3, R15) MUST be bumped
  whenever spawner/pattern/RNG-consumption changes** — goldens pinned in `DailyChallengeTests`;
  same-day players must see the same track within a layout version.
- **(v1.3) `V13_SPEC.md` is the binding contract** for the v1.3 surface (R-decisions, §C symbol
  names, §W file ownership). Legacy shims it parks (3-arg `applySkin`, defaulted MenuView params,
  `DailyChallengeCard` absorption) are deleted in v1.4 (R13/§P parking lot).
- **(v1.3) Mission-claim character grants land on sheet close**: MissionsView claims straight on
  `ProfileStore` (G3), so `GameModel.closeSheet()` runs `refreshSkinUnlocks` — Drift/Wisp pop on
  the way back to the hub. Run/challenge grants land in `recordRunResults`; launch catch-up in
  `install()`.
- **(v1.2) Revive economy = per-death deltas** (`max(0, cumulative − awarded)` per component);
  `applyRunSummary` exactly once per run (first death); challenge runs can never revive or checkpoint.
- **(v1.2) Pattern order matters**: split bar is index 10, moving walls stay LAST (index 11) — the
  spawner gates by prefix, so reordering changes difficulty gating.
- **(v1.2) `Profile` decodes every field `decodeIfPresent ?? default`** — schema changes never wipe
  an existing save (pinned by EconomyTests decode tests).

## Blockers
- None.

## HUMAN GATES (do not fake — for the operator; full detail in `docs/SHIP_CHECKLIST.md`)
- [x] Apple Developer **Team ID** → `project.yml` `DEVELOPMENT_TEAM` — **DONE** (`8M64JJQQAU`, commit `ba45711`).
- [ ] Capabilities on the App ID: In-App Purchase, Sign in with Apple, Game Center, iCloud KV
      (Xcode auto-manage handles most on the first signed build; entitlements already in the repo).
- [ ] App Store Connect app record (`com.rayancheca.prismrush`) + name-availability check for **"Prism Rush"**.
- [ ] Game Center leaderboards: classic **`prismrush.best`** AND **recurring `prismrush.daily`**
      (daily reset, UTC — ranks the shared-seed daily challenge; without it challenge submissions
      silently no-op).
- [ ] 5 IAP products from `Products.storekit` created in ASC.
- [ ] App Privacy questionnaire (NOT "Data Not Collected" — see `Store/metadata.md` §7).
- [ ] The actual signed upload.

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
