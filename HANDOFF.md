# HANDOFF → Session 010

## Paste this to start the next session

```
You are session 010 of a long-running program to finish and ship Prism Rush, a neon three-lane
endless runner for iPhone (Swift 6, SwiftUI, RealityKit, zero dependencies, zero binary assets).

Read docs/agent/01_RULES.md, then docs/agent/02_STATE.md, then this file.

You may and should change code. Rayan's standing instruction is "never be limited by arbitrary
rules, just work however you think is best." Do not ask permission to fix something you can verify.

Direction: App Store submission IS the goal, timing is open, and Rayan wants the app POLISHED first.
Design and feel outrank compliance right now.

YOUR JOB, in priority order. Rayan has ALREADY ANSWERED the design questions — do not re-ask:

  1. THE STUMBLE. He asked for it directly: "functionality like subway surfers where you basically
     have two lives. if you half hit a wall you slow down for a sec... not two lives per say more
     like 1.5." Design + measured numbers are in docs/agent/audits/scratch/s009b_BRIEF.md §5 and
     s009b_probe_stumble.md. His rulings: a Warden beam STUMBLES the first time and KILLS the second
     ("stumble first then kill"), and a stumble RESETS the multiplier.
  2. THE WARDEN IDENTITY PASS. Full implementation spec, already written and adversarially checked:
     docs/agent/audits/scratch/s009c_SPEC.md. It answers his verdict verbatim — "its just a basic
     triangle. no animations. nothing to tell you what it is or what it does. no screen shake. no
     effects. same every time. same functionality every time." Build order is in §6 of that spec;
     the first two steps alone fix four of his six complaints.
  3. THE POST-KILL DEAD AIR. Measured: 5.4–10.4 s of empty deck after the fight, and the LONGEST
     hole belongs to the WEAKEST player. Structural, not a tuning miss — a variable-length fight
     inside a fixed-length arena. Options and costs in s009b_BRIEF.md §1 item 5 and
     s009b_probe_pacing.md. This is the ONE item that costs a layoutVersion bump. Get his call
     before spending it.

READ THESE FOUR SCRATCH FILES FIRST — ~200 KB of already-done work, and they are gitignored:
  docs/agent/audits/scratch/s009b_BRIEF.md          the decision brief he answered
  docs/agent/audits/scratch/s009c_SPEC.md           the identity/presence implementation spec
  docs/agent/audits/scratch/s009b_probe_stumble.md  the stumble geometry, measured
  docs/agent/audits/scratch/s009b_probe_pacing.md   the dead-air arithmetic

FIRST COMMAND, before anything else. docs/agent/scratch/ and docs/agent/audits/scratch/ are
gitignored and hold ~200 MB from nine sessions. Git does NOT move them between worktrees. No-op if
you already have them:

  for w in "" .claude/worktrees/prism-rush-spawn-path-c7d88a \
           .claude/worktrees/prism-rush-design-audit-562d27 \
           .claude/worktrees/prism-rush-audit-91c7ba; do
    s="/Users/rayankarimcheca/Desktop/ClaudeProjects/projects/prism-rush-ios/$w/docs/agent"
    [ -d "$s/scratch" ] && mkdir -p docs/agent/scratch && cp -Rn "$s/scratch/." docs/agent/scratch/ 2>/dev/null
    [ -d "$s/audits/scratch" ] && mkdir -p docs/agent/audits/scratch && cp -Rn "$s/audits/scratch/." docs/agent/audits/scratch/ 2>/dev/null
  done; du -sh docs/agent/scratch docs/agent/audits/scratch

If both are empty, say so in your report rather than working blind.

BUILD AND RUN THE APP BEFORE YOU CLAIM ANYTHING WORKS. That rule is now nine for nine, and S-009 is
the sharpest example yet: it shipped a gun beam that compiled, was wired, passed 218 tests, and
rendered as a sliver pointing at nothing — because a comment asserted a mesh's axis without reading
the six lines it described. `swift test` compiles Core/, seven Meta/ files and Audio/Synth.swift.
It does NOT compile UI/, Render/, IAP/, StoreKit or GameKit.

Report back in three lines.
This file's absolute path: /Users/rayankarimcheca/Desktop/ClaudeProjects/projects/prism-rush-ios/HANDOFF.md
```

---

# What session 009 did

Rayan played the Warden and rejected it twice, on two different axes. Both were answered.

**Round 1 — "its too easy. its just three hits and takes no effort to pass."**
The cause was structural: `Collisions.wardenBeamHit` took no Y parameter, so jump and slide were
*provably inert* inside a fight. The boss asked for one of the player's four verbs, three times,
with an 0.85 s wind-up, and 60% of the time left two safe lanes.

A strike now takes one of three shapes with **disjoint** answers — LANCE (change lane), FLOOR (jump),
CURTAIN (slide). The load-bearing decision is that **the curtain has no ceiling**: the obvious build
reuses `barKillTop`, and that makes the floor's clearance window a strict *superset* of the bar's, so
one jump answers both, slide becomes optional, and the ladder collapses back to the binary the owner
rejected — with the solvability bot certifying the degenerate strategy. Unbounded above it cannot be
jumped from any state (apex 2.1608; sliding at apex the body top is still 2.607).

Plus rank (worlds 3/6/9 → telegraph 0.80/0.75/0.70, hits 4/5/6 — `world` previously drove nothing but
the RNG seed), an escalating double-lance (measured 70.8%, was a flat 40%), and bar-watch cut from
6.25 s to 4.71 s. `LaggedAutopilotTests` is the new two-sided gate: a 0.40 s human reaction must
survive every encounter, a 0.75 s one must die. Both directions pass.

**Round 2 — "it really makes no sense... no animations... same every time."**
A 14-agent brainstorm reframed it: **the encounter was fully built in the simulation and only
sketched in the presentation.** Every causal link existed in code; almost none existed on screen.
Three of the four proposed reconceptions were killed by the stress pass — the recommendation was a
presentation pass, not a redesign, and that is what shipped (eleven fixes, `21dacc8`).

**Also done, both owner-raised mid-session:** the splash's diffused box → the shared stage ring
(`CharacterStageRing`, now one implementation shared with the hub hero), and the in-run HUD's four
different chip geometries → one `StatusChip` at a single fixed width.

Tests: **209 → 218 SPM, 0 failures.**
Commits: `7331d1e`, `7d99d12`, `b6b9ba0`, `21dacc8`, `2185c18`.

---

# Things you would otherwise rediscover the hard way

- **`ProceduralMesh.beam` fans along +Y in the XY plane, with every vertex at z 0.** It is for
  camera-facing decor cards. Scaling it on Z does nothing. Use `beamAlongTrack` for anything running
  down the track. S-009 got this wrong and shipped it for one commit.
- **The Warden fight is over before a shell-driven screenshot lands.** `PR_WARDEN=1` starts the run
  in `onAppear`, so the ~12 s encounter resolves behind the splash. `simctl io screenshot` throttles
  the sim hard — useful for stepping *through* a fight, useless for *reaching* one. The reliable
  capture is `PR_AUTOPLAY=1`, tap once, then **sleep ~95 s untouched** before screenshotting: the bot
  survives, so no game-over panel covers the evidence.
- **`swift test` compiles neither `UI/` nor `Render/`.** Every S-009 render bug was invisible to a
  green 218-test run. Only `./Tools/build.sh` plus eyes catches them.
- **Adding a `Mission.Metric` case is the good kind of breaking change** — three exhaustive switches
  (`MissionsView`, `MissionsTests`, `ProgressionTests`) refuse to compile until each handles it.
- **SourceKit in this checkout resolves against macOS.** `Theme` / `GameCore` / `UIKit` /
  `PowerUpKind` "errors" are noise. Believe `./Tools/build.sh`.
- **Derive layoutVersion goldens in Python and reproduce the EXISTING pins first.** S-009 did this
  for the charge threshold — the old model reproduced 0.804 with 0.85 ✓ and 0.75 ✗ before the new
  0.744 was trusted. That reproduction is the only reason the new number is believable.
- Never drive the simulator while `xcodebuild test` runs — concurrent installs crash the host.
- `state.md` (58 KB) and `README.md` (35 KB) at the repo root are history, not truth.

---

# Current state in one paragraph

Prism Rush is a v1.9 feature-complete iPhone game that has never been submitted: ~100 Swift files,
zero dependencies, zero binary assets but a generated icon, **218 SPM tests green**, and a genuinely
deterministic core behind a clean `RendererPort` seam. `DailyChallenge.layoutVersion` is **still 10**
— S-009 spent its difficulty on the fight and not on the deck, deliberately, so the pre-armed v11
golden is **unspent**. `PR-0401` (the coin sink buys nothing that alters play) is **still open**:
Countermeasures remain unbuilt, though the shield-absorb fix delivers the design doc's "Ion Shield"
using a pickup that already exists. Backlog 263 items, 25 DONE. Five audits remain unrun.

# Rayan action items (surface them; do not try to do them)

1. **PLAY IT AGAIN.** The fight now demands all four verbs, the craft is ~4× bigger and clear of the
   horizon, its shots come from it, and damage visibly leaves the player. Does it read at speed?
2. **The gun beam has never been seen working.** It was broken, then fixed, and the shield phase is
   4.7 s — shorter than a tap-to-screenshot round trip. Ten seconds of his eyes settles it.
3. **The post-kill dead air needs his call** — the only change here that costs a layoutVersion bump.
4. **Is the first Warden hard enough now?** Rank 1 is 4 answers; `wardenCoreHitsByRank` is one edit.
5. Carried: the slide SFX (S-006), act two, the chasm, the hub redesign. All still need his thumbs.
6. **The `Double Coins` IAP description in App Store Connect** — correct it to
   `Every run pays 2× coins. Forever.` before submission.

# Open questions for Rayan (carried until answered)

- **PR-0040** — the music is a 1.82 s loop for the whole session, pinned to world 0 by his decree.
- **PR-0052** — is the Daily Challenge a *layout* guarantee or an *identical-experience* guarantee?
  The dead-air fix in action item 3 turns on this answer.
- **PR-0010** — `Store/metadata.md` sells a three-world game; the binary ships twelve families.
- **PR-0254** — should a run that used a paid revive be leaderboard-eligible? S-003 recommends
  counting it for missions/XP but not the leaderboard. Needs a yes/no.
- **Coin income is uncapped** — four independent components, none of them the score multiplier. He
  said "infinite coins" and was right about the symptom; the multiplier was the wrong suspect (it
  multiplies `bonus` only and never touches coins). If he wants income slowed, the levers are gem
  density, the distance divisor, or the style-coin rate.

# Resolved in session 009

Warden difficulty (three shapes / rank / escalating lance), the splash ring, the HUD chip system,
the shield pickup mesh, eleven Warden coherence fixes, and three staging bugs found by the identity
design pass. **Owner decisions on record this session:** a Warden EXPLODES rather than peeling away;
the shield phase STAYS but must be drawn; a beam STUMBLES first and KILLS second; per-world
antagonists are wanted.
