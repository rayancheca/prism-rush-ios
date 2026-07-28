# HANDOFF → Session 004

## Paste this to start the next session

```
You are session 004 of a long-running program to finish and ship Prism Rush, a neon three-lane
endless runner for iPhone (Swift 6, SwiftUI, RealityKit, zero dependencies, zero binary assets).

Read docs/agent/01_RULES.md, then docs/agent/02_STATE.md, then docs/agent/05_GAME_DESIGN.md
(§3, §4 and §7 especially), then docs/agent/04_DECISIONS.md D-005 through D-008, then this file.

IMPORTANT — the rules changed. Sessions 001-003 were read-only by a process rule that Rayan has
now removed (D-005). You may and should change code. 01_RULES.md is split into judgment
(advisory — use your head) and nine invariants (damage prevention). Rayan's standing instruction
is "never be limited by arbitrary rules, just work however you think is best." Do not reinstate
ceremony. Do not ask permission to fix something you can verify.

Direction: App Store submission IS the goal, but timing is open and Rayan wants the app POLISHED
before publishing. Design and feel outrank compliance right now.

This session you are writing code. Your goal is PR-0400 + PR-0414 — the two spawn-path changes —
landed together in a single DailyChallenge.layoutVersion bump, because doing them separately
means two bumps and two golden repins for no benefit.

PR-0400 (SEV1): the difficulty curve ends at 3,200 m and the game never changes again. The last
new pattern unlocks at 1,920 m, speed caps at 3,077 m, gap floors at 3,200 m. Measured on device:
five consecutive 10-second intervals at 33.5-33.7 m/s with a flat score rate. A 4,000 m run and a
40,000 m run are the same run. Give the run loop a second act.

PR-0414 (SEV2): no gem in the 14-pattern catalogue requires entering an unsafe lane, so greed and
survival are the same input and there is no routing decision. Rayan revoked "coins are the path"
(D-006) — his intent was structure, not safety. Price some gems in risk while keeping them in
deliberate, readable formations.

Both changes touch the spawn path, so INVARIANT 2 binds you: keep SolvabilityBotTests green
(200 seeds x 6,000 m plus the 12,000 m soak) AND bump DailyChallenge.layoutVersion and repin the
DailyChallengeTests goldens. One extra rng.unit() anywhere in the spawn path silently rerolls
every seeded run for every player.

Build and RUN the app before you claim anything works — that rule stays, and it is three for
three at catching things static reading missed.

If you finish those, the stretch items are PR-0445 (attract-track z-order, ~20 min, decided in
D-008) and PR-0254 + PR-0307 (revived runs count for missions and XP, and are not
leaderboard-eligible — decided in D-007).

Report back in three lines.
```

**This file's absolute path:**
`/Users/rayankarimcheca/Desktop/ClaudeProjects/projects/prism-rush-ios/.claude/worktrees/prism-rush-design-audit-562d27/HANDOFF.md`

---

## Goal

**Give the run loop a second act past 3,200 m (PR-0400), and price some gems in risk (PR-0414), in
one `layoutVersion` bump.**

These are the two changes that convert Prism Rush from a game that is technically excellent for two
minutes into one that keeps asking something of the player. Everything else in the 256-item backlog
is smaller than these two.

## Why these two, together

Both modify the spawn path. Invariant 2 says any such change must keep the solvability bot green
*and* bump `DailyChallenge.layoutVersion` with the `DailyChallengeTests` goldens repinned. Doing
them in one session means **one** bump and **one** repin. Doing them separately means two of each,
for zero benefit. If you can only land one, land PR-0400 — but structure the change so PR-0414 can
follow without a second bump if you can.

## PR-0400 — what's actually wrong, with the numbers

From `Core/Tuning.swift` and `Core/Spawner.swift`:

| Distance | What happens |
|---|---|
| 1,920 m | `Spawner.maxIndex` returns `Patterns.count` — **the last new pattern, ever** |
| 3,077 m | `(33 − 17) / 0.0052` — speed cap reached |
| 3,200 m | `diffFullAt` — `gap` floors at `gapMin` 5 |
| 3,200 m → ∞ | **nothing changes** |

Measured on device (autoplay, HUD read every 10 s): `3,315→3,652 m` 33.7 m/s · `3,652→3,989` 33.7 ·
`3,989→4,324` 33.5 · `4,324→4,660` 33.6 · `4,660→4,995` 33.5 · `4,995→5,331` 33.6. Score rate flat
too: 5,874 pts / 337 m at 3.6 km vs 6,171 / 336 m at 5.0 km.

**The seam already exists.** `Spawner.maxIndex(forDistance:)` is a five-tier prefix ladder gated on
distance. It is the natural place to add a sixth tier, or a second axis.

Options, roughly in order of how much I'd trust them:

1. **A second escalation axis past 3,200 m** — e.g. gap continues to tighten on a slower curve, or
   pattern *density within* a pattern rises. Cheapest to reason about, no new art, no new entity.
2. **Pattern weighting by depth** — the catalogue stays 14, but the mix shifts toward the demanding
   patterns past 3,200 m rather than staying uniform. Also cheap, and it makes the existing content
   do more work.
3. **A sixth tier with one genuinely new entity.** Most player-visible, most expensive, highest
   risk to the bot.

Whatever you pick, the acceptance test is empirical, not a code review: **re-run the autoplay HUD
capture and show a tail that is not flat.** The capture recipe is below.

⚠️ **Do not simply raise `speedCap`.** One lens found the ceiling is set by what the renderer can
draw legibly (~65 m visible against a 115 m `spawnHorizon`, PR-0435). Faster without more draw
distance means unreactable, which is a worse game, not a harder one.

## PR-0414 — what's actually wrong

`Spawner.swift:53-58` emits a gem breadcrumb into `Spawner.safeEntryLane` before **every** pattern,
and `safeEntryLane` (`:67-84`) is *defined* as the lane with no tall / movingTall / splitBar cover.
A verifier checked all 14 patterns individually: **zero gems in the catalogue require entering an
unsafe lane.**

Rayan revoked the constraint (D-006): *"coins are not the path anymore — i just said that because
coins were spread randomly before so i wanted them structured."* **Structure and safety are
separable.** Keep the deliberate formations; make some of them cost something.

Suggested shape (not binding): keep the breadcrumb leading into the safe lane, but add a *second*,
denser cluster in a lane that is only safe inside a tight window — so the greedy line and the safe
line diverge and the player chooses. Or: a breadcrumb that leaves you well-placed for *this*
pattern and badly placed for the *next* one (routing debt).

Stale comments to fix in the same change: `Spawner.swift:49-52`, `Patterns.swift:128`, `:163`.

## The invariant-2 procedure, concretely

```bash
swift test -c release                 # 178 tests, ~30 s wall — SolvabilityBotTests lives here
```

1. Make the spawn change.
2. Run the bot. If it fails, the content is unfair, not the test wrong.
3. Bump `DailyChallenge.layoutVersion` (a v8 pin is already armed — see `07_ARCHITECTURE.md §4`).
4. Repin the `DailyChallengeTests` goldens.
5. Re-run the full suite AND `./Tools/build.sh`.
6. Re-run the autoplay capture and look at the tail.

## Verification recipe — the autoplay difficulty instrument

This is how session 003 measured the flat tail; reuse it to prove you fixed it.

```bash
./Tools/build.sh
xcrun simctl boot 10C15FE0-3D9A-40D5-9E45-C0702E906DF3
xcrun simctl install 10C15FE0-3D9A-40D5-9E45-C0702E906DF3 .dd/Build/Products/Debug-iphonesimulator/PrismRush.app
SIMCTL_CHILD_PR_AUTOPLAY=1 SIMCTL_CHILD_PR_SKIP_SPLASH=1 xcrun simctl launch 10C15FE0-3D9A-40D5-9E45-C0702E906DF3 com.rayancheca.prismrush
# then screenshot every 10 s for ~4 min into a folder, and crop the HUD band into one strip:
#   PIL: im.crop((0, h*0.06, w, h*0.16)) stacked vertically → read distance + score per frame
```

**Look at the strip.** Derive speed from the *differences* between consecutive captures — not from
the capture labels. Session 003 got caught here: the labels are sampling indices, not elapsed run
time (the first shot fires ~10 s after `simctl launch`, including app start and autoplay warm-up).
Distance-anchored and delta-derived numbers are sound; absolute-time claims are not.

## Stretch, both already decided — implement if there's room

- **PR-0445 (D-008)** — push the attract track behind the hub card layer, or fade it under the lower
  third. On a clean launch the magenta grid crosses the "HEAD START ×1" glyphs and a solid band cuts
  the CHARACTERS / SHOP / WORLDS row; it fails decree 6. `UI/MenuView.swift` z-ordering only, ~20
  min. **Verify with a clean-launch screenshot — a diff does not prove it.**
- **PR-0254 + PR-0307 (D-007)** — a revived run counts fully for missions and XP and is **not**
  leaderboard-eligible, the same rule `usedCheckpoint` runs already follow. Touches
  `recordRunResults` (`UI/GameView.swift:680-792`): keep the per-death delta shape, invariant 5.

## Files you will need

| Path | Why |
|---|---|
| `PrismRush/Core/Spawner.swift` | 85 lines. `maxIndex` (the tier ladder) and `safeEntryLane`. **Both changes live here.** |
| `PrismRush/Core/Patterns.swift` | The 14 patterns. Gem placement per pattern. |
| `PrismRush/Core/Tuning.swift` | 125 lines, every gameplay constant. |
| `PrismRush/Core/DailyChallenge.swift` | `layoutVersion` — must be bumped. |
| `Tests/CoreTests/SolvabilityBotTests.swift` | The fairness gate. Must stay green. |
| `Tests/CoreTests/DailyChallengeTests.swift` | Goldens to repin. |
| `Tests/CoreTests/PatternOrderTests.swift` | Pins pattern order; prefix-index gating is load-bearing. |
| `docs/agent/05_GAME_DESIGN.md` | §3 (curve), §4 (mastery ceiling), §7 (rewards). **Update §3 and §4 when you land this** — the bible is now wrong the moment you change the curve. |
| `docs/agent/07_ARCHITECTURE.md` §3, §4, §11 | Tick model, tier ladder, where-to-look table. |
| `docs/agent/audits/scratch/difficulty.md` + `verify-difficulty.md` | 12 surviving findings on the curve with arithmetic. **Gitignored — read this session or lose it.** |

## Invariants that bind you here

1. **Invariant 2** — bot green + `layoutVersion` bump + goldens repinned. Non-negotiable.
2. **Invariant 1** — all randomness through the seeded `SplitMix64`. No `Double.random`, no `Date()`
   in `Core/`.
3. **Invariant 3** — `Core/` never imports a renderer or UIKit.
4. **Pattern order is load-bearing** — the spawner gates by prefix index; moving walls stay LAST.
5. Don't cheat the gate: no skipped tests, no lowered thresholds, no `try?` swallowing.

## Traps

- **`swift test` green ≠ the app works.** 178 tests in ~8 s, and none of `UI/`, `Render/`, `IAP/`,
  `SynthEngine`, StoreKit or GameKit is compiled. Only `./Tools/build.sh` proves those are live.
- **Every test count written in this repo is wrong.** `CLAUDE.md` says 95, `Tools/ci.sh` says 174.
  Measured truth is **178**. Trust `08_TESTING.md`.
- **Consuming one extra `rng.unit()` in the spawn path changes every seeded run.** This is the
  single easiest way to break this project silently.
- **`PR_FIRSTRUN` does not reset the profile** — session 003 got a hub reading `FURTHEST 15 ·
  11,200M` from it. For a true first launch, `simctl uninstall` then `install`.
- **Launch hooks leave stale `activeSheet` state.** Relaunch clean before concluding anything about
  navigation.
- **The splash never auto-dismisses.** Tap it.
- **`Tools/qa.sh` and `Tools/screenshots.sh` hardcode this machine's UDIDs and fail silently via
  `|| true`** (PR-0050). A green run may mean nothing ran.
- **Never drive the simulator while `xcodebuild test` runs on it** — concurrent installs crash the
  test host and report a false TEST FAILED.
- **`state.md` (58 KB) and `README.md` (35 KB) at the repo root are history, not truth.** Where they
  disagree with `02_STATE.md`, `02_STATE.md` wins.
- **`docs/agent/scratch/` and `docs/agent/audits/scratch/` are gitignored** and hold ~1.5 MB from
  three sessions. Git will not move them between worktrees — `cp -R` by hand if you make a new one.
- **Don't put `./Tools/build.sh` (~2 min) inside a fan-out.** Build once, up front, in the
  background while you read.

## Orientation commands

```bash
git tag pre-s004
cat PrismRush/Core/Spawner.swift
cat PrismRush/Core/Tuning.swift
sed -n '/## 3. The difficulty curve/,/## 5./p' docs/agent/05_GAME_DESIGN.md
swift test -c release 2>&1 | grep -E "Executed [0-9]+ tests"
```

## Current state in one paragraph

Prism Rush is a v1.6, feature-complete, technically strong iPhone game that has never been
submitted to the App Store: 95 Swift files, ~22,300 lines, zero dependencies, zero binary assets but
a generated icon, 178 SPM tests green, and a genuinely deterministic core behind a clean
`RendererPort` seam. Session 001 built the agent memory system and filed 186 items from static
reading. Session 002 produced the Completeness Ledger: 50 of 59 user-facing features are fully
implemented and exactly one — account deletion — is outright absent, but only 13 of 59 clear the
owner's six decrees, and every failure state fails in the same unfinished way while the correct
pattern already exists in two places. Session 003 wrote the design bible (`05_GAME_DESIGN.md`) and
found the structural problem — **the game runs out of design at 3,200 m**, verified in source and
measured on device — then fixed PR-0411 (a false "2× coins, forever" claim on a paid product) and,
on Rayan's instruction, cut the program's process rules down to nine real invariants. Backlog is 256
items, one DONE. Five audits remain unrun but the phase gate is gone: fixes and audits now
interleave, and **polish outranks compliance** until Rayan says otherwise.

## Rayan action items (not yours — surface them, don't try to do them)

1. **App Store Connect still says "Earn 2x coins, forever."** `Products.storekit` is only the local
   sim config. The real product description must be updated in ASC before submission or the shipped
   metadata is still false. This is the residue of PR-0411 and only Rayan can do it.
2. Optional: PR-0411 was fixed by making the *claim* true. The alternative — making the *product*
   true by multiplying the five un-multiplied faucets (daily reward, chest, level grant, mission
   claim, challenge tier) — is a better deal for buyers and a real economy rebalance. His call.

## Open questions for Rayan

Carried until answered. None block session 004.

1. **PR-0040** — the music is a 1.82 s loop for the whole session, pinned to world 0 by his own
   decree (`SynthEngine.swift:133`). Adding long-form structure inside that constraint needs
   sign-off. The other 11 beds exist and are intentionally unreachable.
2. **PR-0052** — is the Daily Challenge a *layout* guarantee or an *identical-experience* guarantee?
3. **PR-0010** — `Store/metadata.md` sells a three-world game; the binary ships twelve families plus
   an infinite evolved cycle. It needs a ledger-checked rewrite before submission (out of scope
   until the compliance pass).
4. Resolved this session and recorded: submission is the goal with open timing and polish first ·
   PR-0411 done · PR-0414 unblocked (D-006) · PR-0254 decided (D-007) · PR-0445 decided (D-008) ·
   process rules cut (D-005).
