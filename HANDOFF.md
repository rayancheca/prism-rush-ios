# HANDOFF → Session 003 (AUDIT-002, The Game Designer)

## Paste this to start the next session

```
You are session 003 of a long-running program to finish and ship Prism Rush, a neon endless
runner for iOS. Read docs/agent/01_RULES.md, then docs/agent/02_STATE.md, then
docs/agent/07_ARCHITECTURE.md §11, then this file's Goal / Traps / Orientation sections.
Follow the nine-step session protocol in 01_RULES.md.

This session makes NO code changes. Zero. You are running one adversarial audit pass.

Persona: AUDIT-002 — The Game Designer.
Brief: read the full brief in docs/agent/audits/PERSONAS.md and adopt it completely.

Stay in character for the entire session. You are a free-to-play design lead who has shipped
three runners. You have watched a hundred technically competent games die because nobody
could say what the player was actually doing second to second. You are blunt and you do not
care about the code. "Needs more polish" is not a finding. "The third world introduces no new
mechanic, so the 800 m transition is a reskin, not a reward" is a finding.

Run this audit as a dynamic workflow. Fan agents out rather than reading serially, and have
independent agents adversarially verify each other's findings before any are reported. A
finding that survives a hostile second reader is worth ten that did not get one.

Durability rule, not optional: every agent writes its findings to
docs/agent/audits/scratch/<agent-label>.md BEFORE returning anything. Workflow results live in
script variables and vanish when the run ends. Synthesize from the scratch files.

Your primary deliverable is docs/agent/05_GAME_DESIGN.md — a real design bible, not a summary.
Then write docs/agent/audits/AUDIT_003_game_designer.md, append new findings to
docs/agent/03_BACKLOG.md starting at PR-0400, rewrite 02_STATE.md, write
docs/agent/sessions/SESSION_003.md, and write HANDOFF.md for session 004 (AUDIT-003, The App
Review Rejector).

Report back in three lines.
```

## Goal

Write the design bible this project has never had, then find the design failures. `05_GAME_DESIGN.md`
must cover, with **real numbers from `Core/Tuning.swift` and `Meta/`, not vibes**: the three loops
(moment-to-moment, run, meta) and where each breaks; the first 60 seconds tick by tick; the
difficulty curve plotted against actual skill growth; reward schedules and whether the near-miss
window is tuned or arbitrary; **the economy computed out** — coins per average and per good run
against skin prices of 200–7,500 and world unlocks of 400–1,400, yielding time-to-first-unlock and
time-to-full-collection; session shape; each retention hook scored on "does this give a reason to
return *tomorrow specifically*"; and the mastery ceiling — what a player learns on run 5, 50, 500.
If the answer to the last one is "nothing after run 20", that is a SEV1 and you should say so.

## Before you read a single source file: run the app

Mandatory (`01_RULES.md` §4, decision D-003). Session 001 filed 181 findings from static reading and
then found a real defect fifteen minutes after launching it. Session 002 killed **four** of its own
findings by running the build — including a SEV1 decree-1 violation that turned out to be the
default character's intended identity. **You cannot audit game feel from source. Budget an hour.**

```bash
./Tools/build.sh
xcrun simctl boot 10C15FE0-3D9A-40D5-9E45-C0702E906DF3
xcrun simctl install 10C15FE0-3D9A-40D5-9E45-C0702E906DF3 .dd/Build/Products/Debug-iphonesimulator/PrismRush.app
SIMCTL_CHILD_PR_AUTOPLAY=1 SIMCTL_CHILD_PR_SKIP_SPLASH=1 xcrun simctl launch 10C15FE0-3D9A-40D5-9E45-C0702E906DF3 com.rayancheca.prismrush
```

Then **open the PNG and look at it.** A captured screenshot nobody read is not evidence.

Use the native simulator panel (`attach` first, then `tap` / `swipe` / `touch_path`) — it gives real
touch input in a 402×874 pt space, origin top-left. Fall back to `xcrun simctl` only for install,
launch with `SIMCTL_CHILD_*` hooks, and batch screenshots.

Hooks that reach any state in ~5 s: `PR_SCREEN` (`shop`/`characters`/`levels`/`missions`/`stats`/
`settings`) · `PR_AUTOPLAY` · `PR_SKIP_SPLASH` · `PR_FIRSTRUN` · `PR_DEMOPROFILE` · `PR_DEEPWORLDS` ·
`PR_WORLD` · `PR_SKIN` · `PR_SHIELD` · `PR_SNEAKERS` · `PR_TUTORIAL` · `PR_FOCUS` · `PR_DEMO`.

**Two techniques session 002 recommends, both cheap:**
- **Sample pixels, don't eyeball.** A three-line `PIL` block over a series of screenshots turns "it
  looks like it changes" into a table. It killed one false finding and quantified another.
- **Autoplay is your difficulty instrument.** The bot survives 6,000 m by design, so screenshot it at
  intervals and read the HUD — you get a real speed/density/score curve without playing.

## In scope

Everything in the AUDIT-002 brief in `PERSONAS.md`. Leads session 002 surfaced that are **yours, not
mine** — I deliberately did not score them:

- **World 13 is world 1 recoloured.** The ladder continues past 12 as "Pulse City II", "Geode Deep
  II", … with a real evolved palette and correct art. Verified on device. Whether an infinite reskin
  ladder should be *labelled* as new worlds, and whether reaching 9,600 m for one is a reward, is a
  design call.
- **The ×5 multiplier appears trivially reachable** — autoplay held `×5` at 192 m. If the cap is hit
  in the first twenty seconds, the multiplier is not a system.
- **Nothing in the app teaches magnet, streaks, flow, or slide timing.** The first-run gate teaches
  three mechanics of roughly eight. Ledger rows 19, 39, 53.
- **`timeSurvived` is computed and never shown** (PR-0131). Session shape is invisible to the player
  *and* to you — decide whether it should be surfaced.
- **The revive costs 150 coins and its run does not count for missions or XP** (PR-0307). That is a
  design question as much as a bug: what is a paid continue *for*?
- **Music is one 1.82 s bed, pinned to world 0 by explicit owner decree** (`SynthEngine.swift:133`).
  The other 11 beds exist and are intentionally unreachable. Open question 3 for Rayan.

## Explicitly out of scope

- **Do not change a single line of source.** Sessions 001–009 are read-only. A two-line "obviously
  safe" fix is still forbidden — file it.
- **Do not re-audit completeness.** Session 002 just did it and produced the Completeness Ledger in
  `02_STATE.md`. Use the ledger as input; do not rebuild it.
- **Do not audit App Store compliance.** That is AUDIT-003 (session 004). Note and move on.
- **Do not renumber, re-score, merge or delete session 001's or session 002's backlog items.**
  Session 009 triages. If you think one is wrong, say so in your audit file and mark it `WONTFIX`
  with a reason.
- **Do not touch `Store/metadata.md`** — PR-0010, and it waits for the ledger-checked rewrite.
- **Do not refactor `GameView.swift`** despite its 1,224 lines. PR-0241.

## Files you will need

| Path | Why |
|---|---|
| `docs/agent/audits/PERSONAS.md` | Your full brief. Read before anything else. |
| `docs/agent/02_STATE.md` | The Completeness Ledger — 59 features scored. Your starting map. |
| `PrismRush/Core/Tuning.swift` | **125 lines, every gameplay constant.** The difficulty curve lives here. Ground truth. |
| `PrismRush/Core/Spawner.swift` + `Patterns.swift` | Tier ladder + the 14 patterns. What the player meets, and when. |
| `PrismRush/Meta/XPCurve.swift`, `ShopValue.swift`, `MissionCatalog.swift`, `SkinCatalog.swift` | Every price, reward, faucet and sink. Compute the economy from these. |
| `PrismRush/UI/GameView.swift:680-792` (`recordRunResults`) | Where a run turns into money and XP. |
| `docs/agent/07_ARCHITECTURE.md` §3, §4 | Tick model and the pattern tier ladder. §11 is the where-to-look table. |
| `docs/agent/scratch/core.md` | Session 001's deep read of `Core/`. Gitignored — **read it this session or it is gone.** |

## Invariants you must not break

You are not writing code, so most of §8 does not bind you. Three that do:

1. **Never drive the simulator while `xcodebuild test` is running on it.** Concurrent installs crash
   the test host and report a false `TEST FAILED`.
2. **`docs/agent/04_DECISIONS.md` is append-only.** Never edit or delete an entry.
3. **Session logs and audit files are write-once.** `SESSION_001.md`, `SESSION_002.md` and
   `AUDIT_002_completeness.md` are history. Do not revise them.

## Traps

- **`swift test` green does not mean the app works.** 178 tests in 8.85 s, and none of `UI/`,
  `Render/`, `IAP/`, `SynthEngine`, StoreKit or GameKit is compiled.
  `Tests/CoreTests/CharacterParityTests.swift` is wrapped in `#if canImport(UIKit)` and silently
  compiles to **nothing** under `swift test`.
- **Every test count written in this repo is wrong.** `CLAUDE.md` says 95, `Tools/ci.sh` says 174.
  Measured truth is **178** SPM. Trust `08_TESTING.md`.
- **Launch hooks leave stale `activeSheet` state between launches.** A `PR_SCREEN=missions` launch can
  make the next plain launch open on Missions. **Always relaunch clean before concluding anything
  about navigation, and never file a navigation finding you have not reproduced from a fresh
  launch.** Session 001 was caught by this; session 002 nearly was and dropped the finding.
- **The splash never auto-dismisses.** Verified: identical pixels at t = 2, 6, 12, 20, 30 s. If you
  are waiting for the menu, you will wait forever — tap it.
- **`Tools/qa.sh` and `Tools/screenshots.sh` hardcode this machine's UDIDs and fail silently via
  `|| true`** (PR-0050). A green run from them may mean nothing ran.
- **The six owner decrees in `CLAUDE.md` outrank every design doc in `reports/design/`.** Several of
  those docs still specify decisions the owner later revoked (PR-0069 … PR-0073). A feature matching
  a design doc but violating a decree is a finding, not a pass. **This bites you specifically:** you
  will want to propose per-world music and world-reactive characters. Decree 1 and the
  `SynthEngine.swift:133` comment have already ruled both out. Argue the case in your audit if you
  disagree — do not assume it is an oversight.
- **`state.md` (58 KB) and `README.md` (35 KB) are history, not truth.** Where they disagree with
  `02_STATE.md`, `02_STATE.md` wins. Both overclaim (12 bespoke skies — 9 exist; per-world music —
  disabled).
- **Timings:** `swift test -c release` ≈ 29 s wall. `./Tools/build.sh` ≈ 2 min. `./Tools/ci.sh` is
  minutes plus the simulator. **Do not put a full build inside a fan-out.**
- **`docs/agent/scratch/` and `docs/agent/audits/scratch/` are gitignored** and now hold ~1.1 MB from
  sessions 001–002. Mine them this session; they will not survive a clone.
- **This worktree is not `main`.** `main` does not contain `docs/agent/` at all. Branch from session
  002's tip (`claude/prism-rush-audit-91c7ba`), never from `main`.

## Orientation commands

```bash
git tag pre-s003
swift test -c release 2>&1 | tail -3
sed -n '/## Completeness Ledger/,/### Roll-up/p' docs/agent/02_STATE.md
cat PrismRush/Core/Tuning.swift
grep -oE "^## PR-[0-9]{4}" docs/agent/03_BACKLOG.md | tail -1
```

## Current state in one paragraph

Prism Rush is a v1.6, feature-complete, technically strong iPhone game that has never been submitted
to the App Store: 95 Swift files, ~22,300 lines, zero dependencies, zero binary assets but a
generated icon, 178 SPM tests green in 8.85 s, and a genuinely deterministic core behind a clean
`RendererPort` seam. Session 001 built the agent memory system and filed 186 items from static
reading. **Session 002 ran the first adversarial audit and produced the Completeness Ledger: 50 of 59
user-facing features are fully implemented and exactly one — account deletion — is outright absent,
but only 13 of 59 clear the owner's own six decrees.** The finding that matters most is structural:
every failure state in the app is unfinished in the same way (store not loaded, not enough coins,
empty board, signed out, audio dead, nothing to restore), while the app *already contains the correct
pattern* in two places. 25 of 59 features have no automated test at all, concentrated exactly in the
layers `swift test` does not compile. Backlog is **210 items**; six audits remain unrun; no code has
been changed by the program and none should be until session 010.

## Open questions for Rayan

Carried forward until answered. **Do not block on them.**

1. **Is App Store submission still the goal, and on what timescale?** Everything in Phase 2 is priced
   against "yes, soon."
2. **PR-0254 — should a run that used a paid revive be leaderboard-eligible?** Session 002 sharpens
   this: PR-0307 shows post-revive play does not count for missions or XP, so a revived run is
   currently *partly* counted — the worst of both answers. **This one is squarely yours to opine on.**
3. **PR-0040 — the music is a 1.82 s loop for the whole session.** The single-bed decision was
   Rayan's; adding long-form structure inside that constraint is a design change needing sign-off.
4. **PR-0052 — is the Daily Challenge a *layout* guarantee or an *identical-experience* guarantee?**
5. ~~Mystery Box real money?~~ **Resolved:** 300 coins, and session 002 confirmed the odds are
   disclosed pre-purchase and sum to 100%.
6. **PR-0296 — is the attract track showing through the hub cards the intended neon look?** Session
   002 quantified it and deliberately did not score it. One yes/no closes it either way.
