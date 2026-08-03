# S-017 · HOSTILE VERIFY of `s017_missions-economy.md`

## VERDICT: **PARTIALLY REFUTED**

The factual spine is real and unusually well built — I re-derived it and it holds. The **proposal**
does not: three of its four headline recommendations are blocked by a single `guard` the
investigator never opened, its own Option-2 price tag is under-counted by ~20%, and its "the tests
protect you" reassurance is false for exactly the rows it proposes to re-price.

**Provenance note:** the brief and the file both say HEAD `ba9655d`. Actual HEAD is **`8af1814`**,
four commits later (`git diff --stat ba9655d..HEAD` = `HANDOFF.md`, `Tools/workflows/s017_*` only —
**zero source drift**). Findings stand; the header is stale.

---

## 1. WHAT SURVIVES (verified line-by-line, re-derived independently)

**Every `file:line` in §1–§4 is verbatim and at the stated line**, with one exception (§2 below). I
opened all of them: `MissionCatalog.swift:80, 90-97, 100-109, 114-122, 125-140, 148, 152-160, 165,
168-176, 57, 58, 61, 62, 92, 127, 135, 139, 163-164`; `ProfileStore.swift:296, 297, 316, 341, 345,
328-331, 370-373, 385-396, 541-558, 562-590, 584, 586, 619, 626-645`; `GameView.swift:797, 936,
1006, 1012, 979-999`; `GameCore.swift:461`; `Tuning.swift:19, 323, 332, 336, 392`;
`XPCurve.swift:127-129, 135-137`; `ShopValue.swift:85, 89-96, 143-152`; `IAPCatalog.swift:27-40`;
`SkinCatalog.swift:97, 112, 223`; `MissionsView.swift:120-135, 445, 461, 526`;
`MissionsTests.swift:71, 113, 120, 165`; `ProgressionTests.swift:285, 310`; `s016:98-105, 134-136,
180-183, 440, 604`. All correct.

**Finding D — CONFIRMED.** `grep -rn "completionBonus\|boardBonus\|allMissionsComplete\|perfectDay\|missionStreak" PrismRush/ Tests/` → 0 matches. There is no board-completion bonus.

**§1.2 — CONFIRMED to the digit.** I reimplemented SplitMix64 (`RNG.swift:10-27`, `unit()` =
`next()>>11 × 2⁻⁵³`) and `dailySlots`/`weeklySlots` in Python from scratch, seeds
`UInt64(bitPattern:) ^ 0x4D49_5353_494F_4E53` / `^ 0x5745_454B_4C59_3133`, and got:
`DAILY min 280 max 400 mean 345.0959`, distribution `280×7 300×41 320×53 340×102 360×96 380×45
400×21`, `chest2 boards 137/365 = 37.53%`, the same seven boards for 20668–20674, and
`WEEKLY min 1900 max 2500 mean 2228.8462 → 318.4066/day`, dist `1900×3 2000×5 2100×6 2200×14
2300×12 2400×8 2500×4`. **Ceiling 663.5/day — confirmed.** Pool means 115.0 / 742.857 — confirmed.

**§1.4 — CONFIRMED.** `grep -rn coinMultiplier PrismRush/` → 4 hits, of which the only *consumption*
is `GameView.swift:936`; the other three are `Profile.swift:91` (the computed property),
`ShopView.swift:489` and `IAPCatalog.swift:31` (comments). Missions are genuinely not doubled.
*(Bonus defect the file could have caught: `IAPCatalog.swift:32` still says the site is
`GameView.swift:696`. Stale by 240 lines.)*

**§2/§3 — CONFIRMED.** 663/3118 = 21.26%, /4292 = 15.45%, /6640 = 9.98%. 83,500 ÷ those = 26.78 /
19.45 / 12.57 days — reproduces `s016:134-136` exactly. 12,320/83,500 = 14.75%; /59,400 = 20.74%.
663.5 ÷ 2,001 coins-per-$ × 30 = **$9.95/player-month** and 40,000/663.5 = **60.29 days** — both
correct. Mystery-Box coin-axis EV: 0.42·200 + 0.22·350 + 0.075·600 + 0.025·1400 = **241** ✓;
full EV 300.5 ✓.

**§4 — CONFIRMED** apart from one row (§2 below). I recomputed all 26 effort rows off 78.3 coins/min,
2.287 min/run, 42 gems/run, n≈22.9 near-misses/run (84 ÷ 3.667 — the `styleCoins` inversion at
`XPCurve.swift:127-129` with `flowPerSurge = 3` is right) and a 60/40 close/slick split. `ach.runs`
t3 = 1.117% tip on 179,000 incidental ✓. `day.slide10` = 5.5 s = 1,393% ✓. `ach.chests` t2 = 5.71%
commission on 14,000 ✓. The `.slid` edge-trigger claim is exact: `GameCore.swift:461`
`if !wasSliding { emit(.slid(x: px)) }` counts **inputs**, and `run.slide5`'s title
("Slide under 5 bars", `:92`) is a live decree-2 violation. `runsFinished` really does `return 1`
with no floor (`:58`), and `recordRunResults()` really does fire on any `.died` (`GameView.swift:797`).

**§9's layoutVersion claim — CONFIRMED, not a violation of iron rule 3.** `MissionCatalog` uses two
private domain tags and `:163-164` states it never feeds `startRun(seed:)`. Nothing in §5 touches
Core/, the spawner or the RNG stream. No bump, no bot re-run needed.

**No third-party art, names or trademarks are proposed for shipping.** §7 cites Subway Surfers /
Temple Run 2 / Jetpack Joyride as *research with links only*. Clean — but the owner's "ciopy subway
surfers" line must stay a structural lesson, never a literal asset or name.

---

## 2. WHAT IS REFUTED — with my own derivation

**R1 — "Range across days: 320 – 757/day" (§1.2) is wrong.** My joint enumeration of
`daily[d] + weekly[d//7]/7` over the same 365 days: **min 551.4, max 742.9, mean 663.88**. Neither
endpoint they quote is reachable — 320 is below the *daily-only* minimum of 280 plus the *weekly*
minimum of 271.4, and 742.9 (not 757) is the true ceiling because no 400-daily lands in a
2,500-week in that window. **Corrected: 551 – 743 coins/day.**

**R2 — Option 2's headline "+52% / 1,007 coins/day" contradicts its own table.** The table
(§5.2) lists four deltas: daily rows **+58**, daily board **+241**, weekly rows **+13**, weekly
board **+103**. 663.5 + 58 + 241 + 13 + 103 = **1,078.5**. They report 1,007 — which is
663.5 + 241 + 103 exactly, i.e. **the two row-re-price deltas were listed and then dropped from the
total.** Corrected Option 2: **1,078/day = +62.5%** (not +52%); **$16.16/player-month** (not $15.10,
so **+$6.21** over today, not +$5.15); days-to-catalogue @15 min = 83,500/(1,174+1,280+1,078) =
**23.6 days, −3.2** (not 24.1, −2.7); @30 = 18.0, @60 = 11.9. **§8 question 1 asks the owner to
approve a bill that is ~20% understated.** The recommendation itself survives — Option 2 is still
under half of Option 1's $23.34 — but the number he is being asked to sign off on must be fixed.

**R3 — §4.5's "mission reward literals are test-pinned by value" is materially false, and it is the
most dangerous line in the file** because it tells the next agent a safety property that does not
exist. The complete census of *literal* reward pins in the suite is: `MissionsTests.swift:113, 120`
(`run.mult5` = 150), `:145, :147, :153` (`ach.gems` = 50/200/1,000), `:165` (`ach.dist` t1 = 150).
That is **it**. `MissionsTests.swift:71` and `ProgressionTests.swift:285, 286, 310` assert against
`slot.rewardCoins` — self-referential, they pass at **any** value. So of the **21 rows §5.4 proposes
to re-price**, only two (`ach.gems` t1/t2) have a value pin; **all 8 daily rewards, all 7 weekly
rewards, `ach.close`, `ach.slick`, `ach.runs`, `ach.worlds`, `ach.chests` and 5 of 6 per-run feats
can be re-priced silently and green.** Corrected §4.5: *the daily/weekly/most-achievement re-price
is exactly the silent retune the file says it cannot be — a value pin per re-priced row must be
ADDED as part of the change, not assumed to already exist.*

**R4 — `run.gems60` "1.6 runs" (§4.2).** 60 ÷ 42 gems/run = **1.43 runs**, not 1.6 → incidental
256, tip **46.9%**, not 41.9%. (Their tip is internally consistent with 1.6, so the error is the
run count.) Minor; does not move any conclusion.

**R5 — `Mission.Metric.revives` is declared at `MissionCatalog.swift:36`, not `:35`.** Line 35 is
`case gems, distance, nearMisses, slides, slickBonuses, runsFinished`. The rest of that bullet
(dead metric, permanently 0 because `summary.revives = core.revivesUsed` at `GameView.swift:1012`
sits in the `else` of `if statsRecorded` at `:979/:990`) is **confirmed** — the code even says so at
`:998`.

---

## 3. WHAT IS MISSING — the cases the proposal does not handle

**M1 (blocking, kills three §5 recommendations) — `claimMission` refuses a zero-coin reward.**
`ProfileStore.swift:578`: `guard state.claimable, state.reward > 0 else { return nil }`. §5.4's
"achievement tier 3s stop paying currency and unlock a character instead" therefore makes those
tiers **permanently unclaimable**; and because `achievementTier[id]` is advanced *only* inside
`claimMission` (`:584`), the field the character unlock reads never increments. `SkinCatalog`'s
`.achievement(id:tier:)` unlocks (`SkinCatalog.swift:168, 174, 211`; pinned
`SkinCatalogTests.swift:58, 142-152, 185`) key off exactly that field — **so the promised character
would never unlock.** The same `guard` kills §5.2's "per-run feats pay power-up charges instead of
coins (~0 coin cost)". §8 question 2 gestures at a reward *type* but never names the guard, the
`Int?` return, or `MissionState.reward: Int` (`:504`) — all three must change together.

**M2 (the biggest omission, and it contradicts §6.0's clean bill of health) — earned-but-unclaimed
daily missions are destroyed at UTC midnight.** `refreshDailyMissions` (`ProfileStore.swift:385-396`)
removes `missionProgress` **and** `claimedMissions` for every daily id on a day change, with no
banking of completed-but-unclaimed rewards. Finish all three at 23:58 UTC, background the app, and
360 coins evaporate. `MissionsTests.swift:62-78` pins this wipe for the *claimed* case only. §6.0
certifies "what the board advertises is exactly what `claimMission` pays" and praises the D5-2
CLAIM-ALL fix — but the board itself silently voids an advertised, already-earned bonus for a
completely normal situation (closing the app). That is decree 3 and decree 5 territory and it is the
single most literal instance of "not rewarding at all" in the whole surface. **Unmentioned.**

**M3 — daily clock-rollback re-rolls the board while keeping banked progress.** There is a
`testWeeklyClockRollbackBlocked` (`ProgressionTests.swift:305-317`); **there is no daily analogue.**
Trace it: `:74` clamps a future `dailyMissionDate` down to `now`, then `:387`
`if let last …, utcDayKey(min(last, now)) == today { return }` takes the early return, so **no wipe
runs**. The board rendered is the *rolled-back* day's 3 slots (e.g. 20670 `chest2+slick6+gems150`
→ 20668 `slick6+runs5+dist3k`), while `missionProgress` survives — and off-board daily missions
accumulate quietly the whole time (`ProfileStore.swift:495-496` bumps **every** `dailyPool` entry
with a matching metric; `:568` says so). Any slot on the older board that is over target and not in
`claimedMissions` is instantly claimable, repeatable across many past days. The weekly test proves
only that the *same* id can't re-pay. **A real economy exploit, in the exact area audited, unflagged.**

**M4 (gate-weakening the file does not disclose) — §5.3's "delete `day.chest2`, delete `ach.chests`"
deletes a test.** `MissionsTests.swift:168-174` (`testChestOpensFeedChestMissions`) asserts
`missionProgress["ach.chests"] == 2` and `missionProgress["day.chest2"] == 2`. Removing both
missions leaves `Metric.chestsOpened` with zero consumers and forces that test to be **deleted, not
updated** — while §4.5 of the same file says "do not weaken those assertions." It must be stated as
a deliberate gate removal with `chestsOpened` retired from `Metric` in the same commit. Separately,
shrinking `dailyPool` 8 → 7 re-rolls **every player's board on every past and future day** and
invalidates the file's own §1.2 enumeration; nothing catches it, because
`MissionsTests.swift:55-60` only asserts `Set(boards).count > 1`.

**M5 — §5.4's `ach.gems` re-price (t1 50→100, t2 200→900) does break real pins**
(`MissionsTests.swift:145, 147`) — the one place the file's "tests protect you" claim is true, and
it is not called out.

**M6 — brand-new profile.** §2.1 books passive income at 1,000/day from the day-7 login tier
(`dailyTiers` `:296`, clamp `:316`), but `pendingDailyStreak` (`:305-313`) starts at 1: days 1–6 pay
100/150/200/300/400/500. A fresh player is short **4,350 coins** across week 1, so every
"days to catalogue" figure (26.8 / 19.5 / 12.6 and all the Option deltas) is optimistic by ~1–1.5
days. Inherited from S-016, but it should be stated once rather than silently carried.

**M7 — decree 2 / decree 4 on the achievement-exclusive characters.** "Not in the shop and never on
sale" (§5.4) leaves them with no preview surface. Decree 2 requires menu hero, select swatch, shop
card and tease renders to match in-game; decree 4 requires the tease to lead somewhere. The
proposal needs a locked-but-visible presentation, otherwise it ships content with no preview path.

**M8 — no grandfathering plan for deleted missions.** §6.2 grandfathers partial progress for the
tier-3 character swap (correctly — `achievementTier` persists, `:584`) but says nothing about a
player sitting at 80/100 on `ach.chests` when it is deleted: 800 coins of visible, banked progress
vanishes. Iron rule 7 keeps the *decode* safe (`Profile.swift:160`, `decodeIfPresent ?? default`),
but the player-facing loss is a decree-3 "broken-looking state for an expected situation."

---

## 4. CORRECTED TEXT

- §1.2 last line → **"Range across days: 551 – 743/day."**
- §5.2 table → mission coin-axis **1,078/day, +62.5%**; felt value **1,163/day**; days to catalogue
  **23.6 / 18.0 / 11.9**; **$16.16/player-month (+$6.21)**. §8 question 1 → **"+$13.39, +$6.21 or
  +$0.00"**.
- §4.2 `run.gems60` → **1.43 runs · 3.3 min · 256 incidental · 46.9% tip.**
- §4.5 bullet 2 → **"Only `run.mult5` (150), `ach.gems` (50/200/1,000) and `ach.dist` t1 (150) are
  pinned by literal. Every daily reward, every weekly reward and 15 of 18 achievement tiers assert
  only `slot.rewardCoins` and pass at any value — the §5.4 re-price is silent today. Add a value pin
  per re-priced row as part of the change."**
- §4.5 bullet 1 → `MissionCatalog.swift:**36**`.
- §5.2/§5.4/§8 q2 → prepend: **"`ProfileStore.swift:578` guards `state.reward > 0`, and
  `achievementTier` advances only inside `claimMission` (`:584`) — which is the field
  `SkinCatalog.achievement(id:tier:)` unlocks read. A non-coin reward is unclaimable and its
  character never unlocks until that guard, `MissionState.reward: Int` (`:504`) and
  `claimMission`'s `Int?` return are restructured together."**
- **New §4.6, ahead of everything in §5:** M2 (midnight destruction of unclaimed completed dailies)
  and M3 (daily clock-rollback free claims). Both are zero-coin fixes, both are decree-3/5 issues,
  and both must land before any re-price — a curve fitted over a board that deletes its own payouts
  is fitted to noise, which is the file's own argument for §5.3.
- §6.0 heading → **"the mission layer's CLAIM path is clean today; the board's rollover path is
  not."**
- §5.3 → add: **"deleting `day.chest2` / `ach.chests` deletes
  `MissionsTests.testChestOpensFeedChestMissions` (`:168-174`) and retires `Metric.chestsOpened`;
  it also re-rolls every historical and future daily board (pool 8 → 7). Declare both."**
