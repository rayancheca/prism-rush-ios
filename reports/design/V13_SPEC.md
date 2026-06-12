# PRISM RUSH v1.3 — IMPLEMENTATION CONTRACT (V13_SPEC.md)

Status: BINDING. Synthesized 2026-06-10 from DESIGN_characters.md, DESIGN_mechanics.md,
DESIGN_uiux.md, DESIGN_progression.md, verified against source (v1.2, 95/95 green).
Where this spec disagrees with a design doc, **this spec wins**. Implementers must never
invent an API name — every cross-wave symbol is in §C (Contracts Appendix).

Build reality: one Mac, serialized waves 1→5. Waves 1–2 are Linux-verifiable
(`swift test -c release`); waves 3–5 need `./Tools/build.sh` / `./Tools/ci.sh`.

---

## R. RECONCILIATION DECISIONS (conflicts found and settled)

> ### ⚠️ DECREE-1 REVOCATION (owner decree; dated 2026-06-11, code shipped v1.4.2 `7349a19`)
>
> The owner decrees in `CLAUDE.md` §Owner decrees **OVERRIDE this spec** wherever they conflict.
> Decree 1: *"A character NEVER changes identity with the world — including the default."*
> This **revokes** the "Prism = chameleon / sole `followsWorld`" decision that this spec pinned in
> six places (§S item 2, §W wave-2/3 DONE gates, §C.2 sentinel + computed, §C.3 shim, §T test row).
> What shipped instead (v1.4.2):
> - **No skin ever follows the world palette.** `Skin.followsWorld` and the `bodyHex 0` sentinel
>   are DELETED. Prism owns authored hexes — body `0x00F5FF`, antenna `0xFF2BD6` — plus
>   `isPrismatic: Bool` (exactly one: `default`).
> - Prism's identity is a **fixed, time-based prismatic shimmer** —
>   `SkinCatalog.prismaticColor(at:)`, a pure 8 s cycle through authored cyan→magenta→amber stops,
>   identical in every world; phase 0 = `bodyHex` (the static Reduce Motion look). Menu previews
>   and the in-run body sample the same clock, so they agree at any instant (decree 2).
> - `trailHex == nil` is **REPURPOSED**: it now means "ride the shimmer hue" (Prism only) — never
>   "follow the world accent". All renderer FX fallbacks to the world palette were deleted;
>   `skinTrailColor` is non-optional.
> - The legacy 3-arg `applySkin(bodyHex:antennaHex:followsWorld:)` shim is DELETED (v1.4.2 —
>   it outlived its planned v1.4 deletion; see R13 note below).
>
> Affected R/S/W/C/T lines below are **struck through or annotated in place — never silently
> rewritten** — so future readers can see the correction happened. The non-decree staleness
> (roster 16 → 24, `xpUnlockLevels`) is corrected by the **V1.4 AMENDMENTS** block that follows.

> ### V1.4 AMENDMENTS (roster expansion shipped `9b77316`; tests assert the new truth)
>
> - **R1 amended:** `XPCurve.xpUnlockLevels = [3, 6, 8, 12, 18, 25]` — six XP-locked characters:
>   Pebble L3, Blossom L6, **Circuit L8**, Shard L12, **Nebula L18**, Eclipse L25.
> - **§C.2 amended:** `SkinCatalog.all` = **24 entries** — the 16 legacy skins frozen
>   (ids/hexes/costs pinned; sole exception: Prism's revoked sentinel, above) plus the v1.4 eight
>   on the §S parking-lot rungs: Tide 2,000 / Thorn 3,500 / Golem 5,000 / Monarch 7,500 coins,
>   Circuit L8 / Nebula L18, Facet `ach.gems` tier 2, Vigil 14 challenge days.
> - **§T amended:** SkinCatalogTests now pins: 24 unique; legacy 16 frozen; zero world-following
>   skins (`bodyHex != 0` for all); exactly one `isPrismatic` (`default`); `trailHex == nil` for
>   exactly `["default"]` (= shimmer source); `xpUnlockLevels == [3, 6, 8, 12, 18, 25]`;
>   `prismaticColor` purity/8 s-periodicity/authored-stop pins.

**R1 — XP-unlock levels vs roster (characters 3/6/12/25×4 vs progression 3/6/10/15/22×5).**
DECIDED: the 16-character roster from DESIGN_characters §2 is canonical — **4 XP-locked
characters: Pebble L3, Blossom L6, Shard L12, Eclipse L25** *[AMENDED v1.4: roster 24; six
XP-locked — Circuit L8 and Nebula L18 join]*. Progression's 5th XP slot and
its L10/L15/L22 beats are covered instead by the achievement unlocks (Drift = `ach.dist` t1,
Wisp = `ach.close` t1) and Tempo (7 daily-challenge days) — week-1 cadence is preserved with
more *kinds* of unlock, which is better for the owner's "everything leads somewhere" goal.
Single source of truth: ~~`XPCurve.xpUnlockLevels = [3, 6, 12, 25]`~~ **[AMENDED v1.4 — now
`[3, 6, 8, 12, 18, 25]`, see the V1.4 AMENDMENTS block above]**; `SkinCatalogTests` asserts
the catalog's `.level(n)` skins match this array exactly.

**R2 — XP unlocks persisted vs derived.** Progression said "derived, never persisted";
characters said auto-grant into `ownedSkins`. DECIDED: **auto-grant into `ownedSkins` via
`ProfileStore.refreshSkinUnlocks(level:)`** (characters doc wins). `SkinUnlocks.earned` is the
truth function; insertion into `ownedSkins` is the grant cache + the once-ever "NEW CHARACTER"
toast dedupe; cloud `formUnion` is monotonic and already exists. No derived/owned dual path.

**R3 — Double-gating coin skins (uiux §6.2: ember L2 … midas L12 level locks).** CUT.
One unlock axis per skin — the `Skin.Unlock` enum. The legacy 7 keep exact ids, hexes,
and coin costs (pinned by tests). The uiux locked-tile UX applies only to genuinely
locked skins (level/achievement/challengeDays/iap).

**R4 — Coin pricing (characters 200…1,500 ladder vs progression 9 rungs to 7,500).**
DECIDED: legacy five prices frozen (200/350/500/750/1,500); **Bolt = 300** (day-one first
buy); **Fang = 2,500** (was 900 — becomes the week-1 savings goal, absorbing the +25% faucet).
Total coin sink 6,100 + revives. The 3,500/5,000/7,500 rungs are parked to v1.4 roster
expansion (§P). Progression's faucet numbers ship unchanged.

**R5 — Idle preview tech (uiux `CharacterIdleStage` RealityKit stage vs characters Canvas
swatch).** DECIDED: **one component, Canvas-only** — `AnimatedCharacterSwatch`
(TimelineView 30 Hz, DESIGN_characters §4.1). No RealityKit menu stage in v1.3 (perf risk,
and the live game renderer already sits behind the menu). The uiux "CharacterIdleStage" is
realized as `CharacterHeroStage` — a thin wrapper (swatch + procedural glow-disc ellipse +
name pill) in the same new file, used at menu-hero (~swatch 120) and select-hero (96) sizes.

**R6 — Menu buddy chip vs hero stage.** The characters doc's 60 pt "RUNNING AS" chip is CUT —
redundant with the uiux hero stage. The hero stage + name pill IS the buddy
(tap → Characters); "Running as <name>" survives as its VoiceOver label.

**R7 — CharacterSelect: tap-to-equip vs stage-and-shelf.** DECIDED: **uiux stage-and-shelf
wins** (preview-before-commit is the owner's core ask). Hero shows the *focused* skin
(defaults to equipped on open); tapping any card focuses it; commitment happens on the state
button (`EQUIP` / `BUY · 500` / `REACH LEVEL 12` / `GET IN SHOP ›`). The characters doc's
locked-tap routing table (§3.4) applies to the state button + locked-card secondary tap:
coins→buy/shake, iap→`model.open(.shop)`, achievement→`model.open(.missions)`,
challengeDays→close sheet + "Play today's challenge" toast, level→XP-remaining toast.

**R8 — Economy stacking / double-counting.** Ring coins, boost gem bonus, and flow-fountain
gems all flow through Core's `gemCount` (existing currency channel — paid once via the gems
delta line). Style coins are a SEPARATE 4th per-death delta computed in GameView from the pure
helper `XPCurve.styleCoins(closes:slicks:multiplier:)`. Near-miss play double-dips (style
coins + flow fountains) **intentionally** — both capped (40 events/run; `capGem = 72`).
Streak/mult stay gem-pickup-only: ring/boost/fountain coins must NOT bump `streak`.
GameOver's gem breakdown row is relabeled `GEMS & BONUSES`.

**R9 — XP integration point.** `ProfileStore.playerLevel: Int` (computed,
`XPCurve.level(for: profile.totalXP)`) is the ONLY way any consumer reads level.
`applyRunSummary` returns `LevelUpResult`; `unlockedLevels` filters `XPCurve.xpUnlockLevels`.

**R10 — Weekly mission pool.** `wk.chest10` (chestsOpened) is CUT — that metric is not in the
RunSummary→mission pipeline and would need new plumbing. **Weekly pool = the other 7 entries**
from DESIGN_progression §2.2 (gems1k, dist20k, runs30, close75, slick35, slide60, streak25),
all on metrics the daily pool already bumps. 3 slots drawn per UTC week, tag
`0x5745_454B_4C59_3133`.

**R11 — Nav badge-dots.** uiux §1.6's `lastSeenAffordableSkins` profile field is CUT (v1.4).
The Characters nav dot derives from `seenSkins` (any owned-but-unseen skin — free). The Shop
rotation gold dot is CUT (v1.4).

**R12 — `Theme.Type` is an illegal/confusing Swift name.** The uiux type-scale namespace is
**`Theme.TypeScale`** (tokens: display/title/heading/body/caption/micro).

**R13 — Serialized-build compat convention (waves 3–4).** Waves 3 and 4 must NEVER break the
previous waves' call sites: new renderer API is ADDED next to the legacy 3-arg `applySkin`
shim (kept, unused after wave 5, ~~deleted in v1.4~~ **[CORRECTED: the planned v1.4 deletion
never happened — all three D2-6 shims shipped through v1.4/v1.4.1 with stale "still referenced"
comments (AUDIT D2-6). The shim and the legacy `struct CharacterSwatch` were deleted in v1.4.2
`7349a19`; the dead `MenuView` `onSettings`/`onDailyChallenge` params survived that commit too
and were deleted in the v1.4.2 decree-review fix that follows it]**); new view init params get
defaults; views
read `ProfileStore.shared` / `IAPManager.shared` directly in `body` (G3-canonical) instead of
demanding new params from GameView. Wave 5 rewires GameView; dead shims/params are parked.

**R14 — `bestDistanceByWorld`.** Computed inside `applyRunSummary` (wave 2) from
`summary.startWorld`, `summary.distance`, `Tuning.worldLength`: for each world index
`w ∈ startWorld...finalWorld` traversed, `bestDistanceByWorld[w] =
max(existing, min(Tuning.worldLength, startWorld·L + distance − w·L))`. Cloud merge: per-key max.

**R15 — One layoutVersion bump for all of v1.3.** `DailyChallenge.layoutVersion` 1 → 2 lands
in wave 1 and covers: gem-arc rewrite, two new patterns, catalogue reorder, anti-repeat
reroll, pattern-length changes. Waves 2–5 touch ZERO run-RNG paths (meta/UI SplitMix64 uses —
weekly slots, featured rotation, world-decor seeds — are stream-isolated by domain tags and
never feed `startRun(seed:)`).

**R16 — `recordChallengeRun` return.** Becomes `@discardableResult … -> Int` (tier payout,
0 if none) so GameView can toast `CHALLENGE TIER n · +coins`.

**R17 — New SFX set (DSP only).** `Synth.SFX` gains exactly six cases: `ringPass`,
`ringPerfect`, `boostStart`, `boostEnd`, `flowSurge`, `levelUp`. NEW-CHARACTER toast reuses
`purchaseChime`. Haptics (wave 5): ring=light, perfect/boost=medium, flow/level-up=success.

---

## S. SHIPPABLE v1.3 SCOPE (the cut)

**IN (must ship):**
1. P0 gem-arc fix — gems on the ballistic path, 7/7 collectible, speed-aware (mech §1).
2. P0 skin visibility — skin-tinted trail/dust/landing/shatter, per-skin rigs (shape/scale/
   eyes/pupils/antenna), rebuild-on-equip, antenna sway, ~~Prism = sole `followsWorld`~~
   **[REVOKED by decree 1, v1.4.2 — no skin ever follows the world; Prism is prismatic (fixed
   time-based shimmer), authored body `0x00F5FF` / antenna `0xFF2BD6` / trail = shimmer hue]**.
3. Exactly 3 new mechanics: Prism Rings, Overdrive Pads, Flow Surge (+ pacing ladder,
   anti-repeat, `streakPerMult` 6→5). layoutVersion 2.
4. XP/levels 1–30 (`XPCurve`), level coin grants, `LevelUpResult`, GameOver XP bar + level-up
   burst, menu level ring, Profile level card.
5. 16-character roster **[AMENDED v1.4: 24]**, rarity sections, locked silhouettes + requirement
   lines, auto-grant + NEW badges (`seenSkins`), idle previews everywhere
   (`AnimatedCharacterSwatch`).
6. 4 earn loops: level-up grants, weekly missions (3 slots/UTC week), in-run style coins,
   daily-challenge local tiers. Login ladder untouched.
7. UI reframe: menu Hero/Verb/Rail/Nav (5 zones, 14→9 elements), Theme.Role/TypeScale/Space/
   Radius tokens, Worlds tab alive (WorldPreviewCanvas + per-world best + next-locked card),
   Shop 4-section refill (Featured rotation, compact coins, perks, characters rail),
   GameOver 3 bands, HUD diet (ghost-chase chip, merged gem/mult pill, icon timer rings),
   full clickability audit (uiux §5), accessibility contract (uiux §7).

**OUT — v1.4 PARKING LOT:**
- Coin-roster expansion to rungs 3,500/5,000/7,500 (+2–3 new characters) and any faucet
  retune informed by live telemetry.
- `lastSeenAffordableSkins` + Shop-rotation nav badge-dots (R11).
- `wk.chest10` weekly mission + chestsOpened metric plumbing (R10).
- MissionsView per-row `PLAY ›` run-start deep links (cross-sheet run-start plumbing).
- RealityKit hero stage / 3D menu vignette (Canvas swatch ships first; revisit if flat).
- Persisted per-mechanic stats (`bestFlow`, `ringsPassed` in Profile) + ring/flow missions.
- Legacy shim deletion: 3-arg `applySkin`, dead defaulted MenuView params (R13).
  **[Done — but only in v1.4.2, not v1.4 as planned, and in two steps: the shim (+ legacy
  `struct CharacterSwatch`) in `7349a19`, the MenuView params in the decree-review fix after
  it; see the R13 correction.]**
- Eclipse body lighten (only if device QA fails readability on Caverns).
  **[Done v1.4.2 decree-review fix — AUDIT D3-4 promoted this from QA-conditional to shipped,
  at the audit's brighter `0x2A2A4A` (not the `0x232337` parked here); on-device Caverns
  confirmation stays on the state.md device QA checklist.]**
- Shop "GET COINS" toast auto-scroll animation polish; CLAIM ALL stagger tuning.

---

## W. IMPLEMENTATION WAVES — strictly disjoint file ownership

Ownership is EXCLUSIVE: a file listed under a wave may be edited by that wave only, for all
of v1.3. Verification commands are per-wave gates; a wave is not DONE until its gate passes.

### WAVE 1 — CORE (sim mechanics + determinism)

**Owns:** `PrismRush/Core/Models.swift`, `Core/Patterns.swift`, `Core/Spawner.swift`,
`Core/Tuning.swift`, `Core/Collisions.swift`, `Core/GameCore.swift`, `Core/DailyChallenge.swift`
+ `Tests/CoreTests/`: `DailyChallengeTests.swift`, `DifficultyTests.swift`, `RNGTests.swift`,
`SolvabilityBotTests.swift`, `CollisionTests.swift`, `GameplayTests.swift`, `PowerUpTests.swift`,
`SmokeTests.swift`, NEW `ArcCollectionTests.swift`, NEW `RingTests.swift`, NEW
`BoostTests.swift`, NEW `FlowTests.swift`, NEW `PatternOrderTests.swift`.
**Forbidden:** `Core/Autopilot.swift` (zero diffs — the load-bearing property),
`Core/RNG.swift`, `Core/Math.swift`, anything outside Core/ + the listed tests.

Tasks:
1. `Tuning.swift`: add the 24 constants of §C.1 verbatim; retune `streakPerMult = 5`;
   add `midEarlyDiff = 0.18`. Touch NOTHING on the CRITICAL list (jumpV0/gravity, laneX,
   bodyRadius, moving-wall trio, speed ramp, gaps, earlyDistance/midDiff/diffFullAt).
2. `Models.swift`: `EntityKind.{ring, boostPad}`; `SpawnCmd.{ring(d:lane:y:),
   boostPad(d:lane:)}`; `GameSnapshot.{boostRemaining: Double, flowStreak: Int}` (defaults 0
   in `.initial`); `FXEvent.{ringPassed(x:y:perfect:), boostStarted(x:), boostEnded,
   flowSurge(level:x:)}`. All `Sendable`.
3. `Patterns.swift`: replace `gemArc` with the ballistic version (mech §1.2, returns span);
   adjust arc-caller lengths (patterns 1/2/6/9 per mech §1.5); add `ringArc` (idx 9, 1 RNG
   call) and `overdriveRunway` (idx 10, 1 RNG call, 48 units, ZERO obstacles); move gauntlet
   →11, splitBar→12, movingWalls→13 (LAST). `Patterns.count = 14`.
4. `Spawner.swift`: 5-tier `maxIndex` (5/9/11/13/14 per mech §2.4); `lastIdx` anti-repeat
   one-bounded-reroll; reset `lastIdx` with spawner state.
5. `Collisions.swift`: `ringPass(playerCenterY:playerX:ringX:ringY:z:) -> (pass: Bool,
   perfect: Bool)`; boost-pad trigger predicate (grounded, |z|<1.1, |px−padX|<1.1).
6. `GameCore.swift`: `boostT` state + `effectiveSpeed` composition (chrono then boost, cap
   36); ring/pad pickup handling (`activePickups`, never lethal; ring pays
   `bonus += ringScore×mult`, `gemCount += ringCoins/ringPerfectCoins` WITHOUT streak bump);
   boost gem bonus (`+1` gemCount per gem while `boostT > 0`); `flowStreak` increment in
   `.close`/`.slick` branches, reset in `die()` + `shieldAbsorbed`, surge every
   `flowPerSurge`-th (bonus + `.flowSurge` FX + 10-gem fountain via `apply(.gem(...))`,
   lane = `laneIndex`, NO RNG); emit all four FXEvents; snapshot mirrors; reset paths
   (`reset`/`revive` zero `boostT`/`flowStreak`).
7. `DailyChallenge.swift`: default `layoutVersion = 2`.
8. Tests: re-pin DailyChallenge goldens (2026-06-10 v2 = `0x1030_754F_4336_7811`; recompute
   2026-06-11 + 2025-12-31; add explicit `layoutVersion: 3` pin); update DifficultyTests tier
   asserts; re-pin any absolute runHash in RNGTests; new test files per §T wave-1 rows;
   both bot soaks (200×6,000 m + 12,000 m) green with ZERO Autopilot diffs.

**Verify:** `swift test -c release` — all green, `git diff --stat PrismRush/Core/Autopilot.swift`
empty.
**DONE:** suite green incl. soaks; goldens pinned; per-pattern RNG counts pinned
(0–8 unchanged, 9:1, 10:1, 11:1, 12:2, 13:0); no file outside ownership touched.

### WAVE 2 — META (XP, roster, earn loops, persistence)

**Owns:** `PrismRush/Meta/Profile.swift`, `Meta/ProfileStore.swift`, `Meta/SkinCatalog.swift`,
`Meta/MissionCatalog.swift`, NEW `Meta/XPCurve.swift`, NEW `Meta/SkinUnlocks.swift`,
`Package.swift`, `Tests/CoreTests/EconomyTests.swift`, `Tests/CoreTests/MissionsTests.swift`,
NEW `Tests/CoreTests/ProgressionTests.swift`, NEW `Tests/CoreTests/SkinCatalogTests.swift`.

Tasks:
1. `SkinCatalog.swift`: Skin v2 struct exactly per §C.2 (Foundation-only — it is in the SPM
   package) **[§C.2 since amended — decree-1 revocation + 24 entries, see top of §R]**;
   16-entry catalog per DESIGN_characters §2 **with Fang cost 2,500 (R4)**, ordered
   rarity→unlock difficulty; compat computeds `premium`/`cost`; `xpUnlockLevels` lives in
   XPCurve (catalog asserts agreement via tests). Not Codable, never persisted.
2. NEW `Meta/SkinUnlocks.swift`: `earned(_:profile:level:)` + `requirementText(_:)` verbatim
   from DESIGN_characters §3.1 (pure, no UI imports).
3. NEW `Meta/XPCurve.swift`: per §C.3 — formula, cumulative table, `level(for:)`,
   `xpIntoLevel(for:)`, `coinGrant(forLevel:)` (100/250/500/2,000 bands),
   ~~`xpUnlockLevels = [3, 6, 12, 25]`~~ **[AMENDED v1.4: `[3, 6, 8, 12, 18, 25]`]**,
   `styleCoins(closes:slicks:multiplier:)` (= `min(closes+slicks, 40) * 2 * multiplier`).
4. `MissionCatalog.swift`: `RunSummary.startWorld: Int = 0`; `Mission.Scope.weekly`;
   `weeklyPool` (7 entries, R10); weekly slot draw mirroring the daily one with tag
   `0x5745_454B_4C59_3133`.
5. `Profile.swift`: six new fields + CodingKeys + `decodeIfPresent ?? default`:
   `seenSkins: Set<String> = ["default"]`, `totalXP: Int = 0`, `xpLevelRewarded: Int = 1`,
   `weeklyMissionDate: Date? = nil`, `challengeRewardTier: Int = 0`,
   `bestDistanceByWorld: [Int: Double] = [:]`.
6. `ProfileStore.swift`: `playerLevel` computed; `applyRunSummary` → `LevelUpResult`
   (XP add, watermarked banded grants, weekly-pool bumps, `bestDistanceByWorld` update per
   R14 — existing body otherwise unchanged); `refreshWeeklyMissions(now:)` (rollback-clamped
   mirror of daily); `claimMission` `.weekly` case; `unclaimedCount` includes weekly;
   `recordChallengeRun` tier payout + `-> Int` (R16); `refreshSkinUnlocks(level:) -> [Skin]`
   + `markSkinsSeen()`; `sanitized` clamps future `weeklyMissionDate`; `mergeFromCloud`:
   `totalXP`/`xpLevelRewarded` max, `seenSkins` formUnion, `bestDistanceByWorld` per-key max;
   `weeklyMissionDate`/`challengeRewardTier` NOT merged.
7. `Package.swift`: add `Meta/XPCurve.swift`, `Meta/SkinUnlocks.swift` to sources.
8. Tests per §T wave-2 rows; amend EconomyTests/MissionsTests only where the
   `applyRunSummary` return/grants shift expectations.

**Verify:** `swift test -c release` — full Linux suite green (wave-1 + wave-2 tests).
**DONE:** suite green; legacy-JSON decode test passes with all six fields defaulted; pinned
XP thresholds (L2=300, L5=2,100, L10=8,100, L20=31,350, L30=69,600) green; catalog integrity
test (~~16 skins, legacy hex/cost frozen, exactly one followsWorld, one .iap~~ **[AMENDED:
24 skins, legacy frozen, ZERO followsWorld — the computed is deleted; exactly one
`isPrismatic`, one .iap — see the §T amendment at top of §R]**) green.

### WAVE 3 — RENDER (skin identity + mechanic visuals)

**Owns:** `PrismRush/Render/Reality/RealityRenderer.swift`,
`Render/Reality/ProceduralMesh.swift`, `Render/Reality/EntityPools.swift`.
**Forbidden:** `RendererPort.swift` (unchanged), `ParticleSystem.swift`, `WorldDecor.swift`,
all UI/, GameView.

Tasks:
1. `applySkin(_ skin: Skin)` ADDED (legacy 3-arg shim KEPT per R13): stores skin params +
   `skinTrailColor: UIColor?` (nil for Prism), sets `paletteKey = -1`, calls
   `rebuildCharacter()` — sphere/cube/crystal body, eye radius/tint, 4 pupil styles, antenna
   height/tip scales, `skinScale` folded into the per-frame pose (visual-only, 0.85…1.12)
   exactly per DESIGN_characters §1.6.
2. FX tinting: trail (:244), slide dust (:186), landed (:276), died first burst (:299) →
   `skinTrailColor ?? tintAccent(/2)`. Gem ladder, pickup bursts, speed lines, world ring
   UNCHANGED.
3. Antenna sway in `advanceVisuals` (Reduce Motion-gated, per-skin `idle.sway`).
4. Ring rendering: pooled torus (`MeshDescriptor`, reuse magnet-torus generator), emissive
   world-accent, scale-pulse on `.ringPassed` (gold flash on perfect).
5. Boost pad: pooled flat chevron strip (procedural mesh, pulsing scale); `.boostStarted` →
   +6° FOV punch + trail elongation + speed lines while `snapshot.boostRemaining > 0`;
   `.boostEnded` → restore.
6. `.flowSurge` → player aura flash + lane shimmer + sparkle cascade at fountain spawn
   (reuse existing burst API — ParticleSystem untouched).
7. `EntityPools.swift`: pools for `EntityKind.ring` / `.boostPad`
   (`capRing = 4`, `capBoostPad = 2`).

**Verify:** `./Tools/build.sh` clean (legacy GameView call site still compiles via shim);
sim sanity: `SIMCTL_CHILD_PR_AUTOPLAY=1 xcrun simctl launch booted com.rayancheca.prismrush`
shows rings/pads rendering and world-accent trail (skin wiring lands in wave 5).
**DONE:** build green, zero new warnings, all meshes MeshDescriptor (zero binary assets),
~~old `applySkin(bodyHex:antennaHex:followsWorld:)` still present and compiling~~ **[historical
wave-3 gate; the shim was DELETED in v1.4.2 `7349a19` — its parameter name is the
decree-1-banned behavior]**.

### WAVE 4 — UI + AUDIO (reframe, previews, XP surfacing, SFX)

**Owns:** `PrismRush/UI/Theme.swift`, `UI/MenuView.swift`, `UI/CharacterSelectView.swift`,
NEW `UI/CharacterSwatch.swift`, NEW `UI/WorldPreviewCanvas.swift`, `UI/MetaScreenScaffold.swift`,
`UI/ShopView.swift`, `UI/LevelSelectView.swift`, `UI/HUDView.swift`, `UI/GameOverView.swift`,
`UI/MissionsView.swift`, `UI/ProfileView.swift`, `UI/SettingsView.swift`, `UI/HowToPlayView.swift`,
`UI/EffectsOverlay.swift`, `UI/PauseOverlay.swift`, `UI/RewardsBar.swift`,
`UI/DailyChallengeCard.swift` (DELETED — 7-day dot strip moves into GameOverView),
`UI/CoinBadge.swift`, `Audio/Synth.swift`, `Audio/SynthEngine.swift`,
`Tests/CoreTests/SynthTests.swift`.
**Constraint (R13):** every changed view keeps its existing initializer compiling
(new params defaulted, removed params accepted-but-ignored); new data flows in via direct
`ProfileStore.shared` / `IAPManager.shared` reads inside `body` (G3) wherever possible.

Tasks:
1. `Theme.swift`: `Theme.Role` palette, `Theme.TypeScale` (R12), `Theme.Space`,
   `Theme.Radius`, `NeonCard` modifier, gradient law (uiux §2). `WorldPalette` stays.
2. NEW `UI/CharacterSwatch.swift`: `AnimatedCharacterSwatch` (Canvas/TimelineView 30 Hz, bob/
   deterministic blink/sway/shape/pupil/silhouette rules per DESIGN_characters §4.1) +
   `CharacterHeroStage` wrapper (R5). Remove old `CharacterSwatch` from MetaScreenScaffold.
3. `MenuView.swift`: 5-zone reframe per uiux §1 — level-ring avatar (reads
   `ProfileStore.shared.playerLevel` + `XPCurve.xpIntoLevel` in body), tappable CoinBadge→Shop,
   hero stage (`CharacterHeroStage`, tap→Characters), world-progress chip→Worlds, PLAY
   (pulse deleted), best chip→Profile (`FIRST RUN ›`→HowToPlay when best==0), rewards rail,
   demoted nav row. Old params (`onSettings` etc.) kept defaulted/no-op. **[Historical — the
   dead params were deleted in the v1.4.2 decree-review fix (AUDIT D2-6); see the R13
   correction. Do not restore them.]**
4. `RewardsBar.swift`: rebuilt as the 3-cell rail (Daily Rush | Rewards | Missions) with the
   gold priority ladder (one lit cell max) per uiux §1.5; absorbs DailyChallengeCard.
5. `CharacterSelectView.swift`: stage-and-shelf per R7 — hero (`CharacterHeroStage` 96 +
   flavor + state button), rarity-sectioned 3-up grid, locked silhouettes + pinned requirement
   copy, NEW badges (clear via `markSkinsSeen()` onAppear), locked-tap routing, **G3 rewrite
   of line 12** (no `let profile =` snapshot — all reads at point of use).
6. `ShopView.swift`: 4 sections (Featured UTC-day rotation via UI-local SplitMix64, compact
   coin row + BEST VALUE, Perks, Characters rail → CharacterSelect), store-offline degrades
   StoreKit items only (uiux §4).
7. `LevelSelectView.swift` + NEW `UI/WorldPreviewCanvas.swift`: preview header (PLAY FROM
   HERE), world cards with live `WorldPreviewCanvas(palette:worldIndex:size:)` vignettes
   (UI-local SplitMix64 decor seed), `BEST HERE` from `profile.bestDistanceByWorld`, visible
   next-locked card with distance requirement (uiux §3).
8. `HUDView.swift`: hide BEST during play; ghost-chase chip at ≥90% of best; gem count merges
   into mult pill (`◆ 23 ×4`); power timers → icon rings; flow pips (`snapshot.flowStreak %
   flowPerSurge`); boost ring from `snapshot.boostRemaining`. Stays non-interactive.
9. `GameOverView.swift`: 3 bands per uiux §6.7; init gains
   `levelUp: LevelUpResult? = nil, styleCoins: Int = 0, challengePayout: Int = 0`; XP row +
   bar + level-up burst + "NEW CHARACTER UNLOCKED · TAP"→Characters; expandable coin breakdown
   incl. STYLE line + `GEMS & BONUSES` label (R8); Reached/Balance rows deleted; challenge
   7-day dot strip (challenge deaths only); challenge-tier toast line.
10. `MissionsView.swift` (weekly section + CLAIM ALL + tier-tick bars), `ProfileView.swift`
    (level card + settings gear + next-unlock teaser + milestone card <5 runs),
    `SettingsView.swift` (version-copy row), `HowToPlayView.swift` (one new card: rings/pads/
    flow), `PauseOverlay.swift` (session line), `EffectsOverlay.swift` (popup styles for
    RING/PERFECT/OVERDRIVE/FLOW SURGE/LEVEL UP/NEW CHARACTER), `CoinBadge.swift` (tappable).
11. `Audio/Synth.swift` (+ SynthEngine registry if needed): six SFX per R17, pure DSP;
    2 SynthTests additions (buffers non-empty, finite samples).
12. Accessibility per uiux §7: identifiers `heroStage`, `worldProgressChip`, `bestChip`,
    `railDaily`, `railRewards`, `railMissions`, `worldCard_N`, `skinStageButton`,
    `claimAllButton`, `levelCard`, `xpLine`, `versionRow`; Reduce Motion/Flashing tables.

**Verify:** `./Tools/build.sh` clean + `swift test -c release` (SynthTests) green.
**DONE:** build green with the UNTOUCHED GameView call sites; menu/select/shop/worlds render
correctly with v1.2 wiring (level ring, hero stage, rail all live via direct store reads);
no `@State`-captured store anywhere new (grep gate: `let profile = ProfileStore` zero hits
in UI/).

### WAVE 5 — WIRING + QA (GameView glue, haptics, end-to-end)

**Owns:** `PrismRush/UI/GameView.swift`, `Services/Haptics.swift`,
`UITests/InteractionUITests.swift`, `state.md`.

Tasks:
1. `GameView.recordRunResults`: 4th per-death delta `lastCoinsFromStyle` via
   `XPCurve.styleCoins(closes: closesThisRun, slicks: slicksThisRun, multiplier: mult)` minus
   `styleCoinsAwarded` (new @ObservationIgnored vars, reset in `startRun`); set
   `summary.startWorld = runStartWorld`; capture `lastLevelUp =
   ProfileStore.shared.applyRunSummary(summary)` (new `lastLevelUp: LevelUpResult?` model
   state, cleared in `startRun`); challenge runs: capture `recordChallengeRun` payout into
   `lastChallengePayout: Int`.
2. Skin pipeline: `applyCurrentSkin()` resolves Skin, guards ownership (fallback `default`),
   calls `renderer.applySkin(skin)` (new API); `refreshSkinUnlocks(level: store.playerLevel)`
   at `install()` launch catch-up, after `recordRunResults`, after challenge record, after
   mission claims — each granted skin fires "NEW CHARACTER — <NAME>" popup + `purchaseChime`;
   demo profile adds `"bolt"`.
3. GameOver/menu wiring: pass `levelUp: lastLevelUp, styleCoins: lastCoinsFromStyle,
   challengePayout: lastChallengePayout`; prune MenuView call site to the final signature;
   FX → haptics: `ringPassed`(light/medium on perfect), `boostStarted`(medium),
   `flowSurge` + level-up (success) in `Services/Haptics.swift` + synth `play` mapping for
   the six SFX; EffectsOverlay popups for ring/boost/flow events.
4. `InteractionUITests.swift`: update identifiers to the new menu (gear no longer on menu —
   route via Profile), add 2 flows: hero stage→Characters→focus locked skin→requirement
   visible; GameOver→XP bar exists after autoplay death.
5. Full QA: device checklist (Bolt trail end-to-end, Prism crossfade regression, Eclipse on
   Caverns, Reduce Motion statics, Pebble vs Eclipse silhouettes, 7/7 arc by feel, ring
   PERFECT, overdrive runway, flow surge cadence, level-up burst, weekly board, challenge
   tier toast); update `state.md`.

**Verify:** `./Tools/ci.sh` (generate + build + FULL suite ≈121 tests incl. XCUITest);
autoplay demo; `PR_DEMOPROFILE` screenshots; device install.
**DONE:** full suite green; every QA checklist item checked or filed to §P; state.md updated.

---

## C. CONTRACTS APPENDIX — every cross-wave symbol

### C.1 Wave 1 → 3/4/5 (Core surface)

| Symbol | Exact contract |
|---|---|
| `GameSnapshot.boostRemaining` | `Double`, 0 when inactive, mirrors `boostT` |
| `GameSnapshot.flowStreak` | `Int`, near-miss streak since last surge/reset |
| `FXEvent.ringPassed(x: Double, y: Double, perfect: Bool)` | once per ring |
| `FXEvent.boostStarted(x: Double)` / `FXEvent.boostEnded` | edge events |
| `FXEvent.flowSurge(level: Int, x: Double)` | `level` = surges this run (1-based) |
| `EntityKind.ring`, `EntityKind.boostPad` | in `activePickups`, never lethal |
| `SpawnCmd.ring(d: Double, lane: Int, y: Double)` / `.boostPad(d: Double, lane: Int)` | |
| `Collisions.ringPass(playerCenterY:playerX:ringX:ringY:z:) -> (pass: Bool, perfect: Bool)` | pure |
| `Tuning` (names binding) | `gemArcBaseY 0.8 · gemArcAirFrac 0.75 · gemArcMaxSpan 14 · ringY 2.90 · ringPassDX 0.9 · ringPassDY 0.9 · ringPerfectDY 0.12 · ringZHalf 0.9 · ringScore 150 · ringCoins 5 · ringPerfectCoins 12 · capRing 4 · boostDuration 1.0 · boostFactor 1.3 · boostSpeedMax 36 · boostScoreBonus 60 · boostGemBonus 1 · capBoostPad 2 · flowPerSurge 3 · flowSurgeScore 80 · fountainGems 10 · fountainLead 26 · fountainSpacing 1.7 · midEarlyDiff 0.18 · streakPerMult 5` |
| `DailyChallenge.layoutVersion` | default `2` |
| `Patterns.count` | `14`; movingWalls = index 13 (LAST) |

### C.2 Wave 2 → 3/4/5 (Meta surface)

```swift
struct Skin: Identifiable, Sendable {                      // SkinCatalog.swift (SPM — Foundation only)
    enum BodyShape: Sendable { case sphere, cube, crystal }
    enum PupilStyle: Sendable { case dot, wide, slit, glint }
    enum Rarity: Int, Sendable, Comparable { case common = 0, rare, epic, legendary }
    enum Unlock: Equatable, Sendable {
        case free, coins(Int), level(Int)
        case achievement(id: String, tier: Int), challengeDays(Int), iap
    }
    struct Idle: Sendable { var bobSpeed = 1.6; var bobAmp = 0.05
                            var blinkMin = 2.2; var blinkMax = 4.2; var sway = 0.12 }
    let id, name, flavor: String
    let bodyHex, antennaHex: UInt32          // bodyHex 0 = followsWorld (Prism only)
                                             //   ^ REVOKED v1.4.2 (decree 1): sentinel deleted —
                                             //     Prism authored 0x00F5FF / 0xFF2BD6; no skin
                                             //     may have bodyHex 0 (pinned by tests)
    var trailHex: UInt32? = nil              // nil = follow world accent (Prism only)
                                             //   ^ REPURPOSED v1.4.2: nil = "ride the prismatic
                                             //     shimmer hue" (Prism only) — NEVER the world
    var isPrismatic = false                  // ADDED v1.4.2: fixed 8 s time-based shimmer
                                             //   (SkinCatalog.prismaticColor) — identical in
                                             //   every world; exactly one (`default`)
    var bodyShape: BodyShape = .sphere
    var scale: Float = 1                     // visual only, 0.85...1.12
    var eyeRadius: Float = 0.13
    var eyeTintHex: UInt32 = 0xFFFFFF
    var pupilStyle: PupilStyle = .dot
    var antennaHeightScale: Float = 1
    var antennaTipScale: Float = 1
    var idle: Idle = Idle()
    let rarity: Rarity
    let unlock: Unlock
    var followsWorld: Bool { bodyHex == 0 }  // DELETED v1.4.2 (decree 1) — replaced by
                                             //   `isPrismatic` above; nothing follows the world
    var premium: Bool { unlock == .iap }                       // back-compat
    var cost: Int { if case .coins(let c) = unlock { c } else { 0 } }   // back-compat
}
```

| Symbol | Exact contract |
|---|---|
| `SkinCatalog.all` | ~~16 entries~~ **[AMENDED v1.4: 24 entries — 16 legacy frozen + the v1.4 eight (Tide 2,000 / Thorn 3,500 / Golem 5,000 / Monarch 7,500 coins, Circuit L8 / Nebula L18, Facet ach.gems t2, Vigil 14 challenge days)]**, DESIGN_characters §2 table, Fang cost **2,500** (R4) |
| `SkinCatalog.skin(_ id: String) -> Skin` | unchanged fallback `all[0]` |
| `SkinUnlocks.earned(_ skin: Skin, profile: Profile, level: Int) -> Bool` | coins/iap → false |
| `SkinUnlocks.requirementText(_ skin: Skin) -> String` | pinned copy per unlock case |
| `enum XPCurve` | `maxLevel = 30` · `cumulativeXP: [Int]` (L2 = 300 … L30 = 69,600) · `level(for totalXP: Int) -> Int` · `xpIntoLevel(for totalXP: Int) -> (current: Int, needed: Int)` · `xp(for s: RunSummary) -> Int` (clamped 0…2,000; never reads Profile) · `coinGrant(forLevel n: Int) -> Int` (2–9: 100, 10–19: 250, 20–29: 500, 30: 2,000) · ~~`xpUnlockLevels: [Int] = [3, 6, 12, 25]`~~ **[AMENDED v1.4: `[3, 6, 8, 12, 18, 25]`]** · `styleCoins(closes: Int, slicks: Int, multiplier: Int) -> Int` = `min(closes+slicks, 40) * 2 * multiplier` |
| `struct LevelUpResult: Equatable, Sendable` | `xpGained, levelBefore, levelAfter, coinsGranted: Int; unlockedLevels: [Int]` |
| `Profile` new fields | `seenSkins: Set<String> = ["default"]` · `totalXP: Int = 0` · `xpLevelRewarded: Int = 1` · `weeklyMissionDate: Date? = nil` · `challengeRewardTier: Int = 0` · `bestDistanceByWorld: [Int: Double] = [:]` — all `decodeIfPresent ?? default` |
| `ProfileStore.playerLevel: Int` | computed `XPCurve.level(for: profile.totalXP)` |
| `ProfileStore.applyRunSummary(_ s: RunSummary, now: Date = Date()) -> LevelUpResult` | `@discardableResult`; XP + watermarked grants + missions (daily+weekly) + bestDistanceByWorld |
| `ProfileStore.refreshSkinUnlocks(level: Int) -> [Skin]` | `@discardableResult`; grants once via `ownedSkins` insertion |
| `ProfileStore.markSkinsSeen()` | `seenSkins.formUnion(ownedSkins)` |
| `ProfileStore.refreshWeeklyMissions(now: Date = Date())` | rollback-clamped UTC-week rollover |
| `ProfileStore.recordChallengeRun(score: Int, now: Date = Date()) -> Int` | `@discardableResult`; returns tier payout (tiers 1k/5k/15k → +100/+150/+250, daily reset) |
| `RunSummary.startWorld: Int = 0` | checkpoint start world; zeroes skipped-world XP |
| `Mission.Scope.weekly` + `MissionCatalog.weeklyPool` | 7 entries (R10), tag `0x5745_454B_4C59_3133` |

### C.3 Wave 3 → 5 (Render surface)

| Symbol | Exact contract |
|---|---|
| `RealityRenderer.applySkin(_ skin: Skin)` | stores params, `paletteKey = -1`, `rebuildCharacter()` |
| `RealityRenderer.applySkin(bodyHex:antennaHex:followsWorld:)` | ~~legacy shim, KEPT until v1.4 (R13)~~ **[DELETED v1.4.2 `7349a19` — zero callers; survived v1.4/v1.4.1 contrary to plan (AUDIT D2-6) and its parameter name is the decree-1-banned behavior]** |
| Renderer consumes | `EntityKind.ring/.boostPad`, all four new FXEvents, `boostRemaining`, `flowStreak` |

### C.4 Wave 4 → 5 (UI/Audio surface)

| Symbol | Exact contract |
|---|---|
| `AnimatedCharacterSwatch(skin: Skin, size: CGFloat = 62, silhouette: Bool = false, animated: Bool = true)` | Canvas idle preview |
| `CharacterHeroStage(skin: Skin, height: CGFloat)` | swatch + glow disc + name pill (one tap target) |
| `WorldPreviewCanvas(palette: WorldPalette, worldIndex: Int, size: PreviewSize)` | `PreviewSize: .chip/.card/.hero` |
| `GameOverView` init additions | `levelUp: LevelUpResult? = nil, styleCoins: Int = 0, challengePayout: Int = 0` |
| `GameOverView` init additions (amended post-review — wave 4 shipped, wave 5 wired) | `isChallengeRun: Bool = false` (gates the 7-day dot strip + tier line) · `onCharacters: (() -> Void)? = nil` (NEW CHARACTER UNLOCKED · TAP → Characters) · `onFullStats: (() -> Void)? = nil` (FULL STATS › → Profile) |
| `MenuView` init addition (amended post-review) | `onHowToPlay: (() -> Void)? = nil` (FIRST RUN › when best == 0; falls back to `onPlay`) |
| `CharacterSelectView` init addition (amended post-review) | `initialFocus: String? = nil` (shop rail/featured routing — stage opens focused on that skin, uiux §4.1) |
| `Theme.Role` / `Theme.TypeScale` / `Theme.Space` / `Theme.Radius` | uiux §2 tokens (R12 naming) |
| `Synth.SFX` new cases | `ringPass, ringPerfect, boostStart, boostEnd, flowSurge, levelUp` |
| MenuView / meta views | read `ProfileStore.shared` directly in `body`; legacy init params defaulted |

---

## I. IRON-RULE COMPLIANCE PER WAVE

| Rule | W1 core | W2 meta | W3 render | W4 ui/audio | W5 wiring |
|---|---|---|---|---|---|
| 1 Core purity | Foundation-only; new contact via Snapshot/FXEvent only | no Core imports beyond reading Tuning constants | renderer behind same seam | no Core writes | no Core writes |
| 2 Seeded RNG | new patterns 1 call each via run stream; flow/fountain ZERO RNG; arc pure f(d) | weekly SplitMix64 = meta stream, distinct tag, never feeds startRun | n/a (visual `elapsed` jitter allowed) | featured-rotation/decor SplitMix64 UI-local only | no RNG |
| 3 Bot green + layoutVersion | **layoutVersion 1→2 here**; both soaks re-run; Autopilot ZERO diffs; 2 directed bot tests | no spawn-path change | no sim change | no sim change | ci.sh re-proves |
| 4 Pattern order | movingWalls = idx 13 LAST; prefix tiers 5/9/11/13/14; RNG counts pinned | — | — | — | — |
| 5 G3 | — | — | — | **CharacterSelectView:12 rewrite; grep gate; direct store reads in body** | lastLevelUp is model state, not store snapshot |
| 6 Zero binary assets | — | — | MeshDescriptor torus/chevrons only | Canvas/TimelineView only; DSP SFX only | — |
| 7 decodeIfPresent | — | **all six new fields ?? default + legacy-JSON test** | — | — | — |
| 8 Swift 6 strict | new types Sendable; GameCore @MainActor | Sendable value types | MainActor.assumeIsolated pattern kept | Sendable; @MainActor views | existing patterns |
| 9 Economy | ring/boost/fountain → gemCount, no streak bump | grants watermarked; one applyRunSummary | — | breakdown display only | style coins = 4th per-death delta; applyRunSummary once via statsRecorded |
| 10 Checkpoint/challenge | mechanics seed-deterministic | startWorld zeroes checkpoint world-XP; challenge XP allowed (R: progression §1.6) | — | — | challenge no-revive/no-checkpoint untouched; checkpoint GC skip untouched |

## T. TEST PLAN (95 → ≈121)

| Wave | File | Tests (≈) | Pins |
|---|---|---|---|
| 1 | ArcCollectionTests (NEW) | 4 | 7/7 at d∈{300,1000,2500,4000}; +1.2-late 7/7; chrono ≥5/7; length law |
| 1 | RingTests (NEW) | 3 | ringPass boundaries; scripted perfect fires once + exact score/coins; no-jump no-event |
| 1 | BoostTests (NEW) | 4 | grounded-only trigger; effectiveSpeed composition + chrono cap; boostEnded edge once; gem bonus + doubler stacking via gemCount (rule 9) |
| 1 | FlowTests (NEW) | 4 | surge every 3rd; fountain 10 gems lane/lead; resets on shield/death; same-seed-same-inputs identical hash + pattern-stream isolation |
| 1 | PatternOrderTests (NEW) | 2 | movingWalls LAST; maxIndex monotone + tier boundaries + per-pattern RNG counts pinned |
| 1 | SolvabilityBotTests (amend) | +2 | runway containment invariant (5.1 + 36 < 48); forced-boost-into-next-pattern; soaks re-green |
| 1 | DailyChallenge/Difficulty/RNG (amend) | 0 net | goldens re-pinned for layoutVersion 2 (+ v3 pre-arm pin) |
| 2 | ProgressionTests (NEW) | 8 | XP curve table; formula+clamp+startWorld+no-IAP-XP; grants+watermark idempotent; weekly determinism/rollover/rollback; styleCoins cap; challenge tiers once/day; legacy decode (6 fields); cloud-merge max |
| 2 | SkinCatalogTests (NEW) | 4 | ~~16 unique; legacy hex/cost frozen + aurora premium; scale 0.85…1.12 + exactly one followsWorld/one iap + xpUnlockLevels == [3,6,12,25] + achievement ids exist in MissionCatalog~~ **[RE-PINNED v1.4 + v1.4.2: 24 unique; legacy 16 frozen (sole exception: Prism's revoked bodyHex-0 sentinel → authored 0x00F5FF/0xFF2BD6); scale 0.85…1.12 + ZERO followsWorld (no bodyHex 0; computed deleted) + exactly one isPrismatic (`default`) + nil-trail == ["default"] (shimmer source) + one iap + xpUnlockLevels == [3,6,8,12,18,25] + achievement ids exist + prismaticColor pure/8 s-periodic/authored stops]**; refreshSkinUnlocks grant-once + requirementText non-empty |
| 4 | SynthTests (amend) | +2 | six new SFX buffers non-empty/finite |
| 5 | InteractionUITests (amend) | +2 | hero→Characters→locked requirement; GameOver XP bar present |
| | **Total new** | **≈26** | **≈121 total (89+26 SPM-side + 6+2 XCUITest)** |
