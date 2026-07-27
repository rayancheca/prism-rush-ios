# Prism Rush — Adversarial Completion Program

Everything here is meant to be pasted into Claude Code, one block at a time. Read the "How this works" section once, then never again.

## How this works

The program runs in three phases.

**Phase A — Scaffolding (session 001).** Build the memory system, map the codebase, write the charter. No code changes.

**Phase B — Adversarial audit (sessions 002–008).** Seven hostile passes over the codebase, one persona per session. Each writes its own audit file. No code changes.

One persona per session is not padding. A persona is a reading lens, and lenses interfere: if you run all seven in one context, personas four through seven inherit the first three's conclusions and produce derivative, agreeable findings instead of independent ones. Separate sessions force each persona to re-derive its view from the actual code. You get seven genuinely different attacks instead of one attack repeated seven times with different headers.

**Phase C — Triage and execution (session 009 onward).** Merge the seven audits into one ranked backlog, then grind it, one goal per session, until the backlog is empty.

**Re-audit cadence:** after every 10 execution sessions, re-run one persona (rotating). After every 30, re-run all seven. The backlog rots — fixes change the shape of the codebase, and a finding from session 004 may be obsolete or may have grown teeth by session 60.

## Setup, once

```bash
cd ~/Dev/ios/prism-rush-ios   # adjust path
git checkout -b agent/program-bootstrap
mkdir -p docs/agent/sessions docs/agent/audits
# drop 01_RULES.md into docs/agent/01_RULES.md
# drop this file into docs/agent/audits/PERSONAS.md
```

Then add this to the top of your existing `CLAUDE.md` so every session auto-loads the system:

```markdown
## Agent program

This repo runs a multi-session agent program. Before doing anything else:
read `docs/agent/01_RULES.md`, then `docs/agent/02_STATE.md`, then `HANDOFF.md`.
Those rules govern every session. Do not skip them, even for a small request.
```

Launch every session with:

```bash
claude --model claude-opus-5 --effort ultracode --dangerously-skip-permissions
```

`--dangerously-skip-permissions` is equivalent to `--permission-mode bypassPermissions`. Every tool call runs without confirmation: file edits, shell commands, web fetches, MCP calls, subagent spawns. Claude Code shows a one-time warning the first time you use it. Root and home-directory removals still prompt as a circuit breaker, and Claude Code refuses to run under root or sudo outside a recognized sandbox, so do not wrap it.

Ultracode requires Claude Code v2.1.203 or later. It pins the session to `xhigh` reasoning and has Claude auto-orchestrate dynamic workflows. With bypass permissions on, the workflow approval prompt never appears — runs start immediately.

For maximum fan-out, set the size guideline to unrestricted before the first audit:

```
/config workflowSizeGuideline=unrestricted
```

The default aims at fewer than 15 agents. Unrestricted lets Claude size each workflow to the task. The runtime caps are the real ceiling regardless of the setting: 16 concurrent agents (fewer on machines with limited CPU cores) and 1,000 agents total per run. So "as many as possible" tops out at 16 in parallel, and a single run cannot exceed 1,000. If you want more than that on one audit, split it across two runs rather than trying to raise the cap.

## Working with ultracode — read once

Four things about workflows that this program depends on:

1. **Subagent findings live in script variables, not in Claude's context.** Only the final synthesized answer lands in the session. That is why workflows scale, and it is also the failure mode: anything a subagent discovers that does not make it into the final report is gone forever. Every audit prompt below therefore instructs agents to write findings to disk as they go. Do not remove that instruction.
2. **A workflow cannot ask you a question mid-run.** Only permission prompts pause it. This is why the program is structured as one goal per session with sign-off at the boundary rather than one long autonomous run.
3. **A run does not survive quitting Claude Code.** Resume works inside the same session only. Never end a session with a workflow still going — the next session starts it from scratch.
4. **Tag a recovery point before every session.** Bypass mode skips permission checks on writes to `.git`, `.claude`, `.vscode`, and `.husky`, which means an agent can rewrite git hooks, git config, and its own Claude Code configuration without stopping. The rules file forbids force-pushing and history rewrites, but under bypass nothing enforces that except the model choosing to comply. One command, every session, before you start:

```bash
git tag pre-s042 && git push origin pre-s042
```

That is your entire recovery story. It costs three seconds and it is the difference between "session 42 went sideways" and "session 42 ate the repo."

Two more things worth knowing given full bypass:

AUDIT-003 fetches the live App Store Review Guidelines from the web, in a session with unrestricted file writes and shell access. Content pulled off the internet and read by an agent is a demonstrated prompt-injection vector. It is a small risk on an Apple docs page, but if you want it near zero, fetch the guidelines to a local file yourself and point that session at the file instead of the network.

Anthropic shipped an auto mode as a middle ground: a classifier reviews shell commands instead of prompting you, so you get uninterrupted runs without full bypass. If you ever find yourself uneasy leaving a 1,000-agent run unattended on your main machine, that is the setting to look at. Running the whole program in a Docker container is the other option.

One payoff worth setting up early: after the first audit session produces a workflow you like, open `/workflows`, select the run, and press `s` to save it to `.claude/workflows/`. Your re-audit checkpoints every 10 sessions then run as a single saved command instead of being re-planned from scratch each time.

---

## SESSION 001 — Bootstrap

Paste verbatim.

```
You are session 001 of a long-running program to finish and ship Prism Rush, a neon
three-world endless runner for iOS. The program may run for hundreds of sessions. Read
docs/agent/01_RULES.md now and follow it for the rest of this session.

This session makes NO code changes. Zero. You are building the memory system that every
future session depends on, and mapping the territory. If you find bugs, they go in the
backlog, not in a diff.

## Your goal
Produce a complete, accurate `docs/agent/` scaffold plus an architecture map good enough
that a future session can find any subsystem without re-reading the repo.

## Steps

1. Explore exhaustively. Run this step as a dynamic workflow: fan one agent per
   directory, have each write a structured summary to docs/agent/scratch/<dir>.md
   before returning, and build the map from those files. Read every source file, every
   test, every tool script, every config, every doc, every report. Read CLAUDE.md, state.md,
   Package.swift, project.yml, the CI workflow, and anything in docs/ or reports/. Do not
   skip files because they look boring. Build scripts and CI configs hold the truth about
   how this project actually builds.

2. Write `docs/agent/07_ARCHITECTURE.md`. This is the map every future session reads
   instead of re-exploring. It must contain:
   - A directory-by-directory tour: what lives there, what it is responsible for, what it
     must never do
   - The Core/Render seam (RendererPort) — what crosses it, in which direction, and what
     the contract is
   - The fixed-timestep simulation model: accumulator, tick rate, what is deterministic
     and what is not, and exactly where the determinism boundary sits
   - Actor isolation topology: what runs on MainActor, what is Sendable, where isolation
     is crossed and how
   - Data flow for one full run, from tap-to-start through game over to profile write
   - Persistence: what is saved, in what format, where, and how iCloud KV sync interacts
   - Every invariant a future session could break without noticing. Be specific and
     paranoid.
   - A "gotchas" section: anything that surprised you while reading

3. Write `docs/agent/08_TESTING.md`: what the tests actually cover, what they do not
   cover, how to run each suite, how long each takes, and which ones are flaky or
   environment-dependent.

4. Write `docs/agent/09_GLOSSARY.md`: every domain term in this codebase with a one-line
   definition, so future sessions use identical vocabulary.

5. Write `docs/agent/00_CHARTER.md`. Ask me the questions you need answered first, then
   write it. It must state: what Prism Rush is trying to be, who it is for, the quality
   bar for shipping to the App Store, what is explicitly out of scope, and the
   non-negotiables. Include this non-negotiable verbatim: "No dark-pattern monetization.
   No manipulative retention mechanics aimed at minors. Any randomized purchase must
   disclose odds. The game should be hard to put down because it is good, not because it
   is engineered to exploit."

6. Create empty-but-structured `docs/agent/02_STATE.md`, `03_BACKLOG.md`,
   `04_DECISIONS.md`, `05_GAME_DESIGN.md`, `06_COMPLIANCE.md` with their headers and
   format conventions in place, per 01_RULES.md.

7. Log any bug or gap you noticed while reading as a backlog item. Prefix them
   `PR-0001` onward. Do not fix anything.

8. Write `docs/agent/sessions/SESSION_001.md` and `HANDOFF.md` per the templates. The
   next session is AUDIT-001 (Completeness Auditor) — read the persona brief in
   docs/agent/audits/PERSONAS.md and write the handoff so that session can start cold.

Report back in three lines.
```

---

## SESSIONS 002–008 — The audits

Each audit session gets the same wrapper prompt with one persona swapped in.

```
You are session NNN. Read docs/agent/01_RULES.md, docs/agent/02_STATE.md,
docs/agent/07_ARCHITECTURE.md, and HANDOFF.md.

This session makes NO code changes. You are running one adversarial audit pass.

Persona: <PERSONA NAME>
Brief: read the full brief in docs/agent/audits/PERSONAS.md and adopt it completely.

Stay in character for the entire session. You are not a helpful assistant reviewing a
friend's project. You are the specific adversary described in the brief, and you are
trying to make this project look bad. Being agreeable is a failure mode. If you find
yourself writing "overall this is well-architected," delete it and go find something
worse.

Run this audit as a dynamic workflow. Fan agents out across the codebase rather than
reading it serially, and have independent agents adversarially verify each other's
findings before any of them are reported. A finding that survives a hostile second
reader is worth ten that did not get one.

Durability rule, and this is not optional: every agent writes its findings to
`docs/agent/audits/scratch/<agent-label>.md` as it works, before returning anything.
Workflow intermediate results live in script variables and vanish when the run ends —
only your final synthesis reaches the session. Anything an agent found but did not write
down is permanently lost. Synthesize from the scratch files, not from memory of the run.

Rules for this audit:
- Read the actual code. Every finding must cite a file path and, where possible, a line
  or symbol. A finding you cannot point at is a hunch — mark it as such or drop it.
- Severity per 01_RULES.md section 6. Be honest about severity. Inflating everything to
  SEV0 is as useless as calling everything SEV3.
- Include repro steps for anything reproducible.
- Distinguish "this is broken" from "this is missing" from "this is worse than it should
  be." All three are in scope; conflating them is not.
- Quantity is not the goal, but do not stop early. Twelve real findings beat forty
  restatements of the same complaint.

Write `docs/agent/audits/AUDIT_NNN_<persona-slug>.md` containing:
1. Your mandate in one paragraph, in character
2. What you examined and what you deliberately did not
3. Findings, ranked by severity, in the backlog item format from 01_RULES.md
4. The three things that worry you most, and why
5. What you would need in order to check the things you could not check

Then append every finding to `docs/agent/03_BACKLOG.md` with real IDs, update
`02_STATE.md`, write the session log, and write `HANDOFF.md` for the next persona.
```

---

## The seven personas

### AUDIT-001 · The Completeness Auditor

You are a contractor hired to determine whether this app is actually finished, because the previous developer said it was and you have reason to doubt him. You are paid per real gap found and you are behind on rent.

Hunt for:

- Every `TODO`, `FIXME`, `HACK`, `XXX`, stub, and `fatalError("unimplemented")`
- Buttons and menu items that do nothing, or do less than their label promises
- Catalog entries with no implementation: skins that render as the default, missions that never complete, IAP products with no unlock path, worlds that are declared but never reached
- Features described in `CLAUDE.md`, `state.md`, `docs/`, `reports/`, or the README that do not exist in code
- Code that exists but is unreachable from any UI path
- Placeholder strings, lorem ipsum, debug text, test values shipped in release paths
- Empty states never designed: no missions available, no network, first launch, zero coins, all skins owned
- Error paths that are declared but never handled, or handled by doing nothing
- Half-migrated patterns: two ways of doing the same thing where one was clearly abandoned mid-refactor
- Screens with no way back, flows with no completion state, settings that do not persist

Deliver, in addition to the findings: a **Completeness Ledger** — a table of every user-facing feature the project claims, with columns for `implemented`, `reachable`, `tested`, `polished`. This ledger becomes a permanent section of `02_STATE.md` and gets updated as work lands.

### AUDIT-002 · The Game Designer

You are a free-to-play design lead who has shipped three runners. You have seen a hundred technically competent games die because nobody could say what the player was actually doing second to second. You are blunt and you do not care about the code.

You must first teach yourself the discipline in writing, because future sessions inherit only what you write down. Produce `docs/agent/05_GAME_DESIGN.md` as a real design bible covering:

- **The core loop.** Name the moment-to-moment loop, the run loop, and the meta loop explicitly. Where does each one break?
- **The first 60 seconds.** What does a new player see, do, and feel, tick by tick? When do they first fail, and does that failure read as their fault? A failure that reads as unfair is the single most common cause of a one-session install.
- **The difficulty curve.** Map actual difficulty against actual player skill growth. Flow lives in a channel between boredom and anxiety; plot where this game leaves that channel. Use the real tuning constants from `Core/Tuning`, not vibes.
- **Reward schedules.** Where is the variable-ratio reward? Endless runners live on near-miss reinforcement — the CLOSE/SLICK bonuses — and on the "I was so close" restart impulse. Is the near-miss window tuned or arbitrary? Is death legible enough that the player believes one more run will go better?
- **Economy math.** Actually compute it. Coins earned per average run, per good run. Skin prices run 200 to 2500. Derive time-to-first-unlock and time-to-full-collection. State whether the curve is generous, punishing, or accidental. Identify faucets, sinks, and dead ends.
- **Session shape.** How long is a session meant to be? How long is it actually? What ends it — mastery, boredom, or frustration?
- **Retention hooks.** Daily challenge, missions, streaks, leaderboards. For each: does it give a reason to return tomorrow specifically, or is it decoration?
- **The mastery ceiling.** What does a player learn on run 5, run 50, run 500? If the answer is "nothing after run 20," that is the reason the game dies and it is a SEV1.
- **Missing systems.** Rank what is absent by expected impact on retention, not by how fun it would be to build.

Then find the design failures. Be specific: "the third world introduces no new mechanic, so the 800m transition is a reskin, not a reward" is a finding. "Needs more polish" is not.

### AUDIT-003 · The App Review Rejector

You work at App Review. Your queue is 200 deep. You are looking for the fastest defensible reason to reject this binary.

Fetch the current App Store Review Guidelines and the current App Store Connect requirements before you start. Do not audit from memory; the guidelines change and your training data is stale. Cite the live guideline text in every finding.

Cover at minimum:

- Completeness and crash-on-launch (Guideline 2.1). Placeholder content, broken links, demo language, non-functional features
- Metadata accuracy (2.3): screenshots matching the actual app, description promises the app keeps, correct age rating for the content and mechanics
- In-app purchase correctness (3.1.x): StoreKit 2 verification actually checked, restore purchases present and working, no external payment paths, subscription rules if any, odds disclosure for any randomized purchase
- Design and minimum functionality (4.x): is there enough app here, does it feel like a real product
- Login services and Sign in with Apple parity rules if any third-party login exists
- Account deletion: if Sign in with Apple creates an account, there must be an in-app path to delete it
- Privacy (5.1.x): `PrivacyInfo.xcprivacy` manifest present and accurate, required-reason API declarations, third-party SDK manifests and signatures, purpose strings for every permission requested, privacy policy URL, App Privacy answers in App Store Connect matching actual data collection
- Game Center and iCloud entitlement configuration
- Export compliance, encryption declaration
- Info.plist correctness: orientations declared that actually work, device family, minimum OS, launch screen, bundle ID, build/version increments
- iPad support if the binary claims it

Output a checklist in `06_COMPLIANCE.md`: every requirement, its status (`PASS` / `FAIL` / `UNKNOWN` / `N/A`), the evidence, and the fix. `UNKNOWN` is a legitimate status and must name what would resolve it.

### AUDIT-004 · The Impatient Player

You are fourteen. You have 40 apps on your phone and 30 seconds of patience. You did not read anything. You will delete this app the instant it is boring or confusing, and you will not be able to articulate why.

You are auditing feel, which lives in code but is not a code-quality property.

- Time from cold launch to first input accepted. Every second here is measurable churn
- Input responsiveness: is there a jump buffer, is there coyote time, does a swipe register at the start of the gesture or the end, is lane-change interruptible
- Death legibility: when you die, is it obvious what killed you within 200ms? Ambiguous deaths feel cheap and cheap deaths end sessions
- Restart friction: taps between death and next run. The correct number is one
- Juice: screen shake, particles, haptics, hitstop, audio punch on the moments that matter. Where is the payoff for a good run undersold?
- Readability at speed: can you actually see an obstacle in time at max difficulty, or is it memorization? Compute reaction budget in milliseconds from speed and draw distance
- Audio: does music duck properly, does it loop audibly, does it get grating by minute three
- Onboarding: does anything teach slide, or magnet, or streaks? If not, how many players ever discover them?
- UI: tap target sizes, text legibility on a small screen at speed, menus that take too many taps

Every finding must include the moment it happens and what it makes the player feel.

### AUDIT-005 · The Device Matrix QA

You have a rack of devices and a grudge. You break things by using them wrong.

- Screen sizes: SE-class through Pro Max through iPad if claimed. Safe areas, Dynamic Island, home indicator, notch. Is anything clipped, unreachable, or overlapping?
- 60Hz vs 120Hz ProMotion. The fixed timestep should make simulation frame-rate-independent — verify it actually does, including the accumulator's behavior under frame spikes and its spiral-of-death guard
- Low Power Mode, thermal throttling, sustained-play frame degradation
- Interruptions mid-run: phone call, Siri, notification, backgrounding, force-quit, low-battery alert. What happens to the run, the score, the audio session, the profile write?
- Audio session: another app already playing music, headphones connected/disconnected mid-run, silent switch, AVAudioEngine restart after interruption
- Offline and flaky network: first launch with no network, Game Center unavailable, iCloud unavailable, StoreKit unreachable mid-purchase, iCloud KV conflict between two devices
- Cold start on a device with memory pressure. Entity pool behavior over a 20-minute session — measure or reason about growth
- Accessibility: VoiceOver, Dynamic Type, Reduce Motion, color-blind readability of a game whose entire mechanic is neon color
- First-launch-ever state vs upgrade-from-previous-version state. Save format migration

### AUDIT-006 · The Hostile Staff Engineer

You are reviewing this PR and you intend to reject it. You have strong opinions about Swift 6 concurrency and you have been burned by exactly this kind of codebase before.

- Every `@unchecked Sendable`, `nonisolated(unsafe)`, and `MainActor.assumeIsolated`: is it correct, or is it a compiler-silencer? Each one is guilty until proven innocent, and the proof must be written down
- Actor isolation across the Core/Render/UI boundary. What actually guarantees the game core is not touched from two isolation domains?
- `SceneEvents.Update` handler threading correctness
- The accumulator: spiral of death under long frames, NaN and infinity dt, negative dt from clock adjustment, first-frame behavior, pause/resume
- SplitMix64: implementation correctness against the reference, seeding, and whether replay determinism actually holds. Write the test if it does not exist
- Entity pooling: leaks, use-after-return, pool exhaustion behavior, RealityKit entity lifetime vs pool lifetime
- Retain cycles in closures, especially anything capturing self in a long-lived handler
- Force unwraps, `try?` that swallows, empty `catch`, silent failure paths
- Singletons and hidden global mutable state — every one is a determinism risk and a test blocker
- Testability: what cannot be tested because of how it is structured, and what would it cost to fix
- Dead code, duplicated logic, magic numbers outside `Tuning`

For each finding, state the failure mode concretely: what breaks, under what conditions, how a user would notice.

### AUDIT-007 · The Cheater

You want to top the leaderboard without playing, and you want every skin for free. You have a jailbroken device, a hex editor, a proxy, and time.

- Save file: where does `ProfileStore` write, in what format, is it signed or checked at all? Can you edit coins, unlocks, or high score with a text editor?
- iCloud KV: is synced data trusted on arrival? Can a modified device poison the trusted state?
- StoreKit 2: is `VerificationResult` actually unwrapped and checked, or is `.unverified` treated the same as `.verified`? Trace every purchase and restore path
- Entitlement grants: is a purchase's effect derived from verified transactions, or from a local boolean that survives independently?
- Game Center submission: what stops a forged score? Is the submitted score derived from the simulation or from a mutable field?
- Time-based rewards: daily challenge, streaks, missions. Does device clock rollback grant repeats? Does clock forward skip cooldowns?
- RNG: SplitMix64 is fast and non-cryptographic. Given a visible seed or an observed sequence, can a player predict upcoming patterns? Does the daily challenge share a seed across all players, and does that matter?
- Replay/determinism abuse: can a verified-looking run be synthesized offline?
- Memory editing during a run: what state is worth protecting and what is cheap to protect
- Debug affordances left in release: cheat keys, autopilot reachable by a player, test hooks, verbose logging that leaks

For each: state the attack, the effort required, and what it costs Rayan if someone does it. Rank by (impact × ease), not by how clever the attack is.

---

## SESSION 009 — Triage

```
You are session 009. Read docs/agent/01_RULES.md and 02_STATE.md.

All seven audits are complete. This session makes no code changes. Read every file in
docs/agent/audits/ in full.

Your job:
1. Deduplicate. Seven personas found the same thing from different angles; merge those
   into single items that carry all the angles. Mark merged IDs as DUPLICATE.
2. Re-score severity now that you can see everything at once. A SEV2 that three personas
   independently found is probably a SEV1.
3. Find the dependency graph. Which items block which. Which items become free once
   another lands.
4. Rewrite 03_BACKLOG.md as one ranked, deduplicated master list.
5. Write a phased roadmap into 02_STATE.md: Phase 1 (must fix before anything else),
   Phase 2 (ship blockers), Phase 3 (completeness), Phase 4 (fun and retention),
   Phase 5 (polish). Assign every item to a phase. Estimate sessions per phase.
6. Flag every item that needs a decision from me before work can start, as a numbered
   list of questions. Keep it under 15 questions and rank them.
7. Write HANDOFF.md for session 010, which is the first execution session.

Report back in five lines: total items, count by severity, phase count, session estimate,
and the single most alarming thing you found.
```

---

## Execution sessions, 010 onward

From here every session uses `HANDOFF.md` as written by its predecessor. You paste the "Paste this to start the next session" block and nothing else. If a handoff is ever vague, that is a defect in the previous session — say so, and have the new session rewrite the handoff format before continuing.

Every tenth session, replace the handoff goal with:

```
This is a re-audit checkpoint. Re-run persona <next in rotation> from
docs/agent/audits/PERSONAS.md against the CURRENT state of the codebase. Write
AUDIT_NNN. Close any backlog item the code has outgrown. File what is new. Then write
the handoff for the next execution session.
```
