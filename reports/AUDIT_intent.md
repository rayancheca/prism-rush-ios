# AUDIT_intent — Owner-Decree Synthesis Audit (v1.4.1)

Synthesis of three parallel audit sweeps (fidelity, docs-states, firstrun) — 33 raw findings
merged into **24 distinct findings + 1 verified-clean record**. Rubric: the six owner decrees in
`CLAUDE.md` (§Owner decrees), which OVERRIDE every design doc, spec, and R-decision.

Audit was strictly read-only. No code, doc, or test was modified. All file:line references
verified by the sweeps against the shipped tree at commit `a246184`.

---

## 1. Executive summary

The owner caught decree 1 being violated by the shipped default: Prism follows the world
palette. The audit found that this is not one bug — it is **one decision enforced by seven
mutually-reinforcing surfaces**: the catalog sentinel (`bodyHex 0` / `trailHex nil`), the
renderer's `skinFollowsWorld` branches (body, antenna, trail, and seven FX fallbacks), the
menu/select previews (which compound it with a decree-2 lie: a static rainbow that exists in
NO world), the binding V13_SPEC (6 places), DESIGN_characters (§1.2 origin decision + a §8 QA
item that literally regression-guards the violation), SkinCatalogTests (3 pins that will BLOCK
any fix until flipped), and the public README + flavor copy. Any single-surface fix gets
reverted by the others; the fix must land as one wave.

Beyond the headline, the audit found a second cluster of decree-2 erosion (preview vs. rig
divergence on antenna color, blink cadence, sway speed, body proportions — the roster's sold
personality is partially undelivered in-run), one reachable broken-state combo around unowned
`selectedSkin` (decrees 2+3+4 simultaneously), a first-run experience with three untutored run
entrances and an info-tap that force-starts a run, and a handful of honesty/clarity notes
(README "pays triple" overclaim, CLAIM ALL midnight race, HUD churn). Monetization surfaces
and state-honesty surfaces otherwise verified clean — recorded in the appendix so no fleet
"fixes" them into something worse.

Severity census after merge: **1 DECREE-VIOLATION cluster** (7 enforcement surfaces),
**7 MISMATCH**, **7 GAP**, **9 NOTE**, **1 CLEAN record**.

---

## 2. Findings by decree

Severity key: **DV** = DECREE-VIOLATION · **MM** = MISMATCH · **GAP** · **NOTE**.
A finding is listed under its primary decree; cross-decree impact is noted inline.

### Decree 1 — A character never changes identity with the world (incl. the default)

#### D1-1 [DV] The Prism chameleon cluster — one decision, seven surfaces (also violates decree 2)

The complete inventory, so the fix fleet can kill every tendril in one wave:

**(a) Catalog sentinel** — `PrismRush/Meta/SkinCatalog.swift`
- `:55-57` Prism defined as `bodyHex: 0 / antennaHex: 0 / trailHex: nil`
- `:41` `Skin.followsWorld` computed (`bodyHex == 0`)
- `:4-5`, `:28-29` sentinel documented in comments ("follow the live world accent — Prism only")
- `:55` flavor copy "Born of every world, loyal to none." — chameleon lore on the hero card
  (rendered at `CharacterSelectView.swift:91`; canonized in `DESIGN_characters.md:29, :111`)

**(b) In-game renderer** — `PrismRush/Render/Reality/RealityRenderer.swift`
- `:43` defaults `skinFollowsWorld = true` — the renderer's out-of-box state IS the violation
- `:180-181` body + antenna stem = world accent, tip = world accent2 → Prism is solid cyan
  `0x00F5FF` in Neon Metropolis, purple `0xB26BFF` in Crystal Caverns, orange-red `0xFF5E3A`
  in Solar Sands, re-tinting mid-dodge at every ~800 m world crossfade (~1.7 s blend)
- `:372` trail follows world when `trailHex` nil
- FX fallbacks `skinTrailColor ?? tintAccent`: slide dust `:310`, wake `:382`, jump puff `:422`,
  landing dust `:426`, lane skid `:432`, flow aura `:487`; death shatter → world accent2 `:458`
- `:593` comment "keeps the followsWorld chameleon behavior" sanctions it

**(c) Previews (the decree-2 compound lie)** — `PrismRush/UI/CharacterSwatch.swift`
- `:81-89` Prism's body drawn as a STATIC conic rainbow (`0x00F5FF→0xFF2BD6→0xFFB13D→0x00F5FF`)
  — the in-run body is a single flat `UnlitMaterial`, NEVER a gradient, so the hero stage
  promises a rainbow character that exists in no world, for the skin 100% of new players run
- `:162` fixed magenta antenna; `:69` fixed cyan glow; `:83` comment "the chameleon IS its identity"
- CharacterHeroStage `:203` fixed cyan disc; `:236-245` 8-second hue-rotating disc
  (the `followsWorld` branch at `:237-241`) — the menu visibly presents the default as a
  color-shifter
- `:280, :293, :298-303` legacy struct re-implements the rainbow (dead code, see D2-6)

**(d) Binding spec** — `reports/design/V13_SPEC.md` (self-declares "this spec wins")
- `:116` §S must-ship item 2 "Prism = sole followsWorld" · `:236` wave-2 DONE "exactly one
  followsWorld" · `:403, :415` §C.2 contract pins the bodyHex-0 / trailHex-nil sentinel and the
  `followsWorld` computed · `:444` §C.3 keeps the 3-arg `applySkin(...followsWorld:)` shim ·
  `:491` §T pins the SkinCatalogTests row. Any agent told "the spec wins" re-ships the chameleon.

**(e) Origin design doc + QA guard** — `reports/design/DESIGN_characters.md`
- `:27-34` §1.2 argues FOR the chameleon · `:38` + §1.3 "nil = follow world" · `:111` §2 roster
  row 1 zeros · `:291` §4.1 "followsWorld keeps today's AngularGradient rainbow" · `:454` §7
  test 1 · `:465` §8 QA item verifies the trail STILL follows world accent through a crossfade
  ("regression guard" — it guards the violation). `state.md:69` repeats the same QA item.
- `reports/design/DESIGN_uiux.md:86-87` + `:155` spec the hero-disc world-palette cycle / 8 s
  hue drift for followsWorld skins — shipped at `CharacterSwatch.swift:234-245`.

**(f) Tests that pin the violation** — `Tests/CoreTests/SkinCatalogTests.swift`
- `:59` asserts "exactly one followsWorld" == `["default"]` · `:61` asserts Prism's trail is
  nil ("follows the world accent") · `:18` legacy pin tuple `("default", 0, 0, 0, false)`.
  Any decree-1 code fix correctly breaks all three — they must flip in the same commit or CI
  blocks the fix.

**(g) Public copy** — `README.md:159-161` celebrates "only Prism, the free chameleon, still
morphs with the world — that's its whole personality". Plus `GameView.swift:455` milestone
color guards `bodyHex == 0` (dies with the sentinel).

**Fix:** §3.A below (the Prism identity fix is the entire first wave).

---

### Decree 2 — Previews never lie

#### D2-1 [MM] Antenna stem color: preview paints stem in antennaHex, rig paints it body color — wrong for all 23 fixed skins
`RealityRenderer.swift:187-190` assigns the BODY material to the antenna stem (`antenna.model?.
materials = [bodyMat]`), antennaColor only to the tip; the preview (`CharacterSwatch.swift:162-179`)
strokes stem AND tip with `antennaHex`. Worst cases: Mono (its whole "allergic to color" cue —
black stem promised, white-on-white delivered), Toxic (magenta→green), Pebble/Golem (catalog
comment `SkinCatalog.swift:149` says "the sibling cue is the antenna", but only the 0.095-radius
tip carries it), Thorn (leaf-green spike rendered wine-red).
**Fix:** in the palette block of `sync` (`:188-190`): `let antennaMat = UnlitMaterial(color:
antennaColor); antenna.model?.materials = [antennaMat]; antennaTip.model?.materials =
[antennaMat]`. Also seed `buildCharacter`'s stem (`:731`) with `uiHex(skinAntennaHex)` instead
of `.cyan` for the pre-first-sync frame. The preview is the purchase promise — the rig moves.

#### D2-2 [MM] Blink personality exists only in the preview — in-game every skin blinks at a hardcoded 2.2–4.2 s
Preview blinks per-skin (`CharacterSwatch.swift:122-124`: Tempo on its 3 s beat, Fang 6.5 s
"Blinks never", Vigil 7.5 s, Bolt 1.8 s). In-game `RealityRenderer.swift:508-509` re-arms
`blinkT = Double.random(in: 2.2...4.2)` for ALL skins — only Prism's default Idle matches.
Sold personality undelivered (also brushes decree 5: flavor copy advertises behavior).
**Fix:** store the range in `applySkin` (`:594-610`): `skinBlinkMin/Max = skin.idle.blinkMin/Max`;
use at `:509`: `blinkT = Double.random(in: skinBlinkMin...skinBlinkMax)` (renderer-side random
is fine — not Core). Update the Idle doc comment at `SkinCatalog.swift:19`.

#### D2-3 [MM] Antenna idle sway runs ~2.5× slower in-game than in the preview
Preview ω = `bobSpeed · 2π · 0.8` ≈ 5.03·bobSpeed rad/s (`CharacterSwatch.swift:167`); rig
ω = `2·bobSpeed` (`RealityRenderer.swift:607` + `:534`). Ratio π·0.8 ≈ 2.51 — Tempo's metronome
whip and Blossom's petal sway read at less than half their stage speed; the `:57` comment shows
the constant never matched the preview formula. bobSpeed is defined as Hz (`SkinCatalog.swift:21`),
so the renderer is the wrong side.
**Fix:** one line at `:607`: `skinSwaySpeed = skin.idle.bobSpeed * 2 * .pi * 0.8`; default at
`:57` → ≈ 4.02 for the pre-applySkin frame.

#### D2-4 [GAP] Trail color — a paid-for identity trait — is invisible in every preview surface
All 23 fixed skins carry a `trailHex` driving wake/slide ribbon/jump-land puffs/flow aura/death
shatter (`RealityRenderer.swift:310/:382/:422/:426/:432/:458/:487`); for Aurora it IS the sell
(`SkinCatalog.swift:169` "the two-tone money look"). Neither `AnimatedCharacterSwatch` nor
`CharacterHeroStage` renders or indicates it — the select stage, shop hero cards
(`ShopView.swift:169/:180`), and rail cards (`:468`) show only body/antenna/eyes. A
purchase-deciding trait omitted from the promise at the exact buy moment.
**Fix:** render a short fading trailHex streak behind the character in `CharacterHeroStage`
(Canvas-only, zero-asset rule), or minimally a TRAIL color chip next to the rarity chip in
`CharacterSelectView.heroSection` (`:85-90`). Grid swatches stay trail-free.
**Owner check:** the death shatter deliberately uses `trailHex`, not `bodyHex` — Aurora's teal
body explodes magenta. Confirm intended before anyone "fixes" it.

#### D2-5 [NOTE] Body-shape proportions drift between preview and rig
Rig (`RealityRenderer.swift:689-692`): sphere ⌀1.24, cube edge 1.06 (≈85 %), crystal
octahedron(0.78) → 1.56 (≈126 %, symmetric). Preview (`CharacterSwatch.swift:94-112`): cube
spans 100 % of footprint, crystal 95 % × 115 % elongated per DESIGN_characters §4.1. Relative
sizes flip across the seam (Golem previews ≥ Monarch, renders ~13 % narrower; crystals preview
slim, render wide; the documented elongation exists only in 2D).
**Fix:** align numerically — preview cube span → 0.85·(2·bodyR), cornerRadius ratio 0.18/1.06;
add `ProceduralMesh.octahedron(rx:ry:rz:)` ≈ (0.66, 0.80, 0.66) for the 3D elongation; pin
with a tolerance test on preview/rig width ratios per shape.

#### D2-6 [NOTE] Two dead skin-rendering shims with FALSE "still referenced" comments — decree-2 landmines if revived (docs also claim they were deleted in v1.4)
(1) Legacy `struct CharacterSwatch` (`CharacterSwatch.swift:267-311`) — comment claims ShopView
uses it; grep: zero call sites. Renders every skin as a sphere with white eyes/dot pupils,
ignoring bodyShape/scale/eyeTint/pupilStyle, and re-implements the rainbow. (2) Legacy 3-arg
`applySkin(bodyHex:antennaHex:followsWorld:)` (`RealityRenderer.swift:612-619`) — comment claims
GameView calls it "until the wave-5 rewire"; GameView calls the full `applySkin(Skin)`
(`GameView.swift:444`); zero callers. If revived it leaves shape/scale/eyes/pupils/trail from
the previous skin (the `:45-47` comment admits this). Its parameter NAME is the banned behavior.
`state.md:266` and `V13_SPEC.md:444` claim all legacy shims were "deleted in v1.4" — false;
the dead `MenuView.swift:19-21` `onSettings/onDailyChallenge` no-op params also still ship.
**Fix:** delete the struct, the 3-arg shim, the dead MenuView params, and the stale shim
comments at `RealityRenderer.swift:45-47, :56`. Correct `state.md:266` (deleted in v1.4.1,
not v1.4). Pure dead-code removal.

#### D2-7 [NOTE] Tutorial numbers are hardcoded copies of Tuning — correct today, silent-lie risk on the next retune
`HowToPlayView.swift:121` `ForEach(1...5)` matches `Tuning.multCap = 5`; "chain 3 near-misses"
matches `flowPerSurge = 3`; "one-second" matches `boostDuration = 1.0` (`:158-160`). All
literals.
**Fix:** derive — `ForEach(1...Tuning.multCap)`, `mult == Tuning.multCap` for the gold capsule,
interpolate `"chain \(Tuning.flowPerSurge) near-misses"`.

---

### Decree 3 — No broken-looking states for expected situations

#### D3-1 [GAP] Unowned `selectedSkin`: menu hero says "Running as X · Equipped" while the run silently plays default — and CharacterSelect dead-ends (decrees 2 + 3 + 4 at once)
`GameView.swift:438-444` deliberately guards the run against a cloud-merge/stale-save selecting
an unowned skin — but the surfaces don't share the guard: `MenuView.swift:124` stages
`SkinCatalog.skin(profile.selectedSkin)` with no `owns()` check, `:133` voices "Running as X.
Equipped."; `CharacterSelectView.swift:108` computes equipped purely by id, so the stage shows
the locked TEASE (lock chip `:80-82`) while the state button reads EQUIPPED and is `.disabled`
(`:113`) — a locked skin labeled equipped, no way to buy or re-equip. `ProfileStore.merged`
(`:546-565`) never reconciles `selectedSkin` against `ownedSkins`; `select(skin:)`
(`ProfileStore.swift:125`) doesn't validate ownership — the state is reachable and sticky.
**Fix:** one canonical resolver on ProfileStore — `var equippedSkinID: String {
owns(skin: profile.selectedSkin) ? profile.selectedSkin : "default" }` — used at
`MenuView.swift:124`, `CharacterSelectView.swift:32, :108, :347`, `GameView.swift:443`.
Better: also self-heal after load/merge (if `!ownedSkins.contains(selectedSkin)` reset to
"default") so the contradiction can't persist.

#### D3-2 [GAP] Challenge death silently hides CONTINUE with no explanation
Tutorial card 4 teaches CONTINUE (`HowToPlayView.swift:175`); on a Daily Rush death GameView
passes `revivesLeft: 0` (`GameView.swift:768`) and the entire continueSection just doesn't
render (`GameOverView.swift:85-88`) — the promised feature missing with zero explanation, and
the fair-shared-track design intent goes unsold.
**Fix:** when `isChallengeRun`, render an inert one-line caption in place of the button:
"NO CONTINUES IN DAILY RUSH — EVERYONE RUNS THE SAME FAIR TRACK" (micro type, textTertiary).

#### D3-3 [MM] Menu hub ignores purchased worlds: progress chip + ambient tint contradict the Worlds tab after a v1.4 world purchase
`MenuView.swift:140` (worldProgressChip) and `:46` (furthestAccent) read reach-only
`unlockedWorldCount` (`ProfileStore.swift:157`). Buy world 8 (the v1.4 headline feature),
return to the menu: still "WORLD 02 · …" while `LevelSelectView.swift:20` offers world 8 as
PLAY FROM HERE. The hub renders as if the purchase didn't take.
**Fix:** decide + document the chip's semantics (DESIGN_uiux §1.3 amendment), then align:
chip/accent → `highestStartableWorld` (max of reach and purchase — matches the Worlds header
it routes to). Display only; reach-based systems (achievements/XP/world coin bonus) untouched.

#### D3-4 [NOTE] Eclipse is near-invisible in-run, and its tease/glow self-cancels
`SkinCatalog.swift:173-178`: bodyHex `0x1A1A2E` as flat unlit against world backgrounds
`0x07021A/0x02141A/0x1C0A02` — contrast ≈1.2:1; only eyes/tip/trail locate the body (decree 6:
slide-under-bar judgment is hardest on the level-25 skin). The swatch glow
(`CharacterSwatch.swift:69-74`) uses bodyColor so Eclipse's halo is near-black, and the 0.45
locked tease on dark cards shows little more than two floating eyes. Consistent across
preview/game (no lie), but borders broken-looking.
**Fix:** brighten one step in the CATALOG ONLY so all three renderings stay in lockstep —
e.g. bodyHex `0x2A2A4A` — or a fixed (non-world) rim accent: thin trailHex outline ring in the
swatch + slightly larger dark-lavender `0x6B5BFF` shell behind the 3D body. Verify on-device
against all three world backgrounds.

---

### Decree 4 — Everything tappable leads somewhere

The only dead-end found is the CharacterSelect EQUIPPED-but-locked button — folded into D3-1
(same root cause, same fix). No other dead tappables: the firstrun sweep verified every menu
tappable routes (level ring→Profile, coin badge→Shop, hero→Characters, world chip→Worlds, rail
cells, nav row), locked worlds explain both keys, locked-skin taps route to requirements, and
disabled buttons all show their reason (see Appendix).

---

### Decree 5 — Honest monetization, no ads

#### D5-1 [MM] README advertises "PERFECT window pays triple" — actual perfect pays the SAME score and 2.4× coins
`README.md:173` vs reality: `GameCore.swift:422-423` pays `ringScore*mult` for ANY pass;
perfect pays 12 coins vs 5 (`Tuning.swift:78-80`) — 2.4× coins, not 3× anything. In-game
surfaces are honest (popup at `GameView.swift:414` shows exactly what the core paid).
**Fix:** copy fix (zero-risk): "a PERFECT thread pays 12 coins instead of 5". (Alternative —
retune `ringPerfectCoins` to 15 — is Core-side; economy-only but re-pins RingTests' coin delta.
Not recommended this wave.)

#### D5-2 [NOTE] CLAIM ALL can under-deliver its advertised total across a UTC-midnight board reset
`MissionsView.swift:101` computes "+total" from the rendered board, then `:107-114` claims
sequentially (80 ms gaps) with `now: Date()`; `claimMission` (`ProfileStore.swift:431-444`)
refreshes boards per claim — if UTC midnight lands mid-cascade, remaining daily claims return
nil and the player receives less than advertised. Rare (seconds/day) but real; UTC midnight is
evening in the Americas.
**Fix:** pass one frozen `now` captured at tap time through every `claimMission` call so the
cascade resolves against one board; and/or sum actual return values and toast the real amount
("CLAIMED +N") if it differs.

#### D5-3 [NOTE] First-death screen carries an IAP upsell line from run #1
`GameOverView.swift:216-226`: whenever doubleCoins is unowned (every new player), every death
panel — including the first — shows "EARN ×2 WITH DOUBLE COINS →". Honest (the shop really
pays ×2, no fake urgency) but it's the only monetization touch in the first ten minutes and
lands before the player knows what coins buy (decree 6: calm).
**Fix (optional polish):** suppress until `profile.totalRuns >= 3` — one condition on the
existing `!doubled` branch.

---

### Decree 6 — Clarity beats spectacle, calm UI

#### D6-1 [GAP] First-run tutorial gate only covers the menu PLAY button — Daily Rush and Worlds drop a zero-run player into an untutored run
The `totalRuns == 0 → HowToPlay` gate lives only in MenuView's onPlay closure
(`GameView.swift:739-743`). Two other live run-starters within the first 30 s: (a) the rail's
DAILY RUSH cell (`RewardsBar.swift:51` → `startDailyChallenge()` → startRun directly,
`GameView.swift:281-284`) — and after the REWARDS claims it becomes the gold-LIT cell drawing
the first tap, into the no-revive challenge ruleset; (b) the Worlds sheet's 200 pt PLAY FROM
HERE header and World 01 card (`LevelSelectView.swift:67-68, :43`).
**Fix:** move the gate into GameModel — a guard in `startRun`/`startDailyChallenge` (or a
`routeRun()` wrapper) that presents the tutorial first when `totalRuns == 0` and runs the
original start action on LET'S GO. One fix instead of three.

#### D6-2 [GAP] "FIRST RUN ›" chip and the tutorial's X button force-start a run — the info tap becomes a gameplay commitment
MenuView's bestChip (`MenuView.swift:189-207`, a11y hint "Shows how to play.") routes to the
HowToPlayView instance whose onClose ALWAYS calls `model.startRun()` (`GameView.swift:792-794`)
— wired to BOTH the LET'S GO button AND the top-right X (`HowToPlayView.swift:21-31`). Tap the
info chip, tap X to back out → launched into a run. The Settings-side instance closes cleanly
(`SettingsView.swift:50`), proving the component supports non-starting dismissal.
**Fix:** add `startsRunOnDone` param or a separate `onCancel` closure: X always returns to the
menu; only LET'S GO starts the run, and only when entered via PLAY. Via the chip, the final
button reads "GOT IT" and returns to the menu.

#### D6-3 [GAP] Tutorial covers v1.3 mechanics but not v1.4 worlds — the 800 m transition is totally unannounced
The four cards (`HowToPlayView.swift:37-44`) fully cover v1.3 (copy verified CURRENT against
Tuning — see D2-7), but nothing covers worlds: not the 800 m changes, not checkpoints, not the
Worlds tab. Mid-run at ~40-50 s everything crossfades — and with the current default skin, the
player's own body (see D1-1) — with only the world banner as explanation.
**Fix:** add a fifth WORLDS card (or one instructionRow on RINGS & FLOW): "NEW WORLDS — every
800 m the scenery changes; reach a world once to start from its checkpoint in the Worlds tab."
After the decree-1 fix, add: "Your character never changes — only the world does."

#### D6-4 [GAP] DAILY RUSH unplayed sub-line "NEW H:MM" reads as "available in H:MM" on a cell that starts a run NOW
`RewardsBar.swift:49-50` + `:130-133`: a countdown under a feature name universally means
"unlocks in 5:23" — yet the tap starts today's challenge immediately. Once REWARDS claims are
exhausted this becomes the gold-LIT cell: the rail's single call-to-action is a button whose
subtitle is an expiry countdown with no verb.
**Fix:** verb + expiry framing: "PLAY · ENDS 5:23" (or "TODAY'S TRACK", countdown demoted to
the a11y label — itself reworded to "Today's track ends in X").

#### D6-5 [NOTE] Locked-skin presentation is inconsistent: select grid teases at 0.45 + lock chip, shop renders the same skins full-color with no lock
`CharacterSelectView.swift:407` (silhouette tease, hero stage 0.6 at `:82`) vs
`ShopView.swift:169/:180` (featured cards) and `:468` (miniSkinCard, silhouette defaults false).
Not a lie (full color is the real appearance; prices carry state), but the same skin reads
owned-bright in the shop and locked-dim one tap later on the select stage it routes to (`:466`).
**Fix:** pass ownership through — `silhouette: !owned` at `:468` (owned computed at `:463`) and
on both featured-card previews (`:167/:178`). If the owner prefers a bright storefront, instead
document the rule ("shop = catalog render, select = ownership render") in DESIGN_characters.

#### D6-6 [NOTE] Ghost-chase chip is flicker-noise in the first session
`HUDView.swift:48-61`: appears at score ≥ 90 % of best whenever best > 0 — with a tiny first
best (150-600), "BEST 120 AHEAD" pops and vanishes within seconds of run 2, during the exact
window the player is learning controls.
**Fix:** add a floor — `snap.best >= 1_000` (or `profile.totalRuns >= 3`) — one clause at `:49`.

#### D6-7 [NOTE] Overdrive timer ring is sub-second churn — the only HUD element that cannot be read in time
`HUDView.swift:99-101`: `boostDuration` is 1.0 s (`Tuning.swift:85`), so the 20 pt depletion
ring lives under a second, alongside the OVERDRIVE popup, SFX, and renderer speed FX that
already announce the state — an unidentifiable flash in the top-right stack. The other three
rings (5-10 s) are useful; flow pips are fine.
**Fix:** drop the boostRemaining ring from timerRings, or only show rings for effects with
duration > 3 s — one condition at `:99`.

---

### Doc-rot mismatches (enable the next decree violation)

#### DR-1 [MM] Binding spec's roster/XP "single source of truth" numbers were never amended for v1.4
`V13_SPEC.md:21-22` pins `xpUnlockLevels = [3, 6, 12, 25]`; `:423` pins "SkinCatalog.all |
16 entries"; `:491` re-pins. Shipped: `XPCurve.swift:71 = [3, 6, 8, 12, 18, 25]`, 24 skins,
tests assert the new truth. The self-described winning document loses to the code in three
pinned places — the same doc-rot pattern that let the chameleon survive.
**Fix:** "v1.4 AMENDMENTS" block in V13_SPEC: R1 → `[3,6,8,12,18,25]`; §C.2 → 24 entries
(16 legacy frozen + the v1.4 eight at rungs 2,000/3,500/5,000/7,500, L8/L18, ach.gems t2,
14 challenge days). No test change needed.

#### DR-2 [MM] Public README is stale against shipped v1.4
`README.md:157` "16 fully procedural characters" (now 24); `:162` "XP levels 3/6/12/25" (now
3/6/8/12/18/25); `:180-181` "129/129" and "137/137" (state.md:15: 142/142 = 132 + 10); no v1.4
section at all (worlds ladder, WorldSky, tease rendering, missions board).
**Fix:** add a v1.4 section + update the three stale numbers — in the SAME README pass as the
D1 chameleon sentence and D5-1 "pays triple" fix, so only one pass is needed.

---

## 3. Prioritized fix plan

Ordering principle: Wave 1 must land first (it touches the catalog/renderer/preview/test spine
everything else sits on). Waves 2A/2B/2C are mutually disjoint by file and run in parallel
after Wave 1. Wave 3 (docs) can draft in parallel but merges last so it documents what shipped.

### A. Wave 1 — THE PRISM IDENTITY FIX (single owner; one commit; CI stays green throughout)

**Chosen direction (per owner intent):** Prism's identity is the PRISMATIC look the menu
already sells — kept constant across all worlds via a **time-based iridescent hue shimmer
in-game that matches the menu hero**, never the world palette. The menu's rainbow/8 s hue
cycle becomes truthful instead of being deleted.

Files owned: `PrismRush/Meta/SkinCatalog.swift`, `PrismRush/Render/Reality/RealityRenderer.swift`,
`PrismRush/UI/CharacterSwatch.swift`, `PrismRush/UI/GameView.swift` (one line),
`Tests/CoreTests/SkinCatalogTests.swift`.

1. **Catalog** (`SkinCatalog.swift`): kill the sentinel. Give Prism real hexes —
   `bodyHex 0x00F5FF / antennaHex 0xFF2BD6 / trailHex 0x00F5FF` (the world-0 look players know,
   and the preview's existing fixed antenna/glow colors) — plus an explicit
   `isPrismatic: Bool = true` flag on the default only (a flag for a FIXED time-based effect is
   decree-1 legal: identical in every world). Delete `followsWorld` (`:41`) and the sentinel
   comments (`:4-5, :28-29`). New flavor line selling a fixed identity, e.g. "The first runner.
   Every world remembers it." (replaces `:55`).
2. **Renderer** (`RealityRenderer.swift`): delete `skinFollowsWorld` and both world-tint
   branches (`:40-43, :180-181, :372, :597`); flip the out-of-box default to fixed colors. For
   `isPrismatic`, drive the body (and antenna tip if desired) `UnlitMaterial` color through the
   SAME fixed cyan→magenta→amber palette on an **8 s elapsed-time cycle matching
   CharacterHeroStage's 8 s hue rotation** — world-independent, identical in all 12 worlds.
   `skinTrailColor` becomes always non-nil: collapse the seven `?? tintAccent` fallbacks
   (`:310, :382, :422, :426, :432, :458, :487`) to the plain skin trail color. Death shatter
   `:458` → trail color. Delete the 3-arg shim (`:612-619`) and stale comments (`:45-47, :56`).
3. **Previews** (`CharacterSwatch.swift`): keep the conic rainbow (`:81-89`), fixed magenta
   antenna (`:162`), cyan glow (`:69`), and the 8 s hue-rotating disc (`:236-245`) — but key
   them off `isPrismatic`, not `followsWorld`, and align the rainbow stops + cycle period with
   the renderer's shimmer palette so menu and run are the same character (decree 2 satisfied
   by construction). Rewrite the `:83` "chameleon" comment. Delete legacy `struct
   CharacterSwatch` (`:267-311`).
4. **GameView**: replace the `bodyHex == 0` milestone-color guard (`:455`) with the real hex
   (or `isPrismatic` → fixed cyan).
5. **Tests** (`SkinCatalogTests.swift`) — flip in the SAME commit:
   - `:59` "exactly one followsWorld" → `XCTAssertTrue(all.allSatisfy { $0.bodyHex != 0 },
     "decree 1: no skin follows the world")` (followsWorld no longer exists)
   - `:61` `XCTAssertNil(trailHex)` → `XCTAssertEqual(SkinCatalog.skin("default").trailHex,
     0x00F5FF, "Prism's trail is constant")`
   - `:18` legacy pin tuple `("default", 0, 0, 0, false)` → pin the new fixed hexes; add
     "exactly one isPrismatic == default".
6. **Acceptance:** Prism's colors/trail/FX do NOT change across a world crossfade (the
   INVERSE of the old DESIGN_characters §8 QA item); menu hero, select stage, shop card, and
   in-run body show the same prismatic identity; full Mac suite green.

### B. Wave 2 — everything else (three parallel owners, disjoint files)

**Wave 2A — Rig/preview fidelity** (owner of `RealityRenderer.swift`, `CharacterSwatch.swift`,
`ProceduralMesh`, `SkinCatalog.swift` Eclipse line, `CharacterSelectView.swift:85-90` chip;
sequenced AFTER Wave 1 since it shares two files):
- D2-1 antenna stem material (+ `buildCharacter:731` seed)
- D2-2 per-skin blink range (`applySkin` + `:509`)
- D2-3 sway speed `* .pi * 0.8` (`:607`, default `:57`)
- D2-5 shape proportions (preview cube 0.85 span; `ProceduralMesh.octahedron(rx:ry:rz:)`;
  tolerance test)
- D3-4 Eclipse brighten (catalog-only change, e.g. `0x2A2A4A`) — verify on-device
- D2-4 trail streak/chip in CharacterHeroStage + heroSection

**Wave 2B — Meta/menu state honesty** (owner of `ProfileStore.swift`, `MenuView.swift`,
`CharacterSelectView.swift` equip logic, `ShopView.swift`):
- D3-1 `equippedSkinID` resolver + self-heal on load/merge; rewire MenuView `:124`,
  CharacterSelect `:32/:108/:347`, GameView `:443` (coordinate the one-line GameView touch
  with 2C's owner — or land it in Wave 1)
- D3-3 world chip/accent → `highestStartableWorld` (display only)
- D6-5 `silhouette: !owned` in ShopView `:167/:178/:468` (or document the storefront rule)

**Wave 2C — First-run flow & HUD calm** (owner of `GameView.swift`, `HowToPlayView.swift`,
`RewardsBar.swift`, `GameOverView.swift`, `HUDView.swift`, `MissionsView.swift`):
- D6-1 model-level tutorial gate (`routeRun()` wrapper)
- D6-2 HowToPlayView `onCancel` / `startsRunOnDone` split; FIRST RUN chip → GOT IT
- D6-3 WORLDS tutorial card (+ post-Wave-1 reassurance line)
- D6-4 DAILY RUSH "PLAY · ENDS H:MM" copy (+ a11y label)
- D3-2 challenge-death inert caption in GameOverView
- D5-2 frozen `now` through the CLAIM ALL cascade (+ honest "CLAIMED +N" toast)
- D6-6 ghost-chip floor; D6-7 drop the sub-second boost ring
- D2-7 derive tutorial numbers from Tuning
- D5-3 (optional) defer doubler upsell to `totalRuns >= 3`

### C. Wave 3 — docs & README (single owner; merges last; full list in §4)

---

## 4. Doc & test amendments list (exhaustive)

### `reports/design/V13_SPEC.md` (BINDING — amend, never "ship the doc")
- Top of §R: dated **"DECREE-1 REVOCATION (v1.4.1)"** addendum — the chameleon R-decision is
  revoked by owner decree and overriding.
- `:116` §S item 2 "Prism = sole followsWorld" → "no skin ever follows the world — Prism is
  prismatic (fixed time-based shimmer); pin body 0x00F5FF / antenna 0xFF2BD6 / trail 0x00F5FF"
- `:236` wave-2 DONE "exactly one followsWorld" → "zero followsWorld skins; exactly one
  isPrismatic (default)"
- `:403, :415` §C.2 — delete the bodyHex-0 sentinel, trailHex-nil rule, and `followsWorld`
  computed from the contract
- `:444` §C.3 — 3-arg `applySkin(...followsWorld:)` shim: mark **DELETED v1.4.1**
- `:491` §T — re-pin the SkinCatalogTests row (see test flips below)
- `:21-22` R1 xpUnlockLevels → `[3, 6, 8, 12, 18, 25]`; `:423` §C.2 → 24 entries (v1.4 amendment
  block)

### `reports/design/DESIGN_characters.md`
- `:27-34` §1.2 — **SUPERSEDED-BY-DECREE-1** banner quoting the revocation
- `:38` §1.3 — delete "nil = follow world"
- `:111` §2 roster row 1 — replace zeros with Prism's fixed hexes + isPrismatic
- `:291` §4.1 — body-fill rule: rainbow allowed ONLY as a fixed gradient/shimmer identical
  in-game; never palette-driven
- `:454` §7 test 1 — "exactly one followsWorld" → zero
- `:465` §8 QA — INVERT: "Prism equipped → colors/trail do NOT change across a world crossfade"
- (If chosen in 2A:) document antenna-stem rule (stem = antennaHex both sides) and the
  shop-vs-select locked-render rule

### `reports/design/DESIGN_uiux.md`
- `:86-87` §1.3 — "glow disc tinted by the skin's fixed bodyHex (prismatic: fixed 8 s cycle);
  no skin tracks the world palette"
- `:155` §1.8 — re-scope "Glow disc shimmer | 8 s hue drift" from followsWorld → isPrismatic
- §1.3 — new line defining the menu world chip as `highestStartableWorld` (D3-3)

### `README.md` (one pass, same PR as the code)
- `:159-161` — delete the "free chameleon … whole personality" parenthetical; state every
  character including the default keeps a constant identity in all worlds
- `:157` 16 → 24 characters; `:162` XP levels → 3/6/8/12/18/25; `:180-181` test counts →
  current (142/142 per state.md:15, re-verify at merge)
- `:173` "PERFECT window pays triple" → "a PERFECT thread pays 12 coins instead of 5"
- New v1.4/v1.4.1 section: 12-world purchasable ladder + reach-credit gate, roster 24,
  missions board, tease rendering, decree-driven Prism identity fix

### `state.md`
- `:69` — invert the QA item ("Prism crossfade" now asserts constancy)
- `:266` — correct the shim-deletion record (deleted in v1.4.1, not v1.4)

### `Tests/CoreTests/SkinCatalogTests.swift` (flip IN THE SAME COMMIT as Wave 1)
- `:59` `"exactly one followsWorld"` → **zero** (assert no `bodyHex == 0` /
  `followsWorld` deleted; assert exactly one `isPrismatic`)
- `:61` `XCTAssertNil(default.trailHex)` → `XCTAssertEqual(default.trailHex, 0x00F5FF,
  "Prism's trail is constant")`
- `:18` legacy pin tuple `("default", 0, 0, 0, false)` → new fixed hexes
- New (Wave 2A): preview/rig shape-width ratio tolerance test

---

## Appendix — Verified CLEAN (do not "fix")

Recorded so later fleets don't churn surfaces that already meet the decrees:

- **FX trail audit:** every character-FX call site uses `skinTrailColor ?? fallback`; the
  fallback fires ONLY for Prism (D1-1). Slide skid decals (`RealityRenderer.swift:651-658`)
  and worldChanged horizon ring (`:461-465`) are intentionally world/floor-colored — not
  character FX.
- **Eye/pupil/scale recipes** honored both sides incl. Eclipse's gold sclera and glint sparkle
  (`CharacterSwatch.swift:115-158` vs `RealityRenderer.swift:699-724`); `skin.scale` honored
  both sides with matching clamp, never touches the hitbox.
- **Locked-tease copy honest:** `SkinUnlocks.requirementText` (`SkinUnlocks.swift:19-34`)
  matches the real ladders in `MissionCatalog.swift:113-128`.
- **State honesty:** signed-out Game Center = neutral explainer (`ProfileView.swift:253-272`);
  pre-first-run Profile zero-state (`:164-181`); IAP pre-ASC notConfigured = quiet footnote
  (`IAPManager.swift:23-28, 79-87`); all `Role.danger` uses are action-denial or death header;
  no placeholder/"coming soon"/TODO copy anywhere in UI/.
- **Monetization honesty:** gem/ring/flow popups, GameOver breakdown rows, mission/rail/chest/
  daily toasts, first-purchase +50 % (paid exactly once), challenge tier line, XP-to-go toast —
  all show exactly what the core/store paid; all countdowns are real UTC timers; no fake
  urgency. Tutorial mechanic numbers currently CORRECT vs Tuning (hardcoding risk = D2-7).
- **HowToPlayView** contains no chameleon copy. ShopView intentionally out of scope (redesign
  in flight).
