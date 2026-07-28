# HANDOFF → Session 006

## Paste this to start the next session

```
You are session 006 of a long-running program to finish and ship Prism Rush, a neon three-lane
endless runner for iPhone (Swift 6, SwiftUI, RealityKit, zero dependencies, zero binary assets).

Read docs/agent/01_RULES.md, then docs/agent/02_STATE.md, then this file. For your goal you will
also want docs/agent/03_BACKLOG.md PR-0450 and docs/agent/05_GAME_DESIGN.md §§3-4 (the mastery
ceiling argument, which is the reason PR-0450 exists).

You may and should change code. 01_RULES.md is split into judgment (advisory) and nine invariants
(damage prevention). Rayan's standing instruction is "never be limited by arbitrary rules, just
work however you think is best." Do not reinstate ceremony. Do not ask permission to fix something
you can verify.

Direction: App Store submission IS the goal, timing is open, and Rayan wants the app POLISHED
before publishing. Design and feel outrank compliance right now.

Your goal is PR-0450: the pattern catalogue is still 14. Session 004 built an act two that changes
how OFTEN you meet things; nothing new has been added to meet. A player who has read all 14
patterns has read them all, and every endgame structure in this game rests on distance staying an
axis of challenge. One genuinely new entity or verb, gated into a sixth tier, is the highest-value
work left.

This is the most invariant-heavy task in the program. Invariant 2 binds IN FULL and is the one that
looks like bureaucracy and isn't: the 200-seed solvability bot must stay green, DailyChallenge
.layoutVersion must go 8 -> 9, and the goldens must be repinned in TWO places (DailyChallengeTests
AND MissionsTests.testTodaysChallengeSeedMatchesUTCGoldens, which is easy to miss). Derive the
goldens in Python from the SplitMix64 formula — never read them off the code they pin. A v9 pin is
already pre-armed in DailyChallengeTests.

Build and RUN the app before you claim anything works. That rule is five for five at catching
things static reading missed. `swift test` green is NOT the app working — it compiles Core/, seven
Meta/ files and Audio/Synth.swift, and none of UI/, Render/, IAP/, StoreKit or GameKit.

FIRST COMMAND, before anything else. docs/agent/scratch/ and docs/agent/audits/scratch/ are
gitignored and hold ~8 MB of working detail from five sessions, including every hub screenshot
PR-0452 was argued and verified with. Git does NOT move them between worktrees. This copies them
from wherever they still exist and is a no-op if you already have them:

  for w in "" .claude/worktrees/prism-rush-spawn-path-c7d88a \
           .claude/worktrees/prism-rush-design-audit-562d27 \
           .claude/worktrees/prism-rush-audit-91c7ba; do
    s="/Users/rayankarimcheca/Desktop/ClaudeProjects/projects/prism-rush-ios/$w/docs/agent"
    [ -d "$s/scratch" ] && mkdir -p docs/agent/scratch && cp -Rn "$s/scratch/." docs/agent/scratch/ 2>/dev/null
    [ -d "$s/audits/scratch" ] && mkdir -p docs/agent/audits/scratch && cp -Rn "$s/audits/scratch/." docs/agent/audits/scratch/ 2>/dev/null
  done; du -sh docs/agent/scratch docs/agent/audits/scratch

Expect ~6.9M and ~1.2M. If both are empty, say so in your report rather than working blind.

Report back in three lines.
This file's absolute path: /Users/rayankarimcheca/Desktop/ClaudeProjects/projects/prism-rush-ios/HANDOFF.md
```

---

# Goal — PR-0450: the catalogue is still 14 patterns

**This is now the top item because both of Rayan's direct requests are delivered.** He asked for an
act two (S-004 built it) and a hub redesign (S-005 built it). Nothing is queued behind a standing
ask any more, so the backlog's own highest-value entry wins.

`docs/agent/03_BACKLOG.md` **PR-0450** carries the brief. The argument in one line, from
`05_GAME_DESIGN.md §4`:

> Past 1,920 m the player has seen every pattern the game will ever show them. v1.7 makes the
> demanding ones arrive more often and the breathers less often, and swings the moving walls — but
> **density is not novelty.**

S-004 filed this as the acknowledged residual of its own work and was right to. The whole endgame —
the infinite world ladder, the 13,400-coin deep rungs, the leaderboard, the 12,000 m soak — rests on
distance being an axis of *challenge*. Act two bought roughly 6,400 m more of that. It did not buy a
new *kind* of moment.

## What "one new thing" has to survive

The expensive part is not the idea, it is the proof. Budget for all of it:

- **New mesh** in `Render/Reality/` — procedural `MeshDescriptor`, `UnlitMaterial` only, pooled.
  Zero binary assets (invariant / decree).
- **New collision predicate** in `Core/Collisions.swift`, pure and testable.
- **New Autopilot policy** in `Core/Autopilot.swift`. The bot is greedy and reads only
  `activeObstacles`; if it cannot solve your entity, `SolvabilityBotTests` fails and it is telling
  you the truth — 200 seeds × 6,000 m plus the 12,000 m soak, zero deaths.
- **Pattern order is load-bearing** (iron rule 4): the spawner gates by prefix index and **moving
  walls stay LAST**. A sixth tier goes in at the right index or every gate shifts.
- **`layoutVersion` 8 → 9** and the goldens repinned in both homes (see the prompt above).
  Consuming one extra `rng.unit()` anywhere in the spawn path silently changes every seeded run for
  every player.
- **`DifficultyCurveTests` should show the new tier arriving as a step, not a slope.** That is the
  difference between "we added something" and "you can feel where it starts."

## Things S-004 paid for that you get free

- **Do not raise `speedCap`.** The readable lead is capped at ~65 m by the backdrop plane — 1.97 s
  at the cap. Pushing it back was tried and reverted in v1.6. Faster is unreactable, not harder.
  Receipt: `docs/agent/audits/scratch/verify-difficulty.md §12`.
- **Fixed-width measurement bands lie.** The mean pattern cycle is ~451 m; a 500 m band grid beats
  against it with a ~4.6 km period and manufactures a fake trend. The bands in
  `DifficultyCurveTests` are snapped to real pattern boundaries. Do not "simplify" that away.
- **The bot cannot certify anything involving gems** — it has never collected one.
  `testEveryGreedGemLeavesATakeableExit` is the separate proof and must stay green if you touch gem
  placement.

---

# If PR-0450 is too big for the session you have, or it stalls

All three are clean and nothing blocks them.

**PR-0254 + PR-0307 (decided in D-007, ~1 hour, fully specified).** A revived run counts fully for
missions and XP and is **not** leaderboard-eligible — the rule `usedCheckpoint` runs already follow.
Touches `recordRunResults` (`UI/GameView.swift:~680-792`). **Invariant 5 binds: keep the per-death
delta shape (`max(0, cumulative − awarded)`); do not reintroduce cumulative re-pays.** This was
S-005's named fallback and went unused.

**PR-0453, the rest of it (S-005 filed it, half-fixed it, and said so).** The character body glow is
drawn 1.6 × the canvas width and is therefore **hard-clipped into a faint rectangle**. S-005 fixed
the hub hero stage via `AnimatedCharacterSwatch.widthScale` (default 1.0 → every other call site
byte-identical). The 24-card grid, shop rows, NEXT UNLOCK strip and Mystery Box still carry it and
it is plainly visible on the characters screen — look at Ember's orange glow in
`docs/agent/scratch/s005/v3_characters.png`. Left open because those slots are sized to the swatch,
so widening the canvas is a four-screen layout change that had no business riding inside a hub diff.

**The Phase 3 failure-state sweep** is the other big coherent job (`02_STATE.md` worry #1): every
failure state in the app fails identically — raw, silent, or misleading. The good news is that the
correct pattern already exists in the codebase (the Worlds `UnlockPanel` and the revive offer both
show `NEED N MORE` plus a route to coins). Most of it is "use the pattern you already wrote."

---

# What changed in session 005 — read before touching the hub

**The hub was redesigned (PR-0452).** `RewardsBar.swift` is **deleted**; `ClaimRibbon.swift`
replaces it. The governing rule is *three species of surface*, and anything you add to the hub has
to pick one:

| Species | Means | Is |
|---|---|---|
| **Gradient** | the verb | PLAY, alone, at full screen width |
| **Cards** | objects you act on | claim ribbon, Daily Rush launcher, loadout chips |
| **Bare rail** | exits | Characters / Shop / Worlds / Missions — **no card chrome** |

The old 3-cell rail is gone because it mixed three different kinds of thing: **Daily Rush** is a way
to start a run (now a light 48 pt row directly under a full-width PLAY — it stood beside PLAY at
first and Rayan moved it: the primary verb should own the full width), **Rewards** is coins waiting
(now a full-width gold bar when
claimable, a slim strip when not), **Missions** is a board you visit (now a nav exit with a gold
count badge). The centre axis breaks on an editorial masthead — wordmark hard left, world dateline
hard right, identity and resources as two balanced clusters. Only the hero and PLAY stay centred.

Absorbed and closed: **PR-0134** (the `rewards:` AnyView is deleted, not genericised), **PR-0149**
(the stage takes its slot exactly — no floor, no cap), **PR-0150** (44 pt chip). **PR-0155 was
listed as absorbed but is not** — it is a `ProfileView` defect; the hub and `LevelSelectView` always
agreed.

**New launch hook: `PR_HUBDEEP=1`** pins a late-game profile (24,500 coins, best 128,400, 214 runs,
level 23, world 15 evolved, all claimables taken). Use it — a hub verified only at first launch is
not verified, and that is exactly how the old one survived so long. The before-shots proved it: a
player 214 runs in got a **pixel-identical** layout to first launch.

**Things you would otherwise rediscover the hard way:**

- **`.accessibilityElement(children: .ignore)` placement is load-bearing and cuts BOTH ways.**
  On the rail elements (`railRewards`, `railDaily`) it must land **BEFORE** the identifier and
  label, or the label is silently dropped — the element still exists and still taps, so **only a
  label assertion catches it**. On the nav exits it must **not be applied at all**, or they stop
  surfacing as `.button` and every `app.buttons["worldsButton"]` lookup fails.
  `InteractionUITests.swift:21-23` documents half of this. S-005 lost two suite runs to it.
- **Prism, the default character, shimmers through hues on its own 8 s clock** (`isPrismatic`). It
  is yellow in one screenshot and pink in the next **from the same build**. That is its fixed
  identity, explicitly annotated in `CharacterSwatch.swift` as *not* world-tracking, so it is not a
  decree-1 violation. Do not read it as a change between captures.
- **`unclaimedCount(now:)` is still called from inside a view `body`** — the hazard moved from
  `RewardsBar.swift:23` to `MenuView`'s `navRail` (inside a 60 s `TimelineView`). It did not go
  away. `07_ARCHITECTURE.md` was repointed.

---

# Traps (all still true, all have cost someone a session)

- **`swift test` green ≠ the app works.** It compiles `Core/`, seven `Meta/` files and
  `Audio/Synth.swift`. **Not** `UI/`, `Render/`, `IAP/`, `SynthEngine`, StoreKit or GameKit. Only
  `./Tools/build.sh` proves those.
- **Test counts elsewhere in this repo are stale.** Measured at S-005: **194 Xcode unit + 11
  XCUITest = 205**, and **187 SPM**. Trust `08_TESTING.md`.
- **`rm -f dir/*.png` aborts a zsh `&&` chain when nothing matches.** It silently killed S-004's
  first screenshot loop and the failure looked like "0 files captured". Do not suppress stderr on
  capture commands. S-005's capture script has no `|| true` anywhere, deliberately.
- **`PR_FIRSTRUN` does not reset the profile.** Only `simctl uninstall` gives a true first launch.
- **The splash never auto-dismisses.** Tap it, or launch with `PR_SKIP_SPLASH=1`.
- **`Tools/qa.sh` and `Tools/screenshots.sh` hardcode this machine's UDIDs and fail silently via
  `|| true`** (PR-0050). A green run may mean nothing ran.
- **Never drive the simulator while `xcodebuild test` runs on it** — concurrent installs crash the
  test host and report a false TEST FAILED.
- **SourceKit in this checkout resolves against macOS, not iOS**, so the editor shows a wall of
  "Cannot find 'Theme' in scope" / "only available in macOS 15.0" on files that compile fine.
  Ignore the diagnostics; believe `./Tools/build.sh`.
- `state.md` (58 KB) and `README.md` (35 KB) at the repo root are history, not truth. Where they
  disagree with `02_STATE.md`, `02_STATE.md` wins.
- `docs/agent/scratch/` and `docs/agent/audits/scratch/` are **gitignored**, ~8 MB, five sessions
  deep. **The prompt at the top of this file opens with a command that recovers them — run it.**
- Don't put `./Tools/build.sh` (~2 min) inside a fan-out. Build once, up front, in the background.

---

# Current state in one paragraph

Prism Rush is a v1.7, feature-complete, technically strong iPhone game that has never been submitted
to the App Store: ~95 Swift files, ~22,800 lines, zero dependencies, zero binary assets but a
generated icon, **205 Xcode tests and 187 SPM tests green**, and a genuinely deterministic core
behind a clean `RendererPort` seam. Session 001 built the agent memory system and filed 186 items
from static reading. Session 002 produced the Completeness Ledger: 50 of 59 user-facing features are
fully implemented and exactly one — account deletion — is outright absent, but only 13 of 59 clear
the owner's six decrees. Session 003 wrote the design bible and found the structural problem — the
game ran out of design at 3,200 m — then cut the program's process rules to nine real invariants.
Session 004 fixed that structural problem: there is now an act two out to 9,600 m and gems can cost
something. **Session 005 rebuilt the front door**: the hub is no longer six identical tiles under a
centred stack, and it no longer renders identically for a player 214 runs in and one who has never
pressed PLAY. Backlog is 260 items, 10 DONE. Five audits remain unrun; the phase gate is gone, so
fixes and audits interleave, and polish outranks compliance until Rayan says otherwise.

# Rayan action items (surface them; do not try to do them)

1. **The `Double Coins` in-app purchase description in App Store Connect.** ASC is Apple's web
   console (appstoreconnect.apple.com) — the listing, pricing, IAPs and submissions live there, not
   in this repo. Each IAP carries its own **Description** that Apple shows in the purchase sheet.
   **Careful with the framing: this app has never been submitted, so nothing is public.** Earlier
   handoffs called this a "live listing" — that was inherited and overstated, and S-005 corrected
   it. The accurate statement: *if* Rayan has already created `com.rayancheca.prismrush.doublecoins`
   in ASC with the old "Earn 2x coins, forever" wording, it must be corrected before submission,
   because the app no longer claims that (PR-0411 made the claim match the code). If he has not
   created it yet there is nothing to fix — `docs/APP_STORE_SETUP.md` and `docs/SHIP_CHECKLIST.md`
   both now carry the correct text to paste: **`Every run pays 2× coins. Forever.`**
   Either way only he can touch ASC.
2. **Does the new hub feel right?** He asked for the redesign without naming a direction, and an
   autonomous session cannot ask, so one was picked and documented (editorial/arcade, three species
   of surface). Screenshots at three profile states are in `docs/agent/scratch/s005/after_*.png` —
   but a hub is a thing you tap, not a picture. Specifically: does PLAY dominate enough? Does Daily
   Rush beside it read as "the other way to start", or as clutter? Does the bare nav rail read as
   navigation, or does it look unfinished next to the carded ribbon above it?
3. **Does act two feel right?** Verified deterministic, fair and measurably escalating, but
   "measurably escalating" and "fun" are different claims. Is the 3,200 m step noticeable? Do the
   swung moving walls past ~6,800 m read, or feel cheap? Can you *see* the two coin lines diverge in
   time to choose, at speed?
4. Optional, still open from S-003: PR-0411 was fixed by making the *claim* true. The alternative —
   making the *product* true by multiplying the five un-multiplied faucets — is a better deal for
   buyers and a real economy rebalance. His call.

# Open questions for Rayan (carried until answered; none block session 006)

- **PR-0040** — the music is a 1.82 s loop for the whole session, pinned to world 0 by his own
  decree (`SynthEngine.swift:133`). Long-form structure inside that constraint needs sign-off.
- **PR-0052** — is the Daily Challenge a layout guarantee or an identical-experience guarantee?
- **PR-0010** — `Store/metadata.md` sells a three-world game; the binary ships twelve families plus
  an infinite evolved cycle. Needs a ledger-checked rewrite before submission.

# Resolved in session 005

PR-0452 (the hub redesign) · PR-0134 · PR-0149 · PR-0150 · PR-0453 (hub instance only).
Filed: PR-0453. No new decisions — D-005 … D-008 all held up in practice.
