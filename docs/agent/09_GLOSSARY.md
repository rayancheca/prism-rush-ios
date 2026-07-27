# 09 — Glossary

Canonical vocabulary for Prism Rush. Every future session should use **these** words with **these**
meanings. Entry format: **term** — definition — `where it lives`.

All paths are relative to the repo root
(`/Users/rayankarimcheca/Desktop/ClaudeProjects/projects/prism-rush-ios/.claude/worktrees/beautiful-davinci-797e3b`).
Line numbers were verified against source on 2026-07-27 (branch `claude/beautiful-davinci-797e3b`,
HEAD `7e87380`).

> **Read this first:** §7 "Terms the codebase uses inconsistently" lists the traps. If you are about
> to write a doc or a commit message using the words *world*, *tier*, *slot*, *streak*, *gem*,
> *cycle*, or *skin*, read §7 before you do.

---

## 1. Game vocabulary

Player-facing nouns and the mechanics they name.

| term | definition | lives in |
|---|---|---|
| **lane** | One of exactly 3 fixed X positions the player occupies: `-2.2`, `0`, `+2.2`. Lane index `0/1/2` (1 = centre) is the canonical integer; `laneX[i]` is the world X. A `lane` of `-1` on an `EntityState` means *full-span* (a `bar`). | `Core/Tuning.swift:7`; `Core/GameCore.swift` `laneIndex`; `Core/Models.swift:41` |
| **world** | An 800 m stretch of track. The **world ordinal** (`maxWorld` / `worldOrdinal`) is the unbounded absolute index `floor(distance / 800)`. Worlds never stop — the run is endless. | `Core/Tuning.swift:8` (`worldLength = 800`); `Core/GameCore.swift:46`, `:286-298` (`stepWorld`) |
| **world family** | The *cosmetic* identity a world wears: `ordinal mod worldFamilyCount` (12). Twelve authored palettes + skies; past 12 the family repeats but the palette is hue-rotated per **cycle**. | `Core/Tuning.swift:13`; `Core/GameCore.swift:290-292`; `UI/Theme.swift:22` (12 `WorldPalette`s), `:61` (`evolvedPalette`) |
| **cycle** | `worldOrdinal / 12` — how many times the 12-family set has wrapped. Drives palette hue rotation (+0.137 turns/cycle, capped at 4 cycles), sky element density, and the roman-numeral name suffix ("Orbital Drift II"). | `UI/Theme.swift:47-61`; `Render/Reality/WorldDecor.swift` (`WorldSky`) |
| **pattern** | One entry of the **14-item** obstacle catalogue: a function `(index, base, rng) -> [SpawnCmd]` returning the pattern's length. Patterns are the only thing the spawner places. | `Core/Patterns.swift:27` (`count = 14`), `:74` (`run`) |
| **gap** | The empty distance the spawner inserts *between* consecutive patterns; lerps `11 → 5` m as difficulty rises. Since v1.6 a gem breadcrumb trail is laid through it into the next pattern's safe entry lane. **Do not confuse with** the open lane of a `splitBar`, which the code comments also call "the gap" (`Core/Models.swift:19`, `Patterns.swift:174`). | `Core/Spawner.swift:18` (`gap(forDistance:)`), `:48-59`; `Core/Tuning.swift:59` (`gapMax 11`, `gapMin 5`) |
| **tier** | Overloaded — see §7. In the spawner it means one of the **5 difficulty tiers** of the prefix ladder (`maxIndex(forDistance:)` returns 5 / 9 / 11 / 13 / 14). | `Core/Spawner.swift:25-32` |
| **gem** | The octahedron collectible on the track. In-run it pays **score** (`gemBaseScore 10 × mult`) and increments `gemCount` + `streak`. At death `gemCount` converts to **coins**. Renders as `EntityKind.gem`. | `Core/Models.swift:20`; `Core/Tuning.swift:76`; `Core/GameCore.swift:61` (`gemCount`) |
| **coin** | The persistent **currency**. Lives only in `Profile.coins`; the core never knows about coins. Earned at run end from gems / distance / worlds crossed / style, and from chests, missions, XP level-ups, packs. **Do not confuse with gem:** a gem is a track object and a run-scoped counter; a coin is a meta-layer balance. | `Meta/Profile.swift:6`; `UI/GameView.swift:680-712` (`recordRunResults`) |
| **streak** | Overloaded — see §7. In-run it is `GameCore.streak`: consecutive gems collected without dying; every `streakPerMult` (5) gems bumps the multiplier, capped at `multCap` (5). | `Core/GameCore.swift:62`; `Core/Tuning.swift:51` |
| **multiplier / `mult`** | The 1…5 score multiplier derived from `streak`. Multiplies gem score, near-miss bonus, flow-surge score, and the end-of-run coin payouts. | `Core/GameCore.swift:64`; `Core/Tuning.swift:51` |
| **near-miss** | Passing an obstacle by a hair. Two flavours, `NearMissKind.close` and `.slick`. Awards `nearMissBonus` (40) × mult and advances `flowStreak`. | `Core/Models.swift:119`; `Core/Tuning.swift:76` |
| **CLOSE** | The near-miss flavour: squeezed past a `tall` with `1.25 ≤ |dx| < 1.95`. The outer edge must stay under the 2.2 lane pitch or merely standing one lane away would auto-award it. Surfaces as the popup text `CLOSE`. | `Core/Tuning.swift:64` (`nearMissInner`, `nearMissOuter`); `Core/Models.swift:120` |
| **SLICK** | The other near-miss flavour: slid under a `bar` (or `splitBar`). Surfaces as the popup text `SLICK`. | `Core/Models.swift:120` |
| **flow streak** | `GameCore.flowStreak` — near-misses accumulated since the last surge or the last hit. Always `< flowPerSurge`. The HUD shows it as **flow pips**. | `Core/GameCore.swift:57`; `Core/Tuning.swift:120` |
| **flow surge** | What every 3rd (`flowPerSurge`) consecutive near-miss detonates: `flowSurgeScore` (80) × mult **plus** a gem **fountain**. Derived purely from state — consumes **zero** RNG. Emits `FXEvent.flowSurge(level:x:)`; `level` = surges this run, 1-based. | `Core/GameCore.swift:447-460`; `Core/Tuning.swift:118-124`; `Core/Models.swift:140` |
| **fountain** | The 10-gem spray a flow surge places into the player's current lane, `fountainLead` (26 m) ahead at `fountainSpacing` (1.7 m). Deterministic, zero RNG. | `Core/GameCore.swift:456-459`; `Core/Tuning.swift:122-124` |
| **checkpoint** | Starting a run mid-track from a reached-or-purchased world: `GameModel.beginRun(fromWorld:)` → `GameCore.startRun(startDistance:)`. Sets `usedCheckpoint`, `scoreOffset`, and repositions `spawner.cursor` + `powerUpCursor`. Checkpoint runs are **excluded from Game Center submission** (iron rule 10). | `Core/GameCore.swift:96-114`; `Core/Models.swift:78` |
| **revive / continue** | Paying `150 × (revivesUsed + 1)` coins after a death to resume the *same* run. Max 2 per run; **never** on a Daily Rush. | `UI/GameView.swift:454-462`; `UI/GameOverView.swift:91` |
| **daily challenge** | The internal/Core name for the UTC-date-seeded shared run: every player on the same calendar date and `layoutVersion` gets a byte-identical track. | `Core/DailyChallenge.swift:8-27`; `Meta/Profile.swift:62-65` |
| **Daily Rush** | The **player-facing UI label** for the daily challenge. Same feature. No revive, no checkpoint, no loadout, no deploy buttons — the shared competitive board stays consumable-free (decree 5). Use "daily challenge" when talking about `Core/`, "Daily Rush" when talking about UI copy. | `UI/GameView.swift:833`, `:1177`; `UI/GameOverView.swift:91` |
| **mission** | A tracked objective with a metric, target and coin reward. Four **scopes**: `perRun`, `daily`, `weekly`, `lifetimeTiered(targets:rewards:)` (the last are the "achievements"). | `Meta/MissionCatalog.swift:27` (`Mission`), `:28` (`Metric`), `:58` (`Scope`) |
| **slot** (mission) | One of the 3 daily (or weekly) missions drawn deterministically from the pool for a UTC day/week. Only slots are claimable, though the whole pool accumulates progress. **Do not confuse with** decor slot or G-counter device slot — see §7. | `Meta/MissionCatalog.swift`; `Meta/Profile.swift:58-59` |
| **skin** | The `Skin` value type: the *data recipe* for a character (id, colours, geometry params, crest, aura, rarity, unlock rule). This is the type name; `Profile.selectedSkin` / `ownedSkins` are the storage. | `Meta/SkinCatalog.swift:9-63`; `Meta/Profile.swift:45-47` |
| **character** | The **player-facing word** for a skin. UI strings say "character"; the code says `Skin`. They are the same thing. 24 exist as of v1.4. | `UI/CharacterSelectView.swift`; `Meta/SkinCatalog.swift` |
| **equipped skin** | The *resolved* character actually rendered: `selectedSkin` if owned, else `"default"`. A dormant selection revives when the skin is later unlocked. Always read this, never `profile.selectedSkin` directly. | `Meta/ProfileStore.swift:214` (`equippedSkinID`) |
| **rarity** | `Skin.Rarity`: `common < rare < epic < legendary`. Drives the shelf sectioning and the crest/aura ladder. | `Meta/SkinCatalog.swift:27-30` |
| **crest** | The head adornment that signals rarity (`Skin.Crest`, 7 cases): rare → ears/floppy/fin, epic → horns/crown, legendary → signature crest. **Purely cosmetic — never a gameplay advantage.** | `Meta/SkinCatalog.swift:18-25`, `:60`, `:76` (`crestHex`) |
| **aura** | The orbiting glow ring worn by legendaries only (`Skin.hasAura`). Cosmetic. | `Meta/SkinCatalog.swift:63`, `:244` |
| **prismatic / shimmer** | Prism's (the default character's) identity: a fixed 8 s cyan→magenta→amber colour cycle from `SkinCatalog.prismaticColor(at:)`. **World-independent by owner decree 1.** Replaced the revoked v1.3 "chameleon" (`followsWorld`) behaviour. | `Meta/SkinCatalog.swift`; `Render/Reality/RealityRenderer.swift:49-50`, `:580-592` |
| **tease** | The rendering of a *locked* character: full colour, animated, at 0.45 opacity (grid) / 0.6 (hero stage) with a solid lock chip. Replaced the pre-v1.4 dark silhouette. The parameter is still historically named `silhouette`. | `UI/CharacterSelectView.swift`; `UI/CharacterSwatch.swift` |
| **loadout** | Pre-run consumables **armed on the hub** and consumed at run start: **Head Start** and **Coin Surge**. Never applied on a Daily Rush. | `Meta/Profile.swift:24-25`; `UI/LoadoutStrip.swift`; `UI/GameView.swift:399-410`, `:1177` |
| **deploy** | Spending a **banked charge** from an in-run HUD corner button. Exactly three deployables, frozen: Slow-Mo, Speed Up, Shield. **Do not confuse with pickup** (grabbed off the track) **or loadout** (armed before the run). | `UI/GameView.swift:843` (`deploySlowMo`), `:862` (`deploySpeedUp`), `:881` (`deployShield`); `Core/GameCore.swift:245`, `:256` |
| **pickup** | A power-up **collected on the track**: shield, magnet, doubler, chrono, superSneakers (plus ring and boostPad, which are scored objects rather than timed buffs). Enumerated as `PickupKind` (5 cases) and as `EntityKind` cases. | `Core/Models.swift:9-11`, `:14-28` |
| **head start** | The pre-run loadout consumable that launches the run with `headStartBoostDuration` (4.5 s) of Overdrive boost. A momentum grant, not a score grant — leaderboard-safe (does **not** set `usedCheckpoint`). | `Core/Tuning.swift:114`; `Meta/Profile.swift:24` |
| **Coin Surge** | The other pre-run loadout consumable: ×2 coins for the whole run. Captured at run start into `coinSurgeActiveThisRun` and held stable through revives so the payout multiplier never drifts mid-run. | `Meta/Profile.swift:25`; `UI/GameView.swift:400-410` |
| **Overdrive / boost** | Speed ×1.3 (capped at 36) for `boostDuration` (1.0 s from a floor **boost pad**, 3.0 s from a Speed Up deploy, 4.5 s from a Head Start). Emits `boostStarted` / `boostEnded`. | `Core/Tuning.swift:107-116`; `Core/Models.swift:138-139` |
| **boost pad** | The floor chevron strip; grounded contact triggers Overdrive. `EntityKind.boostPad`. Always spawned inside an obstacle-free runway (pattern 10). | `Core/Models.swift:27`; `Core/Patterns.swift:147` |
| **chrono / slow-mo** | The pickup that scales world scroll by `chronoFactor` (0.65) for 5 s while the player still ticks at real dt — stretching every dodge window ~1.5×. Strictly easier. The raw `speed` ramp is untouched. | `Core/Tuning.swift:34-36`; `Core/GameCore.swift:54` |
| **Super Sneakers** | The winged-boot pickup: jump launch velocity ×1.3 for 8 s (≈ ×1.7 apex). While active only, a jump whose feet clear `tallVaultClearance` (2.9) **vaults** a tall wall instead of dying. The solvability bot never collects pickups, so this buff is never active in the soak. | `Core/Tuning.swift:38-47`; `Core/GameCore.swift:131` (`launchVelocity`) |
| **vault** | Super-Sneakers-only: surviving a `tall` by having feet above 2.9. Collision-only, no spawn RNG — no `layoutVersion` bump. | `Core/Tuning.swift:43-47` |
| **ring / prism ring** | The torus at jump-apex height (`ringY 2.90`). Threading it pays `ringScore` (150) + `ringCoins` (5), or `ringPerfectCoins` (12) on a bullseye (`|dy| ≤ ringPerfectDY 0.12`). **Never lethal.** Emits `ringPassed(x:y:perfect:)`. | `Core/Tuning.swift:94-103`; `Core/Models.swift:137` |
| **ballistic gem arc** | A run of gems laid **on the predicted jump parabola** so the survival jump and the collect are the same input. Pure `f(d)` — zero RNG. Span capped at `gemArcMaxSpan` (14). | `Core/Tuning.swift:89-92` |
| **coin trail / breadcrumb** | The v1.6 path-aware gem line laid through a pattern gap into the next pattern's `safeEntryLane`, so following the coins is always a takeable route. Zero RNG; rode `layoutVersion` 5. | `Core/Spawner.swift:49-59`, `:64` |
| **cadence (power-up cadence)** | The guaranteed power-up drip: one power-up every `powerUpCadence` (350 m) from `powerUpFirstAt` (150 m), cycling through **all five** pickup kinds, placed in a free lane (`freeLaneNear`). Deterministic, zero RNG. | `Core/Tuning.swift:52-58`; `Core/GameCore.swift:300-330` |
| **invuln window** | `invulnDuration` (0.4 s) of grace after a shield absorb. Patterns place twin talls at the same `d`, so without it the second wall would finish the job on the same or next tick. | `Core/Tuning.swift:48-50` |
| **Mystery Box** | The 300-coin gacha in the shop. Its odds are **published verbatim** in the UI from `mysteryOdds` (owner decree 5 — no dark patterns). | `Meta/ShopValue.swift:117`; `UI/MysteryBoxView.swift:70` |
| **pack** | A coin **pack** — a coin-for-money IAP (`coins.small/medium/large/mega` = 1,200 / 7,000 / 16,000 / 40,000) or its shop card. Carries a computed **pack badge** (`bestValue` / `balancedPick` / `bonus(N)` / `none`). | `IAP/IAPCatalog.swift:26-35`; `Meta/ShopValue.swift:9` |
| **hero offer / hero slot** | The Shop's single spotlight card: `HeroOffer.doubler` / `.starter` / `.rotation(skinID)`. | `UI/ShopView.swift:129` |
| **rotation / featured** | The day-seeded featured skin picked by the pure `ShopValue.featuredSkin(daySeed:pool:owned:)`. | `Meta/ShopValue.swift:46` |
| **rail / rail cell** | The hub's 3-cell horizontal `RewardsBar` (rewards / missions / daily). A **lit cell** is the single gold cell chosen by the priority ladder. Rail cells wrap their button in `.accessibilityElement(children: .ignore)`, so XCUITest must query them by `.any`, never `.button`. | `UI/RewardsBar.swift`; `UITests/InteractionUITests.swift` |
| **hub** | Ambiguous by layer: in UI docs it is `MenuView` (the menu screen). In `ui-game.md` it is `GameModel` (the object that owns everything). **Prefer "menu screen" for the view and "GameModel" for the object.** | `UI/MenuView.swift`; `UI/GameView.swift` (`GameModel`) |
| **meta screen / meta sheet** | One of the six `GameModel.MetaScreen` cases (`characters`, `shop`, `levels`, `stats`, `settings`, `missions`), rendered as a **ZStack layer**, not a SwiftUI `.sheet`. | `UI/GameView.swift` (`MetaScreen`, `metaSheet(_:)`); `UI/MetaScreenScaffold.swift` |
| **startable world** | Reached **or** purchased — the level-select card is playable. Distinct from **reach**. | `Meta/ProfileStore.swift:260` (`isWorldStartable`) |
| **reach** | `Profile.maxWorldReached` — advances **only by playing**. Achievements, the world coin bonus and XP are all reach-based. | `Meta/Profile.swift:36` |
| **reach credit** | The guard that stops a *purchased* deep-world start from laundering into `maxWorldReached`. | `Meta/ProfileStore.swift:290` (`reachCredit(maxWorldThisRun:startWorld:reachAtStart:)`) |
| **popup** | Screen-space rising text (`+250`, `CLOSE`, `PERFECT`, `LEVEL UP`) positioned from the player's world X and styled by text prefix. | `UI/GameView.swift` (`GameModel.Popup`); `UI/EffectsOverlay.swift` |
| **milestone** | The LEVEL UP / NEW CHARACTER class of popup, queued in `milestoneQueue` and released one per 1.0 s so they never stack on the shared anchor. | `UI/GameView.swift` |
| **tutorial cue / hint** | `GameModel.TutorialCue` (`jump`, `slide`, `lane`) — the just-in-time control prompt fired once each when a matching obstacle enters `-34 < z < -12`. Pure presentation off the snapshot; never touches Core/RNG. | `UI/GameView.swift:105-113`, `:412-414` |
| **first-run gate** | `GameModel.pendingFirstRunStart`: the deferred run-start closure held while `HowToPlayView` is interposed, so LET'S GO starts the run the player actually chose (menu PLAY, Daily Rush, or Worlds). | `UI/GameView.swift:59` |
| **restart cooldown** | The 1.0 s `overTime` gate before RUN AGAIN becomes tappable (`canRestart` / `restartCountdown`). | `UI/GameView.swift:133-140` |
| **ghost chase chip** | The HUD's "BEST N AHEAD" line, shown only within 10 % of a best ≥ 1,000. | `UI/HUDView.swift` |
| **XP / level** | Lifetime XP (`Profile.totalXP`) → level 1…30, always **derived** via `XPCurve.level(for:)`, never stored. Level-ups pay a coin grant gated by the `xpLevelRewarded` watermark. | `Meta/XPCurve.swift:19-58`; `Meta/Profile.swift:41-42` |

---

## 2. Simulation vocabulary

Everything below is `Core/` — Foundation only, no UIKit, no RealityKit (iron rule 1).

| term | definition | lives in |
|---|---|---|
| **tick** | One fixed simulation step of `Tuning.tickDt = 1/120 s`. `GameCore.tick(_:)` is internal so tests can drive exact step counts. | `Core/Tuning.swift:60`; `Core/GameCore.swift:172` |
| **dt** | The tick's timestep. Inside `tick` it is always `tickDt`; `advance(realDt:)` takes wall-clock time. Renderers use a separate clamped `sdt` (§3). | `Core/GameCore.swift:159`, `:172` |
| **accumulator** | The leftover wall-clock time carried between `advance` calls. `advance` adds `min(realDt, 0.1)` then drains it in whole `tickDt` steps. A non-finite or non-positive `realDt` is **rejected before the accumulator** — `min(NaN, 0.1)` is NaN, which would stick and brick the run. | `Core/GameCore.swift:76`, `:159-169` |
| **snapshot** | `GameSnapshot` — the immutable, `Sendable`, per-frame value the core hands the renderer and the UI. Rebuilt once per `advance`, **not** once per tick. | `Core/Models.swift:53-116`; `Core/GameCore.swift:168` |
| **FX event** | `FXEvent` — a one-shot gameplay edge emitted from inside a tick, delivered synchronously **before** that frame's `sync`. The core never performs side effects itself; it only describes what happened. 16 cases. | `Core/Models.swift:123-142` |
| **entity** | Ambiguous across layers — see §7. Prefer the qualified terms below. | — |
| **`EntityKind`** | The pure-data enum of every spawnable thing: `low`, `tall`, `movingTall`, `bar`, `splitBar`, `gem`, `shield`, `magnet`, `doubler`, `chrono`, `superSneakers`, `ring`, `boostPad` (13 cases). | `Core/Models.swift:14-28` |
| **`EntityState`** | One pooled thing's **render state for a single frame**: `id`, `kind`, `x/y/z`, `lane`, `spin`, `fading`. `y` is authoritative for every obstacle kind — renderers must place from `y`, never hardcode heights. | `Core/Models.swift:35-50` |
| **CoreEntity** | The core's *internal* live-object record (obstacle / gem / pickup arrays keyed by absolute `d`), as distinct from the per-frame `EntityState` handed out in the snapshot. Not one Swift type — `activeObstacles` / `activeGems` / `activePickups`. **Do not confuse with RealityKit `Entity`**, which is the pooled render node (§3). | `Core/GameCore.swift` (`activeObstacles`, `activeGems`, `activePickups`) |
| **`d`** | A spawned thing's **absolute** world distance — the odometer value at which it sits. Never changes after spawn (except moving walls' lateral sweep). | `Core/Spawner.swift`, `Core/Patterns.swift` |
| **`z`** | An entity's position **relative to the player**: `distance − d`. **Negative = ahead of the player, positive = behind.** | `Core/Models.swift:31-32` |
| **arrival** | The Autopilot's inverse of `z`: `d − distance`. **Positive = ahead.** Used only in `Autopilot`. | `Core/Autopilot.swift:29`, `:48-52`, `:96-101` |
| **cursor** | `Spawner.cursor` — the absolute distance up to which patterns have been placed. Starts at 60; a checkpoint start moves it to `startDistance + 60`. There is a second, independent `powerUpCursor` for the cadence. | `Core/Spawner.swift:7`; `Core/GameCore.swift:106-107` |
| **horizon** | `distance + Tuning.spawnHorizon` (115 m). The spawner fills up to it every tick; the cadence loop runs to the same horizon **after** `fill`, so `freeLaneNear` sees the patterns already placed. | `Core/Tuning.swift:52`; `Core/GameCore.swift:300-315` |
| **distance** | The **absolute** odometer. Matches world labels; it is the HUD's meters readout. Continues climbing during the post-death decel. | `Core/GameCore.swift:33`; `Core/Models.swift:55` |
| **traveledDistance** | `distance − scoreOffset` — the *fair, this-attempt* metres. Feeds score and XP. **Do not confuse with `distance`:** on a checkpoint run at t=0, `distance` is already thousands and `traveledDistance` is 0. | `Core/GameCore.swift:117`; `Core/Models.swift:56` |
| **scoreOffset** | Distance that must **not** be scored: the checkpoint head-start plus post-death decel drift. | `Core/GameCore.swift:34` |
| **speed** | The **raw difficulty-ramp** world speed: `min(33, 17 + d·0.0052)`, starting at `speedStart` 17 (menu idles at `menuSpeed` 7). Untouched by any buff. | `Core/GameCore.swift:35`; `Core/Tuning.swift:15-16` |
| **effectiveSpeed** | `speed` after chrono (×0.65) then boost (×1.3, capped at 36). **The single composition point for all speed buffs.** Everything distance-domain (obstacle arrival, autopilot leads, scroll) uses this. | `Core/GameCore.swift:123-129`; `Core/GameCore.swift:283` |
| **rampSpeed** | The snapshot field carrying the *un-slowed* `speed`. HUD/debug only — the renderer must not scroll from it. | `Core/Models.swift:58`; `Core/GameCore.swift:720` |
| **difficulty / `diff`** | Normalised difficulty `min(1, distance / diffFullAt)`, `diffFullAt = 3200`. Gates the pattern tier ladder, the gap lerp, and moving-wall availability (`movingWallMinDiff 0.6`). | `Core/Tuning.swift:59`, `:26`; `Core/Spawner.swift:19`, `:26` |
| **prefix gating / tier ladder** | `Spawner.maxIndex(forDistance:)` returns an **exclusive** upper bound, and every tier is a **prefix** of the catalogue — so unlocking a tier never removes a pattern. Iron rule 4: pattern order is load-bearing; moving walls stay LAST. Tiers: `< 260 m → 5`, `diff < 0.18 → 9`, `diff < 0.45 → 11`, `diff < 0.6 → 13`, else `14`. | `Core/Spawner.swift:23-32` |
| **anti-repeat reroll** | One bounded reroll when the drawn pattern index equals **either of the last two** placed (`lastIdx`, `prevIdx`). Single reroll, no loop — repeats stay possible, just rarer. Widening this from one to two is what took `layoutVersion` 6 → 7. | `Core/Spawner.swift:10-12`, `:41-45` |
| **`layoutVersion`** | The integer folded into the daily seed (`layoutVersion << 48`). **Currently `7`** (default arg of `DailyChallenge.seed`). Must be bumped on *any* change to the generated track — RNG-consuming or not — or same-day players stop sharing a track (iron rule 3). Per-version history is in the doc comment. | `Core/DailyChallenge.swift:14-25` |
| **RNG-neutral** | A spawn-path change that adds or moves entities **without** altering the number or order of `rng` draws. `PatternOrderTests`' per-pattern RNG counts stay byte-identical, but the track still reshuffles — so it still needs a `layoutVersion` bump. (Versions 4, 5 and 6 were all RNG-neutral.) | `Core/DailyChallenge.swift:16-21` |
| **seed** | The `UInt64` fed to `SplitMix64`. Iron rule 2: **all randomness goes through the seeded RNG**; a seed must fully determine a run. No `Double.random`, no `Date()` in `Core/`. | `Core/RNG.swift`; `Core/GameCore.swift` (`startRun(seed:)`) |
| **seed salt** | A per-test constant XORed into a test's seed generator (`0x1234_5678`, `0xDEE9_5EED`, `0xC400_0001`, `0xB005_7AD5`) so different soaks sample disjoint seed families. | `Tests/` |
| **golden / pin** | A hardcoded expected value in a test whose change is a **product decision**, not a test fix. Daily-challenge seeds are pinned per `layoutVersion`, with the *next* version **pre-armed** so the following bump already has its expected value recorded. | `Tests/DailyChallengeTests.swift` |
| **run hash** | An FNV-1a fold over 7 per-tick fields (`distance`, `px`, `score`, `gemCount`, obstacle count, gem count, mode) proving two runs are bit-identical. | `Tests/` |
| **spawn-stream isolation** | The property that player input cannot perturb the seeded obstacle stream — proven by replaying one seed against two different input traces. | `Tests/` |
| **autopilot** | `Autopilot.decide(_:)` — the greedy, pure, deterministic bot that reads a `GameCore` and returns a lane/jump/slide decision by predicting obstacle **arrival**. Also drives `PR_AUTOPLAY` / `PR_DEMO` in the shipping app. It **never collects pickups**, so no buff is ever active during a soak. | `Core/Autopilot.swift:8-21` |
| **solvability bot** | The Autopilot run headlessly across **200 seeds × 6,000 m**, asserting zero deaths **and zero stalls**. The mandatory gate on every spawner/pattern/RNG change (iron rule 3). | `Tests/` |
| **soak** | A longer solvability run — the **deep soak** is 64 seeds × 12,000 m. | `Tests/` |
| **containment invariant** | A geometric (no-simulation) proof that a pattern's effects finish inside its own length; used for the Overdrive runway. Related: the **length law** — every pattern's last spawn sits ≥ 2 units before `base + len`. | `Tests/` |
| **`cleanCore` / `debugClearTrack` / `debugSpawn`** | The hand-built-scenario test idiom: start a run, wipe the procedurally spawned track, then place exactly the entities under test. | `Tests/`; `Core/GameCore.swift` |
| **`tickUntil`** | Bounded polling test helper (default `max: 600` ticks) used instead of fixed tick counts. | `Tests/` |

---

## 3. Engine / rendering vocabulary

| term | definition | lives in |
|---|---|---|
| **port / seam** | `RendererPort` — the *one* protocol between sim and renderer: `sync(GameSnapshot)` in, `fire(FXEvent)` in, **nothing out**. This is why the sim is headless-testable. | `Render/RendererPort.swift` |
| **`Entity`** (RealityKit) | A RealityKit scene node. Distinct from `EntityState` (per-frame data) and from the core's internal live objects. When the word is ambiguous, write "pooled render entity". | `Render/Reality/EntityPools.swift` |
| **pool / free list** | Per-`EntityKind` stacks of hidden, parent-less `Entity`s. `obtain` pops or creates; `recycle` disables + unparents + pushes back. Pool caps mirror `Tuning.capLow`…`capBoostPad`. | `Render/Reality/EntityPools.swift`; `Core/Tuning.swift:83-85`, `:103`, `:116` |
| **prewarm** | Pre-building free entities for kinds whose first live spawn is minutes into a run (`ring`, `boostPad`, `superSneakers`) so nothing allocates mid-play. | `Render/Reality/EntityPools.swift` |
| **place closure** | The `(Entity, EntityState) -> Void` passed to `EntityPools.sync`, where all per-kind positioning, spin, scale and material assignment happens. | `Render/Reality/EntityPools.swift` |
| **procedural mesh** | Every mesh in the app, built at runtime via `MeshDescriptor`. Iron rule 6: **zero binary assets** (sole carve-out: `Assets.xcassets/AppIcon.appiconset`, a byte-copy of `Tools/gen_icon.swift`'s output). Materials are `UnlitMaterial` only. | `Render/Reality/ProceduralMesh.swift` |
| **decor slot** | One `WorldDecor.Slot` — a side-of-track scenery group. Slots come in **side pairs sharing a `d`**, scroll toward the camera, and recycle to the horizon re-styled for the current world. | `Render/Reality/WorldDecor.swift:13`, `:39`, `:77`, `:103` |
| **sky family** | One of 12 mutually exclusive `WorldSky` set-piece groups (3 legacy inline + 9 `BespokeSky` objects), indexed by the folded world ordinal. Everything is prebuilt once at init and recycled by `restyle`. | `Render/Reality/WorldDecor.swift:192-197`; `Render/Reality/*Sky.swift` |
| **restyle** | The world-boundary (or Reduce-Motion-flip) pass that re-places and re-tints a sky family or a decor slot from a deterministic **local** RNG. Never runs per frame. | `Render/Reality/WorldDecor.swift:101-103`, `:192` |
| **retint** | `WorldSky.famTints` — the recipe registry that recolours legacy sky elements toward the cycle's evolved palette at each restyle. | `Render/Reality/WorldDecor.swift` |
| **entrance ease** | The ~0.7 s upward rise of an incoming sky family root, folded into the world crossfade flare. | `Render/Reality/WorldDecor.swift` (`WorldSky.update`) |
| **card** | A flat single-sided XY mesh (skyline, ridge, ribbon, grid, beam, disc) facing the chase camera at +Z. The sky layer's basic building block. **Do not confuse with** a SwiftUI `NeonCard`. | `Render/Reality/ProceduralMesh.swift`, `*Sky.swift` |
| **mote** | A small disc particle in a sky family's drifting field (glow motes, plankton, embers, snow, petals, data motes, stars). | `Render/Reality/*Sky.swift` |
| **rig** | The player character's assembled entity hierarchy (body parts, antenna, crest, aura, trail source), rebuilt **only on equip/launch** by `applySkin(_:)` — never per frame. Purely visual; never the hitbox. | `Render/Reality/RealityRenderer.swift:696-697`, `:808`, `:825`, `:914` |
| **shimmer step** | `shimmerStep` — the ~30 Hz **quantized** clock that gates Prism's prismatic body/trail material repaint, so the shimmer does not swap materials every frame. | `Render/Reality/RealityRenderer.swift:50`, `:589-592` |
| **whip** | The underdamped antenna spring (stiffness 140, damping 10) that lags then overshoots the body's lateral velocity. | `Render/Reality/RealityRenderer.swift:621-625` |
| **gallop / run phase** | `runPhase` — the speed-scaled run-cycle clock driving the grounded bob, the `sy` pulse and the antenna bounce. | `Render/Reality/RealityRenderer.swift` |
| **skid** | One of 4 pooled flattened dark boxes dropped under the player on `.slid`, scrolling and fading via scale. | `Render/Reality/RealityRenderer.swift` |
| **ring pulse** | The dedicated one-shot torus that scale-expands on `.ringPassed` — the *pooled* ring entity is already recycled by that frame. | `Render/Reality/RealityRenderer.swift` |
| **debt accumulator** | `trailDebt` / `dustDebt` / `speedLineDebt` / `sneakerDebt` — fractional particle-count carry, so per-second emission rates stay frame-rate independent. | `Render/Reality/ParticleSystem.swift`, `RealityRenderer.swift` |
| **palette key** | The quantized `(fromOrdinal, toOrdinal, blend)` hash that gates the material rebuild. In steady state (`blend == 1`) it never changes, so the rebuild block is skipped. | `Render/Reality/RealityRenderer.swift` |
| **`sdt`** | "Safe dt" — `max(min(lastDt, 1/30), 1/240)`, the clamped frame delta used for the camera spring and velocity estimation so a run-start teleport or a stall cannot spike the pose. A second local `sdtA = min(dt, 1/30)` does the same job for the antenna whip. | `Render/Reality/RealityRenderer.swift:242-244`, `:262-264`, `:621` |
| **ProMotion** | 120 Hz display refresh. Relevant because the frame loop runs at the display rate: any smoothing written as a **fixed per-frame alpha** (e.g. `x += (target - x) * 0.12`) converges **twice as fast on a 120 Hz device as on 60 Hz**. `sdt`-based springs and the debt accumulators were explicitly written to avoid this; the fixed-alpha lerps were not (see `scratch/render.md` §Suspicious, SEV2). | `Render/Reality/RealityRenderer.swift` (many fixed-alpha sites, e.g. `:237`, `:253-254`) |

---

## 4. Meta / economy vocabulary

| term | definition | lives in |
|---|---|---|
| **profile** | `Profile` — the single `Codable`, `Equatable`, `Sendable` value holding everything the player keeps between launches. Iron rule 7: every field is `decodeIfPresent ?? default` in `init(from:)`, so old saves never wipe or fail to load. | `Meta/Profile.swift:5-87`, `:124-171` |
| **ProfileStore** | The `@MainActor @Observable` **singleton** that owns the Profile and is its **only writer**. Also owns iCloud sync and the load-time sanitize. | `Meta/ProfileStore.swift` |
| **`mutate`** | The **one** write funnel. Every profile mutation goes through it and triggers a save. Every persistence side effect in the app originates here. | `Meta/ProfileStore.swift:90` |
| **faucet** | A source of coins into the economy: gems, distance, worlds crossed, style bonus, chests, daily bonus, missions, XP level-up grants, Mystery Box, coin packs. | `UI/GameView.swift:680-712`; `Meta/XPCurve.swift:58`, `:75` |
| **sink** | A place coins leave the economy: character purchases, world purchases (`XPCurve.worldPrice`), revives (`150 × (n+1)`), Mystery Box, deploy/loadout charge top-ups. | `Meta/XPCurve.swift:91`; `UI/GameView.swift:454`; `Meta/ProfileStore.swift:98` (`spendCoins`) |
| **entitlement** | Overloaded — see §7. In the IAP sense: a non-consumable a purchase permanently confers (`Profile.doubleCoins`, an owned `skin(...)`, membership of `ownedProducts`). | `IAP/IAPCatalog.swift:26-35`; `Meta/Profile.swift:68-69` |
| **per-death delta** | The payout shape `max(0, cumulative − alreadyAwarded)`. Lets `recordRunResults` run once per **death** (not once per run) without re-paying a revived run. Iron rule 9 — do not reintroduce cumulative re-pays. | `UI/GameView.swift:698-708` |
| **watermark** | A stored "highest already paid" value that makes a one-time reward idempotent under merges and revives. Persistent ones: `xpLevelRewarded`, `challengeRewardTier`, `achievementTier`, `firstPurchaseBonusUsed`. Per-run ones: `gemCoinsAwarded`, `distCoinsAwarded`, `worldCoinsAwarded`, `styleCoinsAwarded`. | `Meta/Profile.swift:42`, `:65`, `:57`, `:71`; `UI/GameView.swift:78-81` |
| **G-counter** | Grow-only counter (a CRDT). `coinsPurchasedByDevice` is one: each install owns a slot keyed by `pr.device.id`, and merging takes the **per-key max**, so concurrent real-money purchases on two devices can never collapse into one. `totalCoinsPurchased` is the sum of the slots. | `Meta/Profile.swift:72`, `:86`; `Meta/ProfileStore.swift:53` |
| **device slot / `pr.device.id`** | A per-install UUID stored in **device-local** `UserDefaults`, deliberately *outside* the synced profile, used as the G-counter key. Regenerated on reinstall. | `Meta/ProfileStore.swift:53` |
| **KVS** | `NSUbiquitousKeyValueStore` — Apple's small iCloud key/value store. Here it holds the **whole profile JSON** under the key `pr.profile.v1` (the same key used for device-local `UserDefaults`). | `Meta/ProfileStore.swift:14`, `:20`, `:36` |
| **`merged(local:remote:)`** | The pure two-way conflict resolver run when `didChangeExternallyNotification` fires. Field strategies: `max` for lifetime scalars, **per-key max** for `missionProgress` / `achievementTier` / `bestDistanceByWorld` / `coinsPurchasedByDevice`, union for sets, OR for one-time flags. **Consumable inventory (`slowMoCharges`, `speedUpCharges`, `shieldCharges`, `headStartCharges`, `coinSurgeCharges`) is device-local and NOT merged** — a `max()` merge would resurrect spent charges. | `Meta/ProfileStore.swift:657`; `Meta/Profile.swift:20-25` |
| **`sanitized`** | The load-time hardening pass. It does exactly two things: clamp future-dated timestamps to `now`, and heal an unowned `selectedSkin`. **The only validation applied to loaded data.** | `Meta/ProfileStore.swift:70` |
| **clamp (clock-rollback clamp)** | `min(storedDate, now)` — a future-dated timestamp reads as "just now", so setting the device clock forward cannot farm daily/chest rewards. All reward timestamps are clamped (iron rule 9). | `Meta/ProfileStore.swift:70-88` |
| **replay dedupe** | `grantedTransactionIDs` + `applyOncePerTransaction`: the StoreKit transaction id is recorded in the **same `mutate`** as the grant, so a `Transaction.updates` redelivery is a no-op. The set is bounded to the newest 512. | `Meta/ProfileStore.swift:161`; `Meta/Profile.swift:73`, `:93-103` |
| **StoreState / availability** | `loading` / `ready` / `notConfigured` / `offline`. **`notConfigured` is not an error** — the products request *succeeded* but returned a zero/partial catalog (pre-App-Store-Connect). It shows fallback prices plus a quiet "PRICES SHOWN · APP STORE SETUP PENDING" footnote (owner decree 3). `offline` is the only state that auto-retries. | `IAP/IAPManager.swift`; `UI/ShopView.swift` |
| **UTC day key** | `"yyyy-MM-dd"` in UTC — the rollover unit for missions, the daily challenge, and the played-days calendar. Related: `ProfileStore.daysSinceEpoch(_:)`, used as the Game Center leaderboard context and the featured-skin day seed. | `Meta/Profile.swift:64`; `Meta/ProfileStore.swift:359` |
| **daily challenge tier** | A **local, offline-friendly** placement reward (100 / 150 / 250 coins; max 500/day), ratcheted by the `challengeRewardTier` watermark. | `Meta/Profile.swift:65` |
| **recurring leaderboard** | `prismrush.daily`, an App Store Connect leaderboard configured to reset daily. The app submits `core.score` with `context = daysSinceEpoch(UTC)`. The all-time board is `prismrush.best`. | `Services/GameCenterService.swift` |

---

## 5. Build / process vocabulary

| term | definition | lives in |
|---|---|---|
| **xcodegen** | The tool that **generates `PrismRush.xcodeproj` from `project.yml`**. The `.xcodeproj` is a build artifact — edit `project.yml`, never the project file. `Tools/build.sh` and `Tools/ci.sh` both run `xcodegen generate` first. | `project.yml`; `Tools/build.sh`, `Tools/ci.sh` |
| **SPM harness** | `Package.swift` — the Linux/CI-testable subset. It compiles **only** `Core/`, four `Meta/` files, and `Audio/Synth.swift`. Anything touching UIKit / RealityKit / SwiftUI / StoreKit / AVFoundation / GameKit is **not even type-checked** there. A real `swift test -c release` executes **178 tests in ~7.3 s** (measured; `CLAUDE.md`'s "89 tests" is stale — see §7). | `Package.swift`; `.github/workflows/core-tests.yml` |
| **`build-for-testing` / `test-without-building`** | The two-phase `xcodebuild` split that lets CI compile every layer against `generic/platform=iOS Simulator` (no device needed) and only then require a booted simulator. | `Tools/ci.sh` |
| **launch hook** | A `PR_*` environment variable read at launch (or sheet-appear) that seeds deterministic state for QA, screenshots and XCUITests. **These are compiled into the production binary** — they are `ProcessInfo` reads, not `#if DEBUG`. Full table below. | mostly `UI/GameView.swift:102-250` |
| **human gate** | A step only the account holder can perform: Apple Developer enrollment, App Store Connect records, IAP product creation, leaderboard creation, the privacy questionnaire, a signed archive. Tracked in `state.md` §HUMAN GATES and both ship docs. | `state.md`; `docs/SHIP_CHECKLIST.md` |
| **decree (owner decree)** | A product law stated by the owner in `CLAUDE.md` §"Owner decrees". **Overrides every design doc, spec and R-decision.** Six exist: (1) a character never changes identity with the world, (2) previews never lie, (3) no broken-looking states for expected situations, (4) everything on screen leads somewhere, (5) zero ads / no dark patterns, (6) clarity beats spectacle. When a doc conflicts with a decree, **the doc is wrong** — amend the doc. | `CLAUDE.md` |
| **iron rule** | One of ten engineering invariants in `CLAUDE.md` §"Iron rules": (1) Core purity, (2) seeded RNG only, (3) bot-green + `layoutVersion` bump, (4) pattern order load-bearing, (5) G3 observation, (6) zero binary assets, (7) `decodeIfPresent ?? default`, (8) Swift 6 strict concurrency + `MainActor.assumeIsolated`, (9) per-death economy deltas, (10) checkpoint/challenge gating. | `CLAUDE.md` |
| **G3** | The SwiftUI observation anti-pattern ban (iron rule 5): never `@State` a shared `@Observable`, never snapshot `store.profile` into a `let` at the top of `body`. Named after item G3 in `reports/CRITIQUE.md`. This exact anti-pattern shipped three v1.0 bugs. | `CLAUDE.md`; `reports/CRITIQUE.md` |
| **R-decision** | A numbered conflict resolution in `V13_SPEC.md` §R (R1…R17), settling disagreements between the four `DESIGN_*.md` docs. **Outranked by decrees.** | `reports/design/V13_SPEC.md` |
| **D-finding** | An `AUDIT_intent.md` finding id + severity: `DECREE-VIOLATION` / `MISMATCH` / `GAP` / `NOTE` (e.g. D1-1 = the Prism chameleon cluster, D6-1/D6-2 = the first-run gate). | `reports/AUDIT_intent.md` |
| **isolation domain** | The actor an object's state belongs to. This app has exactly **one**: `@MainActor`. Nothing runs concurrently with anything else except at `await` suspension points inside StoreKit/GameKit calls. | project-wide |
| **escape hatch** | A construct that *asserts* or *bypasses* isolation instead of proving it. This codebase uses only the **trapping** kind — `MainActor.assumeIsolated` (9 sites; being wrong is a `fatalError`, not a data race). It uses **no** `@unchecked Sendable` and **no** `nonisolated(unsafe)`. | `scratch/trace-concurrency.md` §2 |

### 5.1 Every `PR_*` launch hook in the repo

Grep source of truth: `grep -rn "PR_[A-Z_]*" PrismRush/ UITests/ Tools/`.
App-side hooks are read with `ProcessInfo.processInfo.environment[...]`; via `simctl` they are passed
as `SIMCTL_CHILD_PR_*`.

**App hooks (compiled into the shipping binary):**

| hook | value | what it does | site |
|---|---|---|---|
| `PR_AUTOPLAY` | `"1"` | Starts a run at launch driven by the `Autopilot` bot, seed 7. | `UI/GameView.swift:102`, `:212` |
| `PR_DEMO` | `"1"` | Autoplay **plus** a forced death ~6 s in (`GameCore.debugDie`), so `applyRunSummary` has run — the game-over screenshot/UITest path. | `UI/GameView.swift:103`, `:212`; `Core/GameCore.swift:586` |
| `PR_DEMOPROFILE` | `"1"` | Pins an **exact** demo profile (8,000 coins, `maxWorldReached = 6`, no purchased worlds, three owned skins, all auto-grant skins stripped, `totalXP = 0`, the whole achievement ladder pinned). Exact pins, not max-folds — earlier CI cycles must not flip UI-test outcomes. | `UI/GameView.swift:146-190` |
| `PR_SKIN` | skin id | Force-owns and equips a skin so an autoplay run renders that character's rig (the in-game half of the crest/aura decree-2 check). | `UI/GameView.swift:193-197` |
| `PR_WORLD` | `Int > 0` | Starts the run **already inside world n** (`beginRun(fromWorld:)`, seed 7) for sky/decor verification. Bypasses the first-run tutorial gate. Combines with `PR_AUTOPLAY`. | `UI/GameView.swift:213-217` |
| `PR_SHIELD` | `"1"` | Spawns a shield 5 m ahead **and** deploys one immediately, so the HUD chip + in-world dome both show. | `UI/GameView.swift:219-222` |
| `PR_SNEAKERS` | `"1"` | Arms Super Sneakers (`debugActivateSuperSneakers`) **and** drops one on the track 6 m ahead. Needs `PR_WORLD`/`PR_AUTOPLAY` to actually be in a run. | `UI/GameView.swift:224-228`; `Core/GameCore.swift:589` |
| `PR_DEEPWORLDS` | `"1"` | **(previously undocumented)** Raises `maxWorldReached` to at least **14**, so the Worlds ladder shows the evolved cycles past 12. Screenshot/debug only. | `UI/GameView.swift:229-232` |
| `PR_FIRSTRUN` | `"1"` | **(previously undocumented)** Pins a true zero-run profile (`totalRuns = 0`, `bestScore = 0`, `core.best = 0`) so the first-run gate + FIRST RUN chip flows are testable regardless of what earlier CI cycles banked on the simulator. | `UI/GameView.swift:233-238`; `UITests/InteractionUITests.swift:217-223` |
| `PR_SCREEN` | `characters` \| `shop` \| `levels` \| `stats` \| `settings` \| `missions` (all six `MetaScreen` cases) | Opens a meta screen directly at launch for screenshots. | `UI/GameView.swift:240-251` |
| `PR_FOCUS` | skin id | With `PR_SCREEN=characters`, opens the character screen pre-focused on that skin. | `UI/GameView.swift:242-245` |
| `PR_SKIP_SPLASH` | `"1"` | Boots straight to the hub, skipping the launch splash. QA/screenshot/XCUITest only. | `UI/GameView.swift:921-923`; `UITests/InteractionUITests.swift:15` |
| `PR_TUTORIAL` | `"1"` | Forces the in-context control hints on even when `totalRuns > 0` and even under autoplay (which normally suppresses them). | `UI/GameView.swift:412-414` |
| `PR_PLAYCONFIRM` | `Int` | Auto-opens the Worlds play-confirm card for world n. Screenshot hook. | `UI/LevelSelectView.swift:71-74` |
| `PR_POWERUPS` | `"1"` | Auto-opens the Power-Ups catalog sheet inside Settings. Screenshot hook. | `UI/SettingsView.swift:65-67` |
| `PR_MYSTERYBOX` | `"1"` | Auto-opens the Mystery Box sheet in the Shop. Screenshot hook. | `UI/ShopView.swift:56` |
| `PR_BUYPACK` | pack id | Auto-fires the `PackRewardBurst` for that coin pack (screenshot hook "S1"); falls back to the first pack on an unknown id. | `UI/ShopView.swift:57-59` |

**Tooling hooks (shell scripts only — not read by the app):**

| hook | default | what it does | site |
|---|---|---|---|
| `PR_SIM_NAME` | `iPhone 17 Pro` | Simulator device name for build/test. | `Tools/build.sh:7`, `Tools/ci.sh:19` |
| `PR_SIM_OS` | `26.5` | Simulator OS version for build/test. | `Tools/build.sh:8`, `Tools/ci.sh:20` |
| `PR_SIM_UDID` | `10C15FE0-…906DF3` | Explicit simulator UDID for the QA screenshot script. | `Tools/qa.sh:7` |
| `PR_SIM_69_UDID` | `52DF5467-…9062DF` | The 6.9" simulator UDID for App Store screenshot capture. | `Tools/screenshots.sh:22` |
| `PR_SHOT_DELAY` | `4` (qa) / `3` (screenshots) | Seconds to wait after launch before capturing. | `Tools/qa.sh:19`, `Tools/screenshots.sh:26` |

---

## 6. "Do not confuse with" — the pairs that bite

| A | B | the difference |
|---|---|---|
| **`distance`** | **`traveledDistance`** | `distance` is the absolute odometer (matches world labels, HUD meters, keeps climbing during post-death decel). `traveledDistance = distance − scoreOffset` is the fair this-attempt metres (score, XP). On a checkpoint run they differ by thousands at t=0. |
| **`speed`** | **`effectiveSpeed`** / **`rampSpeed`** | `GameCore.speed` and the snapshot's `rampSpeed` are the same raw difficulty ramp. `effectiveSpeed` (= snapshot `speed`) is that ramp after chrono ×0.65 then boost ×1.3-capped-36. Scroll and arrival math use `effectiveSpeed`; HUD/debug uses `rampSpeed`. |
| **gem** | **coin** | Gem = the octahedron on the track + the run-scoped `gemCount`. Coin = the persistent `Profile.coins` balance. Gems become coins only in `recordRunResults`. `Core/` never mentions coins. |
| **world** | **world family** | World = unbounded ordinal (`floor(distance/800)`). Family = `ordinal mod 12`, the cosmetic palette/sky set. `worldOrdinal` in the snapshot is the world; `worldFrom`/`worldTo` are families. |
| **skin** | **character** | Same thing. `Skin` is the type; "character" is the UI word. |
| **deploy** | **pickup** | Deploy = spending a *banked* charge from a HUD button (slow-mo / speed-up / shield). Pickup = grabbing an object off the track. The **road shield pickup is a separate thing from the shield deploy charge**. |
| **deploy / pickup** | **loadout** | Loadout = a *pre-run* consumable armed on the hub (Head Start, Coin Surge), consumed at `beginRun`. |
| **`EntityState`** | RealityKit **`Entity`** | `EntityState` is pure per-frame data in `Core/Models.swift`. `Entity` is the pooled RealityKit render node. The core's own live records (`activeObstacles` etc.) are a third thing. |
| **daily challenge** | **Daily Rush** | Same feature; "daily challenge" is the code/Core word, "Daily Rush" is the UI label. |
| **reach** | **startable** | Reach (`maxWorldReached`) advances only by playing. Startable = reached **or** purchased. |
| **`dt`** | **`sdt`** | `dt` is the sim's fixed `1/120 s`. `sdt` is the renderer's *clamped wall-clock* delta `max(min(lastDt,1/30),1/240)`. |
| **card** (render) | **card** (UI) | Render: a flat single-sided XY sky mesh. UI: a `NeonCard` surface. Always qualify. |

---

## 7. Terms the codebase itself uses inconsistently

Flagged so a future session does not "fix" one side and break the other.

1. **`world` mod-3 vs mod-12.** `GameCore.stepWorld` folds the ordinal by `Tuning.worldFamilyCount`
   (12) at `Core/GameCore.swift:290-292`, but the **checkpoint start path still folds by 3**:
   `let wi = ((wn % 3) + 3) % 3` at `Core/GameCore.swift:110`. A checkpoint start therefore seeds
   `world`/`worldFrom`/`worldTo` with a *different family index* than a run that walks into the same
   world normally — until the next world boundary corrects it.
   The doc comment at `Core/Models.swift:66-68` ("worldFrom/To are the 0–2 palette family") and
   `scratch/render.md:234`/`:408` (which assert the same) are **stale**: the steady-state fold is 12.
   `scratch/render.md` is the file that is wrong here; the source was checked.

2. **Pattern count: 12 vs 14.** `CLAUDE.md` §Architecture says "12 spawn patterns".
   `Patterns.count == 14` (`Core/Patterns.swift:27`), indices 0…13, and `Spawner.maxIndex` returns up
   to `Patterns.count`. **14 is correct.**

3. **Test counts.** `CLAUDE.md` §Build & test says "95 tests (89 unit + 6 XCUITest)" and
   "`swift test -c release` → 89 tests". A real measured run is **178 SPM tests in 7.28 s**, and
   there are **11** XCUITests, not 6 (`scratch/tests-tools.md` §MEASURED TEST RUN,
   `UITests/InteractionUITests.swift`). `docs-claims.md` quotes 196 (185 + 11) for v1.6. Treat every
   test count in `CLAUDE.md` as stale; re-measure before quoting.

4. **"tier"** means at least five different things:
   spawner difficulty tier (`Spawner.maxIndex`, 5 rungs) · achievement tier
   (`Profile.achievementTier`, `Mission.Scope.lifetimeTiered`) · daily-challenge placement tier
   (`Profile.challengeRewardTier`, 0…3) · skin rarity tier (`Skin.Rarity`) · the `Skin.Unlock
   .achievement(id:tier:)` requirement. **Always qualify it.**

5. **"slot"** means: a `WorldDecor.Slot` (scenery group) · a mission slot (one of 3 daily/weekly
   drawn missions) · a G-counter device slot (`coinsPurchasedByDevice[deviceID]`) · the Shop's hero
   slot. **Always qualify it.**

6. **"streak"** means: `GameCore.streak` (consecutive gems → multiplier) · `flowStreak`
   (near-misses → flow surge) · `Profile.loginStreak` (consecutive daily-bonus days) ·
   `Profile.bestStreak` (lifetime best gem streak) · the `streak:` payload on
   `FXEvent.gemCollected`. **Always qualify it.**

7. **"cycle"** means: the world cycle `worldOrdinal / 12` (palette evolution, sky density) · the
   music cycle `world / 12` → `layer` in `Audio/Music.swift` (dead in production — `world` is pinned
   to 0). Same formula, different subsystems.

8. **"gap"** means: the inter-pattern empty distance (`Spawner.gap`) · the open safe lane of a
   `splitBar` (`Core/Models.swift:19`).

9. **"entitlement"** means: an IAP non-consumable the player owns · the file
   `PrismRush/Support/PrismRush.entitlements` (iCloud KVS, Game Center, Sign in with Apple
   capabilities). Unrelated.

10. **"hub"** means `MenuView` in `scratch/ui-meta.md` but `GameModel` in `scratch/ui-game.md`.
    Prefer "menu screen" and "GameModel" respectively.

11. **"tease" vs `silhouette`.** The locked-character render is called a *tease* (full colour, 0.45
    opacity) since v1.4, but the parameter is still named `silhouette` from the pre-v1.4 dark-cutout
    era. The name is historical; the behaviour is a tease.

12. **`layoutVersion` "currently N".** `scratch/docs-claims.md` says 7 and so does the source
    (`Core/DailyChallenge.swift:23`) — but `Core/Tuning.swift:57` still carries a v1.6 comment
    saying "it rides the layoutVersion 3→4 bump", which was true when that block was written and is
    now three bumps behind. The **default argument of `DailyChallenge.seed` is the only source of
    truth**.
