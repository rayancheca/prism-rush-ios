# AUDIT 011 — the coin economy, and the plan to fix it

**Session 011. Owner-triggered.** Verbatim: *"what does x5 mean in the [HUD] and why am i getting so
many coins. why would anyone spend 20$ on 40 coins if they can just get it in on run… coins tie into
everything so you cant just change one function… always plan extremely before implementing."*

Measured by five parallel scouts driving the shipped `Autopilot` through the real `GameCore`, plus
three hostile verifiers reading the source independently. Working files:
`s011_econ_{faucet,sinks,iap,hud,role}.md` and `s011_econverify_*.md` in `audits/scratch/`.

---

## 1. What is actually true

### 1.1 The `×5` — the owner's first question

`HUDView.gemMultPill` (`HUDView.swift:219-235`) renders `◆ [label] [value]`, where the **label slot**
holds `"×\(snap.mult)"` when `mult > 1` and the word `"GEMS"` only when `mult == 1`. The value is
`snap.gems`.

`mult` reaches its ×5 cap at **124 m / 7.16 s / 20 gems** and holds it for **90.3% of a clean run**.
So in practice the chip **never says what it is**: for nine tenths of every run it reads
`◆ ×5 24,523` — a multiplier, a number, and no noun anywhere.

And `mult` **does not touch coins**. It multiplies `score` only; every currency line deliberately
omits it (`GameCore.swift:641, 685`, comment at `:638-640`). The chip therefore pairs a *score*
multiplier with a *currency* figure, which is precisely the misreading the owner reported.

### 1.2 The `24,523`

`snap.gems` is `GameCore.gemCount`, which is not a count of gems but a **currency accumulator**:
`+1` per gem (`+2` under a doubler, `+3` under a boost), `+5`/`+12` per ring. Gems convert to coins
**1:1** at payout (`GameView.swift:802`). Reaching 24,523 takes **~54 minutes of unbroken running**
(measured, 3 seeds: 53.6 / 55.0 / 54.3 min). No debug flag inflates it. So the number was real, from
a very long run — not from a normal one.

### 1.3 The faucet

Shipped `Autopilot`, real `GameCore`, 40 seeds, `mult = 1`:

| distance | seconds | gems | dist | worlds | style | bounty | **total** | coins/min |
|---|---|---|---|---|---|---|---|---|
| 800 m | 42.2 | 217 | 22 | 5 | 16 | 0 | **259** | 369 |
| 1,500 m | 73.6 | 511 | 42 | 5 | 27 | 0 | **586** | 478 |
| 3,300 m | 136.7 | 979 | 94 | 20 | 43 | 150 | **1,286** | 564 |

**Gems are 76–87% of every payout. Style — the only skill term — is hard-capped at 80 coins/run
(`XPCurve.styleCoins`: `min(closes + slicks, 40) * 2`), about 6%.** The game pays for pickup, not
for play.

Nothing caps coins per run. Stacking ceiling is **12 coins per gem** (doubler ×2 + boost +1 → 3, ×
payout multiplier 4).

### 1.4 The sink cannot absorb it

- Nothing in the game costs more than **23 minutes**.
- 11 characters (24,100) + 11 worlds (59,400) = **83,500 coins ≈ 2 h 22 m** for the entire catalogue.
- Level-ups grant ~**13,050 coins** of free power-up inventory across L1→L30, undercutting the one
  sink that does affect play.
- Mystery Box EV is **242.7 against a 300 price — −19%**.
- Buying deep worlds **forfeits Game Center submission, reach credit and achievements**
  (`ProfileStore.swift:274-292`), so 71% of the catalogue makes runs count for *less*.

### 1.5 The real monetisation break

Not pack size — **arbitrage**. The Coin Surge pack costs **450 coins** and returns **+3,858**
(+7,716 with Double Coins): **8.6×–17× ROI, repeatable, uncapped**. You can mint currency with
currency. Beside that, `$0.99 → 1,200 coins` is worth **less than one good run**.

### 1.6 What the verifiers killed

- **"Coins buy nothing that changes play" — REFUTED.** Revives, power-up charges, world starts and
  the Mystery Box all affect a run. Cosmetics are only **29%** of the fixed sink. The problem is
  income versus sink, not the absence of a sink.
- **"The IAP packs are worthless" — PARTIALLY-CONFIRMED.** True for the $0.99 tier against a good
  run; false for $4.99/$9.99/$19.99 and false against an ordinary run. The Coin Surge arbitrage is
  the finding worth acting on.
- **"The ×5 badge misreads" — CONFIRMED**, and the legibility half proved stronger than claimed.

---

## 2. The owner's four decisions (S-011)

1. **A mid-tier character should cost ~30–45 minutes.** Cut income ~6×; full catalogue 15–25 h.
   Cut the FAUCET rather than raise prices, so in-run numbers stay small and readable.
2. **Skill should pay much more.** Uncap style; near-misses, clean streaks and risky lines become the
   major variable share. Gems become the steady baseline, skill the upside.
3. **Coin Surge becomes earned, never bought** — so spending coins to make coins is structurally
   impossible rather than merely priced out.
4. **IAP should genuinely matter** — faucet, sinks and pack sizes tuned together.

---

## 3. The plan

Ordered so each step is independently verifiable, and so the two that touch the SPAWN stream (and
therefore cost a `layoutVersion` bump) are **avoided entirely**. Every change below is a payout or UI
change: gem *placement* is untouched, so `layoutVersion` stays at 11 and the solvability proof,
`PatternOrderTests` call counts and the daily goldens are all unaffected.

### E1 — separate the gem from the coin *(the keystone)*
Gems keep doing their three in-run jobs — draw the route, fuel the blast charge, feed score — and
stop being currency at 1:1. Introduce `Tuning.coinsPerGemDivisor`; `lastCoinsFromGems` becomes
`gemCount / divisor`. This is the single biggest lever (76–87% of income) and it costs no spawn
change. **Verify:** headless payout probe at 800 / 1,500 / 3,300 / 12,000 m.

### E2 — uncap and enrich style
`XPCurve.styleCoins` loses `min(…, 40)` and gains a rate that makes skill the upside, plus credit for
flow surges (already tracked, currently pays score only). **Verify:** the same probe, plus a
lagged-bot pass so the number moves with skill rather than with distance.

### E3 — re-weight the flat terms
`distance / 35` and `worlds × 5` and the 150 Warden bounty are re-scaled against the new total so no
single flat term dominates, and so a 54-minute run cannot mint a catalogue.

### E4 — Coin Surge becomes a reward
Remove it from the coin shop; grant via missions / level-ups / daily. Kills the arbitrage by
construction. **Verify:** grep that no `spendCoins` path can reach a coin-multiplying consumable.

### E5 — the HUD chip tells the truth
The `×N` moves off the gem chip (it multiplies SCORE, so it belongs on the score readout) and the gem
chip always carries its noun. **Verify:** simulator screenshot at `mult > 1`.

### E6 — re-price against the new faucet
Character prices, world ladder, pack prices, revive cost, Mystery Box EV and the IAP pack sizes are
re-checked against measured coins/min so that: a mid character is 30–45 min, the catalogue is
15–25 h, the Box is not negative EV, and each IAP tier is a meaningful shortcut rather than a
rounding error. **Verify:** a table in the session log, derived from the probe, not from intent.

### E7 — the level-up giveaway
~13,050 coins of free power-ups across L1→L30 is re-scaled so it remains a real on-ramp without
erasing the only play-altering sink.

### Deliberately NOT in scope
- Gem *density* on the track (spawn change → `layoutVersion` 12; the pre-armed pin exists but this
  rework does not need it).
- Removing coin packs (owner chose "IAP should genuinely matter").
- The infinite world ladder's Game-Center forfeiture — real, but a separate decision.

---

## 4. Open items this audit created

- **PR-0401** — "the coin sink buys nothing that alters play": **amend, do not close.** The verifier
  refuted it as written. The true statement is narrower: *cosmetics are 29% of the fixed sink, and
  income outruns every sink by ~6×.*
- **Coin Surge arbitrage** — new, SEV1 until E4 lands.
- **Mystery Box −19% EV** — new, SEV2.
- **Deep-world purchase forfeits Game Center / achievements** — new, SEV2, needs an owner call.
- **`DifficultyCurveTests.seeds` are not independent.** They are built as
  `i × 0x9E3779B97F4A7C15 + offset`, which is the exact Weyl increment `SplitMix64.next()` adds every
  call — so the 64 "seeds" are 64 adjacent offsets into ONE master sequence, not 64 streams. At
  shallow draw depth they have not decorrelated, and a per-index histogram shows it (index 9 drew
  **0 times in 1,596 eligible draws** in one band). It does not invalidate any shipped behaviour, but
  every per-band statistic in that file is less independent than its seed count implies. SEV3.
