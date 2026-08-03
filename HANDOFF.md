# HANDOFF → Session 014

**This session is about ONE THING: the Warden. Do not go and do something else.**

## Paste this to start the next session

```
You are session 014 of a long-running program to finish and ship Prism Rush, a neon three-lane
endless runner for iPhone (Swift 6, SwiftUI, RealityKit, zero dependencies, zero binary assets).

Read docs/agent/01_RULES.md, then docs/agent/02_STATE.md, then this file.

You may and should change code. Rayan's standing instruction is "never be limited by arbitrary
rules, just work however you think is best." Do not ask permission to fix something you can verify.

THIS SESSION IS THE WARDEN, AND ONLY THE WARDEN. His instruction, verbatim, closing session 013:

  "yeah he should be able to kill you at some point. i still need you to revise the warden so many
   times and test test test like a human because it still feels very empty."

Three separate instructions in one sentence. All three are binding.

  (1) IT MUST BE ABLE TO KILL YOU. This REVOKES D-028 (its own predecessor decree). Read D-037.
      The teaching rank stays survivable — lethality is the TOP of the ladder, not the floor. An
      implementation that can kill a player during their first-ever encounter has misread it.

  (2) "REVISE SO MANY TIMES" — he is telling you this is not a one-pass job and he expects
      iteration. Do not build one version, prove it green, and write a handoff. Build, PLAY IT,
      change it, play it again. Budget most of the session for the loop, not the first build.

  (3) "TEST TEST TEST LIKE A HUMAN" — this is a correction of METHOD, and it is the most important
      line in the message. Thirteen sessions have verified this game with `Autopilot`, which has
      perfect information and zero latency, and with autoplay captures in which the bot plays
      flawlessly. NOBODY IN THIS PROGRAM HAS EVER PLAYED THE GAME. That is why "it feels empty"
      keeps surviving sessions that fix nine things at once — feel is not in the test suite.
      YOU CAN ACTUALLY PLAY IT. See "How to test like a human" below; this is not optional.

  (4) "IT STILL FEELS VERY EMPTY" — the thing to actually fix. Read D-038: it is measurable, and
      the arena is empty BY CONSTRUCTION. 36-46% of the fight has nothing on the deck, 7.7 s of
      every arena is blank track with a boss in the sky doing nothing, and `Warden.suppresses`
      deliberately deletes every obstacle and boost pad from 770 m of deck. Five sessions of TUNING
      have not touched this because it is not a tuning problem.

Decisions are in docs/agent/04_DECISIONS.md as D-023..D-038 — do not re-ask what is answered there.

FIRST COMMAND, before anything else. docs/agent/scratch/ and docs/agent/audits/scratch/ are
gitignored and hold ~700 MB from thirteen sessions. Git does NOT move them between worktrees. No-op
if you already have them:

  for w in "" .claude/worktrees/prism-rush-spawn-path-c7d88a \
           .claude/worktrees/prism-rush-design-audit-562d27 \
           .claude/worktrees/prism-rush-audit-91c7ba; do
    s="/Users/rayankarimcheca/Desktop/ClaudeProjects/projects/prism-rush-ios/$w/docs/agent"
    [ -d "$s/scratch" ] && mkdir -p docs/agent/scratch && cp -Rn "$s/scratch/." docs/agent/scratch/ 2>/dev/null
    [ -d "$s/audits/scratch" ] && mkdir -p docs/agent/audits/scratch && cp -Rn "$s/audits/scratch/." docs/agent/audits/scratch/ 2>/dev/null
  done; du -sh docs/agent/scratch docs/agent/audits/scratch

BUILD AND RUN THE APP BEFORE YOU CLAIM ANYTHING WORKS. Thirteen for thirteen. `swift test` compiles
Core/, seven Meta/ files and Audio/Synth.swift. It does NOT compile UI/, Render/, IAP/, StoreKit or
GameKit. S-013 shipped 261 green SPM tests over an iOS target that DID NOT COMPILE — one
non-exhaustive `switch` in GameView.swift, invisible to the whole suite.

Report back in three lines.
This file's absolute path: /Users/rayankarimcheca/Desktop/ClaudeProjects/projects/prism-rush-ios/HANDOFF.md
```

---

# HOW TO TEST LIKE A HUMAN (read this before writing any code)

This is the instruction the program has been failing for thirteen sessions, so it gets its own
section. **You have a tool that can play the game with real touch input**, and no session has used
it for that:

    mcp__Claude_Code_iOS_Simulator__control

- `attach` opens a live panel (do it FIRST, before building — it is cheap and Rayan can watch).
- `tap`, `swipe`, `touch_path` inject real gestures. Coordinate space is **402 x 874 points**,
  origin top-left. The game's inputs are: swipe left/right = lane, swipe up = jump, swipe down =
  slide, **double tap = THE BLAST**.
- `screenshot` is headless and needs no panel.

**So: launch the game with NO autoplay, swipe your way to the Warden, and fight it yourself.**
`PR_WARDEN=1|2|3` drops you at the first / second / third Warden (worlds 3/6/9) with a full charge
bank, and `PR_SKIP_SPLASH=1` skips the intro. Do NOT pass `PR_AUTOPLAY=1` — that is the bot, and the
bot is the thing that has been lying to us.

    SIMCTL_CHILD_PR_WARDEN=2 SIMCTL_CHILD_PR_SKIP_SPLASH=1 \
      xcrun simctl launch <udid> com.rayancheca.prismrush

Then actually play it and write down what you FELT — where you were confused, where you were bored,
where you did not know what had just happened, whether the 0.7 s of dead air between throws reads as
tension or as nothing. That report is the deliverable this session has been missing, and it is worth
more than another green test.

**Known capture traps** (all paid for already):
- `Tools/build.sh` writes to `.dd/Build/Products/`, **NOT** `~/Library/Developer/Xcode/DerivedData`.
  S-013's first capture ran a stale bundle from the latter and showed a pre-S-012 HUD.
- `simctl install` KEEPS the profile. Uninstall first when testing anything gated on a profile
  counter (the Warden coaching reads `Profile.wardensMet`).
- Prefer `simctl io recordVideo` + `ffmpeg` over repeated screenshots — screenshots stall the app
  into slow motion; video does not. Use OUTPUT seeking (`-i file -ss t`), never input seeking.
- Never drive the simulator while `xcodebuild test` runs on it. (`swift test` is macOS/SPM and safe.)

---

# THE JOB, in priority order

### 1. Make it able to kill you — correctly (D-037)

He said *"at some point"*, not *"always"*. The specified outcome is his; the mechanism is yours.
S-013's recommendation, which you may replace but should beat:

**A per-encounter strike budget.** The first N landed hazards stagger, the (N+1)th kills, and N falls
with rank — 3 / 2 / 1. Rank 1 is then effectively unkillable (its script has room for only so many
misses), and a rank-3 Warden kills on the second thing it lands. It is legible, it uses the HUD's
existing hit-pip vocabulary, and it restores an honest `HIT — ONE MORE ENDS IT` (a string S-013 had
to delete because D-028 had made it a lie).

Two tests are direct assertions of the revoked decree and must be **re-pointed at the teaching rank,
not deleted** — "cannot kill you at rank 1" is still the promise:
`WardenTests.testAPlayerWhoNeverMovesInsideAnArenaAlwaysSurvivesIt` and
`…testAWardenCannotKillEvenAPlayerWhoArrivesAlreadyStumbling`.

Note `LaggedAutopilotTests` gets sharper teeth for free: its 0.40 s "never TOUCHED" assertion now
also guards against deaths, and its 0.75 s gate already proves a careless player gets hit a lot
(357 hazards landed across 72 encounters). Re-read what those numbers mean once a hit can compound.

### 2. Fill the space (D-038) — this is the one he actually cares about

*"It still feels very empty"* survived a session that fixed nine other complaints, so it is not about
any of them. The measurements:

| rank | hazard in flight | dead air between | % of fight with a bare deck |
|---|---|---|---|
| 1 | 0.84 s | 0.71 s | **46%** |
| 2 | 0.75 s | 0.55 s | **42%** |
| 3 | 0.71 s | 0.39 s | **36%** |

Plus: an arena is **770 m ≈ 26 s** of deck and the fight occupies **18.4 s**, so **7.7 s of every
arena is blank track with a boss hanging in the sky doing nothing**.

**Do not fix this by shrinking the gaps.** Two things bind and both are load-bearing:
`WardenTests.testTwoThrowsAreNeverInFlightAtOnce` (two opposite verbs must never share the deck) and
`LaggedAutopilotTests` (a human-speed player must stay untouched). The gap is not the enemy; the
BARENESS is. Candidates, roughly in order of feel-per-effort:

- **Arena geometry.** `Warden.suppresses` filters `SpawnCmd`s — it cannot see decor. Nothing stops
  you building an arena that LOOKS like an arena: gantries, side walls, a ceiling, hazard lighting,
  a floor that changes material at the mouth. Right now the boss arrives and the world does not
  react at all. This is probably the single biggest win and it touches no gameplay rule.
- **Music.** PR-0040: there is ONE 1.82 s loop for the entire session, so a boss fight sounds
  exactly like open track. A fight with no music state is the definition of empty.
- **The Warden has no voice of its own.** Its aimed shot reuses the lance cue; the blast reuses
  `.boostStart`. Nothing in this program can hear a sound, so S-010/S-012/S-013 all declined to
  invent voices unheard — but that decision has now compounded three times and is a real part of
  "empty". Consider whether this is the session that fixes it, or flag it to Rayan as needing his ears.
- **Camera / post.** No FOV push, no vignette, no shake ramp across phases, no slow-mo beat on the
  kill. The fight is drawn at exactly the same camera as jogging down an empty road.
- **Something to look at between throws.** The craft idles at a constant yaw and stops dead during a
  telegraph. 0.4-0.7 s is enough for a wind-up, a tell, a charge glow — anything that says the next
  one is coming and what it will be.

### 3. Then iterate (his word: "so many times")

Build → play it yourself → change it → play it again. Do not stop at the first green suite.

---

# What session 013 did (context you need)

Two commits, `82f838a` (`PR-0461`) and `07e2802` (docs). **261 SPM tests green** (was 254).
`DailyChallenge.layoutVersion` **11 -> 12**; **v13 is pre-armed at `0x9E49_3424_C18A_59C5`**
(2026-6-10). Full detail in `docs/agent/sessions/SESSION_013.md`, decisions **D-032..D-038**.

Rayan rejected the S-012 Warden with nine complaints; all nine were fixed and verified on screen:
a pre-arena countdown, first-time verb coaching, the red deleted, the hanging bar rebuilt as a
see-through portcullis, hazards that CLOSE at the player, a five-axis rank ladder, aimed shots from
rank 2, a ~2x denser fight, and a longer clock. **He then played it and said it still feels empty** —
which is the whole of session 014's job.

---

# Things you would otherwise rediscover the hard way

- **`CoreEntity.closeSpeed` is 0 for everything the spawner places, and that is load-bearing.** It is
  what keeps ordinary track, the 200-seed solvability proof and every daily golden untouched by the
  field's existence. Only `applyThrown` sets it. `WardenTests.testOnlyAWardensHazardsEverClose` guards it.
- **`Autopilot.closingRatio` and `GameCore.advanceClosingHazards` are two halves of ONE arithmetic**
  and must both read `GameCore.hazardCloseScale`. When they disagreed (chrono-scaled `effectiveSpeed`
  vs unscaled `closeSpeed`) the factors stopped cancelling, the bot read a closing chasm as nearer
  than it was, launched early into the catalogue's only two-sided window and air-slammed into the
  hole. 1 seed in 200.
- **The reaction window is `lead / (run + close)`. Moving one term without the other INVERTS the
  difficulty.** Leads 34->52 with closing at only +9 m/s made the boss EASIER — a bot reacting 0.75 s
  late killed 48 of 48. `LaggedAutopilotTests` is two-sided on purpose; both directions bind.
- **18.1 s is a hard ceiling on `wardenMaxSeconds`**: `(worldLength - wardenArmWindow) /
  boostSpeedMax - 1.9`. Past it an arena straddles two worlds. Fight LENGTH is nearly exhausted as a
  lever — which is exactly why "empty" has to be answered with content, not with more seconds.
- **A landed hazard never calls `registerWardenAnswer`** — it staggers, deletes the whole throw, and
  `continue`s. Anything derived from "damage dealt" is pinned at zero for a player who is missing
  everything; that is why `throwLead` lerps on `max(damage, throwCount / wardenLeadClockThrows)`.
- **iCloud conflict copies break the Xcode build too, not just SPM.** `PrismRush/UI/GameView 2.swift`
  appeared mid-session and turned a green 261-test run into `** BUILD FAILED **`. They are
  gitignored, so `git status` is clean. `find PrismRush Tests -name "* [0-9].swift"`.
- **SourceKit in this checkout resolves against macOS.** `Theme` / `UIKit` / "has no member" errors
  are noise. Believe `./Tools/build.sh`.
- `state.md` (58 KB) and `README.md` (35 KB) at the repo root are history, not truth.

---

# Current state in one paragraph

Prism Rush is a v2.3 feature-complete iPhone game that has never been submitted: ~100 Swift files,
zero dependencies, zero binary assets but a generated icon, **261 SPM tests green**, and a
deterministic core behind a clean `RendererPort` seam. `layoutVersion` is **12**, v13 pre-armed. The
Warden throws real obstacles that visibly rush the player, ladders across three ranks, shoots from
rank 2, announces itself 240 m out and teaches its own verbs — and **still feels empty**, because the
arena is 770 m of deliberately-cleared deck with 36-46% dead air and no music, no bespoke audio, no
geometry and no camera work of its own. It also still cannot kill anybody, which D-037 now revokes.

**Nothing is pushed.** `07e2802`, `82f838a` and all four S-012 commits are local only; that is the
repo's existing rhythm, not an oversight.

# Rayan action items

1. **The Warden's ears.** Its aimed shot reuses the lance cue, the blast reuses `.boostStart`, and
   there is one 1.82 s music loop for the whole session. Nothing in this program can hear a sound,
   so three sessions have declined to invent voices unheard — that is now a measurable part of
   "empty". Either he listens and directs, or a session ships something and he judges it.
2. Carried and still never confirmed by a human: **the stumble** (four sessions), the slide SFX
   (S-006), the hub redesign (PR-0452).
3. **The `Double Coins` IAP description in App Store Connect** — correct it to
   `Every run pays 2x coins. Forever.` before submission.

# Open questions for Rayan (carried until answered)

- **PR-0040** — the music is a 1.82 s loop for the whole session, pinned to world 0 by decree. This
  is now blocking the boss fight's feel, not just ambience.
- **PR-0010** — `Store/metadata.md` sells a three-world game; the binary ships twelve families.
- **PR-0254** — should a run that used a paid revive be leaderboard-eligible? S-003 recommends
  counting it for missions/XP but not the leaderboard. Needs a yes/no.
- **Buying a deep world forfeits Game Center submission, reach credit and achievements**
  (`ProfileStore.swift:274-292`), so 71% of the coin catalogue makes runs count for LESS. Intended?

# Resolved in session 013

Hazards that travel at the player; a five-axis rank ladder; aimed shots from rank 2; a ~2x denser,
3 s longer fight; the pre-arena countdown; first-time verb coaching; the red deleted; the hanging bar
rebuilt as a see-through portcullis; the shield no longer wasted on a non-lethal hazard; the fight
now escalating for a player who is losing it; the fairness gate extended to cover rank 3 for the
first time. **D-032..D-036.** Then, from the owner's play session: **D-037** (it must be able to
kill you — D-028 revoked) and **D-038** (the emptiness, measured). `PR-0461`.
