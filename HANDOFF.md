# HANDOFF → Session 002 (AUDIT-001, The Completeness Auditor)

## Paste this to start the next session

```
You are session 002 of a long-running program to finish and ship Prism Rush, a neon
endless runner for iOS. Read docs/agent/01_RULES.md, then docs/agent/02_STATE.md, then
docs/agent/07_ARCHITECTURE.md, then this file's Goal / Traps / Orientation sections.
Follow the nine-step session protocol in 01_RULES.md.

This session makes NO code changes. Zero. You are running one adversarial audit pass.

Persona: AUDIT-001 — The Completeness Auditor.
Brief: read the full brief in docs/agent/audits/PERSONAS.md and adopt it completely.

Stay in character for the entire session. You are a contractor hired to determine
whether this app is actually finished, because the previous developer said it was and
you have reason to doubt him. You are paid per real gap found and you are behind on
rent. You are not a helpful assistant reviewing a friend's project. Being agreeable is
a failure mode. If you find yourself writing "overall this is well-architected," delete
it and go find something worse.

Run this audit as a dynamic workflow. Fan agents out across the codebase rather than
reading it serially, and have independent agents adversarially verify each other's
findings before any of them are reported. A finding that survives a hostile second
reader is worth ten that did not get one.

Durability rule, and this is not optional: every agent writes its findings to
docs/agent/audits/scratch/<agent-label>.md as it works, BEFORE returning anything.
Workflow intermediate results live in script variables and vanish when the run ends —
only your final synthesis reaches the session. Anything an agent found but did not
write down is permanently lost. Synthesize from the scratch files, not from memory of
the run.

Rules for this audit:
- Read the actual code. Every finding must cite a file path and, where possible, a line
  or symbol. A finding you cannot point at is a hunch — mark it as such or drop it.
- Severity per 01_RULES.md section 6. Be honest. Inflating everything to SEV0 is as
  useless as calling everything SEV3.
- Include repro steps for anything reproducible.
- Distinguish "this is broken" from "this is missing" from "this is worse than it
  should be." All three are in scope; conflating them is not.
- Twelve real findings beat forty restatements of the same complaint.

Write docs/agent/audits/AUDIT_002_completeness.md containing:
1. Your mandate in one paragraph, in character
2. What you examined and what you deliberately did not
3. Findings, ranked by severity, in the backlog item format from 01_RULES.md
4. The three things that worry you most, and why
5. What you would need in order to check the things you could not check

Then: append every NEW finding to docs/agent/03_BACKLOG.md starting at PR-0300, put the
Completeness Ledger into docs/agent/02_STATE.md, rewrite 02_STATE.md, write
docs/agent/sessions/SESSION_002.md, and write HANDOFF.md for session 003 (AUDIT-002,
The Game Designer).

Report back in three lines.
```

## Goal

Determine whether Prism Rush is actually finished, and produce the **Completeness Ledger** — one
row per user-facing feature the project claims, with columns for `implemented`, `reachable`,
`tested`, `polished` — as a permanent section of `02_STATE.md`.

## Before you read a single source file: run the app

This is mandatory (`01_RULES.md` §4, decision D-003). Session 001 filed 181 findings from static
reading, then found a **money bug in the first fifteen minutes of actually launching it** —
PR-0290, the shop rendering hardcoded USD prices on live buy buttons whenever StoreKit has not
loaded. Ten agents had read `IAPCatalog.swift` and missed it.

Your persona's whole job is "is this actually finished." You cannot answer that from source.

```bash
./Tools/build.sh
```

```bash
xcrun simctl boot 10C15FE0-3D9A-40D5-9E45-C0702E906DF3
```

```bash
xcrun simctl install 10C15FE0-3D9A-40D5-9E45-C0702E906DF3 .dd/Build/Products/Debug-iphonesimulator/PrismRush.app
```

```bash
SIMCTL_CHILD_PR_SCREEN=shop SIMCTL_CHILD_PR_SKIP_SPLASH=1 xcrun simctl launch 10C15FE0-3D9A-40D5-9E45-C0702E906DF3 com.rayancheca.prismrush
```

```bash
xcrun simctl io 10C15FE0-3D9A-40D5-9E45-C0702E906DF3 screenshot shop.png
```

Then **open the PNG and look at it.** A captured screenshot nobody read is not evidence.

Walk every screen this way — `PR_SCREEN` takes `shop`, `characters`, `levels`, `missions`,
`stats`, `settings`; `PR_AUTOPLAY=1` plays the game for you; `PR_FIRSTRUN=1` gives the first-run
tutorial state; and `PR_DEMOPROFILE`, `PR_DEEPWORLDS`, `PR_WORLD`, `PR_SKIN`, `PR_SHIELD`,
`PR_SNEAKERS`, `PR_TUTORIAL`, `PR_FOCUS`, `PR_DEMO` reach the rest. **Screenshot the zero-coin,
everything-owned, and offline states in particular** — those are where decree 3 ("no
broken-looking states for expected situations") gets violated, and they are your persona's
richest hunting ground.

Two constraints: `simctl` **cannot synthesise taps or swipes**, so anything needing arbitrary
touch input must be written as an XCUITest; and **never drive the simulator while `xcodebuild
test` is running on it** — concurrent installs crash the test host.

## In scope

Everything in the AUDIT-001 brief in `docs/agent/audits/PERSONAS.md`. The highest-yield leads
session 001 already surfaced, for you to **verify or refute independently** — do not take them on
trust:

- **PR-0130** — `PauseOverlay`'s entire session-summary block is dead: `snapshot` defaults to nil
  and `GameView` never passes it (`PauseOverlay.swift:10, 24-40`).
- **PR-0131** — `timeSurvived` is accumulated every frame, plumbed to `GameOverView`, and never
  displayed.
- **PR-0138** — the `charges == 0` branch of `deployButton` is unreachable; the caller only renders
  when `charges > 0`.
- **PR-0176** — `MissionCatalog.Metric.revives` is structurally unsatisfiable: `summary.revives` is
  captured at the first death, where `revivesUsed` is always 0.
- **PR-0160 / PR-0161** — `auroraID` prices every premium skin, correct only because Aurora is the
  only `.iap` skin today; the shop rotation hero silently renders free Prism for an unknown id.
- **PR-0158** — "REACH IT · Nm" is styled as an actionable key but only dismisses the panel.
- **PR-0045 / PR-0032 / PR-0031 / PR-0033** — four empty/error states that look broken for
  situations that are entirely normal (unaffordable box, partial store load, ask-to-buy pending,
  an undismissible stale error).
- **PR-0010** — `Store/metadata.md` describes a three-world game; the shipped build has twelve
  world families.

Raw material you should mine before writing anything: **`docs/agent/scratch/docs-claims.md`
contains a 108-row claims ledger** already built by grepping every claim in `README.md`,
`state.md`, `Store/metadata.md` and `reports/` against the shipped tree. Start from it; do not
rebuild it.

## Explicitly out of scope

- **Do not change a single line of source.** Sessions 001–009 are read-only. A two-line "obviously
  safe" fix is still forbidden — file it.
- **Do not fix `Store/metadata.md`** even though it is plainly wrong. It is PR-0010 and it must wait
  until your ledger exists, so that every rewritten claim is checkable against it.
- **Do not audit game feel, difficulty, or economy balance.** That is AUDIT-002 (session 003) and
  duplicating it wastes the separation the program is built on.
- **Do not audit App Store compliance.** That is AUDIT-003 (session 004). Note anything you trip
  over and move on.
- **Do not renumber, re-score, merge, or delete session 001's backlog items.** Session 009 does
  triage. If you believe an item is wrong, say so in your audit file and mark the item
  `WONTFIX` with a reason — do not silently remove it.
- **Do not refactor `GameView.swift`** despite it being 1,224 lines. Tracked as PR-0241.

## Files you will need

| Path | Why |
|---|---|
| `docs/agent/audits/PERSONAS.md` | Your full persona brief — read it before anything else |
| `docs/agent/scratch/docs-claims.md` | The 108-row claims ledger. **Gitignored — read it this session or it is gone** |
| `docs/agent/scratch/ui-meta.md` | Navigation graph, empty states, preview fidelity, every control and what it actually does |
| `docs/agent/scratch/ui-game.md` | Run lifecycle state machine, the input layer, dead code in the in-run surfaces |
| `docs/agent/scratch/meta-iap.md` | Every skin, every mission, every product — and whether each has a real implementation |
| `docs/agent/07_ARCHITECTURE.md` | The map. §1 directory tour and §11 "where to look first" will save you an hour |
| `PrismRush/UI/` | 26 files, 8,688 lines — where unreachable affordances live |
| `PrismRush/Meta/SkinCatalog.swift`, `MissionCatalog.swift` | Catalog entries to check for real implementations |
| `Store/metadata.md`, `README.md` | The claims. Both are stale; `docs-claims.md` already digested them |

## Invariants you must not break

You are not writing code, so most of `07_ARCHITECTURE.md` §8 does not bind you. Three that do:

- **Do not run `Tools/screenshots.sh` or `simctl launch` while `xcodebuild test` is running on the
  same simulator.** Concurrent installs crash the test host and report a false TEST FAILED.
- **`docs/agent/04_DECISIONS.md` is append-only.** Never edit or delete an existing entry.
- **Session logs and audit files are write-once.** `SESSION_001.md` and this handoff's predecessor
  are history; do not revise them.

## Traps

- **`grep -rn -E "TODO|FIXME|HACK|XXX" PrismRush --include='*.swift'` returns exactly zero, and
  there are no `fatalError`s.** Session 001 verified this across all 95 files. Your persona brief
  puts marker-hunting first — do it once, get zero, and move on. **This codebase's gaps are
  semantic, not textual.** They look like a dead `if let snapshot` block, an unreachable `else`
  branch, a computed-and-discarded value, a catalog entry that renders as the default. Budget your
  time for reading meaning, not scanning strings.
- **Every test count written in this repo is wrong.** `CLAUDE.md` says 95; `Tools/ci.sh` says 174.
  The measured truth is 178 SPM / 196 total. Trust `docs/agent/08_TESTING.md`, which has the real
  output pasted in.
- **`swift test -c release` green does NOT mean the app builds.** Linux/SPM compiles only `Core/`,
  seven named `Meta/` files and `Audio/Synth.swift`. Nothing touching UIKit, RealityKit, SwiftUI,
  StoreKit, AVFoundation or GameKit is type-checked there at all.
- **`Tests/CoreTests/CharacterParityTests.swift` is wrapped in `#if canImport(UIKit)`, which is
  false under `swift test` on every platform SPM runs on.** It silently compiles to nothing. If you
  are checking whether a feature is "tested", that file does not count outside the Xcode bundle.
- **Timings:** `swift test -c release` ≈ 29 s wall (7.3 s of tests). `./Tools/build.sh` is minutes.
  `./Tools/ci.sh` is minutes plus the simulator. Do not put a full build inside a fan-out.
- **`Tools/qa.sh` and `Tools/screenshots.sh` hardcode this machine's simulator UDIDs and fail
  silently via `|| true`** (PR-0050). A green run from them may mean nothing ran.
- **`.gitignore` excludes `reports/shots/*.png`,** so every "evidence: see `reports/shots/vNN/`"
  link in `README.md` and `state.md` is dead on a fresh clone. Do not treat those citations as
  proof that anything was verified.
- **`state.md` is 58 KB and `README.md` is 35 KB.** They are history, not truth. Where they
  disagree with `02_STATE.md`, `02_STATE.md` wins.
- **The six owner decrees in `CLAUDE.md` outrank every design doc in `reports/design/`.** Several
  of those docs still specify decisions the owner later revoked (PR-0069 … PR-0073). A feature
  matching a design doc but violating a decree is a finding, not a pass.
- **Decrees 3 and 4 are your sharpest tools.** "No broken-looking states for expected situations"
  and "everything on screen leads somewhere" set a bar well above Apple's, and this app has several
  surfaces that miss it.

## Orientation commands

```bash
git tag pre-s002
```

```bash
swift test -c release 2>&1 | tail -5
```

```bash
grep -n "^## " docs/agent/scratch/docs-claims.md
```

```bash
grep -n "^## \|^### " docs/agent/07_ARCHITECTURE.md
```

```bash
grep -oE "PR-[0-9]{4}" docs/agent/03_BACKLOG.md | sort -u | tail -1
```

## Current state in one paragraph

Prism Rush is a v1.6, feature-complete, technically strong iPhone game that has never been
submitted to the App Store: 95 Swift files, ~22,300 lines, zero third-party dependencies, zero
binary assets except a generated icon, 178 SPM tests passing in 7.3 s, and a genuinely
deterministic simulation core behind a clean `RendererPort` seam. Session 001 changed no code and
built the agent memory system: charter, state, a 181-item backlog, an architecture map, a testing
map and a glossary. What is actually wrong is concentrated: the iCloud save-merge layer leaks money
in four independent ways and can silently discard a newer local save (PR-0002, PR-0003, PR-0005,
PR-0250, PR-0252, PR-0253); three cheap compliance items block a first submission (PR-0007,
PR-0008, PR-0009); and the store listing describes a three-world game that no longer exists
(PR-0010). None of session 001's findings has been adversarially verified — that is what your
session and the six after it are for.

## Open questions for Rayan

Carried forward until answered. Do not block on them.

1. Is App Store submission still the goal, and on what timescale? Everything in the compliance
   phase is priced against "yes, soon."
2. PR-0254 — should a run that used a paid revive be leaderboard-eligible? Iron rule 10 currently
   says yes, by omission.
3. PR-0040 — the music is a 1.82 s loop for the entire session. Adding long-form structure inside
   the single-bed decision is a design change, not a bug fix.
4. PR-0052 — is the Daily Challenge a *layout* guarantee or an *identical-experience* guarantee?
5. Can the Mystery Box ever be opened with real money, or coins only? If real money buys a
   randomized outcome, odds disclosure becomes a hard 3.1.1 blocker.
