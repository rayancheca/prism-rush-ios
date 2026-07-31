# HANDOFF → Session 014

## Paste this to start the next session

```
You are session 014 of a long-running program to finish and ship Prism Rush, a neon three-lane
endless runner for iPhone (Swift 6, SwiftUI, RealityKit, zero dependencies, zero binary assets).

Read docs/agent/01_RULES.md, then docs/agent/02_STATE.md, then this file.

You may and should change code. Rayan's standing instruction is "never be limited by arbitrary
rules, just work however you think is best." Do not ask permission to fix something you can verify.

Direction: App Store submission IS the goal, timing is open, and Rayan wants the app POLISHED first.
Design and feel outrank compliance right now. He also said, in S-011: "always plan extremely before
implementing" and "ask me questions if you need". Decisions are recorded in docs/agent/04_DECISIONS.md
as D-023..D-036 — do not re-ask what is already answered there.

YOUR JOB, in priority order.

  1. WHATEVER RAYAN SAYS WHEN HE PLAYS THE NEW WARDEN. S-013 rebuilt it against nine verbatim
     complaints and every one is verified on screen, but nothing in this program can feel a game.
     The specific things that need his thumbs are listed under "Rayan action items" below. Item 1
     there — whether a boss that CANNOT KILL YOU is enough of a stake now that it is genuinely
     hard — is the one open design question that could change the whole feature, and it is his call
     alone (D-028 is his own decree; only he can revoke it).

  2. OBSTACLE VARIETY IN THE ORDINARY TRACK — carried from S-013, and now the largest gap left.
     The Warden is fixed; the 15-pattern catalogue underneath it is not.
       - **SLIDE IS STILL MANDATORY NOWHERE IN THE CATALOGUE.** `EntityKind.hangingBar` exists,
         works, is unjumpable from every state, and now has a proper see-through portcullis mesh —
         and NO PATTERN PLACES ONE. Putting it in the catalogue is still the single highest-value
         change left. It is also cheap now: the mesh, the collision, the graze rule, the Autopilot
         arm and the blast rule are all shipped and exercised by the Warden every third world.
       - 3 of 15 patterns consume ZERO randomness and render identically every time (indices 2, 8,
         13); 10 of the remaining 12 vary by exactly one thing, WHICH OF THREE LANES.
       - `EntityKind.bolt` and `CoreEntity.closeSpeed` are now available to the catalogue too. A
         closing hazard on ordinary track would be a genuinely new pattern axis — but note the
         Autopilot's time-conversion (`Autopilot.closingRatio`) is what makes closing hazards
         survivable, and the 200-seed proof has only ever exercised it inside arenas.
     THIS COSTS THE layoutVersion BUMP. It is now **12**, and **v13 is pre-armed at
     `0x9E49_3424_C18A_59C5`** (2026-6-10). Iron rule 3, exactly: keep the 200-seed bot green (ZERO
     CONTACTS), bump the version, repin goldens in BOTH `DailyChallengeTests` AND
     `MissionsTests.testTodaysChallengeSeedMatchesUTCGoldens`. Derive them in Python from the
     SplitMix64 constants and reproduce every existing pin before trusting a new one.

  3. PER-WORLD WARDEN SPECIES — specified in s009c_SPEC.md §3, carried since S-009. Much easier now
     than it has ever been: a species is a different THROW TABLE (`WardenEncounter.script(rank:)`
     plus `Tuning.wardenThrowKind`), and v2.3 added a fourth shape to that table without touching
     the fight's structure, which is the proof the seam works.

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

# What session 013 did

One commit, `82f838a` (`PR-0461`), built and run on the simulator at all three ranks before it was
claimed. **261 SPM tests green** (was 254). `DailyChallenge.layoutVersion` **11 → 12** — the pre-armed
pin is spent; **v13 is pre-armed at `0x9E49_3424_C18A_59C5`**.

Rayan played the S-012 Warden and rejected it in one message with nine distinct complaints. All nine
are answered and verified on screen. Full detail in `docs/agent/sessions/SESSION_013.md`, decisions
**D-032…D-036**.

The one that mattered: **"its not sending walls down the lane like i asked" was a missing mechanic,
not a tuning miss.** Every obstacle in this game — including a Warden's — was pinned to a fixed `d`
and the player ran into it. There was no velocity field anywhere in `Core/`, so "the Warden throws a
wall" and "the spawner places a wall" produced identical motion, and the only thing marking the
boss's attack was that it was tinted red. He had been right about this in S-012 too.

---

# Things you would otherwise rediscover the hard way

- **`CoreEntity.closeSpeed` is 0 for everything the spawner places, and that is load-bearing.** It is
  what keeps ordinary track, the 200-seed solvability proof and every daily golden untouched by the
  field's existence. Only `applyThrown` ever sets it. `WardenTests.testOnlyAWardensHazardsEverClose`
  is the guard.
- **`Autopilot.closingRatio` and `GameCore.advanceClosingHazards` are two halves of ONE arithmetic**
  and must both read `GameCore.hazardCloseScale`. When they disagreed (a chrono-scaled
  `effectiveSpeed` against an unscaled `closeSpeed`) the factors stopped cancelling, the bot read a
  closing chasm as nearer than it was, launched early into the catalogue's only two-sided window and
  air-slammed into the hole. 1 seed in 200. With it right, `d(effective)/dt` is exactly
  `−effectiveSpeed`, so every distance-as-time lead in that file keeps meaning what it meant.
- **The window is `lead / (run + close)`, and moving one term without the other inverts the
  difficulty.** Leads 34→52 with closing at only +9 m/s made the boss EASIER than before — a bot
  reacting 0.75 s late killed 48 of 48. If you touch either number, `LaggedAutopilotTests` is the
  gate; it is two-sided on purpose and both directions are load-bearing.
- **18.1 s is a hard ceiling on `wardenMaxSeconds`**, not a preference:
  `(worldLength − wardenArmWindow) / boostSpeedMax − 1.9`. Past it an arena straddles two worlds and
  `Warden.arenaWorld` is ambiguous. This is why fight LENGTH is nearly exhausted as a lever and
  density is the one that is left.
- **A landed hazard never calls `registerWardenAnswer`** — it staggers, deletes the whole throw, and
  `continue`s. Anything you derive from "damage dealt" is therefore pinned at zero for a player who
  is missing everything; `throwLead` now lerps on `max(damage, throwCount / wardenLeadClockThrows)`
  for exactly that reason.
- **`Tools/build.sh` writes to `.dd/Build/Products/`, NOT to `~/Library/Developer/Xcode/DerivedData`.**
  The first capture of the session ran a stale bundle from the latter and showed a pre-S-012 HUD.
  And `simctl install` KEEPS the profile — uninstall first if you are testing anything gated on a
  profile counter (the Warden coaching reads `Profile.wardensMet`).
- **iCloud conflict copies break the Xcode build too, not just SPM.** `PrismRush/UI/GameView 2.swift`
  appeared mid-session and turned a green 261-test run into `** BUILD FAILED **`. They are
  gitignored, so `git status` is clean. `find PrismRush Tests -name "* [0-9].swift"`.
- **SourceKit in this checkout resolves against macOS.** `Theme` / `UIKit` / "has no member" errors
  are noise. Believe `./Tools/build.sh`.
- `PR_WARDEN=1|2|3` now starts at the FIRST, SECOND or THIRD Warden (worlds 3/6/9), which is the only
  way to inspect a rank-2 or rank-3 fight — aimed shots do not exist at rank 1 by design. Prefer
  `simctl io recordVideo` + `ffmpeg` over repeated screenshots; screenshots stall the app into slow
  motion. Use OUTPUT seeking (`-i file -ss t`).
- `state.md` (58 KB) and `README.md` (35 KB) at the repo root are history, not truth.

---

# Current state in one paragraph

Prism Rush is a v2.3 feature-complete iPhone game that has never been submitted: ~100 Swift files,
zero dependencies, zero binary assets but a generated icon, **261 SPM tests green**, and a
deterministic core behind a clean `RendererPort` seam. `DailyChallenge.layoutVersion` is **12** and
**v13 is pre-armed**. The boss now throws real obstacles that visibly rush the player, gets harder
across three ranks, shoots at you from rank 2, announces itself 240 m out, teaches its own verbs for
three encounters, and contains no red at all. What is left is CONTENT: the ordinary pattern catalogue
is still 15 patterns, ~60 arrangements, and one verb — SLIDE — that it never once requires.

**Nothing is pushed.** `82f838a` and all four S-012 commits are local only; that is the repo's
existing rhythm, not an oversight.

# Rayan action items (surface them; do not try to do them)

1. **PLAY THE NEW WARDEN — and answer the one question this session could not.** It is now genuinely
   hard (a bot reacting 0.75 s late kills only 17 of 72, down from 31 of 48) but it still CANNOT KILL
   YOU, because D-028 is your own decree. You said "it needs to be a challenge". Is losing the bounty
   a real enough stake now that the fight has teeth, or should a rank-3 Warden be able to end a run?
   **That is a one-flag change and only you can make the call.**
2. **Does the approach warning land?** `⚠ WARDEN AHEAD · 240 m` counting down. Too early, too late,
   too quiet?
3. **Does the coaching teach or nag?** It names the verb for your first THREE encounters, then
   retires forever. Your save has `wardensMet = 0`, so you will get it.
4. **The violet.** Everything the Warden owns is now `#C77BFF` on a near-black body instead of red.
   Gems stay gold, shields stay cyan. Right call?
5. **Do the walls read as thrown?** They close at 25–32 m/s ON TOP of the run, so they approach at
   ~1.9× the speed of the deck. Too fast to read, or finally "like the trains from subway surfers"?
6. **The aimed shot** (rank 2+, so `PR_WARDEN=2`). It targets the lane you are standing in. Fair?
7. Carried and still never confirmed by a human: **the stumble** (four sessions), the slide SFX
   (S-006), a full audio pass (PR-0456), the hub redesign (PR-0452).
8. **The `Double Coins` IAP description in App Store Connect** — correct it to
   `Every run pays 2× coins. Forever.` before submission.

# Open questions for Rayan (carried until answered)

- **NEW: should a Warden be able to kill you at high rank?** See action item 1. Everything else in
  the fight is now tuned; this is the last structural question about it.
- **NEW: the blast has no sound of its own**, and neither does the aimed shot — it reuses the lance
  cue. Nothing in this program can hear a sound, so bespoke voices were not invented (same call
  S-010 made for the stumble). The audio pass (PR-0456) is where these get fixed together.
- **PR-0040** — the music is a 1.82 s loop for the whole session, pinned to world 0 by decree.
- **PR-0010** — `Store/metadata.md` sells a three-world game; the binary ships twelve families.
- **PR-0254** — should a run that used a paid revive be leaderboard-eligible? S-003 recommends
  counting it for missions/XP but not the leaderboard. Needs a yes/no.
- **Buying a deep world forfeits Game Center submission, reach credit and achievements**
  (`ProfileStore.swift:274-292`), so 71% of the coin catalogue makes runs count for LESS. Intended?

# Resolved in session 013

Hazards that travel at the player; a five-axis rank ladder; aimed shots from rank 2; the fight ~2×
denser and 3 s longer; the pre-arena countdown; first-time verb coaching; the red deleted; the
hanging bar rebuilt as a see-through portcullis; the shield no longer wasted on a non-lethal hazard;
the fight now escalating for a player who is losing it; the fairness gate extended to cover rank 3
for the first time. Decisions **D-032…D-036**. `PR-0461`.
