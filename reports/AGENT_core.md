# AGENT_core — Core gameplay wave handoff (v1.2)

All work confined to `PrismRush/Core/**` + `Tests/CoreTests/**` (SynthTests untouched).
**Suite: 68/68 green** (`swift test -c release`), including the 200-seed × 6,000 m solvability bot
AND a new 10-seed × 12,000 m deep soak that exercises split bars + chrono at full density.

---

## BREAKING CHANGES to Models / snapshot (integration agent: update call sites)

### 1. `FXEvent.nearMiss` kind is now an enum
- OLD: `case nearMiss(kind: String, x: Double)` — `"CLOSE"` / `"SLICK"`
- NEW: `case nearMiss(kind: NearMissKind, x: Double)` with `enum NearMissKind { case close, slick }`
- Break sites: `UI/GameView.swift:195-196` (`kind == "CLOSE"` comparison and `addPopup(kind, …)`
  which expects a String — map `.close → "CLOSE"`, `.slick → "SLICK"` for display).
  `Services/Haptics.swift:38` (`case .nearMiss:`) still compiles as-is.

### 2. New `PickupKind` cases: `.doubler`, `.chrono`
- Any exhaustive `switch` over `PickupKind` (FX handling for `.pickup(kind:…)` in
  GameView/SynthEngine/Haptics) must add the two cases.

### 3. New `EntityKind` cases: `.splitBar`, `.doubler`, `.chrono`
- Break site: `Render/Reality/RealityRenderer.swift:260` `makeEntity(_:)` exhaustive switch.
  Suggested meshes: splitBar = two 1-lane bar segments over the covered lanes (see contract
  below), doubler/chrono = pickup-sized procedural meshes (gold "×2", teal hourglass/clock).
- `EntityPools` keys by `EntityKind` — pools for the three new kinds appear automatically, but
  cap sizing should mirror `Tuning.capSplitBar = 6`, `capDoubler = 2`, `capChrono = 2`.

### 4. `GameSnapshot` field changes
- `speed` now carries the **EFFECTIVE** speed (chrono-slowed). This is deliberately the field
  the renderer already reads (`RealityRenderer.swift:95-96`) so camera FOV, world scroll and
  trail emission slow down with zero renderer changes.
- NEW `rampSpeed: Double` — the raw, un-slowed difficulty-ramp speed (HUD/debug only).
- NEW `doublerRemaining: Double` — > 0 → gems pay double coins. HUD should show the timer.
- NEW `chronoRemaining: Double` — > 0 → slow-mo active. HUD timer; renderer may tint.
- NEW `usedCheckpoint: Bool` — see §Game Center below.

### 5. `EntityState.y` is authoritative for ALL obstacle kinds (contract)
- Bars now arrive with `y = 1.3` **from the core** (was `0`, renderer hardcoded 1.3).
- Remove the hardcode at `RealityRenderer.swift:137` (`s.kind == .bar ? 1.3 : Float(s.y)`)
  → always `Float(s.y)`. Heights: bar/splitBar 1.3, low 0.425, tall/movingTall 1.6.
- This keeps the door open for a piston-style obstacle whose `y` animates from the core.

### 6. New `FXEvent.chronoEnded`
- Fired exactly once, the tick the chrono timer crosses 0 (an edge, not a level). Audio should
  key the "time resumes" sting / filter release off it; pickup start uses the existing
  `.pickup(kind: .chrono, …)`.

### 7. `SpawnCmd` new cases (only matters to anything pattern-matching it)
- `.splitBar(d: Double, openLane: Int)`, `.doubler(d: Double, lane: Int)`,
  `.chrono(d: Double, lane: Int)`.

---

## What the integrator must wire

| Layer | Work |
|---|---|
| GameView | `nearMiss` enum mapping (popup text/colors); new `.pickup` kinds → SFX/popup |
| Renderer | `makeEntity` meshes for splitBar/doubler/chrono; drop the bar-y hardcode (use `s.y`); splitBar render: `lane` on the entity is the **OPEN** lane — draw bar segments over the other two lanes at y 1.3 |
| HUD | doubler ×2 badge + `doublerRemaining` timer; chrono timer (`chronoRemaining`); optional `rampSpeed` debug readout |
| Audio | chrono pickup + `chronoEnded` edge; doubler pickup; (optional) pitch/LP filter while `chronoRemaining > 0` |
| Game Center | **Skip leaderboard submission when `snapshot.usedCheckpoint == true`** (checkpoint runs reach 66 pts/s from t=0 — strictly better for best-score chasing). Local best may still update. |
| Daily challenge (meta) | `DailyChallenge.seed(year:month:day:layoutVersion:)` — derive y/m/d **in UTC**; pass the seed to `startRun(seed:)`. **Bump `layoutVersion` whenever spawner/pattern/RNG-consumption behaviour changes** (this wave is version 1). Goldens pinned in `DailyChallengeTests`. |

---

## Bug fixes (all probe-confirmed, all tested)

1. **NaN dt guard** — `GameCore.advance` rejects non-finite / ≤ 0 `realDt` before the
   accumulator (`min(NaN, 0.1)` is NaN and was sticky). `testAdvanceSurvivesNaNAndJunkDt`.
2. **Near-miss band** — `nearMissOuter 2.4 → 1.95` (lane pitch is 2.2; standing a lane away used
   to auto-award CLOSE ~119 pts/run), `nearMissBonus 25 → 40`. New pure predicate
   `Collisions.closeNearMiss(dx:)` + boundary tests; sim tests prove dx 2.2 pays nothing,
   dx 1.6 pays once.
3. **Shield same-tick double-hit** — new `invulnT` (0.4 s, `Tuning.invulnDuration`) set on
   absorb; obstacle hit checks skipped while > 0 (a same-tick break was NOT enough — the twin
   wall stays in the kill band for ~13 more ticks). Hand-built twin-tall test incl. expiry
   re-arm. `invulnT` is exposed `private(set)` if the renderer wants a flicker.
4. **Revive score leak** — `die()` records `deathDistance`; `revive()` folds the death-decel
   drift into `scoreOffset` (`+= distance − deathDistance`). Score after revive == frozen death
   score; `traveledDistance` (coin payout basis) is corrected too.
5. **Checkpoint fairness** — `usedCheckpoint` on core + snapshot (see GC row above).
6. **Minors** — magnet no longer pulls when `mode != .play`; gem `fading` is sticky (no
   opacity pop on window release); `obstacleCount(where:)` closure predicate (no per-spawn `Set`
   allocation); `nearMiss` enum (above); `Tuning.worldBlendRate = 0.6` (was hardcoded 0.8 —
   ~1.7 s cinematic crossfade).

## Tuning (pinned in `testRetunedFeelConstants`)

- Fresh `startRun()` launches at `speedStart` 17 (was menuSpeed 7 — killed the 1.5 s crawl).
- `revive()` → `speed = max(speed, speedStart)` (paid continues feel instant).
- `laneLerpRate 12 → 15` (settle 0.38 → 0.30 s), `streakPerMult 8 → 6` (×5 at 24 gems),
  `magnetRange 13 → 16`, `magnetGemYRate 5 → 7` (arc gems now reel in vertically).

## New features

- **A. Coin Doubler** — `doublerT` (10 s). Gems pay `gemCount += 2` (currency feeding the coin
  payout — zero meta changes) but `streak += 1` (skill stats never double). Spawned from
  pattern 7's pickup roll, now weighted 3-way: shield 40% / magnet 40% / doubler 20%.
- **B. Chrono slow-mo** — `chronoT` (5 s, factor 0.65). Distance integrates
  `speed × factor` while the raw `speed` ramp is untouched (resumes seamlessly); the player
  ticks at real dt → dodge windows stretch ~1.5×, strictly easier. Autopilot leads
  (`jumpLead`/`slideCommit`) now scale from `effectiveSpeed`; `testBotCollectsChronoDuringProceduralRuns`
  proves the bot survives real runs WITH slow-mo active. Spawned by pattern 10 (35% roll, in the
  gap lane), so it's gated diff ≥ 0.45 by construction.
- **C. Split Bar** — overhead bar covering 2 of 3 lanes; `CoreEntity.lane` = open lane.
  Pure predicate `Collisions.splitBarHit` (bar kill band ∧ covered lane within
  `laneHitHalfWidth`) with tall-style boundary tests. Two legal answers: steer to the gap or
  slide. Autopilot: covered lanes feed `laneScore`/`blockedNow` exactly like talls (steers to
  the gap) and splitBars join `nearestBar` (slide fallback when the gap is unreachable).
  **Pattern note:** split bar landed at index **10** and moving walls moved to index **11** —
  the spawner gates by prefix (`maxIndex`), and split bars unlock at diff ≥ 0.45 while moving
  walls must stay ≥ 0.6; keeping moving walls last preserves both gates. Gating table + 
  DifficultyTests rows updated (1440 m → 11 selectable, 1920 m → all 12).
- **D. y plumbing** — `EntityState.y` = `CoreEntity.baseY` for every obstacle (contract in §5).
- **E. DailyChallenge** — `Core/DailyChallenge.swift`, pure, no `Date`:
  fold `y*10000 + m*100 + d` XOR tag `0x5052_4953_4D44_4159` ("PRISMDAY") XOR
  `layoutVersion << 48` through one SplitMix64 step. Goldens (v1):
  2026-06-10 → `0xFBC0C33738F02209`, 2026-06-11 → `0x9399C65392BADC4F`,
  2025-12-31 → `0x2CC216EEF9259E5F`.

## Test inventory (CoreTests, 68 total; SynthTests' 8 owned elsewhere)

- `GameplayTests` (12): dt guard · near-miss band ×2 · single-award pin · shield/death path pin ·
  twin-tall invuln · score freeze · revive score/speed · checkpoint flag · splitBar sim · feel pins
- `PowerUpTests` (5): doubler currency/streak split · doubler expiry · chrono distance/snapshot ·
  chronoEnded edge · bot-collects-chrono solvability
- `DailyChallengeTests` (3): goldens · consecutive-date inequality · same-seed run-hash determinism
- `CollisionTests` (19): +4 splitBar boundaries, +closeNearMiss band, magnet window re-pinned to
  `Tuning.magnetRange`
- `DifficultyTests` (5): gating rows updated for the 12-pattern catalogue
- `SolvabilityBotTests` (2): 200 × 6,000 m AND 10 × 12,000 m deep soak — zero deaths
- `RNGTests` (5) / `SmokeTests` (2) / `EconomyTests` (8): unchanged, green

## Test scaffolding added to GameCore (used by tests; also handy for demos)

- `debugClearTrack()` — wipes live entities + parks the spawner (hand-built scenarios).
- `debugSpawn(_ cmd: SpawnCmd)` — inject a single spawn through the normal `apply` path.

## Determinism note

Pattern 7's pickup roll consumes one `rng.unit()` (was one `chance(0.5)`) and pattern 10 changed
entirely — **seed → run mappings differ from v1.1**. That's why DailyChallenge landed last and
why its `layoutVersion` starts at 1 with these streams.
