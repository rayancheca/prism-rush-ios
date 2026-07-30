# HANDOFF → Session 011

## Paste this to start the next session

```
You are session 011 of a long-running program to finish and ship Prism Rush, a neon three-lane
endless runner for iPhone (Swift 6, SwiftUI, RealityKit, zero dependencies, zero binary assets).

Read docs/agent/01_RULES.md, then docs/agent/02_STATE.md, then this file.

You may and should change code. Rayan's standing instruction is "never be limited by arbitrary
rules, just work however you think is best." Do not ask permission to fix something you can verify.

Direction: App Store submission IS the goal, timing is open, and Rayan wants the app POLISHED first.
Design and feel outrank compliance right now.

YOUR JOB, in priority order:

  1. FINISH THE WARDEN SPEC. docs/agent/audits/scratch/s009c_SPEC.md is the implementation spec and
     S-010 built only steps 1-2 of its §6 build order. What is left maps DIRECTLY onto the owner's
     two remaining complaints:
       - Step 3, the FX and shake table (§2.4)  -> answers "no screen shake. no effects."
       - Steps 6-8, WardenSpecies (§3)          -> answers "same every time."
     Steps 4-5 (motion beats, sound) are lower value; step 5 needs ears nobody in this program has.
     BEFORE YOU TRUST A NUMBER IN THAT SPEC, read D-022 — three of its figures were wrong, one by
     arithmetic and two in ways only running the app could catch.

  2. THE POST-KILL DEAD AIR — but get Rayan's call FIRST. Measured: 5.4-10.4 s of empty deck after
     the fight, and the LONGEST hole belongs to the WEAKEST player. Structural, not a tuning miss:
     a variable-length fight inside a fixed-length arena sized for the worst case. This is the ONE
     item that costs a layoutVersion bump (v11 is pre-armed and still unspent after three sessions
     of deliberately not spending it). Options and honest prices: s009b_probe_pacing.md §4. The
     recommended bundle is A + E + F1 (~470 m arena, entrance on real track, break-off attacks
     instead of leaving) — one bump, no new fairness proof, about one session.

  3. PLAY-TEST THE STUMBLE AND REPORT THE NUMBER. It is built and proven (D-020) but its width is a
     judgement call: `Tuning.stumbleGrazeDX = 0.35` buys ~21 ms of extra grace against 30-80 ms of
     human timing jitter, so it converts roughly a QUARTER of near-miss deaths. Rayan asked for
     Subway Surfers; this is rarer than that, deliberately, because at 0.90 the body is already 54%
     buried and deeper stops reading as HALF a hit. Widening it is one edit. He needs to feel it.

READ THESE FOUR SCRATCH FILES FIRST — ~200 KB of already-done work, and they are gitignored:
  docs/agent/audits/scratch/s009c_SPEC.md           the Warden spec — steps 3-8 remain
  docs/agent/audits/scratch/s009b_probe_pacing.md   the dead-air arithmetic and its option space
  docs/agent/audits/scratch/s009b_BRIEF.md          the decision brief Rayan answered
  docs/agent/audits/scratch/s009b_probe_stumble.md  the stumble geometry (now built — D-020)

FIRST COMMAND, before anything else. docs/agent/scratch/ and docs/agent/audits/scratch/ are
gitignored and hold ~350 MB from ten sessions. Git does NOT move them between worktrees. No-op if
you already have them:

  for w in "" .claude/worktrees/prism-rush-spawn-path-c7d88a \
           .claude/worktrees/prism-rush-design-audit-562d27 \
           .claude/worktrees/prism-rush-audit-91c7ba; do
    s="/Users/rayankarimcheca/Desktop/ClaudeProjects/projects/prism-rush-ios/$w/docs/agent"
    [ -d "$s/scratch" ] && mkdir -p docs/agent/scratch && cp -Rn "$s/scratch/." docs/agent/scratch/ 2>/dev/null
    [ -d "$s/audits/scratch" ] && mkdir -p docs/agent/audits/scratch && cp -Rn "$s/audits/scratch/." docs/agent/audits/scratch/ 2>/dev/null
  done; du -sh docs/agent/scratch docs/agent/audits/scratch

If both are empty, say so in your report rather than working blind.

BUILD AND RUN THE APP BEFORE YOU CLAIM ANYTHING WORKS. That rule is now ten for ten. S-010 is the
cleanest demonstration yet: 231 green tests said nothing about a Warden core that was invisible for
its entire exposed phase while the HUD read "CORE EXPOSED", a health bar that was white-on-white, or
a vignette that rendered as a full-screen magenta wash. All three shipped from a spec, compiled
clean, and were rejected by opening a PNG. `swift test` compiles Core/, seven Meta/ files and
Audio/Synth.swift. It does NOT compile UI/, Render/, IAP/, StoreKit or GameKit.

Report back in three lines.
This file's absolute path: /Users/rayankarimcheca/Desktop/ClaudeProjects/projects/prism-rush-ios/HANDOFF.md
```

---

# What session 010 did

Session 009 left three priorities with the owner's answers already on record. Two were built; the
third was deliberately not spent.

**1. THE STUMBLE — the game's first non-lethal contact.** Until now a contact either did nothing or
ended the run, and that missing vocabulary is also why S-008 reached for "the Warden leaves" as its
only non-lethal lever and got a polite antagonist.

The rule, once: *a contact is a stumble when the smallest move that would have made it a clean pass
is shallow, measured on the axis whose VERB answers that obstacle, at the instant the overlap
begins.* Lateral for walls (kill line 1.25 → 0.90), either axis for a low, both edges for a bar,
escape-to-gap for a split bar, and **never** for a chasm.

It is one rescue, not a second life: `stumbleRecover` (0.90 s) leaves the player fully vulnerable and
any further contact is lethal. No counter, no HUD pip, no hoarding. A Warden **stumbles first and
kills second**, held per-ENCOUNTER rather than on a timer — strikes are 1.05–1.20 s apart, so a
timer rule would leave a Warden mathematically unable to kill anyone.

**2. THE WARDEN GOT A BODY.** Scale ×1.70 (0.46 % → ~2.2 % of frame, derived from "an ordinary wall
paints 4× the shipped craft"), a banded disc with a one-value-darker keel and a three-slot dome —
under `UnlitMaterial` there are no normals, so a single-colour body *is* a silhouette, which is the
literal content of "just a basic triangle". Plus the shed: six spars, one detaching per landed hit,
outermost-first so the SPAN narrows. Deleted the shrinking core and the 34° yaw snap.

**3. The dead air was NOT spent.** It costs the pre-armed v11 `layoutVersion`, and it is Rayan's call.

Tests: **218 → 231 SPM**, 238 Xcode unit tests, 12 XCUITests, zero failures.
Commits: `bd8df3b`, `ac818a9`, `60a9985`.

---

# Things you would otherwise rediscover the hard way

- **`s009c_SPEC.md` is good but not infallible — see D-022.** Its halo clearance omitted the torus
  MINOR radius (2 px of clearance instead of the 26 it required); its core position put the core
  under an opaque hull that the camera looks down on, so it was invisible for the whole exposed
  phase; its spar colour was white-on-white. Redo its sums, and look at every visual claim.
- **`Spawner.gapFor(dist)` takes the PLAYER's live distance, not the cursor (D-021).** So any speed
  change nudges every later spawn `d` — by ~0.0002 m at 184 m, which cannot change an answer, and
  which chrono and the boost have done for versions. Pattern content and order ARE cursor-pure.
  This answers PR-0052: the daily challenge promises a layout, never an identical experience.
- **Prism wears a static rainbow (D-011), so it already contains red.** A steady red marker on the
  player's body reads as one more of its own bands. The strobe is what carries a warning on the
  character, not the hue — nothing else in this game blinks.
- **`Autopilot` never enters a graze band**, so the 200-seed proof is unchanged in kind. But it now
  asserts **zero contacts**, not zero deaths, and that change was mandatory — without it a survivable
  contact would turn an unanswerable pattern into a green stagger.
- **`PR_STUMBLE=1`** holds the player permanently staggered (re-armed as the window expires) so the
  ring, the vignette and the impact FX can be captured. `stumbleRecover` is 0.9 s — far shorter than
  a launch-to-screenshot round trip — and the Autopilot never stumbles on its own.
- **`simctl install` without `uninstall` keeps the profile.** Repeated installs left `muted=1` and
  turned `testMuteIsReversibleFromSettings` red mid-session. It was not a regression; it passes on a
  clean profile. Uninstall before trusting any first-run or fresh-profile assertion.
- **SourceKit in this checkout resolves against macOS.** `Theme` / `UIKit` / `PowerUpKind` "errors"
  are noise. Believe `./Tools/build.sh`.
- Never drive the simulator while `xcodebuild test` runs — concurrent installs crash the host.
- `state.md` (58 KB) and `README.md` (35 KB) at the repo root are history, not truth.

---

# Current state in one paragraph

Prism Rush is a v2.0 feature-complete iPhone game that has never been submitted: ~100 Swift files,
zero dependencies, zero binary assets but a generated icon, **231 SPM / 238 Xcode tests green**, and
a genuinely deterministic core behind a clean `RendererPort` seam. `DailyChallenge.layoutVersion` is
**still 10** after three consecutive sessions of not spending it — the pre-armed v11 golden is
unspent and the post-kill dead air is the one change that would use it. `PR-0401` (the coin sink buys
nothing that alters play) is **still open**. Five audits remain unrun.

# Rayan action items (surface them; do not try to do them)

1. **PLAY THE STUMBLE.** It is the thing you asked for and it is in. Does being rescued feel earned,
   and is it rare enough? `Tuning.stumbleGrazeDX` is one edit if you want it more forgiving — the
   honest number is that it converts about a quarter of "I nearly made that" deaths.
2. **PLAY THE WARDEN AGAIN.** It has a body now: ~4.8× the painted area, a keel that gives it form, a
   red core visibly slung under the belly, and a health bar made of spars that fall off it. Does it
   read as a boss at speed?
3. **THE POST-KILL DEAD AIR NEEDS YOUR CALL** — the only change here that costs a layoutVersion bump,
   and the reason it has now waited two sessions. 5.4–10.4 s of empty deck, worst for the weakest
   player.
4. **Per-world antagonists** are specified and unbuilt (`s009c_SPEC.md` §3). Note only FOUR are ever
   reachable — worlds 3/6/9/12 — so the mummy you asked for is currently impossible without moving
   the palette order. D-019 in that spec prices the three options.
5. Carried: the slide SFX (S-006), act two, the chasm, the hub redesign. All still need your thumbs.
6. **The `Double Coins` IAP description in App Store Connect** — correct it to
   `Every run pays 2× coins. Forever.` before submission.

# Open questions for Rayan (carried until answered)

- **PR-0040** — the music is a 1.82 s loop for the whole session, pinned to world 0 by your decree.
- ~~**PR-0052**~~ — **answered by the code in D-021.** The daily challenge guarantees a LAYOUT, not an
  identical experience; three shipped power-ups already perturb the realised gap. No action needed
  unless you want the stronger promise, which would mean making the gap cursor-pure.
- **PR-0010** — `Store/metadata.md` sells a three-world game; the binary ships twelve families.
- **PR-0254** — should a run that used a paid revive be leaderboard-eligible? S-003 recommends
  counting it for missions/XP but not the leaderboard. Needs a yes/no.
- **Coin income is uncapped** — four independent components, none of them the score multiplier. If
  you want income slowed, the levers are gem density, the distance divisor, or the style-coin rate.
- **The `×N` badge still lives inside the GOLD GEM CHIP**, replacing the word "GEMS". This is the HUD
  bug that made you read "infinite coins", and it is still there — it was outside this session's
  scope. Moving it onto the score chip is small and safe.

# Resolved in session 010

The stumble (Core, tests, FX, HUD, and two simulator-driven redesigns of its treatment); the Warden's
presence, form, shed and aimed gun beam; BUG C finished; `resetRig()`; and the spawner-gap correction
that answers PR-0052. **Owner decisions implemented this session:** a beam stumbles first and kills
second; a stumble resets the multiplier.
