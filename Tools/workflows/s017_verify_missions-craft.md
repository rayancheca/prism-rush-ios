# S-017 · hostile verification of `s017_missions-craft.md`

## Verdict: **PARTIALLY REFUTED**

The diagnosis is mostly sound and the code citations are unusually accurate. **Every headline
NUMBER that supports it is wrong**, one of them impossibly so, and the AFTER commits three of the
sins the BEFORE indicts — plus it would silently defuse the only UITest that guards the claim
pipeline. Findings survive; the arithmetic and the proposal do not survive intact.

**Citation audit: 55 `file:line` opened. 3 substantively wrong, 4 off-by-one at a range boundary,
48 verbatim and at the cited line.**

Wrong:
- `HowToPlayView.swift:157` (cited as "HowToPlayView covers CLOSE calls") is
  `card(title: "RINGS & FLOW", accent: 0xB26BFF)`. CLOSE is at **`:149`**
  (`instructionRow("scope", "CLOSE", "shave past an obstacle for bonus points")`).
- `MissionCatalog.swift:106` cited inside "six titles are 28–31 characters".
  `"Score 6 SLICK bonuses today"` is **27**.
- `UITests/InteractionUITests.swift:261-267` cited as asserting four identifiers. That range holds
  only `railMissions` (:263) and `missionsSummary` (:267). `claimAllButton` is :269, `claim_ach.*`
  is :272/:275/:282. **`missionCard_<id>` is asserted NOWHERE in `UITests/`** — `grep -rn
  "missionCard_" UITests/` returns nothing. §7's central constraint over-claims its own gate.

Off-by-one: `MissionsView.swift:548-576` (CoinFlyUp ends :577); `Theme.swift:280-292`
(NeonButtonStyle :280-289, extension :291-293); `MetaScreenScaffold.swift:16-58` and `:7-59`
(body 16-59, struct 7-60); `StateNotice.swift:31+` (`ShortfallRow` is :30).

---

## 1 · What survives

**C1 — CONFIRMED, mechanically.** `activeMissions` (`MissionsView.swift:159-162`) really is
`perRun + daily + weekly + achievements` = 6+3+3+7 = 19, and `MissionBoardSummary.of`
(`ProfileStore.swift:527-538`) filters `!claimed` over that one flat pool. Claim all three dailies →
they flip `claimed` → 16 `.open`. `.allClear` requires all 18 ladder tiers + 6 feats + both boards.
The daily success state is genuinely unrepresentable. **The strongest finding in the report.**

**C2 — CONFIRMED (geometry re-derived independently, see §2).** 19 rows, 6 above the fold, 13
below = 68.4 %. Correct.

**C5 — CONFIRMED as a code fact.** `refreshDailyMissions:388-396` wipes `missionProgress` and
`claimedMissions` for **all 8** `dailyPool` ids (not just today's 3 slots); `:408-419` does the same
for all 7 weekly ids. The only surface warning is 9 pt `.micro`/`textTertiary` at `:207-210`.

**C6/C7/C9/C10/C11/C13/C15 — CONFIRMED verbatim.** `Theme.swift:25` really is Solar Sands
`grid: rgb(0xFFB13D)`; `CharacterSelectView.swift:488` really is `case .epic: 0xB26BFF`;
`Theme.swift:154` `interactive = 0x00F5FF`; `Role.reward = 0xFFD23D` (:155) beside `todayTint`
`0xFFB13D` (:206) in one 15 pt cluster; `sparkles` at both `:313` and `:520`; `gift.fill` at `:524`
and `ShopView.swift:541`; `CharacterSelectView.swift:301` "PLAY TODAY'S CHALLENGE",
`GameOverView.swift:284` "CHALLENGE TIER", `ClaimRibbon.swift:160` "DAILY RUSH";
`RewardBurst.Kind` has exactly `.daily` / `.chest` (`:6-11`) and `RewardBurstView` is constructed
only at `GameView.swift:1532` — **never from missions**; exactly **6** raw `.font(.system(size:`
sites at `:74 :249 :267 :415 :492 :564` plus the inline `0x00FF88` at `:493`. All clean.

**"What must survive the rebuild" (§3) — CONFIRMED and correct.** `claimMission` before FX
(`:476-484`), the AUDIT D5-2 same-`now` cascade (`:126-136`), the `CoinFlyUp`-on-`Group` placement
(`:354-363`), G3 at `:31`, `MissionBoardSummary` as a 3-case enum pinned by
`Tests/CoreTests/MissionsTests.swift:279-283`. `compactCount` is referenced only at `:380` and
`:539`, so change 2's deletion is safe. `s016_design-system.md:442` really does prescribe
"Ring progress → a segmented bar (countable)" and `:355` really says "One E3 per screen, maximum."

---

## 2 · Refuted, with my own derivation

### R1 — **`5,510 COINS` is arithmetically impossible.** (C1, §1.3, §1.5)
`.open` coins = Σ rewards of non-claimed states. Fixed contributions: perRun
`150+100+120+150+200+250 = 970`; achievements at tier 0 `50+150+200+150+100+100+100 = 850`.
Variable: 3 of 8 daily (80–140) and 3 of 7 weekly (600–900).

```
daily-3   ∈ [280, 400]      weekly-3 ∈ [1900, 2600]
19-OPEN   ∈ [4000, 4820]     ← 5,510 is OUTSIDE the range, on every possible day
```
I replicated SplitMix64 (`Core/RNG.swift:10-27`) and `dailySlots`/`weeklySlots`
(`MissionCatalog.swift:152-176`) in python. Today (2026-08-03, `daysSinceEpoch` 20668, week 2952):
daily = slick6/runs5/dist3k = 360, weekly = slide60/streak25/slick35 = 2200 →
**`19 OPEN · UP TO 4,380 COINS`**. Over ±400 days the value never leaves **[4,000, 4,800]**.
After clearing three dailies today it reads **`16 OPEN · UP TO 4,020 COINS`**, not 5,510.
The finding stands; every instance of the number must be corrected.

### R2 — **The ring is 62°, not "~11° apart".** (C3)
`(118 − 92) / 150 × 360 = 62.4°`. Arc length at r≈20 pt ≈ **21.8 pt** of travel — plainly readable.
11° would be a 4.6-unit delta on a 150 target. C3's *only* quantitative support is off by 5.7×.
The finding survives on its other legs (the ring is redundant with `:380`, and it eats 44 of 370 pt),
but it must be re-argued from **redundancy and width cost**, not from arc discriminability.

### R3 — **The scroll is 1,878 pt, not 1,818.** (C2, §1.4)
`34 + 40 + 262 + 262 + 508 + 590 = 1,696` content, `+ 5 × 22` VStack gaps `= 1,806`,
`+ 16` top `.padding(Theme.Space.m)` `+ 16 + 40` bottom (`MetaScreenScaffold.swift:46-47`)
**= 1,878**. The report's own y-table agrees with me (last block ends screen y 1941; scroll top
y 119; 1941 − 119 + 56 = 1878) and contradicts its own total. **2.60 screens, not 2.5.** Section
heights, the 72 pt card, the 370 pt column, the 721 pt viewport and 13/19 = 68 % all re-derive clean.

### R4 — **C12 undercounts itself.** With 5 claimable rows the screen carries
`1 (CLAIM ALL) + 5 rings (:411) + 5 pills (:453) = 11` gold-gradient objects; the fold fits ~6 rows,
so the real ceiling above the fold is **13**, not six. The parenthetical arithmetic
("CLAIM ALL + one ring + one pill per claimable row × up to 5") cannot produce 6. Finding is
stronger than stated — fix the number upward.

### R5 — **C14's title census is wrong in count and band.** Not "six titles, 28–31 chars": **nine**
titles are ≥28, spanning **27–32**. `:106` is 27 (excluded); `:118` and `:119` are **32** (above the
stated band); and `:91` (30), `:92` (29), `:107` (28), `:121` (31) were omitted. The suffix cost is
**27.3 %** for `" today"` (6/22) and **35.7 %** for `" this week"` (10/28) — "~35 %" is the weekly
case only, and "~7 of those 32 characters" matches neither (the suffix is 6 or 10).

### R6 — **C8's "18 is not a token" is already stale.** True against today's
`Theme.Radius` (`:203-207`, s12/m16/l20) — but `s016_design-system.md:435-436`, the very revision
this report's AFTER adopts, sets `Radius: … m 18 (cells) · l 26 (cards)`. So `cornerRadius: 18`
becomes **correct** the moment s016 lands. C8 should be re-scoped to the two real bypasses:
`.ultraThinMaterial` instead of `Role.surface` (`:391`) and `white 0.04` (`:507`).

### R7 — **C5 is mis-filed under decree 5 and argues the weak case.** A daily board resetting at
UTC midnight is not a withheld advertised bonus; it is a standard reset with no warning — that is
**decree 6 / clarity**, not a dark pattern. And "148/150 evaporates" is the *weak* example. The
strong one, which the report misses entirely: a mission the UI has already painted gold and labelled
`CLAIM +120` is wiped by the same code path, and because `claimMission` calls
`refreshDailyMissions` FIRST (`ProfileStore.swift:564`), a tap landing at 00:00:00 hits
`guard … else { return }` at `MissionsView.swift:478` — **no coins, no error, no shake, nothing**.
That is the honest defect and it is the one worth building for.

---

## 3 · The proposal — what it breaks

### **P1 · CHANGE 10 WOULD MAKE AN EXISTING GATE PASS BY WEAKENING IT. Highest-value catch.**
`UITests/InteractionUITests.swift:261-289` (`testMissionsClaimAllCascadeAndSingleClaim`) is built
**entirely on achievement rows**: it asserts `claim_ach.gems` and `claim_ach.slick`
`waitForNonExistence` after the cascade (:272, :275), then `claim_ach.chests`
`waitForExistence` → scroll → tap → `waitForNonExistence` (:282-288).

Change 10 moves ladders behind an **inactive `CAREER` segment**. Consequences:
- `waitForNonExistence(claim_ach.gems)` **passes vacuously** — the button never renders because the
  segment is hidden. The cascade assertion stops proving the cascade ran. This is precisely the
  failure mode §7 forbids, authored by §4.2.
- `waitForExistence(claim_ach.chests, 6)` **fails** — hidden segment, and the test does not know to
  tap `CAREER`.
- If CLAIM ALL is scoped to the hero set (the mockup places it under the hero, `y 445`), a demo
  profile whose claimables are three seeded tier-1 achievements shows **no CLAIM ALL** and
  `claimAll.waitForExistence` fails. If it stays global, it advertises coins for rows the player
  cannot see — a worse C1.

**Corrected requirement:** the rebuild must either (a) keep every `claim_<id>` in the hierarchy
regardless of segment, or (b) rewrite `testMissionsClaimAllCascadeAndSingleClaim` to drive the
segment explicitly and assert the segment tap — and the rewrite must be reviewed as a *gate change*,
never as a passing suite. Do not ship (a) silently.

### **P2 · The AFTER commits C6 verbatim.** Change 4 declares `#00E5FF` "the only accent" and then
paints it on the **non-tappable SET BAR** (`y 127`) and the **non-tappable week day-dots**
(`y 577`). C6's charge against the current screen is `#00F5FF` = `Role.interactive` "used here on a
*non-tappable* label". Same sin, new hex. Either the accent stops meaning "tap", or those two
elements move to `text-2`/`surface-2`.

### **P3 · Change 5 gives `#FF3355` a second meaning and puts danger on a normal event.**
`s016_design-system.md:91` pins `#FF3355` as **"the next contact ends the run", ONE meaning since
v2.4** (`RealityRenderer.swift:36`). Using it for a daily timer under 2 h (a) re-creates the exact
F9 collision this report cites, and (b) paints a red alarm on a completely expected situation —
**decree 3**. It is also not `Theme.Role.danger` (`#FF5E5E`, `Theme.swift:156`), so shipping it in
missions alone forks the danger token. Use `money`/`text-1` escalation plus weight, not danger red.

### **P4 · The AFTER's "three hues" reintroduces the hue it deleted.** Change 4 kills `#FFB13D`
(C6: "world 2's grid hue") and installs `money #FFB020`. Those are **Δhue 2.8°** apart
(38.7° vs 35.9°; identical R and G, blue 32 vs 61) — an F9-class hand-written near-duplicate. Worse,
shipping `#FFB020` on missions while `CoinBadge`, `ClaimRibbon` and `GameOverView` still draw
`Role.reward #FFD23D` puts **two money golds in the app at once** and violates decree 2 mid-migration.
The palette swap is app-wide or it is not done — same rule §6 already applies to the status shelf.

### **P5 · Purple is not just the Epic tint — it is the Missions nav identity, and change 4 deletes
it.** `MenuView.swift:343` tints the Missions rail cell `Theme.color(0xB26BFF)` — two lines above
the `target` symbol the report cites at the same line for a different point. `0xB26BFF` has **six**
owners (`HowToPlayView:157/161/165/185`, `SkinCatalog:125`, world 1 accent `Theme:24`,
`CharacterSelectView:488`, `MenuView:343`). So C6 understates the collision — and change 4 severs
the nav→screen color continuity the hub already establishes, with no replacement proposed.

### **P6 · `CAREER 4/19` is wrong; the ladders have 18 tiers.**
`3+3+2+2+3+3+2 = 18` (`MissionCatalog.swift:127-139`). "19" is the total mission count reused. Also
change 10 sends claimed **feats** into `CAREER` while a separate `FEATS` segment exists — pick one.
And the segment labels show *progress* (`1/3`, `2/6`), not *claimable* count: **a ready reward
behind an inactive segment has zero on-screen representation.** That is a new decree-4 hole strictly
worse than C1, which at least surfaces a count.

### **P7 · The AFTER's own geometry does not close.** Hero claims `370 × 306` (y 127→433) but its
contents total ≈315 (16 pad + 4 bar + ~30 header + 3×66 + 2×8 gaps + 1 divider + ~34 prize footer +
16 pad). And the third weekly row starts at `y 773` at "74 tall" → ends **847**, past the 840 fold —
directly contradicting "nothing important below the fold". Row pitch is also inconsistent
(613→691 = 78, 691→773 = 82, spec says 74+8=82).

### **P8 · Token drift in the row spec.** "title 15pt semibold" is neither s016 `.body` (15 **medium**)
nor s016 `.label` (13 semibold) — `s016:414-419`. Pick a token.

---

## 4 · What is missing

1. **The claimable-at-rollover loss** (see R7) — the single most defensible reason to touch this
   screen, absent from the report.
2. **A silent-failure path**: `MissionsView.swift:478` `guard … else { return }` swallows every
   rejected claim. `ShakeEffect` (`Theme.swift:297-309`) is cited in §6 as "available for a denied
   claim" but no change wires it. Decree 3.
3. **The set prize is uncosted.** Deferring the tier to the economy pass is correct, but the report
   should state the ceiling it must not exceed: dailies already run **345 coins/day**
   (`s016_coins-economy.md:73`, mean 115 × 3 — I re-derived: 920/8 = 115 ✓) against **318/day**
   equivalent from weeklies (`:74`, 5200/7 = 742.86 × 3 / 7 = 318.4 ✓). A prize is a >10 % raise to
   the daily line before the box contents are priced.
4. **Iron rule 7 is named but not discharged.** A `dailySetPrizeClaimedDate` field needs
   `decodeIfPresent ?? default` **and** the clock-rollback clamp every other reward timestamp gets
   (rule 9) — `refreshDailyMissions`'s `min(last, now)` (`ProfileStore.swift:387`) is the pattern.
5. **Decree-5 check on the set itself.** "FINISH ALL 3 → SILVER BOX" is an advertised bonus; if the
   3 daily slots are ever individually unreachable (e.g. `day.chest2` needs 2 chest opens = 30 min
   apart, `ProfileStore.swift:297`), the set is un-completable on a short session and the advertised
   prize is not delivered. **The report never checks that the 3-slot draw is always finishable.**
   That is a real decree-5 exposure the current unbundled board does not have.
6. **Third-party naming.** §5 correctly warns off the SYBO "Mystery Box" name — but the repo already
   ships `MysteryBoxView.swift` and §6 proposes reusing its crate. No trademark risk is introduced
   by this pass, and "SILVER BOX" is fine; flagging only so the builder does not "fix" it by
   importing SYBO's vocabulary. No third-party art, names or marks are proposed. Clean.

## 5 · Rules checked, clean

No Core/ involvement; `MissionCatalog`'s SplitMix64 is meta-only (`:162-166`) with **zero**
`layoutVersion` implications — iron rules 1–4 untouched, no solvability-bot exposure. G3 preserved.
No Swift 6 isolation hazards introduced (the cascade is already `Task { @MainActor in }`, `:130`).
D-046 makes "zero binary assets" a non-objection; nothing here needs an asset budget.

---

*Read-only. Nothing built, run, launched or edited outside this file.*
