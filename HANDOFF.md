# HANDOFF → Session 015

## Paste this to start the next session

```
You are session 015 of a long-running program to finish and ship Prism Rush, a neon three-lane
endless runner for iPhone (Swift 6, SwiftUI, RealityKit, zero dependencies, zero binary assets).

Read docs/agent/01_RULES.md, then docs/agent/02_STATE.md, then this file.

You may and should change code. Rayan's standing instruction is "never be limited by arbitrary
rules, just work however you think is best." Do not ask permission to fix something you can verify.

SESSION 014 DID THE WARDEN. It can now kill you (D-039), its arena is a place (D-040), and the red
is spent rather than sprayed (D-041). 266 SPM tests green, verified on device at all three ranks.
DO NOT REDO IT. Read D-037..D-041 before touching anything Warden-shaped.

YOUR FIRST JOB IS TO PLAY IT AND REPORT BACK, exactly as S-014 did — see "How to test like a human"
below, which is now proven rather than aspirational. The owner has not yet seen ANY of S-014's work.
His verdict on it outranks everything in this file, so get it early: build, play the Warden at
ranks 1/2/3, and tell him what changed and what you think is still wrong.

Then, in priority order, the three things S-014 deliberately did not do:

  (1) THE WARDEN HAS NO VOICE, AND THIS IS NOW FOUR SESSIONS OLD. A landed hazard plays
      `.shieldBreak` — the SAME BUFFER as clipping a wall, your own shield breaking, the Warden's
      armour breaking, and a blast shattering walls. One buffer, five meanings, three opposite in
      valence. Under D-039 that is the sound the whole fight now turns on. There is also ONE 1.82 s
      music loop for the entire session, so a boss sounds exactly like open track.
      A costed design for both is in docs/agent/audits/scratch/s014_audio.md — including a
      defaulted `fight: Float` on `Synth.step` that needs no new audio node.
      NOBODY IN THIS PROGRAM CAN HEAR A SOUND. Four sessions have declined for that reason and the
      cost has compounded. See "Rayan action items" — this one is his call, and asking is the job.

  (2) THE BOSS DOES NOT OWN THE FRAME. At rank 3 (world 9) the sky is a giant pink-and-gold halo
      filling two thirds of the screen, and the craft is drawn on top of it — the Warden has LESS
      visual authority at rank 3 than at rank 1, which is backwards. S-014's arena shell helps
      (the craft now sits inside a structure) but does not fix it. Nothing dims the sky, changes the
      lighting, or gives the set piece the frame. Design is in
      docs/agent/audits/scratch/s014_camera_post.md (FOV, vignette, shake ramp, a slow-mo beat on
      the kill), all of it compositor-cheap and Reduce-Motion-gated.

  (3) HAZARD VIOLET SITS ON WORLD VIOLET. D-034 chose 0xC77BFF because it is far in hue from gold
      gems and shield cyan — but it was never checked against the twelve WORLD palettes. World 9's
      grid is violet, and rank 3 is the fight with the shortest reaction window (0.62 s). Verified
      by eye on the simulator.

Decisions are in docs/agent/04_DECISIONS.md as D-023..D-041. Do not re-ask what is answered there.

FIRST COMMAND, before anything else. docs/agent/scratch/ and docs/agent/audits/scratch/ are
gitignored and now hold ~750 MB from fourteen sessions, including S-014's play captures. Git does
NOT move them between worktrees. No-op if you already have them:

  for w in "" .claude/worktrees/prism-rush-spawn-path-c7d88a \
           .claude/worktrees/prism-rush-design-audit-562d27 \
           .claude/worktrees/prism-rush-audit-91c7ba; do
    s="/Users/rayankarimcheca/Desktop/ClaudeProjects/projects/prism-rush-ios/$w/docs/agent"
    [ -d "$s/scratch" ] && mkdir -p docs/agent/scratch && cp -Rn "$s/scratch/." docs/agent/scratch/ 2>/dev/null
    [ -d "$s/audits/scratch" ] && mkdir -p docs/agent/audits/scratch && cp -Rn "$s/audits/scratch/." docs/agent/audits/scratch/ 2>/dev/null
  done; du -sh docs/agent/scratch docs/agent/audits/scratch

BUILD AND RUN THE APP BEFORE YOU CLAIM ANYTHING WORKS. Fourteen for fourteen. `swift test` compiles
Core/, seven Meta/ files and Audio/Synth.swift. It does NOT compile UI/, Render/, IAP/, StoreKit or
GameKit. S-013 shipped 261 green SPM tests over an iOS target that DID NOT COMPILE. S-014 hit the
same class of thing twice — a non-exhaustive switch and an out-of-order memberwise argument — both
invisible to a green `swift test`.

Report back in three lines.
This file's absolute path: /Users/rayankarimcheca/Desktop/ClaudeProjects/projects/prism-rush-ios/HANDOFF.md
```

---

# HOW TO TEST LIKE A HUMAN (this now works — S-014 proved it)

S-014 was the first session to play the game. It is not hard, and it found three things thirteen
sessions of testing had not.

    mcp__Claude_Code_iOS_Simulator__control

- `attach` opens a live panel (do it FIRST, before building — cheap, and Rayan can watch).
- `tap`, `swipe`, `touch_path` inject real gestures. **Coordinate space is 402 × 874 points**, origin
  top-left. Inputs: swipe left/right = lane, up = jump, down = slide, **double tap = THE BLAST**.
- `PR_WARDEN=1|2|3` drops you at the first / second / third Warden (worlds 3/6/9) with a full charge
  bank; `PR_SKIP_SPLASH=1` skips the intro. **Do NOT pass `PR_AUTOPLAY=1`** — that is the bot, and
  the bot is the thing that has been lying to us.

```
SIMCTL_CHILD_PR_WARDEN=2 SIMCTL_CHILD_PR_SKIP_SPLASH=1 \
  xcrun simctl launch <udid> com.rayancheca.prismrush
```

**The instrument that actually works** — record video, then review contact sheets. 24 game states per
image, at real speed, for one Read:

```
xcrun simctl io <udid> recordVideo --codec h264 --force out.mp4 &   # then launch, then kill -INT
ffmpeg -v error -ss 3 -i out.mp4 -vf "fps=2,scale=250:-1,tile=4x3:margin=4:padding=3" -frames:v 1 sheet.png
```

Screenshots stall the app into slow motion; video does not. Use OUTPUT seeking (`-i file -ss t`),
never input seeking. **Then open the sheet and look at it** — a captured PNG nobody read is not
evidence.

**Known traps, all paid for already:**
- `Tools/build.sh` writes to `.dd/Build/Products/`, **NOT** `~/Library/Developer/Xcode/DerivedData`.
  Both exist and the latter is stale. To confirm a build is current, grep the dylib for a string only
  your change introduced — **file mtimes in this checkout are misleading** (S-014 nearly discarded a
  perfectly current build over a Jul 31 timestamp).
- `simctl install` KEEPS the profile. Uninstall first for anything gated on a profile counter — and
  **lethality now is** (`Profile.wardensMet` must exceed `Tuning.wardenCoachEncounters`).
- Never drive the simulator while `xcodebuild test` runs on it. (`swift test` is macOS/SPM and safe.)

---

# What session 014 changed (so you do not re-derive it)

One commit, `f95363a` (`PR-0462`). **266 SPM tests** (was 261). `layoutVersion` **untouched at 12**;
**v13 is still pre-armed and unspent** at `0x9E49_3424_C18A_59C5`. Full log:
`docs/agent/sessions/SESSION_014.md`. Decisions **D-039..D-041**.

- **`Tuning.wardenStrikesSurvivedByRank = [nil, 3, 2]`.** Per-encounter, resets at every arena.
- **`GameCore.wardenLethalityUnlocked`** gates it on `Profile.wardensMet`, handed in via
  `startRun(wardensMetBefore:)` — default `Int.max` so every existing caller and the whole suite
  measure the LETHAL fight.
- **`WardenEncounter.strikes` / `wouldNextStrikeBeFatal` / `isOneStrikeFromDeath`**, mirrored onto
  `WardenState`. The shield fires *before* the counter moves, so absorbing leaves the player at the
  brink rather than one past the budget.
- **`FXEvent.died` gained `fromWarden`**, and `GameCore.diedToWarden` survives the event so the death
  panel can read it (`THE WARDEN GOT YOU`).
- **`ArenaShell.swift`** (new) + a deck tint folded into the renderer's palette cache key.
- **`WardenState.throwCharge`** drives the craft's wind-up. Presentation only; no RNG.

## Things you would otherwise rediscover the hard way

- **`while core.warden != nil` does not terminate after a Warden kill.** `stepWarden` bails on
  `.over`, so `warden` is never cleared. Thirteen test loops have this shape; S-014 added
  `&& core.mode == .play` to the ones it touched. **Check yours.**
- **`Warden.suppresses` deliberately lets POWER-UPS into an arena**, and `debugClearTrack` parks
  `spawner.cursor` but **not** `powerUpCursor` — so a stationary test probe collects a fresh shield
  mid-fight. S-014 lost time to a shield test asserting the wrong thing because of it.
- **`GameOverView` is presentational with a synthesized memberwise init**, so arguments must be
  passed in DECLARATION order. Out-of-order is a build failure `swift test` cannot see.
- **SourceKit in this checkout resolves against macOS.** `No such module 'UIKit'` / `Cannot find
  'Theme' in scope` are noise. Believe `./Tools/build.sh`.
- **`CoreEntity.closeSpeed` is 0 for everything the spawner places, and that is load-bearing.**
- **The reaction window is `lead / (run + close)`. Moving one term without the other INVERTS the
  difficulty** (D-032). `LaggedAutopilotTests` is two-sided on purpose, and S-014 added a third test
  that prints the whole curve — if it goes non-monotonic, a window is inverted somewhere.
- **18.1 s is a hard ceiling on `wardenMaxSeconds`.** Fight LENGTH is exhausted as a lever.
- `state.md` (58 KB) and `README.md` (35 KB) at the repo root are history, not truth. `02_STATE.md`
  below its header block is still session 012's and describes a v1.7 codebase.

---

# Current state in one paragraph

Prism Rush is a v2.4 feature-complete iPhone game that has never been submitted: ~100 Swift files,
zero dependencies, zero binary assets but a generated icon, **266 SPM tests green**, and a
deterministic core behind a clean `RendererPort` seam. `layoutVersion` is **12**, v13 pre-armed. The
Warden throws real obstacles that visibly rush the player, ladders across three ranks, shoots from
rank 2, announces itself 240 m out, teaches its own verbs, **fights inside an arena that now looks
like one**, and **can end your run** once it has finished teaching you. What it still does not have
is a voice, a music state, or a camera of its own — and at rank 3 the world's wallpaper still
upstages it.

**Nothing is pushed.** `f95363a` and everything back through the S-012 commits are local only; that
is the repo's existing rhythm, not an oversight.

# Rayan action items

1. **PLAY THE NEW WARDEN.** All of S-014 is unseen by you. Specifically: does it now feel like a
   place and a fight rather than weather? Is dying to it fair, or annoying? `HIT — ONE MORE ENDS IT`
   in red, then `THE WARDEN GOT YOU` — does the stake read in the moment?
2. **THE WARDEN'S EARS — the one only you can unblock, and it is four sessions old.** Its strike, its
   shot and its blast all borrow other sounds; a landed hazard shares one buffer with four unrelated
   events; and there is one 1.82 s music loop for the whole session. A full design is costed and
   waiting in `docs/agent/audits/scratch/s014_audio.md`. Either listen and direct, or say "ship your
   best guess and I'll judge it" — both are fine, but silence keeps it stuck.
3. Carried and still never confirmed by a human: **the stumble** (five sessions), the slide SFX
   (S-006), the hub redesign (PR-0452).
4. **The `Double Coins` IAP description in App Store Connect** — correct it to
   `Every run pays 2x coins. Forever.` before submission.

# Open questions for Rayan (carried until answered)

- **PR-0040** — the music is a 1.82 s loop for the whole session, pinned to world 0 by decree. A
  boss-fight music state is a *different axis* from per-world beds and would not violate that decree;
  the audit says so explicitly. Needs a yes/no.
- **PR-0010** — `Store/metadata.md` sells a three-world game; the binary ships twelve families.
- **PR-0254** — should a run that used a paid revive be leaderboard-eligible? S-003 recommends
  counting it for missions/XP but not the leaderboard. Needs a yes/no.
- **Buying a deep world forfeits Game Center submission, reach credit and achievements**
  (`ProfileStore.swift:274-292`), so 71% of the coin catalogue makes runs count for LESS. Intended?

# Resolved in session 014

A Warden can kill you, correctly (**D-039**) — with S-013's recommended numbers refuted by play, and
a second gate so a bought world-9 start can never make a rank-3 arena somebody's first Warden. The
arena is a place (**D-040**) — and the reason it felt empty was found: worlds 3/6/9 are the only
worlds in the game with no side decor at all. The red is spent rather than sprayed (**D-041**), so
`HIT — ONE MORE ENDS IT` is true again and a run a boss ended says so. **And somebody finally played
the game.** `PR-0462`.
