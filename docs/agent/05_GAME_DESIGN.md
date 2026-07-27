# Game design bible

> **Status: SKELETON — owned by AUDIT-002 (The Game Designer, session 003).**
> Session 001 created the headings and filled in only what it could read directly out of
> `PrismRush/Core/Tuning.swift`. Everything marked `TO BE WRITTEN` is AUDIT-002's job and
> must be derived from the real constants, not from vibes. Do not fill these in casually
> from another session — a half-written design bible is worse than an empty one, because
> later sessions will trust it.

Update policy: rewrite a section when the design actually changes. Note the session number
next to any number you change so a later session can find the commit.

---

## 1. What the player is doing, second to second

TO BE WRITTEN (AUDIT-002). Must name three loops explicitly:
- **Moment-to-moment loop** (the ~1 s cycle: read obstacle → choose verb → execute → resolve)
- **Run loop** (the ~1–5 min cycle: launch → ramp → death → payout → relaunch)
- **Meta loop** (the multi-day cycle: earn → unlock → return)

For each: where it breaks.

## 2. The verbs

The input verbs the simulation actually accepts (from `GameCore` input intents):
`changeLane(±1)`, `jump()`, `slide()`, plus three consumable deploys
(`activateSlowMo()`, `activateHeadStart()`, `deployShield()`, `deployOverdrive()`).

TO BE WRITTEN: which verbs a player discovers unprompted, which are taught, and which are
effectively invisible.

## 3. The first 60 seconds

TO BE WRITTEN (AUDIT-002). Tick-by-tick. Cover: cold launch → first input accepted → first
obstacle → first gem → first near-miss → first death. State whether the first death reads as
the player's fault. A first death that reads as unfair is the single largest cause of a
one-session install.

## 4. The difficulty curve

Ground truth from `Core/Tuning.swift` (session 001 transcription — verify before using):

| Constant | Value | Meaning |
|---|---|---|
| `speedStart` | 17 | m/s at run start |
| `speedRamp` | 0.0052 | speed gained per metre |
| `speedCap` | 33 | m/s ceiling from the ramp |
| `boostSpeedMax` | 36 | m/s hard ceiling including overdrive |
| `menuSpeed` | 7 | attract-mode scroll speed |
| `diffFullAt` | 3200 | metres at which difficulty reads 1.0 |
| `gapMin` / `gapMax` | 5 / 11 | metres between spawned patterns at max / min difficulty |
| `spawnHorizon` | 115 | metres ahead of the player that content is spawned |
| `worldLength` | 800 | metres per world |
| `earlyDistance` | 260 | metres before the pattern ladder opens past tier 1 |
| `midEarlyDiff` | 0.18 | difficulty (≈576 m) unlocking rings + overdrive |
| `midDiff` | 0.45 | difficulty unlocking the mid tier |
| `movingWallMinDiff` | 0.6 | difficulty before moving walls can spawn |
| `tickDt` | 1/120 s | fixed simulation step |

Derived, to be computed by AUDIT-002 and shown with working:
- speed at 500 m / 1000 m / 3200 m / cap, and the metre at which the cap is reached
- **reaction budget in milliseconds** at each of those speeds, from `spawnHorizon` and the
  actual first-visible distance (NOT the spawn distance — the renderer's draw distance is the
  real number and must be read out of `Render/`)
- where the curve leaves the flow channel (too easy / too hard)

## 5. Reward schedules

Ground truth from `Core/Tuning.swift`:

| Constant | Value |
|---|---|
| `gemBaseScore` | 10 |
| `nearMissBonus` | 40 |
| `nearMissInner` / `nearMissOuter` | 1.25 / 1.95 (lane pitch is 2.2) |
| `streakPerMult` / `multCap` | 5 gems per multiplier step, ×5 max |
| `ringScore` / `ringCoins` / `ringPerfectCoins` | 150 / 5 / 12 |
| `boostScoreBonus` | 60 |
| `flowPerSurge` / `flowSurgeScore` / `fountainGems` | 3 / 80 / 10 |
| score formula | `floor(traveledDistance × 2) + bonus` |

TO BE WRITTEN: is the near-miss window tuned or arbitrary? Where is the variable-ratio
reward? Is death legible enough to drive the "one more run" impulse?

## 6. Economy math

TO BE WRITTEN (AUDIT-002). Compute, do not estimate:
- coins per average run and per good run (needs the real payout code in `Meta/`, not just
  `Tuning`)
- faucets, sinks, dead ends
- time-to-first-unlock and time-to-full-collection at the real skin prices
- verdict: generous / punishing / accidental

## 7. Session shape

TO BE WRITTEN.

## 8. Retention hooks

TO BE WRITTEN. For each of daily challenge, missions, streaks, leaderboards: does it give a
reason to return *tomorrow specifically*, or is it decoration?

## 9. The mastery ceiling

TO BE WRITTEN. What does a player learn on run 5, run 50, run 500? If the answer is "nothing
after run 20", that is a SEV1 and it is the reason the game dies.

## 10. Missing systems

TO BE WRITTEN. Ranked by expected retention impact, not by how fun they would be to build.

---

## Constraints this bible may not violate

The six **owner decrees** in the repo `CLAUDE.md` are product law and outrank any design
proposal made here. In particular:
1. A character never changes identity with the world.
2. Previews never lie.
3. No broken-looking states for expected situations.
4. Everything on screen leads somewhere.
5. Zero ads, no dark patterns; advertised bonuses are always delivered.
6. Clarity beats spectacle.

Plus the charter non-negotiable: no manipulative retention mechanics aimed at minors, and any
randomized purchase discloses odds.
