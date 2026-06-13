# v1.6 — "Power-ups, Polish & Progression" (in progress, 2026-06-13)

## ▶ PROGRESS (resume here)
**DONE + committed (NOT pushed yet — push at the very end after the screenshot gate):**
- Wall-vault + visible shoes (`7a9d217`); Wave-1 UX bugs — Head Start/coin-popup/revive/worlds-silhouette
  (`b2c505a`); worlds past 12 (`df1ee5a`); shield-break glass shatter (`3671c46`); power-up cadence
  (`c080046`, layoutVersion **3→4**); HUD rework + Speed-Up deploy
  (`699adeb`); stacked deploy layout + Shield deploy (`5a2355e`); world decor obstruction (`573e8d8`).
- Mystery Box reveal sequence (`1552ad9`) — odds screen + shake/swivel/burst/reward; PR_MYSTERYBOX hook.
- **Coin-path routing (G1)** (`42eb607`) — gap breadcrumb into each pattern's safe entry lane + pattern-7
  gem line. Zero RNG → layoutVersion **4→5**; 200-seed bot + 12k soak green; goldens re-pinned (next
  pre-arm `0xCF1D_7FAA_DFEF_898D` for v6). VERIFIED in-run (coin trail threads ahead of the player).
- **Rarity-themed crests + auras (C2)** (`93544d3`) — cosmetic Crest enum + hasAura, id-keyed overlay
  over the authored roster (legacy pins untouched). common plain → rare ears/floppy/fin → epic horns/
  crown → legendary crown/halo/horns + orbiting aura. crestHex falls back to body hue for dark antennas
  (Mono/Fang). Drawn by BOTH the swatch + the rig; VERIFIED in select + in-run (decree 2). Hooks
  PR_FOCUS / PR_SKIN.
- **Character-select carousel (C3)** (`cf8ed43`) — the hero card is now a paged slider through ALL
  characters with per-page unlock requirement + progress bar; rarity-coloured page dots. VERIFIED across
  coins/level/challenge gates.
- **Pack purchase reveal burst (S1)** (`bdd4306`) — coin-spend packs fire a ring/spark/medallion reveal
  (PackRewardBurst) on purchase, not just a toast. Hook PR_BUYPACK. VERIFIED.
- **Bespoke power-up glyphs + catalog (P3)** (`bc7edeb`) — `PowerUpGlyph` (10 procedural icons) across
  HUD chips, deploy buttons, the How-to-Play card + a Power-Ups catalog that now documents deploys +
  loadout. B4 meters label = by-design (no change). Hook `PR_POWERUPS`.
- **C3 carousel test fix** (`f263425`) — scoped `skinStageButton` id to the focused page.
- **Pre-push gate DONE + PUSHED** (`78d30be`): full suite green (185 unit + 11 XCUITest, 0 failures);
  v1.6 README section + live `docs/screenshots/20–25` + refreshed `11_characters.png`; pushed to origin/main.
- Gates green each step: SPM 178, Mac BUILD OK + full test suite. Sims: iPhone 17 Pro (dev) / 17 Pro Max (shots).

**v1.6 COMPLETE — entire line pushed to GitHub (origin/main @ 78d30be).** Next owner gate: App Store Connect.


Owner-driven, fed by a live play session. Single source of truth for v1.6 scope. Order = waves below.
**Iron-rule reminder:** any spawn-stream change batches into ONE `DailyChallenge.layoutVersion` 3→4
bump (pre-armed `0x2E28_5014_7596_8B7D`) + 200-seed bot re-verify + golden re-pin. Collision/visual/
UI changes that the bot never exercises need NO bump. Zero binary assets stays in force (owner asked
about AI-gen assets — recommendation: procedural, see §Assets).

## Wave 1 — fix what's broken (bugs)
- **B2 Wall-jump kills you → ✅ DONE** (`7a9d217`): Super Sneakers now vaults tall walls (height-aware
  `tallHit` gated on the active buff; bot byte-identical, no bump). Visible amber shoes on the feet.
- **B1 Head Start "does nothing"** — investigate the loadout arm→consume path; make arming unmistakable
  (clear ARMED state + confirmation) and the launch boost obviously felt. Possibly an AnyView/observation
  bug on the hub chip OR just unclear feedback. VERIFY on-device.
- **B3 Revive = "clears board, starts new"** — revive already KEEPS distance/score (folds the decel
  drift), clears nearby obstacles + grants a shield + respawns 70 ahead. Either a feel/clarity issue
  (reads as a restart) or a real bug. Investigate; make "continue" obviously continuous.
- **B4 Meters/score accuracy on a world-start** — checkpoint start sets distance=startDistance, score
  from 0 (scoreOffset). Confirm the HUD reads right per world; fix any mismatch.
- **B5 Coin popup "+50" but 1 coin** — the gold "+N" popup is SCORE points, not coins; reads as coins.
  Clarify (relabel/recolor, or show the coin gain) so points vs coins is unambiguous (decree 6).
- **B6 Worlds beyond 12 / "and beyond"** — after Singularity the run should keep evolving (Pulse City II
  with rotated palette per `evolvedPalette`), and the Worlds screen must SHOW that progression so buying
  worlds has a point. Investigate the cycle progression + worlds-screen display past 12.
- **B7 Worlds "square with 2 dots"** = `WorldPreviewCanvas.drawSlime` — a decorative player silhouette
  on the hero card. Reads like a control. Remove/clarify (and consider the world-scrub slider, §C3-adjacent).
- **G2 Shield-break feedback** — on a shielded crash: big camera shake + a glass-shatter FX (screen
  crack + character glass burst) so you KNOW the shield broke.

## Wave 2 — power-up presence + presentation
- **P1 Frequency ↑** (Core spawn → layoutVersion 3→4 + bot + golden): widen pattern-7 bands AND add a
  deterministic "guaranteed pickup cadence" (zero-RNG, distance-driven) so power-ups appear regularly.
- **P2 HUD power-up bar rework**: bigger, repositioned, **per-power-up color + theme** (shield cyan /
  magnet magenta / doubler green / chrono pale-blue / sneakers amber / overdrive gold), readable timers
  for slow-mo + sneakers + all (not a tiny circle). Owner override of the old uniform-color design.
- **P3 Custom procedural power-up icons** — bespoke neon SwiftUI glyphs matching the in-world meshes
  (NOT downloaded/AI assets). Replaces generic SF Symbols.
- **P4 Deploy buttons rework** — bigger, thumb-reachable; add a **Speed-Up deploy** (manual overdrive)
  alongside slow-mo. Banked-charge model like slow-mo.

## Wave 3 — designed gameplay + shop feel
- **G1 Coin-path routing** (Core spawn → layoutVersion bump; batch with P1 if possible): gems always
  trace a continuous TAKEABLE safe route through each pattern (Subway-Surfers style), teaching the
  solution. Re-verify bot.
- **S1 Shop purchase feel** — coin-spend packs need a real open/pay/reveal workflow + animations + sound
  (today: only a sound). Apply richer feedback across the whole shop.
- **S2 Mystery Box = gambling centerpiece** — dedicated screen/sequence: swiveling box, color burst,
  reveal, **visible odds**, juicy sound (Subway-Surfers crate). Procedural (no assets — see §Assets).

## Wave 4 — worlds + characters
- **F (world obstruction)** — pyramids (Solar Sands) + audit all 12: no decor/sky over the central lanes;
  push decor outward/back/down. Fix the safe envelope across worlds.
- **C1/C2 Rarity themes** (cosmetic only — decided): common = basic shapes/colors; rare = more features
  (antennas, eye styles); epic/legendary = THEMED families (e.g. cat / dog / etc.). Higher tier = cooler
  look, never stronger (non-pay-to-win). Needs roster art direction.
- **C3 Character-select slider** — replace the single equipped-character card with a browsable carousel of
  ALL characters (owned + locked, all rarities) showing unlock requirements + a progression view, to
  drive collection desire.

## Then: App Store Connect (owner gate, after the above).

## Assets decision (§Assets)
Owner offered AI-gen (Nano Banana / Seedream). Recommendation: **stay procedural.** Great mobile juice
(Subway-Surfers crates, particle bursts, swivels) is animation/particle/Canvas work, not static images.
Procedural keeps the zero-asset purity, tiny bundle, no licensing, and a consistent neon look. Revisit
only if a specific illustrated look is impossible procedurally — owner's call.
