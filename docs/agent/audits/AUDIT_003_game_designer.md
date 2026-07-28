# AUDIT-003 · The Game Designer

- Session: 003
- Persona: AUDIT-002 (The Game Designer) — free-to-play design lead, three shipped runners
- Date: 2026-07-28
- Code changes: **zero**
- Method: 10 design lenses fanned out in a dynamic workflow, each finding attacked by an
  independent hostile verifier before reaching this file. 20 agents, 3.89 M tokens, 740 tool calls.
- **124 findings raised → 92 survived → 32 killed.** 41 of the survivors carry a material
  correction from the verifier. Severity was downgraded on 34.

---

## 1. Mandate, in character

I do not care about your code. I have watched a hundred technically competent games die because
nobody could say what the player was doing second to second, and this is one of them. Prism Rush is
a well-built, well-lit, well-tested game that runs out of design at the two-minute mark and then
asks the player to keep going forever. My job was to write the design bible this project never had
— `docs/agent/05_GAME_DESIGN.md`, which is the real deliverable of this session — and then to find
the design failures. I did both, and I spent an hour playing the thing before I read a single
source file, which is how I caught the three inherited claims that were simply false.

The headline: **this game is 3,200 metres long and ships an infinite credits roll.**

---

## 2. What I examined, and what I deliberately did not

**Examined.** `Core/Tuning.swift` in full · `Core/Spawner.swift` · `Core/Patterns.swift` (all 14) ·
`Core/GameCore.swift` · `Core/Autopilot.swift` · `Meta/XPCurve.swift` · `Meta/ShopValue.swift` ·
`Meta/SkinCatalog.swift` · `Meta/MissionCatalog.swift` · `Meta/ProfileStore.swift` ·
`UI/GameView.swift:680-792` · `UI/Theme.swift` · `docs/agent/02_STATE.md`'s Completeness Ledger.

**Ran the app for an hour before reading source** (mandatory per D-003):
- `./Tools/build.sh` → BUILD OK; clean install (uninstall → install) for a true FTUE
- Autoplay bot, 20 screenshots at 10 s intervals, 143 m → 5,331 m — the difficulty instrument
- Full first-run path: splash → hub → PLAY → all 5 tutorial pages → run → death panel
- Pixel-sampled the HUD across all 20 frames to turn "it looks like it changes" into a table

**Deliberately did not.** Re-audit completeness (session 002 owns the Ledger; I used it as input) ·
App Store compliance (AUDIT-003) · input latency in ms, juice, death legibility in 200 ms
(AUDIT-004) · code quality, concurrency, `@unchecked Sendable` (AUDIT-006) · anything in
`Render/` beyond confirming `applySkin` is render-side. I did not renumber, re-score or delete any
session 001/002 backlog item.

---

## 3. Findings, ranked

Numbering continues the backlog at **PR-0400**. Full blocks are in `03_BACKLOG.md`; this section is
the ranked argument. `[nn survived]` marks how many independent lenses reached the same conclusion.

### SEV1 — the ones that decide whether this game has a second week

**PR-0400 · The difficulty curve ends at 3,200 m and the game never changes again.** `[4 lenses]`
The last new pattern unlocks at 1,920 m (`Spawner.maxIndex`), speed caps at 3,077 m
(`(33−17)/0.0052`), gap floors at 3,200 m (`diffFullAt`). **Measured:** five consecutive 10 s
intervals at 33.5–33.7 m/s, and a flat score rate (5,874 pts/337 m at 3.6 km vs 6,171/336 m at
5.0 km). A 4,000 m run and a 40,000 m run are the same run. This is the finding; everything below
is detail. Survived every attempt to kill it, at SEV1, in three separate lenses.

**PR-0401 · The meta loop is a decoration loop — zero of 83,500 coins buy a new way to play.**
24 characters are colour/shape/trail only; 12+ worlds are a palette plus a start offset; the only
play-affecting purchases are single-run consumable charges. A player at run 500 owning everything
plays exactly the same game as a player at run 5 owning nothing.

**PR-0403 · A world transition introduces no mechanic, pattern, or demand.** `[3 lenses]`
`Spawner.fill` takes `dist` and nothing else; `Patterns.run` takes **no world parameter**; grepping
`world` across both files returns one hit, in a doc comment. It is *structurally impossible* for a
world change to alter play. The 800 m transition is a reskin dressed as the progression spine, and
it pays five coins.

**PR-0406 · The first-death panel sells an unaffordable revive above the free retry.** Measured on
a genuine first install: 72 m, score 132, **+1 coin**, and the panel's largest, highest-contrast
element is a solid amber **"NEED 149 MORE — 150 🪙"**, directly above `GET COINS — FIRST PURCHASE
+50% BONUS`, and only then `RUN AGAIN`. Every element is honest; the *sequencing* is not. A dark
pattern does not require a lie. Also a decree-3 failure: being broke on your first death is the
most expected situation in the game, and it renders as a permanently disabled button.

**PR-0411 · "Earn 2× coins, forever" under-delivers on a paid product.** Survived verification with
severity cut SEV0 → SEV1. This is a decree-5 violation ("advertised bonuses are always delivered")
on a real-money purchase. **Flagged to Rayan.** Full accounting in `scratch/economy.md` §F1 and
`scratch/verify-economy.md` §F1.

**PR-0412 · Buying a world silently disqualifies the run from the leaderboard and credits zero
reach.** The *behaviour* is correct and deliberate (iron rule 10, `GameView.swift:718-721`) — this
is a **disclosure** defect, and must be filed as one or it will be closed WONTFIX on sight of the
comment. The player spends up to 13,400 coins and is never told what it costs them.

**PR-0413 · The first-run tutorial banner names the wrong verb ~1 prompt in 5.** Its trigger window
is blind to anything closer than 12 m (`GameView.swift:344`, `:347`). Teaching the wrong verb
during the only teaching moment the game has.

### SEV2 — the ones that cost retention without being noticed

- **PR-0405 · The ×5 multiplier is a loading bar.** `[4 lenses]` ×5 at 20 gems; **measured ×5 in
  all 20 frames from the 143 m sample onward** — capped before the first screenshot, pinned for
  ~96% of the run. The HUD spring-animates it as contested state. It is not.
- **PR-0409 · Depth is execution-only.** `Autopilot.swift` reads only `activeObstacles` — grep for
  `activeGems`/`gemCount`/`score` returns zero — and survives 200 seeds × 6,000 m. The survival
  layer requires no routing, resource or risk decision. *(Corrected: this does not mean "no skill
  ceiling" — the bot has perfect information, 120 Hz actuation and zero input latency. The claim is
  narrower and still damning.)*
- **PR-0402 · Onboarding is inverted.** ~17 concepts in a 5-page pre-run text carousel, then zero
  in-context teaching ever. In-run cues are capped at three, on run 1 only.
- **PR-0414 · The coin trail is painted on the provably safe lane.** Verified exhaustively across
  all 14 patterns: **no gem in the catalogue requires entering an unsafe lane.** Greed and survival
  are the same input, so gem income is an attention tax, not a decision. *(This is a deliberate
  v1.6 change — `Spawner.swift:49-52`, "coins are the path" — so any fix is a **reversal request**,
  not a bug report.)*
- **PR-0415 · The risk economy is ~8% of the faucet and hard-capped.** Style coins cap at 80/run.
  Gems are 76–88% of income depending on run length. Distance — the game's name, its leaderboard
  metric and its 48 pt HUD number — is ~7% of coins and ~12% of score.
- **PR-0416 · CLOSE cannot be aimed at.** It only fires mid-lane-change, in an ~89 ms window, and
  nothing teaches it. **PR-0417 · SLICK fires for surviving a bar**, with no timing window at all,
  while the tutorial card advertises timing. The two "skill" rewards are an accident and a
  participation trophy.
- **PR-0418 · Moving walls award CLOSE for zero player input**, breaking the 1.95 outer bound.
- **PR-0419 · No variable-ratio reward exists in the run loop.** The only randomised rewards are
  the Mystery Box and the chest, both in the menu. Admirable honesty (decree 5); also why there is
  no "one more run" pull.
- **PR-0420 · Zero notifications.** No `UNUserNotifications`, no `aps-environment`. Four retention
  mechanics depend on the player spontaneously remembering. *(Cut from SEV1: the challenge-day
  skins are cumulative distinct days, not consecutive; the true consecutive ladder pays 2,650
  coins over 7 days.)*
- **PR-0421 · PERFECT rings pay +0 score** over a normal pass and the popup shows the same number
  for both. The hardest input in the game (±96 ms) is worth 7 coins.
- **PR-0422 · The score gradient runs opposite the difficulty gradient** — the safest pattern pays
  2× the hardest, so the leaderboard ranks gem-hoovering, not survival.
- **PR-0423 · Coin Surge is a 177–1,040% ROI purchase** that turns the 83,500-coin sink into a
  speed bump.
- **PR-0424 · The daily leaderboard has no viewer** and the competitive layer is invisible at the
  death panel — the only moment it would matter.
- **PR-0425 · The Daily Rush ladder is exhausted in ~35 s** and pays zero for the rest of the day.
- **PR-0426 · The login streak is only ever shown as a receipt** — never as a stake, never with a
  countdown, despite being the one genuinely consecutive mechanic in the game.
- **PR-0427 · 9,600 m buys a 49° hue rotation** ("Pulse City II"), and the price ladder escalates
  +2,000/rung forever over a provably flat value curve. A treadmill, not a progression system.
- **PR-0428 · Post-revive death panel replays the first death's XP, level-up burst and unlock
  badge**, having granted none of it. *(The only survivor of 11 in the session lens — the other 10
  were duplicates of existing backlog items.)*
- **PR-0429 · SLOW-MO is a −116-point button styled as the twin of a +18-point button.**
- **PR-0430 · Nothing tells the player what to chase next**, and the one surface that did (the
  skill mission board) self-clears by run 3 and stays permanently empty.

### SEV3 — real, cited, and not urgent

Filed in `03_BACKLOG.md` as PR-0431 … PR-0444: FLOW meter never renders completion · 13.8% of the
endgame track requires zero input · jump and slide get *easier* as speed rises · tier 3 *lowers*
density at 576 m · `spawnHorizon` is 115 m but the player sees 65 m · `gemArc` stops telegraphing
past 1,133 m · no build/loadout variance · level 30 is a wall · zero shareability · no review
prompt · two coin-spend packs are dead stock · `DESIGN_progression.md` overstates style XP by 3–5× ·
first-run gate has no SKIP and its ✕ eats the PLAY you tapped · the chest outranks Daily Rush in
the lit-cell ladder.

---

## 4. What I killed, including my own

Adversarial verification killed **32 of 124**. The pattern is worth recording, because the next
audit will make the same mistakes:

- **10 of 11 session-lens findings died as duplicates** of session 001/002 backlog items
  (PR-0011, PR-0259, PR-0307…). A lens that does not grep the backlog first wastes its whole run.
- **"No telemetry" — killed on charter grounds, and it was mine.** I had it drafted as SEV2.
  `00_CHARTER.md:73` non-negotiable #4 is *"Zero ads, zero analytics, zero tracking"*, advertised
  in the store listing; `:94-98` lists analytics SDKs under Explicitly out of scope with the words
  *"Do not file backlog items proposing them."* I withdrew it. The real consequence — **every
  retention claim in my bible is permanently unfalsifiable on live data** — is recorded in
  `05_GAME_DESIGN.md §9` as a conscious, owner-made trade rather than as a defect.
- **"MAGNET does nothing"** — refuted by code the lens had not opened.
- **"HUD hierarchy is inverted"** — killed on three grounds.
- **"WORLDS CYCLE FOREVER contradicts WORLD 13"** — killed; a UX nit, not a SEV2.
- **A verifier attacked my own measurement and was right.** "523 m at t = 20 s cannot be reproduced
  by the shipped tuning" — correct. My capture labels were sampling indices, not elapsed run time.
  Everything the argument rests on is distance-anchored or delta-derived and survives; the bad
  number is struck in the bible's provenance section rather than quietly repaired.

### Three inherited claims I refuted by running the app

These were handed to me as leads. All three are **false**, and all three would have propagated:

1. `02_STATE.md` ledger row 53 — *"[the first-run gate] teaches 3 of ~8 mechanics."* It teaches
   **~17 concepts across 5 pages**.
2. `HANDOFF.md` — *"Nothing in the app teaches magnet, streaks, flow, or slide timing."* All four
   are taught: magnet p5, streaks p2, flow surge p3, slide p1, SLICK p2.
3. The implicit assumption that the tutorial is opt-in. On a genuine first launch **PLAY routes
   straight into the gate**; `FIRST RUN ›` is a replay affordance.

The real onboarding defect is the *opposite* of the inherited one and worse: everything is taught
once, as text, before the player has any referent, and never again in context.

I also confirmed a refutation rather than re-filing it: **Prism's cyan→pink shift is
`isPrismatic: true` (`SkinCatalog.swift:94`), not a decree-1 violation.** Decree 1 forbids identity
changing *with the world*; Prism's identity *is* the prism. Session 002 killed this once; it is now
recorded in `05_GAME_DESIGN.md §11` so session 004+ does not file it a third time.

---

## 5. The three things that worry me most

**1. The game is 3,200 metres long and does not know it.** Everything — the infinite world ladder,
the 13,400-coin deep rungs, the leaderboard, the 12,000 m soak test — is built on the premise that
distance is an axis of challenge. Past 3,200 m it is an axis of *patience*. The whole endgame
superstructure rests on content that does not exist, and no amount of art will fix it. This is one
tuning seam away from being solvable: `Spawner.maxIndex` already gates by prefix index, so the hook
for a second act is sitting there unused.

**2. The economy rewards the opposite of the game.** Gems are 76–88% of coin income. Distance is
~7% of coins and ~12% of score. Style — the design's own stated skill premium — is capped at 80
coins a run and the autopilot farms it. Meanwhile the coin trail is deliberately painted on the
provably safe lane, so collecting gems is not even a decision. The game pays you the most for the
activity that requires the least, and it ranks you on the one it barely pays for.

**3. Nobody will ever know if any of this is right.** The charter bans analytics as a compliance
commitment — a principled choice I am not contesting. But it means this document is the last word
on Prism Rush's retention, forever, and this document is one designer's inference from a bot run
and a clean install. Every fix shipped from this audit is a bet placed with no scoreboard. Rayan
should make that trade knowingly rather than discover it after launch.

---

## 6. What I could not check, and what it would take

| Unchecked | What would resolve it |
|---|---|
| **Real reaction budget in ms** | The renderer's true draw distance from `Render/`, not `spawnHorizon` 115 m. One lens measured ~65 m visible; unverified. The bible names this as the number it still owes. |
| **Whether any of this affects real retention** | Nothing available. The charter bans analytics; see worry #3. |
| **How the curve feels to a human at the cap** | A human play session at 3,000 m+. The bot is an instrument, not a player — it has perfect information and zero input latency. |
| **Whether the tutorial is retained** | Ask five people to play cold and then name the magnet. I cannot run a playtest. |
| **Haptics, audio grate, juice at the cap** | A device. AUDIT-004 + AUDIT-005. |
| **Whether the 5-page gate is skipped in practice** | Session-1 funnel data, which cannot exist. |

---

## 7. Open questions for Rayan

Carried forward, plus two of mine. Do not block on them.

1. **PR-0411 is a money bug on a paid product** (decree 5). It survived verification at SEV1. Worth
   your eyes before Phase 2 pricing work.
2. **PR-0254 (revive eligibility) — my ruling:** revived runs should count for missions and XP and
   be **leaderboard-ineligible**, exactly the rule checkpoint runs already follow (iron rule 10).
   Currently a revived run is *partly* counted, which is the worst available answer.
3. **PR-0414 is a reversal request, not a bug.** "Coins are the path" was a deliberate v1.6 owner
   change. It is also why routing has no decision in it. You cannot have both; pick one knowingly.
4. **PR-0296 (attract track through the hub cards) — ruled.** Measured on a clean launch: the
   magenta grid crosses the "HEAD START ×1" glyphs and a solid band cuts the CHARACTERS/SHOP/WORLDS
   row. That is not a neon look, it fails decree 6 (clarity beats spectacle). Filed SEV2 as
   **PR-0445**. One yes/no from you closes it either way.
5. **Should the evolved cycle be labelled a world?** I ruled it *compliant but weak* — "II" does
   real work, so it does not lie, but it dresses repetition as progression. Recommend
   "Pulse City · Cycle II" in the FURTHEST headline.
6. Unchanged and unanswered: is App Store submission still the goal and on what timescale
   (everything in Phase 2 is priced against "yes, soon"); PR-0040 (1.82 s music loop); PR-0052
   (Daily Challenge — layout guarantee or identical-experience guarantee).

---

## 8. Provenance

Every finding above was written to `docs/agent/audits/scratch/<lens>.md` by its finder and attacked
in `docs/agent/audits/scratch/verify-<lens>.md` by an independent agent before reaching this file.
Those 20 files are **gitignored** and hold roughly 450 KB of working detail — arithmetic,
pattern-by-pattern tables, line-by-line refutations — that did not fit here. **Session 004 should
mine them; they will not survive a clone.** The device screenshots (autoplay curve, FTUE, tutorial
pages, death panel) are in this session's scratchpad and are already summarised in
`05_GAME_DESIGN.md`.
