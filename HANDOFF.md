# HANDOFF → Session 012

## Paste this to start the next session

```
You are session 012 of a long-running program to finish and ship Prism Rush, a neon three-lane
endless runner for iPhone (Swift 6, SwiftUI, RealityKit, zero dependencies, zero binary assets).

Read docs/agent/01_RULES.md, then docs/agent/02_STATE.md, then this file.

You may and should change code. Rayan's standing instruction is "never be limited by arbitrary
rules, just work however you think is best." Do not ask permission to fix something you can verify.

Direction: App Store submission IS the goal, timing is open, and Rayan wants the app POLISHED first.
Design and feel outrank compliance right now. He also said, in S-011: "always plan extremely before
implementing" and "ask me questions if you need" — he answered eight structured questions in that
session and every answer is recorded below. Do not re-ask them.

YOUR JOB, in priority order. All four are things Rayan explicitly approved in S-011 and that S-011
did not have room to build.

  1. THE BLAST — the game's first offensive verb, and the answer to "what does charged mean".
     Rayan's own idea: "maybe double tap sends a blast originating from the player that knocks
     things down and clears a path." He chose "CHARGE becomes ammo": gems fill the bar, DOUBLE TAP
     spends it, the blast destroys obstacles ahead. This is the highest-value item left — it gives
     the player agency (today the game has ZERO offensive inputs; everything is evasion), and it
     makes the CHARGE bar mean something. Today that bar appears 1.5 s into the first run anyone
     ever plays and its referent (a Warden) does not exist for another 104 seconds.
     The input space is completely free: double tap, long press, touch LOCATION, swipe velocity and
     all multi-touch are unread (docs/agent/audits/scratch/s011_input.md §2). SINGLE TAP IS JUMP and
     must stay instant — do NOT add a double-tap recogniser that delays it. Fire the jump on tap 1
     exactly as today, and treat a second tap inside the window as the blast.
     Chasms should stay immune (you cannot knock down a hole) — the same carve-out the stumble uses.

  2. THE WARDEN REBUILD. Rayan's three answers, all recorded:
       - "It can never kill you." Every shipped runner boss researched (Sonic Dash, Minion Rush,
         Crash On the Run) is an OPPORTUNITY layer: the boss has no kill move, the lethal thing is
         the obstacle it places, and failure means the boss escapes and you lose the reward.
         Prism Rush inverted this. Today two landed hits 1.20 s apart end the run.
       - "Throw real hazards." Stop firing instant beams; the Warden REBUILDS THE TRACK — launches
         walls down a lane, drops bars to slide under, blasts holes in the deck. Travel time is the
         telegraph, and every hazard uses vocabulary the player already reads.
       - Per-world species remain specified and unbuilt (s009c_SPEC.md §3).
     READ docs/agent/audits/scratch/s011_warden_render.md §7 FIRST. Nine numbered findings with the
     geometry, and it is why the current fight is unreadable.

  3. FINISH THE ECONOMY (E6/E7 of docs/agent/audits/AUDIT_011_ECONOMY.md §3). The faucet is done and
     measured; the SINK side has not been re-checked against it. Specifically: re-price the IAP packs
     and the world ladder against the new coins/min, fix the Mystery Box's −19% EV, and re-scale the
     level-up giveaway (~13,050 coins of free power-ups across L1→L30, which undercuts the only
     play-altering sink). Rayan chose "IAP should genuinely matter", so this is a real constraint.

  4. OBSTACLE VARIETY AND SURPRISE — the rest of "the gameplay has been left stale". The ladder is
     fixed but the CONTENT is thin: 3 of 15 patterns consume ZERO randomness and render identically
     every time (2, 8, 13); 10 of the remaining 12 vary by exactly one thing, WHICH OF THREE LANES;
     the whole game contains 60 distinct arrangements; and the spawner draws a gem breadcrumb into
     the safe entry lane of every pattern, so the floor tells you the answer before you arrive.
     **SLIDE IS NEVER MANDATORY ANYWHERE IN THE CATALOGUE** — every bar in the game can be jumped
     (`Collisions.barHit` only kills below 1.65; a base jump clears it for 0.408 s). A player who
     never swipes down can complete every pattern. See s011_research_obstacles.md for a master table
     of what shipped runners use.

BEFORE YOU TRUST ANY NUMBER IN A SCRATCH FILE, check whether a verifier killed it. S-011 ran nine
hostile verifiers and TWO of its own leading hypotheses were REFUTED (see below). A finding that
survived a hostile reader is worth ten that did not.

FIRST COMMAND, before anything else. docs/agent/scratch/ and docs/agent/audits/scratch/ are
gitignored and hold ~350 MB from eleven sessions. Git does NOT move them between worktrees. No-op if
you already have them:

  for w in "" .claude/worktrees/prism-rush-spawn-path-c7d88a \
           .claude/worktrees/prism-rush-design-audit-562d27 \
           .claude/worktrees/prism-rush-audit-91c7ba; do
    s="/Users/rayankarimcheca/Desktop/ClaudeProjects/projects/prism-rush-ios/$w/docs/agent"
    [ -d "$s/scratch" ] && mkdir -p docs/agent/scratch && cp -Rn "$s/scratch/." docs/agent/scratch/ 2>/dev/null
    [ -d "$s/audits/scratch" ] && mkdir -p docs/agent/audits/scratch && cp -Rn "$s/audits/scratch/." docs/agent/audits/scratch/ 2>/dev/null
  done; du -sh docs/agent/scratch docs/agent/audits/scratch

If both are empty, say so in your report rather than working blind.

BUILD AND RUN THE APP BEFORE YOU CLAIM ANYTHING WORKS. Eleven for eleven. `swift test` compiles
Core/, seven Meta/ files and Audio/Synth.swift. It does NOT compile UI/, Render/, IAP/, StoreKit or
GameKit. S-011's character-select fix is the newest example: 231 green tests said nothing about a
coloured rectangle behind every character on a screen nobody had opened.

Report back in three lines.
This file's absolute path: /Users/rayankarimcheca/Desktop/ClaudeProjects/projects/prism-rush-ios/HANDOFF.md
```

---

# What session 011 did

Rayan opened with a long, sharp critique of the Warden and of the gameplay generally, then added two
more complaints mid-session (the character-select background, and the coin economy). S-011 measured
all of it before changing any of it, asked him eight structured questions, and built what his answers
implied.

**Three commits, each verified on the simulator, 231 SPM tests green throughout.**

1. **`7736058` — the faded colour box behind every character.** Two independent causes, the same
   mistake: a soft glow cut square by a clip. The body halo was drawn `bodyR × 1.6` into a canvas
   `size × 1.0` wide, so it clipped on all four sides into a *coloured rectangle* — cyan behind
   Prism, red behind Ember, blue behind Bolt. Every large surface had already opted out via
   `haloScale: 0`, which left the halo drawn ONLY where it was guaranteed to clip; deleted rather
   than defaulted off. A fainter box remained around the hero's feet: `CharacterHeroStage` put
   `.clipped()` on the whole ZStack, so the stage ring's pool blur and rim shadow — which spill past
   the ring's frame *on purpose*, because that spill IS the glow — were cut square. The clip now sits
   on the mirrored reflection, the one child whose spill it always claimed to be trimming.

2. **`934b211` — the ladder and the moving walls.** D-023, D-024, D-025. Gates
   260/576/1,440/1,920/2,560 → **150/350/600/900/1,200 m**. Moving-wall swing on at all distances.
   `layoutVersion` **10 → 11**; goldens rederived in Python after the script reproduced all seven
   pre-existing pins, and the v11 value came out bit-identical to the pin S-010 pre-armed.
   **v12 pre-armed.**

3. **`0a5265d` — the economy.** D-026, D-027. A gem is no longer a coin; `styleCoins` uncapped and
   counting streaks; Coin Surge removed from the coin shop; the `×N` moved off the gem pill onto the
   score. Income cut 6.3–7.4×, style share 3% → 47–59%. **No spawn change** — `layoutVersion` stays
   at 11.

---

# Rayan's eight answers (S-011) — do not re-ask these

**On the Warden and the verbs:**
1. **It can never kill you.** A hit costs the multiplier, gems and a core-hit chance; it drops real
   obstacles that kill by the normal rules; failure = it escapes with your reward.
2. **Double tap = a blast, and CHARGE becomes its ammo.** Usable in any run, not just boss fights.
3. **The Warden throws real hazards** rather than firing instant beams.
4. **Obstacles before the Warden** — "you meet obstacles every 3 seconds and a Warden every 106."

**On the economy:**
5. **A mid-tier character should cost ~30–45 minutes** (cut the faucet ~6×, don't raise prices).
6. **Skill should pay much more** — uncap style, make near-misses and clean streaks the upside.
7. **Coin Surge becomes earned, never bought** — structurally, not by re-pricing.
8. **IAP should genuinely matter** — faucet, sinks and pack sizes tuned together.

---

# Things you would otherwise rediscover the hard way

- **Two of S-011's own leading hypotheses were REFUTED by its verifiers.** (a) *"The Warden's
  telegraph is too short"* — it is not. Measured usable input windows are 583–742 ms at every rank,
  and the repo's own `LaggedAutopilotTests` pins survival at 0.40 s of latency. The problem is what
  is DRAWN in that window, not its length. (b) *"The stumble is too rare or too quiet"* — neither; it
  fires on 25–45% of lethal-band contacts. Rayan had not seen it because **it shipped the day
  before, and every capture he reviews is autoplay — the Autopilot structurally cannot stumble**
  (measured: 1 in 120 perfect runs).
- **The red thing that covers the screen is three things** (`s011_warden_render.md` §7): the curtain
  (19.8% of the frame, erasing 100% of the track beyond 5.3 m), the floor (379 of its final 440 px
  appear in ONE frame), and — most literally — a red vignette that closes in from the frame edges for
  0.90 s *after* every hit, intensifying, named nowhere. A full-width opaque red band is on screen
  **91.7–95.2% of the exposed phase**; the dark gap between shapes is 100 ms.
- **`DifficultyCurveTests.seeds` are not independent.** They are `i × 0x9E3779B97F4A7C15 + offset` —
  the exact Weyl increment `SplitMix64.next()` adds every call — so the 64 "seeds" are 64 adjacent
  offsets into ONE master sequence. At shallow draw depth they have not decorrelated (a per-index
  histogram showed index 9 drawing **0 times in 1,596 eligible draws**). Every per-band statistic in
  that file is less independent than its seed count implies. SEV3; shipped behaviour unaffected.
- **A chasm met under a chrono has a misleading telegraph.** The hole is placed from the predicted
  RAMP speed while chrono moves the player at 0.65×, so the gem-arc cue points ~1.2 m early. Still
  clearable (0.30 s of slop). Pre-existing; D-023 makes it more reachable.
- **`PR_WARDEN=1` + `PR_AUTOPLAY=1` + `PR_SKIP_SPLASH=1`** drives a full Warden fight you can record.
  Prefer `simctl io recordVideo` + `ffmpeg` over repeated `simctl io screenshot` — screenshots stall
  the app into slow motion, video does not. Use OUTPUT seeking (`-i file -ss t -to u`), never input
  seeking; h264 keyframes are sparse and `-ss` before `-i` lands far off.
- **SourceKit in this checkout resolves against macOS.** `Theme` / `UIKit` / `RealityRenderer` /
  "has no member" errors are noise. Believe `./Tools/build.sh`.
- Never drive the simulator while `xcodebuild test` runs — concurrent installs crash the host.
  (`swift test` is macOS/SPM and never touches the simulator, so those two are safe together.)
- `state.md` (58 KB) and `README.md` (35 KB) at the repo root are history, not truth.

---

# Current state in one paragraph

Prism Rush is a v2.1 feature-complete iPhone game that has never been submitted: ~100 Swift files,
zero dependencies, zero binary assets but a generated icon, **231 SPM tests green**, and a genuinely
deterministic core behind a clean `RendererPort` seam. `DailyChallenge.layoutVersion` is **11** —
spent this session on the ladder and the moving-wall swing — and **v12 is pre-armed and unspent**.
The obstacle ladder and the coin faucet are both freshly measured and tuned. The blast and the Warden
rebuild are approved and unbuilt. `PR-0401` should be **amended, not closed**: a verifier refuted it
as written, because coins DO buy play-affecting things and cosmetics are only 29% of the fixed sink.

# Rayan action items (surface them; do not try to do them)

1. **PLAY THE NEW LADDER.** The chasm now arrives around 1,300 m / ~67 s instead of a median
   2,971 m / 125 s, and the moving walls are a real weave. Does the first minute keep giving you
   something new?
2. **PLAY THE STUMBLE.** Still never confirmed by a human. It is real; autoplay captures cannot
   show it.
3. **CHECK THE NEW COIN RATE.** A mid character is now ~31–34 min and the whole catalogue ~21 hours.
   If that feels slow, `Tuning.coinsPerGemDivisor` and `Tuning.styleCoinRate` are one edit each.
4. **The `Double Coins` IAP description in App Store Connect** — correct it to
   `Every run pays 2× coins. Forever.` before submission.
5. Carried: the slide SFX (S-006), act two, the hub redesign, per-world Warden species.

# Open questions for Rayan (carried until answered)

- **PR-0040** — the music is a 1.82 s loop for the whole session, pinned to world 0 by his decree.
- **PR-0010** — `Store/metadata.md` sells a three-world game; the binary ships twelve families.
- **PR-0254** — should a run that used a paid revive be leaderboard-eligible? S-003 recommends
  counting it for missions/XP but not the leaderboard. Needs a yes/no.
- **NEW: buying a deep world forfeits Game Center submission, reach credit and achievements**
  (`ProfileStore.swift:274-292`), so 71% of the coin catalogue makes runs count for LESS. Intended?
- **NEW: the Mystery Box is −19% EV** (242.7 expected against a 300 price). Decree 5 says no dark
  patterns; this is at least in tension with it.

# Resolved in session 011

The character-select colour box (two causes); the unlock ladder; the moving-wall exploit; the chasm's
reachability; an `Autopilot` chasm bug the ladder exposed; the coin faucet; the Coin Surge arbitrage;
and the `×5` HUD misread. Decisions **D-023…D-027**. `audits/AUDIT_011_ECONOMY.md` written and
committed. **Owner decisions implemented this session:** the ladder pulled forward, the moving-wall
swing made permanent, a gem separated from a coin, skill made the largest term in the faucet, and
Coin Surge made unbuyable.
