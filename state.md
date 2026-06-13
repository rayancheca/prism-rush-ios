# PRISM RUSH — Build State

> Single source of truth for session resumability. On any fresh session: read this first, then continue.
> Last updated: end of **v1.4.2 (owner-decree compliance — Prism identity fix + audit waves)**.

## v1.5 — "Depth & Clarity" overhaul (in progress, 2026-06-12)
Owner-driven redesign. Full plan + locked decisions: `reports/design/V15_PLAN.md`. Order: (1) home/
menu UX + splash + music → (2) 12 distinct worlds → (3) gameplay difficulty + scoring clarity →
(4) power-ups + tutorial. Decisions: characters stay cosmetic identity **+** honest higher-tier
passive **+** equippable power-up loadout; **12 distinct themed worlds** then evolve; in-run HUD =
**meters primary** (score/coins/×N/live-XP secondary).

**Phase 1 — DONE (verified: Mac BUILD OK, 174/174 tests, on-sim screenshots):**
- Splash screen (`UI/SplashView.swift`): character floats full-size + uncropped, wordmark, name
  pill, breathing "TAP TO START"; calm ambient bed plays from launch. First tap fades to the hub.
  `PR_SKIP_SPLASH=1` (QA/UITests) boots straight to the hub.
- Character cutoff fix: `AnimatedCharacterSwatch` gained `heightScale`/`verticalAnchor` (defaults
  hold every grid byte-identical); `CharacterHeroStage` renders in a 1.85× canvas (anchor 0.66) so
  tall antennas + up-bob never crop; `showsReflection` toggle (splash off → no "box").
- Menu hub (`UI/MenuView.swift`): **settings gear surfaced top-right** (was 3 taps deep in Profile);
  nav cards now **color-coded** (Characters cyan / Shop gold / Worlds magenta) with tinted icon
  chips — no longer uniform gray. `onSettings` → `model.open(.settings)`.
- Top-bar conflict fixed (`UI/GameView.swift`): the floating mute/pause cluster is **hidden in
  `.menu`** (it sat on top of the coin badge — the owner's "hidden circular button behind coins").
- Menu music (`Audio/Music.swift` `start(targetVolume:)`, `SynthEngine.musicStart(calm:)`): hub/
  splash run the sequencer as a calm 0.4 bed; `returnToMenu` restarts it instead of going silent;
  a run still starts the full 0.85 bed.

**Phase 1 follow-ups (DONE):** RewardsBar color-coded to match the nav; Daily Rush text overflow
fixed (shrink-to-fit); split **Menu music vs Game music** volume (Profile.menuMusicVolume +
SynthEngine calm/run context + two Settings sliders).

**Phase 2 — 12 distinct worlds (IN PROGRESS).** Blueprint: `reports/design/V15_WORLDS.md` (multi-agent
design pass). Two CRITICAL resolutions baked in: World 12 ships radiant-white-on-deep-violet (a white
bg would break the dark-bg-only obstacle/ground/gem/FX materials); `evolvedPalette` moves BOTH the
family AND cycle divisor to worlds.count (else worlds 0–11 get spurious roman suffixes).
- **2a DONE** (commit 1c76022): `Theme.worlds` 3→12 distinct (Pulse City, Geode Deep, Solar Sands,
  Orbital Drift, Tidal Glow, Ashfall, Borealis, Datastream, Bloomfall, Eventide, Tempest,
  Singularity); `Tuning.worldFamilyCount=12`; `stepWorld` modulus (RNG-neutral — bot green, NO
  layoutVersion bump); `WorldPaletteTests` guards. Loop broken: level-select shows 12 distinct
  named/colored worlds. Sky/decor for 4–12 borrow the 3 families recolored (stub) until bespoke.
- **2b DONE**: **Orbital Drift** bespoke sky family — `OrbitalSky.swift` (planet limb + drifting
  tumbling astronaut + satellites + starfield), the scalable per-world-object pattern; `WorldSky`
  gains a `skyFamily()` map + `case 3` delegate (+ 12-case switch, no silent default); `WorldDecor`
  clears Orbital's sides (sparse space); `WorldPreviewCanvas.drawOrbital` so the card matches
  (decree 2). Verified on-sim: astronaut + planet visible in-game (PR_WORLD=3) AND on the card.

- **2c DONE — all 8 remaining bespoke worlds.** Each is a self-contained `BespokeSky`-conforming
  object in its own file (Tidal/Ashfall/Borealis/Datastream/Bloomfall/Eventide/Tempest/Singularity
  Sky.swift), authored in parallel from the OrbitalSky template + a build/QA gate (Swift 6
  @MainActor-class, pool caps, local-seeded RNG, RM-gated, procedural+UnlitMaterial only).
  `WorldSky` now drives all 9 bespoke families through one `[any BespokeSky]` array (proto in
  `BespokeSky.swift`); `skyFamily()` is the folded ordinal; `WorldDecor.style` clears sides for all
  bespoke worlds. Two new `ProceduralMesh` factories: `tentacleStrip` (jellyfish), `gridCard`
  (Tron). 8 matching `WorldPreviewCanvas.draw*` cards (decree 2). Verified on-sim: all 8 render
  distinctly (jellyfish, volcano+lava, aurora, Tron grid, blossoms+moon, black-hole accretion,
  rain/storm, radiant rainbow core); Mac test 178/178, 200-seed bot green.

**Phase 2 COMPLETE** — 12 distinct themed worlds, each its own palette + name + bespoke sky motif.
Optional later: per-world music (`Synth.beds` 12-entry table); richer per-world SIDE decor.

**Phase 3 — scoring + gameplay:**
- **3a DONE** (commit 9e003cd): meters-primary HUD — big number = absolute distance (matches world
  labels, no more "0" at a 3,200 m checkpoint); SCORE a separate secondary line; live LV/XP bar at
  the bottom. `GameSnapshot.traveledDistance` added (pure output field).
- **3b/3c — gameplay difficulty: NOT shipped (reverted).** The speed-ramp fix (traveled-based) broke
  a load-bearing contract — gem-arc placement, boost cap, difficulty curve all assume
  `speed = f(absolute distance)`; ArcCollectionTests + BoostTests caught it; reverted clean. The
  real slide→jump fairness fix is a PATTERN-SPACING change (e.g. the gauntlet packs a slide-bar +
  jump-block too tight at max speed) → needs a `DailyChallenge.layoutVersion` 2→3 bump (pre-armed
  golden exists at 0xB51F_E337_DB06_ED2F) + bot re-verify + golden re-pin. **Owner chose to SKIP
  gameplay tuning for now** (subjective + protected sim) and move to Phase 4; revisit once playable
  on-device. NOTE: jump already cancels an active slide (`jump()` sets slideT=0 when grounded), so
  the mechanic is forgiving — the issue is the reaction window at max speed.

**Phase 4 — power-ups + tutorial:**
- **4a DONE** (commit b4ae596): active-SHIELD HUD badge (the "how do I know I have a shield?" gap).
  PR_SHIELD=1 sim QA hook.
- **4b DONE** (commit a6d1f00): discoverable `PowerUpsView` (every power-up: icon/effect/duration +
  revive), reached from a clear "Power-Ups" row in Settings (2 taps from the prominent hub gear).
- **4c DONE** (commit ba226f4): just-in-time first-run tutorial — contextual "SWIPE UP/DOWN/SIDE"
  prompts the first time each obstacle type approaches on a genuine first run (totalRuns==0, not
  autoplay). Pure presentation off the snapshot (bot-unaffected). PR_TUTORIAL=1 QA hook.
- **4d DONE** (commit 899bdb6): **manual-trigger slow-mo** — bank charges, deploy on demand via a
  thumb-reachable bottom-left HUD button (hourglass + count). `GameCore.activateSlowMo()` (RNG-free,
  no-stack), `Profile.slowMoCharges` (default 2, +2 per level-up), `GameModel.deploySlowMo()/
  canDeploySlowMo`. NOT a change to the auto-chrono pickup → bot untouched. PowerUpTests added.
- **Owner decision:** characters stay **pure cosmetic** — NO passives.

**Phase 5 — deferred power-up backlog (v1.5 continuation, 2026-06-12):**
- **5a DONE — Super Sneakers** (in-run higher-jump track pickup). Collect the amber winged-
  chevron → jumps launch at `Tuning.superSneakersJumpMult` ×1.25 velocity (≈1.56× apex) for
  `superSneakersDuration` 8 s. **Determinism:** added by RE-BANDING pattern 7's existing single
  `rng.unit()` (shield<0.35 / magnet<0.70 / doubler<0.88 / sneakers else) — **zero new RNG
  calls**, so `PatternOrderTests` count array `[…,7:2,…]` is unchanged and the obstacle geometry
  is byte-identical (only the pickup KIND in pattern-7 slots shifts). `DailyChallenge.layoutVersion`
  **2→3** (consumed the pre-armed `0xB51F…ED2F`); goldens re-pinned in DailyChallengeTests +
  MissionsTests; explicit v1/v2 pins kept; fresh **layoutVersion 4 pre-arm = `0x2E28_5014_7596_8B7D`**.
  **Bot-safe by construction:** the Autopilot ignores all pickups and never collects one, so the
  buff is never active in the 200-seed soak — its air-slam arc model + `ArcCollectionTests` stay on
  the base jump. Ballistic gem-arc/ring placement deliberately never reads the buff (over-clears,
  never under-places). Core: `superSneakersT` timer (refresh, no-stack; preserved on revive like
  the other earned timers; cleared in reset), `launchVelocity` helper gates `jump()` + the buffered
  branch, `.sneakersEnded` edge, `snapshot.sneakersRemaining`, `debugActivateSuperSneakers`. Render:
  amber double-chevron pickup mesh + pickup burst + snapshot-driven amber FEET sparks (the identity
  trail stays `skinTrailColor` — decree 1), prewarm. HUD: depletion ring (`arrow.up.circle.fill`).
  Catalog: `PowerUpsView` row (timing from Tuning). `GameView`: pickup popup + sound (**reuses
  `.boostStart`** — adversarial-review LOW, deferred: a dedicated SFX would remove the shared-sound
  ambiguity with Overdrive), `PR_SNEAKERS` screenshot hook. Verified: **SPM 164/164** (200-seed bot
  green), **Mac 171 unit + 11 XCUITest**, on-sim (`reports/shots/v15/sneakers_active_*.png` — active
  ring + amber sparks across Orbital Drift). Adversarial 4-lens review: 0 CRITICAL/HIGH/MEDIUM.

### ▶ RESUME HERE (next session)
Continuing the deferred power-up backlog on Fable 5 (ultracode). All committed to `main`, NOT
pushed. Last verified: **SPM 164/164** (incl. 200-seed bot), **Mac 171 unit + 11 XCUITest**.
Remaining backlog (owner said "keep working on what's next, push at the end"):
1. ~~**Super Sneakers** (higher-jump in-run pickup)~~ **DONE (Phase 5a above)** — layoutVersion is now
   3; next pre-arm is 4 (`0x2E28_5014_7596_8B7D`).
2. **NEXT: pre-run consumables** — **Head Start** (launch with a few seconds of Overdrive boost;
   leaderboard-safe, does NOT route through `fromWorld`/`usedCheckpoint`) + **Score Booster** (run-
   scoped payout multiplier — implement as a fair, honest variant; see decision note). No spawner/RNG
   touch → no layoutVersion bump. Needs a lightweight pre-run loadout arm UI + consume in `beginRun`.
3. **Shop coin-spend items**: **Mystery Box** coin gacha (meta-side RNG, NOT the Core sim RNG — use
   the `openFreeChest(reward:)` `Int.random`+override precedent), **slow-mo refill pack**, consumable
   packs. Coin-spend (NOT IAP) — a new `ShopConsumables`/section using `coinPricePill` + `spendCoins`.
4. Per-world themed music (`Synth.beds` 12-entry table — Synth.swift pure/Linux-tested; MUST keep
   cycle-0 worlds 0/1/2 byte-identical per SynthTests goldens).
5. Gameplay difficulty / slide→jump fairness pass (protected sim — layoutVersion bump; best after
   on-device play). Still deferred.
Then the **pre-push gate**: capture live `docs/screenshots/` golden-path set, then `git push`.
- Deferred polish: dedicated Super Sneakers SFX (currently reuses `.boostStart`).
Invariants to keep: iron rules 2/3/4 (no run-RNG/spawn change without a layoutVersion bump + bot
green), decrees 1/2/6, Swift 6 @MainActor, zero binary assets. Verify every increment: SPM bot +
Mac `xcodebuild test` + an on-sim screenshot (PR_SKIP_SPLASH / PR_WORLD / PR_SCREEN / PR_SHIELD /
PR_TUTORIAL hooks). Never screenshot the dev sim while `xcodebuild test` runs on it.
- **DEFERRED (owner did not select; revisit when asked):** manual-trigger saved power-up (build as a
  NEW consumable + tappable HUD button, NOT a change to the auto-chrono or the bot breaks); new
  power-ups (super sneakers/higher jump, head start, score booster, mystery box); equippable loadout;
  per-world themed music; the gameplay difficulty / slide→jump pattern-fairness pass (needs a
  layoutVersion 2→3 bump + bot re-verify + golden re-pin — subjective, best after on-device play).

## v1.5 session status (2026-06-12)
All work committed to `main`, **NOT pushed** (owner holding the push). Commits: 62352d4, 66f9f24,
50d767b (Phase 1 + follow-ups) · 1c76022, 9d699bf, 43d80e0 (Phase 2 — 12 worlds) · 9e003cd (3a HUD)
· b4ae596, a6d1f00, ba226f4 (4a/4b/4c) · 8958e41 (docs). Mac `xcodebuild test` 178/178, SPM 160/160
incl. the 200-seed bot. No Core sim-logic / spawn-RNG change shipped; `DailyChallenge.layoutVersion`
unchanged. Pre-push gate (live screenshots in `docs/screenshots/`) still TODO before any GitHub push.

## v1.4.3 — CODE_REVIEW.md §20 implementation (in progress, 2026-06-12)
Executing the prioritized plan from `CODE_REVIEW.md` (Opus 4.8 strict pass, 8.7/10). Ordered steps;
each verified + committed independently. The worlds work (step 2) is **purely visual** — no Core/,
no spawn-RNG consumption, `DailyChallenge.layoutVersion` unchanged (the sim is untouched, so the
200-seed bot stays green and every seed stays byte-stable).

| Step | Scope | Status |
|---|---|---|
| 1 | Doc/claim fixes: README test split (147+11), IAP 5→7, "zero hand-authored binary assets", "material-allocation-free"; `ci.sh` stale Phase-2 comment deleted; SUPERSEDED banners on `AGENT_docs.md` (privacy) + `AGENT_wiring.md` (daily board) | ✅ `4b9..` |
| 2 | **The worlds — distance-driven evolution** (M1): `Theme.evolvedPalette(ordinal:)` (hue-rotate ~49°/cycle + intensify + cycle-tier name) drives playfield/decor/previews/UI; `WorldSky` re-tint registry recolors set pieces per cycle at each boundary; `min(cycle,N)` clamps removed; `Synth.step` layers voices by cycle (fed `worldOrdinal`). Cycle 0 byte-identical. Evidence `reports/shots/v143/` (Caverns w1→4→7 teal→blue→violet). SPM 145✓, Mac BUILD OK. **No Core/ edits, no RNG, layoutVersion unchanged.** | ✅ 3 commits |
| 3 | macOS CI job (`.github/workflows/ios-build.yml`): macos-15, newest Xcode, xcodegen, `build-for-testing` (generic iOS Simulator — compiles renderer/audio/SwiftUI/StoreKit) + `PrismRushTests` unit bundle. Locally validated (`build-for-testing` → TEST BUILD SUCCEEDED); first push confirms the hosted runner. | ✅ |
| 4 | Pure `Meta/ShopValue.swift` (added to Package.swift): `coinsPerUnit`/`badge`, `featuredSkin`, `StoreState`+`StoreAvailability.afterLoad/afterThrow`. ShopView/IAPManager delegate (`Availability` = typealias). 15 Linux tests in `ShopValueTests`. | ✅ |
| 5 | Dynamic Type: `@ScaledMetric`-backed `Theme.scaledFont(size:weight:design:)`; all 35 hardcoded `.system(size:)` in ProfileView/HowToPlay/Pause migrated (copySize left to avoid double-scale). | ✅ |
| 6 | Deep solvability soak 10 → 64 seeds × 12,000 m (still ~5 s, bot green). | ✅ |
| 7 | `heroShell` generic (10 AnyView dropped); `revive()` comment honest (boost/flow reset, magnet/doubler/chrono carry over by design); Apple id + name → Keychain (`Services/Keychain.swift`, one-time UserDefaults migration). | ✅ |
| 8 | Re-captured `docs/screenshots/11_characters.png` (current 24-roster) + caption fix; deep-world evolution evidence in `reports/shots/v143/`. Full curated 13-shot walkthrough re-capture left as optional polish (cycle-0 worlds unchanged so existing world shots stay accurate). | ✅ (partial) |

**Final gate (v1.4.3):** Full Mac `xcodebuild test` → **TEST SUCCEEDED, 174/174** (163 unit + 11
XCUITest, iPhone 17 Pro · iOS 26.5). SPM `swift test -c release` 160 green incl. 200-seed bot + the
widened 64-seed deep soak. Mac `./Tools/build.sh` BUILD OK. **No Core/ sim-logic change, no spawn
RNG consumed, `DailyChallenge.layoutVersion` unchanged** — the worlds work is purely visual/audio.
Outstanding (human-only): the on-device feel pass (§v1.3 checklist) + App Store Connect gates
(`docs/SHIP_CHECKLIST.md`); the new macOS CI job's first hosted run to confirm the runner toolchain.

## v1.4.2 — owner decrees enforced (AUDIT_intent fix fleet, 2026-06-11)
The six owner decrees landed in `CLAUDE.md` (product law, overriding every design doc) together
with the read-only `reports/AUDIT_intent.md` sweep (`bf75acd`); four serialized fix waves then
cleared it:

| Commit | Scope |
|---|---|
| `7349a19` | **Decree 1 — the 7-surface chameleon kill.** Prism never follows the world: bodyHex-0 sentinel retired (authored `0x00F5FF`/`0xFF2BD6` + `isPrismatic`), pure `SkinCatalog.prismaticColor` 8 s shimmer shared by previews AND rig, `followsWorld` computed deleted, renderer world-tint branches + all 7 world-accent FX fallbacks deleted (`skinTrailColor` non-optional; `trailHex nil` repurposed = shimmer hue), legacy 3-arg `applySkin` shim + dead `struct CharacterSwatch` deleted, SkinCatalogTests pins flipped in the same commit |
| `c173f37` | Wave 2A — preview/rig fidelity (D2-1/2/3/5 + D2-4): antenna stem = `antennaHex` both sides, per-skin blink range in-run, sway = preview's `bobSpeed·2π·0.8`, shared `CharacterProportions` contract (+ `octahedron(rx:ry:rz:)`, CharacterParityTests), trail wisp in every swatch (Aurora's two-tone sell finally visible at the buy moment) |
| `37ea7f2` | Wave 2B — state honesty (D3-1/3-3/6-5): canonical `ProfileStore.equippedSkinID` resolver + self-heal in `sanitized()`/`merged()` (unowned-selection contradiction can't persist), menu chip + ambient tint → `highestStartableWorld` (purchases show on the hub; display only), shop locked-skins render the same tease as select |
| `0bf0094` | Wave 2C — first-run flow + HUD calm (D6-1/2/3/4/6/7, D3-2, D5-2/3, D2-7): `routeRun()` tutorial gate covers ALL run entrances, HowToPlay X never force-starts a run (info mode = GOT IT), new WORLDS card + decree-1 reassurance, DAILY RUSH "PLAY · ENDS H:MM", challenge-death fair-track caption, CLAIM ALL frozen-clock cascade, doubler upsell deferred to ≥3 runs, ghost chip floored at best ≥ 1,000, sub-second Overdrive ring dropped, tutorial numbers derived from `Tuning` |
| `a7632a2` | Wave 3 — doc-rot purge (D1-1 d/e/g, DR-1/DR-2, D2-6 record): V13_SPEC DECREE-1 REVOCATION + v1.4 amendments, DESIGN_characters §1.2 superseded + §8 QA inverted, DESIGN_uiux glow-disc/world-chip rescope, README v1.4–v1.4.2 section + honest PERFECT/chameleon copy |
| decree-review fix | The three audit items the waves dropped or half-landed: **D3-4** Eclipse body lightened `0x1A1A2E` → `0x2A2A4A` (catalog-only — swatch/tease/rig stay in lockstep; SkinCatalogTests pin flipped; on-device Caverns check stays on the QA list); **D2-6 completed** — the dead `MenuView` `onSettings`/`onDailyChallenge` params (third item of the audit's fix list, missed by `7349a19`) deleted, and the three v1.4.2 doc records that falsely claimed `7349a19` deleted them corrected (V13_SPEC R13 + §P, state.md decision log); **D3-1 completed** — `GameView.applyCurrentSkin()` rewired to the canonical `ProfileStore.equippedSkinID` resolver (the rewire `37ea7f2` promised to wave 2C; the run now shares the exact guard the menu/select/shop surfaces render from) |

**Test status: 158/158** via `./Tools/ci.sh` (CI GREEN re-measured at the decree-review fix on
the 10C15FE0 iPhone 17 Pro · iOS 26.5 sim: 147 unit + 11 XCUITest — the earlier "146 + 12"
split recorded at `0bf0094` had the same 158 total).
Evidence: `reports/shots/v142/` — Prism holds its own shimmer (never the world accent) across
the 800 m crossfade; menu hero + glow disc cycle in lockstep with the in-run body.

## v1.4.1 — shop conversion + honest pre-launch states (2026-06-11)
| Commit | Scope |
|---|---|
| `5951cb4` | IAP catalog 5 → 7 (Starter Bundle $1.99/3,000 — hidden after first purchase; Crate of Coins $19.99/40,000), four-state availability (loading/ready/notConfigured/offline — quiet "APP STORE SETUP PENDING" footnote instead of a red error), ShopView conversion layout (hero slot, 2×2 coin grid with COMPUTED value badges), first-purchase +50 % coin-pack bonus (flag flips in the same mutate as the payout) |
| `b0dbb14` | Review findings: per-device G-counter `coinsPurchasedByDevice` (an iCloud merge can never erase a paid grant), replay-idempotent grants via `grantedTransactionIDs`, "MOST POPULAR" → curated "BALANCED PICK" (no fabricated social proof), uniform price source for value badges, ask-to-buy starter hiding |

**Test status: 150/150** (140 unit + 10 XCUITest) via `./Tools/ci.sh`. Evidence: `reports/shots/v141/`.

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
**v1.4.2 DECREE COMPLIANCE COMPLETE** (sections above). The v1.3 content update below shipped per
the binding contract `reports/design/V13_SPEC.md` (where it disagrees with the four DESIGN_*.md
docs, the spec wins — and the owner decrees in `CLAUDE.md` now override the spec itself; see its
DECREE-1 REVOCATION addendum). What remains is the App Store ops track (unchanged — see §B below
and `docs/SHIP_CHECKLIST.md`).

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
Bolt trail end-to-end · ~~Prism crossfade regression~~ **[INVERTED v1.4.2 by decree 1 — the old
item guarded the violation; now: Prism's body colors/trail do NOT change across a world
crossfade, the fixed 8 s shimmer is the only motion]** · Eclipse readability on Caverns
**[body lightened to `0x2A2A4A` in the v1.4.2 decree-review fix (AUDIT D3-4, supersedes the §P
`0x232337` candidate) — device pass now just confirms it reads against all three world
backgrounds]** · Reduce Motion statics · Pebble vs Eclipse
silhouettes · 7/7 arc by feel · ring PERFECT timing · overdrive runway feel · flow surge
cadence · level-up burst · weekly board rollover · challenge tier toast.

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
  names, §W file ownership) — **as amended**: the owner decrees in `CLAUDE.md` override it, and
  its DECREE-1 REVOCATION + v1.4 amendment blocks (top of §R) record where. Legacy shims it parks
  (3-arg `applySkin`, defaulted MenuView params, `DailyChallengeCard` absorption) were ~~deleted
  in v1.4 (R13/§P parking lot)~~ **[CORRECTION (AUDIT D2-6): that deletion never happened in
  v1.4 — the shims shipped through v1.4/v1.4.1 behind stale "still referenced" comments. The
  3-arg shim + legacy `struct CharacterSwatch` were deleted in v1.4.2 `7349a19`; the dead
  MenuView `onSettings`/`onDailyChallenge` params survived that commit too and were deleted in
  the v1.4.2 decree-review fix after it]**.
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
