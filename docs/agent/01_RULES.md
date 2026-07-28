# Prism Rush — Agent Operating Rules

**Read at the start of every session.** Kept short on purpose: every line costs context that could
have gone to the code.

> **Revised by session 003 on Rayan's instruction (2026-07-28).** The previous version was ~290
> lines of process ceremony written before anyone had run this program. Most of it was slowing work
> down rather than protecting anything. It has been cut hard.
>
> What follows is split into **judgment** (how to work — advisory, use your head) and
> **invariants** (a short list that protects the product, not the process). If a rule here is ever
> getting in your way, say so and change it. That instruction is from Rayan directly and it
> outranks anything written below.

---

## 0. The one thing that actually matters

Your context dies at the end of this session. The only thing that crosses the boundary is what you
write to disk. Treat `docs/agent/` as your memory, not as documentation for humans.

A session that ships a great fix and leaves a vague handoff has cost the next session more than it
gained. Budget real time for the handoff.

---

## 1. Where things live

| File | Purpose |
|---|---|
| `00_CHARTER.md` | What the product is trying to be. Rayan's, not yours. |
| `01_RULES.md` | This file. |
| `02_STATE.md` | Single source of truth for *right now*. If it and another file disagree, this wins. |
| `03_BACKLOG.md` | Every known defect, gap and idea. |
| `04_DECISIONS.md` | Decision log. **Append-only** — never edit or delete an entry. |
| `05_GAME_DESIGN.md` | The design bible: loops, curve, economy, retention. |
| `06_COMPLIANCE.md` | App Store readiness. |
| `07_ARCHITECTURE.md` | Codebase map, seams, gotchas. §11 is the where-to-look table. |
| `08_TESTING.md` | What is covered, what is not, how to run it. |
| `09_GLOSSARY.md` | Shared vocabulary. |
| `sessions/SESSION_NNN.md` | One session's log. Write-once. |
| `audits/AUDIT_NNN_*.md` | One audit pass. Write-once. |
| `HANDOFF.md` (repo root) | The literal prompt for the next session. Overwrite every session. |

Never let two files disagree about the same fact. If you're copying a paragraph into a second file,
one of them should hold a pointer instead.

---

## 2. How to work — judgment, not law

**Start** by reading `HANDOFF.md`, `02_STATE.md`, and whatever `07_ARCHITECTURE.md §11` points at
for your task. Don't re-explore the repo; that's what the map is for. If the map is wrong, fix it.

**Tag a recovery point** — `git tag pre-sNNN`. Three seconds, and it's the whole recovery story
under bypass permissions.

**Work in small commits.** `[S-NNN][PR-0123] imperative summary`; the body explains *why*.

**Verify before you claim.** See §3 — this is the part that is not advisory.

**Finish by** updating `02_STATE.md`, filing/updating backlog items, writing the session log, and
writing `HANDOFF.md`. A handoff that says "continue improving the game" is a failure. One that names
a goal, four files, two traps and one invariant is doing its job.

**On scope:** you will find problems outside your goal constantly. Default to filing them rather
than fixing them — not because fixing is forbidden, but because a session that does five unrelated
things produces a diff nobody can review and a handoff nobody can trust. If a fix is genuinely
small, genuinely related, and you can verify it, just do it and say so in the log.

**On context:** when you're running low, stop taking on new work and spend what's left on
verification and the handoff. Don't start a determinism-affecting change on fumes.

**On sizing:** one clear goal per session is a good default, not a cage. If the goal turns out to be
three goals, say so and pick the one that unblocks the most.

---

## 3. Verification — this part is not advisory

**Run the app before claiming behaviour works.** This is the rule with the best track record in the
program and it stays:

- Session 001 filed 181 findings from static reading, then found a money bug fifteen minutes after
  first launching the app.
- Session 002 killed four of its own findings by running the build.
- Session 003 refuted three inherited claims and one of its own in the first hour on device.

```bash
./Tools/build.sh                                    # ~2 min
xcrun simctl boot 10C15FE0-3D9A-40D5-9E45-C0702E906DF3
xcrun simctl install 10C15FE0-3D9A-40D5-9E45-C0702E906DF3 .dd/Build/Products/Debug-iphonesimulator/PrismRush.app
xcrun simctl launch 10C15FE0-3D9A-40D5-9E45-C0702E906DF3 com.rayancheca.prismrush
```

Then **open the screenshot and look at it.** A captured PNG nobody read is not evidence.
For a true first-launch state you must `simctl uninstall` then `install` — `PR_FIRSTRUN` does not
reset the profile.

**Paste real command output into the session log.** No output, no credit. If something genuinely
can't be verified here (needs a device, App Store Connect, a real purchase), mark it
`VERIFY-PENDING` and add a line to `02_STATE.md` under "Needs Rayan on a device." Never claim done
on the strength of reasoning alone.

**Never make the gate pass by cheating it:** deleting or skipping a test, lowering a threshold,
adding `@unchecked Sendable`, adding `MainActor.assumeIsolated` to silence an isolation error,
`try?` to swallow, `#if DEBUG`-ing a failure away, or suppressing a warning. Each of those is a
finding to log, not a fix to apply.

**Know what your tests actually cover.** `swift test` compiles only `Core/`, seven `Meta/` files and
`Audio/Synth.swift`. It does **not** compile `UI/`, `Render/`, `IAP/`, `SynthEngine`, StoreKit or
GameKit. A green SPM run says nothing about any of those. Only a Mac build does.

---

## 4. The invariants

Short list. These protect the product, not the process. Each one is here because breaking it causes
damage you would not notice until much later.

1. **Determinism.** All randomness goes through the seeded `SplitMix64` plumbed from
   `startRun(seed:)`. No `Double.random`, no `Date()` in `Core/`. A seed must fully determine a run.
2. **Spawn changes carry two obligations.** Any change to the spawner, patterns, or RNG consumption
   must (a) keep `SolvabilityBotTests` green — 200 seeds × 6,000 m plus the 12,000 m soak — and
   (b) bump `DailyChallenge.layoutVersion` and repin the `DailyChallengeTests` goldens. Consuming
   one extra `rng.unit()` anywhere in the spawn path silently changes every seeded run for every
   player. *This is the one that looks like bureaucracy and isn't.*
3. **`Core/` never imports a renderer or UIKit.** It meets the outside world only through
   `RendererPort`, `GameSnapshot` and `FXEvent`. Foundation only.
4. **`Profile` fields decode as `decodeIfPresent ?? default`.** Old saves must never fail to load or
   silently wipe. Adding a field means giving it a default and deciding its merge policy in the same
   edit.
5. **Economy payouts stay per-death deltas** (`max(0, cumulative − awarded)`), `applyRunSummary`
   once per run, reward timestamps clamped against clock rollback. Don't reintroduce cumulative
   re-pays.
6. **G3 — never `@State` a shared `@Observable`; never snapshot `store.profile` into a `let` at the
   top of `body`.** Reference `ProfileStore.shared` / `IAPManager.shared` directly in `body`. This
   exact anti-pattern shipped three v1.0 bugs.
7. **Swift 6 strict concurrency stays `complete`.** Follow the existing `MainActor.assumeIsolated`
   pattern for main-delivered non-isolated callbacks; don't introduce `Task.detached`,
   `DispatchQueue`, or `@unchecked Sendable`.
8. **Never force-push, never rewrite published history, never `git add -A` without reading the
   diff.** Under bypass permissions nothing stops you but you.
9. **Build config lives in `project.yml` only.** `*.xcodeproj` and `PrismRush.entitlements` are both
   regenerated by xcodegen.

Everything else in this repo that reads like a rule is a *default*. Use your judgment.

---

## 5. Backlog

One block per item. IDs never get reused.

```
### PR-0142 · SEV1 · Run state corrupts when backgrounded mid-run
- Area / Status / Symptom / Repro / Why / Impact / Fix sketch / Blast radius / Verification
```

Use the full shape when an item is likely to be picked up soon; a one-line row is fine for the long
tail. Expand a row to the full block before working it. **Don't file an item just to satisfy a
format.**

**Status:** `OPEN` · `IN-PROGRESS(S-NNN)` · `DONE(S-NNN)` · `VERIFY-PENDING(S-NNN)` ·
`WONTFIX(D-NNN)` · `DUPLICATE(PR-NNNN)`

**Severity is about consequence, not effort.** A one-character fix can be SEV0.

| | Meaning |
|---|---|
| SEV0 | Crash, data loss, money bug, guaranteed rejection, determinism break |
| SEV1 | Core function missing or broken. A player notices and quits |
| SEV2 | Feel, balance or polish that measurably changes whether players come back |
| SEV3 | Code health, tests, architecture, docs |
| SEV4 | Parking lot |

---

## 6. Multi-agent work

Fan out when the task is genuinely wide (an audit, a migration, a sweep). Don't orchestrate three
agents to change one constant.

**The one hard part:** a workflow's intermediate results live in script variables and are destroyed
when the run ends. Every agent must write its findings to `docs/agent/audits/scratch/<label>.md`
*before returning*, and you synthesize from those files. Anything an agent found and didn't write
down is gone.

**Have findings adversarially verified.** Session 003 raised 124 findings and killed 32 of them with
independent hostile second readers — including one of its own, and one attack on its own
measurement instrument. A finding that survives a hostile reader is worth ten that didn't get one.

Never end a session with a workflow in flight; runs resume only inside the same session.

**`docs/agent/scratch/` and `docs/agent/audits/scratch/` are gitignored and hold ~1.5 MB of working
detail.** They will not survive a clone, and git will not move them between worktrees — `cp -R` them
by hand if you work in a new one.

---

## 7. Reporting to Rayan

Three lines at the end: what got done, what's next, what needs him specifically. Everything else
goes in the files.

Flag immediately, mid-session, if you find a SEV0, need a decision only he can make, or think the
plan is wrong.
