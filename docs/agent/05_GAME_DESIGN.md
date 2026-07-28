# Prism Rush — Design Bible

**Owned by AUDIT-002 (session 003). Update when the design changes, not when the code changes.**

This is the document the project never had. Everything here derives from `Core/Tuning.swift`,
`Meta/`, and a measured device session — not from `reports/design/`, several of whose decisions
the owner later revoked.

**Ground rule:** the six owner decrees in `CLAUDE.md` outrank every statement in this file. Where
this file argues against a decree it is filed as a *revocation request* and says so.

**Measurement provenance.** Numbers tagged **[M]** were measured on device this session: iPhone 17
Pro simulator `10C15FE0…`, autoplay bot, 20 screenshots at 10 s intervals spanning 143 m → 5,331 m
of one uninterrupted run, plus a clean-install FTUE pass (uninstall → install → launch → tutorial
→ death). Numbers tagged **[C]** are computed from source constants.

**A correction to my own instrument, found by adversarial review.** The capture labels `t000…t190`
are *sampling indices*, not elapsed run time: the first screenshot fired ~10 s after `simctl
launch`, which includes app start and an unknown autoplay warm-up. So "523 m at t = 20 s" is
**not** reproducible from the shipped tuning and should never be quoted — at `speedStart` 17 m/s,
20 s of real running is ~360 m.

What survives is everything the argument actually rests on, because it is **distance-anchored or
delta-derived, not absolute-time-anchored**:
- the per-interval speed table in §3 (differences between consecutive 10 s captures — unaffected
  by any start offset), and its flat 33.5–33.7 m/s tail;
- "×5 by the 143 m / 32-gem sample and in all 20 frames" (distance-anchored);
- the 0.365 gems/m rate (a ratio over the sampled span);
- "5,188 m across 190 s of sampling" = 27.3 m/s mean, consistent with the ramp.

Nothing in this bible is from vibes, and the one number that was from a sloppy instrument is
struck above rather than quietly repaired.

---

## 1. What the player is actually doing

### The moment-to-moment loop (0.5–3 s)

> **Read the lane ahead → pick one of four responses (stay / lane / jump / slide) → live or die.**

The verbs are exactly three plus "do nothing": `changeLane`, `jump`, `slide` — the only entry
points `GameCore` exposes (input at `UI/GameView.swift:893-911`). No attack, no in-dodge resource
spend, no sub-lane positioning. Lane position is discrete-3, so the entire spatial decision space
of this game is **three cells wide**.

The one real texture is that jump and slide are *timed*, not merely chosen: `jumpBuffer` 0.25 s
forgives an early press, `slideDuration` 0.55 s commits you, and SLICK rewards sliding at the last
instant [C]. That is the only continuous skill axis in the game.

**Where it breaks.** The gesture binds to `onEnded` — it fires on finger *lift*, not gesture start
(`UI/GameView.swift:1058`; flagged in `07_ARCHITECTURE.md §11`). A three-lane runner whose lane
change waits for you to let go has an input-latency floor no `jumpBuffer` tuning can remove.
Quantifying it in ms is AUDIT-004's; it is noted here because it caps how good this loop can feel.

### The run loop (45 s – 3 min)

> **Start → survive an escalating track → die → see a number → run again.**

Real lengths [C], speed 17→33 m/s: 1,000 m ≈ 45 s, 3,000 m ≈ 110 s, 6,000 m ≈ 200 s. The measured
bot run spanned 143 m → 5,331 m across 190 s of sampling (27.3 m/s mean) and was still alive [M].

**Where it breaks:** it stops escalating. See §3. Past ~3,300 m the run loop has no second act.

### The meta loop (between runs)

> **Coins → buy a skin or a deeper start → look different → run again.**

**Nothing purchasable in this game changes how the game plays.**

- 24 characters are cosmetic: colour, shape, eye style, idle animation, trail
  (`Meta/SkinCatalog.swift`). No stat, no handling change, no ability. `applySkin`
  (`Render/Reality/RealityRenderer.swift:701`) is render-side.
- 12+ worlds are a palette plus a start offset (§6).
- The only things that touch play — Shield, Head Start, Coin Surge, Slow-Mo, Speed-Up — are
  *pre-run consumable charges*, each modifying one run.

**This is a decoration loop, not a progression loop.** A player at run 500 owning everything plays
*exactly the same game* as a player at run 5 owning nothing. Every other economy finding in this
document is downstream of that sentence.

---

## 2. The first 60 seconds

Measured on a genuine clean install, not a launch hook (launch hooks leave stale profile state —
`PR_FIRSTRUN` returned a profile reading `FURTHEST 15 · 11,200M`). **[M]**

| Beat | What actually happens | Verdict |
|---|---|---|
| t=0 | Splash: "PRISM RUSH", cyan Prism, **TAP TO START**. Never auto-dismisses. | Deliberate; costs one tap. |
| +1 tap | Hub: 0 coins, `FURTHEST 01 · PULSE CITY`, LVL 1. Full-width gradient **PLAY**, small `FIRST RUN ›` chip beneath. `REWARDS CLAIM +100` is a solid amber card — second-loudest element. `DAILY RUSH · ENDS 10:27` shows a live countdown. | Hub is genuinely good. |
| tap PLAY | **PLAY does not start a run.** It opens a mandatory 5-page tutorial carousel. | See below. |
| pages 1–5 | CONTROLS (lane/jump/slide) · SCORING (streak ladder ×1–×5, CLOSE, SLICK) · RINGS & FLOW (rings, overdrive pads, flow surge) · WORLDS (new world/800 m, checkpoints, *"your character never changes — only the world does"*) · POWER-UPS (Shield, Magnet, Doubler, Chrono, Continue). | **~17 concepts before the player has moved once.** |
| run start | 17 m/s. Patterns 0–4 only until 260 m. First guaranteed power-up at 150 m. | Correctly gentle. |
| first death | Measured passive run: **72 m, score 132, +1 coin, +16 XP.** | §8 — the worst moment in the game. |

### The onboarding is inverted — and two inherited claims are wrong

Refuted on device:

- `02_STATE.md` ledger row 53: *"teaches 3 of ~8 mechanics."* **False** — ~17 concepts, 5 pages.
- `HANDOFF.md`: *"Nothing in the app teaches magnet, streaks, flow, or slide timing."* **False on
  all four** — magnet p5, streaks p2, flow surge p3, slide p1, slide *timing* (SLICK) p2.

The real defect is the opposite one, and it is worse:

> **Everything is taught once, as text, before the player has any referent for any of it — and
> then never again, in context, ever.**

A player who has never seen a prism ring reads a paragraph about scoring a bullseye at the apex.
Retention from a 17-concept carousel read before first input is near zero. There is no
first-ring callout, no first-magnet callout, no "that was a CLOSE." The information is present;
the teaching is absent. → **PR-0402**.

### Does the first death read as the player's fault?

Yes — a genuine strength. At 72 m only patterns 0–4 exist, speed is 17 m/s, `gap` is near
`gapMax` 11. Dying there means ignoring a single telegraphed obstacle on an empty track. That reads
as "I wasn't paying attention," not "that was unfair." **Pass. Do not let anyone re-tune the early
tier.**

---

## 3. The difficulty curve, and where it stops

### Computed [C]

`speed(d) = 17 + 0.0052·d` capped 33 → **cap at 3,077 m**.
`diff(d) = min(1, d/3200)` → `gap` lerps 11 → 5, **flat from 3,200 m**.
`Spawner.maxIndex`: `<260 m` → 0–4 · `<576 m` → 0–8 · `<1,440 m` → 0–10 · `<1,920 m` → 0–12 ·
**`≥1,920 m` → full catalogue.**

| Distance | Speed | New content |
|---|---|---|
| 0–260 m | 17.0–18.4 | teach set (patterns 0–4) |
| 260–576 m | 18.4–20.0 | zigzag, mixed, pickup, double bar |
| 576–1,440 m | 20.0–24.5 | prism rings, overdrive runways |
| 1,440–1,920 m | 24.5–27.0 | gauntlet, split bars |
| **1,920 m** | 27.0 | **moving walls — the last new thing in the game** |
| 3,077 m | 33.0 | speed cap |
| 3,200 m | 33.0 | density cap |
| 3,200 m → ∞ | 33.0 | **nothing** |

### Measured [M] — speed per 10 s interval from the HUD

```
143→328   18.5      1,921→2,160  23.9
328→523   19.5      2,160→2,455  29.5
523→730   20.7      2,455→2,767  31.2
730→947   21.7      2,767→3,038  27.1
947→1,177 23.0      3,038→3,315  27.7
1,177→1,389 21.2    3,315→3,652  33.7  ← cap
1,389→1,654 26.5    3,652→3,989  33.7
1,654→1,921 26.7    3,989→4,324  33.5
                    4,324→4,660  33.6
                    4,660→4,995  33.5
                    4,995→5,331  33.6
```

**Five consecutive intervals at 33.5–33.7 m/s.** Score rate is equally flat: 5,874 points over
337 m at 3.6 km; 6,171 over 336 m at 5.0 km. The curve is empirically dead from ~3,300 m.

### The flow channel

Held well from 0 to ~2,000 m: content arrives every few hundred metres, speed climbs steadily.
This part is good design and should not be touched — and v1.7 does not touch it (act two's
intensity is exactly zero below 3,200 m, pinned by `testActOneIsUnchangedByTheSecondAct`).

Then the game ran out. **From 3,200 m to infinity, speed, density and pattern set were all
constant.** A 4,000 m run and a 40,000 m run were the same run. The player did not exit the flow
channel upward into anxiety; they exited downward into boredom, at roughly the two-minute mark of
a good run.

**Reaction budget** is deliberately left open: it requires the renderer's true draw distance, not
`spawnHorizon` 115 m, and reading `Render/` was out of this audit's budget. Named in §11 as the
one number this bible still owes.

### Act two — what v1.7 (S-004) changed [C, verified M]

**Speed does NOT rise past the cap, deliberately.** The readable lead is hard-capped at ~65 m by
the opaque backdrop plane (`RealityRenderer.swift:756`) — 1.97 s at 33 m/s — and pushing it back
was tried and reverted in v1.6. Faster would be unreactable, which is a worse game, not a harder
one. Act two is therefore a **second escalation axis over the same speed**, on four mechanisms,
all zero-RNG and all keyed off `Spawner.intensity` (0 at 3,200 m → 1 at 9,600 m):

| Mechanism | Act one | Act two |
|---|---|---|
| Pattern mix | uniform over all 14 | weighted table, 3 waves; breathers get rarer, nothing is ever removed |
| Inter-pattern gap | 11 → 5 by 3,200 m, then flat | 5 → 4 by 9,600 m |
| Moving walls (pattern 13) | phase 0 — parked at centre, both outer lanes safe forever | phase swings to ±0.75·intensity; past ~6,800 m exactly one lane is open |
| Gem lines | one safe breadcrumb | + a greed line in a lane the pattern closes (§7) |

Waves are **front-loaded** (intensity 1/6 and 1/2, i.e. 4,267 m and 6,400 m) because a good run is
about two minutes ≈ 3,300 m: an escalation whose first real step lands at 5,300 m is one almost
nobody meets.

**Measured [M]** — `DifficultyCurveTests`, mean of 64 seeds, bands snapped to pattern boundaries
(a fixed band grid aliases against the ~451 m cycle and manufactures a fake trend):

```
  band(m)      obst/100m  inputs/100m  gems/100m  priced%  rest%   phase
      0- 1200       5.28         3.01       41.2     0.7%  35.9%   act 1
   1200- 2400       5.61         3.68       42.2    10.5%  28.4%   act 1
   2400- 3200       6.02         3.93       42.2    13.3%  27.1%   act 1  ← the old plateau
   3200- 4267       6.40         4.42       39.5    11.4%  19.4%   act 2 w1
   4267- 6400       7.49         4.80       38.6    13.8%  12.6%   act 2 w2
   6400- 9600       7.63         4.44       40.4    14.6%  12.4%   act 2 w3
```

Against the plateau: **obstacles +27%, Autopilot inputs +13%, obstacle-free track −54%.**
For comparison, v1.6 measured 5.7 obst/100 m, 3.4 inputs/100 m and ~32% rest flat across the
entire 3,000–8,000 m stretch, with no trend in any column.

`obst/100m` for act one reproduces independently: a closed-form sum over the catalogue's lengths
at the cap gives 5.99 against the instrument's 6.02.

**What is still flat, honestly:** speed, score-per-metre, and the world cosmetics' rate of change.
Act two buys *density and decisions*, not pace. Whether that is enough to hold a player past five
minutes is not something a headless instrument can answer — it needs playtesting.

---

## 4. The mastery ceiling — the SEV1

The persona's own test: *if the answer is "nothing after run 20", that is why the game dies.*

| Skill | Mastered by |
|---|---|
| Lane change / jump / slide | run 1–2 (taught explicitly) |
| Reading the 14 patterns | run 10–20 — finite catalogue, fully unlocked at 1,920 m |
| Slide timing (SLICK) | run 5–15 — the only continuous-timing skill |
| Gem routing | ~~run 5~~ → **open-ended since v1.7**: past 1,440 m the greed line and the safe line diverge, so routing is a live risk/reward call rather than a guarantee |
| Ring aiming | run 10 |
| Near-miss courting | run 20 |
| Power-up timing | run 5 |
| Reading a swung moving wall | **new in v1.7** — past ~6,800 m the safe lane must be read, not remembered |

**After run ~20 the game has nothing left to teach.** The evidence was structural:

1. The pattern catalogue is 14 entries, fully unlocked at 1,920 m (`Spawner.maxIndex`).
   **Still true** — v1.7 shifts the mix, it does not add a 15th pattern.
2. ~~Difficulty is flat past 3,200 m (`Tuning.diffFullAt`)~~ — **addressed in v1.7 (S-004)**: see
   §3's act-two table. Obstacle density, input load and rest share all move to 9,600 m now.
3. **The survival layer requires zero reward-layer reasoning.** `Core/Autopilot.swift` reads only
   `c.activeObstacles` — grepping the file for `activeGems`, `activePickups`, `gemCount`, `score`
   and `bonus` returns **zero occurrences**. A fixed greedy policy with a 30-unit horizon
   (`Autopilot.swift:19`) survives 200 seeds × 6,000 m with zero deaths plus a 12,000 m soak
   (`SolvabilityBotTests.swift:17-26`). No routing decision, no resource decision, no risk/reward
   trade is required to survive anything the game can generate.

   **Still true of the SURVIVAL layer after v1.7, and deliberately so** — the bot must stay green,
   that is iron rule 2. What changed is that surviving is no longer the same as *scoring*: the
   greed line pays roughly 2× the safe breadcrumb and costs a timed lane exit, so the bot's
   permanently-safe policy is now a permanently *poor* one. That is a real risk/reward trade for a
   human, and it is invisible to the bot — which is also why `SolvabilityBotTests` cannot certify
   it, and why `testEveryGreedGemLeavesATakeableExit` exists as a separate fairness proof.

~~Points 1–2 carry the SEV1.~~ → **PR-0400: point 2 fixed in S-004 (v1.7)**; point 1 stands (the
catalogue is still 14) and is now the residual argument for a 15th pattern, filed separately.

**Correction, recorded so it is not overstated later.** "A bot beats it, therefore there is no
skill ceiling" is a *category error* and this bible does not make that claim. The bot has perfect
information at 30 units regardless of draw distance or occlusion, actuates at 120 Hz, and has zero
input latency, while the human path fires on finger *lift*. `SolvabilityBotTests` exists to prove
**fairness** (iron rule 3), and it does. The correct, narrower claim is that **depth here is
execution-only**: the game asks for reflexes, never for a decision. That is → **PR-0409 (SEV2)**,
separate from PR-0400.

**Is there an expression ceiling instead?** Barely. Score rewards risk (CLOSE +40, ring +150), so
a skilled player scores more per metre. But §5 shows the coin economy pays ~88% for gem hoovering
and ~3% for style — the reward structure tells the player expression is worth nothing. The two
currencies point in opposite directions.

---

## 5. The economy, computed

### Faucet [C, calibrated by M]

Per run (`UI/GameView.swift:696-711`), all × `coinMultiplier`:

```
coins = gems×1  +  floor(distance/35)  +  5×(worlds crossed)  +  min(closes+slicks, 40)×2
```

Measured gem rate: **1,948 gems over 5,331 m = 0.365 gems/m** [M] — the greedy-bot ceiling.

| Run | Dist | Coins | gems | distance | worlds | style |
|---|---|---|---|---|---|---|
| first death (measured) | 72 m | **+1** [M] | ~0 | ~2 | 0 | 0 |
| bad | 300 m | 121 | 90% | 7% | 0% | 3% |
| average | 1,000 m | 418 | 87% | 7% | 1% | 5% |
| good | 3,000 m | 1,246 | 88% | 7% | 1% | 4% |
| great | 6,000 m | 2,478 | 88% | 7% | 1% | 3% |

**Gems are 87–90% of all coin income at every run length.** The other three terms are rounding
error. Distance — the thing the game is named for, on the leaderboard, in 48 pt on the HUD — pays
**7%**. Crossing a world, the entire progression spine, pays **five coins**. Style, the only term
rewarding *playing well*, is hard-capped at 80 coins and lands at **3%**.

The same skew runs through score: at 5,331 m, `distance×2` = 10,662 of a 91,072 total ≈ **12%**
[M]. **Running far is ~10% of both currencies in a game about running far.**

The death panel splits the payout into four components as if the player has four levers. They
have one. → **PR-0401 (SEV1)**.

Worse, gems are *optional*. The measured passive run paid **+1 coin over 72 m** [M] where the
greedy rate predicts ~28. **Coin income swings ~12× on gem collection alone**, and gem collection
is the one activity that pulls you off the safe line. Meanwhile the leaderboard ranks *score*. The
optimal coin strategy and the optimal score strategy diverge, and the game never says which it
wants.

### Sinks [C]

| Sink | Total | Repeatable |
|---|---|---|
| 11 coin skins (200 … 7,500) | 24,100 | no |
| 11 world rungs (400 … 13,400), then +2,000 forever | 59,400 + ∞ | no / ∞ |
| Power-up packs (250–450) | — | yes |
| Mystery Box | 300 | yes |
| Revive | 150/use | yes |
| **Permanent collection** | **83,500** | |

### One-time vs repeatable faucets

Level-up grants total **10,300 coins across the whole 30-level ladder** — 12% of the collection,
paid once ever. Everything else must come from runs, and 88% of that is one optional activity.

### Time to collection [C]

| Milestone | Cost | At 418 coins/run (average, gem-hoovering) |
|---|---|---|
| First skin (Ember) | 200 | run 1, with the +100 free chest |
| First world skip | 400 | run 1–2 |
| **Full collection** | 83,500 − 10,300 one-time | **~175 runs ≈ 2.2 h of running** |

**Verdict: accidentally generous, and mis-aimed.** 2.2 hours to exhaust every permanent sink is
short — but only if you play as a gem hoover. Play the way the HUD, the leaderboard and the game's
title all tell you to, and the same collection takes ~12× longer. The curve is not tuned generous
or punishing; it is tuned for a player the game never asks you to be.

### Dead ends

- **The deep world ladder.** Rungs past ~7,400 cost hours and buy a *starting palette*. Past rung
  11 the price grows +2,000 forever against a flat faucet — an infinite sink that can never be
  cleared.
- **Level 30.** 69,600 cumulative XP, per-run XP capped at 2,000, then the ladder simply stops. No
  prestige, no post-30 currency.
- **Mystery Box.** Cost 300; coin EV 192, full EV including consumables ≈ 243 → **19% house edge**
  (36% on coins alone). Odds are honestly disclosed and sum to 100% (session 002 verified), so this
  is **not** a decree-5 violation. It is a net coin destroyer sold beside coin packs, and it is the
  only variable-ratio reward in the game (§7).

---

## 6. Worlds: a reskin, not a reward

`Spawner.fill(to:dist:rng:emit:)` takes **`dist` and nothing else**. `Patterns.run(idx, base:,
rng:, out:)` takes **no world parameter**. Grepping `world` across `Core/Spawner.swift` and
`Core/Patterns.swift` returns exactly one hit, in a doc comment about absolute distance.

**There is no world-conditional logic anywhere in the spawn path.** It is structurally impossible
for a world transition to introduce a mechanic, a pattern, or a demand.

Therefore: **crossing into a new world every 800 m changes the palette and the sky and nothing
else. The 800 m transition is a reskin, not a reward.** It is dressed as the progression spine —
the hub headline is `FURTHEST 01 · PULSE CITY`, the tutorial spends a page on it, coins pay 5 per
crossing — and it delivers a colour change. → **PR-0403 (SEV2)**.

### The infinite ladder — three rulings the handoff assigned to me

Past world 12 the ladder continues as "Pulse City II", "Geode Deep II", … with a genuinely evolved
palette (`Theme.evolvedPalette`), verified on device by session 002 and again here
(`FURTHEST 15 · SOLAR SANDS II · 11,200M` [M]).

1. **Is reaching 9,600 m for one a reward?** No. At the 33 m/s cap that is ~5 minutes of
   flat-difficulty running for a recoloured sky. The cost is real; the payload is not.
2. **Should a reskin be labelled a new world?** Closest thing here to a decree question. Decree 2
   says previews never lie; decree 5 forbids fake value. Naming a Pulse City recolour "Pulse City
   II" is *honest about being a variant* — the "II" does real work. I rule it **compliant but
   weak**: it does not lie, but it dresses repetition as progression. Recommend labelling the
   evolved cycle as a tier ("Pulse City · Cycle II") rather than as a new world in the FURTHEST
   headline.
3. **Is the price ladder progression?** No — a treadmill. Prices escalate forever (+2,000/rung)
   against a flat faucet, buying a cosmetic start offset. → **PR-0404**.

---

## 7. Reward schedules

### The near-miss window is genuinely tuned — a refutation, not a finding

`nearMissInner` 1.25 · `nearMissOuter` 1.95 · lane pitch 2.2 · `laneHitHalfWidth` **1.25**.

The inner edge is *exactly* the collision half-width. The CLOSE band is therefore
`[death boundary, 1.95]` — it begins at the precise point you stop dying. That is principled and
non-arbitrary; whoever chose it knew what they were doing. The outer edge leaves 0.25 margin below
the lane pitch (11% of a lane), so standing one lane away (|dx| = 2.2) cannot auto-award CLOSE —
the guard the code comment claims is real. **This is a pass. Do not re-file it.**

### Schedule classification

| Reward | Schedule | Note |
|---|---|---|
| Gems (safe breadcrumb) | fixed-ratio | 1 coin each, always |
| **Gems (greed line, v1.7)** | **fixed-ratio, player-gated** | 1 coin each, but only if you take the risk — see below |
| CLOSE / SLICK | fixed-ratio | deterministic on geometry |
| Flow surge | **fixed-ratio, every 3rd** | `flowPerSurge` 3 — a metronome, not a schedule |
| Multiplier | fixed, capped | below |
| Level-up | fixed-interval | banded, watermarked |
| Daily payout / free chest | fixed-interval | |
| **Mystery Box** | **variable-ratio** | **the only one — and it lives in the menu, not the run** |

**Prism Rush has no variable-ratio reward inside the run loop.** Every in-run reward is a
deterministic function of geometry and state. That is admirable honesty (decree 5) and it is also
why the run loop has no pull: there is no "one more run, it might be the good one" — the good run
is fully determined by how well you play, and past run 20 you know how well you play. The single
variable-ratio hook is a 300-coin gacha two menu taps away; it reinforces *menu visits*, not play.

**v1.7 amendment (S-004, PR-0414).** This still holds — nothing in the run loop became random, and
deliberately so (invariant 1 and decree 5 both push the other way). But the sentence "the good run
is fully determined by how well you play" now means something better than it did. Before v1.7 the
coin line was routed into `safeEntryLane` before every pattern, so **no gem in the catalogue
required entering an unsafe lane**: greed and survival were the same input, and "how well you
play" collapsed to execution alone. Since v1.7, past `riskGemsFrom` (1,440 m) a second gem line is
hung in a lane the pattern *closes*, ending one planned swerve short of the wall
(`riskExitSeconds` 0.30 s, constant in time so the commitment is identical at 17 m/s and at the
cap). The safe breadcrumb is still there and still takeable — the player chooses. Measured: 0.7%
of gems are priced in risk before the gate, 13–15% after it.

That is a *decision*, not a variable-ratio hook, and it is the honest version of one. The
open question this bible cannot answer is whether a deterministic decision generates the same
"one more run" pull that a variable-ratio schedule does. It probably does not, fully — but decree
5 rules out the alternative, and a real choice beats no choice.

### The multiplier is not a system — it is a loading bar

`streakPerMult` 5, `multCap` 5 → **×5 at 20 consecutive gems** [C].

Measured: the multiplier chip read **×5 in all 20 sampled frames**, from the first sample at 143 m
(32 gems) through 5,331 m (1,948 gems) — every frame of the sampled span [M]. Already capped before the first
screenshot; never moved again.

Twenty gems arrive within ~8 seconds of any run in which the player collects gems at all. A system
whose ceiling is reached in the first 8 seconds of a 200-second run and is then pinned for the
remaining 96% is not a progression system — it is a loading bar that fills once and stays full.
The tutorial devotes a page to a ×1→×5 ladder the player will observe for eight seconds, ever.
→ **PR-0405 (SEV2)**.

---

## 8. Session shape

**Intended:** stated nowhere in the repo.
**Actual [C, M]:** runs are 45 s (1 km) to ~200 s (the sampled span alone was 190 s and the run was still alive). Restart is **one tap** —
`RUN AGAIN` is the primary CTA on the death panel [M], which is the correct number. A session is
therefore a chain of 45–120 s runs with ~2 s of dead time between.

**What ends it:** boredom, specifically the boredom of §3 and §4 — the run stops escalating at
3,300 m and the meta loop's payout does not change how the next run plays. There is no frustration
exit (deaths read as fair) and no mastery exit (there is no mastery to reach).

**`timeSurvived` is computed every frame and rendered nowhere** — confirmed on the death panel,
which shows `72m · World 1` and `0 close calls` and no duration [M] (PR-0131). The consequence is
not cosmetic: **neither the player nor Rayan can see session length**, and combined with the total
absence of analytics (§9) nobody will ever know how long a Prism Rush session is.

### What is a paid continue for?

The revive costs 150 coins and post-revive play does not count for missions or XP (PR-0307).

Measured first-death panel [M]: a brand-new player who has just died at 72 m holding 1 coin sees,
as the **largest, highest-contrast element on the panel**, a solid amber bar reading
**"NEED 149 MORE — 150 🪙"**, directly above `🛒 GET COINS — FIRST PURCHASE +50% BONUS`, and only
*then* the free `RUN AGAIN`.

Argued both ways, as the brief demands:

- **Defence:** every element is honest. Price shown, shortfall shown, no faked urgency, `RUN
  AGAIN` free and present. No single component deceives.
- **Prosecution:** decree 5 forbids dark patterns, and a dark pattern needs no lie — it needs
  *sequencing*. The hierarchy on a first-ever death, before the player has completed one
  satisfying run, is: (1) a purchase you cannot afford, (2) where to buy money, (3) play again.
  The unaffordable button is also a permanently broken-looking state for the whole early game,
  which decree 3 forbids for expected situations — and being broke on your first death is the most
  expected situation in the game.

**Ruling: violates decrees 3 and 5 by placement.** → **PR-0406 (SEV1)**.

On the design question underneath: a continue that buys distance but not progression makes the
number bigger and the player poorer. Recommendation for **PR-0254**: revived runs count for
missions and XP and are **not** leaderboard-eligible — exactly the rule checkpoint runs already
follow (iron rule 10). That is the only internally consistent answer, and it is one line of policy
instead of two half-answers.

---

## 9. Retention hooks, scored honestly

One question per hook: **does it give a reason to return tomorrow specifically?**

| Hook | Verdict | Why |
|---|---|---|
| Daily Rush | **Real** | Live hub countdown (`ENDS 10:27` [M]), UTC-day seed, tiered payout. Strongest hook in the app. |
| Login streak ladder | **Real** | `pendingDailyStreak` resets to 1 on a gap (`ProfileStore.swift:305-313`) — genuinely consecutive. Pays 2,650 coins over 7 days. The only true consecutive-day mechanic in the game. |
| Challenge-day skins (7, 14 days) | **Weaker than it looks** | `SkinUnlocks.swift:13` counts **cumulative distinct UTC days ever**, not consecutive. 14 days spread across any span. A collection gate wearing a habit costume. |
| Daily / weekly missions | **Weak** | Real rotation, but claimable whenever; nothing decays. |
| Free chest | **Weak** | Fixed-interval; pulls you back to the *menu*, not into a run. |
| Streaks | **Decoration** | Tracked and rewarded, and despite being on tutorial page 2 has no countdown, no "streak ends in Nh", no jeopardy surface. A streak with no visible loss condition is a stat. |
| Leaderboards | **Decoration** | `prismrush.daily` advertised 4× with no in-app viewer (PR-0310). A board you cannot look at cannot motivate. |
| Achievements | **Decoration** | One-time, no cadence. |

### The finding that outranks all of them

```
grep -rn "UNUserNotification|requestAuthorization|import UserNotifications" --include=*.swift PrismRush
→ no matches
```

**There is no notification code in this app** [M/C].

The entitlements file declares only `applesignin`, `game-center` and `ubiquity-kvstore-identifier`
— no `aps-environment`. A game with a countdown timer, day-gated skin unlocks, a consecutive-login
ladder and a rotating mission board has built four retention mechanisms that all depend on the
player *spontaneously remembering to open the app*. → **PR-0407 (SEV2)**.

**Scoped honestly, after adversarial review.** The original SEV1 framing did not survive:

- The `challengeDays(7)` / `challengeDays(14)` skins are **cumulative distinct UTC days ever**
  (`Meta/SkinUnlocks.swift:13`), *not* consecutive-day habits. My §9 table said otherwise; that was
  wrong and is corrected there.
- The only genuinely consecutive mechanic is the login ladder (`ProfileStore.swift:305-313`, a gap
  resets to 1), and it pays **2,650 coins over seven days** — 3.2% of the 83,500 collection. Real,
  but not a population-level cliff.
- Charter non-negotiable #1 plus the 4+ age rating means a 30-minute chest ping would be a
  *manipulative* notification and is out of bounds. The defensible version is a single
  once-per-day Daily Rush reminder, opt-in.

### Analytics: do not file this

I nearly filed "zero instrumentation, Rayan will ship blind" as SEV2. **It is out of bounds and I
withdraw it.** `00_CHARTER.md:73` non-negotiable #4 is *"Zero ads, zero analytics, zero tracking"*,
advertised in the store listing and therefore a compliance commitment; `:94-98` lists analytics
SDKs under **Explicitly out of scope** with the words *"Do not file backlog items proposing
them."*

The consequence is real and future sessions should hold it consciously rather than rediscover it:
**every retention claim in this document, including mine, is permanently unfalsifiable on live
data.** That is a deliberate, principled trade the owner has already made. If it is ever to be
revisited it needs an ADR and Rayan's sign-off, not a backlog row.

---

## 10. Missing systems, ranked by retention impact

Ranked by effect on whether this game has a second week — not by how fun they'd be to build.

| # | Missing | Impact | Why here |
|---|---|---|---|
| 1 | **Anything past 3,200 m** | D7 | The run loop has no second act (§3, §4). The only finding here that survived adversarial review at SEV1. |
| 2 | **A meta purchase that changes play** | D7 | The economy buys colours (§1). One permanent unlock altering a verb converts a decoration loop into a progression loop. |
| 3 | **Just-in-time teaching** | D1 | 17 concepts in a pre-run text wall, zero in-context callouts (§2). |
| 4 | **A once-daily Daily Rush reminder** (opt-in) | D1 | Four retention mechanics cannot reach the player (§9). Scoped down from "notifications" — a 30-min chest ping is barred by charter #1 + the 4+ rating. |
| 5 | **Visible streak jeopardy** | D1 | The login ladder *is* consecutive and *is* invisible as a stake. |
| 6 | **In-app daily leaderboard viewer** | D7 | Advertised 4×, unreachable (PR-0310). |
| 7 | **Surface `timeSurvived`** | low | Already computed; rendering costs nothing (PR-0131). |
| 8 | **Post-level-30 endgame** | D30 | Few players, but they are the ones who'd pay. |

**Analytics is deliberately absent from this list** — charter non-negotiable #4 bans it and §9
explains why proposing it is out of bounds.

---

## 11. What this bible does not cover, and what it still owes

- **Owes:** the real reaction budget in ms, which needs the renderer's true draw distance rather
  than `spawnHorizon` 115 m. Named in §3; the next design pass should read `Render/` and fill it.
- Input latency in ms, death legibility within 200 ms, juice and haptics — **AUDIT-004**.
- App Store compliance of the first-purchase bonus and the gacha — **AUDIT-003**.
- Whether the greedy bot is a correct solvability *oracle* — **AUDIT-006**; §4 argues only its
  design consequence.
- **Per-world music.** Pinned to world 0 by explicit owner decree (`Audio/SynthEngine.swift:133`).
  Not filed. It is a constraint I disagree with, it is the owner's call, and open question 3
  already carries it.
- **Prism's hue shift.** `Skin(id: "default", … isPrismatic: true)` (`Meta/SkinCatalog.swift:94`)
  makes the default character cycle colour over time — cyan on the splash, pink in the hub [M].
  This is *not* a decree-1 violation: decree 1 forbids identity changing **with the world**, and
  Prism's identity *is* the prism. Session 002 already refuted this; recorded here so session 004+
  does not re-file it a third time.

---

## 12. The three things that should change first

1. **Give the run loop a second act past 3,200 m** (PR-0400). Everything else is polish on a game
   that ends after two minutes. This is the only design finding that survived hostile review at
   SEV1 on its own merits, and it was independently reached by four of ten lenses.
2. **Fix the first-death panel's hierarchy** (PR-0406). The worst-sequenced moment in the app, and
   it happens to 100% of players at the exact moment they decide whether this game is for them.
3. **Make one purchasable thing change how the game plays** (PR-0410). 83,500 coins of sink
   currently buy zero mechanical change; this is what makes the meta a decoration loop (§1).

A once-daily opt-in Daily Rush reminder (PR-0407) is the cheapest item on the list and would be
first on effort-per-point — it is fourth here because adversarial review correctly cut its claimed
impact from SEV1 to SEV2.

---

## Constraints this bible may not violate

The six **owner decrees** in `CLAUDE.md` are product law and outrank any proposal here:
1. A character never changes identity with the world.
2. Previews never lie.
3. No broken-looking states for expected situations.
4. Everything on screen leads somewhere.
5. Zero ads, no dark patterns; advertised bonuses always delivered.
6. Clarity beats spectacle.

Plus the charter non-negotiable: no manipulative retention mechanics aimed at minors, and any
randomized purchase discloses odds.
