# HANDOFF → Session 007

## Paste this to start the next session

```
You are session 007 of a long-running program to finish and ship Prism Rush, a neon three-lane
endless runner for iPhone (Swift 6, SwiftUI, RealityKit, zero dependencies, zero binary assets).

Read docs/agent/01_RULES.md, then docs/agent/02_STATE.md, then this file.

You may and should change code. 01_RULES.md is split into judgment (advisory) and nine invariants
(damage prevention). Rayan's standing instruction is "never be limited by arbitrary rules, just
work however you think is best." Do not reinstate ceremony. Do not ask permission to fix something
you can verify.

Direction: App Store submission IS the goal, timing is open, and Rayan wants the app POLISHED
before publishing. Design and feel outrank compliance right now.

Your goal is the Phase 3 failure-state sweep (02_STATE.md worry #1): every failure state in the
app fails identically — raw, silent, or actively misleading. Store not loaded, not enough coins,
empty mission board, signed out of Game Center, nothing to restore, a purchase awaiting parental
approval. The happy path is polished; the moment anything is not normal the app stops looking
finished. The good news is that the correct pattern already exists in this codebase — the Worlds
UnlockPanel and the revive offer both show "NEED N MORE" plus a route to coins. Most of this job is
"use the pattern you already wrote." Items: PR-0302 / 0304 / 0305 / 0306 / 0308 / 0311 / 0314 /
0315, and read PR-0304 first (a 0/N mission board that says "ALL CLEAR" at first launch).

Build and RUN the app before you claim anything works. That rule is six for six at catching things
static reading missed — session 006 shipped a chasm that was invisible on the simulator TWICE
before it read. `swift test` green is NOT the app working: it compiles Core/, seven Meta/ files and
Audio/Synth.swift, and none of UI/, Render/, IAP/, StoreKit or GameKit.

FIRST COMMAND, before anything else. docs/agent/scratch/ and docs/agent/audits/scratch/ are
gitignored and hold ~45 MB of working detail from six sessions, including every hub screenshot
PR-0452 was argued with and every chasm capture PR-0450 was corrected by. Git does NOT move them
between worktrees. This copies them from wherever they still exist and is a no-op if you already
have them:

  for w in "" .claude/worktrees/prism-rush-spawn-path-c7d88a \
           .claude/worktrees/prism-rush-design-audit-562d27 \
           .claude/worktrees/prism-rush-audit-91c7ba; do
    s="/Users/rayankarimcheca/Desktop/ClaudeProjects/projects/prism-rush-ios/$w/docs/agent"
    [ -d "$s/scratch" ] && mkdir -p docs/agent/scratch && cp -Rn "$s/scratch/." docs/agent/scratch/ 2>/dev/null
    [ -d "$s/audits/scratch" ] && mkdir -p docs/agent/audits/scratch && cp -Rn "$s/audits/scratch/." docs/agent/audits/scratch/ 2>/dev/null
  done; du -sh docs/agent/scratch docs/agent/audits/scratch

If both are empty, say so in your report rather than working blind.

Report back in three lines.
This file's absolute path: /Users/rayankarimcheca/Desktop/ClaudeProjects/projects/prism-rush-ios/HANDOFF.md
```

---

# What session 006 did

**PR-0450 is DONE — the catalogue is 15 patterns and the ladder has six tiers.** Plus two owner
requests that arrived mid-session and outranked the backlog: the slide SFX and Prism's shimmer.

## 1. THE CHASM (PR-0450)

A full-width 8 u gap in the deck. `EntityKind.chasm`, pattern 14, tier six at **2,560 m**,
`layoutVersion` **8 → 9** (a v10 pin is pre-armed).

It is a new *kind* of moment, not a recombination: the first obstacle with an EXTENT rather than a
plane, and the first **two-sided timing window** in the game. Every other jump is one-sided — clear
a plane, and going early is free — so nothing until now punished jumping too *soon*. The gap is
centred on the APEX of the jump its gem arc cues, which is what makes the slack symmetric at
~±0.25 s at every speed.

**Measured step** (`DifficultyCurveTests`, 64 seeds): 0.00 chasm/km through 2,560 m, then 1.84/km,
rising to 2.20/km at depth. Below the gate it is not rare, it is *impossible*. Act two's own density
escalation is intact (6.06 → 6.33 → 6.96 → 7.36 obst/100 m; rest 18.0% → 9.0%).

Iron rule 4's "moving walls stay LAST" shorthand is **amended** in `CLAUDE.md`, not routed around:
moving walls are the last entry of tier FIVE (index 13, still exclusive to it), the chasm is index
14, and the rule's real content — every tier is a prefix — is unchanged.

## 2. The slide SFX (PR-0454) and PR-0320

Rayan: *"so harsh and horrible."* Two structural causes — the noise burst hit full amplitude on
sample 0 (an instantaneous broadband onset is a click), and a 6 dB/oct filter at 600 Hz still passes
plenty of 2–5 kHz. `Synth.noise` gained `attack` and `poles` (both defaulted, so every other caller
is byte-identical). **PR-0320 was live and worse than filed:** `swell:` was declared and never
applied — all four callers asking for a rising whoosh got a dying one. `.slid` is now edge-triggered
(the bot re-armed it every tick → 120 overlapping sounds/second in autoplay).

## 3. Prism holds one identity (PR-0455 / D-009)

Rayan: *"why does the character change colours as it runs."* **Nothing was reverted** — no character
code had been touched, and 23 of 24 skins were always fixed. Prism's 8 s cyan→magenta→amber shimmer
landed in v1.4.2 and S-005 recorded it as decree-compliant *because it is world-blind*. That reading
was too literal. **Decree 1 now covers space AND time.** The shimmer machinery is deleted, not
disabled.

---

# Things you would otherwise rediscover the hard way

- **You cannot see into a hole from this camera.** The chase camera is low enough that depth cues
  arrive long after a jump must be committed. The chasm reads because an opaque lid at y 0.045
  **interrupts the deck's neon grid** — the track visibly stops for 8 m. Two earlier versions
  (near-black well; then visibly-walled well) were both invisible on the simulator and read as two
  gold stripes, i.e. as a bar to SLIDE under. If you add any floor feature, the grid is your canvas.
- **`ProceduralMesh.build` falls back to a plain SPHERE on a bad descriptor** — no log, no crash, no
  test failure. And nothing sets `faceCulling`, so a CW-wound face is silently invisible. The chasm
  double-winds every face for exactly this reason.
- **`obstacleX` indexes `Tuning.laneX[e.lane]` in its `default:` arm.** Any new full-span obstacle
  that forgets to join the `.bar, .splitBar, .chasm` case crashes on `laneX[-1]`.
- **Core has six `default:` clauses that will silently accept a new obstacle kind** and make it
  decorative, non-lethal, and invisible to the solvability bot: `obstacleX`, the collision dispatch,
  the near-miss switch, `freeLaneNear`, `Autopilot.decide`, `Spawner.isObstacle`. The RENDER seam is
  safe (two exhaustive switches); the CORE seam is not. Full map in
  `docs/agent/audits/scratch/s006_scout_*.md` — four detailed ground-truth files with file:line
  citations for GameCore, Render, the tests, and the bot. Read them before any Core/Render change.
- **A green solvability bot proves nothing if it never met the hazard.**
  `testTheSoakActuallyDrivesTheBotAcrossChasms` exists to keep that honest. Copy the pattern.
- **`DifficultyCurveTests` counts input EDGES, not input precision.** A chasm costs one jump exactly
  like a low, but with a ±0.25 s window against ±0.64 s. The instrument *undervalues* it. Do not
  tune against those numbers without reading D-010.
- **Derive `layoutVersion` goldens in Python** from the SplitMix64 constants and reproduce the
  existing pins first — never read them off the Swift they pin. They live in TWO places
  (`DailyChallengeTests` **and** `MissionsTests.testTodaysChallengeSeedMatchesUTCGoldens`).
- **New launch hook `PR_CHASM=1`** drops a chasm at the spawn horizon so tier six is inspectable
  without running 2,560 m. Combine with `PR_WORLD=9 PR_AUTOPLAY=1 PR_SKIP_SPLASH=1`.
- **`PR_HUBDEEP=1`** (S-005) pins a late-game profile for hub work. `PR_FIRSTRUN` does NOT reset the
  profile — only `simctl uninstall` gives a true first launch. The splash never auto-dismisses
  (`PR_SKIP_SPLASH=1`).
- **SourceKit in this checkout resolves against macOS, not iOS** — a wall of "No such module 'UIKit'"
  and "only available in macOS 15.0" on files that compile fine. Believe `./Tools/build.sh`.
- **Test counts, measured at S-006: 198 Xcode unit + 11 XCUITest = 209, and 191 SPM.**
- **`cd` inside one Bash call persists into the next**, and `rm -f dir/*.png` aborts a zsh `&&` chain
  when nothing matches. S-006 lost a build to the first of those. Use absolute paths.
- **Never drive the simulator while `xcodebuild test` runs on it** — concurrent installs crash the
  test host and report a false TEST FAILED.
- **`Tools/qa.sh` and `Tools/screenshots.sh` hardcode this machine's UDIDs and fail silently via
  `|| true`** (PR-0050). A green run may mean nothing ran.
- `state.md` (58 KB) and `README.md` (35 KB) at the repo root are history, not truth. Where they
  disagree with `02_STATE.md`, `02_STATE.md` wins.

---

# Current state in one paragraph

Prism Rush is a v1.8, feature-complete, technically strong iPhone game that has never been submitted
to the App Store: ~95 Swift files, zero dependencies, zero binary assets but a generated icon,
**209 Xcode tests and 191 SPM tests green**, and a genuinely deterministic core behind a clean
`RendererPort` seam. Session 001 built the agent memory system. Session 002 produced the Completeness
Ledger: 50 of 59 user-facing features are fully implemented and exactly one — account deletion — is
outright absent, but only ~13 of 59 clear the owner's six decrees. Session 003 wrote the design bible
and found the structural problem: the game ran out of design at 3,200 m. Session 004 built act two
out to 9,600 m. Session 005 rebuilt the hub. **Session 006 closed the catalogue half of the mastery
ceiling** — there is a 15th pattern behind a sixth tier, carrying the first new verb since v1.3 —
and took two owner fixes on audio and character identity. Backlog is 262 items, 14 DONE. Five audits
remain unrun; the phase gate is gone, so fixes and audits interleave, and polish outranks compliance
until Rayan says otherwise.

# Rayan action items (surface them; do not try to do them)

1. **The slide sound — does it actually sound better now?** This is the one item in the whole
   program no agent can verify: nothing here can hear audio. The fix is DSP reasoning (the old burst
   had no attack ramp and a 6 dB/oct filter at 600 Hz) plus sanity tests. If it is still wrong, the
   knobs are all one line each in `Synth.slide()` — `attack`, `poles`, `cutoff`, `vol`.
2. **Prism is now solid cyan.** That is its authored `bodyHex` and exactly what Reduce Motion users
   already saw. If you wanted Prism to keep a *static* rainbow rather than a single colour, say so —
   that is a different and larger change than the one made, because the swatch and the 3D rig both
   have to render the same gradient for decree 2 to hold.
3. **Does the chasm feel right?** Verified fair (200-seed bot green, symmetric ±0.25 s window) and
   legible in stills, but a still and 33 m/s are different claims. Does the gap read as a gap the
   first time you meet it? Fastest way to see it:
   `SIMCTL_CHILD_PR_WORLD=9 SIMCTL_CHILD_PR_AUTOPLAY=1 SIMCTL_CHILD_PR_SKIP_SPLASH=1 SIMCTL_CHILD_PR_CHASM=1`
4. **Does act two feel right?** (carried from S-005) Is the 3,200 m step noticeable? Do the swung
   moving walls past ~6,800 m read, or feel cheap?
5. **Does the new hub feel right?** (carried from S-005) Screenshots at three profile states in
   `docs/agent/scratch/s005/after_*.png`, but a hub is a thing you tap.
6. **The `Double Coins` IAP description in App Store Connect** — *if* you have already created
   `com.rayancheca.prismrush.doublecoins` with the old "Earn 2x coins, forever" wording, it must be
   corrected before submission. Correct text: **`Every run pays 2× coins. Forever.`** Nothing is
   public yet, so if you have not created it there is nothing to fix.

# Open questions for Rayan (carried until answered; none block session 007)

- **PR-0040** — the music is a 1.82 s loop for the whole session, pinned to world 0 by your own
  decree. Long-form structure inside that constraint needs sign-off. *(Now more pointed: S-006
  touched the SFX layer and found PR-0320 sitting unfixed inside it, so the audio layer has had
  less attention than the rest of the game.)*
- **PR-0052** — is the Daily Challenge a layout guarantee or an identical-experience guarantee?
- **PR-0010** — `Store/metadata.md` sells a three-world game; the binary ships twelve families plus
  an infinite evolved cycle. Needs a ledger-checked rewrite before submission.
- **PR-0401** — the coin sink still buys nothing that alters play. This is the surviving half of
  session 003's verdict, and it is now the largest structural gap left in the design.

# Resolved in session 006

PR-0450 · PR-0320 · PR-0454 · PR-0455. New decisions: **D-009** (decree 1 covers time),
**D-010** (tier-six placement + the two rejected act-two weightings, with measurements).
