# Prism Rush — Agent Operating Rules

**Install at:** `docs/agent/01_RULES.md`
**Read this file at the start of every session, before any other file.**
Keep it under ~400 lines. It is loaded every session, so every line costs context that could have gone to code.

---

## 0. The rule that outranks all others

You are one session in a chain that may run for hundreds of sessions. Your job is **not** to finish Prism Rush. Your job is to:

1. Complete exactly one goal, and
2. Leave the repo so that the next session starts smarter than you did.

A session that ships a flawless feature and writes a weak handoff is a **failed session**. The handoff is the product. The code is a side effect.

Why: your context window dies at the end of this session and nothing in it survives. The only thing that crosses the boundary is what is written to disk. Treat every file in `docs/agent/` as your memory, not as documentation for humans.

---

## 1. Document map and write ownership

| File | Purpose | Write policy |
|---|---|---|
| `docs/agent/00_CHARTER.md` | Vision, quality bar, non-negotiables | Only when Rayan changes direction |
| `docs/agent/01_RULES.md` | This file | Only with Rayan's explicit approval |
| `docs/agent/02_STATE.md` | Single source of truth for *right now* | Rewrite every session |
| `docs/agent/03_BACKLOG.md` | Every known defect, gap, and idea | Update every session |
| `docs/agent/04_DECISIONS.md` | Append-only decision log (ADRs) | Append only. Never edit or delete history |
| `docs/agent/05_GAME_DESIGN.md` | Design bible: loop, economy, curve, retention | Update when design changes |
| `docs/agent/06_COMPLIANCE.md` | App Store readiness checklist with status | Update when compliance work happens |
| `docs/agent/07_ARCHITECTURE.md` | Codebase map, seams, invariants, gotchas | Update when structure changes |
| `docs/agent/08_TESTING.md` | Coverage map, known gaps, how to run everything | Update when tests change |
| `docs/agent/09_GLOSSARY.md` | Project vocabulary, so sessions use identical names | Append |
| `docs/agent/sessions/SESSION_NNN.md` | Immutable log of one session | Create once, never edit afterward |
| `docs/agent/audits/AUDIT_NNN_<persona>.md` | One adversarial audit pass | Create once, never edit afterward |
| `HANDOFF.md` (repo root) | The literal prompt for the next session | Overwrite every session |

Two files must never disagree about the same fact. If `02_STATE.md` and a session log conflict, `02_STATE.md` wins and you fix the state file. If you find yourself copying the same paragraph into two files, one of them should hold a pointer instead.

`CLAUDE.md` at the repo root must contain a pointer to this system so it auto-loads. Nothing else about the program lives in `CLAUDE.md`.

---

## 2. Session protocol — nine steps, in order

**Step 1 — Boot.** Tag a recovery point first: `git tag pre-sNNN`. Then read, in this order: `HANDOFF.md`, `01_RULES.md`, `02_STATE.md`, `00_CHARTER.md`. Then read only the backlog items named in the handoff, not the whole backlog. Do not explore the codebase yet.

**Step 2 — Declare the goal.** Write one sentence: "This session I will ___." If `HANDOFF.md` names a goal, that is the goal. If the handoff is missing or incoherent, pick the highest-severity `OPEN` backlog item that is not blocked, and say so.

**Step 3 — Orient.** Read `07_ARCHITECTURE.md`, then only the files the goal actually touches. Resist reading the whole repo. You already have a map; that is what the map is for. If the map is wrong, fix the map as part of this session.

**Step 4 — Work.** Small commits. Follow the conventions in section 5.

**Step 5 — Verify.** Run the Definition of Done gate in section 4. Paste real command output into the session log. No output, no credit.

**Step 6 — Update memory.** `02_STATE.md` (rewrite), `03_BACKLOG.md` (statuses, plus any new findings), `04_DECISIONS.md` (append if you made a judgment call a future session could reasonably reverse), and whichever of `05`–`09` your work invalidated.

**Step 7 — Write the session log.** `docs/agent/sessions/SESSION_NNN.md`, using the template in section 7.

**Step 8 — Write the handoff.** Overwrite `HANDOFF.md` using the template in section 8. This is the highest-value thing you do all session. Budget for it.

**Step 9 — Stop.** Commit, report to Rayan in three lines or fewer, and do not begin the next goal. Ending early with a clean handoff is always correct.

### Context budget rule

At roughly 60% context consumed, stop taking on new work. At 70%, finish the current edit, then spend everything remaining on steps 5 through 8.

Why this matters mechanically: handoff quality degrades sharply as context fills, because a saturated context makes you compress and generalize exactly when the next session needs specifics. A handoff written at 95% context is a summary; a handoff written at 70% is a briefing. If you blow through the budget, say so in the session log so the next session distrusts your handoff appropriately.

### Workflows and ultracode

When the session runs with `--effort ultracode`, or when you spawn a dynamic workflow yourself, the budget above still governs your own context, but two mechanics change and both matter.

A workflow's intermediate results live in script variables rather than in your context window. Only the final synthesized answer reaches you. That makes wide sweeps cheap in context and expensive in tokens, and it is why audits and migrations belong in workflows while a two-file fix does not.

The trap is durability. **Anything a subagent discovered and did not write to disk is destroyed when the run ends.** Every workflow you write must instruct its agents to persist findings to `docs/agent/scratch/<label>.md` before returning, and you must synthesize from those files rather than from the run's summary. Delete or gitignore the scratch directory once the real artifact is written.

Never end a session with a workflow in flight. Runs resume only inside the same session; quitting discards everything still running.

If a task is genuinely trivial, do it directly rather than orchestrating three agents to change one constant. Ultracode decides when a task warrants a workflow; that decision is yours to make well, not to make maximally.

This session runs with bypass permissions. Nothing will stop you before a destructive command executes. The git conventions in section 5 are therefore self-enforced: there is no prompt standing between you and a force-push that destroys another session's work. Treat every irreversible git operation as forbidden rather than merely discouraged.

---

## 3. Scope discipline

You will find problems outside your goal. Constantly. That is expected and it is not an invitation.

- **Found something broken and it is not your goal?** Add a backlog item. Do not fix it.
- **The fix is two lines and obviously safe?** Still add a backlog item. Two-line fixes are how sessions turn into six-hour unreviewable diffs.
- **It is SEV0 and it blocks your goal?** Fix it, log it as a scope exception in the session log, and note in the handoff that this session did two things.
- **You think the goal itself is wrong?** Say so in the session log and the handoff, do the goal anyway unless it is actively harmful, and flag it as an open question for Rayan.

Never expand a goal silently. Silent expansion is the single most common way this kind of program collapses: session 40 discovers session 12 quietly rewrote a subsystem, and no file explains why.

---

## 4. Definition of Done

An item is `DONE` only when all of these hold and the evidence is pasted into the session log:

- [ ] Project builds clean: `./Tools/build.sh` (or the documented `xcodebuild` invocation)
- [ ] Core tests pass: `swift test` for the SwiftPM package
- [ ] QA script passes if it covers the area: `./Tools/qa.sh`
- [ ] No **new** compiler warnings. Pre-existing warnings get backlog items, not silence
- [ ] The specific verification named on the backlog item was executed
- [ ] Backlog item status updated to `DONE(S-NNN)`

If something cannot be verified in this environment — simulator unavailable, device-only behavior, needs App Store Connect, needs a real purchase — mark the item `VERIFY-PENDING` instead of `DONE`, and add a line to `02_STATE.md` under "Needs Rayan on a device." Never mark `DONE` on the strength of reasoning alone.

### Run the app (added by D-003, on Rayan's explicit instruction)

**If your session concerns behaviour, you must build and run the app before you write your
findings.** Reading the source is not verification. Session 001 produced 181 findings from static
reading alone and then found a money bug in the first fifteen minutes of actually launching it
(PR-0290: hardcoded USD prices on live buy buttons), plus two readability defects that cannot
exist in a source file (PR-0291, PR-0292).

The minimum, in order:

```bash
./Tools/build.sh                                    # BUILD OK, ~2 min
xcrun simctl boot <UDID> && xcrun simctl install <UDID> .dd/Build/Products/Debug-iphonesimulator/PrismRush.app
SIMCTL_CHILD_PR_AUTOPLAY=1 xcrun simctl launch <UDID> com.rayancheca.prismrush
xcrun simctl io <UDID> screenshot shot.png          # then actually LOOK at it
```

Full working command set, hook table, and the current simulator UDID: `08_TESTING.md`.

- **Look at the screenshots.** A captured PNG nobody opened is not evidence.
- **Reach states with the repo's launch hooks**, not by guessing: `PR_AUTOPLAY`, `PR_SCREEN`
  (`shop`/`characters`/`levels`/`missions`/`stats`/`settings`), `PR_FIRSTRUN`, `PR_SKIP_SPLASH`,
  `PR_WORLD`, `PR_SKIN`, `PR_DEEPWORLDS`, `PR_SHIELD`, `PR_SNEAKERS`, `PR_DEMOPROFILE`,
  `PR_TUTORIAL`, `PR_FOCUS`, `PR_DEMO`.
- **`simctl` cannot synthesise taps or swipes.** Anything needing arbitrary touch input must be
  written as an XCUITest — which is the better outcome anyway, since it leaves a regression test
  behind.
- **Never drive the simulator while `xcodebuild test` is running on it.** Concurrent installs
  crash the test host and report a false TEST FAILED.
- A finding that *could* have been confirmed on a running build and was not is an **incomplete
  finding**. Mark it as unconfirmed rather than presenting it as established.

**Forbidden ways to make the gate pass:** deleting or skipping a test, lowering a threshold, adding `@unchecked Sendable`, adding `MainActor.assumeIsolated` to silence an isolation error, wrapping in `try?` to swallow, `#if DEBUG`-ing a failure away, or suppressing a warning. Each of those is a *finding* to log, never a fix to apply.

---

## 5. Code and git conventions

- Branch per session: `session/NNN-short-slug`. Never commit directly to `main`.
- Commit messages: `[S-NNN][PR-0123] imperative summary`. Body explains *why*, not what.
- Never force-push, never rewrite published history, never `git add -A` without reading the diff.
- Leave the working tree clean. No stray scratch files, no commented-out blocks "for later."
- No new third-party dependency without an ADR in `04_DECISIONS.md`.
- Do not rewrite a subsystem wholesale. Land the smallest change that fixes the item.
- Swift conventions follow `~/.claude/skills/ios-swiftui/SKILL.md` where they do not conflict with this repo's existing patterns. This project is RealityKit + strict-concurrency Swift 6, not the Firebase/MVVM stack in that skill; when they disagree, the repo wins and you note the divergence in `07_ARCHITECTURE.md`.
- Preserve determinism. The game core is a pure deterministic simulation on a fixed timestep. Any change that introduces wall-clock time, floating-point nondeterminism, unordered iteration, or hidden state into `Core/` is a SEV0 regardless of how nice it looks.

---

## 6. Backlog format

Every item is one block. IDs never get reused, even after `DONE`.

```
### PR-0142 · SEV1 · Run state corrupts when backgrounded mid-run
- Area:        Core/GameCore
- Found by:    AUDIT-006 (QA-Device)
- Status:      OPEN
- Symptom:     What the player or reviewer actually observes.
- Repro:       Numbered steps. Exact seed / device / state if it matters.
- Why:         One line on the mechanism, if known. "Unknown" is allowed and honest.
- Impact:      Who hits this, how often, what it costs.
- Fix sketch:  The approach, not the diff.
- Blast radius: Files likely touched.
- Verification: The exact command or test that proves it fixed.
- Blocked by:  PR-0101 (omit if none)
```

**Status values:** `OPEN` · `IN-PROGRESS(S-NNN)` · `DONE(S-NNN)` · `VERIFY-PENDING(S-NNN)` · `WONTFIX(D-NNN)` · `DUPLICATE(PR-NNNN)`

**Severity ladder:**

| | Meaning |
|---|---|
| **SEV0** | Crash, data loss, money bug, guaranteed App Review rejection, determinism break |
| **SEV1** | Core function missing or broken. A player notices and quits |
| **SEV2** | Game feel, balance, or polish that measurably changes whether players come back |
| **SEV3** | Code health, test coverage, architecture debt, docs |
| **SEV4** | Speculative improvement. Parking lot |

Severity is about consequence, not effort. A one-character fix can be SEV0.

---

## 7. Session log template

```markdown
# Session NNN — <goal in five words>

- Date:        YYYY-MM-DD
- Branch:      session/NNN-slug
- Goal:        <the one sentence from Step 2>
- Items:       PR-0142, PR-0147
- Outcome:     COMPLETE | PARTIAL | BLOCKED
- Context used at handoff: ~NN%

## What I changed
<Paths and one line each. Not a diff. Not a novel.>

## Evidence
<Pasted build/test output. Real output only.>

## What I learned about this codebase
<Non-obvious mechanics, invariants, traps. The stuff that cost you 20 minutes
to discover. This section is why the next session is faster than you were.>

## New backlog items filed
<IDs and one-line titles.>

## Decisions made
<D-NNN references, or "none".>

## Where I was wrong
<Assumptions that turned out false. Be specific. Future sessions will
otherwise repeat your mistake.>

## Open questions for Rayan
<Non-blocking. Numbered.>
```

The "Where I was wrong" section is not optional and is not decoration. Across a long chain, repeated wrong assumptions are the dominant cost, and they are invisible unless someone writes them down.

---

## 8. Handoff template

`HANDOFF.md` is overwritten every session. It is a prompt, written for a model that knows nothing about this project. Assume no memory whatsoever.

```markdown
# HANDOFF → Session NNN+1

## Paste this to start the next session

Read docs/agent/01_RULES.md, then docs/agent/02_STATE.md, then this file's
"Context" and "Goal" sections. Follow the nine-step session protocol.

## Goal
<One sentence. One goal. Sized to fit comfortably in one session.>

## In scope
<Backlog IDs, with a one-line restatement of each so the next session does
not have to open the backlog to know what it's doing.>

## Explicitly out of scope
<Named temptations. "Do not refactor the spawner even though it looks wrong.
It is tracked as PR-0210 and depends on PR-0188 landing first.">

## Files you will need
<Exact paths, with one line on why each matters.>

## Invariants you must not break
<Determinism, actor isolation boundaries, save-format compatibility,
whatever applies to this goal.>

## Traps
<Things that will waste your time. "Tools/build.sh takes 4 minutes; use
swift test for core-only changes." "The 200-seed solvability bot is flaky
above seed 180 — known, tracked as PR-0155, ignore it.">

## Orientation commands
<The 3–5 commands that get the next session productive fastest.>

## Current state in one paragraph
<Where the project actually is. Honest. Include what is broken.>

## Open questions for Rayan
<Carried forward until answered or dropped.>
```

A handoff that says "continue improving the game" is a failure. A handoff that names one goal, four files, two traps, and one invariant is doing its job.

---

## 9. Reporting to Rayan

At the end of a session, three lines maximum in chat: what got done, what the next session's goal is, and anything that needs him specifically. Everything else goes in the files. He reads the files when he wants detail; he does not want a wall of text in the terminal.

Flag immediately, mid-session, if: the goal turns out to be much larger than one session, you find a SEV0, you need a decision only he can make, or you think the program's direction is wrong.
