# Session 001 — Bootstrap the agent program

- Date:        2026-07-27
- Branch:      `claude/beautiful-davinci-797e3b` (a worktree at `.claude/worktrees/beautiful-davinci-797e3b`, not a fresh `session/001-*` branch — see "Where I deviated")
- Goal:        Build the `docs/agent/` memory system and produce an architecture map good enough that a future session can find any subsystem without re-reading the repo.
- Items:       Filed PR-0001 … PR-0285 (181 unique IDs). Fixed none.
- Outcome:     COMPLETE
- Context used at handoff: ~75%

## What I changed

No source file was touched. Verified: `git status` shows changes only under `docs/agent/`, plus
`CLAUDE.md` and `.gitignore`.

| Path | What |
|---|---|
| `docs/agent/01_RULES.md` | The operating rules, installed verbatim from the program document |
| `docs/agent/audits/PERSONAS.md` | The full program: phases, the seven persona briefs, the session-009 triage prompt |
| `docs/agent/00_CHARTER.md` | Written from repo evidence, with a 7-row Assumptions table (see D-002) |
| `docs/agent/02_STATE.md` | Current state, the three biggest worries, a provisional phased roadmap |
| `docs/agent/03_BACKLOG.md` | 181 items — 1 SEV0-conditional, 14 SEV1, 40 SEV2, 123 SEV3, 3 SEV4 |
| `docs/agent/04_DECISIONS.md` | Format + D-001 (adopt the program), D-002 (charter from evidence) |
| `docs/agent/05_GAME_DESIGN.md` | Skeleton with the real `Tuning` constants transcribed; body owned by AUDIT-002 |
| `docs/agent/06_COMPLIANCE.md` | Skeleton; rows I could verify from `project.yml` / entitlements / manifest are filled, the rest are honest `UNKNOWN` |
| `docs/agent/07_ARCHITECTURE.md` | The map — 3,208 lines, §0–§11, including **110 numbered invariants** (INV-01 … INV-110) each with a "breaks if" and a "detected by" (or an explicit "nothing — untested") |
| `docs/agent/08_TESTING.md` | Coverage map with **measured** numbers, what compiles where, vacuous tests, the tooling |
| `docs/agent/09_GLOSSARY.md` | Project vocabulary, grouped, with "do not confuse with" notes |
| `CLAUDE.md` | Added the four-line "Agent program" pointer at the top. Nothing else |
| `.gitignore` | Ignore `docs/agent/scratch/` and `docs/agent/audits/scratch/` |

## Evidence

Measured test run, executed this session at the repo root:

```
$ /usr/bin/time -p swift test -c release
Test Suite 'PrismRushCorePackageTests.xctest' passed at 2026-07-27 13:51:00.717.
	 Executed 178 tests, with 0 failures (0 unexpected) in 7.283 (7.291) seconds
Test Suite 'All tests' passed at 2026-07-27 13:51:00.717.
	 Executed 178 tests, with 0 failures (0 unexpected) in 7.283 (7.296) seconds
real 28.89   user 25.09   sys 3.24
```

Placeholder scan across all 95 Swift files:

```
$ grep -rn -E "TODO|FIXME|HACK|XXX" PrismRush --include='*.swift' | wc -l
0
$ grep -rn -E "unimplemented|fatalError" PrismRush --include='*.swift'
(no output)
```

Backlog tally:

```
$ grep -oE "PR-[0-9]{4}" docs/agent/03_BACKLOG.md | sort -u | wc -l
181
```

Three dynamic workflows, 19 agents total:

| Workflow | Agents | Result |
|---|---|---|
| Survey — one agent per subsystem plus two cross-cutting traces | 10 | 10/10 clean, 342 tool uses, 2,505,844 subagent tokens, ~21 min |
| Synthesis — write `07`, `08`, `09` + extract trace findings | 4 | 3/4; **the architecture writer died at a usage limit** having written §0–§4 (743 lines) |
| Architecture completion — §5–§11 as five parallel part files | 5 | 5/5 clean; concatenated onto the existing 743 lines → 3,208 |

Invariant range check after concatenating two independently-written halves:

```
$ grep -oE "INV-[0-9]+" docs/agent/07_ARCHITECTURE.md | sort -u | wc -l
110
```

INV-01 … INV-110 with no gaps and no collisions — the two writers respected their assigned ranges.

Confirmation that this was a read-only session:

```
$ git status --short -- PrismRush Tests UITests Tools project.yml Package.swift Products.storekit | wc -l
0
```

## What I learned about this codebase

The things that cost me time, so they cost the next session nothing.

- **`GameCore` is `@Observable @MainActor`**, not a plain value type. The "pure core" is
  main-actor-isolated and imports `Observation`. It is still Foundation-only and Linux-testable —
  but do not assume you can drive it off the main actor.
- **Exactly one property is observed.** `snapshot` drives every SwiftUI update; all ~35 other
  simulation fields are `@ObservationIgnored`. `rebuildSnapshot()` runs once per `advance` call,
  **not** per tick — several tests depend on that distinction, and bare `tick(_:)` does not rebuild.
- **`advance(realDt:)` sanitises before accumulating.** `guard realDt.isFinite, realDt > 0` first,
  then `accumulator += min(realDt, 0.1)`. That is a hard ceiling of 12 ticks per call: a 5-second
  background trip discards 4.9 s of simulated time rather than fast-forwarding. The early return
  on junk dt deliberately skips `rebuildSnapshot()`.
- **"A seed fully determines a run" is not true for a human-played run.** The spawner is called
  with the player's *current* distance, and per-tick distance depends on chrono and overdrive. The
  determinism tests all pass because the Autopilot never collects pickups. Two code comments
  assert the opposite. This is PR-0020 and it is the finding I would most want re-derived
  independently.
- **`Patterns.count` is 14, not the 12 that `CLAUDE.md` claims.** RNG consumption per pattern is
  pinned as `[1,1,0,1,1,3,1,2,0,1,1,1,2,0]` by `PatternOrderTests`. The tier ladder is a strict
  prefix — a tier can only ever *add* patterns.
- **`DailyChallenge.layoutVersion` is at 7 and the v8 golden is already pre-armed** at
  `0x2FC8A9EAC0B9E30F`. Bumping is designed to be a one-line change. Note v5 and v6 were bumped
  for **zero-RNG** changes — adding or moving deterministic entities counts.
- **Every documented test count in the repo is wrong, in three different ways.** `CLAUDE.md` says
  95 total / 89 SPM; `Tools/ci.sh` says 174. Real: 178 SPM, 196 total. Do not trust a count you
  read in a comment.
- **`swift test` green does not mean the app builds.** `Package.swift` names seven Meta files and
  one Audio file individually; everything touching UIKit/RealityKit/SwiftUI/StoreKit/GameKit is
  not type-checked at all on Linux. `CharacterParityTests` is wrapped in `#if canImport(UIKit)`,
  which is **false under `swift test` on every platform SPM runs on** — it silently compiles to
  nothing and only ever executes inside the iOS-Simulator bundle.
- **The `.gitignore` excludes `reports/shots/*.png`,** so every "evidence: see `reports/shots/vNN/`"
  citation in `README.md` and `state.md` is a dead link for anyone who clones. Filed as PR-0067.

## New backlog items filed

181 IDs, `PR-0001` … `PR-0285` with intentional gaps. Highlights:

- **SEV1 economy/persistence cluster:** PR-0002 (iCloud merge duplicates spent coins), PR-0003
  (KVS is an unauthenticated entitlement source), PR-0004 (an `.unverified` purchase is charged
  and never resolved), PR-0005 (`load()` can discard a newer local save), PR-0250 (a decode throw
  silently wipes the profile), PR-0252 and PR-0253 (two-device exploits needing no jailbreak).
- **SEV1 compliance:** PR-0007 (undeclared required-reason API), PR-0008 (no account deletion),
  PR-0009 (privacy manifest contradicts the ship docs), PR-0010 (store listing describes a
  three-world game).
- **SEV1 behaviour:** PR-0006 (a view `body` mutates and saves the profile), PR-0011 (RUN AGAIN
  after a Daily Rush burns loadout charges), PR-0012 (pool ids can outlive their kind).
- **SEV0, conditional and unproven:** PR-0251 — `MainActor.assumeIsolated` on GameKit's auth
  handler. Flagged explicitly as a hunch for AUDIT-006 to resolve.

## Decisions made

- **D-001** — adopt the program as written, including the full seven-audit phase.
- **D-002** — write the charter from repo evidence rather than blocking on Rayan, because the
  workspace `CLAUDE.md` mandates autonomous mode and this session is non-interactive. Every
  inference is listed in the charter's Assumptions table.

## Where I deviated

Three deviations, all deliberate, all recorded so nobody has to reverse-engineer them.

1. **Branch.** `01_RULES.md` §5 says `session/NNN-short-slug`. This session was invoked inside an
   existing worktree on `claude/beautiful-davinci-797e3b`. I worked there rather than creating a
   branch inside a worktree. Session 002 should follow the rule on a normal checkout.
2. **Backlog format.** §6 mandates the ten-field block for every item. I used it for SEV1 and SEV2
   (55 items) and a compact table row for SEV3 (125 items). Writing 125 full blocks in a bootstrap
   session would have been padding. Filed as PR-0001; any SEV3 must be expanded before it is
   worked.
3. **Charter questions.** §5 of the session-001 prompt says to ask Rayan first. See D-002.

## The usage-limit interruption, and what it teaches the next session

The synthesis workflow's architecture writer hit the 5-hour session limit mid-file. It had written
§0–§4 to disk and died; its return value was empty. **Nothing was lost**, because the survey agents
had already persisted all ten scratch files and the writer had been streaming into the real file
rather than holding the document in context. A completion workflow then wrote §5–§11 as five
independent part files, which concatenated cleanly.

Three things generalise, and every audit session should apply them:

1. **The durability rule is not ceremony.** It is the only reason a limit hit cost twenty minutes
   instead of the whole session. Agents must write to disk *before* returning, always.
2. **Do not give one agent a 1,000-line document to write.** Split it by section with explicit,
   non-overlapping ID ranges (this session used INV-01…50 / INV-51…110) and concatenate. Two
   writers produced 110 invariants with zero collisions.
3. **A dead agent returns an empty string, not an error.** `parallel()` yields `null` and the run
   reports success. Always check the artifact on disk, not the workflow's summary.

## Where I was wrong

- **I assumed a grep for `TODO`/`FIXME`/`fatalError` would seed the backlog.** It returned zero
  across all 95 files. This codebase does not leave markers; its gaps are semantic — a dead
  `if let snapshot` block, an unreachable `charges == 0` branch, a computed-and-discarded
  `timeSurvived`. AUDIT-001 must read for meaning, not scan for strings, and should budget
  accordingly.
- **I assumed `Core/` was renderer-agnostic *and* isolation-agnostic.** It is the first but not
  the second — `@MainActor` on `GameCore`. I had to re-read to correct this.
- **I initially read `GameCore.swift:352` (`jumpBuf` decrement) as an unclamped-counter bug.** It
  is not; the `> 0` gate stops it. The survey agent made and corrected the same mistake
  independently. Filed as PR-0099 at SEV3 purely so the next reader does not spend the same ten
  minutes.
- **I did not verify a single finding in this backlog by re-reading the cited code myself.** Every
  item is one agent's reading. I believe most of them, but "session 001 filed it" is not evidence.
  This is stated at the top of `03_BACKLOG.md` and it is the most important caveat in this log.

## Open questions for Rayan

Non-blocking. Full versions with context in `02_STATE.md`.

1. Is App Store submission still the goal, and on what timescale?
2. PR-0254 — should a run that used a paid revive be leaderboard-eligible? Iron rule 10 currently
   says yes, by omission.
3. PR-0040 — the music is a 1.82 s loop for the entire session. Fixing it inside your single-bed
   decision is a design change, not a bug fix.
4. PR-0052 — is the Daily Challenge a *layout* guarantee or an *identical-experience* guarantee?
5. Can the Mystery Box ever be opened with real money, or is it coins only? The answer decides
   whether odds disclosure is a hard 3.1.1 blocker.

---

# Addendum — the build was actually run

Rayan, reading the session report: *"so you're saying no agents are actually spinning up a
simulator on xcode to run the code and actually see what's going on? cause it should def do that."*

He was right, and it was the single biggest defect in this session. Everything above this line is
static reading. `swift test` genuinely executed 178 tests, but **nobody built the app, launched it,
or looked at a frame** — and I wrote a handoff sending AUDIT-004 (Impatient Player) and AUDIT-005
(Device Matrix QA) into work that is *definitionally* impossible from source.

## What was then done

```
$ ./Tools/build.sh
BUILD OK

$ xcrun simctl install 10C15FE0-3D9A-40D5-9E45-C0702E906DF3 .dd/Build/Products/Debug-iphonesimulator/PrismRush.app
INSTALLED
$ xcrun simctl launch 10C15FE0-3D9A-40D5-9E45-C0702E906DF3 com.rayancheca.prismrush
com.rayancheca.prismrush: 30351
```

Then: splash captured; `PR_AUTOPLAY=1` run with six frames over ~36 s of real gameplay (189 m →
660 m); all six meta screens captured via `PR_SCREEN`; hub captured. Fourteen screenshots, opened
and read.

## What fifteen minutes of running it found

| ID | Sev | Finding |
|---|---|---|
| PR-0290 | SEV1 | The shop renders **hardcoded USD prices on live, tappable buy buttons** whenever StoreKit has not loaded. `displayPrice` falls back to `IAPCatalog`'s `fallbackPrice` strings (`IAPManager.swift:127-128`, `IAPCatalog.swift:28-35`). A non-US player is shown a price they will not be charged |
| PR-0291 | SEV2 | Score popups stack into an unreadable smear — seen at 189 m and again at 660 m, so systematic, not a collision |
| PR-0292 | SEV2 | A near-field tall obstacle washes the SHIELD deploy button out to near-invisible |
| PR-0293 | SEV2 | The Mystery Box discloses no odds |
| PR-0294 | SEV3 | `state.md`'s "Store unavailable fallback verified" note is no longer true of the shipped build |

**PR-0290 is the one that matters.** Ten agents read `IAPCatalog.swift` in full during the survey.
The `fallbackPrice` field is right there, with a comment explaining it. Not one flagged that the
buy button stays live while a fabricated price is on screen — because in source it reads as a
sensible loading affordance, and only on screen is it obviously a price tag on a working button.

Also resolved by looking: **the Mystery Box costs 300 coins, not real money.** That closes charter
assumption A4 and open question 5 — Guideline 3.1.1's odds requirement does not bite. Two agents
had flagged it as a possible hard blocker; one screenshot settled it.

## What this changes about the program

- `01_RULES.md` §4 amended (D-003, on Rayan's explicit instruction — the one authorised edit to the
  rules file): any session concerning behaviour must build and run the app before writing findings,
  and a finding that could have been confirmed on a running build and was not is an **incomplete
  finding**.
- `HANDOFF.md` now opens with a mandatory run-the-app block before AUDIT-001 reads any source.
- D-004 records that the native simulator integration is blocked on
  `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer` (which needs Rayan's password,
  and which is odd because `xcode-select -p` already returns that path), so sessions drive
  `xcrun simctl` instead — no synthetic taps, so arbitrary input must become an XCUITest.

## Where I was wrong (addendum)

- **I treated "read every file exhaustively" as equivalent to "understand the product."** It is
  not, and the gap is not marginal — it is a money bug and every finding AUDIT-004 and AUDIT-005
  exist to produce. Ten agents and 2.5M tokens of reading did not surface what one screenshot did.
- **I wrote a handoff that would have propagated the mistake.** The original version sent the
  Completeness Auditor to grep for markers and read `ui-meta.md`. Its actual job — "is this
  finished" — is answered by launching the thing.
- **I trusted `state.md`'s verified-behaviour note** about the shop's offline fallback. It was
  wrong (PR-0294). The lesson generalises: a doc saying "verified" records what someone saw once,
  on some build, and this repo's docs are demonstrably stale in a dozen places.
