# HANDOFF → Session 013

## Paste this to start the next session

```
You are session 013 of a long-running program to finish and ship Prism Rush, a neon three-lane
endless runner for iPhone (Swift 6, SwiftUI, RealityKit, zero dependencies, zero binary assets).

Read docs/agent/01_RULES.md, then docs/agent/02_STATE.md, then this file.

You may and should change code. Rayan's standing instruction is "never be limited by arbitrary
rules, just work however you think is best." Do not ask permission to fix something you can verify.

Direction: App Store submission IS the goal, timing is open, and Rayan wants the app POLISHED first.
Design and feel outrank compliance right now. He also said, in S-011: "always plan extremely before
implementing" and "ask me questions if you need" — he answered eight structured questions there and
S-012 built three of the four things those answers implied. Do not re-ask them; they are recorded in
docs/agent/04_DECISIONS.md as D-023..D-031.

YOUR JOB. Item 1 is the whole session unless it goes faster than it should. It is the last of the
four things Rayan asked for in S-011 and the only one S-012 did not finish — and it is also the only
one that spends the layoutVersion bump, which is why it was left rather than rushed.

  1. OBSTACLE VARIETY AND SURPRISE — "the gameplay has been left stale."
     The ladder is fixed (S-011) and the boss is fixed (S-012). The CONTENT is still thin:
       - **SLIDE IS MANDATORY NOWHERE IN THE 15-PATTERN CATALOGUE.** Every bar in the game can be
         jumped (`Collisions.barHit` only kills between 0.95 and 1.65; a base jump clears it for
         0.434 s of an 0.815 s arc). A player who never swipes down can complete every pattern.
         **The fix is already built and shipped — you just have to place it.** S-012 added
         `EntityKind.hangingBar`: full-span, kill band 0.95 → 4.0, unjumpable from any state
         including Super Sneakers, cleared only by sliding, with a mesh that is exactly its kill
         band. It has a `SpawnCmd` case, a collision predicate, a graze rule, an Autopilot arm, a
         renderer mesh and a `capHangingBar`. **No pattern places one.** Putting it in the catalogue
         is the single highest-value change left in the game.
       - 3 of 15 patterns consume ZERO randomness and render identically every time (indices 2, 8,
         13); 10 of the remaining 12 vary by exactly one thing, WHICH OF THREE LANES; the whole game
         contains ~60 distinct arrangements.
       - The spawner draws a gem breadcrumb into the safe entry lane of every pattern, so the floor
         tells you the answer before you arrive. (D-006 kept this deliberately; the greed line past
         `riskGemsFrom` is the counterweight. Read it before changing it.)
     See docs/agent/audits/scratch/s011_research_obstacles.md for a master table of what shipped
     runners use, and s012_scout_spawn.md for the per-pattern RNG-draw table.

     THIS COSTS THE layoutVersion BUMP. Currently 11, v12 is pre-armed and unspent. Read iron rule 3
     in CLAUDE.md and follow it exactly: keep the 200-seed bot green (it asserts ZERO CONTACTS, not
     zero deaths), bump `DailyChallenge.layoutVersion`, and repin the goldens in BOTH
     `DailyChallengeTests` AND `MissionsTests.testTodaysChallengeSeedMatchesUTCGoldens`. Derive the
     goldens in Python from the SplitMix64 constants and reproduce the existing pins first.

  2. PER-WORLD WARDEN SPECIES — specified in s009c_SPEC.md §3, carried unbuilt since S-009. Much
     easier now than it was: a species is a different THROW TABLE (`WardenEncounter.script(rank:)`
     plus `Tuning.wardenThrowKind`), not a different attack system. Rayan asked for this directly.

  3. Whatever Rayan says when he plays it. Four things are new since he last looked and every one of
     them needs his thumbs — see "Rayan action items" below.

BEFORE YOU TRUST ANY NUMBER IN A SCRATCH FILE, check whether a verifier killed it. S-011 ran nine
hostile verifiers and refuted two of its own leading hypotheses. S-012 ran a hostile integration
reader that found three defects in code written thirty minutes earlier, and had two of its own
assumptions killed by measurement (a longer telegraph made the boss unloseable; a bigger shockwave
ring covered the read). A finding that survived a hostile reader is worth ten that did not.

FIRST COMMAND, before anything else. docs/agent/scratch/ and docs/agent/audits/scratch/ are
gitignored and hold ~700 MB from twelve sessions. Git does NOT move them between worktrees. No-op if
you already have them:

  for w in "" .claude/worktrees/prism-rush-spawn-path-c7d88a \
           .claude/worktrees/prism-rush-design-audit-562d27 \
           .claude/worktrees/prism-rush-audit-91c7ba; do
    s="/Users/rayankarimcheca/Desktop/ClaudeProjects/projects/prism-rush-ios/$w/docs/agent"
    [ -d "$s/scratch" ] && mkdir -p docs/agent/scratch && cp -Rn "$s/scratch/." docs/agent/scratch/ 2>/dev/null
    [ -d "$s/audits/scratch" ] && mkdir -p docs/agent/audits/scratch && cp -Rn "$s/audits/scratch/." docs/agent/audits/scratch/ 2>/dev/null
  done; du -sh docs/agent/scratch docs/agent/audits/scratch

If both are empty, say so in your report rather than working blind.

BUILD AND RUN THE APP BEFORE YOU CLAIM ANYTHING WORKS. Twelve for twelve. `swift test` compiles
Core/, seven Meta/ files and Audio/Synth.swift. It does NOT compile UI/, Render/, IAP/, StoreKit or
GameKit. S-012 shipped 254 green tests and still found, only by looking at the screen, that the
Warden hovered inside the vertical span of its own thrown hanging bar and spent every curtain throw
hidden behind its own attack.

Report back in three lines.
This file's absolute path: /Users/rayankarimcheca/Desktop/ClaudeProjects/projects/prism-rush-ios/HANDOFF.md
```

---

# What session 012 did

Three commits, each built and run on the simulator before it was claimed. **254 SPM tests green**
(was 231). `DailyChallenge.layoutVersion` is **still 11** and v12 is still pre-armed.

1. **`3b1cb21` — THE BLAST.** The game's first offensive verb, and Rayan's own idea. A double tap
   spends a third of the charge bank and destroys every destructible obstacle within 46 m. Tap 1
   still fires the jump on the frame it arrives — the double-tap window lies **entirely inside the
   span where a buffered jump is already discarded**, so the verb costs the player no latency at all.
   Charge is now ammo: `chargeFullGems` 520 → 240 and the HUD reads `⚡ BLAST ×2` instead of
   `CHARGE · 37%`. The chasm is immune by rule; a blast with no target is refused, not wasted; and
   the Autopilot never fires it, so the 200-seed proof still means "survivable by dodging".

2. **`ae68fc7` — THE WARDEN, rebuilt.** It has no attack of its own and no collision rule at all. It
   throws real obstacles — two `tall` walls / a `chasm` / a `hangingBar` — and the S-009 verb
   trichotomy survives one-for-one. **The three red bands are deleted from `WardenRig`.** A landed
   hazard costs the multiplier, the tempo, one blast round and the answer it would have been worth;
   miss enough and the clock runs out and it leaves with the bounty. The Autopilot LOST both its
   Warden-specific override blocks and needed nothing in return.

3. **`7871dd5` — the economy finished.** E6 and E7 of `AUDIT_011_ECONOMY` §3.

---

# Things you would otherwise rediscover the hard way

- **The blast does not change the track, and it is proven rather than argued.** With the player's
  route frozen, 8 seeds place byte-identical obstacles. Under a driven bot, kind and lane never
  differ and positional drift maxes at **0.0027 m — under half the 0.0063 m the shipped slow-mo
  deploy already causes** through the same D-021 mechanism. **The pool caps never bind** (peak live
  12/18, 10/14, 5/6, 2/6, 2/3 over 12,000 m), which is why freeing a slot cannot change spawning.
  All of this is pinned in `BlastTests`; if you widen `blastRange` past
  `spawnHorizon − cadenceClearance` it stops being true, and one test says so.
- **A longer telegraph made the boss unloseable.** The Warden's first build threw from 46 m and a bot
  reacting a full 0.75 s late took ZERO hits and killed 48 of 48. S-011 had already refuted "the
  telegraph is too short" — the window was never the problem, what was DRAWN in it was. 34 m is the
  shipped value and `LaggedAutopilotTests` is the gate that will catch you moving it.
- **`WardenEncounter.step` no longer takes the player's geometry** — no lane, x, body extent, jumpY,
  vy or grounded. A thrown hazard resolves in `stepObstacles` like every other obstacle. If you find
  yourself passing player state back into the encounter, you are rebuilding the thing that was wrong.
- **A `.lance` is TWO walls at one `d` and ONE answer.** `hasUnpassedThrownTwin` is what stops the
  Warden taking two hits for one dodge, and a hazard that lands on you removes the whole throw, so
  you cannot be hit by one wall and credited for the other.
- **Thrown hazards carry `fromWarden`, and that flag does three things**: they can only stagger
  (never kill), answering them damages the Warden, and the renderer paints them hazard red. The tint
  is not decoration — they follow a different rule from every other wall and the player has to be
  able to see whose they are.
- **`obstacleTrace`-style determinism probes must filter `!o.fromWarden`.** The Warden's throws are
  SUPPOSED to differ when the player behaves differently; only the spawner's output is pinned.
- **`GameCore.rebuildSnapshot()` runs once per RENDERED frame inside `advance(realDt:)`, never inside
  `tick(_:)`.** A test that steps the sim by hand and reads `core.snapshot` is reading the menu
  state. Read the core's own properties instead. This cost real time in S-012.
- **`PR_BLAST=1`** fires a blast every 1.6 s during autoplay so the verb can be captured;
  **`PR_WARDEN=1 PR_AUTOPLAY=1 PR_SKIP_SPLASH=1`** drives a full fight you can record. Prefer
  `simctl io recordVideo` + `ffmpeg` over repeated `simctl io screenshot` — screenshots stall the app
  into slow motion, video does not. Use OUTPUT seeking (`-i file -ss t`), never input seeking.
- **SourceKit in this checkout resolves against macOS.** `Theme` / `UIKit` / `RealityRenderer` /
  "has no member" errors are noise. Believe `./Tools/build.sh`.
- Never drive the simulator while `xcodebuild test` runs. (`swift test` is macOS/SPM and never
  touches the simulator, so those two are safe together.)
- `state.md` (58 KB) and `README.md` (35 KB) at the repo root are history, not truth.

---

# Current state in one paragraph

Prism Rush is a v2.2 feature-complete iPhone game that has never been submitted: ~100 Swift files,
zero dependencies, zero binary assets but a generated icon, **254 SPM tests green**, and a genuinely
deterministic core behind a clean `RendererPort` seam. `DailyChallenge.layoutVersion` is **11** and
**v12 is pre-armed and unspent** — the obstacle-variety work is what should spend it. The player now
has four verbs instead of three, the boss can no longer kill anybody and fights with the track's own
vocabulary, and the coin economy is measured end to end on both the faucet and the sink side. What is
left is CONTENT: the pattern catalogue is still 15 patterns, ~60 arrangements, and one verb it never
requires.

# Rayan action items (surface them; do not try to do them)

1. **PLAY A WARDEN.** This is the big one. It can no longer kill you, it throws walls and holes and
   hanging bars instead of red beams, and the three red bands are gone. Does the fight read? And does
   it still feel like a fight when it cannot kill you — is losing the bounty enough of a stake?
2. **DOUBLE TAP.** Jump, then tap again fast. Does the blast fire when you meant it to, and does
   spending a jump to fire it bother you? The window is 0.30 s and it is one constant.
3. **CHECK THE NEW BLAST ECONOMY.** 240 gems fills the bank and a blast is a third of it, so roughly
   80 gems a shot. Too precious, or too cheap? `Tuning.chargeFullGems` and `Tuning.blastCost`.
4. **THE CRAFT'S PRESENCE.** It moved from 19 m out to 34 m — it has to sit where its hazards appear
   or the throw is a lie — and `craftScale` went 1.70 → 2.55 to compensate. It is now *smallest* at
   full health and *largest* as it dies. Does that read as menacing, or as distant?
5. **PLAY THE STUMBLE.** Still never confirmed by a human, three sessions running. Autoplay captures
   structurally cannot show it — the Autopilot plays perfectly.
6. **The `Double Coins` IAP description in App Store Connect** — correct it to
   `Every run pays 2× coins. Forever.` before submission.
7. Carried: the slide SFX (S-006), a full audio pass (PR-0456), the hub redesign (PR-0452).

# Open questions for Rayan (carried until answered)

- **PR-0040** — the music is a 1.82 s loop for the whole session, pinned to world 0 by his decree.
- **PR-0010** — `Store/metadata.md` sells a three-world game; the binary ships twelve families.
- **PR-0254** — should a run that used a paid revive be leaderboard-eligible? S-003 recommends
  counting it for missions/XP but not the leaderboard. Needs a yes/no.
- **Buying a deep world forfeits Game Center submission, reach credit and achievements**
  (`ProfileStore.swift:274-292`), so 71% of the coin catalogue makes runs count for LESS. Intended?
- **NEW: THE BLAST HAS NO SOUND OF ITS OWN.** It reuses `.boostStart` and `.shieldBreak`. Nothing in
  this program can hear a sound, so a bespoke voice was not invented — the same call S-010 made for
  the stumble. It is the game's newest verb and the one most likely to feel weightless without one.

# Resolved in session 012

THE BLAST built and proven determinism-neutral; CHARGE turned into ammo with an honest HUD; the
Warden rebuilt so it can never kill and throws real hazards; the three red bands deleted; the
catalogue's first mandatory-slide obstacle created; the Mystery Box's −19% EV *and* its D-026
violation fixed by one edit; the level ladder cut from 1.6–2.2× the run faucet to 38–52%. Decisions
**D-028…D-031**. `PR-0458`, `PR-0459`, `PR-0460`.
