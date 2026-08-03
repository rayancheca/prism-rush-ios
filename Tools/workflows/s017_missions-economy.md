# S-017 · missions-economy — "not rewarding at all", costed

**READ-ONLY pass at HEAD `ba9655d` (branch main, clean). No source file was modified, no build, no
simctl.** Every number below is either quoted from a `file:line`, derived in Python from those
literals (scripts reproduced inline), or quoted from a prior *measured* probe with the probe named.
Where a figure is an estimate rather than a measurement it says so and gives the method.

Built on `docs/agent/audits/scratch/s016_coins-economy.md`, which mapped every coin source and sink.
Its §1.1 faucet, §1.3 sink census and §1.5 ratio are **used, not redone**. Siblings this pass:
`s017_missions-inventory.md` (what the system is), `s017_missions-does-nothing.md` (consequence).

---

## 0. THE ANSWER, UP FRONT

> The owner said four things. This file only answers **"not rewarding at all."**

**The complaint is correct, but the diagnosis in the brief needs one correction, and the correction
changes the fix.**

| # | finding | number |
|---|---|---|
| **A** | **The mission layer is NOT primarily too small — it is the wrong KIND of reward.** `Mission` can express exactly one reward: `let rewardCoins: Int` (`MissionCatalog.swift:80`), and `claimMission` does exactly one thing with it — `$0.coins += state.reward` (`ProfileStore.swift:586`). **No mission in this game can pay XP, a consumable, a Mystery Box, a character, or anything else. Ever.** The currency it pays is the one S-016 proved buys the whole finite catalogue in 26.8 days (`s016_coins-economy.md:136`). One reward type × a currency with nothing left to buy = "not rewarding" is *literally* true. | 1 reward type, 28 missions |
| **B** | **A daily mission pays LESS than the free chest, which requires zero play.** Median daily mission = **120** (`MissionCatalog.swift:101-108`). Free chest = `Int.random(in: 60...220)`, mean **140**, every 30 min, no daily cap (`ProfileStore.swift:297, 341`). **A mission is 86% of a chest.** And 12% of a day-7 login (1,000, `ProfileStore.swift:296`). | 120 vs 140 vs 1,000 |
| **C** | **Mission income is HARD-CAPPED at 663 coins/day and does not scale with anything.** Everything else in the game is unbounded. So the better you play, the less missions matter: **21.3% of a 15-min/day player's income, 15.5% at 30 min, 10.0% at 60 min** (§2). The brief's "under ~15% ⇒ the fix is numeric" test is therefore **met for a committed player and NOT met for a casual one** — see §2.3 for why that makes the numeric fix the *second* priority, not the first. | 663/day, flat |
| **D** | **There is no completion bonus anywhere.** `grep -rn "completionBonus\|boardBonus\|allMissionsComplete\|perfectDay\|missionStreak" PrismRush/ Tests/` → **0 matches, all five**. Finishing all three dailies pays the sum of three rows and nothing more. Every reference game in §7 pays a chest/box/key for the *board*, not the row. | 0 |
| **E** | **Three missions pay for doing nothing and two of the biggest pay a 1.1% tip on 38 hours.** The effort model is not merely mis-tuned, it is absent — the same ladder position costs 69 minutes on `ach.dist` and 38 hours on `ach.runs`, and pays 1,500 vs 2,000 (§4). | see §4.3/§4.4 |

**The one-line fix, and it is not a bigger number:** give `Mission` a reward *type*, pay the daily
board's completion with a **Mystery Box**, and terminate the achievement ladders in **characters that
coins cannot buy**. That is what the reference games do (§7), it costs the coin economy +52% instead
of +135% (§5), and it is the only version that does not shorten an already-27-day game.

**No decree-5 violation exists in the mission layer today** (§6.0). That is worth stating positively:
what the board advertises is exactly what `claimMission` pays, including CLAIM ALL's `+total`.

---

## 1. WHAT A MISSION PAYS — EXACT NUMBERS

### 1.1 The whole catalogue, verbatim

**Per-run feats** (`MissionCatalog.swift:90-97`) — claimable once, forever:

| id | title | metric | target | pays |
|---|---|---|---|---|
| `run.mult5` | Hit a ×5 multiplier in one run | `multiplierHit` | 5 | **150** |
| `run.slide5` | Slide under 5 bars in one run | `slides` | 5 | **100** |
| `run.gems60` | Collect 60 gems in one run | `gems` | 60 | **120** |
| `run.close8` | Thread 8 CLOSE calls in one run | `nearMisses` | 8 | **150** |
| `run.dist2k` | Travel 2,000 m in one run | `distance` | 2,000 | **200** |
| `run.warden1` | Defeat a Warden | `wardensDefeated` | 1 | **250** |
| | | | **lifetime total** | **970** |

**Daily pool** (`MissionCatalog.swift:100-109`) — 3 of 8 drawn per UTC day by
`dailySlots` (`:152-160`), SplitMix64 over the day number ^ `0x4D49_5353_494F_4E53` (`:148`):

| id | title | pays |
|---|---|---|
| `day.close15` | Score 15 CLOSE bonuses today | **140** |
| `day.slick6` | Score 6 SLICK bonuses today | **140** |
| `day.gems150` | Collect 150 gems today | **120** |
| `day.dist3k` | Travel 3,000 m today | **120** |
| `day.streak18` | Reach an 18-gem streak today | **120** |
| `day.runs5` | Finish 5 runs today | **100** |
| `day.slide10` | Slide 10 times today | **100** |
| `day.chest2` | Open 2 free chests today | **80** |
| | pool mean | **115.0** |

**Weekly pool** (`MissionCatalog.swift:114-122`) — 3 of 7 per UTC week, `weeklySlots` (`:168-176`),
tag `0x5745_454B_4C59_3133` (`:165`):

| id | pays | | id | pays |
|---|---|---|---|---|
| `wk.close75` | **900** | | `wk.gems1k` | **700** |
| `wk.slick35` | **900** | | `wk.runs30` | **600** |
| `wk.dist20k` | **800** | | `wk.slide60` | **600** |
| `wk.streak25` | **700** | | pool mean | **742.9** |

**Achievement ladders** (`MissionCatalog.swift:125-140`) — 18 tiers, each pays once:

| id | title | targets | rewards | ladder total |
|---|---|---|---|---|
| `ach.gems` | Gem Hoarder | 100 / 1,000 / 10,000 | 50 / 200 / 1,000 | 1,250 |
| `ach.dist` | Marathoner | 10k / 50k / 100k m | 150 / 500 / 1,500 | 2,150 |
| `ach.close` | Needle Threader | 100 / 1,000 | 200 / 1,200 | 1,400 |
| `ach.slick` | Limbo Legend | 50 / 500 | 150 / 1,000 | 1,150 |
| `ach.runs` | Veteran Runner | 25 / 250 / 1,000 | 100 / 500 / 2,000 | 2,600 |
| `ach.worlds` | World Walker | 3 / 6 / 12 | 100 / 300 / 1,500 | 1,900 |
| `ach.chests` | Chest Hunter | 10 / 100 | 100 / 800 | 900 |
| | | | **lifetime total** | **11,350** |

**The single largest payout in the entire mission system is 2,000 coins** (`ach.runs` tier 3,
`MissionCatalog.swift:135`). **That is less than world 4** (2,200, `XPCurve.swift:135`).

### 1.2 Per day — the REAL distribution, not the mean

The 3-slot draws are deterministic, so this is enumerable rather than estimated. Python
reproducing `SplitMix64` (`Core/RNG.swift:10-17`) and `dailySlots`/`weeklySlots` exactly, over the
365 days from `daysSinceEpoch = 20668` (2026-08-03):

```
DAILY  365 days:  min 280   max 400   mean 345.1
  distribution: 280×7  300×41  320×53  340×102  360×96  380×45  400×21
  boards containing day.chest2 (a wall-clock mission): 137 / 365 = 37.5%
  next seven boards:
    20668  slick6+runs5+dist3k            = 360
    20669  streak18+gems150+slick6        = 380
    20670  chest2+slick6+gems150          = 340
    20671  slick6+runs5+streak18          = 360
    20672  slick6+close15+chest2          = 360
    20673  dist3k+chest2+streak18         = 320
    20674  slide10+close15+streak18       = 360
WEEKLY 52 weeks:  min 1,900  max 2,500  mean 2,228.8  →  318.4 / day
  distribution: 1900×3 2000×5 2100×6 2200×14 2300×12 2400×8 2500×4
```

**Mission income ceiling = 345.1 (daily) + 318.4 (weekly amortised) = 663.5 coins/day.**
Range across days: 320 – 757/day. Plus 12,320 one-time (970 + 11,350).

### 1.3 What the challenge tier is, for completeness

Not a mission — `ProfileStore.challengeTiers = [(1_000, 100), (5_000, 150), (15_000, 250)]`
(`ProfileStore.swift:619`), ≤500/day, paid by `recordChallengeRun` (`:626-645`). It lives on a
different screen and is excluded from the 663 above (as S-016 did) so the two files agree.

### 1.4 The Double-Coins IAP does NOT touch mission claims

`profile.coinMultiplier` is consumed at exactly one site, `GameView.swift:936`
(`let mult = store.profile.coinMultiplier * (coinSurgeActiveThisRun ? 2 : 1)`). `claimMission`
(`ProfileStore.swift:579-589`) never reads it. The blurb states this correctly —
*"Every run pays 2× coins"* (`IAPCatalog.swift:35`). So **the one thing a paying player buys makes
missions relatively LESS valuable**, not more: a Double-Coins owner's run income doubles while the
mission ceiling stays at 663.

---

## 2. THE MISSION LAYER AS A FRACTION OF EVERYTHING

### 2.1 The denominator

Measured run faucet, `docs/agent/sessions/SESSION_011.md:32-37` — headless probe, shipped
`Autopilot` through the real `GameCore`, 24 seeds, `mult = 1`. The bot never chases gems or
near-misses, so `gems`/`style` are **floors** for a human:

```
  dist(m)   secs   gems  dist  worlds  style  bounty   TOTAL   coins/min
      800   42.1     10     4       3     24       0      41       58.4
     3300  137.2     42    19      12     84      22     179       78.3
    12000  411.1    148    70      45    339      88     691      100.9
```

A **"good run" = 3,300 m = 2 min 17 s = 179 coins = 78.3 coins/min.** That is the profile used
throughout this file.

Passive income (no play at all): day-7 login **1,000** (`ProfileStore.swift:296`, clamped `:316`)
+ two free chests **280** (mean 140 each, `:341`, 30-min interval `:297`, **no daily cap**) =
**1,280 coins/day for opening the app twice.**

### 2.2 The share table

| play pattern | run coins | passive | **missions** | total/day | **mission share** | days to the 83,500 catalogue |
|---|---|---|---|---|---|---|
| 15 min/day | 1,174 | 1,280 | **663** | 3,118 | **21.3%** | 26.8 |
| 30 min/day | 2,348 | 1,280 | **663** | 4,292 | **15.5%** | 19.5 |
| 60 min/day | 4,697 | 1,280 | **663** | 6,640 | **10.0%** | 12.6 |

*(The three totals reproduce `s016_coins-economy.md:134-136` exactly, which is the cross-check that
the two files share one model.)*

### 2.3 **Reading this honestly**

The brief said: *"If it is under ~15% the owner is objectively right and the fix is numeric."* By
that test the mission layer is **borderline** — under 15% only for a heavy player. So I will not
pretend the numeric case is open-and-shut. **Three comparisons are far more damning than the share,
and all three point at reward TYPE and STRUCTURE rather than magnitude:**

1. **Missions pay 51.8% of what showing up pays.** 663 (all six missions, every day, perfectly)
   against 1,280 (login + two chests, zero play). **The game pays roughly twice as much for
   opening the app as it does for completing every objective it sets you.**
2. **One mission (120) is 86% of one free chest (140).** The unit of reward the player *feels* — one
   card, one CLAIM tap — is worth less than a thing that happens to them while they are in a menu.
3. **Mission income is the only income in the game with a ceiling.** Run coins, chest coins and
   challenge tiers all scale with time or skill. 663/day is fixed. So the player who most wants a
   reason to engage — the one already playing an hour a day — gets the *smallest* relative return
   from the entire missions feature. That is the exact inverse of what a mission system is for.

**Conclusion: the fix is not "multiply 120 by 3". It is (a) a second reward type, (b) a board-level
completion prize, (c) an effort-indexed curve. The numbers in §5 follow from those three.**

---

## 3. WHAT IT BUYS — MISSIONS AGAINST THE REAL SINKS

Sinks and prices from `s016_coins-economy.md:98-105`, re-verified at HEAD:
`SkinCatalog.swift:112,116,128,133,138,157,162,180,198,205,238` (characters),
`XPCurve.swift:135-137` (worlds), `ShopValue.swift:85` (Mystery Box 300),
`ShopValue.swift:89-96` (packs 250/250/300/350).

**Days of PERFECT mission completion (663/day, every daily + every weekly, no misses):**

| sink | price | **days of perfect missions** | as multiples of ONE daily mission (120) |
|---|---|---|---|
| Mystery Box | 300 | **0.45** | 2.5 missions |
| Ember — the cheapest thing in the game | 200 | **0.30** | 1.7 missions |
| Slow-Mo / Speed-Up pack (+3) | 250 | 0.38 | 2.1 |
| Head Start pack (+3) | 300 | 0.45 | 2.5 |
| Shield pack (+3) | 350 | 0.53 | 2.9 |
| World 1 | 400 | 0.60 | 3.3 |
| Fang — the authored "week-1 savings goal" (`SkinCatalog.swift:97`) | 2,500 | **3.8** | 20.8 |
| Monarch — dearest character | 7,500 | **11.3** | 62.5 |
| World 11 — dearest single item | 13,400 | **20.2** | 111.7 |
| all 11 characters | 24,100 | 36.3 | 200.8 |
| all 11 worlds | 59,400 | 89.5 | 495.0 |
| **the whole permanent catalogue** | **83,500** | **125.9** | **695.8** |

**The three sentences that matter:**

- **No single mission in the daily or weekly pool can buy the cheapest item in the game.** The
  dearest daily mission is 140; Ember is 200 (`SkinCatalog.swift:112`).
- **You must complete 2.5 daily missions to open one Mystery Box** — the object the whole S-016
  monetization plan is built around (`ShopValue.swift:85`).
- **The entire lifetime mission + achievement layer (12,320 coins) is 14.8% of the catalogue** and
  **20.7% of the world ladder alone.** A player who 100%s every achievement in the game has earned
  less than world 11 costs.

---

## 4. THE EFFORT / REWARD CURVE

### 4.1 Method, stated plainly

Per-run rates at the 3,300 m profile: 2.287 min/run, 179 coins/run, **42 gems/run**, 78.3 coins/min
(`SESSION_011.md:32-37`). Near-misses per run are **derived, not measured**: `styleCoins` is
`((closes + slicks) × 2 + surges × 5)` (`XPCurve.swift:127-129`, `Tuning.swift:332,336`) and a surge
is every 3rd near-miss (`Tuning.swift:392`, `flowPerSurge = 3`), so `style ≈ n × 3.667` and the
measured 84 → **n ≈ 22.9 near-misses/run**.

**NOT FOUND — the closes/slicks split and the per-run slide count.** No probe in the repo reports
them; `grep -rln "slidesThisRun" docs/` returns 11 documents, none of which carries a measured
per-run rate (they discuss the plumbing). Rows below that need the split say so and assume 60/40.

"Incidental" = coins the *same effort* already pays from the run faucet. "Tip %" = mission
reward ÷ incidental. **A tip below ~20% means the mission is invisible next to the coins you were
going to earn anyway; above ~100% means the mission, not the running, is the reason to do it.**

### 4.2 Every mission, costed

**Daily pool:**

| mission | pays | effort | incidental coins | **tip** |
|---|---|---|---|---|
| `day.dist3k` | 120 | 0.9 runs · 2.1 min | 163 | **73.7%** ✔ |
| `day.slick6` | 140 | 0.7 runs · 1.5 min | 117 | **119.5%** ✔ |
| `day.close15` | 140 | 1.1 runs · 2.5 min | 195 | **71.7%** ✔ |
| `day.streak18` | 120 | ~1.5 runs · 3.4 min | 268 | 44.7% |
| `day.gems150` | 120 | 3.6 runs · **8.2 min** | 639 | **18.8%** ✗ |
| `day.runs5` (played honestly) | 100 | 5 runs · **11.4 min** | 895 | **11.2%** ✗✗ |
| `day.runs5` (degenerate — see 4.3) | 100 | ~1 min of instant deaths | 78 | 127.7% |
| `day.slide10` | 100 | **5.5 seconds of tapping** | 7 | **1,394%** ✗✗ |
| `day.chest2` | 80 | **60 min of wall clock, zero play** | — | **1.7%** ✗✗ |

**Weekly pool:**

| mission | pays | effort | incidental | tip |
|---|---|---|---|---|
| `wk.slick35` | 900 | 3.8 runs · 8.7 min | 684 | 131.6% ✔ |
| `wk.streak25` | 700 | ~4 runs · 9.1 min | 716 | 97.8% ✔ |
| `wk.close75` | 900 | 5.5 runs · 12.5 min | 977 | 92.1% ✔ |
| `wk.dist20k` | 800 | 6.1 runs · 13.9 min | 1,085 | 73.7% ✔ |
| `wk.gems1k` | 700 | 23.8 runs · **54.4 min** | 4,262 | **16.4%** ✗ |
| `wk.runs30` | 600 | 30 runs · **68.6 min** | 5,370 | **11.2%** ✗✗ |
| `wk.slide60` | 600 | **33 seconds of tapping** | 43 | **1,394%** ✗✗ |

**Per-run feats:**

| mission | pays | effort | tip |
|---|---|---|---|
| `run.dist2k` | 200 | 0.6 runs | 183.2% ✔ |
| `run.warden1` | 250 | ~1 run to the first Warden | 139.7% ✔ |
| `run.mult5` / `run.close8` | 150 each | ~1 run | 83.8% ✔ |
| `run.gems60` | 120 | 1.6 runs (bot floor is 42/run) | 41.9% |
| `run.slide5` | 100 | **2.8 seconds** | **2,787%** ✗✗ |

**Achievement ladders — this is where it falls apart:**

| tier | pays | effort (runs · minutes) | incidental coins | **tip** |
|---|---|---|---|---|
| `ach.worlds` t3 (world 12 in one run) | 1,500 | 1 deep run · 6.9 min | 536 | 279.7% ✔ |
| `ach.dist` t1 / t2 / t3 | 150 / 500 / 1,500 | 3 · 6.9 / 15 · 34.6 / **30 · 69.3 min** | 542 / 2,712 / 5,424 | 27.7 / 18.4 / **27.7%** |
| `ach.close` t1 / t2 | 200 / 1,200 | 7 · 16.6 / **73 · 166 min** | 1,302 / 13,022 | 15.4 / **9.2%** ✗ |
| `ach.slick` t1 / t2 | 150 / 1,000 | 6 · 12.5 / **55 · 125 min** | 977 / 9,767 | 15.4 / **10.2%** ✗ |
| `ach.gems` t1 / t2 / t3 | 50 / 200 / 1,000 | 2 · 5.4 / 24 · 54 / **238 · 544 min (9.1 h)** | 426 / 4,262 / 42,619 | 11.7 / 4.7 / **2.3%** ✗✗ |
| `ach.runs` t1 / t2 / t3 | 100 / 500 / 2,000 | 25 · 57 / 250 · 572 / **1,000 · 2,287 min (38.1 h)** | 4,475 / 44,750 / **179,000** | 2.2 / 1.1 / **1.1%** ✗✗✗ |
| `ach.chests` t1 / t2 | 100 / 800 | **5 h / 50 h of wall clock, zero play** | — | 0.4 / **0.3%** ✗✗✗ |

### 4.3 **The missions that are actively insulting**

1. **`ach.runs` tier 3 — 1,000 runs finished for 2,000 coins.** 38.1 hours of play, during which the
   run faucet pays **179,000 coins**. The achievement is a **1.1% tip on 38 hours**, and 2,000 coins
   does not buy world 4 (2,200). `MissionCatalog.swift:135`.
2. **`ach.chests` tier 2 — 100 chests for 800 coins.** 100 × 30 min interval = **50 hours of
   elapsed time**, and the chests themselves pay 100 × 140 = 14,000 coins. The achievement for
   collecting 14,000 coins pays 800 — a **5.7% commission**. `MissionCatalog.swift:139`,
   `ProfileStore.swift:297`.
3. **`ach.gems` tier 3 — 10,000 gems for 1,000 coins.** 9.1 hours at the bot floor. 2.3% tip.
   `MissionCatalog.swift:127`.
4. **`day.gems150` (120) and `wk.gems1k` (700).** The gem missions are the worst-paid in both pools
   because S-011 cut a gem from 1 coin to 1/20th of a coin (`Tuning.swift:323`,
   `coinsPerGemDivisor = 20`) **and nobody re-priced the gem missions.** Their targets were written
   against the old faucet. This is a stale-constant defect, not a design choice.

### 4.4 **The missions that pay for doing nothing**

1. **`run.slide5` / `day.slide10` / `wk.slide60` — 850 coins for ~40 seconds of tapping, total.**
   `RunSummary.slides` is fed by `slidesThisRun`, counted from `FXEvent.slid` (`GameView.swift:1006`,
   `MissionCatalog.swift:57`). `.slid` is edge-triggered on *starting* a slide
   (`GameCore.swift:461`: `if !wasSliding { emit(.slid(x: px)) }`) and re-arms after
   `Tuning.slideDuration = 0.55` s (`Tuning.swift:19`). **It counts slide INPUTS, not bars cleared.**
   Ten slides is 5.5 s of tapping on an empty track.
   **`run.slide5`'s title says "Slide under 5 bars in one run" (`MissionCatalog.swift:92`) — the
   game does not measure bars and cannot tell.** That is a decree-2 problem ("previews never lie")
   sitting inside a mission, and it is a direct hit on "not easy to understand."
2. **`day.runs5` / `wk.runs30` / `ach.runs` — 3,300 coins gated on a counter with no floor.**
   `case .runsFinished: return 1` (`MissionCatalog.swift:58`), and `recordRunResults()` fires on any
   `.died` event (`GameView.swift:797`) with no minimum distance, score or duration. A 0-metre death
   counts. `ach.runs` t3's 38 hours collapses to roughly **1.4 hours of deliberately playing badly**
   — which is worse than the 38 hours, because it makes the optimal strategy degenerate.
3. **`day.chest2` (80) and `ach.chests` (900) — 980 coins on the wall clock.** `chestsOpened` is not
   a run metric at all (`MissionCatalog.swift:61`: `return 0 // bumped by ProfileStore.openFreeChest`),
   bumped at `ProfileStore.swift:345`. **Worse: on 37.5% of days (137/365, §1.2) one of your three
   missions cannot be completed in a single sitting** — two chests need 30 minutes of wall clock
   between them (`ProfileStore.swift:297, 328-331`), so a 15-minute-a-day player must open the app
   twice, an hour apart, to clear their board. **A mission that gates on the clock rather than on
   play is the purest form of "does nothing".**

### 4.5 Two smaller economy-adjacent facts, for completeness

- **`Mission.Metric.revives` is a dead metric.** Declared (`MissionCatalog.swift:35`), given a value
  extractor (`:62`), given an SF Symbol (`MissionsView.swift:526`) — and used by **zero missions**.
  It is also permanently 0: `summary.revives = core.revivesUsed` is set at the *first* death
  (`GameView.swift:1012`), before any revive can have happened, and post-revive deaths never
  re-enter the branch (`GameView.swift:979-999`).
- **Mission reward literals are test-pinned by value** — `MissionsTests.swift:113,120` assert
  `claimMission("run.mult5") == 150`, `:165` asserts `ach.dist` t1 = 150,
  `:71` and `ProgressionTests.swift:285,310` assert against `slot.rewardCoins`. **Re-pricing missions
  is a deliberate, reviewable act, not a silent retune** — same property S-016 noted for characters
  (`s016_coins-economy.md:604`). Good. Do not weaken those assertions to make a re-price pass;
  update them with the new intent stated.

---

## 5. A CORRECTED REWARD CURVE — WITH THE PRICE TAG

**Three options, costed. The trade is the owner's: every coin a mission pays is a coin he cannot
sell.** The exchange rates that set that price (`IAPCatalog.swift:27-38`, unchanged):

| pack | coins | price | coins per $ |
|---|---|---|---|
| Pouch | 1,200 | $0.99 | 1,212 |
| Starter Bundle | 3,000 | $1.99 | 1,508 |
| Bag | 7,000 | $4.99 | 1,403 |
| Vault | 16,000 | $9.99 | 1,602 |
| **Crate** | **40,000** | **$19.99** | **2,001** ← best rate, used as the yardstick below |

**Today the mission layer gives away 663 coins/day = $0.33/day = $9.95 per player-month at the Crate
rate.** The $19.99 Crate is **60.3 days of perfect missions**.

### 5.1 Option 1 — "coins, bigger" (pure inflation; cheapest to build, worst for IAP)

Target a 30% mission share for a 30-min/day player ⇒ M = 1,557 coins/day (2.35×).
Shape: daily rows 200/200/250, weekly rows ~1,000 each, plus a 300-coin board bonus.

| | today | Option 1 | delta |
|---|---|---|---|
| mission coins/day | 663 | **1,557** | **+135%** |
| days to the 83,500 catalogue @15 min/day | 26.8 | **20.8** | **−6.0 days** |
| … @30 min | 19.5 | 16.1 | −3.4 |
| … @60 min | 12.6 | 11.1 | −1.5 |
| mission share @15/30/60 min | 21.3 / 15.5 / 10.0% | **38.8 / 30.0 / 20.7%** | |
| coin value given away per player-month | $9.95 | **$23.34** | **+$13.39** |
| the $19.99 Crate now equals | 60.3 days of missions | **25.7 days** | |

**Verdict: do not ship this alone.** It answers the complaint on the axis the complaint was *not*
mainly about, and it hands every player $23/month of the thing being sold, on a catalogue that is
already free in under a month (`s016_coins-economy.md:140-143`). **If the owner wants Option 1, it
is only defensible alongside S-016 §4.1 #2 — an infinite non-arbitrage sink.**

### 5.2 Option 2 — "boxes, not coins" (RECOMMENDED SHAPE)

**Change `Mission.rewardCoins: Int` into a reward *type*.** `ConsumableGrant` already exists in
`ShopValue.swift` and is what `mysteryReward` returns (`ShopValue.swift:143-152`) — the enum is
built, only `Mission` cannot express it.

| what | reward | coin-axis cost |
|---|---|---|
| daily rows (3) | unchanged coins, re-tiered by measured effort (§5.4) | +58/day |
| **daily board 3/3** | **1 free Mystery Box** | **+241/day** |
| weekly rows (3) | re-tiered coins | +13/day |
| **weekly board 3/3** | **3 free Mystery Boxes** | **+103/day** |
| per-run feats | power-up charges instead of coins | ~0 |
| **achievement tier 3s** | **3 achievement-exclusive characters** (new content, never on sale) | **0** |

*A Mystery Box's EV is 300.5 against its 300 price, but only **241** of that EV is coin-shaped —
26% of the table pays consumables (`ShopValue.swift:143-152`, arithmetic at
`s016_coins-economy.md:180-183`). That distinction is what makes this option cheap: the player feels
a 300-coin prize and the coin supply grows by 241.*

| | today | Option 2 | delta |
|---|---|---|---|
| mission **coin-axis** /day | 663 | **1,007** | **+52%** |
| mission **felt value** /day (boxes at face) | 663 | **1,092** | +65% |
| days to catalogue @15 min | 26.8 | **24.1** | **−2.7 days only** |
| … @30 / @60 min | 19.5 / 12.6 | 18.0 / 12.0 | −1.5 / −0.6 |
| mission share @15/30/60 min (felt value) | 21.3 / 15.5 / 10.0% | **30.8 / 23.1 / 15.4%** | |
| coin value given away per player-month | $9.95 | **$15.10** | **+$5.15** |
| box openings created per week | 0 | **4** | — |

**Why this is the right shape:** it turns the missions board into the game's second-biggest source
of Mystery Boxes, which is exactly what M7 asked for ("getting boxes should be more prominent"), and
it gives the S-016 box ceremony work four guaranteed stages a week instead of a 300-coin shop
purchase nobody makes. **It costs 39% of Option 1's IAP devaluation and shortens the catalogue by
2.7 days instead of 6.0.**

### 5.3 Option 3 — "fix the curve, spend nothing" (revenue-neutral; ship this regardless)

Redistribute the same ~663/day. **Net coin inflation: 0. Net IAP devaluation: $0.00.**

| change | coins moved |
|---|---|
| delete `day.chest2` from the pool (wall-clock gate, 1.7% tip, blocks 15-min sessions) | −80 from the pool mean |
| delete `ach.chests` entirely (900 lifetime for 55 h of elapsed time) | −900 lifetime |
| re-metric `slides` to bars actually cleared, or retarget those 3 missions onto `slicks` | removes the 1,394% and 2,787% rows |
| add a distance floor to `runsFinished` (e.g. ≥ 500 m to count) | removes the degenerate-death strategy |
| move the freed coins onto `day.gems150`, `day.runs5`, `wk.gems1k`, `wk.runs30` | +0 net |

**Option 3 fixes "not easy to understand" and the degenerate incentives. It does NOT fix "not
rewarding at all" on its own** — that is Option 2's job.

### 5.4 The concrete re-priced tables (Option 3 + Option 2 together — what I would actually ship)

Effort tiers from the measured minutes in §4.2: **A ≤ 3 min → 100; B 3–8 min → 140; C > 8 min → 180.**

**Daily pool (7 entries, `day.chest2` deleted):**

| id | measured effort | today | **proposed** |
|---|---|---|---|
| `day.dist3k` | 2.1 min | 120 | **100** |
| `day.slick6` | 1.5 min | 140 | **100** |
| `day.close15` | 2.5 min | 140 | **100** |
| `day.streak18` | 3.4 min | 120 | **140** |
| `day.slide10` → re-metric to bars cleared | (est. 3–5 min) | 100 | **140** |
| `day.gems150` | 8.2 min | 120 | **180** |
| `day.runs5` (with a 500 m floor) | 11.4 min | 100 | **180** |
| | pool mean | 115.0 | **134.3** |
| | **3 slots/day** | **345** | **403** (+17%) |
| | **+ board 3/3** | — | **1 Mystery Box** |

**Weekly pool (7 entries):**

| id | measured effort | today | **proposed** |
|---|---|---|---|
| `wk.slick35` | 8.7 min | 900 | **600** |
| `wk.streak25` | 9.1 min | 700 | **600** |
| `wk.close75` | 12.5 min | 900 | **600** |
| `wk.dist20k` | 13.9 min | 800 | **600** |
| `wk.slide60` → re-metric | (est. 20–30 min) | 600 | **700** |
| `wk.gems1k` | 54.4 min | 700 | **1,100** |
| `wk.runs30` (with the floor) | 68.6 min | 600 | **1,200** |
| | pool mean | 742.9 | **771.4** |
| | **3 slots/week** | **2,229** | **2,314** (+4%) |
| | **+ board 3/3** | — | **3 Mystery Boxes** |

**Achievement ladders — the top tier stops paying currency.** `ach.gems` t3 (9.1 h), `ach.runs` t3
(38 h) and `ach.dist` t3 each unlock **a character that is not in the shop and never goes on sale**.
Coin inflation: **0**. Catalogue days: **unchanged**. IAP devaluation: **$0.00**. And it creates the
only content in the game that money cannot buy — which is a decree-5 *asset*, not a liability
(today exactly one item is real-money-exclusive, Aurora, `SkinCatalog.swift:223`; nothing at all is
skill-exclusive).

**The tier-1/tier-2 rungs get re-priced to ~25% of their incidental** (from §4.2): `ach.gems`
t1 50→100, t2 200→900; `ach.close` t2 1,200→2,600; `ach.slick` t2 1,000→1,900;
`ach.runs` t1 100→900, t2 500→3,000. **That adds ~8,000 of one-time faucet** (12,320 → ~20,300,
14.8% → 24.3% of the catalogue) and is the single biggest coin cost in the whole proposal — it is
also the one most likely to be trimmed if the owner wants a smaller bill. **State it separately so
he can price it separately.**

---

## 6. DECREE 5 ADJUDICATION

> *"Zero ads, no dark patterns. Monetization is honest: advertised bonuses are always delivered, no
> fake urgency."* **NOT revoked.** D-050 lets three flagged mechanics ship but keeps the clause.

### 6.0 The mission layer is clean today — verified, not assumed

- **What the board advertises is what `claimMission` pays.** The UI renders `state.reward`
  (`MissionsView.swift:445, 461`) from `missionState` (`ProfileStore.swift:541-558`); `claimMission`
  pays `state.reward` from the same function (`:577-589`). No second table, no rounding.
- **CLAIM ALL's `+total` is honest across a UTC rollover.** `MissionsView.swift:120-135` computes the
  total and every claim against **one** `now`, with the reason written in the code: a live `Date()`
  per claim let a midnight rollover nil the remaining daily claims mid-cascade and pay less than the
  button promised. That was audited (D5-2) and fixed. **Do not regress it during the rebuild.**
- **No dark pattern found in the mission surface.** Unlike the Mystery Box, whose *displayed* odds
  are not its rolled odds (`s016_coins-economy.md:190-222`, SEV1 — still open at HEAD).

### 6.1 (a) SHIP — compatible with decree 5

| mechanic | why it is column (a) |
|---|---|
| Daily board 3/3 → a free Mystery Box | Earned by play, published odds, reward always delivered. |
| Weekly board 3/3 → 3 boxes | Same. |
| Achievement-exclusive characters | Content that money cannot buy. Strictly anti-pay-to-progress. |
| Re-pricing every mission to its measured effort (§5.4) | Makes the advertised reward honest about the work. |
| Deleting `day.chest2` | **Removes** a wall-clock gate. Strictly more honest. |
| Fixing `run.slide5`'s title ("Slide under 5 bars" — it counts inputs) | Decree 2. The title lies today. |
| A 500 m floor on `runsFinished` | Removes a degenerate incentive. **It makes a mission harder** — say so on the board rather than shipping it quietly. |
| Showing what a reward buys on the card ("+120 · 0.4 Mystery Box") | Pure disclosure. Answers "not easy to understand" for free. |
| A mission-completion streak that only ever ADDS | No reset, no loss framing, nothing to fear. |
| Paying per-run feats in power-up charges | Advertised, delivered, no randomness. |

### 6.2 (b) STRADDLES THE LINE — the owner must rule

| mechanic | for | against | the ruling needed |
|---|---|---|---|
| **A daily-mission streak that RESETS on a miss** (the reference game's Word Hunt does exactly this — miss a day and you drop to day 1) | The escalation is real and always paid; it is the reference loop's most-loved mechanic | It manufactures a cost for *not* playing. That is engagement pressure, not a fabricated deadline — but it is pressure | **My line: allowable only if the full ladder AND the reset rule are on the board before the streak starts.** A reset the player discovers by suffering it is a dark pattern; one they signed up for is a rule. |
| **Inflating the mission layer at all** | It is the direct answer to the complaint | It devalues the coin IAPs by $5.15–$13.39 per player-month (§5) on a catalogue already free in 27 days | **Owner picks Option 1, 2 or 3.** This is a revenue decision, not a design one. Numbers are in §5; I am not making this call. |
| **Removing coins from achievement tier 3s in favour of characters** | Turns a 1.1% tip into a real prize at zero coin cost | Removes 4,500 of expected faucet from players mid-ladder | Whether existing partial progress is grandfathered (it must be — `achievementTier` persists, `ProfileStore.swift:584`). |
| **A timed double-reward window on one daily mission** | D-050 permits real countdowns; enforce it in code and it is not fake | A window that returns every week is exactly the "recurring deadline" `s016_coins-economy.md:502` bars | Whether a *recurring* real window counts as fake urgency. **My read: a weekly-recurring window is fake; a genuinely one-time one is not.** |
| **Paying coins to re-roll one daily mission slot** (Jetpack Joyride charges 500 coins per star to skip) | An honest, infinite, non-arbitrage coin sink — which is the #1 gap S-016 §4.1 named — and it hides nothing | It monetises friction the game itself created | Whether converting a bad board into a spend is acceptable. **It is the cheapest infinite sink in this whole document.** |
| **A push notification tied to a mission expiring** | The deadline (UTC midnight) is real and already in the code (`ProfileStore.swift:370-373`) | Engineered re-engagement | Notifications in general — out of scope for this file, flagged because missions would be the trigger. |

### 6.3 (c) VIOLATES DECREE 5 AS WRITTEN — needs an explicit revocation

| mechanic | the exact clause |
|---|---|
| **Rewarded-ad mission skips** (Jetpack Joyride: skip free by watching an ad, or 500 coins/star) | *"Zero ads."* Named here because it is the reference game's actual mechanic and omitting it would make §7 misleading. |
| **A mission whose reward is randomised but whose odds are not shown** | *"Monetization is honest."* If a board bonus is a Mystery Box, the box's published odds apply and **must be reachable from the missions board**, not only from the Shop (`ShopView.swift:539` is the only presenter today, `s016_coins-economy.md:226-239`). |
| **A streak whose reward ladder is hidden until you reach it** | *"Advertised bonuses are always delivered"* presumes they were advertised. |
| **Loss-framed copy on a broken streak ("You lost your 12-day streak!")** | *"No dark patterns."* Frames a normal life event as a punishment. |
| **Missions that only complete if you spend** ("open 2 Mystery Boxes today") | *"No dark patterns."* A paid objective dressed as a mission. Note `day.chest2` is the free-chest analogue and is fine; the box version would not be. |

---

## 7. HOW SHIPPED GAMES STRUCTURE THIS

Four data points, chosen because two are the reference title the owner named (M8, "ciopy subway
surfers") and two are the closest genre neighbours.

### 7.1 Subway Surfers — Word Hunt (the daily objective)

Collect the day's letters during runs. **The reward ladder is: days 1–2 a Mystery Box, days 3–4
coins, day 5 onward a *Super* Mystery Box — and the streak resets to day 1 on a miss.**
([Subway Surfers Help Center](https://sybo.helpshift.com/hc/en/5-subway-surfers/faq/134-word-hunt/),
[Wiki](https://subwaysurf.fandom.com/wiki/Word_Hunt))

**The lesson, and it is the whole thesis of this file: in the reference game, coins are the WORST
rung of the daily-objective ladder.** They sit *below* the entry-level box. Prism Rush's mission
system can only pay the rung the reference game uses as a consolation prize.

### 7.2 Subway Surfers — Daily Challenges and the login ladder

Completing all three daily challenges yields **3 Keys plus 2,000+ coins**; the daily-login ladder
runs **day 1 = 100 coins → day 7 = 2 Keys → day 30 = a premium character or board**.
([vocal.media walkthrough](https://vocal.media/gamers/how-to-complete-missions-and-earn-rewards-in-subway-surfers),
[Theria Games coin guide](https://theriagames.com/guide/subway-surfers-coin/))

Three structural gaps this exposes, all confirmed in our code:

1. **A board-completion bonus exists there and does not exist here.** (§0-D: 0 grep matches.)
2. **The ladder terminates in CONTENT, not currency** — day 30 is a character. Our login ladder is
   `[100, 150, 200, 300, 400, 500, 1000]` and **flat-lines at 1,000 forever** from day 7
   (`ProfileStore.swift:296`, clamped `:316`). There is no day 30.
3. **The board pays premium currency (Keys).** Prism Rush has exactly one currency
   (`s016_coins-economy.md:440`), so the mission board has nothing scarce to hand out. That is the
   structural reason a mission reward *cannot* feel special here today.

### 7.3 Temple Run 2 — daily and weekly challenges

Daily streak: **day 1 = 250 coins, day 2 = 500, day 3 = 750, day 4 = 1,000, day 5 = 5,000–15,000
coins or 1–25 gems.** Weekly: **1,000 coins, then 5,000 coins, then 10 gems.** Objectives come three
at a time and feed a level ladder that pays coins, gems and power-ups.
([Temple Run Wiki — Daily Challenge](https://templerun.fandom.com/wiki/Daily_Challenge),
[Objectives](https://templerun.fandom.com/wiki/Objectives_(Temple_Run_2)),
[Udonis teardown](https://www.blog.udonis.co/mobile-marketing/mobile-games/temple-run-2))

**The lesson: escalation.** Temple Run 2's daily reward multiplies **20–60× across one week**. Prism
Rush's daily missions are a flat 80–140 on day 1 and a flat 80–140 on day 400 (§1.2: mean 345.1,
σ small, no time term anywhere in `dailySlots`). **Nothing in our mission system gets better the
longer you play it.**

### 7.4 Jetpack Joyride — the designer's own price for a mission

Three missions active at a time; each pays 1–3 stars; **a mission can be skipped for 500 coins per
star**, or free by watching an ad. Levelling from missions pays **400–6,000 coins per rank**.
([Jetpack Joyride Wiki — Missions](https://jetpackjoyride.fandom.com/wiki/Jetpack_Joyride/Missions),
[Currency](https://jetpackjoyride.fandom.com/wiki/Currency))

**This is the single most useful number in the section, because it is a revealed preference: the
designer priced one mission at 500–1,500 coins by charging that to make it go away.** Prism Rush
pays **80–140** for the same object. **By the reference game's own skip price, a Prism Rush daily
mission is worth 4–12× what it pays.**

### 7.5 The general pattern

Industry writeups of daily-mission systems converge on **progression + a mystery container**: the
reward scales with engagement rather than sitting flat, and the terminal reward of a board is
concealed until opened.
([GameRefinery — progression in daily rewards](https://www.gamerefinery.com/feature-spotlight-progression-daily-rewards/),
[Beamable — daily login reward design](https://beamable.com/blog/inspiring-examples-of-daily-login-rewards-for-your-mobile-game))
Prism Rush's board has neither: every reward is a known integer, revealed before you start, that
does not grow.

---

## 8. WHAT THIS FILE ASKS THE OWNER TO DECIDE

1. **Option 1, 2 or 3 (§5).** The bill: **+$13.39, +$5.15 or +$0.00** of granted coin value per
   player-month, buying **−6.0, −2.7 or −0.0 days** off the 26.8-day catalogue. **My recommendation
   is 3 + 2**, but the trade belongs to him.
2. **Does `Mission` get a reward TYPE?** Everything in Option 2 depends on it. It is a small change
   (`MissionCatalog.swift:80`, `ProfileStore.swift:501-509, 577-589`) with a `Profile`-schema
   consequence if boxes are banked rather than opened inline (iron rule 7: `decodeIfPresent ?? default`).
3. **Does a mission streak reset on a miss?** §6.2 row 1.
4. **Do achievement tier 3s stop paying coins and start unlocking characters?** §5.4. Zero coin cost,
   requires new characters authored (cheap now that D-046 revoked the asset decree).
5. **Ship the revenue-neutral cleanup regardless?** §5.3 — deleting `day.chest2`, deleting
   `ach.chests`, re-metricising `slides`, flooring `runsFinished`. **None of it costs a coin and all
   of it is required before any re-price is meaningful**, because a curve fitted over exploitable
   missions is fitted to noise.

---

## 9. SCOPE NOTES / WHAT I DID NOT DO

- **Nothing here touches Core/, the spawner, the RNG or `DailyChallenge.layoutVersion`.** Missions
  are meta-layer only (`MissionCatalog.swift` uses `SplitMix64` with its own domain tags at
  `:148, :165`, and the file's own comment at `:163-164` states it "never feeds `startRun(seed:)`,
  so it has zero layoutVersion implications"). **No bump required for anything in §5.**
- **Everything in `MissionCatalog`, `RunSummary` and the `ProfileStore` mission block is
  Linux-testable** (`Package.swift`), so the whole re-price pins in `swift test -c release` without
  a Mac build. The claim UI does not.
- **NOT MEASURED, and it gates §5.4's two "re-metric" rows:** per-run slide count and the
  closes/slicks split. `grep -rln "slidesThisRun" docs/` → 11 files, none with a measured rate.
  A headless probe counting `FXEvent.slid` / `.nearMiss(kind:)` per run at 3,300 m would cost one
  test run and would firm up `day.slide10` / `wk.slide60` / `day.close15` / `day.slick6`.
- **Out of scope, deliberately:** the board's visual craft (`s017_missions-does-nothing.md` and the
  design passes), the Mystery Box's SEV1 odds mismatch (`s016_coins-economy.md:190-222` — still open
  at HEAD and should land regardless of this session), and the world-purchase forfeiture
  (`s016_coins-economy.md:510-591`).

---

*Derivation scripts (SplitMix64 board enumeration + the effort/reward table) were run at
`/private/tmp/claude-501/.../scratchpad/mis.py` and `eff.py`. Both are pure restatements of the
literals cited above and are reproducible from this file alone.*
