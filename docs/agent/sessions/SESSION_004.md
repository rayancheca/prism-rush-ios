# Session 004 — the second act, and gems that cost something

**Date:** 2026-07-28 · **Branch:** `claude/prism-rush-spawn-path-c7d88a` · **Recovery tag:** `pre-s004`
**Goal:** PR-0400 + PR-0414 in a single `DailyChallenge.layoutVersion` bump.
**Outcome:** both landed, plus PR-0445, plus the PR-0411 residue Rayan raised mid-session.
This is the first session to change the simulation rather than the copy.

---

## What shipped

| Item | Sev | What |
|---|---|---|
| PR-0411 (residue) | SEV1 | The two repo files that are the copy-paste source for App Store Connect still sold "Earn 2x coins, forever" |
| **PR-0400** | **SEV1** | The difficulty curve ended at 3,200 m. It now runs to 9,600 m |
| **PR-0414** | **SEV2** | No gem required entering an unsafe lane. Some now do |
| PR-0445 | SEV2 | The attract track cut through the hub's glyphs |
| PR-0451 | SEV3 | `Tuning`'s pool-cap comment claimed a renderer coupling that does not exist |

Filed: **PR-0450** (the catalogue is still 14 patterns — PR-0400's acknowledged residual),
**PR-0452** (Rayan's hub redesign request).

Commits: `d1445a4` · `fdafae6` · `09c3f47` · `9766e7d`.

---

## PR-0400 — how act two is built, and why not the obvious way

**The obvious way was wrong.** The handoff already flagged it and the audit had the receipt
(`verify-difficulty.md §12`): the readable lead is hard-capped at ~65 m by the opaque backdrop
plane at z = −65, which is 1.97 s at the speed cap, and pushing it back was *tried and reverted*
in v1.6 because it left the world's set-pieces floating mid-track. **Raising `speedCap` makes the
game unreactable, not harder.** So act two had to be a second axis over the same speed.

Four mechanisms, all pure functions of distance, all consuming **zero RNG**, all keyed off
`Spawner.intensity` (0 at 3,200 m → 1 at 9,600 m, which is world 12 where the palette cycle starts
evolving — the whole game tops out together):

1. **The pattern draw becomes a weighted table**, in three waves. `rng.int` now picks a *slot* that
   resolves through a table instead of picking an index directly — same single call, so
   `PatternOrderTests`' pinned per-pattern consumption is untouched, and in act one there is no
   table at all so the draw is byte-identical to v1.6.
   The catalogue is never reduced: pattern 0 and the obstacle-free overdrive runway stay reachable
   at any depth, they just lose share. Pinned by `testEveryWaveKeepsTheFullCatalogueReachable` —
   a shipped feature must not silently stop existing in long runs.
2. **The gap continues 5 → 4** (act one was 11 → 5, then flat forever). Deliberately shallow: the
   catalogue's tightest cross-pattern adjacency is pattern 8's trailing clearance + gap + pattern
   5's leading obstacle, which at gap 4 is still 18 u ≈ 0.55 s at the cap — looser than adjacencies
   act one already ships *inside* a single pattern. Density comes from the mix, not from crowding
   the seams.
3. **Moving walls stop parking at phase 0.** This was the best find in the audit and it is
   embarrassing in the right way: pattern 13 is the game's *exclusive tier-5 unlock*, is labelled
   "high difficulty" in `Models.swift`, and was the **easiest late pattern in the catalogue** —
   phase 0 puts both walls dead centre on their collision plane, so both outer lanes are safe
   forever and the spawner even pre-parks you in one. The phase now swings apart with intensity.
   Past ~6,800 m exactly one lane is open and it has to be read.
4. **Risk-priced gems** — PR-0414, below.

**The waves are front-loaded** (intensity 1/6 and 1/2 → 3,200 / 4,267 / 6,400 m) and this was a
correction, not the first design. My first cut used even thirds, which put the first real step at
5,333 m. A good run is about two minutes ≈ 3,300 m: an escalation whose first step lands at 5,333 m
is one almost nobody meets. The instrument showed wave 1 at +2.3% over the plateau and that was the
tell.

---

## PR-0414 — what "priced in risk" actually means here

D-006 separated **structure** (what Rayan wanted) from **safety** (what got built). The safe
breadcrumb into `safeEntryLane` stays exactly as it was. Past `riskGemsFrom` (1,440 m) the spawner
*also* hangs a second, longer line in a lane the pattern **closes**, ending `riskExitSeconds`
(0.30 s) of travel short of the wall.

Constant in **time**, not metres, so the commitment is identical at 17 m/s and at the cap. Clearing
a lane takes ~0.06 s of lane lerp, so 0.30 s is a planned swerve with real margin — never a
reaction, never a knife-edge.

The line is laid down **backwards from the exit point**, so it always points at the wall it stops
short of. That shape — a run of coins aimed at something lethal, stopping just before it — is the
whole design in one glance.

**Why the solvability bot cannot certify this, and does not claim to.** `Autopilot` reads only
`activeObstacles`; grep it for `activeGems` and you get nothing. It has never collected a gem. It
walks the safe line every time and would stay green **even if the greed line were lethal**. So
`testEveryGreedGemLeavesATakeableExit` exists as a separate proof: it walks every gem the spawner
can emit across 16 seeds × 12,000 m and asserts the lane stays open for at least the exit window.

That test immediately earned its place — see below.

---

## Two defects the new tests caught, both of which would have shipped

**1. The greed line could place a gem inside the previous pattern's tall.** The line reaches back
past the gap into the previous pattern's tail, and I justified how far with "the catalogue's
smallest trailing clearance is 9 u (pattern 8)". That was **wrong**: it counted *bars*, which are
full-width and close no lane. The binding constraint is the last **lane-blocking** obstacle, and
pattern 5's third tall sits 7 u from its end. The test found gems with 0.04 m of runway. The
spawner now carries the previous pattern's spawns and floors the line above them — a fix that stays
correct if someone later adds a pattern with a shorter tail, which a magic number would not.

**2. `safeEntryLane` routed the SAFE breadcrumb into a moving wall.** Its zone was 8.5 u; pattern
13 puts its first wall at 9 u. Just outside. So the "safe" coin trail led into the centre lane that
wall crosses, and the player had 9 u — 0.27 s at the cap — to discover it. This predates v1.7 and
got worse with swung phases. Zone widened to 12 u; nothing else in the catalogue has a lane-blocking
obstacle in that window, so it fixes exactly that case and nothing else.

**3. (pre-existing) Gems were being silently dropped.** `GameCore.apply` has
`guard activeGems.count < Tuning.capGem else { return }`. Measured peak concurrent demand inside
the spawn horizon is **94** against a cap of **72**. Verified pre-existing by running the new test
against the stashed v1.6 tree — it pegged 72 as well. Raised to 112. `Tuning`'s comment claimed
"renderer pools mirror these", which is false — repo-wide grep shows `capGem` appears only in
`Tuning`, `GameCore` and the new test; the RealityKit renderer pools on demand. That stale comment
is why this sat unfixed: it made a Core-only constant look like a cross-layer change (**PR-0451**).

---

## The instrument, and why the handoff's instrument could not do this job

Session 003 measured the flat tail by screenshotting the HUD every 10 s. The handoff asked me to
re-run that capture "and show a tail that is not flat."

**I did run it, and I am not going to claim that.** The HUD shows distance and score. Distance rate
*is* speed, which I deliberately did not raise; score rate is dominated by gem collection, and the
Autopilot ignores the new gems by construction. **The HUD capture is structurally incapable of
showing this fix.** Reporting a "non-flat tail" from it would have meant finding a number that
moved and calling it the result.

So the fix is measured by `Tests/CoreTests/DifficultyCurveTests.swift`, which measures what the
difficulty actually *is*: what the spawner puts down, and how much work the track extracts.

Three things went wrong building it, all worth knowing:

- **Normalisation.** First run summed 24 seeds and divided once → obstacle densities ~25× too high.
- **The 20 m "rest beat" threshold was meaningless** — mean obstacle spacing is ~25 m, so almost
  everything counted as rest. Raised to 40 m (1.2 s at the cap).
- **Band aliasing, the subtle one.** The catalogue's mean cycle is ~451 m. A fixed 500 m band grid
  beats against it with a ~4.6 km period and produces a slow oscillation that looks *exactly* like
  a difficulty trend. It is not one — it is band edges chopping patterns in half. Bands are now
  snapped to real pattern boundaries (read off `spawner.cursor` after each `fill`), and the table's
  bands are aligned to the wave boundaries, because within a wave the pool is constant and any
  variation is noise by definition.

**The instrument validates against two independent sources**, which is why I trust it: its act-one
obstacle density is **6.02 per 100 m** against a closed-form sum over the catalogue giving **5.99**,
and its input rate at the cap reproduces the audit's independently-derived **1.17 decisions/s**.

### Result (64 seeds)

```
  band(m)      obst/100m  inputs/100m  gems/100m  priced%  rest%  phase
      0- 1200       5.28         3.01       41.2     0.7%  35.9%  act 1
   1200- 2400       5.61         3.68       42.2    10.5%  28.4%  act 1
   2400- 3200       6.02         3.93       42.2    13.3%  27.1%  act 1  ← the old plateau
   3200- 4267       6.40         4.42       39.5    11.4%  19.4%  act 2 w1
   4267- 6400       7.49         4.80       38.6    13.8%  12.6%  act 2 w2
   6400- 9600       7.63         4.44       40.4    14.6%  12.4%  act 2 w3
```

v1.6, measured the same way before the change: **5.7 obst/100 m, 3.4 inputs/100 m, ~32% rest, ~2%
priced — flat across the whole 3,000–8,000 m range with no trend in any column.**

Note `gems/100m` barely moves (42 → 40). That is deliberate and good: the *composition* shifts onto
the risk axis without inflating the economy.

---

## Invariant 2, discharged

- `swift test -c release` → **187 tests, 0 failures**, including `SolvabilityBotTests` at
  200 seeds × 6,000 m and the 64 × 12,000 m soak. Bot green on the first run after the spawn change.
- `DailyChallenge.layoutVersion` **7 → 8**; `DailyChallengeTests` goldens repinned, and
  `MissionsTests.testTodaysChallengeSeedMatchesUTCGoldens` too — it pins the same seeds from the
  meta layer and would otherwise have drifted silently.
- **Goldens were derived independently in Python from the SplitMix64 formula, not read off the
  code they pin.** The derivation reproduces the known v5, v6 and v7 values *and* the v8 value that
  was pre-armed when v7 shipped — four checks against known-good before trusting the two new ones.
  A v9 pin is pre-armed for the next spawn change.
- `./Tools/build.sh` → **BUILD OK** (SPM compiles none of `UI/`, `Render/`, `IAP/`).

## On device

Clean install, autoplay. **One unbroken run from 1,310 m to 10,327 m** — across all three act-two
waves and past the full-intensity point at 9,600 m, no crash, no death. That is an independent
on-device confirmation of fairness at a depth the SPM soak only reaches at 12,000 m.

Speed per 10 s interval read off the HUD strip: 33.5–34.0 m/s in the fast intervals with dips to
27–30 (chrono slow-mo — it lowers *apparent* m/s by design, `chronoFactor` 0.65). Score rate
23.0 pts/m at 3.2 km, 18.3 pts/m at 10.0 km. Both exactly as expected for a change that does not
touch speed and that the Autopilot cannot exploit. Strip kept at `docs/agent/scratch/s004/`.

---

## A finding I nearly filed and killed myself

The hub character's colour cycles — I sampled it at 18 s intervals and got magenta → pink → orange.
Decree 1 says a character never changes identity with the world, and Rayan has called that out
twice, so this looked like a live decree violation on the screen he had just asked me to redesign.

It is not. The default skin **is** `Prism`, `isPrismatic` is true, and `CharacterSwatch.swift:88`
runs the *same* `SkinCatalog.prismaticColor` clock the in-run RealityKit rig uses, specifically so
preview and gameplay shimmer in lockstep. That is decree 2 being *satisfied*. An authored shimmer
on its own clock is not `followsWorld` behaviour. Not filed.

---

## What I did not do, and why

- **PR-0254 / PR-0307** (revived runs count for missions and XP, not leaderboard-eligible) — decided
  in D-007, still open. It touches `recordRunResults` and invariant 5 (per-death delta payouts), and
  I would not start an economy change on the context I had left. It is small and fully specified.
- **PR-0452** (the hub redesign Rayan asked for mid-session) — filed with a concrete critique from
  the clean-launch screenshot, not started. A redesign is design work, not a patch.
- **PR-0450** (a 15th pattern) — named as PR-0400's honest residual rather than quietly absorbed.
  Act two changes how often you meet things, not what things exist.
