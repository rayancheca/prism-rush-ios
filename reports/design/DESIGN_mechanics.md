# Prism Rush v1.3 — Gameplay Mechanics Design

Role: GAMEPLAY MECHANICS designer. Scope: gem-arc geometry fix (P0), three new in-run
mechanics, pacing curve, test plan. All design verified against source at:
`PrismRush/Core/{Tuning,Patterns,Spawner,Autopilot,Collisions,GameCore,Models,DailyChallenge}.swift`.

Iron-rule compliance is stated inline per feature and summarized in §5.

---

## 0. Physics ground truth (verified, used throughout)

| Quantity | Formula | Value |
|---|---|---|
| Jump initial velocity | `jumpV0` | 10.6 |
| Gravity | `gravity` | 26 |
| Time to apex | `t_apex = v0/g` | 0.40769 s |
| Max jump height | `h_max = v0²/2g` | 2.16077 |
| Total airtime | `t_air = 2v0/g` | 0.81538 s |
| Airtime span (spatial) | `S(v) = v·t_air` | 13.86 @ v=17 · 17.94 @ 22 · 24.46 @ 30 · 26.91 @ 33 |
| Grounded player center | `groundedCenterY·1.0` | 0.66 |
| In-air player center offset | `0.66·airHoldY(1.12)` | ≈ 0.739 (jump-start transient 1.18 → 0.779) |
| In-air jumpY by airtime fraction τ | `jumpY(τ) = 4·h_max·τ(1−τ)` | apex 2.161 at τ=0.5 |
| Gem vertical pickup window | `gemPickup.dy` | ±1.15 around player center |
| Predicted ramp speed at distance d | `v(d) = min(33, 17 + 0.0052·d)` | deterministic, pure |

Key derived facts:
- Grounded gem band: pcy=0.66 → gems y ∈ (−0.49, 1.81).
- At apex: pcy ≈ 2.16+0.74 = 2.90 → gems y ∈ (1.75, 4.05).
- Chrono changes the **spatial** jump arc (player physics run real-time while the world
  scrolls at 0.65×), shrinking the arc's spatial span by 0.65×. Speed-aware placement
  must budget tolerance for this (see §1.4).

---

## 1. P0 — GEM-ARC FIX

### 1.1 Why the current arc is geometrically wrong

Current formula (`Patterns.swift:31-37`): 7 gems, fixed spacing 1.25 (span 7.5), heights
`y = 0.8 + sin(t·π)·1.5` → dome 0.8 → 2.30 → 0.8.

The dome's **spatial wavelength is 7.5 units**; the jump's spatial wavelength is
**13.9–26.9 units** (speed 17–33). Near apex the player's height changes by at most
`½g(3.75/v)² ≈ 0.20` over the dome's half-span at v=30, while the dome's own height
varies by 1.5. Mismatch 1.3 > dy window 1.15 ⇒ **no single jump can collect all 7
gems at any play speed**: you get either the edge gems (low) or the middle gems (high),
never both. That is the "jump-then-airslam salvage" the owner feels. The dome shape is
also speed-blind — but the spawner *knows* the distance `d` of every gem it places, and
ramp speed is a pure function of distance. We exploit that.

### 1.2 New gemArc — gems placed exactly ON the ballistic center path

Design rule: **the player jumps when gem 0 is underfoot** (gem 0 *is* the telegraph; same
trigger rule at every speed). Every subsequent gem sits at the height the player's center
will actually have when crossing it, computed from the predicted crossing speed.

```swift
// Patterns.swift — replaces gemArc. Returns the arc's span so callers size lengths.
private static func gemArc(_ d: Double, _ lane: Int, _ out: inout [SpawnCmd]) -> Double {
    let v    = min(Tuning.speedCap, Tuning.speedStart + d * Tuning.speedRamp) // crossing speed
    let tAir = 2 * Tuning.jumpV0 / Tuning.gravity                             // 0.81538 s
    let span = min(Tuning.gemArcAirFrac * v * tAir, Tuning.gemArcMaxSpan)     // 10.40 … 14
    let hMax = Tuning.jumpV0 * Tuning.jumpV0 / (2 * Tuning.gravity)           // 2.16077
    for i in 0..<7 {
        let frac = Double(i) / 6                       // 0…1 across the span
        let tau  = frac * span / (v * tAir)            // airtime fraction at gem i
        let y    = Tuning.gemArcBaseY + 4 * hMax * tau * (1 - tau)
        out.append(.gem(d: d + frac * span, lane: lane, y: y))
    }
    return span
}
```

New `Tuning` constants:

```swift
static let gemArcBaseY: Double = 0.8      // gem 0 height (grounded-collectible, |0.8−0.66|=0.14 ✓)
static let gemArcAirFrac: Double = 0.75   // arc covers first 75% of the airtime (up, over, ¾ down)
static let gemArcMaxSpan: Double = 14     // span cap so pattern lengths stay bounded at high speed
```

**The math.** A jump triggered at gem 0 has center height `pcy(Δ) = jumpY(Δ/(v·t_air)) + 0.74`
at spatial offset Δ. Gem i is placed at offset `Δᵢ = (i/6)·span` with height
`yᵢ = 0.8 + 4·h_max·τᵢ(1−τᵢ)` where `τᵢ = Δᵢ/(v·t_air)`. The placement error against the
true center path is the constant `0.8 − 0.74 = +0.06` for every airborne gem, and 0.14 for
the grounded gem 0 — both ≪ dy window 1.15. **All seven gems lie on the path by
construction**; the remaining ~1.0 of dy slack is the human timing budget.

**Concrete numbers** (`yᵢ` and spacing):

| v (d) | span | spacing | y₀…y₆ |
|---|---|---|---|
| 17 (start) | 10.40 | 1.733 | 0.80, 1.75, 2.42, 2.83, **2.96**, 2.83, 2.42 |
| 22 (d≈960) | 13.45 | 2.242 | identical heights (τᵢ = 0.125·i is speed-invariant below the cap) |
| 30 (d≈2500) | 14 (cap) | 2.333 | 0.80, 1.51, 2.13, 2.55, 2.81, 2.92, **2.92** (ascent-to-apex comet) |
| 33 (cap) | 14 (cap) | 2.333 | 0.80, 1.47, 2.06, 2.49, 2.77, 2.92, **2.96** |

Below the cap (v ≤ 22.9, d ≤ 1134 m) the arc is a full dome traced up-over-and-¾-down;
above the cap it becomes a rising trail ending exactly at apex — both visually honest.

**Human timing window.** If the player jumps δ units late/early, the per-gem error is
bounded by `|f′|·δ` with max slope `v0/v` at takeoff: slack ≈ 1.0 → δ ≈ ±1.6 units at v=17
and ±2.8 at v=30 ⇒ ≈ **±90–95 ms** at all speeds, plus the gem dz window (±1.0) on top.
Consistent, fair, learnable — and the trigger is literally standing on gem 0.

**Low-clearance check (patterns 1/2/6/9 place a low ~3.8–4 units after arc start).**
Jumping at gem 0: at the low's near kill edge (Δ=2.85, |z|<0.95), `jumpY` = 0.82 @ v=33
(player bottom = jumpY+0.105 = 0.92 > lowKillTop 0.85 ✓) and 1.40 @ v=17 ✓. The arc jump
and the survival jump are the same jump — geometry now agrees with the obstacle.

### 1.3 gemLine — unchanged

`y = 0.8`, spacing 1.7. Grounded band tops at 1.81 ⇒ lines are collectible by running;
no change, no justification to spend layout churn on it.

### 1.4 Chrono interaction (accepted, tested edge)

Chrono spawns only via pattern "splitBar" (diff ≥ 0.45 → d ≥ 1440, v ≥ 24.5). An arc
placed for v but crossed at 0.65v has a spatially-shrunken jump (lands at Δ = 0.65·v·t_air
= 12.98 < span 14). Worked errors per gem: gems 0–4 collect (max error 0.46 < 1.15);
gems 5–6 can drop. **Guarantee: ≥ 5/7 on a single jump under chrono** — acceptable
(slow-mo already makes survival strictly easier; magnet reels in full arcs). Pinned by a
unit test (§4). Speed-lerp transient (rate 1.5/s toward target) contributes ≤ ~0.1 error
at the spawn horizon — inside budget.

### 1.5 Caller adjustments (pattern lengths become deterministic functions of `b`)

`gemArc` now returns its span; lengths grow with it. No RNG involved (lengths derive from
`b` only):

| Pattern | Change | New length |
|---|---|---|
| 1 (low+arc) | arc at b+2.2, low at b+6 unchanged | `max(16, span + 6)` |
| 2 (triple low+arc) | unchanged geometry | `max(18, span + 8)` |
| 6 (mixed row+arc) | arc at b+2, row at b+6 unchanged | `max(18, span + 8)` |
| 9 (gauntlet) | arc at b+20 over lows b+24; tail gemLine moves b+27 → `b + 20 + span + 2` | `24 + span + 12` |

Note: today, arc-jumping at v=33 already overlands pattern 1 (lands at b+29 vs length 16);
the new lengths *improve* post-arc landing room. Longer patterns ⇒ slightly fewer
patterns per 115-unit horizon ⇒ marginally lower early obstacle density (also wanted, §3).

### 1.6 RNG & determinism impact

- **Zero new RNG calls.** `v(d)` is a pure function of distance. Per-pattern RNG call
  counts are byte-identical to v1.2.
- Gem `d`/`y` values and pattern lengths change ⇒ same RNG stream produces different
  tracks ⇒ **`DailyChallenge.layoutVersion` 1 → 2** (one bump covers everything in v1.3).
- `capGem = 72` unaffected (still 7 gems/arc).
- Solvability: gems never kill; the bot ignores them. Bot must still re-soak because
  pattern lengths shift the obstacle cursor (expected green; patterns individually
  unchanged in obstacle geometry).

---

## 2. THREE NEW MECHANICS

Selection rationale: one **aim-skill verb** (Prism Rings), one **speed/juice beat**
(Overdrive Pads), one **aggression loop with no new entities** (Flow Surge). All three are
*structurally incapable* of breaking the solvability bot: rings and pads live in
`activePickups` (the Autopilot scans `activeObstacles` only — its code is untouched), and
the pad's speed effect is contained inside an obstacle-free runway owned by its own
pattern. All three add coin income (owner ask).

### 2.1 Mechanic A — PRISM RINGS (score-gate rings you jump through)

**Fantasy.** A floating neon torus hangs at apex height. Thread it mid-jump for a payout;
nail the bullseye for a "PERFECT" double payout. Converts the jump from a binary dodge
into an aim verb.

**Core sim model.**
- `EntityKind.ring`, `SpawnCmd.ring(d: Double, lane: Int, y: Double)`.
- Lives in `activePickups` (recycle z > `recycleCollectibleZ`); never lethal.
- New `Tuning`: `ringY = 2.90` (= h_max + 0.74, the apex center height),
  `ringPassDX = 0.9`, `ringPassDY = 0.9`, `ringPerfectDY = 0.12`, `ringZHalf = 0.9`,
  `ringScore = 150`, `ringCoins = 5`, `ringPerfectCoins = 12`, `capRing = 4`.
- New predicate in `Collisions`:

```swift
static func ringPass(playerCenterY pcy: Double, playerX: Double,
                     ringX: Double, ringY: Double, z: Double) -> (pass: Bool, perfect: Bool) {
    guard abs(z) < Tuning.ringZHalf,
          abs(playerX - ringX) < Tuning.ringPassDX,
          abs(pcy - ringY) < Tuning.ringPassDY else { return (false, false) }
    return (true, abs(pcy - ringY) < Tuning.ringPerfectDY)
}
```

- On pass: `bonus += ringScore × mult`; `gemCount += ringCoins` (perfect: `ringPerfectCoins`).
  Coins flow through the existing `gemCount` currency channel — precedent: doubler already
  pays gemCount +2 — so **economy rule 9 is untouched** (one `applyRunSummary`, per-death
  deltas). Streak/mult are skill stats and stay gem-only.

**Window math** (v=20 reference): pass requires `jumpY ∈ [1.26, 2.16]` → jump trigger
tolerance ±0.185 s ≈ **±3.7 units**; perfect requires `jumpY > 2.04` → ±0.08 s ≈
**±1.6 units**. Generous pass, demanding perfect — exactly the skill gradient wanted.

**Spawn pattern** (catalogue index 9 in the v1.3 ordering, §2.4): "ringArc".

```
lane = rng.int(0, 2)                                   // 1 RNG call
gems: 3-gem line at b+0 … b+3.4 (y 0.8, the run-up telegraph)
low at b+7, lane                                       // keeps the jump honest
ring at d = b+3.4 + v(d)·t_apex, lane, y = 2.90        // apex of a jump at the last gem
length = max(18, 9.4 + v·t_apex)                       // 16.4 @ v17 … 20.4 @ v33, so 18…20.4
```

Gating: unlocks with the mid-2 tier (diff ≥ 0.18, ≈ 580 m — §3).

**Autopilot:** zero change. Rings are non-lethal and not in `activeObstacles`; the bot
jumps the low via its existing low logic and may or may not thread the ring — irrelevant
to survival. Bot stays green by construction.

**Snapshot/FX:** no snapshot field needed (score/gems carry it).
`FXEvent.ringPassed(x: Double, y: Double, perfect: Bool)`.

**Renderer/audio:** torus via `MeshDescriptor` (the magnet torus generator is reusable —
100% procedural, rule 6 ✓), emissive world-accent hue, scale-pulse shockwave on pass;
DSP audio: harmonic chime, perfect = double chime an octave up; haptic light tap
(perfect: medium).

**Variety per 60s:** adds a third verb (aim) to dodge/collect; appears ~every 25–40 s
mid-game; perfect-streak chasing gives the skilled player a private goal during otherwise
familiar dodging.

**Chrono edge:** under slow-mo the spatial apex shifts; a placed ring may require a later
jump (apex height is unchanged at 2.16, so it stays threadable by timing — skill, not
unfairness). Non-lethal ⇒ no solvability concern. Documented, not mitigated.

### 2.2 Mechanic B — OVERDRIVE PADS (boost runway)

**Fantasy.** Floor chevrons flash ahead in one lane. Run over them: the world howls, FOV
kicks, and you blast down a gem river at +30% speed with doubled gem pay. A pure
adrenaline beat with the danger budget set to zero by construction.

**Core sim model.**
- `EntityKind.boostPad`, `SpawnCmd.boostPad(d: Double, lane: Int)`. Lives in
  `activePickups`; baseY = 0.05 (floor strip).
- Trigger predicate (grounded contact, generous): `|z| < 1.1 && |px − padX| < 1.1 && grounded`
  (slide counts — it is grounded).
- New state: `boostT: Double` (decays like `chronoT`, edge-emits `.boostEnded`).
- `effectiveSpeed` becomes the single composition point:

```swift
var effectiveSpeed: Double {
    var v = speed
    if chronoT > 0 { v *= Tuning.chronoFactor }
    if boostT  > 0 { v = min(v * Tuning.boostFactor, Tuning.boostSpeedMax) }
    return v
}
```

- On trigger: `boostT = boostDuration`; `bonus += boostScoreBonus × mult`; while
  `boostT > 0`, each gem pays `+boostGemBonus` extra coin (`gemCount += 1` extra).
- New `Tuning`: `boostDuration = 1.0`, `boostFactor = 1.3`, `boostSpeedMax = 36`,
  `boostScoreBonus = 60`, `boostGemBonus = 1`, `capBoostPad = 2`.

**Containment proof (why the bot cannot break).** The pad spawns ONLY inside its own
pattern, "overdriveRunway" (index 10 in v1.3 ordering), which contains **no obstacles**:

```
r = rng.int(0, 2)                                      // 1 RNG call
boostPad at b+4, lane r
gem river: gemLine(b+8,  r, 10)            // 10 gems spacing 1.7 → b+8…b+23.3
           gemLine(b+12, r==2 ? 1 : r+1, 8) // offset second stream, weave temptation
           gemLine(b+28, 1, 6)              // center finisher b+28…b+36.5
length = 48
```

Worst-case boost travel: trigger by `b+5.1` (z window), `boostDuration · boostSpeedMax`
= 36 units ⇒ boost is over by **b+41.1 < b+48**, and the next pattern's earliest obstacle
sits at ≥ `b+48 + gapMin(5) + ~5 lead-in` = b+58. **The boost can never coexist with an
obstacle.** Therefore:
- **Autopilot: unchanged.** Its leads already scale with `c.effectiveSpeed`
  (`Autopilot.swift:89-92`), and during the only window where effectiveSpeed exceeds 33
  there is nothing to dodge. No clamp changes, no decide() changes — green by
  construction, re-soaked anyway (§4).
- No load-bearing constant (`speedStart/Ramp/Cap`, gaps, leads) is touched; the raw
  `speed` ramp never sees the boost (same pattern as chrono).

**Snapshot/FX:** `GameSnapshot.boostRemaining: Double`.
`FXEvent.boostStarted(x: Double)` and `.boostEnded` (edge, audio keys off it).

**Renderer/audio:** pad = flat emissive chevron strip via `MeshDescriptor` with pulsing
scale (procedural ✓); during boost: +6° FOV punch, trail elongation, speed-line
particles, DSP rising whoosh + low-pass sweep open; `.boostEnded` = soft down-chirp.
Haptics: medium impact on trigger.

**Gating:** unlocks with rings at diff ≥ 0.18 (≈ 580 m) — it is a reward beat, players
should meet it before the hard tiers.

**Variety per 60s:** a 2.5-second sensory spike roughly every 45–60 s that contrasts the
gauntlets; the two offset gem streams create a micro-choice (weave for greed vs hold the
lane) with zero death risk — a deliberate breather-with-juice beat the run currently lacks.

### 2.3 Mechanic C — FLOW SURGE (near-miss streaks → gem fountains)

**Fantasy.** Shave walls on purpose. Every third CLOSE/SLICK near-miss without getting
hit detonates a "flow surge": a burst score bonus and a fountain of bonus gems sprays
into your lane ahead. Defense becomes offense; the wall-hug becomes a farming strategy.

**Core sim model.** No new entity kinds, no new patterns, **zero RNG**.
- New state: `flowStreak: Int` (and `bestFlow` for missions/meta).
- Increment at the existing near-miss scoring sites (`GameCore.stepObstacles`, the
  `.close` and `.slick` branches). Reset to 0 in `die()` and on `shieldAbsorbed`.
- When `flowStreak % flowPerSurge == 0` (i.e. every 3rd): `bonus += flowSurgeScore × mult`,
  emit `.flowSurge`, and spawn the fountain through the normal `apply()` path:

```swift
for i in 0..<Tuning.fountainGems {                       // 10 gems
    apply(.gem(d: distance + Tuning.fountainLead + Double(i) * 1.7,   // lead 26
               lane: laneIndex,                          // deterministic from state, NOT rng
               y: 0.8))
}
```

- New `Tuning`: `flowPerSurge = 3`, `flowSurgeScore = 80`, `fountainGems = 10`,
  `fountainLead = 26`, `fountainSpacing = 1.7`.

**Determinism note (rule 2).** The fountain consumes **no RNG** — it derives from player
state (`laneIndex`, `distance`). Runs remain a pure function of (seed, input trace):
identical inputs reproduce identical fountains, so daily-challenge fairness and the
deterministic bot are preserved. The seeded stream that drives the spawner is never
touched, so pattern sequences stay byte-identical whether or not surges fire.

**Collision/solvability.** Fountain spawns are gems only — never lethal. They may overlap
a following pattern's obstacle field; gems inside obstacle lanes are simply uncollected
(or magneted). `capGem = 72` guards overflow (silent drop, existing behavior). The
Autopilot near-misses constantly by nature (it hugs lanes), so fountains fire throughout
the soak — and cannot kill it. **Zero Autopilot changes.**

**Snapshot/FX:** `GameSnapshot.flowStreak: Int` (HUD shows up to 3 pips next to the
multiplier — UI team's surface; the core just exposes the count).
`FXEvent.flowSurge(level: Int, x: Double)` (`level` = surges this run, lets audio/visuals
escalate).

**Renderer/audio:** player aura flash + lane shimmer toward the fountain; fountain gems
spawn with a sparkle cascade (masks the 26-unit pop-in); DSP riser pitched up per level.
Haptic: success notification.

**Variety per 60s:** the run currently rewards passivity (center lane, react). Flow makes
proximity itself a resource: aggressive players trigger a self-authored reward moment
every 15–25 s, casual players discover it organically through the existing CLOSE/SLICK
toasts. It is also the cheapest of the three (no entities, no patterns, no RNG, no bot
work) and a direct new coin source that scales with skill — the owner's "more ways to
earn coins" answered without inflating passive income.

### 2.4 Catalogue order & gating (rule 4 compliance)

Prefix gating means new patterns must slot so that each tier is a prefix. v1.3 order
(**moving walls remain LAST**; gauntlet/splitBar deliberately move after the two new
reward patterns so the fun unlocks before the pain — order change is legal because gates
are updated in the same change and the mandatory layoutVersion bump reshuffles dailies):

| Idx | Pattern | RNG calls | Tier |
|---|---|---|---|
| 0–8 | unchanged (gemLine … doubleBar) | unchanged | early/mid-1 |
| 9 | **ringArc (NEW)** | 1 | mid-2 |
| 10 | **overdriveRunway (NEW)** | 1 | mid-2 |
| 11 | gauntlet (was 9) | 1 | late |
| 12 | splitBar + chrono (was 10) | 2 | late |
| 13 | movingWalls (was 11) — **LAST** | 0 | full |

`Patterns.count = 14`. `Spawner.maxIndex` rewrite (new constant `Tuning.midEarlyDiff = 0.18`):

```swift
if dist < Tuning.earlyDistance { return 5 }    // 0–260 m: patterns 0–4
if diff < Tuning.midEarlyDiff  { return 9 }    // 260–576 m: + 5–8
if diff < Tuning.midDiff       { return 11 }   // 576–1440 m: + rings, overdrive
if diff < Tuning.movingWallMinDiff { return 13 } // 1440–1920 m: + gauntlet, split bars
return Patterns.count                          // 1920 m+: + moving walls
```

---

## 3. PACING — what 0–2 min vs 5 min+ should feel like

At average effective speeds, 2 minutes ≈ 2,200–2,400 m and 5 minutes ≈ 5,800 m+
(difficulty caps at 3,200 m). v1.2's curve has two dead zones: 260–1,440 m (the same 9
patterns for ~70 seconds) and post-3,200 m (nothing new ever again). v1.3 attacks both.

**Tightened unlock ladder** (a new *kind* of moment every ~20–35 s for the first 2 min):

| Distance | ≈ time | New this tier | Beat it adds |
|---|---|---|---|
| 0–260 m | 0:00–0:15 | patterns 0–4 | teach: collect, jump-arc, weave, slide |
| 260–576 m | 0:15–0:32 | + zigzag, mixed row, pickup, double bar | first power-ups, first combos |
| 576–1,440 m | 0:32–1:15 | + **rings**, **overdrive runways** | aim verb + adrenaline beat |
| 1,440–1,920 m | 1:15–1:35 | + gauntlet, split bars (+ chrono) | endurance chains, slow-mo |
| 1,920 m+ | 1:35+ | + moving walls | full catalogue |

**Flow Surge is tier-less** — it makes the *early* minutes self-directed (hunt CLOSEs)
even before the catalogue widens, and at 5 min+ it is what separates a focused run from
autopiloting: gap is at gapMin 5, every pattern is live, and the player's own aggression
modulates reward density. 5 min+ identity = *interleave density + flow management +
perfect-ring chasing*, not new content drip.

**Anti-repeat reroll** (the single biggest perceived-variety win per line of code): in
`Spawner.fill`, if the selected index equals the previous pattern's index, reroll once:

```swift
var idx = rng.int(0, maxIdx - 1)
if idx == lastIdx { idx = rng.int(0, maxIdx - 1) }   // one bounded reroll; repeats still possible
lastIdx = idx
```

This **changes RNG consumption** (conditional extra call) — covered by the same
layoutVersion 2 bump and the mandatory bot re-soak. `lastIdx` is new `Spawner` state
(reset with the spawner; deterministic).

**Tuning retunes — explorer-SAFE list only:**
- `streakPerMult: 6 → 5` (mult ×5 at 20 gems instead of 24; score-only per explorer §9;
  makes the first minute's collecting visibly escalate).
- Everything else holds. Explicitly NOT touched (CRITICAL list): `jumpV0/gravity`,
  `laneX/laneHitHalfWidth`, `bodyRadius/groundedCenterY`, moving-wall trio,
  `speedStart/Ramp/Cap`, `gapMin/gapMax`, `earlyDistance/midDiff/diffFullAt`,
  `gemLine` spacing.

---

## 4. TEST PLAN

### 4.1 Goldens that break (and how they're re-pinned)

- **`DailyChallengeTests.testGoldenSeeds`** — `layoutVersion` default goes 1 → 2.
  The 2026-06-10 v2 golden is *already pinned*: `0x1030_754F_4336_7811` becomes the new
  default-arg expectation. The 2026-06-11 and 2025-12-31 defaults must be recomputed at
  implementation time (one-shot print from `DailyChallenge.seed(..., layoutVersion: 2)`),
  and a fresh explicit `layoutVersion: 3` pin is added so the next bump is pre-armed.
  `testConsecutiveDatesDiffer` and `testSameDailySeedYieldsIdenticalRun` are
  relative/self-comparing — they pass unchanged.
- **`DifficultyTests`** — any assertions on `Spawner.maxIndex` tier values/boundaries
  update to the 5-tier ladder (5/9/11/13/14) and `Patterns.count = 14`.
- **`RNGTests`** — if any test pins an absolute `runHash` golden (vs comparing two runs),
  it breaks (spawn stream layout changed) and gets re-pinned; the pure SplitMix64 vector
  tests are untouched.

### 4.2 Solvability bot (must stay green, zero deaths)

- `testGreedyBotSurvives200Seeds` (200 × 6,000 m) and `testGreedyBotSurvivesDeepRuns`
  (10 × 12,000 m) re-run against the 14-pattern catalogue + anti-repeat + new lengths.
  **No Autopilot code changes are required** (rings/pads live in `activePickups`; boost
  is contained in an obstacle-free runway; fountains are gems) — the soak verifies it.
- New directed solvability tests:
  - `testOverdriveRunwayContainmentInvariant` — *geometric, no sim*: generate pattern 10
    output for d ∈ {600, 1600, 3200, 8000}; assert it emits zero obstacle SpawnCmds and
    `padTriggerLatest + boostDuration × boostSpeedMax < length` (5.1 + 36 < 48).
  - `testBotSurvivesForcedBoostIntoNextPattern` — debug-spawn a pad, then drive the bot
    through 200 m of normal spawning with boost forced on trigger; zero deaths.

### 4.3 New unit tests

- **`ArcCollectionTests`** (the P0 regression net):
  - For d ∈ {300, 1000, 2500, 4000} (v ≈ 18.6, 22.2, 30, 33): `debugClearTrack`,
    debug-spawn the new arc at a known distance, scripted input jumps exactly at gem 0
    → assert **7/7 gems collected**.
  - Jump-late tolerance: same setup, jump 1.2 units late → assert 7/7 (inside the ±1.6
    worst-case budget).
  - Chrono: debug-spawn `.chrono`, collect it, cross an arc placed for v=24.5 →
    assert **≥ 5/7** (pins §1.4's guarantee).
  - Pattern-length law: for each arc pattern, `length ≥ arcEnd − b + margin`.
- **`RingTests`**: `Collisions.ringPass` boundary values (pass edge 0.9, perfect edge
  0.12, miss); integration: scripted jump through pattern-9 ring at fixed d → assert
  `.ringPassed(perfect: true)` fires once, score/coin deltas exact; no-jump → no event.
- **`BoostTests`**: trigger requires grounded (airborne crossing does not trigger);
  `effectiveSpeed` composition (boost alone = min(1.3·v, 36); chrono+boost = capped
  product); `boostEnded` emitted exactly once on edge; `snapshot.boostRemaining` mirrors;
  gem coin bonus only while active; second pad refreshes timer.
- **`FlowTests`**: 3 near-misses → exactly one surge, `fountainGems` gems spawned in the
  player's lane at lead 26; streak resets on `shieldAbsorbed` and death; surge math at
  streak 6, 9 (levels escalate); **determinism**: same seed + same scripted input trace
  twice → identical run hash (fountains included); **stream isolation**: a run with
  surges and a run without (different inputs, same seed) produce identical *pattern*
  sequences (spawner cursor log equality).
- **`PatternOrderTests`**: movingWalls is `Patterns.count − 1`; `maxIndex` monotone
  non-decreasing in distance; tier boundary values exact; per-pattern RNG call counts
  pinned (0–8 unchanged, 9:1, 10:1, 11:1, 12:2, 13:0) so future drift forces a
  conscious layoutVersion decision.
- **`EconomyTests` additions**: ring coins and boost gem bonus flow through `gemCount`
  → single `applyRunSummary` payout unchanged (rule 9); doubler × boost stacking pays
  2+1 per gem.
- **`CollisionTests` additions**: ring/pad predicates at exact boundary values.

Estimated suite: 95 → ~112 tests.

### 4.4 Implementation surface summary (for the wave plan)

- `Models.swift`: `EntityKind.{ring, boostPad}`; `GameSnapshot.{boostRemaining, flowStreak}`
  (+ `.initial` defaults); `FXEvent.{ringPassed, boostStarted, boostEnded, flowSurge}`.
- `Patterns.swift`: new `gemArc`, two new patterns, reorder, `count = 14`, length math.
- `Spawner.swift`: 5-tier `maxIndex`, `lastIdx` anti-repeat.
- `Tuning.swift`: ~16 new constants (listed inline above), `streakPerMult = 5`.
- `Collisions.swift`: `ringPass`; pad trigger predicate.
- `GameCore.swift`: `boostT`/`flowStreak` state + reset paths (`reset`, `revive` keeps
  flow at 0), `effectiveSpeed` composition, pickup handling for ring/pad, surge hook in
  near-miss branches, snapshot fields.
- `DailyChallenge.swift`: default `layoutVersion = 2`.
- `Autopilot.swift`: **no changes** (the load-bearing design property of this entire spec).
- Meta/profile: if `bestFlow`/`ringsPassed` persist, decode via
  `decodeIfPresent ?? 0` (rule 7). Renderer: ring torus + pad chevrons via
  `MeshDescriptor`, audio via DSP synth (rule 6 — zero binary assets). All new code
  Foundation-only in Core (rule 1), Swift 6 strict concurrency (rule 8): all new types
  are `Sendable` value types; GameCore stays `@MainActor`.

---

## 5. Iron-rule compliance matrix

| Rule | Status |
|---|---|
| 1 Core purity | All new sim code is Foundation-only; world contact via Snapshot/FXEvent additions only |
| 2 Seeded RNG | gemArc/lengths: pure f(d). New patterns: 1 RNG call each via the run stream. Flow: zero RNG, deterministic from (seed, inputs) |
| 3 Bot green + layoutVersion | layoutVersion 1→2 (single bump); both soaks re-run; two new directed bot tests; Autopilot untouched |
| 4 Pattern order | Prefix tiers rewritten with the reorder; **movingWalls stays LAST (idx 13)** |
| 5 G3 observation rules | No UI work in this spec; snapshot remains the only observed property |
| 6 Zero binary assets | Ring torus / pad chevrons via MeshDescriptor; all audio DSP-synthesized |
| 7 Profile decoding | New persisted stats use `decodeIfPresent ?? default` |
| 8 Swift 6 strict | New state on `@MainActor GameCore`; new enums/structs `Sendable` |
| 9 Economy | All new coin sources route through `gemCount`; one `applyRunSummary` per run |
| 10 Checkpoint/challenge | Untouched; new mechanics are seed-deterministic so challenge runs stay fair |
