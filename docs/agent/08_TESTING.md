# Testing map

Written session 002 from the session-001 survey (`docs/agent/scratch/tests-tools.md`) plus direct
re-verification of every line number cited here. Repo root in all paths below:
`/Users/rayankarimcheca/Desktop/ClaudeProjects/projects/prism-rush-ios/.claude/worktrees/beautiful-davinci-797e3b`.

Read this **instead of** re-exploring `Tests/`, `UITests/`, `Tools/`, and `.github/workflows/`.
Every number here was measured or grepped, not quoted from a doc.

---

## Real measured numbers

### The run

Two independent executions of the same command, both on 2026-07-27:

| when | command | result | XCTest time | wall clock |
|---|---|---|---|---|
| 13:51 (survey, session 001) | `/usr/bin/time -p swift test -c release` | **178 tests, 0 failures** | 7.283 s | **28.89 s** (`user 25.09`, `sys 3.24`) — included a release recompile |
| 14:14 (session 002, confirming) | `/usr/bin/time -p swift test -c release` | **178 tests, 0 failures** | 7.681 s | **8.86 s** (`user 7.91`, `sys 0.54`) — warm `.build`, no recompile |
| 2026-07-28 (session 004, after PR-0400/0414) | `swift test -c release` | **187 tests, 0 failures** | 24.04 s | warm `.build` |

Read the first two as: **~8–9 s warm, ~30 s when `.build` needs a release compile.**

**Session 004 changed both numbers.** The count is now **187**: `DifficultyCurveTests` (5) plus four
new gates in `DifficultyTests`. The XCTest time roughly tripled to ~24 s, and that is expected, not
a regression — `DifficultyCurveTests` plays **64 seeded Autopilot runs to 9,600 m** plus a 16-seed
× 12,000 m greed-line sweep, because measuring a difficulty curve honestly means simulating it. It
is the second-most expensive test in the suite after the solvability bot. If you need the fast loop,
`--filter` around it.

Trailing output of both runs ends with:

```
✔ Test run with 0 tests in 0 suites passed after 0.001 seconds.
```

That is the **swift-testing** runner finding nothing. The suite is **100 % XCTest** — grep for
`import Testing` / `@Test` across `Tests/` + `UITests/` returns zero hits. If a future session is
told "use Swift Testing for new tests" (the global `~/.claude/rules/swift/testing.md` says so), note
that doing it introduces the first `@Test` in the repo; it will work, but the counts below split.

### Per-suite table (from the 13:51 run; ordering is alphabetical, as XCTest emits it)

| suite | tests | seconds |
|---|---|---|
| ArcCollectionTests | 4 | 0.005 |
| BoostTests | 4 | 0.001 |
| CollisionTests | 21 | 0.001 |
| DailyChallengeTests | 3 | 0.015 |
| DifficultyTests | 5 | 0.050 |
| EconomyTests | 30 | 0.008 |
| FlowTests | 4 | 0.041 |
| GameplayTests | 12 | 0.005 |
| MissionsTests | 18 | 0.002 |
| PatternOrderTests | 2 | 0.001 |
| PowerUpTests | 16 | 0.233 |
| ProgressionTests | 15 | 0.002 |
| RNGTests | 5 | 0.059 |
| RingTests | 3 | 0.001 |
| ShopValueTests | 15 | 0.001 |
| SkinCatalogTests | 5 | 0.001 |
| SmokeTests | 2 | 0.000 |
| SolvabilityBotTests | 4 | 6.817 |
| SynthTests | 10 | 0.041 |
| **total (session 001)** | **178** | **7.283** |
| + DifficultyCurveTests (S-004) | 5 | ~16.9 |
| + DifficultyTests, 4 new gates (S-004) | 4 | ~0.02 |
| **total (session 004)** | **187** | **24.04** |

### The four slowest tests — 96 % of the runtime

```
4.263 s  SolvabilityBotTests.testGreedyBotSurvives200Seeds
2.549 s  SolvabilityBotTests.testGreedyBotSurvivesDeepRuns
0.216 s  PowerUpTests.testBotCollectsChronoDuringProceduralRuns
0.049 s  DifficultyTests.testSpeedMonotonicToCap
```

Everything else is sub-0.25 s. **If the SPM suite suddenly takes minutes, the cause is almost always
a spawner change pushing the bot toward `maxTicks = 400_000` (`Tests/CoreTests/SolvabilityBotTests.swift:93`),
which surfaces as a "STALLED" failure, not a hang.**

### The four real counts

| bundle | tests | how derived |
|---|---|---|
| SPM (`swift test`) | **187** | S-004; was 178 through S-003 |
| Xcode unit bundle `PrismRushTests` | **194** | `Tests/` path = 181 declared in `Tests/CoreTests/**` + 4 in `Tests/WorldPaletteTests.swift`; all 181 compile on iOS (the 3 UIKit-gated ones become live) |
| Xcode UI bundle `PrismRushUITests` | **11** | `UITests/InteractionUITests.swift` |
| whole scheme (`xcodebuild test`) | **205** | 194 + 11 |

`Tests/CoreTests/**` declares **190** `func test`; only **187** execute under `swift test`. The
3-test delta is `CharacterParityTests`, gated behind `#if canImport(UIKit)`
(`Tests/CoreTests/CharacterParityTests.swift:4`). See "What compiles where".

### Wrong test counts currently written in the repo — do not trust any of these

| file:line | what it says | reality |
|---|---|---|
| `CLAUDE.md:44` | "→ 95 tests (89 unit + 6 XCUITest)" | **196** (185 unit + 11 XCUITest) |
| `CLAUDE.md:50` | "`swift test -c release` # 89 tests, ~9 s" | **187** tests; ~24 s XCTest since S-004, ~25 s warm wall |
| `CLAUDE.md:52` | "Core/, **4** Meta files, Audio/Synth.swift" | `Package.swift:16-22` lists **7** Meta files |
| `CLAUDE.md:53-54` | non-SPM layers are "**not even type-checked**" on CI | Half-true and misleading. True for the Linux job. **False for CI overall**: `.github/workflows/ios-build.yml:48-54` runs `build-for-testing` against `generic/platform=iOS Simulator`, which type-checks all 70 production files and all 22 test files |
| `Tools/ci.sh:9-10` | "The full suite is 174 tests (163 unit + 11 XCUITest) at v1.4.3" | **196** (185 + 11) at v1.6 — off by 22 |
| `README.md:115` | "38 unit + 6 XCUITest interaction tests" | historical v1.x row; **196** today |
| `README.md:127` | "the full **89-test** suite" | **187** on SPM |
| `README.md:158` | "89/89 unit tests" on Linux | **187/187** |
| `README.md:206` | "`swift test -c release` **129/129**" (labelled v1.3-era) | **187/187** |

Correct-today claims, for contrast (so you know which docs to trust):
`README.md:14` ("196 tests green (185 unit + 11 XCUITest)"), `README.md:398`, `README.md:452`,
`state.md:8` ("SPM 178/Linux; Mac 185 unit + 11 XCUITest"). Older per-version rows inside `state.md`
(lines 107, 245, 284, 306-307 quoting 174 / 171 / 160) are historical records of what was green at
that version — not current claims.

---

## How to run each suite

### 1. `swift test -c release` — the deterministic layers

```bash
cd <repo root>
swift test -c release
```

- **Covers:** the 187 SPM tests — `Core/` (all 10 files), 7 `Meta/` files, `Audio/Synth.swift`.
  Includes the 200-seed solvability bot and the 12,000 m deep soak.
- **Time:** ~8.9 s warm, ~29 s with a release compile, more on a cold `.build`.
- **Prereqs:** a Swift 6 toolchain. No Xcode project, no simulator, no signing, no network.
  Runs on Linux (this is exactly what `core-tests.yml` runs in `swift:6.0-noble`).
- **Does NOT run:** `CharacterParityTests` (3, UIKit-gated), `WorldPaletteTests` (4, outside
  `Tests/CoreTests/`), all 11 XCUITests, and anything touching RealityKit / SwiftUI / StoreKit /
  AVFoundation / GameKit.
- Use `-c release` deliberately: the debug bot soak is far slower, and the repo's `debug*` hooks are
  unconditionally compiled precisely so the release build still exposes them.

### 2. `./Tools/build.sh` — does the app compile

```bash
./Tools/build.sh                                    # defaults: iPhone 17 Pro, iOS 26.5
PR_SIM_NAME="iPhone 16 Pro Max" PR_SIM_OS=26.5 ./Tools/build.sh
```

- **Does:** `cd` repo root → `xcodegen generate --quiet` → `xcodebuild … -derivedDataPath .dd
  CODE_SIGNING_ALLOWED=NO -quiet build`. Prints `BUILD OK`.
- **Covers:** compile + strict-concurrency type-check of all 70 production files. This is the only
  local gate that proves a UI/Render/Audio/IAP change is even valid Swift.
- **Time:** ~1–3 min clean, seconds incremental.
- **Prereqs:** `xcodegen` on PATH, Xcode with the named device *and* runtime installed.
- **Env:** `PR_SIM_NAME` (default `iPhone 17 Pro`, `Tools/build.sh:7`), `PR_SIM_OS` (default `26.5`,
  `Tools/build.sh:8`).

### 3. `./Tools/ci.sh` — the full local gate

```bash
./Tools/ci.sh
PR_SIM_NAME="iPhone 16 Pro Max" ./Tools/ci.sh
```

- **Does:** three banner-separated stages — (a) `xcodegen generate`, (b) `./Tools/build.sh` (which
  regenerates the project a *second* time), (c) `xcodebuild test` on the whole `PrismRush` scheme.
  Prints `CI GREEN`.
- **Covers:** everything. `project.yml:73-77` sets the scheme's `test.targets` to
  `[PrismRushTests, PrismRushUITests]`, so this is the **only** thing anywhere that executes the 11
  XCUITests — 196 tests total.
- **Time:** several minutes. The UITests alone contain three 25-second waits
  (`UITests/InteractionUITests.swift:41, 92, 168`).
- **Prereqs:** everything `build.sh` needs, plus a bootable simulator (the test stage needs a real
  device, not `generic/`).
- **Same env overrides** as `build.sh` (`Tools/ci.sh:19-20`).

### 4. `./Tools/qa.sh` — one screenshot, no assertions

```bash
./Tools/qa.sh
PR_SIM_UDID=<udid> PR_SHOT_DELAY=6 ./Tools/qa.sh
```

- **Does:** `simctl boot` (errors swallowed by `|| true`, `Tools/qa.sh:10`) → `open -a Simulator` →
  `./Tools/build.sh` → `simctl install` → `simctl launch` → `sleep ${PR_SHOT_DELAY:-4}` →
  `simctl io … screenshot` into `reports/shots/shot_<epoch>.png`.
- **It has no pass/fail.** There is no assertion in the file. "qa.sh passes" in the Definition of
  Done means *you ran it and read the PNG*. A green exit says nothing about what is on screen.
- **Time:** build time + ~10 s.
- **Prereqs:** the UDID at `Tools/qa.sh:7` (`PR_SIM_UDID`, default
  `10C15FE0-3D9A-40D5-9E45-C0702E906DF3`) must exist, and `build.sh` must have produced
  `.dd/Build/Products/Debug-iphonesimulator/PrismRush.app` (hardcoded, `Tools/qa.sh:15`).
- **Trap:** it does **not** set `PR_SKIP_SPLASH=1`, so the 4 s default sleep can capture the splash
  instead of the menu.

### 5. Raw `xcodebuild test`

```bash
xcodebuild test -project PrismRush.xcodeproj -scheme PrismRush \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  CODE_SIGNING_ALLOWED=NO
```

- Requires `xcodegen generate` first — **`PrismRush.xcodeproj` is not checked in** and does not exist
  in a fresh clone.
- `CODE_SIGNING_ALLOWED=NO` is mandatory: `project.yml:12` carries a real `DEVELOPMENT_TEAM`
  (`8M64JJQQAU`) and Xcode will otherwise demand signing.
- Add `-only-testing:PrismRushTests` to run 185 unit tests without the 11 slow XCUITests
  (this is what `ios-build.yml:64` does).
- Add `-derivedDataPath .dd` to share build products with `build.sh` / `qa.sh`.

### 6. Autoplay demo launch

```bash
SIMCTL_CHILD_PR_AUTOPLAY=1 xcrun simctl launch booted com.rayancheca.prismrush
```

`simctl` forwards any `SIMCTL_CHILD_*` variable to the app. There are **17** production-compiled
`PR_*` hooks (grepped from `PrismRush/`, not 6 as the survey's shortlist implied):

```
PR_AUTOPLAY  PR_BUYPACK  PR_DEEPWORLDS  PR_DEMO  PR_DEMOPROFILE  PR_FIRSTRUN
PR_FOCUS  PR_MYSTERYBOX  PR_PLAYCONFIRM  PR_POWERUPS  PR_SCREEN  PR_SHIELD
PR_SKIN  PR_SKIP_SPLASH  PR_SNEAKERS  PR_TUTORIAL  PR_WORLD
```

They are compiled into **every** configuration, not just Debug (e.g.
`PrismRush/UI/GameView.swift:102-103, 146, 215, 235, 921-923`). Harmless in practice — env vars
cannot be injected into a sandboxed App Store launch — but worth knowing before someone "cleans them
up" and breaks all 11 XCUITests.

### ⚠️ Concurrency warning — never overlap simulator work

**Never run `Tools/qa.sh`, `Tools/screenshots.sh`, or a bare `simctl launch`/`simctl install`
against the same simulator while `xcodebuild test` is running on it.** The concurrent install kills
the test host and xcodebuild reports a false `TEST FAILED` that looks like a real regression. This is
documented at `CLAUDE.md:57-58` and it costs ~30 minutes of misdirected debugging every time.

Extra hazard on this machine: **two simulators share the name "iPhone 17 Pro"** and two share
"iPhone 17 Pro Max". `build.sh`/`ci.sh` select **by name** (non-deterministic which one wins);
`qa.sh`/`screenshots.sh` install **by UDID**. They can therefore target *different physical devices
in the same session*, which makes "I built it but the screenshot is stale" a real failure mode.

---

## What compiles where

This section exists because **"`swift test` green" does not mean "the app builds"**.

### `Package.swift` — the 18 files SPM compiles (Linux *and* the local `swift test`)

`Package.swift:14-24`:

```
PrismRush/Core/                 ← whole DIRECTORY, so new Core files are auto-included
  Autopilot.swift  Collisions.swift  DailyChallenge.swift  GameCore.swift  Math.swift
  Models.swift     Patterns.swift    RNG.swift             Spawner.swift   Tuning.swift
PrismRush/Meta/Profile.swift        ← named INDIVIDUALLY
PrismRush/Meta/ProfileStore.swift
PrismRush/Meta/SkinCatalog.swift
PrismRush/Meta/SkinUnlocks.swift
PrismRush/Meta/MissionCatalog.swift
PrismRush/Meta/XPCurve.swift
PrismRush/Meta/ShopValue.swift
PrismRush/Audio/Synth.swift         ← named INDIVIDUALLY
```

Test sources: `path: "Tests/CoreTests"` only (`Package.swift:29`).

**Asymmetry trap:** `"Core"` is a directory entry, so a new `Core/Foo.swift` is compiled and covered
automatically. `Meta/` and `Audio/` are file-by-file, so a new pure `Meta/Bar.swift` is **silently
invisible** to Linux CI until someone adds a line. There is no error — the file simply is not
compiled there. `Meta/` currently has **7 files**, all listed; `Audio/` has **3**, of which only
`Synth.swift` is listed.

### The 52 production files SPM never compiles

`PrismRush/` holds 70 Swift files; 18 are in the SPM list. The remaining 52:

| dir | files | lines | why excluded |
|---|---|---|---|
| `Render/` | 16 | 4,758 | RealityKit |
| `UI/` | 26 | 8,688 | SwiftUI |
| `Services/` | 4 | 308 | GameKit, AuthenticationServices, Security, CoreHaptics |
| `IAP/` | 2 | 290 | StoreKit 2 |
| `Audio/` (Music, SynthEngine) | 2 | ~310 | AVFoundation |
| `App/` | 2 | 32 | SwiftUI app entry |

### What CI actually type-checks vs executes

| | `core-tests.yml` (Linux) | `ios-build.yml` (macOS) |
|---|---|---|
| runner | `ubuntu-24.04`, container `swift:6.0-noble` | `macos-15`, newest installed Xcode |
| trigger | push to `main` + all PRs | push to `main` + all PRs |
| type-checks | the 18 SPM files + `Tests/CoreTests/**` | **all 70 production files + all 22 test files** (`build-for-testing`, `generic/platform=iOS Simulator`, lines 48-54) |
| executes | 187 tests | 185 unit tests, **only if a simulator literally named "iPhone 16" exists** (line 63) |
| never executes | — | the 11 XCUITests — `-only-testing:PrismRushTests` (line 64) |

**Files CI never type-checks: none.** CLAUDE.md's "not even type-checked" claim predates
`ios-build.yml`. The genuine CI blind spots are **behavioural**, not compile-level: the RealityKit
renderer, `SynthEngine`/`Music`, StoreKit, GameKit, Keychain, and all 26 UI files are compiled every
PR but their *runtime behaviour* is proven only by a human running `Tools/ci.sh` locally.

### The `CharacterParityTests` trap

```swift
// Tests/CoreTests/CharacterParityTests.swift:1-4
// Mac test bundle only: `CharacterProportions` lives in Render/ (ProceduralMesh.swift), which
// the Linux/SPM package never compiles — the UIKit gate keeps `swift test` green everywhere
// while the full xcodebuild suite enforces the pins.
#if canImport(UIKit)
```

`canImport(UIKit)` is **false on plain macOS** and false on Linux. So under `swift test` — on your
Mac, right now — this file compiles to *nothing*. There is no "skipped" line in the output; the tests
simply do not exist. That is the entire 190-vs-187 delta.

Consequence: the 3 rig↔preview proportion pins run **only** inside the iOS-Simulator Xcode bundle. If
`ios-build.yml`'s `test-without-building` step is removed, or its "iPhone 16" lookup fails, those 3
pins plus the 4 `WorldPaletteTests` run **nowhere** and the Linux job stays green.

The second escape hatch is placement: any test file under `Tests/` but **outside** `Tests/CoreTests/`
is compiled into the Xcode bundle only and is invisible to `swift test`. Today that is exactly
`Tests/WorldPaletteTests.swift` (4 tests), which needs `Theme` from `UI/`.

---

## Coverage map

One row per test file. "Does NOT pin" is the product of this document — those are where regressions
land silently.

| file | tests | pins | does NOT pin |
|---|---|---|---|
| `Tests/CoreTests/SmokeTests.swift` | 2 | `Tuning.laneX` has 3 entries, centre = 0, outer symmetric; `GameSnapshot.initial` is `.menu` at `Tuning.menuSpeed`, mult 1, no entities | any other `Tuning` constant; any other `GameSnapshot` field |
| `Tests/CoreTests/RNGTests.swift` | 5 | SplitMix64 same-seed determinism over 10 k draws; divergence within 32 draws; `unit()` ∈ [0,1) over 100 k; a 10 k-tick autopilot run hashes identically per seed. Owns the shared `static runHash(seed:ticks:)` FNV-1a fold over 7 per-tick fields | distribution quality; seed 0 / `UInt64.max` edges. **The hash omits pickups, buffs, flow state and the whole pickup entity list** — `FlowTests` maintains a second, divergent local fold that adds `flowStreak` + `boostT` |
| `Tests/CoreTests/CollisionTests.swift` | 21 | exact inclusive/exclusive boundaries for `playerBounds`, `lowHit`, `tallHit` (± Super Sneakers vault), `barHit`, `splitBarHit`, `gemPickup`, `magnetActive`, `boostPadHit` (grounded gate, ±1.1 lateral/depth), `closeNearMiss` band, `nearMissOuter < lane pitch` | `ringPass` (lives in `RingTests`); **`movingTall` collision geometry — nothing anywhere tests it directly, only the bot walks it**; NaN/∞ inputs |
| `Tests/CoreTests/DailyChallengeTests.swift` | 3 | 3 golden seeds at default `layoutVersion` (v7) + explicit v5/v6 goldens + a **pre-armed v8** golden (`:23-24`); 27 consecutive dates give distinct seeds; same daily seed ⇒ identical 10 k-tick run | date→(y,m,d) extraction (`ProfileStore.todaysChallengeSeed`, covered in `MissionsTests`); leap days; year boundaries past 2025-12-31 |
| `Tests/CoreTests/DifficultyTests.swift` | 5 | `Spawner.gap` monotone-decreasing and bounded, exact at d=0 and `diffFullAt`; `Spawner.maxIndex` 5-tier ladder at 8 exact boundaries; World 2 (800–1599 m) never unlocks moving walls; live speed monotone ≤ cap over 40 k ticks | interaction with `startDistance` (checkpoint runs); gap curve past 6,400 m |
| `Tests/CoreTests/PatternOrderTests.swift` | 2 | `Patterns.count == 14`; moving walls exclusively at index 13 with exactly 2 per run (`:26-27`); ring @9, boost pad @10, split bar @12; pattern 10 = 1 pad + 24 gems; exact per-pattern RNG-call vector `[1,1,0,1,1,3,1,2,0,1,1,1,2,0]` (`:60`) | the **content** of patterns 0–8. A pattern could swap a low for a tall and this file stays green |
| `Tests/CoreTests/SolvabilityBotTests.swift` | 4 | 200 seeds × 6,000 m and 64 seeds × 12,000 m, zero deaths **and** zero stalls (`:110-122`); overdrive runway containment; forced-pad survival for 200 m on 5 seeds | **human** solvability — `Autopilot` is greedy with perfect information and frame-accurate reactions. It never holds Super Sneakers, so vault-vs-procedural interaction is unexercised. Says nothing about fun or pacing |
| `Tests/CoreTests/GameplayTests.swift` | 12 | junk `dt` (NaN/∞/negative/zero) doesn't step or poison the accumulator; one-lane-away awards nothing; dx≈1.6 squeeze awards CLOSE once with exact bonus; no near-miss through shield-absorb or post-death; shield survives twin talls + grace then expires; score freezes at death, revive resumes at frozen score with decel folded into `scoreOffset`; checkpoint flag excludes head start; magnet stop; split-bar covered/gap/slide; 7 feel constants | double-revive; revive at various points in the death decel; revive interacting with a live buff |
| `Tests/CoreTests/ArcCollectionTests.swift` | 4 | the real 7-gem arc collects 7/7 on one jump at d ∈ {300, 1000, 2500, 4000}; still 7/7 at 1.2 units late; ≥5/7 under chrono at d=1442; every arc-bearing pattern (1,2,6,9,11) contains its last spawn ≥2 units before its end (6 distances × 3 seeds) | jumping **early**; the arc under Super Sneakers (higher apex would overshoot); the arc during a boost |
| `Tests/CoreTests/PowerUpTests.swift` | 16 | doubler doubles currency not streak and expires; chrono slows distance not the ramp, snapshot mirrors effective vs ramp, `chronoEnded` fires once; manual slow-mo activates / refuses to stack / re-arms / ignored outside play; Super Sneakers apex ≥1.4×, never lethal, own pickup kind, `sneakersEnded` once; Head Start grants boost without a checkpoint flag; manual overdrive + shield deploy once each; v1.6 cadence delivers all 5 kinds within 4,000 m | consumable **charge decrement** ("deploy consumes a charge" is nowhere); two buffs expiring on the same tick |
| `Tests/CoreTests/BoostTests.swift` | 4 | airborne pad crossings don't trigger and the pad stays grounded; grounded crossing pays `boostScoreBonus * mult`; `effectiveSpeed` = chrono × boost hard-capped at `boostSpeedMax` and never writes the raw ramp; `boostEnded` is a single edge, second pad refreshes without firing it; boosted gems pay +1 coin, stack with doubler (2+1), never bump streak | pad triggering during a death decel; boost interacting with `startDistance` |
| `Tests/CoreTests/RingTests.swift` | 3 | `ringPass` perfect band (±0.12) and pass band (±0.9) at both sides of every edge; a scripted jump through the real pattern-9 ring fires exactly one PERFECT with exact score/coin deltas and no streak bump; grounded pass-under yields no event and recycles | a **non-perfect** (plain) ring pass end-to-end in the sim — only the predicate covers it; multiple rings; a laterally-missed ring |
| `Tests/CoreTests/FlowTests.swift` | 4 | every 3rd near-miss surges and consumes the streak; the fountain is `fountainGems` gems in the player's lane at exact lead/spacing/height with **zero RNG**; shield-absorb and death both reset the streak; surge levels escalate 1,2,3; same seed + same inputs ⇒ identical hash; **different inputs on the same seed ⇒ identical obstacle kind/lane stream** | surge level 4+ (escalate or clamp?); the fountain while mid-lane-change |
| `Tests/CoreTests/EconomyTests.swift` | 30 | daily reward claim/streak/gap-reset/tier-cap; free chest 30-min cooldown; add/spend with overspend refusal; `unlockWorld` purchases, range guards, idempotence, "buying never touches `maxWorldReached`"; `reachCredit` can't launder a purchased start; `coinPackPayout` first-purchase +50 % rounding down, pays once, flag dedupes; `grantCoinPack(transactionID:)` replay idempotence; bounded granted-ID ledger; **cloud merge never erases purchased coins**, convergent, two-device concurrent purchases both survive; revive grace shield; clock-rollback clamps; `sanitized` clamps future timestamps; equipped-skin resolver self-heals; legacy JSON decode; consumables device-local; Mystery Box odds at every band edge | **the actual persistence** — `ProfileStore.load`, the write path, `persistentDeviceKey()`, the `NSUbiquitousKeyValueStore.didChangeExternallyNotification` observer, the `pr.profile.v1` UserDefaults key. Every test uses `init(testing:)` (`Meta/ProfileStore.swift:25`). Also no coin **earning** from a real end-to-end run |
| `Tests/CoreTests/MissionsTests.swift` | 18 | daily slots deterministic per day, 3 distinct, all from the daily pool; weekly rotation; UTC-midnight rollover wipes daily progress + claims; daily sums across runs vs per-run "best single run"; multiplier missions use max; claim-once semantics; incomplete/unknown claims inert; tiered achievements claim in order and exhaust; lifetime metrics never reset; unclaimed badge count; `todaysChallengeSeed` UTC goldens + midnight straddle; `secondsUntilUTCMidnight`; legacy decode + round-trip | the mission **catalog content** — are the targets reachable? is any mission impossible? Only "slots are distinct and from the right pool" is checked |
| `Tests/CoreTests/ProgressionTests.swift` | 15 | the whole XP curve (30 levels, 6 exact thresholds, `level(for:)` inverse at every boundary ±1, negative clamp, cap, `xpIntoLevel` incl. the (0,0) sentinel, `xpUnlockLevels`); the world price ladder exactly (11 rungs, total sink 59,400, `worldDisplayCount == 12`); the XP formula term-by-term incl. `startWorld` zeroing and the 2,000 clamp; IAP `doubleCoins` never inflates XP; level grants + `unlockedLevels` tagging; the `xpLevelRewarded` watermark ratchets and is idempotent; `bestDistanceByWorld` attribution; weekly slots deterministic/rotating/disjoint-from-daily/UTC-week-wiped, off-board slots unclaimable, rollback blocked; style coin cap; challenge placement tiers pay once/day; `[Int: Double]` keyed encode round-trip; cloud-merge max/union/device-local with no post-merge double grant | XP from a real end-to-end run — only synthetic `RunSummary`s |
| `Tests/CoreTests/SkinCatalogTests.swift` | 5 | 24 skins, unique ids/names, 16 frozen legacy pins (id/cost/bodyHex/antennaHex/premium), v1.4 eight's costs and unlock kinds, scale range, **decree 1** (no `followsWorld`, every skin has real hexes), exactly one prismatic + one premium, level locks == `XPCurve.xpUnlockLevels`, achievement unlocks reference real reachable tiers, challenge-day unlocks ≤50, rarity ordering/counts, unknown-id fallback; prismatic shimmer is pure, deterministic, 8 s-periodic, passes the 3 authored stops; `SkinUnlocks.earned` boundaries; `refreshSkinUnlocks` grant-once + level-30 catch-up + `markSkinsSeen`; every locked-skin requirement string | **decree 2 ("previews never lie") is not enforced for colour anywhere.** `CharacterParityTests` pins proportions only. Also nothing pins `ShopView`'s `featuredPool ⊆ SkinCatalog.all` (see zero-coverage §D) |
| `Tests/CoreTests/ShopValueTests.swift` | 15 | `coinsPerUnit` incl. zero/negative price guards; the four badge outcomes and their precedence (`bestValue` > `balancedPick`), below-baseline → none, single/empty grid → none; featured skin determinism per day, owned-skip, all-owned fallback; `StoreAvailability.afterLoad` ready vs notConfigured; `afterThrow` keeps `.ready`, degrades everything else to `.offline` | `ShopConsumables.packs` contents beyond the one `slowMoPack` used in `EconomyTests`; `CoinSpendItem`; any actual StoreKit interaction |
| `Tests/CoreTests/SynthTests.swift` | 10 | ~22 SFX are non-empty, finite, within a duration window, audible (peak > 0.005), non-clipping (peak ≤ 2.0); gem pitch rises with streak by ≥ a semitone; pickup sounds mutually distinct; the whole `Synth.SFX` catalog renders, cache keys normalise (gem modulo 26) and duck-classify; the v1.3 six mechanic SFX; **24 worlds × 8 beats** of music finite/sized/non-silent/non-clipping; adjacent worlds differ; one cycle deeper layers extra voices | perceptual quality; `SynthEngine`'s caching/ducking **implementation**; `Music`'s sequencing; `AVAudioSession` category; interruption recovery. **`testDeathSweepNoiseSwells` (`:67-71`) is a false negative** — see traps |
| `Tests/CoreTests/CharacterParityTests.swift` | 3 *(iOS bundle only)* | `CharacterProportions.sphereRadius / cubeEdgeRatio / cubeCornerRatio / crystalHalfWidthRatio / crystalHalfHeightRatio`; derived rig cube edge 1.06 and corner 0.18; crystal taller than wide in both layers and narrower than the sphere | it does **not** compare the rendered rig mesh to the rendered Canvas silhouette. It pins the shared *constants* both sides claim to derive from. If one side stopped using `CharacterProportions`, these stay green. Colour is not covered at all |
| `Tests/WorldPaletteTests.swift` | 4 *(Xcode bundle only)* | worlds 0–11 are cycle-0 identity (name/bg/grid/accent/accent2 equal the authored palette); evolution starts at ordinal `worlds.count` with a " II" suffix; `Tuning.worldFamilyCount == Theme.worlds.count`; 12 worlds, unique names, unique backgrounds | the hue-rotation math for cycles ≥1 beyond the name suffix; the per-world sky classes entirely |
| `UITests/InteractionUITests.swift` | 11 | see "The XCUITest gap" | see "The XCUITest gap" |

### Shared helpers you can break from a distance

| helper | file:line | who else depends on it |
|---|---|---|
| `RNGTests.runHash(seed:ticks:)` — `static`, FNV-1a over 7 per-tick fields | `Tests/CoreTests/RNGTests.swift:5` (class) | **`DailyChallengeTests` calls it directly.** Renaming it, making it non-`static`, or changing which fields it folds silently redefines what "identical run" means for the daily-leaderboard proof |
| `cleanCore(seed:)` + `tickUntil(_:max:)` | `Tests/CoreTests/BoostTests.swift:11-23` **and** `Tests/CoreTests/PowerUpTests.swift:9-21` | copy-pasted in both files (BoostTests adds a `startDistance:` param). Fixing a bug in one does not fix the other |
| `summary(...)` metric→`RunSummary` mapper | `Tests/CoreTests/MissionsTests.swift:21` **and** `Tests/CoreTests/ProgressionTests.swift:30` | second copy-paste pair; `ProgressionTests.swift:29` literally says "mirrors MissionsTests" |
| `InteractionUITests.launch(_:)` | `UITests/InteractionUITests.swift:11-19` | **must keep setting `PR_SKIP_SPLASH=1`** (`:15`). The splash covers the menu; without it every menu assertion in all 11 tests fails |

### Production seams the tests bind to

- **`GameCore`** — `@MainActor`, `@Observable`. Tests always do `GameCore(seed: 1)` then
  `startRun(seed:startDistance:)`; the constructor seed is discarded. **The snapshot only rebuilds on
  `advance(realDt:)`, not on bare `tick(_:)`** — three test files carry an explicit comment about
  this (`Tests/CoreTests/PowerUpTests.swift:39`, `Tests/CoreTests/BoostTests.swift:91`). Asserting on
  `core.snapshot` after `tick` is a guaranteed 20-minute confusion.
- **`ProfileStore`** — has `init(testing:deviceKey:)` (`PrismRush/Meta/ProfileStore.swift:25`) that
  bypasses UserDefaults *and* iCloud; `deviceKey` defaults to `"test-device"`. Grep confirms **zero**
  uses of `ProfileStore.shared` under `Tests/` or `UITests/`.
- **`Synth`** — pure Foundation, no isolation, `[Float]` out. Fully testable headless.
- **`RendererPort`** (`PrismRush/Render/RendererPort.swift`, 15 lines) — the seam that makes the
  headless core possible. **It has no test double and no test of its own.**

---

## Zero coverage

Complete list, derived from cross-referencing every top-level type declared under `PrismRush/`
against every identifier appearing anywhere in `Tests/**` + `UITests/**`.
**⚑ = load-bearing** (a defect here reaches a player or reviewer).

### A. Entire directories with no unit test whatsoever

| area | files | lines | note |
|---|---|---|---|
| `PrismRush/Render/**` | 16 | 4,758 | ⚑ Only `CharacterProportions` (inside `ProceduralMesh.swift`) has pins, and only in the iOS bundle |
| `PrismRush/UI/**` | 26 | 8,688 | ⚑ Reachable only via the 11 XCUITests, which touch maybe 8 of the 26 files |
| `PrismRush/Services/**` | 4 | 308 | ⚑ `GameCenterService`, `AccountService`, `Haptics`, `Keychain`. **`Keychain` is security-sensitive and has zero tests of any kind** |
| `PrismRush/IAP/**` | 2 | 290 | ⚑ `IAPCatalog`, `IAPManager`. `EconomyTests` covers the *profile side* of grants (`applyOncePerTransaction`) but never `IAPManager` itself |
| `PrismRush/App/**` | 2 | 32 | `PrismRushApp`, `RootView` — trivial, but the entry point is untested |
| `Audio/Music.swift` + `Audio/SynthEngine.swift` | 2 | ~310 | ⚑ Buffer cache, ducking, `AVAudioSession` category, interruption recovery, world crossfade — all uncovered |

### B. Named production types never referenced by any test file

**Rendering / worlds (19):** `AshfallSky`, `BespokeSky`, `BloomfallSky`, `BorealisSky`,
`DatastreamSky`, `EventideSky`, `OrbitalSky`, `SingularitySky`, `TempestSky`, `TidalSky`, `WorldSky`,
`WorldDecor`, `WorldPalette`, `WorldPreviewCanvas`, `EntityPools`, `EntityState`, `ParticleSystem`,
`RendererPort` ⚑, `ShakeEffect`

**UI screens / components (24):** `CharacterSelectView`, `CharacterHeroStage`, `EffectsOverlay`,
`GameOverView`, `HUDView`, `HowToPlayView`, `LevelSelectView`, `LoadoutStrip`, `LogoMark`, `MenuView`,
`MetaScreenScaffold`, `MissionsView`, `MysteryBoxView`, `PackRewardBurst`, `PauseOverlay`,
`PowerUpGlyph`, `PowerUpsView`, `ProfileView`, `RewardsBar`, `SettingsView`, `SplashView`,
`CoinGlyph`, `NeonButtonStyle`, `NeonCard`

**App / services / audio (8):** `PrismRushApp`, `RootView`, `AccountService` ⚑, `GameCenterService` ⚑,
`Haptics`, `Keychain` ⚑, `Music`, `GameModel` ⚑ *(the app's hub object)*

**Enums / value types never named in a test (9):** `GameMode`, `NearMissKind`, `PowerUpKind`,
`IAPKind`, `IAPProduct`, `PackBadge`, `StoreState`, `ConsumableGrant`, `CoinSpendItem`
— caveat: `NearMissKind`, `PackBadge`, `StoreState`, `ConsumableGrant`, `CoinSpendItem` are exercised
*structurally* (tests match on `.close`, `.bestValue`, `.ready`, `.coins(200)`,
`ShopConsumables.packs`) but no test enumerates all their cases. `GameMode`, `PowerUpKind`,
`IAPKind`, `IAPProduct`, `GameModel` are genuinely untouched.

### C. Untested behaviour inside *tested* types

- ⚑ **`ProfileStore` persistence.** `load(localKey:cloud:)`, the write path, `persistentDeviceKey()`,
  and the `NSUbiquitousKeyValueStore.didChangeExternallyNotification` observer
  (`PrismRush/Meta/ProfileStore.swift` lines 19-21, 34-47, 623-626, 691-709) are executed by **zero
  tests on any platform** — every test uses `init(testing:)`. The Linux CI job exercises the `#else`
  branch's *declaration*; the macOS run exercises the Darwin branch's declaration. Neither runs the
  behaviour. Note also that `init(testing:)` still evaluates the stored-property default
  `private let cloud = NSUbiquitousKeyValueStore.default` (`:20`) on Darwin — inert (no observer,
  `persisting == false`) but it does instantiate the real KVS object during `swift test`.
- ⚑ **`GameCore.movingTall` collision path** — nothing tests it directly; only the solvability bot
  walks it.
- **`GameCore.advance` frame pacing** under real display-link jitter, and `onFX` delivery ordering.
- **`Patterns` indices 0–8 content** — only RNG consumption and negative assertions about
  ring/pad/split/moving presence.

### D. Known-defective behaviour with no test pinning it (from the other surveys)

| what | where | why no test catches it |
|---|---|---|
| ⚑ Guaranteed power-up cadence is player-dependent | `PrismRush/Core/GameCore.swift:320-334` (`freeLaneNear`) + `:410-411` (shield-absorb removes an obstacle) | The absorb path mutates `activeObstacles` based on player behaviour, flipping a cadence mark and shifting the *kind* of every subsequent cadence pickup. It consumes **no RNG**, so every determinism/golden test still passes while the daily track stops being identical between players |
| `capGem = 72` overflow silently truncates coin trails | `PrismRush/Core/GameCore.swift:667`, `PrismRush/Core/Tuning.swift:84` | No counter, no FX, no test. `apply` just returns without placing |
| `crossingSpeed` predicts ramp speed, player crosses at `effectiveSpeed` | `PrismRush/Core/Patterns.swift:33-35, 46-58, 142-144` | `ArcCollectionTests` tests ≥5/7 under chrono and calls that a pass; the systematic placement error is inside tolerance |
| `featuredPool ⊄ SkinCatalog.all` would render Prism as a 0-coin "TODAY'S FEATURE" | `PrismRush/UI/ShopView.swift:206-220`, `PrismRush/Meta/SkinCatalog.swift:267` | Nothing pins `featuredPool ⊆ SkinCatalog.all` |
| `ProcessInfo.systemUptime` is a required-reason API missing from the privacy manifest | `PrismRush/Audio/SynthEngine.swift:150` vs `PrismRush/Support/PrivacyInfo.xcprivacy:7-12` | ⚑ No test or CI check reads the privacy manifest. Expected symptom: `ITMS-91053` on upload |
| Meta-layer randomness is unseeded in production paths | `ProfileStore.openMysteryBox` uses `Double.random` (`:137`), `openFreeChest` uses `Int.random(in: 60...220)` (`:341`) | Both are injectable (`roll:`, `reward:`) and tests inject; the *production* path is non-reproducible. Outside `Core/`, so iron rule 2 is not violated |

---

## Tests that can pass vacuously or trap

Six real hazards, all verified at the line numbers given.

### 1. Guard-and-return that skips the assertion — `Tests/CoreTests/GameplayTests.swift:216`

```swift
core.debugForceDie()
core.tick(Tuning.tickDt)
guard let released = core.activeGems.first else { return }   // (not collected mid-setup)
```

If the gem was collected during setup, the test **returns green having asserted nothing** about
either behaviour it exists to pin (magnet stops at death; `fading` is sticky). Contrast line 209 in
the same method, which correctly does `else { return XCTFail("gem vanished") }`. Fix: make line 216
match line 209. **SEV3.**

### 2. Assertion accumulated outside the loop — `Tests/CoreTests/PowerUpTests.swift:99-113`

```swift
var chronos = 0
for s in 0..<10 {
    ...
    XCTAssertEqual(core.mode, .play, "seed \(seed) must stay solvable with chrono in play")
}
XCTAssertGreaterThan(chronos, 0, "at least one chrono must be collected across the seeds")
```

Nine of ten seeds could stop spawning chrono entirely and the test stays green — one collection
anywhere satisfies it. The per-seed assertion inside the loop only checks survival, which
`SolvabilityBotTests` already covers far more thoroughly. This is a 0.216 s test that pins almost
nothing. **SEV3.**

### 3. Unchecked subscript that **traps** instead of failing — `Tests/CoreTests/ArcCollectionTests.swift:27`

```swift
var cmds: [SpawnCmd] = []
Patterns.debugGemArc(d, lane: 1, out: &cmds)
guard case let .gem(d0, _, _) = cmds[0] else { XCTFail("arc emitted no gem 0"); return 0 }
```

The `XCTFail` is a decoy: `cmds[0]` is evaluated **before** the pattern match. If `debugGemArc` ever
emits nothing, this is an index-out-of-range trap that **kills the whole test process** — every
subsequent suite in the run disappears and you get a crash log, not a failure report. Fix:
`guard let first = cmds.first, case let .gem(d0, _, _) = first else { … }`. **SEV3.**

### 4. Unbounded `while` loop — `Tests/CoreTests/RingTests.swift:63`

```swift
while core.laneIndex != ringLane { core.changeLane(ringLane > core.laneIndex ? 1 : -1) }
```

No tick, no iteration bound. It relies on `changeLane` updating `laneIndex` **synchronously**. If
lane changes ever become tick-deferred (a plausible feel change), this spins forever. Neither
workflow sets `timeout-minutes`, so a CI hang burns the full 6-hour runner slot. **SEV3 for
correctness, SEV2 for CI cost when it fires.**

### 5. Tolerance-based determinism assertion — `Tests/CoreTests/FlowTests.swift:123`

```swift
XCTAssertEqual(a1.obstacles[i].d, b.obstacles[i].d, accuracy: 0.6,
               "obstacle #\(i) drifted beyond fill-tick jitter")
```

The surrounding test (`testDeterminismAndPatternStreamIsolation`) proves *exact* input-isolation of
the RNG stream — lines 120 and 122 compare `kind` and `lane` with no tolerance. This one field gets a
0.6-unit slop justified as "fill-tick jitter", over ≥60 obstacles. **A real determinism drift smaller
than 0.6 units passes.** **SEV3.**

### 6. False-negative audio assertion — `Tests/CoreTests/SynthTests.swift:67-71`

```swift
func testDeathSweepNoiseSwells() {
    // The noise layer swells instead of decaying — the tail must still be clearly audible.
    let s = Synth.deathSweep()
    XCTAssertGreaterThan(peak(Array(s.suffix(s.count / 6))), 0.015, "deathSweep dies too early")
}
```

The `swell:` parameter it is guarding is **dead**: `PrismRush/Audio/Synth.swift:37` declares
`swell: Bool = false` and the render loop at `:49-50` unconditionally applies `(1 - frac)`, never
referencing `swell`. Four SFX pass `swell: true` (`Synth.swift:181` `deathSweep`, `:195`
`frenzyStart`, `:227` `boostStart`, `:255` `flowSurgeChime`) and all four decay instead of building.
The test still passes because the linear decay at frac 0.833 yields ≈ 0.24 × 0.167 ≈ 0.040 > 0.015.
**The test name asserts a behaviour that does not exist. SEV2 feel + SEV3 test-integrity.**

### Also worth knowing

`Tests/CoreTests/CollisionTests.swift:14-18` — `testPlayerBoundsSlidingClearsLow` asserts the
**opposite** of its name (`XCTAssertLessThan(b.bottom, Tuning.lowKillTop)`, i.e. a slide does *not*
clear a low; the inline comment on line 16 confirms). Not a defect, but grepping the symbol name for
"does a slide clear a low?" gives you the wrong answer.

---

## Environment-dependent, slow, or flaky

### Slow (measured)

| test | time | note |
|---|---|---|
| `SolvabilityBotTests.testGreedyBotSurvives200Seeds` | 4.263 s | 200 seeds × 6,000 m |
| `SolvabilityBotTests.testGreedyBotSurvivesDeepRuns` | 2.549 s | 64 seeds × 12,000 m |
| — together | 6.81 s of a 7.28 s suite | everything else is sub-0.25 s |
| `InteractionUITests` ×3 | 25 s timeout each | `:41`, `:92`, `:168` — wait for the `PR_DEMO` run to die. Worst case that is most of the UI suite's runtime |

### Platform / environment dependent

| what | dependency |
|---|---|
| `CharacterParityTests` (3) | `#if canImport(UIKit)` → **iOS Simulator only**. Absent on macOS `swift test` and on Linux |
| `WorldPaletteTests` (4) | outside `Tests/CoreTests/` → **Xcode bundle only**, never on Linux |
| `EconomyTests` daily/chest | `date(_:_:_:_:)` (`:7-10`) builds dates in **`Calendar.current`** — machine timezone. Self-consistent with the implementation (`ProfileStore.swift:301-309` also uses `Calendar.current`), but `MissionsTests.utc` / `ProgressionTests.utc` build **UTC** dates and mission/challenge day keys use `ProfileStore.daysSinceEpoch` (UTC, `:353-359`). Mixing the two in one assertion is one timezone away from confusing |
| `ProfileStore` on Linux vs Darwin | `#if canImport(Darwin)` split; the Linux CI job and your local macOS run exercise **different initialiser paths**. `init(testing:)` sidesteps both, so this is currently latent |
| `ios-build.yml` | brew installing xcodegen; a runner Xcode new enough for Swift 6 strict concurrency; **a simulator literally named "iPhone 16"** (`:63`) |
| `build.sh` / `ci.sh` | default `iPhone 17 Pro` / iOS `26.5`, overridable via `PR_SIM_NAME` / `PR_SIM_OS` |
| `qa.sh` / `screenshots.sh` | **hardcoded UDIDs**, do **not** honour `PR_SIM_NAME`/`PR_SIM_OS`. `Tools/qa.sh:7` → `10C15FE0-3D9A-40D5-9E45-C0702E906DF3` (override `PR_SIM_UDID`); `Tools/screenshots.sh:22` → `52DF5467-1BF8-40B2-BD4D-8EEECA9062DF` (override `PR_SIM_69_UDID`). On any other machine, `simctl boot` fails silently (`|| true`) and the next `simctl install` aborts under `set -e` with a raw simctl error |
| duplicate simulator names | two `iPhone 17 Pro` and two `iPhone 17 Pro Max` exist on this machine. Name-based selection is non-deterministic between them |

### Structurally flaky-prone (no observed failures today)

- `FlowTests.testDeterminismAndPatternStreamIsolation` — 0.6-unit tolerance (trap 5).
- `PowerUpTests.testBotCollectsChronoDuringProceduralRuns` — depends on the seeded spawn stream
  actually producing a chrono in ≤6,000 m across 10 seeds; a spawner tweak makes it probabilistic
  without changing anything it claims to guard (trap 2).
- `GameplayTests.testMagnetStopsAtDeathAndFadingIsSticky` — silently no-ops rather than failing
  (trap 1).
- `RingTests` — unbounded loop (trap 4).
- Every XCUITest using `waitForNonExistence` against an animation (the CLAIM ALL cascade at
  ~80 ms/beat, the ~1.1 s celebration auto-dismiss) is timing-coupled to UI animation durations.

---

## The XCUITest gap

**11 XCUITests, all in `UITests/InteractionUITests.swift`.** The file's own docstring (`:3-4`) says
it exists because "screenshots proved rendering, not behavior".

**CI never runs them.** `.github/workflows/ios-build.yml:64` passes `-only-testing:PrismRushTests`.
They are compiled (the `build-for-testing` step at `:48-54` builds the scheme's test targets) but
executed **only** by a human running `./Tools/ci.sh`. The 11 behavioural tests written specifically to
catch shipped bugs have no automated enforcement. **SEV2.**

`setUp` sets `continueAfterFailure = false` (`:9`), so the **first** failing assertion aborts that
test method. A broken menu reads as one failure, not ten.

### What the 11 drive

| test | line | env fixture | drives |
|---|---|---|---|
| `testBackToMenuFromGameOver` | 38 | `PR_DEMO` | game over → BACK TO MENU returns to the menu |
| `testEquipSkinUpdatesImmediately` | 49 | `PR_DEMOPROFILE` | skin focus → stage → commit reflects as equipped without reopening |
| `testPauseResumeAndQuit` | 74 | `PR_AUTOPLAY` | pause freezes, resume dismisses, quit returns home |
| `testReviveContinuesRun` | 89 | `PR_DEMO` + `PR_DEMOPROFILE` | game over → CONTINUE resumes play |
| `testDailyAndChestRewards` | 100 | `PR_DEMOPROFILE` | rewards rail: daily claim → chest open → cooldown → mini-sheet |
| `testHubNavigation` | 124 | `PR_DEMOPROFILE` | Worlds / Characters / Shop / Profile + Profile→gear→Settings |
| `testHeroStageShowsLockedRequirement` | 152 | `PR_DEMOPROFILE` | locked-skin requirement copy on the stage button |
| `testGameOverShowsXPBar` | 166 | `PR_DEMO` | game over shows an XP line (proves `applyRunSummary` ran) |
| `testWorldsBuyFlowPurchaseDenyAndGetCoins` | 179 | `PR_DEMOPROFILE` | affordable buy, strip advance, unaffordable deny, GET COINS → Shop |
| `testFirstRunGateCoversEntrancesAndCancelNeverStarts` | 222 | `PR_FIRSTRUN` | tutorial gate on three entrances; ✕ never starts a run |
| `testMissionsClaimAllCascadeAndSingleClaim` | 261 | `PR_DEMOPROFILE` | CLAIM ALL cascade + single claim |

### Real user flows with **zero** UI coverage

- ⚑ **Actual gameplay input.** Not one test taps or swipes to jump, slide, or change lane. Every
  "in play" state is reached via `PR_AUTOPLAY` / `PR_DEMO` — i.e. the bot. The gesture recognisers,
  the HUD's response to input, and the on-screen action buttons are untested end-to-end.
- ⚑ **StoreKit purchase.** Nothing buys a coin pack, the premium skin, or restores purchases —
  despite `Products.storekit` being wired into the scheme's **`run`** action (`project.yml:72`), not
  its `test` action. The whole `IAP/` layer is behaviourally unverified.
- **Settings.** Reached and closed in `testHubNavigation`; no test toggles music/SFX volume or
  haptics, or verifies any setting persists.
- **Shop.** Opened and closed. Nothing tests pack badges rendering, `MysteryBoxView`, consumable
  packs, the featured-skin rotation, or the offline / not-configured states `StoreAvailability`
  models.
- **Loadout / pre-run consumables.** `LoadoutStrip`, `PowerUpsView`, Head Start, manual slow-mo /
  overdrive / shield — unit-tested in `PowerUpTests`, unreachable in a UI test (they need a real run).
- **Daily Challenge actually played.** `testFirstRunGate…` taps `railDaily` only to cancel the
  tutorial. No test completes a challenge run or checks the board.
- ⚑ **Game Center / Sign in with Apple / Keychain.** `GameCenterService`, `AccountService`,
  `Keychain` — no coverage of any kind, unit or UI.
- ⚑ **Offline / error states.** **Decree 3** ("no broken-looking states for expected situations")
  has no automated proof: pre-launch store, empty leaderboards, locked content are all untested.
- **Reduce Motion / VoiceOver / Dynamic Type / rotation.** Nothing.
- **Audio.** `SynthEngine`, `Music`, ducking, session-interruption recovery: unit tests cover only
  the pure DSP buffers.
- ⚑ **Multi-launch persistence.** No test relaunches the app to prove a save round-tripped through
  UserDefaults. Every UITest starts from a `PR_DEMOPROFILE` / `PR_FIRSTRUN` seeded profile.

### Structural weaknesses in the 11 that exist

- They assert against **production `PR_*` fixtures**, not a real player. `PR_DEMOPROFILE`
  (`PrismRush/UI/GameView.swift:146`) pins coins / reach / mission progress, so
  `testWorldsBuyFlowPurchaseDenyAndGetCoins` and `testMissionsClaimAllCascadeAndSingleClaim` are
  asserting against numbers baked into `GameView`.
- `:64-67` — `testEquipSkinUpdatesImmediately` polls with `Thread.sleep(forTimeInterval: 0.2)` × 25.
  It is the only raw sleep in the file; every other wait is label/existence-predicate based.
- `:202` — a tap is retried up to 15 times because taps during a celebration animation are
  swallowed. A convergence loop standing in for a real synchronisation point.
- `:284` — `for _ in 0..<10 where !single.isHittable { app.swipeUp() }`: scroll-until-visible with no
  assertion that the scroll made progress.

---

## The `Tools/` scripts

### `Tools/build.sh` (18 lines)

- **Does:** `cd` repo root → `xcodegen generate --quiet` → `xcodebuild -project PrismRush.xcodeproj
  -scheme PrismRush -destination "platform=iOS Simulator,name=$PR_SIM_NAME,OS=$PR_SIM_OS"
  -derivedDataPath .dd CODE_SIGNING_ALLOWED=NO -quiet build` → prints `BUILD OK`.
- **Time:** ~1–3 min clean, seconds incremental.
- **Prereqs:** `xcodegen` on PATH; Xcode with the named device **and** runtime.
- **Failure modes:** missing xcodegen → command-not-found; nonexistent device/OS pair → "Unable to
  find a destination"; **duplicate device names → xcodebuild picks one non-deterministically**;
  `set -euo pipefail` aborts on anything, but `-quiet` hides most diagnostic context (drop `-quiet`
  when debugging).
- **Known defect:** writes `-derivedDataPath .dd` **inside the repo**, which lives under `~/Desktop`
  (iCloud Drive on this machine). The repo's own memory note (`icloud-desktop-codesign-detritus`)
  says device/archive builds need derived data *outside* `~/Desktop`; this does the opposite. Harmless
  for simulator builds, a trap for archives. **SEV3.**

### `Tools/ci.sh` (47 lines)

- **Does:** (a) `xcodegen generate` → (b) `./Tools/build.sh` → (c) `xcodebuild test` on the whole
  scheme → `CI GREEN`.
- **Time:** several minutes (build + 185 unit + 11 UI, incl. three 25 s waits).
- **Prereqs:** `build.sh`'s, plus a bootable simulator.
- **Known defects:**
  1. `:9-10` header claims "174 tests (163 unit + 11 XCUITest) at v1.4.3". Real: **196**. A truncated
     run (one target failing to build) that produced ~174 tests would look *correct* to a session
     that trusts this line. **SEV3.**
  2. It regenerates the Xcode project **twice** — step (a) runs `xcodegen generate`, then
     `build.sh:10` runs `xcodegen generate --quiet` again. Wasteful, not harmful.
  3. `gatherCoverageData: true` is set on the scheme (`project.yml:77`) but **nothing consumes it**.
     No workflow, script, or gate reads the coverage report. The global 80 %-coverage rule is
     completely unenforced here.

### `Tools/qa.sh` (23 lines)

- **Does:** boot → `open -a Simulator` → `build.sh` → install → launch → `sleep` → screenshot into
  `reports/shots/shot_<epoch>.png`.
- **Time:** build time + ~10 s.
- **Prereqs:** the UDID at `:7` must exist; `.dd/Build/Products/Debug-iphonesimulator/PrismRush.app`
  (hardcoded at `:15`) must exist.
- **Known defects:** hardcoded machine-specific UDID with no name fallback (`PR_SIM_UDID` exists but
  `PR_SIM_NAME` does not apply here); `boot` errors swallowed by `|| true` so the real failure surfaces
  later as a raw `simctl install` error; the app path is hardcoded to `Debug-iphonesimulator` so a
  Release build breaks it; **it does not set `PR_SKIP_SPLASH`**, so the 4 s default sleep can capture
  the splash; no verification the launch succeeded. **It has no assertions — it cannot "pass".**

### `Tools/screenshots.sh` (131 lines)

- **Does:** ensures `Store/screenshots/`, errors if the `.app` is missing, greps
  `simctl list devices available` for a 6.5″-class device (11 Pro Max / XS Max / 8 Plus / 7 Plus /
  6s Plus) and *warns* rather than failing if none, then per device: boot → `bootstatus -b` →
  install → launch → for each of 6 named states print a guidance line, `sleep $SHOT_DELAY`,
  `simctl io screenshot` into `Store/screenshots/<label>/<name>.png`.
- **Time:** `6 × SHOT_DELAY` (default 3 s) ≈ 18 s per device + boot/install.
- **Prereqs:** a prior `./Tools/build.sh`; the 6.9″ UDID at `:22` (`PR_SIM_69_UDID` override).
- **Known defect — this is the App Store submission path and it does not work unattended. SEV2.**
  The six named states (`01_menu`, `02_world1` … `06_gameover`) require gameplay, but the script only
  sleeps and shoots (`:103-115`). Run unattended it writes **six identical menu frames** — exactly the
  "screenshot of an empty dashboard" the global README standard bans. Its own header (`:9-13`) still
  says "until the game is playable (Phase 8)"; the game shipped v1.6. It also does not set
  `PR_SKIP_SPLASH`, so shot 1 may be the splash. **Fix direction:** drive it with the `PR_*` hooks
  (`PR_SKIP_SPLASH`, `PR_WORLD`, `PR_AUTOPLAY`, `PR_DEMO`, `PR_SCREEN`, `PR_FOCUS`) rather than sleeps.

### `Tools/gen_icon.swift` (307 lines)

- **Does:** standalone `#!/usr/bin/env swift` script. Builds a 1024² `CGContext` with
  `CGImageAlphaInfo.noneSkipFirst` (no alpha — App Store requirement), draws the gradient, glow and
  character, writes the PNG via ImageIO, then — **only if `outPath` is exactly `Store/icon_1024.png`**
  (`:298`) — syncs the asset-catalog copy.
- **Time:** ~1 s. **Prereqs:** macOS with CoreGraphics/ImageIO. No Xcode project, no UIKit.
- **Known defect — destructive-then-verify ordering. SEV2 (SEV1 if unnoticed before a build):**

  ```swift
  // Tools/gen_icon.swift:299-306
  try? FileManager.default.removeItem(atPath: catalogPath)
  do { try FileManager.default.copyItem(atPath: outPath, toPath: catalogPath) }
  catch { …exit(1) }
  ```

  The `removeItem` is unconditional and its error is swallowed. If `copyItem` then throws (disk full,
  permissions, iCloud-Desktop eviction), the tool exits 1 having **already deleted the only app icon
  in the asset catalog**, and the app builds without an icon. Recoverable via git.
- **Second defect:** passing any custom output path silently skips the sync, letting `Store/` and the
  catalog diverge with no warning.

### `Tools/render_sfx.swift` (48 lines)

- **Does:** writes 44.1 kHz mono 16-bit WAVs (hand-rolled RIFF header, clamp to ±1, `Int16` scale).
  Renders 9 SFX (`gem0`, `gem10`, `jump`, `slide`, `crash`, `chime`, `worldSweep`, `close`,
  `startChime`) and 16-beat bars for worlds 1–3.
- **Run:** `swiftc PrismRush/Audio/Synth.swift Tools/render_sfx.swift -o /tmp/render_sfx &&
  /tmp/render_sfx reports/audio`. **Not part of any build, test, or CI path.**
- **Constraint:** it is compiled against `Synth.swift` **only**, so `Synth.swift` must never gain a
  dependency on anything else in the app or this one-liner stops working.
- **Known defects:** `try? data.write` swallows write errors — a failed write still prints a success
  line. And it is badly stale: `SynthTests` exercises ~28 SFX cases and **24** music worlds
  (`SynthTests.swift:136-148`), so the audio-audit tool cannot hear roughly two-thirds of the shipping
  sound design, including every v1.3/v1.5/v1.6 addition (`ringPass`, `boostStart`, `flowSurge`,
  `levelUp`, `sneakersChime`, …). **SEV3.**

### CI workflows

| file | runs | notes |
|---|---|---|
| `.github/workflows/core-tests.yml` (19 lines) | `swift test -c release` in `swift:6.0-noble` on `ubuntu-24.04`; push-to-main + all PRs | 187 tests. The one always-reliable gate |
| `.github/workflows/ios-build.yml` (65 lines) | `macos-15`; newest Xcode → brew xcodegen → generate → `build-for-testing` (generic sim) → `test-without-building -only-testing:PrismRushTests` on `iPhone 16, OS=latest` | See defects below |

**`ios-build.yml` defects:**
1. `:56-57` — the comment says the unit-test step is "**Best-effort**", but the step has **no
   `continue-on-error: true`**. `-destination '…name=iPhone 16,OS=latest'` (`:63`) hard-fails the
   whole job the day GitHub's `macos-15` image stops shipping a device literally named "iPhone 16".
   Intent and behaviour disagree. **SEV3 (SEV2 when it fires — every PR goes red for infra reasons).**
2. `:64` — `-only-testing:PrismRushTests` means **CI never runs the 11 XCUITests.** **SEV2.**
3. **Neither workflow sets `timeout-minutes`**, so a hung test (trap 4) burns a full 6-hour runner
   slot. **SEV3.**
4. **No CI job runs a linter, a formatter, or a coverage gate**, despite `gatherCoverageData: true`
   and the global 80 %-coverage rule.

---

## Definition of Done — the practical version

`docs/agent/01_RULES.md` §4 in concrete commands for this repo, in the order to run them. Paste the
**real output** of each into the session log — §4 is explicit: *no output, no credit.*

### Step 0 — decide which gates apply to your change

| what you touched | required gates |
|---|---|
| `Core/`, or any of the 7 SPM `Meta/` files, or `Audio/Synth.swift` | 1, 2, 4, 5 (skip 3 unless the change is player-visible) |
| `Render/`, `UI/`, `App/`, `Services/`, `IAP/`, `Audio/Music.swift`, `Audio/SynthEngine.swift` | **1 is not enough — `swift test` does not compile these at all.** Run 2, 3, 4, 5 |
| `Package.swift`, `project.yml`, `Tools/`, `.github/` | whatever the change affects, plus re-read this file |

### Step 1 — deterministic suite (always)

```bash
cd <repo root>
swift test -c release
```

Expected: `Executed 187 tests, with 0 failures (0 unexpected) in ~24 seconds`, then the harmless
`✔ Test run with 0 tests in 0 suites passed` from the swift-testing runner. **Duration ~9 s warm,
~30 s if it recompiles (S-004: ~24 s of that is now XCTest itself — `DifficultyCurveTests` plays
64 seeded Autopilot runs).** If the count is not 187, something changed structurally — find out what
before reading the failures.

### Step 2 — the app must compile

```bash
./Tools/build.sh
```

Expected: `BUILD OK`. **Duration ~1–3 min clean, seconds incremental.** Drop `-quiet` from
`Tools/build.sh:16` temporarily if you need to read a diagnostic. Watch for **new** warnings — §4
forbids silence on them; pre-existing warnings get a backlog item, not a fix.

### Step 3 — full scheme, including the XCUITests

```bash
./Tools/ci.sh
```

Expected: three banners then `CI GREEN`, having executed **196** tests (185 unit + 11 XCUITest).
**Duration several minutes.** Ignore the `174 tests` line in the script header — it is stale
(`Tools/ci.sh:9-10`). This is the **only** way the 11 XCUITests ever run; CI does not run them.

### Step 4 — look at it, if the change is visible

```bash
./Tools/qa.sh          # or: PR_SKIP_SPLASH via SIMCTL_CHILD_* if you want the hub, not the splash
```

Then **open the PNG it prints and actually read it.** `qa.sh` has no assertions; a zero exit code
proves nothing about what is on screen. Do not run this while step 3 is running — concurrent
`simctl install` on the same device produces a false `TEST FAILED`.

For a specific state, launch by hand instead:

```bash
SIMCTL_CHILD_PR_SKIP_SPLASH=1 SIMCTL_CHILD_PR_WORLD=4 SIMCTL_CHILD_PR_AUTOPLAY=1 \
  xcrun simctl launch booted com.rayancheca.prismrush
```

### Step 5 — the item's own verification, then bookkeeping

- Run the exact command named on the backlog item's `Verification:` line. That is not optional and it
  is not substituted by steps 1–4.
- Set the backlog status to `DONE(S-NNN)`.
- If it **cannot** be verified here (no device, needs App Store Connect, needs a real purchase), mark
  it `VERIFY-PENDING(S-NNN)` and add a line to `02_STATE.md` under "Needs Rayan on a device". Never
  `DONE` on reasoning alone.

### Forbidden ways to make the gate pass

From §4, restated because they are all one keystroke away in this repo: deleting or skipping a test,
lowering a threshold (e.g. widening `FlowTests`' 0.6 accuracy, or `SynthTests`' 0.015 peak floor),
adding `@unchecked Sendable`, adding `MainActor.assumeIsolated` to silence an isolation error,
wrapping in `try?` to swallow, `#if DEBUG`-ing a failure away, or suppressing a warning. Each of those
is a **finding to log**, never a fix to apply.

Two repo-specific additions:

- **Never edit a `DailyChallengeTests` golden to make a failure go away.**
  `Tests/CoreTests/DailyChallengeTests.swift:10-17` is explicit: a golden change is a
  `DailyChallenge.layoutVersion` **bump**, not an edit here. Bump the version, move the old value into
  the explicit-version list, promote the pre-armed pin at `:23-24`, and pre-arm the next one.
- **Never `#if DEBUG` a `debug*` hook.** `GameCore.debugForceDie` / `debugClearTrack` / `debugSpawn` /
  `debugActivateSuperSneakers` and `Patterns.debugGemArc` are **unconditionally compiled** (verified:
  no `#if DEBUG` anywhere in `Core/` or `Meta/`) because the suite runs `-c release`. Gating them
  breaks the entire suite.
